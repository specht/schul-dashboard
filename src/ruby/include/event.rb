EVENT_TRACK_ORDER = %w(schiene_1 schiene_2 schiene_3 schiene_sesb online)
EVENT_TRACKS = {
    'schiene_1'    => [ '9:15',  '9:30', '11:00', 'Schiene 1', 3],
    'schiene_2'    => ['10:45', '11:00', '12:30', 'Schiene 2', 3],
    'schiene_3'    => ['12:15', '12:30', '14:00', 'Schiene 3', 3],
    'schiene_sesb' => ['12:45', '13:00', '14:30', 'SESB-Schiene', 3],
    # 'schiene_4'    => ['13:45', '14:00', '15:30', 'Schiene 4', 3],
    'online'       => [    nil, '11:00', '12:30', 'Online-Schiene', 1000],
}
EVENT_NAME = 'Tag der Offenen Tür'

class Main < Sinatra::Base
    post '/api/save_event' do
        require_teacher!
        data = parse_request_data(:required_keys => [:title, :jitsi, :date, :start_time,
                                                     :end_time, :recipients, :description],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:description => 1024 * 1024})
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        event = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :jitsi => (data[:jitsi] == 'yes'), :date => data[:date], :start_time => data[:start_time], :end_time => data[:end_time], :description => data[:description])['e'].props
            MATCH (a:User {email: {session_email}})
            CREATE (e:Event {id: {id}, title: {title}, jitsi: {jitsi}, date: {date}, start_time: {start_time}, end_time: {end_time}, description: {description}})
            SET e.created = {timestamp}
            SET e.updated = {timestamp}
            CREATE (e)-[:ORGANIZED_BY]->(a)
            RETURN e;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:User)
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(e);
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(e);
        END_OF_QUERY
        # link external users (predefined)
        STDERR.puts data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) }.to_yaml
        temp = neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
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
        require_teacher!
        data = parse_request_data(:required_keys => [:eid, :title, :jitsi, :date, :start_time,
                                                    :end_time, :recipients, :description],
                                :types => {:recipients => Array},
                                :max_body_length => 1024 * 1024,
                                :max_string_length => 1024 * 1024,
                                :max_value_lengths => {:description => 1024 * 1024})

        id = data[:eid]
        STDERR.puts "Updating event #{id}"
        timestamp = Time.now.to_i
        event = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :jitsi => (data[:jitsi] == 'yes'), :date => data[:date], :start_time => data[:start_time], :end_time => data[:end_time], :recipients => data[:recipients], :description => data[:description])['e'].props
            MATCH (e:Event {id: {id}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            SET e.updated = {timestamp}
            SET e.title = {title}
            SET e.jitsi = {jitsi}
            SET e.date = {date}
            SET e.start_time = {start_time}
            SET e.end_time = {end_time}
            SET e.description = {description}
            WITH DISTINCT e
            OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
            SET r.deleted = true
            WITH DISTINCT e
            RETURN e;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:User)
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(e)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(e)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users (predefined)
        neo4j_query(<<~END_OF_QUERY, :eid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (e:Event {id: {eid}})
            WITH DISTINCT e
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
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
        require_teacher!
        data = parse_request_data(:required_keys => [:eid])
        id = data[:eid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(e:Event {id: {id}})
                SET e.updated = {timestamp}
                SET e.deleted = true
                WITH e
                OPTIONAL MATCH (r:User)-[rt:IS_PARTICIPANT]->(e)
                SET rt.updated = {timestamp}
                SET rt.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        trigger_update("_event_#{data[:eid]}")
        respond(:ok => true, :eid => data[:eid])
    end
    
    post '/api/get_external_invitations_for_event' do
        require_teacher!
        data = parse_request_data(:optional_keys => [:eid])
        id = data[:eid]
        invitations = {}
        invitation_requested = {}
        unless (id || '').empty?
            data = {:session_email => @session_user[:email], :id => id}
            temp = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:email => x['r.email'], :invitations => x['invitations'] || [], :invitation_requested => x['invitation_requested'] } }
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(e:Event {id: {id}})<-[rt:IS_PARTICIPANT]-(r)
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
            MATCH (u:User)<-[:ORGANIZED_BY]-(e:Event {id: {eid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            RETURN e, u.email;
        END_OF_QUERY
        event = temp['e'].props
        session_user = @@user_info[temp['u.email']][:display_last_name]
        code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + data[:eid] + data[:email]).to_i(16).to_s(36)[0, 8]
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
                io.puts "Datum und Uhrzeit: #{Time.parse(event[:date]).strftime('%d.%m.%Y')}, #{event[:start_time]} &ndash; #{event[:end_time]}<br />"
                link = WEB_ROOT + "/e/#{data[:eid]}/#{code}"
                io.puts "</p>"
                io.puts "<p>Link zum Termin:<br /><a href='#{link}'>#{link}</a></p>"
                io.puts "<p>Bitte geben Sie den Link nicht weiter. Er ist personalisiert und enthält Ihren Namen, den Raumnamen und ist nur am Tag des Termins gültig.</p>"
                io.puts event[:description]
                io.string
            end
        end
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, data)
            MATCH (e:Event {id: {eid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(e.deleted, false) = false
            SET rt.invitations = COALESCE(rt.invitations, []) + [{timestamp}]
            REMOVE rt.invitation_requested
        END_OF_QUERY
    end
    
    post '/api/invite_external_user_for_event' do
        require_teacher!
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
        require_teacher!
        data = parse_request_data(:required_keys => [:eid])
        id = data[:eid]
        STDERR.puts "Sending missing invitations for event #{id}"
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
            MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(e:Event {id: {id}})<-[rt:IS_PARTICIPANT]-(u)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND SIZE(COALESCE(rt.invitations, [])) = 0
            SET rt.invitation_requested = true;
        END_OF_QUERY
        trigger_send_invites()
        respond(:ok => true)
    end

    post '/api/sign_up_for_event' do
        data = parse_request_data(:required_keys => [:name, :email, :track])
        sign_ups = get_sign_ups_for_public_event(EVENT_NAME)
        if sign_ups[data[:track]]
            if sign_ups[data[:track]].size >= EVENT_TRACKS[data[:track]][4]
                respond(:error => 'track_already_booked_out')
                throw 'oh noes'
            end
        end

        tag = RandomTag.generate(12)
        STDERR.puts "Got sign up: #{data.to_json}"
        timestamp = DateTime.now.strftime('%Y-%m-%d %H:%M:%S')
        neo4j_query(<<~END_OF_QUERY, :name => data[:name], :email => data[:email], :track => data[:track], :timestamp => timestamp, :public_event_name => EVENT_NAME, :tag => tag)
            MERGE (e:PublicEvent {name: $public_event_name})
            CREATE (n:PublicEventPerson {tag: $tag, name: $name, email: $email, track: $track, timestamp: $timestamp})-[:SIGNED_UP_FOR]->(e)
        END_OF_QUERY
        deliver_mail do
            to data[:email]
            bcc SMTP_FROM
            from SMTP_FROM
            reply_to DASHBOARD_SUPPORT_EMAIL
            
            subject "Ihre Anmeldung zum Tag der Offenen Tür am 08.01.2022"

            event = EVENT_TRACKS[data[:track]]
            # 'schiene_1':    [ '9:15',  '9:30', '11:00', 'Schiene 1', 30],
            einlass = event[0]
            beginn = event[1]
            ende = event[2]
            titel = event[3]

            StringIO.open do |io|
                if data[:track] == 'online'
                    io.puts "<p>Sehr geehrte/r #{data[:name]}</p>"
                    io.puts "<p>vielen Dank für Ihre Anmeldung für die #{titel} am Tag der Offenen Tür. Die Veranstaltung findet am 08.01.2022 von #{beginn} bis #{ende} Uhr statt. Die Zugangsdaten für das Streaming erhalten Sie zeitnah zur Veranstaltung mit gesonderter Mail. Wir weisen darauf hin, dass es nicht erlaubt ist, Teile der Veranstaltung mitzuschneiden oder andere Formen der Aufzeichnung zu wählen.</p>"
                    io.puts "<p>Falls Sie Fragen haben, können Sie diese im Chat stellen; sie werden dann in der Veranstaltung live beantwortet.</p>"
                    io.puts "<p>Für einen kleinen Vorab-Eindruck empfehlen wir Ihnen unseren <a href='https://rundgang.gymnasiumsteglitz.de/'>virtuellen 360°-Grad-Rundgang</a>.</p>"
                    io.puts "<p>Mit freundlichen Grüßen</p>"
                else
                    io.puts "<p>Sehr geehrte/r #{data[:name]}</p>"
                    io.puts "<p>vielen Dank für Ihre Anmeldung für die #{titel} am Tag der Offenen Tür. Die Veranstaltung findet am 08.01.2022 von #{beginn} bis #{ende} Uhr statt. Der Einlass ist um #{einlass} Uhr am Haupteingang des Gymnasium Steglitz, Heesestraße 15. Wir bitten um Verständnis, dass wir bei Einlass den 2G-Status erwachsener Begleitpersonen überprüfen und Ihre Kontaktdaten (Name, Vorname, E-Mail-Adresse) für eine ggf. notwendige Kontaktnachverfolgung erheben. Die entsprechenden Listen werden nach vier Wochen vernichtet. Zur Überprüfung des Impfstatus bringen Sie bitte einen digital lesbaren Impfnachweis (QR-Code) sowie ein Ausweisdokument mit. Wir weisen darauf hin, dass wir ohne Nachweise in dieser Form keinen Zutritt gewähren können. Sollten Sie Symptome einer Coronaerkrankung aufweisen (Husten, Schnupfen, erhöhte Temperatur etc.) verzichten Sie bitte auf einen Besuch.</p>"
                    io.puts "<p>Wir weisen ferner darauf hin, dass während der gesamten Veranstaltung die Pflicht zum Tragen einer FFP2-Maske besteht. Wir bitten Sie darum, uns zu benachrichtigen, falls Sie nicht an dem gebuchten Termin teilnehmen können, damit wir den Platz neu vergeben können.</p>"
                    io.puts "<p>Für einen kleinen Vorab-Eindruck empfehlen wir Ihnen unseren <a href='https://rundgang.gymnasiumsteglitz.de/'>virtuellen 360°-Grad-Rundgang</a>.</p>"
                    io.puts "<p>Mit freundlichen Grüßen</p>"
                end
                io.string
            end
        end
        respond(:ok => true)
    end

    post '/api/delete_sign_up_for_event' do
        data = parse_request_data(:required_keys => [:tag])
        neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (n:PublicEventPerson {tag: $tag}) DETACH DELETE n;
        END_OF_QUERY
        respond(:ok => true)
    end

    def get_sign_ups_for_public_event(event_name)
        entries = neo4j_query(<<~END_OF_QUERY, :public_event_name => event_name).map { |x| x['n'].props }
            MATCH (n:PublicEventPerson)-[:SIGNED_UP_FOR]->(e:PublicEvent {name: $public_event_name})
            RETURN n
            ORDER BY n.timestamp ASC;
        END_OF_QUERY
        result = {}
        entries.each do |entry|
            result[entry[:track]] ||= []
            result[entry[:track]] << entry
        end
        result
    end

    def public_events_table()
        require_teacher!
        StringIO.open do |io|
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-12'>"
            public_event_names = neo4j_query(<<~END_OF_QUERY).map { |x| x['n.name'] }
                MATCH (n:PublicEvent)
                RETURN n.name;
            END_OF_QUERY
            public_event_names.each do |public_event_name|
                io.puts "<h3>#{public_event_name}</h3>"

                sign_ups = get_sign_ups_for_public_event(EVENT_NAME)

                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
                io.puts "<table class='klassen_table table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
                wrote_something = false
                EVENT_TRACK_ORDER.each do |track|
                    next unless sign_ups[track]
                    if wrote_something
                        io.puts "<tr><td colspan='5' style='background-color: white;'></td></tr>"
                    end
                    wrote_something = true
                    io.puts "<thead>"
                    io.puts "<tr>"
                    io.puts "<th>Schiene</th>"
                    io.puts "<th>Nr.</th>"
                    io.puts "<th>Anmeldung</th>"
                    io.puts "<th>Name</th>"
                    io.puts "<th>E-Mail-Adresse</th>"
                    io.puts "<th>Löschen</th>"
                    io.puts "</tr>"
                    io.puts "</thead>"
                    io.puts "<tbody>"
                        sign_ups[track].each.with_index do |row, index|
                        io.puts "<tr class='user_row'>"
                        io.puts "<td>#{EVENT_TRACKS[track][3]}</td>"
                        io.puts "<td>#{index + 1}.</td>"
                        io.puts "<td>#{row[:timestamp][0, 10]}</td>"
                        io.puts "<td>#{row[:name]}</td>"
                        io.puts "<td>"
                        print_email_field(io, row[:email])
                        io.puts "</td>"
                        io.puts "<td><button data-tag='#{row[:tag]}' class='bu-delete btn btn-sm btn-danger'><i class='fa fa-trash'></i>&nbsp;&nbsp;Löschen</button></td>"
                        io.puts "</tr>"
                    end
                    io.puts "</tbody>"
                end
                io.puts "</table>"
                io.puts "</div>"
            end
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    def print_public_event_table()
        sign_ups = get_sign_ups_for_public_event(EVENT_NAME)
        StringIO.open do |io|
            io.puts "<tr>"
            io.puts "<th></th>"
            EVENT_TRACK_ORDER.each do |track|
                info = EVENT_TRACKS[track]
                titel = info[3]
                io.puts "<th>#{titel}</th>"
            end
            io.puts "</tr>"

            io.puts "<tr>"
            io.puts "<th>Einlass</th>"
            EVENT_TRACK_ORDER.each do |track|
                info = EVENT_TRACKS[track]
                einlass = info[0]
                einlass = "#{einlass} Uhr" if einlass
                einlass ||= '&ndash;'
                io.puts "<td>#{einlass}</td>"
            end
            io.puts "</tr>"

            io.puts "<tr>"
            io.puts "<th>Veranstaltung</th>"
            EVENT_TRACK_ORDER.each do |track|
                info = EVENT_TRACKS[track]
                beginn = info[1]
                ende = info[2]
                io.puts "<td>#{beginn} &ndash; #{ende} Uhr</td>"
            end
            io.puts "</tr>"

            io.puts "<tr>"
            io.puts "<th></th>"
            EVENT_TRACK_ORDER.each do |track|
                if (sign_ups[track] || []).size >= EVENT_TRACKS[track][4]
                    io.puts "<td><button class='btn btn-outline-secondary' disabled>ausgebucht</button></td>"
                else
                    io.puts "<td><button data-track='#{track}' class='bu-track btn btn-outline-info'>auswählen</button></td>"
                end
            end
            io.puts "</tr>"
            io.string
       end 
    end
end
