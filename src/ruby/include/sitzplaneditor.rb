class Main < Sinatra::Base
    @@room_hours_for_klasse = {}
    @@rooms_for_klasse_and_shorthand = {}

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

    # Fachräume der Klasse, in denen die angemeldete Lehrkraft sie laut
    # Stundenplan unterrichtet (ohne den Klassenraum). Dort macht sie ihren
    # eigenen Sitzplan mit eigenen Tischen, für die ganze Klasse.
    def sitzplan_fachraeume(klasse)
        return [] unless teacher_logged_in?
        rooms = (((@@rooms_for_klasse_and_shorthand || {})[klasse] || {})[@session_user[:shorthand]] || []).to_a
        (rooms - klassenraeume_for_klasse(klasse)).sort
    end

    # Wessen Sitzpläne sind gemeint? nil: die der Klasse (Klassenraum, von
    # der Klassenleitung). Sonst die E-Mail der Lehrkraft, die die Klasse in
    # diesem Fachraum unterrichtet - ihre eigenen, getrennt von allen anderen.
    def sitzplan_owner(klasse, raum)
        sitzplan_fachraeume(klasse).include?(raum) ? @session_user[:email] : nil
    end

    # Die Sitzplan-Seiten: im eigenen Fachraum die Lehrkraft, sonst die
    # Klassenleitung.
    def require_sitzplan_page!(klasse, raum, editor = false)
        require_teacher!
        return if sitzplan_owner(klasse, raum)
        require_sitzplan_klassenleitung!(klasse, raum, editor)
    end

    def sitzplan_seats_for(klasse, raum)
        owner = sitzplan_owner(klasse, raum)
        owner ? SitzplanDaten.teacher_room(raum, owner) : SitzplanDaten.room(raum)
    end

    # Bestuhlung für die Sitzplan-Seiten (seats_dict): im eigenen Fachraum
    # gelten die Tische der Lehrkraft.
    def sitzplan_seats_js
        klasse, raum = sitzplan_path_params
        owner = sitzplan_owner(klasse, raum)
        SitzplanDaten.seats_js(owner ? [raum, SitzplanDaten.teacher_room(raum, owner)] : nil)
    end

    # Darf die Seite „Tische im Raum“ anbieten? Halbe Positionen kann der
    # Editor nicht darstellen.
    def sitzplan_editor_allowed?
        klasse, raum = sitzplan_path_params
        allowed = sitzplan_owner(klasse, raum) || sitzplan_editor_rooms(klasse).include?(raum)
        !!allowed && !SitzplanDaten.half_positions?(sitzplan_seats_for(klasse, raum))
    end

    # Für „Raumplan übernehmen“ im eigenen Fachraum: die Tische der Schule
    # für diesen Raum und die anderer Lehrkräfte. Nur, was der Editor
    # darstellen kann (keine halben Positionen). Übernehmen ist eine Kopie.
    def sitzplan_other_layouts
        klasse, raum = sitzplan_path_params
        owner = sitzplan_owner(klasse, raum)
        return [] unless owner
        layouts = []
        shared = SitzplanDaten.room(raum)
        layouts << {:name => 'Tische der Schule', :seats => shared} if shared && !SitzplanDaten.half_positions?(shared)
        SitzplanDaten.teacher_rooms(raum).each do |email, seats|
            info = @@user_info[email]
            next if email == owner || info.nil? || SitzplanDaten.half_positions?(seats)
            layouts << {:name => "Tische von #{info[:display_name_official_dativ] || info[:display_name_official]}", :seats => seats}
        end
        layouts
    end

    def sitzplan_fail!(message)
        respond(:error => message)
        assert(false, message, true)
    end

    # rules und bff können geheime Absprachen enthalten. Der Shuffler rechnet im
    # Browser, deshalb kommen in den Seitenquelltext nur die Einträge der Klasse
    # aus der URL, und auch nur für Lehrkräfte dieser Klasse.
    # Im eigenen Fachraum gibt es keine: Diese Absprachen gehören zur
    # Klassenleitung.
    def sitzplan_logins_for_page
        klasse, raum = sitzplan_path_params
        return [] if sitzplan_owner(klasse, raum)
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
    # Im eigenen Fachraum zählen nur die eigenen Pläne der Lehrkraft.
    def sitzplaneditor_saved_plan_count
        klasse, raum = sitzplan_path_params
        neo4j_query_expect_one(<<~END_OF_QUERY, :raum => raum, :lehrer => sitzplan_owner(klasse, raum) || '')['n']
            MATCH (sc:SeatingCycle {raum: $raum})
            WHERE #{sph_scope_cond('sc')}
            RETURN COUNT(sc) AS n;
        END_OF_QUERY
    end

    # Regeln des Shufflers (rules: Bereich je Person, bff: Paare mit
    # Häufigkeit) für die Klasse - für die Zwischenseite vor dem Shuffler. Nur
    # die Klassenleitung; nur Einträge, bei denen alle Personen in der Klasse
    # sind. Die Vorgaben der übrigen Werkzeuge sind davon getrennt.
    def sitzplan_shuffler_rules_for(klasse)
        login_to_email = {}
        (@@schueler_for_klasse[klasse] || []).each { |e| login_to_email[@@user_info[e][:nc_login]] = e }
        rules = SitzplanDaten.list(:rules).select { |r| login_to_email[r[0]] && r[1].is_a?(Array) && r[2].is_a?(Array) }
        bff = SitzplanDaten.list(:bff).select { |b| login_to_email[b[0]] && login_to_email[b[1]] }
        {
            :rules => rules.map { |r| {:email => login_to_email[r[0]], :x => r[1], :y => r[2]} },
            :bff => bff.map { |b| {:a => login_to_email[b[0]], :b => login_to_email[b[1]], :freq => (b[2].is_a?(Integer) && b[2] > 0 ? b[2] : 1)} },
        }
    end

    post '/api/sitzplan_shuffler_rules' do
        data = parse_request_data(:required_keys => [:klasse, :raum])
        require_sitzplan_klassenleitung!(data[:klasse], data[:raum])
        respond({:ok => true}.merge(sitzplan_shuffler_rules_for(data[:klasse])))
    end

    post '/api/sitzplan_shuffler_rules_save' do
        data = parse_request_data(:required_keys => [:klasse, :raum, :rules, :bff],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        klasse = data[:klasse]
        require_sitzplan_klassenleitung!(klasse, data[:raum])
        email_to_login = {}
        (@@schueler_for_klasse[klasse] || []).each { |e| email_to_login[e] = @@user_info[e][:nc_login] }
        rules = JSON.parse(data[:rules]) rescue nil
        bff = JSON.parse(data[:bff]) rescue nil
        assert(rules.is_a?(Array) && bff.is_a?(Array) && rules.size <= 200 && bff.size <= 200, 'Ungültige Regeln.')
        range_ok = lambda { |v| v.is_a?(Array) && v.size == 2 && v.all? { |n| n.is_a?(Numeric) && n.finite? && n.between?(0, 60) } && v[0] <= v[1] }
        new_rules = rules.map do |r|
            assert(r.is_a?(Hash) && email_to_login[r['email']] && range_ok.call(r['x']) && range_ok.call(r['y']), 'Ungültige Regeln.')
            [email_to_login[r['email']], r['x'], r['y']]
        end
        new_bff = bff.map do |b|
            assert(b.is_a?(Hash) && email_to_login[b['a']] && email_to_login[b['b']] && b['a'] != b['b'] &&
                   b['freq'].is_a?(Integer) && b['freq'].between?(1, 10), 'Ungültige Paare.')
            [email_to_login[b['a']], email_to_login[b['b']], b['freq']]
        end
        # Der Shuffler kennt je Person nur einen Partner.
        in_pairs = new_bff.flat_map { |b| b[0, 2] }
        sitzplan_fail!('Eine Person kann beim Shuffler nur in einem Paar sein.') if in_pairs.uniq.size != in_pairs.size
        logins = email_to_login.values
        begin
            all_rules = SitzplanDaten.list_strict(:rules)
            all_bff = SitzplanDaten.list_strict(:bff)
        rescue SitzplanDaten::FormatError, JSON::ParserError
            sitzplan_fail!('Die bisherigen Regeln des Shufflers sind nicht lesbar. Es wurde nichts geändert.')
        end
        # Einträge der übrigen Klassen bleiben, wie sie sind.
        all_rules = all_rules.reject { |r| r.is_a?(Array) && logins.include?(r[0]) } + new_rules
        all_bff = all_bff.reject { |b| b.is_a?(Array) && logins.include?(b[0]) && logins.include?(b[1]) } + new_bff
        SitzplanDaten.write_list(:rules, all_rules)
        SitzplanDaten.write_list(:bff, all_bff)
        respond({:ok => true}.merge(sitzplan_shuffler_rules_for(klasse)))
    end

    post '/api/sitzplaneditor_save' do
        data = parse_request_data(:required_keys => [:klasse, :raum, :seats],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        require_sitzplan_page!(data[:klasse], data[:raum], true)
        assert(data[:raum] =~ SitzplanDaten::ROOM_NAME, 'Ungültiger Raumname.')
        owner = sitzplan_owner(data[:klasse], data[:raum])
        # Der Editor zeigt halbe Positionen nicht an; Speichern würde sie verlieren.
        if SitzplanDaten.half_positions?(sitzplan_seats_for(data[:klasse], data[:raum]))
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
        if owner
            SitzplanDaten.write_teacher_room(data[:raum], owner, seats)
        else
            SitzplanDaten.write_room(data[:raum], seats)
        end
        respond(:ok => true, :seats => seats)
    end
end
