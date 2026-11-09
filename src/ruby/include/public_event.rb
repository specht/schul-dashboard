# sign-ups per e-mail address within an hour, see /api/sign_up_for_public_event
MAX_PUBLIC_SIGN_UPS_PER_HOUR = 3 unless defined?(MAX_PUBLIC_SIGN_UPS_PER_HOUR)

class Main < Sinatra::Base
    post '/api/sign_up_for_public_event' do
        data = parse_request_data(:required_keys => [:event_key, :entry_key, :name, :email])
        # loaded on demand (otherwise only the sign-up page loads it)
        self.class.refresh_public_event_config()
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

        # A few sign-ups per address and hour at most: the sign-up sends a mail from
        # the school's address to any address, so it must not become a mail relay.
        since = (DateTime.now - Rational(1, 24)).strftime('%Y-%m-%d %H:%M:%S')
        recent = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email].to_s.strip.downcase, :since => since)['n']
            MATCH (p:PublicEventPerson)
            WHERE toLower(p.email) = $email AND p.timestamp >= $since
            RETURN count(p) AS n;
        END_OF_QUERY
        if recent >= MAX_PUBLIC_SIGN_UPS_PER_HOUR
            debug "Too many sign ups for one address within an hour"
            respond(:error => 'too_many_sign_ups')
            return
        end

        tag = RandomTag.generate(12)
        # no name or address of external people in the log
        debug "Got sign up for #{data[:event_key]} / #{data[:entry_key]}"
        timestamp = DateTime.now.strftime('%Y-%m-%d %H:%M:%S')
        neo4j_query(<<~END_OF_QUERY, :name => data[:name], :email => data[:email], :track => track, :timestamp => timestamp, :tag => tag)
            MERGE (t:PublicEventTrack {track: $track})
            CREATE (p:PublicEventPerson {tag: $tag, name: $name, email: $email, timestamp: $timestamp})-[:SIGNED_UP_FOR]->(t)
        END_OF_QUERY
        # the mail is HTML; the name comes from outside
        name = CGI.escapeHTML(data[:name].to_s)
        deliver_mail do
            to data[:email]
            bcc SMTP_FROM
            from SMTP_FROM
            # reply_to SCHULLEITUNG_EMAIL
            reply_to 'winkler@gymnasiumsteglitz.de'

            subject event[:mail_subject]

            # {...} in the configured mail text is Ruby (e.g. {entry[:description]}),
            # evaluated once each – what an expression returns is never evaluated
            text = PageTemplate.evaluate(event[:mail_text] || '', open: '{') do |code|
                begin
                    eval(code)
                rescue
                    debug "Error while evaluating mail text: #{code}"
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
        require_admin_or_sekretariat!
        self.class.refresh_public_event_config()
        StringIO.open do |io|
            description_for_key_and_key = {}
            row_description_for_key_and_key = {}
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
                    io.puts "<col style='min-width: 200px;'/>"
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
                        description_for_key_and_key[event[:key]] ||= {}
                        description_for_key_and_key[event[:key]][entry[:key]] ||= entry[:description]
                        if entry[:row_description]
                            row_description_for_key_and_key[event[:key]] ||= {}
                            row_description_for_key_and_key[event[:key]][entry[:key]] ||= entry[:row_description]
                        end
                        capacity = entry[:capacity] || 0
                        booked_count = (sign_ups[entry[:key]] || []).size
                        percent = 0
                        if capacity != 0
                            percent = booked_count * 100 / capacity
                        end
                        io.puts "<td><div style='display: flex; justify-content: space-between;'><div>#{entry[:description]}</div><div>(#{booked_count}/#{capacity})</div></div><div class='progress'><div class='progress-bar progress-bar-striped' role='progressbar' style='width: #{percent}%;'>#{(percent).to_i}%</div></div></td>"
                    end
                    io.puts "</tr>"
                end
                io.puts "</tbody>"
                io.puts "</table>"
                io.puts "</div>"
            end
            @@public_event_config.each.with_index do |event, event_index|
                STDERR.puts event.to_yaml
                sign_ups = get_sign_ups_for_public_event(event[:key])
                next if sign_ups.empty?
                io.puts "<hr />"
                io.puts "<h4>#{event[:title]}</h4>"
                io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;' data-event-key='#{event[:key]}'>"
                io.puts "<table style='table-layout: fixed;' class='table table-narrow narrow'>"
                io.puts "<tr><th>E-Mail</th><th>Name</th><th>Track</th><th></th></tr>"
                io.puts "<tbody>"
                sign_ups.keys.sort.each do |key|
                    sign_ups[key].each do |entry|
                        io.puts "<tr>"
                        io.puts "<td>#{entry[:email]}</td>"
                        io.puts "<td>#{entry[:name]}</td>"
                        io.puts "<td>#{[(row_description_for_key_and_key[event[:key]] || {})[key], description_for_key_and_key[event[:key]][key]].reject { |x| x.nil? }.join(' / ')}</td>"
                        if admin_logged_in?
                            io.puts "<td><button class='btn btn-xs btn-danger bu-delete-signup' data-tag='#{entry[:tag]}'><i class='fa fa-trash'></i>&nbsp;&nbsp;Löschen</button></td>"
                        else
                            io.puts "<td></td>"
                        end
                        io.puts "</tr>"
                    end
                end
                io.puts "</tbody>"
                io.puts "</table>"
                io.puts "</div>"
            end
            io.string
        end
    end

    # Datum eines Termins aus dem Key, wenn dieser mit YYYY-MM-DD beginnt, sonst nil.
    def public_event_entry_date(entry)
        m = entry[:key].to_s.match(/\A(\d{4}-\d{2}-\d{2})/)
        m ? (Date.parse(m[1]) rescue nil) : nil
    end

    # Die Parameter heißen event, row und entry, weil booking_text aus der
    # Konfiguration Ausdrücke wie {entry[:description]} enthält, die hier per
    # eval ausgewertet werden.
    def public_event_entry_button(event, row, entry, sign_ups, not_yet)
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
        if not_yet
            booked_out = true
        end
        # :label ist die kurze Beschriftung (z. B. "09:00"), :description bleibt
        # für Buchungstext und Mail ("09:00 Uhr")
        "<button data-event-key='#{event[:key]}' data-key='#{entry[:key]}' class='btn #{booked_out ? 'btn-outline-secondary' : 'btn-info'} bu-book-public-event' #{booked_out ? 'disabled': ''}>#{entry[:label] || entry[:description]}</button><div style='display: none;' class='booking-text'>#{text}</div>"
    end

    # Vorbei ist ein Termin, wenn seine Anmeldefrist abgelaufen ist, die Uhrzeit
    # im Key (z. B. "2026-12-02T09:00") vorbei ist oder das Datum im Key vor heute liegt.
    def public_event_entry_past?(entry, today, ts)
        return true if entry[:deadline] && ts > entry[:deadline]
        key = entry[:key].to_s
        return key[0, 16] < ts if key =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
        date = public_event_entry_date(entry)
        !date.nil? && date < today
    end

    # Die anzuzeigenden Zeilen eines Events: vergangene Termine fallen weg, Zeilen
    # ohne kommende Termine ganz. Mit :max_upcoming_weeks: N nur Termine aus den
    # ersten N Kalenderwochen, in denen überhaupt Termine liegen - Wochen ohne
    # Termine (Ferien) zählen nicht mit. Liefert [rows, ob weitere Termine
    # ausgeblendet sind].
    def public_event_upcoming_rows(event, today, ts)
        filter_rows = lambda do |rows, &keep|
            rows.map do |row|
                entries = row[:entries].select(&keep)
                (entries.empty? && !row[:entries].empty?) ? nil : row.merge(:entries => entries)
            end.compact
        end
        rows = filter_rows.call(event[:rows] || []) { |entry| !public_event_entry_past?(entry, today, ts) }
        weeks = event[:max_upcoming_weeks]
        dates = rows.map { |row| row[:entries].map { |entry| public_event_entry_date(entry) } }.flatten.compact
        return [rows, false] if weeks.nil? || dates.empty?
        week_of = lambda { |date| [date.cwyear, date.cweek] }
        shown_weeks = dates.map { |date| week_of.call(date) }.uniq.sort.first(weeks)
        limited = filter_rows.call(rows) { |entry| (date = public_event_entry_date(entry)).nil? || shown_weeks.include?(week_of.call(date)) }
        count = lambda { |list| list.sum { |row| row[:entries].size } }
        [limited, count.call(limited) < count.call(rows)]
    end

    # "23.–27.11.", über den Monat "30.11.–04.12.", über das Jahr
    # "28.12.2026–08.01.2027", ein einzelner Tag "21.12."
    def public_event_date_range(dates)
        first, last = dates.min, dates.max
        return first.strftime('%d.%m.') if first == last
        return "#{first.strftime('%d.%m.%Y')}–#{last.strftime('%d.%m.%Y')}" if first.year != last.year
        return "#{first.strftime('%d.')}–#{last.strftime('%d.%m.')}" if first.month == last.month
        "#{first.strftime('%d.%m.')}–#{last.strftime('%d.%m.')}"
    end

    def public_event_more_note(event)
        return event[:more_rows_note] if event[:more_rows_note]
        n = event[:max_upcoming_weeks]
        weeks = n == 1 ? 'aus der nächsten Woche' : "aus den nächsten #{n} Wochen"
        "Hier werden immer nur die Termine #{weeks} mit Terminen angezeigt. Sobald eine Woche vorbei ist, kommen weitere Termine dazu – es lohnt sich also, später noch einmal vorbeizuschauen."
    end

    def print_public_event_table()
        self.class.refresh_public_event_config()
        ts = Time.now.strftime("%Y-%m-%dT%H:%M")
        StringIO.open do |io|
            if @@public_event_config.empty?
                io.puts "<p>Es sind momentan keine Veranstaltungen geplant, bitte versuchen Sie es später noch einmal.</p>"
            end
            @@public_event_config.each.with_index do |event, event_index|
                if event_index > 0
                    io.puts "<hr />"
                end
                io.puts "<h3>#{event[:title]}</h3>"
                not_yet = false
                if event[:not_before] && Time.now.strftime('%Y-%m-%dT%H:%M:%S') < event[:not_before]
                    not_yet = true
                end
                if event[:description]
                    io.puts event[:description]
                end
                if not_yet && event[:not_before_description]
                    io.puts event[:not_before_description]
                end
                sign_ups = get_sign_ups_for_public_event(event[:key])
                rows, more_rows = public_event_upcoming_rows(event, Date.today, ts)
                if event[:auto_rows]
                    # Ein Tag pro Zeile, die Termine in Spalten nach Stunden, damit
                    # gleiche Uhrzeiten untereinander stehen. Auf schmalen Bildschirmen
                    # stehen sie fortlaufend unter dem Tag (.pe-* in anmeldung.html).
                    hour_of = lambda { |entry| entry[:key].to_s[11, 2].to_i }
                    hours = rows.map { |row| row[:entries].map { |entry| hour_of.call(entry) } }.flatten
                    io.puts "<div class='table-responsive pe-slots' data-event-key='#{event[:key]}'>"
                    io.puts "<div style='display: none;' class='event-title'>#{event[:title]}</div>"
                    unless hours.empty?
                        hour_range = (hours.min..hours.max).to_a
                        io.puts "<div class='pe-day pe-head'><div class='pe-day-label'>#{(event[:headings] || [])[0]}</div><div class='pe-hours'>"
                        hour_range.each { |hour| io.puts "<div class='pe-hour'>#{hour} Uhr</div>" }
                        io.puts "</div></div>"
                        last_week = nil
                        rows.each do |row|
                            next if row[:entries].empty?
                            date = public_event_entry_date(row[:entries].first)
                            week = date && [date.cwyear, date.cweek]
                            io.puts "<div class='pe-day#{(last_week && week != last_week) ? ' pe-new-week' : ''}'>"
                            last_week = week
                            io.puts "<div class='pe-day-label'>#{row[:description]}</div><div class='pe-hours'>"
                            by_hour = row[:entries].group_by { |entry| hour_of.call(entry) }
                            hour_range.each do |hour|
                                slots = by_hour[hour] || []
                                io.puts "<div class='pe-hour#{slots.empty? ? ' pe-empty' : ''}'>"
                                slots.each { |entry| io.puts public_event_entry_button(event, row, entry, sign_ups, not_yet) }
                                io.puts "</div>"
                            end
                            io.puts "</div></div>"
                        end
                    end
                    io.puts "</div>"
                else
                    # Beginnen alle Keys mit einem Datum (z. B. "2026-11-19-klasse-5"),
                    # steht jeder Termin in der Spalte seines Wochentags. Der Spaltenbereich
                    # kommt aus allen Zeilen, damit er sich nicht ändert, wenn Zeilen
                    # wegfallen.
                    all_dates = (event[:rows] || []).map { |row| row[:entries].map { |entry| public_event_entry_date(entry) } }.flatten
                    weekday_grid = !all_dates.empty? && all_dates.all?
                    if weekday_grid
                        first_wday = all_dates.map(&:cwday).min
                        colspan = all_dates.map(&:cwday).max - first_wday + 1
                    else
                        colspan = rows.map { |x| x[:entries].size }.max || 1
                    end
                    io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;' data-event-key='#{event[:key]}'>"
                    io.puts "<div style='display: none;' class='event-title'>#{event[:title]}</div>"
                    io.puts "<table class='table table-narrow narrow th-middle'>"
                    io.puts "<colgroup>"
                    if weekday_grid
                        # Beschriftung so breit wie nötig, die Wochentage teilen sich
                        # den Rest gleichmäßig
                        io.puts "<col style='width: 1%;'/>"
                        colspan.times do
                            io.puts "<col style='width: #{(100.0 / colspan).round(2)}%;'/>"
                        end
                    else
                        io.puts "<col style='width: 180px;'/>"
                        colspan.times do
                            io.puts "<col style='width: auto;'/>"
                        end
                    end
                    io.puts "</colgroup>"
                    io.puts "<tbody>"
                    if event[:headings]
                        io.puts "<tr>"
                        io.puts "<th>#{event[:headings][0]}</th>"
                        io.puts "<th colspan='#{colspan}'>#{event[:headings][1]}</th>"
                        io.puts "</tr>"
                    end
                    # Im Wochenraster steht links der Zeitraum der Zeile; die Beschreibung
                    # nur dann klein darunter, wenn sich die Zeilen darin unterscheiden.
                    same_description = rows.map { |row| row[:description] }.uniq.size <= 1
                    rows.each do |row|
                        io.puts "<tr>"
                        if weekday_grid && !row[:entries].empty?
                            io.puts "<th>#{public_event_date_range(row[:entries].map { |entry| public_event_entry_date(entry) })}"
                            io.puts "<div class='text-muted' style='font-weight: normal; font-size: 85%;'>#{row[:description]}</div>" unless same_description
                            io.puts "</th>"
                        else
                            io.puts "<th>#{row[:description]}</th>"
                        end
                        if weekday_grid
                            by_wday = row[:entries].group_by { |entry| public_event_entry_date(entry).cwday }
                            colspan.times do |i|
                                io.puts "<td>"
                                (by_wday[first_wday + i] || []).each do |entry|
                                    io.puts public_event_entry_button(event, row, entry, sign_ups, not_yet)
                                end
                                io.puts "</td>"
                            end
                        else
                            row[:entries].each do |entry|
                                io.puts "<td>#{public_event_entry_button(event, row, entry, sign_ups, not_yet)}</td>"
                            end
                        end
                        io.puts "</tr>"
                    end
                    io.puts "</tbody>"
                    io.puts "</table>"
                    io.puts "</div>"
                end
                if more_rows
                    io.puts "<div class='alert alert-info' style='margin-top: 0.5em;'><i class='fa fa-info-circle'></i>&nbsp;&nbsp;#{public_event_more_note(event)}</div>"
                end
            end
            io.string
        end
    end

    def self.fix_public_event_config
        debug "Fixing public event config!"
        @@public_event_config.map! do |entry|
            if entry[:auto_rows]
                rows = []
                entry[:auto_rows].each do |auto_entry|
                    row = {}
                    day = Date.parse(auto_entry[:day])
                    row[:description] = "#{%w(So Mo Di Mi Do Fr Sa)[day.wday]}., #{day.strftime("%d.%m.%Y")}"
                    row[:entries] = []
                    auto_entry[:spans].each do |span|
                        t = Time.parse("#{auto_entry[:day]}T#{span[0]}")
                        while t + auto_entry[:duration] * 60 <= Time.parse("#{auto_entry[:day]}T#{span[1]}")
                            deadline = nil
                            if entry[:auto_rows_no_signup_deadline]
                                if entry[:auto_rows_no_signup_deadline].is_a?(Numeric)
                                    deadline = "#{(t - entry[:auto_rows_no_signup_deadline] * 3600).strftime("%Y-%m-%dT%H:%M")}"
                                else
                                    deadline = "#{t.strftime("%Y-%m-%dT")}#{entry[:auto_rows_no_signup_deadline]}"
                                end
                            end
                            row[:entries] << {
                                :key => "#{t.strftime("%Y-%m-%dT%H:%M")}",
                                :deadline => deadline,
                                :description => "#{t.strftime("%H:%M")} Uhr",
                                :label => t.strftime("%H:%M"),
                                :row_description => row[:description],
                                :capacity => 1,
                            }
                            t += auto_entry[:duration] * 60
                        end
                    end
                    rows << row
                end
                entry[:rows] = rows
            end
            entry
        end
        # debug @@public_event_config.to_yaml
    end

    def self.refresh_public_event_config()
        @@public_event_config_timestamp ||= 0
        path = '/data/public_events/public_events.yaml'
        if DEVELOPMENT || @@public_event_config_timestamp < File.mtime(path).to_i
            debug "Reloading public event config from #{path}!"
            @@public_event_config = YAML.load(File.read(path)) || []
            self.fix_public_event_config()
            @@public_event_config_timestamp = File.mtime(path).to_i
        end
    end
end