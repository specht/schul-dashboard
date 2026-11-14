class Main < Sinatra::Base
    @@room_hours_for_klasse = {}

    # Laut Stundenplan der Raum der Klasse: jeder Raum mit mindestens 20
    # Wochenstunden (dieselbe Schwelle wie beim Raumplan-PDF in fragments.rb),
    # sonst der Raum mit den meisten Stunden.
    def klassenraeume_for_klasse(klasse)
        hours = @@room_hours_for_klasse[klasse] || {}
        return [] if hours.empty?
        rooms = hours.select { |_, n| n >= 20 }.keys
        rooms = [hours.max_by { |_, n| n }[0]] if rooms.empty?
        rooms.sort
    end

    def sitzplan_allowed_rooms(klasse)
        (klassenraeume_for_klasse(klasse) + (@@rooms_for_klasse[klasse] || []).to_a).uniq
    end

    # Die Bestuhlung gilt für alle Klassen, die den Raum nutzen. Deshalb darf eine
    # Klassenleitung nur den eigenen Klassenraum ändern, Fachräume nur Admins.
    def sitzplan_editor_rooms(klasse)
        admin_logged_in? ? sitzplan_allowed_rooms(klasse) : klassenraeume_for_klasse(klasse)
    end

    def sitzplan_path_params
        parts = request.path.split('/')
        [CGI.unescape(parts[2] || ''), CGI.unescape(parts[3] || '')]
    end

    def require_sitzplan_klassenleitung!(klasse, raum, editor = false)
        require_teacher!
        assert(klassenleiter_for_klasse_or_admin_logged_in?(klasse), 'Nur die Klassenleitung darf das.')
        rooms = editor ? sitzplan_editor_rooms(klasse) : sitzplan_allowed_rooms(klasse)
        assert(rooms.include?(raum), 'Dieser Raum gehört nicht zur Klasse.')
    end

    def sitzplan_fail!(message)
        respond(:error => message)
        assert(false, message, true)
    end

    # rules und bff können geheime Absprachen enthalten. Der Shuffler rechnet im
    # Browser, deshalb kommen in den Seitenquelltext nur die Einträge der Klasse
    # aus der URL, und auch nur für Lehrkräfte dieser Klasse.
    def sitzplan_logins_for_page
        klasse = sitzplan_path_params[0]
        return [] unless sph_can_manage?(klasse)
        (@@schueler_for_klasse[klasse] || []).map { |e| @@user_info[e][:nc_login] }
    end

    def sitzplan_rules_js
        logins = sitzplan_logins_for_page
        "var rules = #{SitzplanDaten.list(:rules).select { |r| logins.include?(r[0]) }.to_json};"
    end

    def sitzplan_bff_js
        logins = sitzplan_logins_for_page
        "bff = #{SitzplanDaten.list(:bff).select { |b| logins.include?(b[0]) && logins.include?(b[1]) }.to_json};"
    end

    # Sitzordnungen (gespeichert oder noch offen) merken sich Plätze per Index bzw.
    # Koordinate in der Bestuhlung und passen nach einer Änderung nicht mehr.
    def sitzplaneditor_saved_plan_count(raum)
        neo4j_query_expect_one(<<~END_OF_QUERY, :raum => raum)['n']
            MATCH (sc:SeatingCycle {raum: $raum})
            RETURN COUNT(sc) AS n;
        END_OF_QUERY
    end

    post '/api/sitzplaneditor_save' do
        data = parse_request_data(:required_keys => [:klasse, :raum, :seats],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        require_sitzplan_klassenleitung!(data[:klasse], data[:raum], true)
        assert(data[:raum] =~ SitzplanDaten::ROOM_NAME, 'Ungültiger Raumname.')
        # Der Editor zeigt halbe Positionen nicht an; Speichern würde sie verlieren.
        if SitzplanDaten.half_positions?(SitzplanDaten.room(data[:raum]))
            sitzplan_fail!('Dieser Raum hat Plätze auf halben Positionen und kann im Editor nicht bearbeitet werden.')
        end
        seats = JSON.parse(data[:seats]) rescue nil
        assert(seats.is_a?(Array) && seats.size <= 150, 'Ungültige Bestuhlung.')
        sitzplan_fail!('Legen Sie mindestens einen Platz an.') if seats.empty?
        seats.each do |s|
            assert(s.is_a?(Array) && [2, 3].include?(s.size) && s.all? { |v| v.is_a?(Integer) }, 'Ungültige Bestuhlung.')
            assert(s[0].between?(0, 60) && s[1].between?(0, 60) && (s[2].nil? || s[2].between?(-360, 360)), 'Ungültige Bestuhlung.')
        end
        assert(seats.map { |s| s[0, 2] }.uniq.size == seats.size, 'Ungültige Bestuhlung.')
        min_x = seats.map { |s| s[0] }.min
        min_y = seats.map { |s| s[1] }.min
        seats = seats.map { |s| [s[0] - min_x, s[1] - min_y] + s[2..] }.sort_by { |s| [s[1], s[0]] }
        SitzplanDaten.write_room(data[:raum], seats)
        respond(:ok => true, :seats => seats)
    end
end
