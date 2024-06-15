class Main < Sinatra::Base
    post '/api/save_event' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:required_keys => [:title, :jitsi, :date, :start_time,
                                                     :end_time, :recipients, :description],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:description => 1024 * 1024})
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        event = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :jitsi => (data[:jitsi] == 'yes'), :date => data[:date], :start_time => data[:start_time], :end_time => data[:end_time], :description => data[:description])['e']
            MATCH (a:User {email: $session_email})
            CREATE (e:Event {id: $id, title: $title, jitsi: $jitsi, date: $date, start_time: $start_time, end_time: $end_time, description: $description})
            SET e.created = $timestamp
            SET e.updated = $timestamp
            CREATE (e)-[:ORGANIZED_BY]->(a)
            RETURN e;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:User)
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PARTICIPANT]->(e);
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:ExternalUser {entered_by: $session_email})
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PARTICIPANT]->(e);
        END_OF_QUERY
        # link external users (predefined)
        STDERR.puts data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) }.to_yaml
        temp = neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PARTICIPANT]->(e);
        END_OF_QUERY
        STDERR.puts temp.to_yaml
        t = Time.parse(event[:date])
        event = {
            :eid => event[:id], 
            :dow => t.wday,
            :info => event,
            :recipients => data[:recipients],
        }
        # update timetable for affected users
        trigger_update("_event_#{event[:eid]}")
        respond(:ok => true, :event => event)
    end
    
    post '/api/update_event' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:required_keys => [:eid, :title, :jitsi, :date, :start_time,
                                                    :end_time, :recipients, :description],
                                :types => {:recipients => Array},
                                :max_body_length => 1024 * 1024,
                                :max_string_length => 1024 * 1024,
                                :max_value_lengths => {:description => 1024 * 1024})

        id = data[:eid]
        STDERR.puts "Updating event #{id}"
        timestamp = Time.now.to_i
        event = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :jitsi => (data[:jitsi] == 'yes'), :date => data[:date], :start_time => data[:start_time], :end_time => data[:end_time], :recipients => data[:recipients], :description => data[:description])['e']
            MATCH (e:Event {id: $id})-[:ORGANIZED_BY]->(a:User {email: $session_email})
            SET e.updated = $timestamp
            SET e.title = $title
            SET e.jitsi = $jitsi
            SET e.date = $date
            SET e.start_time = $start_time
            SET e.end_time = $end_time
            SET e.description = $description
            WITH DISTINCT e
            OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
            SET r.deleted = true
            WITH DISTINCT e
            RETURN e;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:User)
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PARTICIPANT]->(e)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:ExternalUser {entered_by: $session_email})
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PARTICIPANT]->(e)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users (predefined)
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (e:Event {id: $eid})
            WITH DISTINCT e
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PARTICIPANT]->(e)
            REMOVE r.deleted
        END_OF_QUERY
        t = Time.parse(event[:date])
        event = {
            :eid => event[:id], 
            :dow => t.wday,
            :info => event,
            :recipients => data[:recipients]
        }
        # update timetable for affected users
        trigger_update("_event_#{event[:eid]}")
        respond(:ok => true, :event => event, :eid => event[:eid])
    end
    
    post '/api/delete_event' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:required_keys => [:eid])
        id = data[:eid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: $session_email})<-[:ORGANIZED_BY]-(e:Event {id: $id})
                SET e.updated = $timestamp
                SET e.deleted = true
                WITH e
                OPTIONAL MATCH (r:User)-[rt:IS_PARTICIPANT]->(e)
                SET rt.updated = $timestamp
                SET rt.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        trigger_update("_event_#{data[:eid]}")
        respond(:ok => true, :eid => data[:eid])
    end
    
    post '/api/get_external_invitations_for_event' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:optional_keys => [:eid])
        id = data[:eid]
        invitations = {}
        invitation_requested = {}
        unless (id || '').empty?
            data = {:session_email => @session_user[:email], :id => id}
            temp = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:email => x['r.email'], :invitations => x['invitations'] || [], :invitation_requested => x['invitation_requested'] } }
                MATCH (a:User {email: $session_email})<-[:ORGANIZED_BY]-(e:Event {id: $id})<-[rt:IS_PARTICIPANT]-(r)
                WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND COALESCE(rt.deleted, false) = false
                RETURN r.email, COALESCE(rt.invitations, []) AS invitations, COALESCE(rt.invitation_requested, false) AS invitation_requested;
            END_OF_QUERY
            temp.each do |entry|
                invitations[entry[:email]] = entry[:invitations].map do |x|
                    Time.at(x).strftime('%d.%m.%Y %H:%M:%S')
                end
                invitation_requested[entry[:email]] = entry[:invitation_requested]
            end
        end
        respond(:invitations => invitations, :invitation_requested => invitation_requested)
    end
    
    def self.invite_external_user_for_event(eid, email, session_user_email)
        STDERR.puts "Sending invitation mail for event #{eid} to #{email}"
        timestamp = Time.now.to_i
        data = {}
        data[:eid] = eid
        data[:email] = email
        data[:timestamp] = timestamp
        event = nil
        # TODO: There is a potential bug here when someone adds a PredefinedExternalUser
        # as a recipient and there will be two results here where we would have expected
        # one before
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY, data).first
            MATCH (u:User)<-[:ORGANIZED_BY]-(e:Event {id: $eid})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = $email) AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            RETURN e, u.email;
        END_OF_QUERY
        event = temp['e']
        session_user = @@user_info[temp['u.email']][:display_last_name]
        code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + data[:eid] + data[:email]).to_i(16).to_s(36)[0, 8]
        # remove invitation request / if something goes wrong, we won't keep sending out invites blocking the queue
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, data)
            MATCH (e:Event {id: $eid})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = $email) AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            REMOVE rt.invitation_requested;
        END_OF_QUERY
        begin
            deliver_mail do
                to data[:email]
                bcc SMTP_FROM
                from SMTP_FROM
                reply_to "#{@@user_info[session_user_email][:display_name]} <#{session_user_email}>"
                
                subject "Einladung: #{event[:title]}"

                StringIO.open do |io|
                    io.puts "<p>Sie haben eine Einladung zu einem Termin via Jitsi Meet erhalten.</p>"
                    io.puts "<p>"
                    io.puts "Eingeladen von: #{session_user}<br />"
                    io.puts "Titel: #{event[:title]}<br />"
                    io.puts "Datum und Uhrzeit: #{WEEKDAYS[Time.parse(event[:date]).wday]}., den #{Time.parse(event[:date]).strftime('%d.%m.%Y')}, #{event[:start_time]} &ndash; #{event[:end_time]}<br />"
                    link = WEB_ROOT + "/e/#{data[:eid]}/#{code}"
                    io.puts "</p>"
                    io.puts "<p>Link zum Termin:<br /><a href='#{link}'>#{link}</a></p>"
                    io.puts "<p>Bitte geben Sie den Link nicht weiter. Er ist personalisiert und enthält Ihren Namen, den Raumnamen und ist nur am Tag des Termins gültig.</p>"
                    io.puts event[:description]
                    io.string
                end
            end
        rescue
            deliver_mail do
                to session_user_email
                bcc SMTP_FROM
                from SMTP_FROM
                
                subject "Einladung konnte nicht versendet werden: #{event[:title]}"

                StringIO.open do |io|
                    io.puts "<p>Die Einladung für den folgenden Termin konnte nicht versendet werden:</p>"
                    io.puts "<p>"
                    io.puts "E-Mail: #{data[:email]}<br />"
                    io.puts "Titel: #{event[:title]}<br />"
                    io.puts "Datum und Uhrzeit: #{WEEKDAYS[Time.parse(event[:date]).wday]}., den #{Time.parse(event[:date]).strftime('%d.%m.%Y')}, #{event[:start_time]} &ndash; #{event[:end_time]}<br />"
                    link = WEB_ROOT + "/e/#{data[:eid]}/#{code}"
                    io.puts "</p>"
                    io.puts "<p>Link zum Termin:<br /><a href='#{link}'>#{link}</a></p>"
                    io.puts "<p>Bitte überprüfen Sie die E-Mail-Adresse, sie ist vermutlich falsch.</p>"
                    io.string
                end
            end
        end
        # add timestamp to list of successfully sent invitations
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, data)
            MATCH (e:Event {id: $eid})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = $email) AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            SET rt.invitations = COALESCE(rt.invitations, []) + [$timestamp];
        END_OF_QUERY
    end
    
    post '/api/invite_external_user_for_event' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:required_keys => [:eid, :email])
        self.class.invite_external_user_for_event(data[:eid], data[:email], @session_user[:email])
        respond({})
    end
    
    get '/e/:eid/:code' do
        eid = params[:eid]
        code = params[:code]
        redirect "#{WEB_ROOT}/jitsi/event/#{eid}/#{code}", 302
    end
    
    post '/api/send_missing_event_invitations' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:required_keys => [:eid])
        id = data[:eid]
        STDERR.puts "Sending missing invitations for event #{id}"
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
            MATCH (a:User {email: $session_email})<-[:ORGANIZED_BY]-(e:Event {id: $id})<-[rt:IS_PARTICIPANT]-(u)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND SIZE(COALESCE(rt.invitations, [])) = 0
            SET rt.invitation_requested = true;
        END_OF_QUERY
        trigger_send_invites()
        respond(:ok => true)
    end
end
