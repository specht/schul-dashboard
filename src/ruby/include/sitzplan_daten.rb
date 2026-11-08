require 'fileutils'
require 'json'

# Sitzordnungen, Regeln und Freundespaare für Shuffler, Helfer und Editor.
#
# Das Dashboard verwaltet sie unter /internal/sitzplan: raeume/<raum>.json pro
# Raum, dazu rules.json und bff.json. /data gehört nicht dem Dashboard (dort
# liegt das von Hand gepflegte Datenrepo, schreibgeschützt eingebunden) und wird
# deshalb nur gelesen: Solange migrate-sitzplan.rb nicht gelaufen ist, gelten die
# alten seats.js, rules.js und bff.js, danach können sie aus dem Datenrepo raus.
#
# rules und bff können geheime Absprachen enthalten. Fehlermeldungen und Ausgaben
# nennen deshalb nur Dateinamen, Zeilennummern und Anzahlen, nie Inhalte.
module SitzplanDaten
    class FormatError < StandardError; end

    DATA_DIR = '/data/sitzplan'
    INTERNAL_DIR = '/internal/sitzplan'
    ROOMS_DIR = File.join(INTERNAL_DIR, 'raeume')
    BACKUP_DIR = File.join(ROOMS_DIR, 'backup')
    BACKUPS_KEPT = 10
    LISTS = {
        :rules => {:var => 'rules', :legacy => ['rules.js']},
        :bff => {:var => 'bff', :legacy => ['bff.js', 'bff.json']},
    }
    # kein Anführungszeichen, #, {, <, / oder \ - der Name landet in JS, in einem
    # Template und im Dateinamen; kein führender Punkt wegen ".." und versteckter Dateien
    ROOM_NAME = /\A[[:alnum:]_][[:alnum:]_.\- ]{0,31}\z/
    WRITE_MUTEX = Mutex.new

    # Liest die Werte aus den handgepflegten JS-Dateien: Arrays, Objekte, Strings,
    # Zahlen, Kommentare und Kommas am Ende. Alles andere (etwa berechnete Werte)
    # ist ein FormatError, statt geraten zu werden.
    class JsLiteral
        def initialize(src)
            @src = src
            @i = 0
        end

        def fail!
            raise FormatError, "Zeile #{@src[0...@i].count("\n") + 1}"
        end

        def skip
            loop do
                @i += 1 while @i < @src.size && @src[@i] =~ /\s/
                if @src[@i, 2] == '//'
                    @i = @src.index("\n", @i) || @src.size
                elsif @src[@i, 2] == '/*'
                    j = @src.index('*/', @i + 2)
                    fail! unless j
                    @i = j + 2
                else
                    return
                end
            end
        end

        def string
            quote = @src[@i]
            @i += 1
            out = +''
            while @i < @src.size
                c = @src[@i]
                if c == quote
                    @i += 1
                    return out
                elsif c == '\\'
                    @i += 1
                    esc = @src[@i]
                    fail! if esc.nil? || esc =~ /[\dxbfv]/
                    if esc == 'u'
                        out << @src[@i + 1, 4].to_i(16).chr('UTF-8')
                        @i += 5
                    else
                        out << ({'n' => "\n", 't' => "\t", 'r' => "\r"}[esc] || esc.to_s)
                        @i += 1
                    end
                else
                    out << c
                    @i += 1
                end
            end
            fail!
        end

        def value
            skip
            c = @src[@i]
            if c == '['
                @i += 1
                list = []
                loop do
                    skip
                    if @src[@i] == ']'
                        @i += 1
                        return list
                    end
                    list << value
                    skip
                    @i += 1 if @src[@i] == ','
                    fail! unless @src[@i] == ']' || @src[@i - 1] == ','
                end
            elsif c == '{'
                @i += 1
                hash = {}
                loop do
                    skip
                    if @src[@i] == '}'
                        @i += 1
                        return hash
                    end
                    key = key_name
                    skip
                    fail! unless @src[@i] == ':'
                    @i += 1
                    fail! if hash.include?(key)
                    hash[key] = value
                    skip
                    @i += 1 if @src[@i] == ','
                    fail! unless @src[@i] == '}' || @src[@i - 1] == ','
                end
            elsif c == '"' || c == "'"
                string
            elsif (m = @src[@i..].match(/\A-?\d+(\.\d+)?/))
                @i += m[0].size
                m[1] ? m[0].to_f : m[0].to_i
            elsif (m = @src[@i..].match(/\A(true|false|null)\b/))
                @i += m[0].size
                {'true' => true, 'false' => false, 'null' => nil}[m[0]]
            else
                fail!
            end
        end

        def key_name
            c = @src[@i]
            return string if c == '"' || c == "'"
            m = @src[@i..].match(/\A[\w$]+/)
            fail! unless m
            @i += m[0].size
            m[0]
        end

        # Der Wert der einen Definition "name = ...". Mehrere Stellen wären
        # uneindeutig, denn im Browser gälte die letzte.
        def definition(name)
            found = nil
            while @i < @src.size
                skip
                break if @i >= @src.size
                c = @src[@i]
                if c == '"' || c == "'"
                    string
                elsif @src[@i..].start_with?(name) && (@i == 0 || @src[@i - 1] !~ /[\w$.]/) && @src[@i + name.size].to_s !~ /[\w$]/
                    fail! if found
                    @i += name.size
                    skip
                    fail! unless @src[@i] == '=' && @src[@i + 1] != '='
                    @i += 1
                    found = [value]
                else
                    @i += 1
                end
            end
            fail! unless found
            found.first
        end

        # Für reine JSON-Dateien ohne "var name =".
        def whole
            result = value
            skip
            fail! if @i < @src.size
            result
        end
    end

    def self.read_utf8(path)
        src = File.read(path, :encoding => 'UTF-8')
        raise FormatError, 'keine gültige UTF-8-Datei' unless src.valid_encoding?
        src
    end

    def self.valid_seats?(seats)
        seats.is_a?(Array) && !seats.empty? && seats.all? do |s|
            s.is_a?(Array) && [2, 3].include?(s.size) && s.all? { |v| v.is_a?(Integer) }
        end
    end

    def self.valid_entry?(kind, entry)
        return false unless entry.is_a?(Array) && entry[0].is_a?(String)
        kind == :bff ? entry[1].is_a?(String) : true
    end

    def self.room_path(raum)
        raise FormatError, 'ungültiger Raumname' unless raum =~ ROOM_NAME
        File.join(ROOMS_DIR, "#{raum}.json")
    end

    # Die vom Dashboard verwalteten Räume. Kaputte Dateien fallen weg, statt alle
    # Sitzplan-Seiten mitzureißen.
    def self.internal_rooms
        rooms = {}
        Dir[File.join(ROOMS_DIR, '*.json')].sort.each do |path|
            raum = File.basename(path, '.json')
            begin
                seats = JSON.parse(read_utf8(path))
                raise FormatError unless raum =~ ROOM_NAME && valid_seats?(seats)
                rooms[raum] = seats
            rescue FormatError, JSON::ParserError
                STDERR.puts "Sitzplan: #{File.basename(path)} wird ignoriert, Format ungültig"
            end
        end
        rooms
    end

    # Die alten Räume aus seats.js. FormatError, wenn die Datei nicht lesbar ist.
    def self.legacy_rooms
        path = File.join(DATA_DIR, 'seats.js')
        return {} unless File.exist?(path)
        rooms = JsLiteral.new(read_utf8(path)).definition('seats_dict')
        raise FormatError, 'seats_dict ist kein Objekt' unless rooms.is_a?(Hash)
        rooms
    end

    def self.room(raum)
        rooms = internal_rooms
        return rooms[raum] if rooms[raum]
        legacy_rooms[raum]
    rescue FormatError
        nil
    end

    # JS für die Seiten: seats.js unverändert, falls noch vorhanden, darüber die
    # verwalteten Räume. So bleibt alles lauffähig, vor und nach der Umwandlung,
    # auch wenn seats.js etwas enthält, das JsLiteral nicht versteht.
    def self.seats_js
        path = File.join(DATA_DIR, 'seats.js')
        legacy = begin
            File.exist?(path) ? read_utf8(path) : nil
        rescue FormatError
            nil
        end
        parts = [legacy || 'var seats_dict = {};']
        internal_rooms.each { |raum, seats| parts << "seats_dict[#{raum.to_json}] = #{seats.to_json};" }
        parts.join("\n")
    end

    # Bestuhlung schreiben, vorherige Fassung als Sicherung behalten.
    def self.write_room(raum, seats)
        path = room_path(raum)
        WRITE_MUTEX.synchronize do
            FileUtils.mkdir_p(BACKUP_DIR)
            if File.exist?(path)
                next if (JSON.parse(read_utf8(path)) rescue nil) == seats
                stamp = Time.now.utc.strftime('%Y%m%dT%H%M%S%6NZ')
                FileUtils.cp(path, File.join(BACKUP_DIR, "#{raum}-#{stamp}.json"))
                backups = Dir[File.join(BACKUP_DIR, "#{raum}-[0-9]*.json")].sort
                FileUtils.rm(backups[0...(backups.size - BACKUPS_KEPT)]) if backups.size > BACKUPS_KEPT
            end
            write_atomic(path, seats)
        end
    end

    def self.write_atomic(path, value)
        tmp_path = "#{path}.tmp"
        File.write(tmp_path, JSON.pretty_generate(value))
        File.rename(tmp_path, path)
    end

    def self.list_path(kind)
        File.join(INTERNAL_DIR, "#{kind}.json")
    end

    # Die alte Liste aus rules.js oder bff.js/bff.json; [] wenn es keine gibt.
    def self.legacy_list(kind)
        info = LISTS[kind]
        path = info[:legacy].map { |name| File.join(DATA_DIR, name) }.find { |p| File.exist?(p) }
        return [] unless path
        src = read_utf8(path)
        entries = path.end_with?('.json') ? JsLiteral.new(src).whole : JsLiteral.new(src).definition(info[:var])
        raise FormatError, "#{info[:var]} ist keine Liste" unless entries.is_a?(Array)
        entries
    end

    # Gibt bei unlesbaren Daten eine leere Liste zurück: lieber ohne Regeln mischen,
    # als den Dateiinhalt ungefiltert an den Browser zu schicken.
    def self.list(kind)
        path = list_path(kind)
        entries = File.exist?(path) ? JSON.parse(read_utf8(path)) : legacy_list(kind)
        raise FormatError, 'keine Liste' unless entries.is_a?(Array)
        entries.select { |entry| valid_entry?(kind, entry) }
    rescue FormatError, JSON::ParserError => e
        STDERR.puts "Sitzplan: #{kind} nicht lesbar (#{e.is_a?(FormatError) ? e.message : 'JSON'})"
        []
    end
end
