# Converts a student export from LUSD (CSV or Excel) into the format of
# schueler/ASCII.TXT that Parser#parse_schueler reads, and compares the
# result with the current file.
#
# Plain Ruby without gems (csv, zlib, rexml), so the script in
# src/scripts/lusd-to-ascii.rb runs on the host as well as in the container.
#
# The report only contains counts, row numbers and class names – names only
# when asked for explicitly (show_names), since it is printed to a terminal.

require 'csv'
require 'date'
require_relative 'nachname'
require 'zlib'
require 'rexml/document'

module LusdImport
    class Error < StandardError; end

    # Normalised header (see .header_key) => field
    HEADERS = {
        'nachname' => :nachname, 'familienname' => :nachname, 'name' => :nachname,
        'schuelernachname' => :nachname,
        'vorname' => :vorname, 'vornamen' => :vorname, 'schuelervorname' => :vorname,
        'rufname' => :rufname,
        'namensvorsatz' => :vorsatz, 'vorsatzwort' => :vorsatz, 'namenszusatz' => :vorsatz,
        'klasse' => :klasse, 'klassenbezeichnung' => :klasse, 'klassekurs' => :klasse,
        'klassengruppe' => :klasse, 'lerngruppe' => :klasse, 'klassename' => :klasse,
        'geschlecht' => :geschlecht,
        'geburtsdatum' => :geburtsdatum, 'gebdatum' => :geburtsdatum,
        'geburtstag' => :geburtsdatum,
        # the year when there is no class (upper school): "11/1" => 11
        'stufesemester' => :stufe, 'jahrgangsstufe' => :stufe, 'stufe' => :stufe,
        'jahrgang' => :stufe,
        # for the Bildungsgang (see .bildungsgang)
        'schulformkurz' => :schulform, 'schulform' => :schulform,
        'fremdsprache' => :fremdsprache, 'fremdsprachen' => :fremdsprache,
        # the order of the languages (who has Latin and French: which came
        # first) – a number per language row, or the languages in order
        'sprachenfolge' => :sprachenfolge, 'schuelersprachenfolge' => :sprachenfolge,
        'sprachfolge' => :sprachenfolge, 'fremdsprachenfolge' => :sprachenfolge,
        # the LUSD query field "Schueler_Fremdsprache_Rang": 1, 2, 3, …
        # (0 for placeholders like "Platzhalter Fremdsprache 1")
        'fremdspracherang' => :sprachenfolge, 'sprachenrang' => :sprachenfolge,
        # not read: LUSD's "Schueler_Schluessel" is not stable from one export
        # to the next (2026-11-23) – recognising students by it would give
        # them someone else's account
        # 11/12: who checks a student's data before a switch
        # (review/2026-11/student-data-review.md) – recognised, not used yet
        'tutor' => :tutor, 'tutorin' => :tutor, 'tutorkuerzel' => :tutor, 'tutorname' => :tutor,
        'schuelertutor' => :tutor, 'tutorlehrer' => :tutor,
    }
    # one row per foreign language: these columns don't make a row different
    PER_ROW = [:fremdsprache, :sprachenfolge]
    # languages as they may stand abbreviated in a Sprachenfolge
    LANGUAGE_NAMES = {
        'e' => 'Englisch', 'en' => 'Englisch', 'eng' => 'Englisch', 'englisch' => 'Englisch',
        'l' => 'Latein', 'la' => 'Latein', 'lat' => 'Latein', 'latein' => 'Latein',
        'f' => 'Französisch', 'fr' => 'Französisch', 'frz' => 'Französisch', 'französisch' => 'Französisch',
        'g' => 'Altgriechisch', 'gr' => 'Altgriechisch', 'agr' => 'Altgriechisch', 'griechisch' => 'Altgriechisch', 'altgriechisch' => 'Altgriechisch',
        'ngr' => 'Neugriechisch', 'neugriechisch' => 'Neugriechisch',
        'r' => 'Russisch', 'ru' => 'Russisch', 'russisch' => 'Russisch',
        's' => 'Spanisch', 'sp' => 'Spanisch', 'spa' => 'Spanisch', 'spanisch' => 'Spanisch',
    }
    REQUIRED = [:nachname, :vorname, :klasse, :geschlecht, :geburtsdatum]
    FIELD_LABELS = {
        :nachname => 'Nachname', :vorname => 'Vorname', :klasse => 'Klasse',
        :geschlecht => 'Geschlecht', :geburtsdatum => 'Geburtsdatum',
    }
    GENDER = {
        'm' => 'm', 'männlich' => 'm', 'maennlich' => 'm', 'male' => 'm',
        'w' => 'w', 'weiblich' => 'w', 'f' => 'w', 'female' => 'w',
        'd' => 'd', 'divers' => 'd',
    }

    # Bildungsgang from LUSD's school form and the foreign languages:
    # SESB, altsprachlich (GYM_AS_…), otherwise regular with Latin or French
    # as second language. With both, the one that came first when the export
    # gives the order (all languages in one cell, "Schueler_Fremdsprachen"),
    # else just regular. Willkommensklasse and the like: none.
    def self.bildungsgang(schulform, sprachen, ordered = false)
        form = schulform.to_s.upcase
        return nil if form.empty?
        return 'sesb' if form.start_with?('SESB')
        return 'altsprachlich' if form.start_with?('GYM_AS')
        return nil unless form.start_with?('GYM')
        la = sprachen.include?('Latein')
        frz = sprachen.include?('Französisch')
        return 'regulaer_la' if la && !frz
        return 'regulaer_frz' if frz && !la
        if la && frz && ordered
            return sprachen.index('Latein') < sprachen.index('Französisch') ? 'regulaer_la' : 'regulaer_frz'
        end
        'regulaer'
    end

    Student = Struct.new(:row, :nachname, :vorname, :klasse, :lusd_klasse,
                         :geschlecht, :geburtsdatum, :rufname, :schulform, :sprachen,
                         :bildungsgang, :email, :email_note, :old_klasse, :matched_by, :email_taken, :email_custom,
                         :folge, :klasse_hand, keyword_init: true) do
        # Same rule as Parser#handle_schueler_line: the e-mail address is
        # built from this and the Nachname.
        def effective_rufname
            LusdImport.effective_rufname(vorname, rufname)
        end

        def line
            # 6 Rufname, 7 Bildungsgang, 8 address, 9 LUSD id (all optional,
            # empty in between)
            parts = [nachname, vorname, klasse, geschlecht, geburtsdatum || '', rufname || '', bildungsgang || '', email || '']
            parts.pop while parts.size > 5 && parts.last.empty?
            parts.join("\t")
        end
    end

    def self.effective_rufname(vorname, rufname)
        return rufname unless (rufname || '').strip.empty?
        first = vorname.split(' ').first
        first == 'Ka' ? vorname : first
    end

    def self.header_key(s)
        s.to_s.downcase.unicode_normalize(:nfc)
         .gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('ß', 'ss').gsub(/[^a-z]/, '')
    end

    # LUSD names its fields Quelle_Feld, e.g. "Schüler_Nachname" or
    # "Klassen_Klassenbezeichnung". Returns [field, rank] – a lower rank wins
    # when several columns fit: the heading itself, then the part after the
    # underscore of the student's or class fields, then that of any other
    # field (e.g. a parent's "Ansprechpartner_Nachname").
    def self.header_field(cell)
        key = header_key(cell)
        return [HEADERS[key], 0] if HEADERS[key]
        # "Schueler_Schulform_kurz": "Schulform_kurz", then "kurz"
        parts = cell.to_s.split('_')
        (1...parts.size).each do |j|
            field = HEADERS[header_key(parts[j..].join('_'))]
            next unless field
            return [field, header_key(parts[0, j].join('_')) =~ /\A(schueler|klassen?)/ ? 1 : 2]
        end
        nil
    end

    def self.clean(s)
        s.to_s.unicode_normalize(:nfc).gsub(/[[:space:]]+/, ' ').strip
    end

    # '05a' => '5a', '5 A' => '5a', 'Q1' => 'q1'
    def self.normalize_klasse(s)
        clean(s).gsub(' ', '').downcase.sub(/\A0+(?=\d)/, '')
    end

    # ---------- reading ----------

    def self.read_rows(path)
        data = File.binread(path)
        data[0, 4] == "PK\x03\x04".b ? xlsx_rows(data) : csv_rows(data)
    end

    def self.csv_rows(data)
        text = data.dup.force_encoding('UTF-8')
        text = data.dup.force_encoding('Windows-1252').encode('UTF-8') unless text.valid_encoding?
        text = text.delete_prefix("\uFEFF")
        head = text.each_line.first(20)
        sep = [';', "\t", ','].max_by { |c| head.map { |l| l.count(c) }.max.to_i }
        CSV.parse(text, col_sep: sep, liberal_parsing: true).map { |r| r.map { |c| c.to_s } }
    end

    # Minimal zip reader (central directory, stored or deflated entries).
    class Zip
        def initialize(data)
            @data = data
            eocd = data.rindex("PK\x05\x06".b)
            raise Error, 'Die Excel-Datei ist beschädigt (kein Zip).' unless eocd
            count, _size, offset = data[eocd + 10, 10].unpack('vVV')
            @entries = {}
            count.times do
                raise Error, 'Die Excel-Datei ist beschädigt.' unless data[offset, 4] == "PK\x01\x02".b
                method, = data[offset + 10, 2].unpack('v')
                csize, _usize, nlen, xlen, clen = data[offset + 20, 14].unpack('VVvvv')
                local, = data[offset + 42, 4].unpack('V')
                name = data[offset + 46, nlen].force_encoding('UTF-8')
                @entries[name] = [method, csize, local]
                offset += 46 + nlen + xlen + clen
            end
        end

        def names = @entries.keys

        def read(name)
            return nil unless @entries[name]
            method, csize, local = @entries[name]
            lnlen, lxlen = @data[local + 26, 4].unpack('vv')
            raw = @data[local + 30 + lnlen + lxlen, csize]
            out = case method
                  when 0 then raw
                  when 8 then Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)
                  else raise Error, "Unbekannte Kompression in der Excel-Datei (#{method})."
                  end
            out.force_encoding('UTF-8')
        end
    end

    # Nokogiri (in the container) is about 50 times faster than REXML for a
    # whole school; REXML keeps the script working with plain Ruby.
    def self.nokogiri?
        return @nokogiri unless @nokogiri.nil?
        @nokogiri = begin
            require 'nokogiri'
            true
        rescue LoadError
            false
        end
    end

    def self.xlsx_rows(data)
        zip = Zip.new(data)
        sheet = first_sheet_name(zip) or raise Error, 'Die Excel-Datei enthält keine Tabelle.'
        nokogiri? ? xlsx_rows_nokogiri(zip, sheet) : xlsx_rows_rexml(zip, sheet)
    end

    # LUSD exports carry many formatted but empty cells (180 per row): they
    # are skipped without XPath, which would cost seconds for a school
    def self.xlsx_rows_nokogiri(zip, sheet)
        shared = []
        if (xml = zip.read('xl/sharedStrings.xml'))
            doc = Nokogiri::XML(xml)
            doc.remove_namespaces!
            shared = doc.root.element_children.map { |si| si.xpath('.//t').map(&:text).join }
        end
        # an empty cell is always self-closing (<c r="K2" s="3"/>): dropped
        # before parsing, they don't cost anything
        doc = Nokogiri::XML(zip.read(sheet).gsub(%r{<c [^>/]*/>}, ''))
        doc.remove_namespaces!
        data = doc.root.element_children.find { |x| x.name == 'sheetData' }
        rows = []
        (data ? data.element_children : []).each do |row|
            cells = []
            row.element_children.each do |c|
                kids = c.element_children
                next if kids.empty?
                v = kids.find { |k| k.name == 'v' }
                value = xlsx_value(c['t'], v&.text, shared) { c.xpath('.//t').map(&:text).join }
                next if value.empty?
                cells[column_index(c['r']) || cells.size] = value
            end
            index = (row['r'] || (rows.size + 1)).to_i - 1
            rows[index] = cells.map(&:to_s)
        end
        rows.map { |r| r || [] }
    end

    def self.xlsx_rows_rexml(zip, sheet)
        shared = []
        if (xml = zip.read('xl/sharedStrings.xml'))
            REXML::Document.new(xml).elements.each('sst/si') do |si|
                shared << REXML::XPath.match(si, './/t').map(&:text).join
            end
        end
        rows = []
        REXML::Document.new(zip.read(sheet)).elements.each('worksheet/sheetData/row') do |row|
            cells = []
            row.elements.each('c') do |c|
                col = column_index(c.attributes['r']) || cells.size
                v = c.elements['v']&.text
                cells[col] = xlsx_value(c.attributes['t'], v, shared) { REXML::XPath.match(c, './/t').map(&:text).join }
            end
            index = (row.attributes['r'] || (rows.size + 1)).to_i - 1
            rows[index] = cells.map(&:to_s)
        end
        rows.map { |r| r || [] }
    end

    def self.xlsx_value(type, v, shared)
        case type
        when 's' then shared[v.to_i].to_s
        when 'inlineStr' then yield
        else v.to_s
        end
    end

    def self.first_sheet_name(zip)
        workbook = zip.read('xl/workbook.xml')
        rels = zip.read('xl/_rels/workbook.xml.rels')
        if workbook && rels
            sheet = REXML::Document.new(workbook).elements['workbook/sheets/sheet']
            rid = sheet&.attributes&.[]('r:id')
            REXML::Document.new(rels).elements.each('Relationships/Relationship') do |rel|
                next unless rel.attributes['Id'] == rid
                target = rel.attributes['Target']
                return target.start_with?('/') ? target[1..] : "xl/#{target}"
            end
        end
        zip.names.select { |n| n =~ %r{\Axl/worksheets/sheet\d+\.xml\z} }.min
    end

    def self.column_index(ref)
        letters = ref.to_s[/\A[A-Z]+/] or return nil
        letters.each_char.reduce(0) { |n, ch| n * 26 + ch.ord - 64 } - 1
    end

    # ---------- converting ----------

    def self.parse_date(s)
        s = clean(s)
        return nil if s.empty?
        case s
        when /\A(\d{1,2})\.(\d{1,2})\.(\d{4})\z/ then d = Date.new($3.to_i, $2.to_i, $1.to_i)
        when /\A(\d{4})-(\d{2})-(\d{2})/ then d = Date.new($1.to_i, $2.to_i, $3.to_i)
        when /\A\d+(\.0+)?\z/
            # Excel stores dates as days since 1899-12-30
            d = Date.new(1899, 12, 30) + s.to_i
        else return :invalid
        end
        d.strftime('%d.%m.%Y')
    rescue Date::Error
        :invalid
    end

    # The columns /datenpflege looks for, required or not, and what each is for
    # (shown after an upload: which are there, which are missing)
    COLUMNS = [
        [:nachname, 'Nachname', true, 'der Name'],
        [:vorname, 'Vorname', true, 'alle Vornamen, wie im Ausweis'],
        [:klasse, 'Klasse', true, 'die Klasse; in 11/12 die Stufe'],
        [:geschlecht, 'Geschlecht', true, 'm, w oder d'],
        [:geburtsdatum, 'Geburtsdatum', true, 'für Zeugnisse und um Schüler:innen wiederzuerkennen'],
        [:rufname, 'Rufname', false, 'der Name, der im Dashboard steht; ohne ihn der erste Vorname'],
        [:schulform, 'Schulform (kurz)', false, 'für den Bildungsgang (SESB, altsprachlich, regulär)'],
        [:fremdsprache, 'Fremdsprachen', false, 'für den Bildungsgang (Latein oder Französisch)'],
        [:sprachenfolge, 'Sprachenfolge', false, 'für den Bildungsgang, wenn jemand Latein und Französisch hat: welche zuerst kam'],
        [:stufe, 'Stufe / Semester', false, 'für 11 und 12, wenn die Klasse fehlt'],
        [:tutor, 'Tutor:in', false, 'wer in 11 und 12 die Daten vor der Übernahme prüft'],
    ]

    # [{:field, :label, :required, :purpose, :found => header as in the file or nil}]
    # nil without a header row
    def self.column_report(rows)
        i, columns = find_header(rows)
        return nil unless i
        header = rows[i]
        COLUMNS.map do |field, label, required, purpose|
            col = (columns || {})[field]
            { :field => field, :label => label, :required => required, :purpose => purpose,
              :found => col ? clean(header[col]) : nil }
        end
    end

    # Finds the header row and returns [index, {field => column}].
    def self.find_header(rows)
        rows.first(20).each_with_index do |row, i|
            best = {}
            row.each_with_index do |cell, col|
                field, rank = header_field(cell)
                next unless field
                best[field] = [rank, col] if best[field].nil? || rank < best[field][0]
            end
            columns = best.transform_values { |_, col| col }
            return [i, columns] if columns[:nachname] && columns[:klasse]
        end
        nil
    end

    # Returns {students:, errors:, headers:}. errors: [[row, text]] – never names.
    def self.convert(rows, klassen_map = {})
        i, columns = find_header(rows)
        unless i
            headers = rows.first(3).flatten.map { |c| clean(c) }.reject(&:empty?).first(20)
            raise Error, "Keine Kopfzeile mit Nachname und Klasse gefunden. Gefunden: #{headers.join(', ')}"
        end
        missing = REQUIRED.reject { |f| columns[f] }
        unless missing.empty?
            raise Error, "Spalten fehlen im Export: #{missing.map { |f| FIELD_LABELS[f] }.join(', ')}. " +
                         "Vorhanden: #{rows[i].map { |c| clean(c) }.reject(&:empty?).join(', ')}"
        end
        map = klassen_map.transform_keys { |k| normalize_klasse(k) }
        students = []
        errors = []
        seen = {}
        skipped = 0
        duplicates = 0
        rows[(i + 1)..].each_with_index do |row, offset|
            nr = i + offset + 2 # row number as shown in Excel
            get = ->(f) { columns[f] ? clean(row[columns[f]]) : '' }
            next if row.all? { |c| clean(c).empty? }
            # a query with e.g. the foreign languages has one row per language
            used = columns.values_at(*(HEADERS.values.uniq - PER_ROW)).compact.map { |c| clean(row[c]) }
            if seen[used]
                duplicates += 1
                if seen[used].is_a?(Student)
                    seen[used].sprachen << get.(:fremdsprache)
                    seen[used].folge << [get.(:sprachenfolge), get.(:fremdsprache)]
                end
                next
            end
            seen[used] = :error
            # LUSD fills the name particle field with a placeholder text for
            # everyone without one; real particles are lower case ("von", "de")
            vorsatz = get.(:vorsatz)
            vorsatz = '' unless vorsatz == vorsatz.downcase
            # the particle behind the name, as the dashboard keeps it (nachname.rb)
            nachname = Nachname.intern([vorsatz, get.(:nachname)].reject(&:empty?).join(' '))
            vorname = get.(:vorname)
            lusd_klasse = normalize_klasse(get.(:klasse))
            if lusd_klasse.empty? && (year = get.(:stufe)[/\A0*(\d+)/, 1])
                lusd_klasse = year
            end
            # no class and no year: not (or no longer) at school
            if lusd_klasse.empty? && get.(:stufe).empty?
                skipped += 1
                next
            end
            geschlecht_raw = get.(:geschlecht)
            geschlecht = GENDER[geschlecht_raw.downcase]
            geburtsdatum = parse_date(get.(:geburtsdatum))
            row_errors = []
            row_errors << 'Nachname fehlt' if nachname.empty?
            row_errors << 'Vorname fehlt' if vorname.empty?
            row_errors << 'Klasse fehlt' if lusd_klasse.empty?
            row_errors << "Geschlecht »#{geschlecht_raw}« (erlaubt: m, w, d)" unless geschlecht
            row_errors << 'Geburtsdatum unlesbar' if geburtsdatum == :invalid
            unless row_errors.empty?
                errors << [nr, row_errors.join(', ')]
                next
            end
            rufname = get.(:rufname)
            rufname = nil if rufname.empty? || rufname == effective_rufname(vorname, nil)
            students << Student.new(row: nr, nachname: nachname, vorname: vorname,
                                    klasse: map[lusd_klasse] || lusd_klasse,
                                    lusd_klasse: lusd_klasse, geschlecht: geschlecht,
                                    geburtsdatum: geburtsdatum, rufname: rufname,
                                    schulform: columns[:schulform] ? get.(:schulform) : nil,
                                    sprachen: [get.(:fremdsprache)],
                                    folge: [[get.(:sprachenfolge), get.(:fremdsprache)]])
            seen[used] = students.last
        end
        students.each do |s|
            # "Englisch, Latein, Französisch" in one cell: in that order
            ordered = s.sprachen.any? { |x| x =~ /[,;\/]/ }
            s.sprachen = s.sprachen.flat_map { |x| x.split(/\s*[,;\/]\s*/) }.map { |x| clean(x) }.reject(&:empty?).uniq
            s.sprachen = s.sprachen.sort unless ordered
            # a Sprachenfolge decides the order: a number per language row
            # ("2", "2. Fremdsprache"), or the languages in order in one cell
            numbered = s.folge.filter_map { |pos, lang| [$1.to_i, clean(lang)] if pos.to_s =~ /\A\s*(\d+)/ && !clean(lang).empty? }
            listed = s.folge.map(&:first).find { |pos| pos.to_s =~ /[[:alpha:]]{1,}/ && pos.to_s !~ /\A\s*\d/ }
            if numbered.size > 1
                order = numbered.sort_by(&:first).map(&:last).uniq
                s.sprachen = order + (s.sprachen - order)
                ordered = true
            elsif listed
                order = listed.split(/[\s,;\/\-–>]+/).filter_map { |x| LANGUAGE_NAMES[x.downcase] || (x.length > 3 ? x.capitalize : nil) }.uniq
                unless order.empty?
                    s.sprachen = order + (s.sprachen - order)
                    ordered = true
                end
            end
            s.bildungsgang = bildungsgang(s.schulform, s.sprachen, ordered) if s.schulform
        end
        { students: students, errors: errors, skipped: skipped, duplicates: duplicates }
    end

    def self.klasse_sort_key(k)
        [k[/\A\d+/] ? 0 : 1, k.to_i, k]
    end

    def self.ascii_txt(students)
        students.sort_by { |s| [klasse_sort_key(s.klasse), s.nachname, s.vorname] }
                .map { |s| s.line + "\n" }.join
    end

    # ---------- comparing with the current ASCII.TXT ----------

    def self.read_current(path)
        File.read(path, encoding: 'UTF-8').each_line.filter_map do |line|
            next if line.strip.empty? || line.strip[0] == '#'
            p = line.chomp.split("\t").map { |x| clean(x) }
            geb = parse_date(p[4])
            Student.new(nachname: p[0].to_s, vorname: p[1].to_s, klasse: p[2].to_s,
                        geschlecht: p[3].to_s, geburtsdatum: geb == :invalid ? nil : geb,
                        rufname: (p[5].nil? || p[5].empty?) ? nil : p[5])
        end
    end

    def self.match_key(name, geb)
        [name.to_s.downcase, geb]
    end

    # Pairs new and old students: by Nachname + Geburtsdatum, then by first
    # Vorname + Geburtsdatum (a changed or extended Nachname).
    def self.match(new_students, old_students)
        pairs = []
        rest_old = old_students.dup
        rest_new = new_students.dup
        [->(s) { match_key(s.nachname, s.geburtsdatum) },
         ->(s) { match_key(s.vorname.split(' ').first, s.geburtsdatum) }].each do |key|
            index = rest_old.group_by(&key)
            rest_new = rest_new.reject do |s|
                candidates = index[key.(s)] || []
                candidates = candidates.select { |o| o.vorname.downcase == s.vorname.downcase } if candidates.size > 1
                next false unless candidates.size == 1 && s.geburtsdatum
                old = candidates.first
                index[key.(s)].delete(old)
                rest_old.delete(old)
                pairs << [s, old]
                true
            end
        end
        { pairs: pairs, only_new: rest_new, only_old: rest_old }
    end

    def self.report(result, old_students: nil, show_names: false)
        students = result[:students]
        out = []
        out << "#{students.size} Schüler:innen gelesen."
        out << "#{result[:duplicates]} doppelte Zeilen zusammengefasst (z. B. eine je Fremdsprache)." if result[:duplicates].to_i > 0
        out << "#{result[:skipped]} Zeilen ohne Klasse und Stufe übersprungen." if result[:skipped].to_i > 0
        unless result[:errors].empty?
            out << ''
            out << "#{result[:errors].size} Zeilen mit Fehlern (es wird keine Datei geschrieben):"
            result[:errors].first(30).each { |nr, text| out << "  Zeile #{nr}: #{text}" }
            out << "  …" if result[:errors].size > 30
        end
        new_by = students.group_by(&:klasse).transform_values(&:size)
        if old_students.nil?
            out << ''
            out << 'Klasse   Anzahl'
            new_by.keys.sort_by { |k| klasse_sort_key(k) }.each { |k| out << format('%-8s %6d', k, new_by[k]) }
            return out.join("\n")
        end

        old_by = old_students.group_by(&:klasse).transform_values(&:size)
        m = match(students, old_students)
        out << ''
        out << 'Klasse   bisher    neu  Differenz'
        (old_by.keys | new_by.keys).sort_by { |k| klasse_sort_key(k) }.each do |k|
            o, n = old_by[k] || 0, new_by[k] || 0
            flag = o.zero? ? '  neue Klasse' : (n.zero? ? '  fehlt im Export' : '')
            out << format('%-8s %6d %6d %+10d%s', k, o, n, n - o, flag)
        end
        out << format('%-8s %6d %6d %+10d', 'Summe', old_students.size, students.size,
                      students.size - old_students.size)
        unless (new_by.keys - old_by.keys).empty?
            out << 'Neue Klassen nimmt das Dashboard nur auf, wenn sie in KLASSEN_ORDER stehen.'
        end

        out << ''
        out << "Zugeordnet: #{m[:pairs].size}, nur im Export: #{m[:only_new].size}, " +
               "nur in der bisherigen Datei: #{m[:only_old].size}"

        # Which old class do the students of each LUSD class come from?
        moves = Hash.new { |h, k| h[k] = Hash.new(0) }
        m[:pairs].each { |s, o| moves[s.lusd_klasse][o.klasse] += 1 }
        suggestions = []
        changed = moves.select { |lusd, olds| olds.keys != [students.find { |s| s.lusd_klasse == lusd }.klasse] }
        unless changed.empty?
            out << ''
            out << 'Klassen, deren Schüler:innen bisher anders eingetragen waren:'
            changed.keys.sort_by { |k| klasse_sort_key(k) }.each do |lusd|
                olds = changed[lusd].sort_by { |_, n| -n }
                total = olds.sum { |_, n| n }
                out << "  #{lusd} im Export: " + olds.map { |k, n| "#{n} bisher in #{k}" }.join(', ')
                best, n = olds.first
                suggestions << "--klasse #{lusd}=#{best}" if n >= total * 0.9
            end
            unless suggestions.empty?
                out << "  Vorschlag (bei gleichem Schuljahr): #{suggestions.join(' ')}"
            end
        end

        address = m[:pairs].select do |s, o|
            s.nachname != o.nachname || s.effective_rufname != o.effective_rufname
        end
        spelling = m[:pairs].select do |s, o|
            !address.include?([s, o]) && s.vorname != o.vorname
        end
        geschlecht = m[:pairs].count { |s, o| s.geschlecht != o.geschlecht }
        out << ''
        out << "Rufname oder Nachname anders (bekämen eine neue E-Mail-Adresse): #{address.size}"
        out << "Nur weitere Vornamen anders geschrieben: #{spelling.size}"
        out << "Geschlecht anders: #{geschlecht}"
        if show_names && !address.empty?
            out << ''
            out << 'Neue Adresse, bisher -> Export:'
            address.each do |s, o|
                out << "  Zeile #{s.row}: #{o.effective_rufname} #{o.nachname} -> #{s.effective_rufname} #{s.nachname}"
            end
        elsif !address.empty?
            out << '  (mit --namen werden sie aufgelistet)'
        end
        out.join("\n")
    end
end
