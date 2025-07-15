# zip -r ../final.docx *
# unzip -d temp 5.docx
# d = Docx::Document.open('example.docx')
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.text }};
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.substitute('A', 'B') }};
# d.save('out.docx')
# lowriter --convert-to pdf [in path]
# merge PDFs: gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=merged.pdf z1.pdf z2.pdf

require './fragments/fragments.rb'

class Main < Sinatra::Base
    def self.parse_zeugnisformulare
        FileUtils.mkpath('/internal/lowriter_home')
        @@zeugnisse = {}
        @@zeugnisse[:formulare] ||= {}
        debug "Parsing Zeugnisformulare..."
        Dir["/data/zeugnisse/formulare/#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/*.docx"].each do |path|
            sha1 = Digest::SHA1.hexdigest(File.read(path))
            out_path = File.join("/internal/zeugnisse/formulare/#{sha1}")
            unless File.exist?(out_path)
                FileUtils.mkpath(File.dirname(out_path))
                system("unzip -d \"#{out_path}\" \"#{path}\"")
            end
            doc = File.read(File.join(out_path, 'word', 'document.xml'))
            tags = doc.scan(/[#\$][A-Za-z0-9_]+\./)
            key = File.basename(path).sub('.docx', '')
            # debug "#{key} (#{out_path}): #{tags.to_json}"
            @@zeugnisse[:formulare][key] ||= {}
            @@zeugnisse[:formulare][key][:sha1] = sha1
            @@zeugnisse[:formulare][key][:tags] = tags.map { |x| x[0, x.size - 1] }
            @@zeugnisse[:formulare][key][:formular_fehler] = self.check_zeugnisformular(key)
            if ZEUGNIS_HALBJAHR == '2'
                unless doc.include?('<w:strike/></w:rPr><w:t>nicht</w:t>')
                    @@zeugnisse[:formulare][key][:formular_fehler] ||= []
                    @@zeugnisse[:formulare][key][:formular_fehler] << "fehlende Versetzungsmarkierung (<s>nicht</s>)"
                end
            end
        end

        self.determine_zeugnislisten()
    end

    def self.zeugnis_key_for_email(email)
        bildungsgang = @@user_info[email][:bildungsgang]
        klassenstufe = @@user_info[email][:klassenstufe]
        if bildungsgang == :altsprachlich
            "#{klassenstufe}"
        elsif bildungsgang == :regulaer_la
            "#{klassenstufe}_regulaer_la"
        elsif bildungsgang == :regulaer_frz
            "#{klassenstufe}_regulaer_frz"
        elsif bildungsgang == :sesb
            "#{klassenstufe}_sesb"
        else
            raise 'nope'
        end
    end

    def self.zeugnis_faecher_for_emails(emails)
        zeugnis_keys = {}
        emails.each do |email|
            zeugnis_keys[self.zeugnis_key_for_email(email)] = true
        end
        faecher = []
        faecher_wf = []
        zeugnis_keys.keys.sort.each do |key|
            FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR][key].each do |fach|
                if fach[0] == '$'
                    faecher_wf << fach unless faecher_wf.include?(fach)
                else
                    faecher << fach unless faecher.include?(fach)
                end
            end
        end
        return faecher + faecher_wf
    end

    def need_sozialverhalten()
        # return true if session user has sozialnoten to enter
        return false unless user_logged_in?
        return false unless teacher_logged_in?
        return true if @@need_sozialverhalten[@session_user[:shorthand]]
        return false
    end

    def self.determine_zeugnislisten()
        @@zeugnisliste_for_klasse = {}
        @@zeugnisliste_for_lehrer = {}
        # @@need_sozialverhalten is a hash of teacher shorthands and klassen
        @@need_sozialverhalten = {}

        # STDERR.puts "ATTENTION determine_zeugnislisten() IS DOING NOTHING RIGHT NOW"
        # return

        kurse_for_klasse = Hash[ZEUGNIS_KLASSEN_ORDER.map do |klasse|
            [klasse, (@@lessons_for_klasse[klasse] || []).map { |x| @@lessons[:lesson_keys][x].merge({:lesson_key => x})}]
        end]

        delegates = {}
        delegates_for_klasse = {}
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :path => "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/")
            MATCH (n:ZeugnisDelegate)-[:WHO]->(u:User)
            WHERE n.path STARTS WITH $path
            RETURN n.path AS path, u.email AS email;
        END_OF_QUERY
        rows.each do |row|
            delegates[row['path']] ||= Set.new()
            delegates[row['path']] << row['email']
            klasse = row['path'].split('/')[2]
            delegates_for_klasse[klasse] ||= {}
            delegates_for_klasse[klasse][row['path']] ||= Set.new()
            delegates_for_klasse[klasse][row['path']] << row['email']
        end

        if ZEUGNIS_USE_MOCK_NAMES
            srand(42)
        end
        need_sv_for_klasse = {}
        need_sv_for_klasse_and_fach = {}
        ((ANLAGE_SOZIALVERHALTEN[ZEUGNIS_SCHULJAHR] || {})[ZEUGNIS_HALBJAHR] || []).each do |entry|
            if entry == '*'
                ZEUGNIS_KLASSEN_ORDER.each do |klasse|
                    need_sv_for_klasse[klasse] = true
                end
            elsif entry.include?('/')
                klasse = entry.split('/')[0]
                fach = entry.split('/')[1]
                raise "zeugnis config: unknown klasse #{entry}" unless ZEUGNIS_KLASSEN_ORDER.include?(klasse)
                need_sv_for_klasse_and_fach[entry] = true
            else
                if ZEUGNIS_KLASSEN_ORDER.include?(entry)
                    need_sv_for_klasse[entry] = true
                else
                    raise "zeugnis config: unknown klasse #{entry}"
                end
            end
        end

        ZEUGNIS_KLASSEN_ORDER.each do |klasse|
            lesson_keys_for_fach = {}
            shorthands_for_fach = {}
            # get teachers from stundenplan
            (kurse_for_klasse[klasse]).each do |kurs|
                lesson_keys_for_fach[kurs[:fach]] ||= []
                lesson_keys_for_fach[kurs[:fach]] << kurs[:lesson_key]
                fach = ZEUGNIS_CONSOLIDATE_FACH[kurs[:fach]] || kurs[:fach]
                # next unless FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR].include?(fach) || FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR].include?('$' + fach)
                shorthands = kurs[:lehrer]
                # check if we have delegate overrides
                path = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{klasse}/#{fach}"
                if delegates[path]
                    shorthands = delegates[path].to_a.map { |email| @@user_info[email][:shorthand] }
                end
                shorthands.each do |shorthand|
                    shorthands_for_fach[fach] ||= {}
                    shorthands_for_fach[fach][shorthand] = true
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}"] = true
                    if FAECHER_SPRACHEN.include?(fach)
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}_AT"] = true
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}_SL"] = true
                    end
                    if need_sv_for_klasse[klasse] || need_sv_for_klasse_and_fach["#{klasse}/#{fach}"]
                        SOZIALNOTEN_KEYS.each do |item|
                            @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/#{fach}"] = true
                        end
                        @@need_sozialverhalten[shorthand] = true
                        @@need_sozialverhalten[klasse] = true
                    end
                end
            end
            # get teachers from delegate entries
            (delegates_for_klasse[klasse] || {}).each_pair do |path, emails|
                fach = path.split('/')[3]
                # next unless FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR].include?(fach) || FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR].include?('$' + fach)
                emails.to_a.sort.each do |email|
                    shorthand = @@user_info[email][:shorthand]
                    shorthands_for_fach[fach] ||= {}
                    shorthands_for_fach[fach][shorthand] = true
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}"] = true
                    if FAECHER_SPRACHEN.include?(fach)
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}_AT"] = true
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}_SL"] = true
                    end
                    if need_sv_for_klasse[klasse] || need_sv_for_klasse_and_fach["#{klasse}/#{fach}"]
                        SOZIALNOTEN_KEYS.each do |item|
                            @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/#{fach}"] = true
                        end
                        @@need_sozialverhalten[shorthand] = true
                        @@need_sozialverhalten[klasse] = true
                    end
                end

            end
            
            @@zeugnisliste_for_klasse[klasse] = {}
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach] = {}
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach_is_delegate] = {}
            (@@klassenleiter[klasse] || []).each do |shorthand|
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] ||= []
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] << shorthand
                ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each do |item|
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}"] = true
                end
                if need_sv_for_klasse[klasse]
                    SOZIALNOTEN_KEYS.each do |item|
                        @@zeugnisliste_for_lehrer[shorthand] ||= {}
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/_KL"] = true
                    end
                    @@need_sozialverhalten[shorthand] = true
                    @@need_sozialverhalten[klasse] = true
                end
            end
            path = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{klasse}/_KL"
            if delegates[path]
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] = []
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach_is_delegate]['_KL'] = true
                delegates[path].each do |email|
                    shorthand = @@user_info[email][:shorthand]
                    @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] << shorthand
                    ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each do |item|
                        @@zeugnisliste_for_lehrer[shorthand] ||= {}
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}"] = true
                    end
                    if need_sv_for_klasse[klasse]
                        SOZIALNOTEN_KEYS.each do |item|
                            @@zeugnisliste_for_lehrer[shorthand] ||= {}
                            @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/_KL"] = true
                        end
                        @@need_sozialverhalten[shorthand] = true
                        @@need_sozialverhalten[klasse] = true
                    end
                end
            end
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] ||= []
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'].uniq!
            faecher = self.zeugnis_faecher_for_emails(@@schueler_for_klasse[klasse])
            @@zeugnisliste_for_klasse[klasse][:faecher] = faecher.map do |x|
                x[0] == '$' ? x[1, x.size - 1] : x
            end
            @@zeugnisliste_for_klasse[klasse][:faecher].uniq!
            @@zeugnisliste_for_klasse[klasse][:wahlfach] = Hash[faecher.map do |x|
                [x.sub('$', ''), x[0] == '$' ? true : false]
            end]
            @@zeugnisliste_for_klasse[klasse][:faecher].each do |fach|
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach][fach] = (shorthands_for_fach[fach] || {}).keys
                path = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{klasse}/#{fach}"
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach_is_delegate][fach] = delegates.include?(path)
            end
            @mock = {}
            if ZEUGNIS_USE_MOCK_NAMES
                @mock[:nachnamen] = JSON.parse(File.read('mock/nachnamen.json'))
                @mock[:vornamen] = {
                    'm' => JSON.parse(File.read('mock/vornamen-m.json')),
                    'w' => JSON.parse(File.read('mock/vornamen-w.json'))
                }
            end

            @@zeugnisliste_for_klasse[klasse][:index_for_schueler] ||= {}
            @@schueler_for_klasse[klasse].each.with_index do |email, index|
                @@zeugnisliste_for_klasse[klasse][:index_for_schueler][email] = index
            end

            @@zeugnisliste_for_klasse[klasse][:schueler] = @@schueler_for_klasse[klasse].map do |email|
                geschlecht = ZEUGNIS_USE_MOCK_NAMES ? ['m', 'w'].sample : @@user_info[email][:geschlecht]
                {
                    :email => email,
                    :zeugnis_key => self.zeugnis_key_for_email(email),
                    :official_first_name => ZEUGNIS_USE_MOCK_NAMES ? @mock[:vornamen][geschlecht].sample : @@user_info[email][:official_first_name],
                    :last_name => ZEUGNIS_USE_MOCK_NAMES ? @mock[:nachnamen].sample : @@user_info[email][:last_name],
                    :geburtstag => ZEUGNIS_USE_MOCK_NAMES ? sprintf("%04d-%02d-%02d", @@user_info[email][:geburtstag][0, 4].to_i, (1..12).to_a.sample, (1..28).to_a.sample) : @@user_info[email][:geburtstag],
                    :geschlecht => geschlecht,
                    :bildungsgang => Main.tr_bildungsgang(@@user_info[email][:bildungsgang]),
                    :klassenstufe => @@user_info[email][:klassenstufe],
                }
            end
        end
    end

    def self.check_zeugnisformular(key)
        unless @@zeugnisse[:formulare][key]
            return ['kein Formular vorhanden!']
        end
        required_tags = []
        wf_count = 0
        FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR][key].each do |tag|
            if tag[0] == '$'
                wf_count += 1
                required_tags << "#WF#{wf_count}"
                required_tags << "#WF#{wf_count}_Name"
                # required_tags << "##{tag[1, tag.size - 1]}"
            else
                required_tags << "##{tag}"
            end
            if DETAIL_NOTEN[key].include?(tag)
                required_tags << "##{tag}_AT"
                required_tags << "##{tag}_SL"
            end
        end
        required_tags << '#Zeugnisdatum'
        required_tags << '#Schuljahr'
        required_tags << '#Name'
        required_tags << '#Geburtsdatum'
        required_tags << '#Klasse'
        required_tags << '#VT'
        required_tags << '#VT_UE'
        required_tags << '#VS'
        required_tags << '#VS_UE'
        required_tags << '#VSP'
        required_tags << '#WeitereBemerkungen' if key.include?('sesb')
        if ZEUGNIS_HALBJAHR == '2'
            required_tags << '#Probejahr' if key == '5' || key == '7_sesb'
            required_tags << '#BBR' if key == '9' || key == '9_sesb'
            required_tags << '#MSA' if key == '10' || key == '10_sesb'
        end
        optional_tags = []

        optional_tags << '#Vorname'
        optional_tags << '#Angebote'
        optional_tags << '#Bemerkungen'
        optional_tags << '#BemerkungenAngebote'

        present_tags = Set.new(@@zeugnisse[:formulare][key][:tags])
        missing_tags = Set.new(required_tags) - present_tags
        superfluous_tags = Set.new(@@zeugnisse[:formulare][key][:tags]) - Set.new(required_tags)
        superfluous_tags -= Set.new(optional_tags)
        errors = []
        unless missing_tags.empty?
            errors << "fehlende Markierungen: #{missing_tags.join(', ')}"
        end
        unless superfluous_tags.empty?
            errors << "unbekannte Markierungen: #{superfluous_tags.join(', ')}"
        end
        return nil if errors.empty?
        if present_tags.include?('#Bemerkungen') && present_tags.include?('#Angebote') && !present_tags.include?('#BemerkungenAngebote')
        elsif !present_tags.include?('#Bemerkungen') && !present_tags.include?('#Angebote') && present_tags.include?('#BemerkungenAngebote')
        else
            errors << "Es muss entweder nur #Angebote und #Bemerkungen geben oder nur #BemerkungenAngebote."
        end
        return errors
    end

    def recurse_arrays(path_array, value_array, prefix = [], index_prefix = [], &block)
        if path_array.empty?
            yield prefix.join('/'), value_array
            return
        end
        path_entry = path_array[0]
        key = path_entry[0]
        values = path_entry[1]
        values = [values] unless values.is_a? Array
        values.each.with_index do |value, i|
            recurse_arrays(path_array[1, path_array.size - 1], value_array[i], prefix + ["#{key}:#{value}"], index_prefix + [i], &block)
        end
    end

    def parse_paths_and_values(paths, values)
        result = {}
        recurse_arrays(paths, values) do |path, value|
            result[path] = value
        end
        result
    end

    post '/api/print_zeugnis' do
        # require_zeugnis_admin!
        data = parse_request_data(
            :required_keys => [
                :schueler,
                :paths_fach, :values_fach,
                :paths_fehltage, :values_fehltage,
                :paths_ab, :values_ab,
                :format
            ],
            :types => {:schueler => Array,
                :paths_fach => Array, :values_fach => Array,
                :paths_fehltage => Array, :values_fehltage => Array,
                :paths_ab => Array, :values_ab => Array,
            },
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        cache = {}
        cache.merge!(parse_paths_and_values(data[:paths_fach], data[:values_fach]))
        cache.merge!(parse_paths_and_values(data[:paths_fehltage], data[:values_fehltage]))
        cache.merge!(parse_paths_and_values(data[:paths_ab], data[:values_ab]))

        if data[:format] == 'xlsx'
            file = Tempfile.new('foo')
            result = nil
            begin
                workbook = WriteXLSX.new(file.path)
                sheet = workbook.add_worksheet
                format_header = workbook.add_format({:bold => true})
                format_text = workbook.add_format({})
                sheet.write_string(0, 0, 'Nachname', format_header)
                sheet.write_string(0, 1, 'Vorname', format_header)
                sheet.write_string(0, 2, 'Geschlecht', format_header)
                sheet.write_string(0, 3, 'Klasse', format_header)
                sheet.write_string(0, 4, 'Geburtsdatum', format_header)
                sheet.set_column(0, 2, 16)
                sheet.set_column(3, 3, 6)
                sheet.set_column(4, 4, 16)
                # sheet.write_string(index + 1, 0, (@@user_info[email] || {})[:last_name] || 'NN')
                data[:schueler].each do |schueler|
                    parts = schueler.split('/')
                    klasse = parts[0]
                    index = @@zeugnisliste_for_klasse[klasse][:index_for_schueler][parts[1]]
                    sus_info = @@zeugnisliste_for_klasse[klasse][:schueler][index]
                    email = sus_info[:email]
                    zeugnis_key = sus_info[:zeugnis_key]
                    faecher_info = []
                    @@zeugnisliste_for_klasse[klasse][:faecher].each do |fach|
                        faecher_info << fach
                        if FAECHER_SPRACHEN.include?(fach)
                            faecher_info << "#{fach}_AT"
                            faecher_info << "#{fach}_SL"
                        end
                    end
                    wahlfach_info = @@zeugnisliste_for_klasse[klasse][:wahlfach]
                    sheet.write_string(index + 1, 0, sus_info[:last_name] || '')
                    sheet.write_string(index + 1, 1, sus_info[:official_first_name] || '')
                    sheet.write_string(index + 1, 2, sus_info[:geschlecht])
                    sheet.write_string(index + 1, 3, Main.tr_klasse(klasse) || '')
                    sheet.write_string(index + 1, 4, Date.parse(sus_info[:geburtstag]).strftime('%d.%m.%Y'))
                    faecher_info.each.with_index do |fach, i|
                        sheet.write_string(0, 5 + i, fach, format_header)
                    end
                    ['Versäumte Tage', 'unentschuldigt', 'versäumte Stunden', 'unentschuldigt', 'Verspätungen', 'Angebote', 'Bemerkungen', 'Weitere Bemerkungen'].each.with_index do |x, i|
                        sheet.write_string(0, 5 + i + faecher_info.size, x, format_header)
                    end

                    faecher_info.each.with_index do |fach, i|
                        value = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"] || '--'
                        if value
                            if value =~ /^\d[\-+]$/
                                value = "#{value.to_i}"
                            end
                            sheet.write_string(index + 1, 5 + i, value)
                        end
                    end
                    ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each.with_index do |item, i|
                        v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:#{item}/Email:#{email}"] || '--'
                        v = '--' if v == '0'
                        sheet.write_string(index + 1, 5 + faecher_info.size + i, v)
                    end
                    ['Angebote', 'Bemerkungen', 'WeitereBemerkungen'].each.with_index do |item, i|
                        v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:#{item}/Email:#{email}"] || '--'
                        sheet.write_string(index + 1, 5 + faecher_info.size + 5 + i, v)
                    end
                end
                workbook.close
                result = File.read(file.path)
            ensure
                file.close
                file.unlink
            end
            respond(:yay => 'sure', :xlsx_base64 => Base64::strict_encode64(result), :name => 'Zeugnisliste')
        else
            docx_paths = []

            merged_id = data.to_json
            merged_sha1 = Digest::SHA1.hexdigest("zeugnis_#{merged_id}").to_i(16).to_s(36)
            merged_out_path_pdf = File.join("/internal/zeugnisse/out/#{merged_sha1}.pdf")
            merged_out_path_docx = File.join("/internal/zeugnisse/out/#{merged_sha1}.docx")
            last_zeugnis_name = ''

            data[:schueler].each do |schueler|
                parts = schueler.split('/')
                klasse = parts[0]
                index = @@zeugnisliste_for_klasse[klasse][:index_for_schueler][parts[1]]
                sus_info = @@zeugnisliste_for_klasse[klasse][:schueler][index].clone
                if DEVELOPMENT
                    STDERR.puts '-' * 40
                    STDERR.puts sus_info.to_yaml
                    STDERR.puts '-' * 40
                    STDERR.puts @@zeugnisliste_for_klasse[klasse].to_yaml
                end

                email = sus_info[:email]
                zeugnis_key = sus_info[:zeugnis_key]
                faecher_info = []
                @@zeugnisliste_for_klasse[klasse][:faecher].each do |fach|
                    faecher_info << fach
                end
                faecher_info_extra = []
                faecher_info.each do |fach|
                    if FAECHER_SPRACHEN.include?(fach)
                        faecher_info_extra << "#{fach}_AT"
                        faecher_info_extra << "#{fach}_SL"
                    end
                end
                faecher_info += faecher_info_extra
                # STDERR.puts faecher_info.to_json
                zeugnis_key = Main.zeugnis_key_for_email(email)
                wahlfach_info = {}
                FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR][zeugnis_key].each do |fach|
                    if fach[0] == '$'
                        wahlfach_info[fach.sub('$', '')] = true
                    end
                end

                # wahlfach_info = @@zeugnisliste_for_klasse[klasse][:wahlfach]
                # :zeugnis_key => self.zeugnis_key_for_email(email),
                # :official_first_name => @@user_info[email][:official_first_name],
                # :last_name => @@user_info[email][:last_name],
                # :geburtstag => @@user_info[email][:geburtstag],
                # :geschlecht => @@user_info[email][:geschlecht],
                info = {}
                last_name_parts = sus_info[:last_name].split(',').map { |x| x.strip }.reverse
                name = "#{sus_info[:official_first_name]} #{last_name_parts.join(' ')}"
                info['#Name'] = name
                last_zeugnis_name = name
                info['#Vorname'] = "#{sus_info[:official_first_name]}"
                info['#Geburtsdatum'] = "#{Date.parse(sus_info[:geburtstag]).strftime('%d.%m.%Y')}"
                print_klasse = Main.tr_klasse(klasse)
                if print_klasse.include?('/')
                    parts = print_klasse.split('/').select do |x|
                        x.to_i == sus_info[:klassenstufe]
                    end
                    print_klasse = parts.first
                end
                info['#Klasse'] = print_klasse
                info['#Zeugnisdatum'] = ZEUGNIS_DATUM
                info['#Schuljahr'] = ZEUGNIS_SCHULJAHR.gsub('_', '/')
                info['@Geschlecht'] = sus_info[:geschlecht]
                wf_tr = {}
                wf_count = 0
                wf_entries = {}
                faecher_info.each do |fach|
                    if wahlfach_info[fach]
                        if (cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"] || '×') != '×'
                            wf_count += 1
                            wf_tr[fach] = "WF#{wf_count}"
                            info["#WF#{wf_count}_Name"] = "Wahlfach #{@@faecher[fach] || fach}"
                            wf_entries["#{@@faecher[fach] || fach}"] = wf_count
                        end
                    end
                end
                # TODO: Wahlfächer
                info["#WF1"] = '--'
                info["#WF2"] = '--'
                info["#WF3"] = '--'
                faecher_info.each do |fach|
                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"] || '--'
                    if note =~ /^\d[\-+]$/
                        note = "#{note.to_i}"
                    end
                    fach_tr = wf_tr[fach] || fach
                    info["##{fach_tr}"] = note
                    # Also add the note to the original fach because of hybrid klassen 9o mixup AGr / $AGr (wahlfach for some)
                    info["##{fach}"] = note
                    # Remove the note from Wahlfach entry if it's already there
                    # if wf_entries[@@faecher[fach] || fach]
                    #     info["#WF#{wf_entries[@@faecher[fach] || fach]}"] = '--'
                    #     info.delete("#WF#{wf_entries[@@faecher[fach] || fach]}_Name")
                    # end
                end
                ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each do |item|
                    v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:#{item}/Email:#{email}"] || '--'
                    v = '--' if v == '0'
                    info["##{item}"] = v
                end
                ['Angebote', 'Bemerkungen', 'WeitereBemerkungen'].each do |item|
                    v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:#{item}/Email:#{email}"] || '--'
                    info["##{item}"] = v
                end
                # handle BemerkungenAngebote
                vl = []
                vl << cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:Bemerkungen/Email:#{email}"]
                vl << cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:Angebote/Email:#{email}"]
                vl.reject! { |x| x.nil? }
                info["#BemerkungenAngebote"] = vl.size > 0 ? vl.join(" ") : '--'

                if ZEUGNIS_HALBJAHR == '2'
                    if zeugnis_key == '5' || zeugnis_key == '7_sesb' || zeugnis_key == '7_regulaer_la'|| zeugnis_key == '7_regulaer_frz'
                        if cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:Probejahr bestanden/Email:#{email}"] == 'nein'
                            if zeugnis_key == '5'
                                info['#Probejahr'] = "#{info['#Vorname']} hat die Probezeit nicht bestanden und besucht im kommenden Schuljahr die Jahrgangsstufe 6 der Primarstufe."
                            else
                                info['#Probejahr'] = "#{info['#Vorname']} hat die Probezeit nicht bestanden und besucht im kommenden Schuljahr die Jahrgangsstufe 8 der Integrierten Sekundarschule/Gemeinschaftsschule."
                            end
                        else
                            info['#Probejahr'] = "#{info['#Vorname']} hat die Probezeit bestanden."
                        end
                    elsif zeugnis_key == '9' || zeugnis_key == '9_sesb'
                        if cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:BBR/Email:#{email}"] == 'nein'
                            info['#BBR'] = ''
                        else
                            info['#BBR'] = "#{info['#Vorname']} hat mit diesem Zeugnis die Berufsbildungsreife erworben."
                        end
                    elsif zeugnis_key == '10' || zeugnis_key == '10_sesb'
                        if cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:MSA/Email:#{email}"] == 'nein'
                            info['#MSA'] = ''
                        else
                            info['#MSA'] = "#{info['#Vorname']} hat mit diesem Zeugnis den mittleren Schulabschluss erworben. Das Zeugnis berechtigt gemäß § 48 Abs. 3 Sek I-VO zum Übergang in die Qualifikationsphase der gymnasialen Oberstufe."
                        end
                    end
                end

                if DEVELOPMENT
                    STDERR.puts faecher_info.to_yaml
                    STDERR.puts cache.to_yaml
                    STDERR.puts info.to_yaml
                end
                zeugnis_id = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{zeugnis_key}/#{info.to_json}"
                zeugnis_sha1 = Digest::SHA1.hexdigest(zeugnis_id).to_i(16).to_s(36)
                debug "Printing Zeugnis for #{sus_info[:official_first_name]} #{sus_info[:last_name]} => #{zeugnis_sha1}"
                out_path_docx = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}.docx")
                out_path_pdf = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}.pdf")
                out_path_dir = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}")
                FileUtils.mkpath(out_path_dir)
                formular_sha1 = @@zeugnisse[:formulare][zeugnis_key][:sha1]
                FileUtils.cp_r("/internal/zeugnisse/formulare/#{formular_sha1}/", out_path_dir)
                doc = File.read(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'))
                @@zeugnisse[:formulare][zeugnis_key][:tags].each do |tag|
                    value = info[tag] || ''
                    if value == '×'
                        value = '--'
                    end
                    doc.gsub!("#{tag}.", value)
                end

                if ZEUGNIS_HALBJAHR == '2'
                    if cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:Versetzt/Email:#{email}"] == 'nein'
                        doc.gsub!('<w:strike/></w:rPr><w:t>nicht</w:t>', '</w:rPr><w:t>nicht</w:t>')
                    end
                end

                File.open(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'), 'w') do |f|
                    f.write doc
                end
                command = "cd \"#{File.join(out_path_dir, formular_sha1)}\"; zip -r \"#{out_path_docx}\" ."
                system(command)
                FileUtils::rm_rf(File.join(out_path_dir))
                docx_paths << out_path_docx
            end

            if data[:format] == 'docx'
                raw_docx_data = Base64::strict_encode64(File.read(docx_paths.first))
                docx_paths.each do |path|
                    FileUtils::rm_f(path)
                end

                respond(:yay => 'sure', :docx_base64 => raw_docx_data, :name => last_zeugnis_name)
            else
                command = "HOME=/internal/lowriter_home lowriter --headless --convert-to 'pdf:writer_pdf_Export:{\"ExportFormFields\":{\"type\":\"boolean\",\"value\":\"false\"}}' #{docx_paths.join(' ')} --outdir \"#{File.dirname(docx_paths.first)}\""
                STDERR.puts command
                system(command)

                # command = "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=#{merged_out_path_pdf} #{docx_paths.map { |x| x.sub('.docx', '.pdf')}.join(' ')}"
                command = "pdfunite #{docx_paths.map { |x| x.sub('.docx', '.pdf')}.join(' ')} #{merged_out_path_pdf}"
                STDERR.puts command
                system(command)
                raw_pdf_data = Base64::strict_encode64(File.read(merged_out_path_pdf))
                FileUtils::rm_f(merged_out_path_pdf)
                docx_paths.each do |path|
                    FileUtils::rm_f(path)
                    FileUtils::rm_f(path.sub('.docx', '.pdf'))
                end

                respond(:yay => 'sure', :pdf_base64 => raw_pdf_data, :name => last_zeugnis_name)
            end
        end
    end

    post '/api/zeugnis_delegate' do
        require_zeugnis_admin!
        data = parse_request_data(:required_keys => [:klasse, :fach, :shorthands])
        emails = Set.new()
        data[:shorthands].split(',').each do |shorthand|
            emails << @@shorthands[shorthand.strip]
        end
        debug "zeugnis_delegate: #{data[:klasse]} / #{data[:fach]} / #{emails.to_a.to_json}"
        path = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{data[:klasse]}/#{data[:fach]}"
        transaction do
            neo4j_query(<<~END_OF_QUERY, :path => path)
                MATCH (n:ZeugnisDelegate {path: $path})
                DETACH DELETE n;
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, :path => path, :emails => emails.to_a)
                MERGE (n:ZeugnisDelegate {path: $path})
                WITH n
                MATCH (u:User) WHERE u.email IN $emails
                CREATE (n)-[:WHO]->(u);
            END_OF_QUERY
        end
        self.class.determine_zeugnislisten()
    end

    post '/api/print_zeugniskonferenz_sheets' do
        require_zeugnis_admin!
        data = parse_request_data(
            :required_keys => [
                :paths, :values
            ],
            :types => {:schueler => Array,
                :paths => Array, :values => Array,
            },
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        cache = {}
        (0...data[:paths].size).each do |i|
            cache.merge!(parse_paths_and_values(data[:paths][i], data[:values][i]))
        end

        # File.open('/internal/zeugniskonferenz_cache.json', 'w') do |f|
        #     f.write(cache.to_json)
        # end

        respond(:yay => 'sure', :pdf_base64 => Base64.strict_encode64(get_zeugniskonferenz_sheets_pdf(cache)), :name => 'Zeugniskonferenzen.pdf')
    end

    post '/api/print_zeugnislisten_sheets' do
        require_teacher!
        data = parse_request_data(
            :required_keys => [
                :paths, :values
            ],
            :optional_keys => [:klasse],
            :types => {:schueler => Array,
                :paths => Array, :values => Array,
            },
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        if data[:klasse]
            assert(@session_user[:klassenleitung].include?(data[:klasse]) || zeugnis_admin_logged_in?)
        else
            require_zeugnis_admin!
        end
        cache = {}
        (0...data[:paths].size).each do |i|
            cache.merge!(parse_paths_and_values(data[:paths][i], data[:values][i]))
        end

        # if DEVELOPMENT
        #     File.open('/internal/zeugniskonferenz_cache.json', 'w') do |f|
        #         f.write(cache.to_json)
        #     end
        # end

        filename = 'Zeugnislisten.pdf'
        if data[:klasse]
            filename = "Zeugnisliste Klasse #{tr_klasse(data[:klasse])}.pdf"
        end
        respond(:yay => 'sure', :pdf_base64 => Base64.strict_encode64(get_zeugnislisten_sheets_pdf(cache, data[:klasse])), :name => filename)
    end

    post '/api/print_fehlzeiten_sheets' do
        require_zeugnis_admin!
        data = parse_request_data(
            :required_keys => [
                :paths, :values
            ],
            :types => {:schueler => Array,
                :paths => Array, :values => Array,
            },
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        cache = {}
        (0...data[:paths].size).each do |i|
            cache.merge!(parse_paths_and_values(data[:paths][i], data[:values][i]))
        end

        # File.open('/internal/zeugniskonferenz_cache.json', 'w') do |f|
        #     f.write(cache.to_json)
        # end

        respond(:yay => 'sure', :pdf_base64 => Base64.strict_encode64(get_fehlzeiten_sheets_pdf(cache)), :name => 'Fehlzeitenstatistik.pdf')
    end

    post '/api/print_sozialzeugnis' do
        # require_zeugnis_admin!
        data = parse_request_data(
            :required_keys => [
                :paths, :values, :klasse
            ],
            :types => {:schueler => Array,
                :paths => Array, :values => Array,
            },
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        cache = {}
        cache.merge!(parse_paths_and_values(data[:paths], data[:values]))

        # File.open('/internal/zeugniskonferenz_cache.json', 'w') do |f|
        #     f.write(cache.to_json)
        # end

        respond(:yay => 'sure', :pdf_base64 => Base64.strict_encode64(get_sozialzeugnis_pdf(data[:klasse], cache)), :name => 'Zeugniskonferenzen.pdf')
    end

    post '/api/get_at_overview' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:klasse_or_lesson_key])
        klasse_or_lesson_key = data[:klasse_or_lesson_key]
        data = {}
        neo4j_query(<<~END_OF_QUERY, {:first_school_day => @@config[:first_school_day], :lesson_key => klasse_or_lesson_key}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:AT)-[:REGARDING]->(l:Lesson {key: $lesson_key})
            WHERE at.datum >= $first_school_day
            RETURN l.key, us.email, at
            ORDER BY at.datum;
        END_OF_QUERY
            email = row['us.email']
            data[email] ||= []
            entry = row['at']
            entry['type'] = 'at'
            data[email] << entry
        end
        neo4j_query(<<~END_OF_QUERY, {:ts => Date.parse(@@config[:first_school_day]).to_time.to_i, :lesson_key => klasse_or_lesson_key, :email => @session_user[:email]}).each do |row|
            MATCH (t:User {email: $email})<-[:SENT_BY]-(m:Mail)-[:SENT_TO]->(u:User)
            MATCH (m)-[:REGARDING]->(li:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WHERE m.ts >= $ts
            RETURN t.email, m, u.email, l.key;
        END_OF_QUERY
            email = row['u.email']
            data[email] ||= []
            entry = row['m']
            entry['type'] = 'mail'
            entry['datum'] = Time.at(row['m'][:ts]).strftime('%Y-%m-%d')
            data[email] << entry
        end

        respond(:sus => data)
    end

end

