class Main < Sinatra::Base
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
            
            subject "Ihre Anmeldung zur Info-Veranstaltung für Viertklässlereltern am 22.11.2022"

            event = EVENT_TRACKS[data[:track]]
            einlass = event[0]
            beginn = event[1]
            ende = event[2]
            titel = event[3]

            StringIO.open do |io|
                if data[:track] == 'online'
                    io.puts "<p>Sehr geehrte/r #{data[:name]},</p>"
                    io.puts "<p>vielen Dank für Ihre Anmeldung. Die Veranstaltung findet am 22.11.2022 von #{beginn} Uhr bis ca. #{ende} Uhr statt. Die Zugangsdaten für das Streaming erhalten Sie zeitnah zur Veranstaltung mit gesonderter Mail.</p>"
                    io.puts "<p>Falls Sie Fragen haben, können Sie diese im Chat stellen; sie werden dann in der Veranstaltung live beantwortet.</p>"
                    io.puts "<p>Für einen kleinen Vorab-Eindruck empfehlen wir Ihnen unseren <a href='https://rundgang.gymnasiumsteglitz.de/'>virtuellen 360°-Grad-Rundgang</a>.</p>"
                    io.puts "<p>Mit freundlichen Grüßen<br />Antje Lükemann</p>"
                else
                    io.puts "<p>Sehr geehrte/r #{data[:name]},</p>"
                    io.puts "<p>vielen Dank für Ihre Anmeldung. Die Veranstaltung findet am 22.11.2022 von #{beginn} Uhr bis ca. #{ende} Uhr statt. Der Einlass ist ab #{einlass} Uhr am Haupteingang des Gymnasium Steglitz, Heesestraße 15. Um möglichst vielen Familien die Teilnahme zu ermöglichen, bitten wir darum, dass in der Regel nur eine Person pro Familie an der Veranstaltung teilnimmt. Sollten Sie Symptome einer Coronaerkrankung aufweisen (Husten, Schnupfen, erhöhte Temperatur etc.) verzichten Sie bitte auf einen Besuch."
                    io.puts "<p>Wir weisen ferner darauf hin, dass voraussichtlich während der gesamten Veranstaltung die Pflicht zum Tragen einer FFP2-Maske besteht. Wir bitten Sie darum, uns zu benachrichtigen, falls Sie nicht an dem gebuchten Termin teilnehmen können, damit wir den Platz neu vergeben können.</p>"
                    io.puts "<p>Für einen kleinen Vorab-Eindruck empfehlen wir Ihnen unseren <a href='https://rundgang.gymnasiumsteglitz.de/'>virtuellen 360°-Grad-Rundgang</a>.</p>"
                    io.puts "<p>Mit freundlichen Grüßen<br />Antje Lükemann</p>"
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
        entries = neo4j_query(<<~END_OF_QUERY, :public_event_name => event_name).map { |x| x['n'] }
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
        self.class.refresh_public_event_config()
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

                wrote_something = false
                EVENT_TRACK_ORDER.each do |track|
                    next unless sign_ups[track]
                    io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
                    io.puts "<table class='klassen_table table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
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
                    io.puts "</table>"
                    io.puts "<textarea class='form-control' readonly>"
                    all_emails = []
                    sign_ups[track].each do |row|
                        all_emails << "#{row[:name]} <#{row[:email]}>"
                    end
                    io.puts all_emails.uniq.join("\n")
                    io.puts "</textarea>"
                end
                io.puts "</div>"
            end
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    def print_public_event_table()
        self.class.refresh_public_event_config()
        # sign_ups = get_sign_ups_for_public_event(EVENT_NAME)
        StringIO.open do |io|
            @@public_event_config.each.with_index do |event, event_index|
                if event_index > 0
                    io.puts "<hr />"
                end
                io.puts "<h3>#{event[:title]}</h3>"
                if event[:description]
                    io.puts event[:description]
                end
                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
                io.puts "<div style='display: none;' class='event-title'>#{event[:title]}</div>"
                io.puts "<table class='table table-narrow narrow'>"
                io.puts "<tbody>"
                if event[:headings]
                    io.puts "<tr>"
                    io.puts "<th>#{event[:headings][0]}</th>"
                    io.puts "<th colspan='#{event[:rows].max { |x| x[:entries].size }}'>#{event[:headings][1]}</th>"
                    io.puts "</tr>"
                end
                event[:rows].each do |row|
                    io.puts "<tr>"
                    io.puts "<th style='width: 180px;'>#{row[:description]}</th>"
                    row[:entries].each do |entry|
                        text = (event[:booking_text] || '').dup
                        while true
                            index = text.index('{')
                            break if index.nil?
                            length = 1
                            balance = 1
                            while index + length < text.size && balance > 0
                                c = text[index + length]
                                balance -= 1 if c == '}'
                                balance += 1 if c == '{'
                                length += 1
                            end
                            code = text[index + 1, length - 2]
                            begin
                                text[index, length] = eval(code).to_s || ''
                            rescue
                                debug "Error while evaluating for #{(@session_user || {})[:email]}:"
                                debug code
                                raise
                            end
                        end
                        io.puts "<td><button data-event-key='#{event[:key]}' data-key='#{entry[:key]}' class='btn btn-outline-success bu-book-public-event'>#{entry[:description]}</button><div style='display: none;' class='booking-text'>#{text}</div></td>"
                    end
                    io.puts "</tr>"
                end
                io.puts "</tbody>"
                io.puts "</table>"
                io.puts "</div>"
            end
            # io.puts "<tr>"
            # io.puts "<th></th>"
            # EVENT_TRACK_ORDER.each do |track|
            #     info = EVENT_TRACKS[track]
            #     titel = info[3]
            #     io.puts "<th>#{titel}</th>"
            # end
            # io.puts "</tr>"

            # io.puts "<tr>"
            # io.puts "<th>Einlass</th>"
            # EVENT_TRACK_ORDER.each do |track|
            #     info = EVENT_TRACKS[track]
            #     einlass = info[0]
            #     einlass = "#{einlass} Uhr" if einlass
            #     einlass ||= '&ndash;'
            #     io.puts "<td>#{einlass}</td>"
            # end
            # io.puts "</tr>"

            # io.puts "<tr>"
            # io.puts "<th>Veranstaltung</th>"
            # EVENT_TRACK_ORDER.each do |track|
            #     info = EVENT_TRACKS[track]
            #     beginn = info[1]
            #     ende = info[2]
            #     io.puts "<td>#{beginn} &ndash; #{ende} Uhr</td>"
            # end
            # io.puts "</tr>"

            # io.puts "<tr>"
            # io.puts "<th></th>"
            # EVENT_TRACK_ORDER.each do |track|
            #     if (sign_ups[track] || []).size >= EVENT_TRACKS[track][4]
            #         io.puts "<td><button class='btn btn-outline-secondary' disabled>ausgebucht</button></td>"
            #     else
            #         io.puts "<td><button data-track='#{track}' style='width: 8em;' class='bu-track btn btn-outline-info'>auswählen</button></td>"
            #     end
            # end
            # io.puts "</tr>"
            io.string
        end
    end

    def self.refresh_public_event_config()
        @@public_event_config_timestamp ||= 0
        path = '/data/public_events/public_events.yaml'
        if @@public_event_config_timestamp < File.mtime(path).to_i
            debug "Reloading public event config from #{path}!"
            @@public_event_config = YAML.load(File.read(path))
            @@public_event_config_timestamp = File.mtime(path).to_i
        end
    end
end