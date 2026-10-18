require 'fileutils'

# Liest und ändert /data/sitzplan/seats.js, ohne die handgepflegte Datei neu zu
# formatieren: Beim Speichern wird nur das Array des einen Raums ersetzt bzw.
# ein neuer Eintrag angefügt, alles andere bleibt Zeichen für Zeichen erhalten.
module SitzplanSeatsFile
    class FormatError < StandardError; end

    # kein Anführungszeichen, #, {, <, / oder \ - der Name landet in JS und in einem Template
    ROOM_NAME = /\A[[:alnum:]_.\- ]{1,32}\z/

    def self.skip_ws_and_comments(src, i)
        loop do
            i += 1 while i < src.size && src[i] =~ /\s/
            if src[i, 2] == '//'
                i = src.index("\n", i) || src.size
            elsif src[i, 2] == '/*'
                j = src.index('*/', i + 2)
                i = j ? j + 2 : src.size
            else
                return i
            end
        end
    end

    def self.skip_string(src, i)
        quote = src[i]
        i += 1
        while i < src.size
            return i + 1 if src[i] == quote
            i += (src[i] == '\\') ? 2 : 1
        end
        i
    end

    def self.find_matching(src, i)
        depth = 0
        while i < src.size
            c = src[i]
            if c == '"' || c == "'" || c == '`'
                i = skip_string(src, i)
                next
            elsif src[i, 2] == '//' || src[i, 2] == '/*'
                i = skip_ws_and_comments(src, i)
                next
            elsif c == '[' || c == '{'
                depth += 1
            elsif c == ']' || c == '}'
                depth -= 1
                return i if depth == 0
            end
            i += 1
        end
        nil
    end

    # Alle Vorkommen des Bezeichners seats_dict außerhalb von Kommentaren und Strings
    def self.identifier_positions(src)
        positions = []
        i = 0
        while i < src.size
            c = src[i]
            if c == '"' || c == "'" || c == '`'
                i = skip_string(src, i)
            elsif src[i, 2] == '//' || src[i, 2] == '/*'
                i = skip_ws_and_comments(src, i)
            elsif src[i, 10] == 'seats_dict' && (i == 0 || src[i - 1] !~ /[\w$.]/) && src[i + 10].to_s !~ /[\w$]/
                positions << i
                i += 10
            else
                i += 1
            end
        end
        positions
    end

    def self.parse(src)
        raise FormatError unless src.valid_encoding?
        positions = identifier_positions(src)
        # genau eine Stelle, sonst ist unklar, welche Definition im Browser gilt
        raise FormatError unless positions.size == 1
        j = skip_ws_and_comments(src, positions.first + 10)
        raise FormatError unless src[j] == '=' && src[j + 1] != '='
        open = skip_ws_and_comments(src, j + 1)
        raise FormatError unless src[open] == '{'
        close = find_matching(src, open)
        raise FormatError unless close
        entries = []
        i = open + 1
        loop do
            i = skip_ws_and_comments(src, i)
            break if i >= close
            if src[i] == ','
                i += 1
                next
            end
            if src[i] == '"' || src[i] == "'"
                j = skip_string(src, i)
                key = src[(i + 1)...(j - 1)]
            else
                j = i
                j += 1 while j < close && src[j] =~ /[\w$]/
                raise FormatError if j == i
                key = src[i...j]
            end
            j = skip_ws_and_comments(src, j)
            raise FormatError unless src[j] == ':'
            j = skip_ws_and_comments(src, j + 1)
            raise FormatError unless src[j] == '['
            value_end = find_matching(src, j)
            raise FormatError unless value_end && value_end < close
            raise FormatError if entries.any? { |e| e[:key] == key }
            entries << {:key => key, :value_start => j, :value_end => value_end}
            i = value_end + 1
        end
        {:open => open, :close => close, :entries => entries}
    end

    # Nach dem Ersetzen muss alles außer dem einen Raum Zeichen für Zeichen gleich sein.
    def self.only_room_changed?(old_src, new_src, raum)
        return true if old_src.nil? || old_src.strip.empty?
        a = parse(old_src)
        b = parse(new_src)
        others = lambda do |src, info|
            info[:entries].reject { |e| e[:key] == raum }.map { |e| [e[:key], src[e[:value_start]..e[:value_end]]] }
        end
        old_src[0..a[:open]] == new_src[0..b[:open]] &&
            old_src[a[:close]..] == new_src[b[:close]..] &&
            others.call(old_src, a) == others.call(new_src, b) &&
            new_src.scan('#{').size == old_src.scan('#{').size &&
            new_src.scan('</').size == old_src.scan('</').size
    end

    def self.room(src, raum)
        raise FormatError if src && !src.valid_encoding?
        return nil if src.nil? || src.strip.empty?
        entry = parse(src)[:entries].find { |e| e[:key] == raum }
        return nil unless entry
        text = src[entry[:value_start]..entry[:value_end]]
        JSON.parse(text.gsub(/\/\*.*?\*\//m, '').gsub(/\/\/[^\n]*/, '').gsub(/,(\s*\])/, '\1'))
    end

    # Gleiches Schema wie die handgepflegten Einträge: eine Zeile pro Reihe.
    def self.format_seats(seats)
        rows = seats.group_by { |s| s[1] }
        lines = rows.keys.sort.map do |y|
            '        ' + rows[y].map { |s| '[' + s.join(', ') + ']' }.join(', ') + ','
        end
        "[\n" + lines.join("\n") + "\n    ]"
    end

    def self.upsert(src, raum, seats)
        raise FormatError unless raum =~ ROOM_NAME
        raise FormatError if src && !src.valid_encoding?
        array_text = format_seats(seats)
        if src.nil? || src.strip.empty?
            return "var seats_dict = {\n    '#{raum}': #{array_text},\n};\n"
        end
        info = parse(src)
        entry = info[:entries].find { |e| e[:key] == raum }
        if entry
            return src[0...entry[:value_start]] + array_text + src[(entry[:value_end] + 1)..]
        end
        new_entry = "'#{raum}': #{array_text},"
        last = info[:entries].last
        if last.nil?
            pos = info[:open] + 1
            return src[0...pos] + "\n    " + new_entry + src[pos..]
        end
        after = skip_ws_and_comments(src, last[:value_end] + 1)
        if src[after] == ','
            pos = after + 1
            src[0...pos] + "\n    " + new_entry + src[pos..]
        else
            pos = last[:value_end] + 1
            src[0...pos] + ",\n    " + new_entry.chomp(',') + src[pos..]
        end
    end
end

class Main < Sinatra::Base
    SITZPLAN_DIR = '/data/sitzplan'
    SITZPLAN_SEATS_PATH = File.join(SITZPLAN_DIR, 'seats.js')
    SITZPLAN_BACKUP_DIR = File.join(SITZPLAN_DIR, 'backup')
    SITZPLAN_BACKUPS_KEPT = 30
    @@sitzplan_file_mutex = Mutex.new
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

    def sitzplan_read_seats_file
        File.exist?(SITZPLAN_SEATS_PATH) ? File.read(SITZPLAN_SEATS_PATH, :encoding => 'UTF-8') : nil
    end

    def sitzplan_layout_for_room(raum)
        SitzplanSeatsFile.room(sitzplan_read_seats_file, raum)
    rescue SitzplanSeatsFile::FormatError, JSON::ParserError
        nil
    end

    # Sitzordnungen (gespeichert oder noch offen) merken sich Plätze per Index bzw.
    # Koordinate in der Bestuhlung und passen nach einer Änderung nicht mehr.
    def sitzplaneditor_saved_plan_count(raum)
        neo4j_query_expect_one(<<~END_OF_QUERY, :raum => raum)['n']
            MATCH (sc:SeatingCycle {raum: $raum})
            RETURN COUNT(sc) AS n;
        END_OF_QUERY
    end

    def sitzplan_backup!(old_src)
        FileUtils.mkdir_p(SITZPLAN_BACKUP_DIR)
        # die handgepflegte Fassung vor der ersten Änderung durch den Editor bleibt dauerhaft
        original = File.join(SITZPLAN_BACKUP_DIR, 'seats-original.js')
        File.write(original, old_src) unless File.exist?(original)
        stamp = Time.now.utc.strftime('%Y%m%dT%H%M%S%6NZ')
        File.open(File.join(SITZPLAN_BACKUP_DIR, "seats-#{stamp}.js"), File::WRONLY | File::CREAT | File::EXCL) { |f| f.write(old_src) }
        backups = Dir[File.join(SITZPLAN_BACKUP_DIR, 'seats-[0-9]*.js')].sort
        FileUtils.rm(backups[0...(backups.size - SITZPLAN_BACKUPS_KEPT)]) if backups.size > SITZPLAN_BACKUPS_KEPT
    end

    def sitzplan_write_room!(raum, seats)
        @@sitzplan_file_mutex.synchronize do
            old_src = sitzplan_read_seats_file
            begin
                new_src = SitzplanSeatsFile.upsert(old_src, raum, seats)
                verified = SitzplanSeatsFile.room(new_src, raum) == seats &&
                           SitzplanSeatsFile.only_room_changed?(old_src, new_src, raum)
            rescue SitzplanSeatsFile::FormatError, JSON::ParserError
                sitzplan_fail!('Die Datei seats.js hat ein Format, das der Editor nicht sicher bearbeiten kann. Bitte wenden Sie sich an die Administration.')
            end
            assert(verified, 'Kontrolle der geschriebenen Bestuhlung fehlgeschlagen.')
            next if new_src == old_src
            sitzplan_backup!(old_src) if old_src
            tmp_path = "#{SITZPLAN_SEATS_PATH}.tmp"
            File.write(tmp_path, new_src)
            File.rename(tmp_path, SITZPLAN_SEATS_PATH)
        end
    end

    post '/api/sitzplaneditor_save' do
        data = parse_request_data(:required_keys => [:klasse, :raum, :seats],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        require_sitzplan_klassenleitung!(data[:klasse], data[:raum], true)
        assert(data[:raum] =~ SitzplanSeatsFile::ROOM_NAME, 'Ungültiger Raumname.')
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
        sitzplan_write_room!(data[:raum], seats)
        respond(:ok => true, :seats => seats)
    end

    post '/api/sitzplanverteilen_state' do
        data = parse_request_data(:required_keys => [:klasse, :raum])
        klasse = data[:klasse]
        raum = data[:raum]
        require_sitzplan_klassenleitung!(klasse, raum)
        sus_emails = (@@schueler_for_klasse[klasse] || []).sort_by do |e|
            [@@user_info[e][:last_name].downcase, @@user_info[e][:first_name].downcase]
        end
        sus = sus_emails.map do |e|
            info = @@user_info[e]
            first = info[:display_first_name] || info[:first_name]
            last = info[:display_last_name] || info[:last_name]
            {:email => e, :name => info[:display_name_official], :short => "#{first} #{last[0]}."}
        end
        rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
            MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE sc.saved_at IS NOT NULL
            RETURN sc
            ORDER BY sc.saved_at DESC
            LIMIT 1;
        END_OF_QUERY
        last_seats = rows.empty? ? {} : JSON.parse(rows.first['sc'][:seats] || '{}')
        respond(:ok => true, :sus => sus, :last_seats => last_seats)
    end

    # Speichert eine manuelle Verteilung als SeatingCycle wie der
    # Sitzplanhelfer, damit sie in seiner Plan-Historie und in der
    # SuS-Ansicht (sitzplananzeige.html) erscheint.
    post '/api/sitzplanverteilen_save' do
        data = parse_request_data(:required_keys => [:klasse, :raum, :seats],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        klasse = data[:klasse]
        raum = data[:raum]
        require_sitzplan_klassenleitung!(klasse, raum)
        seats = JSON.parse(data[:seats]) rescue nil
        assert(seats.is_a?(Hash), 'Ungültige Verteilung.')
        sus_emails = @@schueler_for_klasse[klasse] || []
        layout = sitzplan_layout_for_room(raum)
        sitzplan_fail!('Für diesen Raum ist keine Bestuhlung angelegt.') if layout.nil?
        seats = seats.select { |email, idx| sus_emails.include?(email) && idx.is_a?(Integer) && idx >= 0 && idx < layout.size }
        assert(seats.values.uniq.size == seats.size, 'Ein Platz ist doppelt vergeben.')
        sitzplan_fail!('Setzen Sie mindestens eine Person auf einen Platz.') if seats.empty?
        timestamp = Time.now.to_i
        neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => RandomTag.generate(12), :klasse => klasse, :raum => raum, :timestamp => timestamp, :seats => seats.to_json)
            MATCH (a:User {email: $session_email})
            CREATE (sc:SeatingCycle {id: $id, klasse: $klasse, raum: $raum, source: 'manual',
                                     created_at: $timestamp, saved_at: $timestamp, seats: $seats,
                                     unresolved: '[]', satisfied_emails: '[]',
                                     forced_pairs: '[]', forbidden_pairs: '[]', fixed_rules: '[]'})
            CREATE (sc)-[:STARTED_BY]->(a)
            RETURN sc;
        END_OF_QUERY
        respond(:ok => true, :placed => seats.size)
    end
end
