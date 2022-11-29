class Main < Sinatra::Base
    post '/api/sign_up_for_public_event' do
        data = parse_request_data(:required_keys => [:event_key, :entry_key, :name, :email])
        event = @@public_event_config.select { |x| x[:key] == data[:event_key] }.first
        assert(!event.nil?)
        track = "#{data[:event_key]}/#{data[:entry_key]}"
        row = nil
        entry = nil
        event[:rows].each do |_row|
            _row[:entries].each do |_entry|
                if _entry[:key] == data[:entry_key]
                    row = _row
                    entry = _entry
                end
            end
        end
        assert(!row.nil?)
        assert(!entry.nil?)

        sign_ups = get_sign_ups_for_public_event(data[:event_key])
        if sign_ups[data[:entry_key]]
            if sign_ups[data[:entry_key]].size >= (entry[:capacity] || 0)
                respond(:error => 'track_already_booked_out')
                throw 'oh noes'
            end
        end

        tag = RandomTag.generate(12)
        STDERR.puts "Got sign up: #{data.to_json}"
        timestamp = DateTime.now.strftime('%Y-%m-%d %H:%M:%S')
        neo4j_query(<<~END_OF_QUERY, :name => data[:name], :email => data[:email], :track => track, :timestamp => timestamp, :tag => tag)
            MERGE (t:PublicEventTrack {track: $track})
            CREATE (p:PublicEventPerson {tag: $tag, name: $name, email: $email, timestamp: $timestamp})-[:SIGNED_UP_FOR]->(t)
        END_OF_QUERY
        name = data[:name]
        deliver_mail do
            to data[:email]
            bcc SMTP_FROM
            from SMTP_FROM
            reply_to DASHBOARD_SUPPORT_EMAIL

            subject event[:mail_subject]

            text = (event[:mail_text] || '').dup
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

            StringIO.open do |io|
                io.puts text
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

    def get_sign_ups_for_public_event(event_key)
        event = @@public_event_config.select { |x| x[:key] == event_key }.first
        assert(!event.nil?)
        tracks = []
        event[:rows].each do |_row|
            _row[:entries].each do |_entry|
                tracks << "#{event_key}/#{_entry[:key]}"
            end
        end

        entries = neo4j_query(<<~END_OF_QUERY, :tracks => tracks).map { |x| {:person => x['n'], :track => x['t.track']} }
            MATCH (n:PublicEventPerson)-[:SIGNED_UP_FOR]->(t:PublicEventTrack)
            WHERE t.track in $tracks
            RETURN t.track, n
            ORDER BY n.timestamp ASC;
        END_OF_QUERY
        result = {}
        entries.each do |entry|
            result[entry[:track].sub("#{event[:key]}/", '')] ||= []
            result[entry[:track].sub("#{event[:key]}/", '')] << entry[:person]
        end
        result
    end

    def public_events_table()
        require_user_who_can_manage_news!
        self.class.refresh_public_event_config()
        StringIO.open do |io|
            @@public_event_config.each.with_index do |event, event_index|
                if event_index > 0
                    io.puts "<hr />"
                end
                io.puts "<h3>#{event[:title]}</h3>"
                # if event[:description]
                #     io.puts event[:description]
                # end
                sign_ups = get_sign_ups_for_public_event(event[:key])
                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;' data-event-key='#{event[:key]}'>"
                io.puts "<div style='display: none;' class='event-title'>#{event[:title]}</div>"
                io.puts "<table style='table-layout: fixed;' class='table table-narrow narrow'>"
                colspan = event[:rows].map { |x| x[:entries].size }.max
                io.puts "<colgroup>"
                io.puts "<col style='width: 180px;'/>"
                colspan.times do
                    io.puts "<col style='width: calc((100% - 180px) / #{colspan});'/>"
                end
                io.puts "</colgroup>"
                if event[:headings]
                    io.puts "<thead>"
                    io.puts "<tr>"
                    io.puts "<th>#{event[:headings][0]}</th>"
                    io.puts "<th colspan='#{colspan}'>#{event[:headings][1]}</th>"
                    io.puts "</tr>"
                    io.puts "</thead>"
                end
                io.puts "<tbody>"
                event[:rows].each do |row|
                    io.puts "<tr>"
                    io.puts "<th>#{row[:description]}</th>"
                    row[:entries].each do |entry|
                        capacity = entry[:capacity] || 0
                        booked_count = (sign_ups[entry[:key]] || []).size
                        io.puts "<td><div style='display: flex; justify-content: space-between;'><div>#{entry[:description]}</div><div>(#{booked_count}/#{capacity})</div></div><div class='progress'><div class='progress-bar progress-bar-striped' role='progressbar' style='width: #{booked_count * 100 / capacity}%;'>#{(booked_count * 100 / capacity).to_i}%</div></div></td>"
                    end
                    io.puts "</tr>"
                end
                io.puts "</tbody>"
                io.puts "</table>"
                io.puts "</div>"
            end
            io.string
        end
    end

    def print_public_event_table()
        self.class.refresh_public_event_config()
        StringIO.open do |io|
            @@public_event_config.each.with_index do |event, event_index|
                if event_index > 0
                    io.puts "<hr />"
                end
                io.puts "<h3>#{event[:title]}</h3>"
                if event[:description]
                    io.puts event[:description]
                end
                sign_ups = get_sign_ups_for_public_event(event[:key])
                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;' data-event-key='#{event[:key]}'>"
                io.puts "<div style='display: none;' class='event-title'>#{event[:title]}</div>"
                io.puts "<table class='table table-narrow narrow'>"
                colspan = event[:rows].map { |x| x[:entries].size }.max
                io.puts "<colgroup>"
                io.puts "<col style='width: 180px;'/>"
                colspan.times do
                    io.puts "<col style='width: calc((100% - 180px) / #{colspan});'/>"
                end
                io.puts "</colgroup>"
                io.puts "<tbody>"
                if event[:headings]
                    io.puts "<tr>"
                    io.puts "<th>#{event[:headings][0]}</th>"
                    io.puts "<th colspan='#{colspan}'>#{event[:headings][1]}</th>"
                    io.puts "</tr>"
                end
                event[:rows].each do |row|
                    io.puts "<tr>"
                    io.puts "<th>#{row[:description]}</th>"
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
                        booked_out = false
                        if (sign_ups[entry[:key]] || []).size >= (entry[:capacity] || 0)
                            booked_out = true
                        end
                        io.puts "<td><button data-event-key='#{event[:key]}' data-key='#{entry[:key]}' class='btn #{booked_out ? 'btn-outline-secondary' : 'btn-info'} bu-book-public-event' #{booked_out ? 'disabled': ''}>#{entry[:description]}</button><div style='display: none;' class='booking-text'>#{text}</div></td>"
                    end
                    io.puts "</tr>"
                end
                io.puts "</tbody>"
                io.puts "</table>"
                io.puts "</div>"
            end
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