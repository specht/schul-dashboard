class Main < Sinatra::Base
    # The events someone organizes, as /events lists them (newest first, with
    # their participants). Without a period: all of them – exactly the query
    # /events has always used. Optional: from (inclusive) and to (exclusive)
    # as 'YYYY-MM-DD', or a single event by its id. Anchored at the organizer
    # (User/email is unique), so no index is needed for the period.
    def organized_events(email, from = nil, to = nil, eid = nil)
        rows = if from.nil? && to.nil? && eid.nil?
            neo4j_query(<<~END_OF_QUERY, :email => email)
                MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User {email: $email})
                WHERE COALESCE(e.deleted, false) = false
                WITH e
                OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
                WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                RETURN e, u.email
                ORDER BY e.date DESC, e.start_time DESC, e.id;
            END_OF_QUERY
        elsif eid
            neo4j_query(<<~END_OF_QUERY, :email => email, :eid => eid)
                MATCH (e:Event {id: $eid})-[:ORGANIZED_BY]->(ou:User {email: $email})
                WHERE COALESCE(e.deleted, false) = false
                WITH e
                OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
                WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                RETURN e, u.email
                ORDER BY e.date DESC, e.start_time DESC, e.id;
            END_OF_QUERY
        else
            neo4j_query(<<~END_OF_QUERY, :email => email, :from => from || '', :to => to || '9999-12-31')
                MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User {email: $email})
                WHERE COALESCE(e.deleted, false) = false AND e.date >= $from AND e.date < $to
                WITH e
                OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
                WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                RETURN e, u.email
                ORDER BY e.date DESC, e.start_time DESC, e.id;
            END_OF_QUERY
        end
        stored_events = rows.map { |x| {:info => x['e'], :recipient => x['u.email']} }
        temp = {}
        temp_order = []
        stored_events.each do |x|
            unless temp[x[:info][:id]]
                t = Time.parse(x[:info][:date])
                temp[x[:info][:id]] = {
                    :recipients => [],
                    :eid => x[:info][:id],
                    :info => x[:info],
                    :dow => t.wday
                }
                temp_order << x[:info][:id]
            end
            temp[x[:info][:id]][:recipients] << x[:recipient]
        end
        temp_order.map do |x|
            e = temp[x]
            e[:info][:start_time] = fix_h_to_hh(e[:info][:start_time])
            e[:info][:end_time] = fix_h_to_hh(e[:info][:end_time])
            e
        end
    end

    # Neues Design: /events shows what is coming and the last four weeks
    # first; everything older is loaded by school year (1 August to 31 July).
    EVENTS_RECENT_DAYS = 28

    def events_recent_from
        (Date.today - EVENTS_RECENT_DAYS).strftime('%Y-%m-%d')
    end

    # the older events per school year (its first year), newest first:
    # [{:school_year => 2024, :count => 37}, …]
    def organized_events_archive_years(email, before)
        counts = Hash.new(0)
        neo4j_query(<<~END_OF_QUERY, :email => email, :before => before).each do |row|
            MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User {email: $email})
            WHERE COALESCE(e.deleted, false) = false AND e.date < $before
            RETURN substring(e.date, 0, 7) AS month, COUNT(e) AS n;
        END_OF_QUERY
            year, month = row['month'].to_s.split('-').map { |x| x.to_i }
            next if year.nil? || month.nil? || year == 0
            counts[month >= 8 ? year : year - 1] += row['n']
        end
        counts.keys.sort.reverse.map { |y| {:school_year => y, :count => counts[y]} }
    end

    # the script line /events adds for the new design ('' otherwise, so that
    # the page stays exactly as it was)
    def events_preview_js(archive)
        return '' if archive.nil?
        "\nvar pv_events_archive = #{archive.to_json};\nvar pv_events_recent_from = #{events_recent_from.to_json};"
    end

    # the new design's part of /events (preview/events.js), only for those
    # who see it
    def events_preview_script(archive)
        return '' if archive.nil?
        "\n<script src='#{preview_asset('/preview/events.js')}'></script>"
    end

    # Neues Design: older events of one school year (or one event by its id,
    # for /events#eid) – read-only, the same events /events would show the
    # organizer for that period, nobody else's.
    post '/api/get_events_archive' do
        assert(user_with_role_logged_in?(:can_create_events))
        data = parse_request_data(:optional_keys => [:school_year, :eid],
                                  :types => {:school_year => Integer},
                                  :max_value_lengths => {:eid => 64})
        if data[:eid]
            events = organized_events(@session_user[:email], nil, nil, data[:eid])
        else
            year = data[:school_year]
            assert(year.is_a?(Integer) && year >= 2000 && year <= 2100)
            events = organized_events(@session_user[:email], "#{year}-08-01", "#{year + 1}-08-01")
        end
        respond(:events => events)
    end

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
