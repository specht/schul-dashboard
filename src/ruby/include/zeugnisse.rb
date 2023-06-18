# zip -r ../final.docx *
# unzip -d temp 5.docx
# d = Docx::Document.open('example.docx')
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.text }};
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.substitute('A', 'B') }};
# d.save('out.docx')
# lowriter --convert-to pdf [in path]
# merge PDFs: gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=merged.pdf z1.pdf z2.pdf

class Prawn::Document
    def elide_string(s, width, style = {}, suffix = '…')
        return '' if width <= 0
        return s if width_of(s, style) <= width
        suffix_width = width_of(suffix, style)
        width -= suffix_width
        length = s.size
        i = 0
        l = s.size
        r = l
        while width_of(s[0, l], style) > width
            r = l
            l /= 2
        end
        i = 0
        while l < r - 1 do
            m = (l + r) / 2
            if width_of(s[0, m], style) > width
                r = m
            else
                l = m
            end
            i += 1
            break if (i > 1000)
        end
        s[0, l].strip + suffix
    end
end

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
            debug "#{key} (#{out_path}): #{tags.to_json}"
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
        sesb = @@user_info[email][:sesb] || false
        klassenstufe = @@user_info[email][:klassenstufe]
        return "#{klassenstufe}#{sesb ? '_sesb': ''}"
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

    def self.determine_zeugnislisten()
        @@all_zeugnis_faecher = Set.new()
        FAECHER_FOR_ZEUGNIS[ZEUGNIS_SCHULJAHR][ZEUGNIS_HALBJAHR].each_pair do |key, faecher|
            faecher.each do |fach|
                @@all_zeugnis_faecher << fach.sub('$', '')
            end
        end

        @@zeugnisliste_for_klasse = {}
        @@zeugnisliste_for_lehrer = {}

        kurse_for_klasse = Hash[ZEUGNIS_KLASSEN_ORDER.map do |klasse|
            [klasse, @@lessons_for_klasse[klasse].map { |x| @@lessons[:lesson_keys][x].merge({:lesson_key => x})}]
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
        ZEUGNIS_KLASSEN_ORDER.each do |klasse|
            lesson_keys_for_fach = {}
            shorthands_for_fach = {}
            # get teachers from stundenplan
            (kurse_for_klasse[klasse]).each do |kurs|
                next unless @@all_zeugnis_faecher.include?(kurs[:fach])
                lesson_keys_for_fach[kurs[:fach]] ||= []
                lesson_keys_for_fach[kurs[:fach]] << kurs[:lesson_key]
                fach = ZEUGNIS_CONSOLIDATE_FACH[kurs[:fach]] || kurs[:fach]
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
                    ['ZV', 'LLB', 'SSK', 'KF', 'SV'].each do |item|
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/#{fach}"] = true
                    end
                end
            end
            # get teachers from delegate entries
            (delegates_for_klasse[klasse] || {}).each_pair do |path, emails|
                fach = path.split('/')[3]
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
                    ['ZV', 'LLB', 'SSK', 'KF', 'SV'].each do |item|
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/#{fach}"] = true
                    end
                end

            end
            
            @@zeugnisliste_for_klasse[klasse] = {}
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach] = {}
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach_is_delegate] = {}
            @@klassenleiter[klasse].each do |shorthand|
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] ||= []
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]['_KL'] << shorthand
                ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each do |item|
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}"] = true
                end
                ['ZV', 'LLB', 'SSK', 'KF', 'SV'].each do |item|
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/_KL"] = true
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
                    ['ZV', 'LLB', 'SSK', 'KF', 'SV'].each do |item|
                        @@zeugnisliste_for_lehrer[shorthand] ||= {}
                        @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{item}/_KL"] = true
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
                # wf_count += 1
                # required_tags << "$WF#{wf_count}"
                # required_tags << "##{wf_count}"
                required_tags << "##{tag[1, tag.size - 1]}"
            else
                required_tags << "##{tag}"
            end
            if DETAIL_NOTEN[key].include?(tag)
                required_tags << "##{tag}_AT"
                required_tags << "##{tag}_SL"
            end
        end
        required_tags << '#Zeugnisdatum'
        required_tags << '#Name'
        required_tags << '#Geburtsdatum'
        required_tags << '#Klasse'
        required_tags << '#VT'
        required_tags << '#VT_UE'
        required_tags << '#VS'
        required_tags << '#VS_UE'
        required_tags << '#VSP'
        required_tags << '#Angebote'
        required_tags << '#Bemerkungen'
        optional_tags = []

        optional_tags << '#Wahlpflicht_1'
        optional_tags << '#Wahlpflicht_2'
        optional_tags << '#Wahlpflicht_3'

        optional_tags << '#Wahlpflicht_1_Note'
        optional_tags << '#Wahlpflicht_2_Note'
        optional_tags << '#Wahlpflicht_3_Note'
        optional_tags << '#Vorname'

        missing_tags = Set.new(required_tags) - Set.new(@@zeugnisse[:formulare][key][:tags])
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
        # debug cache.to_yaml
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
            sus_info = @@zeugnisliste_for_klasse[klasse][:schueler][index]
            email = sus_info[:email]
            zeugnis_key = sus_info[:zeugnis_key]
            faecher_info = @@zeugnisliste_for_klasse[klasse][:faecher]
            faecher_info_extra = []
            faecher_info.each do |fach|
                if FAECHER_SPRACHEN.include?(fach)
                    faecher_info_extra << "#{fach}_AT"
                    faecher_info_extra << "#{fach}_SL"
                end
            end
            faecher_info += faecher_info_extra
            STDERR.puts faecher_info.to_json
            wahlfach_info = @@zeugnisliste_for_klasse[klasse][:wahlfach]
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
            info['#Klasse'] = Main.tr_klasse(klasse)
            info['#Zeugnisdatum'] = ZEUGNIS_DATUM
            info['@Geschlecht'] = sus_info[:geschlecht]
            faecher_info.each do |fach|
                note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"] || '--'
                if note =~ /^\d[\-+]$/
                    note = "#{note.to_i}"
                end
                info["##{fach}"] = note
            end
            ['VT', 'VT_UE', 'VS', 'VS_UE', 'VSP'].each do |item|
                v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fehltage:#{item}/Email:#{email}"] || '--'
                v = '--' if v == '0'
                info["##{item}"] = v
            end
            ['Angebote', 'Bemerkungen'].each do |item|
                v = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/AB:#{item}/Email:#{email}"] || '--'
                info["##{item}"] = v
            end
            # TODO: Wahlfächer
            info["#Wahlpflicht_1_Note"] = '--'
            info["#Wahlpflicht_2_Note"] = '--'
            info["#Wahlpflicht_3_Note"] = '--'
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
            # TODO: Fix this
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
            command = "HOME=/internal/lowriter_home lowriter --convert-to pdf #{docx_paths.join(' ')} --outdir \"#{File.dirname(docx_paths.first)}\""
            system(command)

            command = "gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile=#{merged_out_path_pdf} #{docx_paths.map { |x| x.sub('.docx', '.pdf')}.join(' ')}"
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

        # CUT HERE ------------------------>

        klassen_for_shorthands = {}
        consider_sus_for_klasse = {}

        ZEUGNIS_KLASSEN_ORDER.each do |klasse|
            consider_sus_for_klasse[klasse] = Set.new()
            liste = @@zeugnisliste_for_klasse[klasse]
            # faecher, lehrer_for_fach, schueler, index_for_schueler, FAECHER_SPRACHEN
            liste[:lehrer_for_fach].each_pair do |fach, shorthands|
                shorthands.each do |shorthand|
                    klassen_for_shorthands[shorthand] ||= Set.new()
                    klassen_for_shorthands[shorthand] << klasse
                end
            end
            liste[:schueler].each do |schueler|
                # STDERR.puts schueler.to_yaml
                email = schueler[:email]
                first_name = schueler[:official_first_name]
                last_name = schueler[:last_name]
                liste[:faecher].each do |fach|
                    sub_faecher = [fach]
                    if FAECHER_SPRACHEN.include?(fach)
                        sub_faecher << "#{fach}_AT"
                        sub_faecher << "#{fach}_SL"
                    end
                    sub_faecher.each do |sub_fach|
                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{sub_fach}/Email:#{email}"]
                        if NOTEN_MARK.include?(note)
                            consider_sus_for_klasse[klasse] << email
                        end
                    end
                end
                zk_marked = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/ZK:marked/Email:#{email}"]
                if zk_marked
                    consider_sus_for_klasse[klasse] << email
                end
            end
            consider_sus_for_klasse[klasse] = consider_sus_for_klasse[klasse].to_a.sort do |a, b|
                @@zeugnisliste_for_klasse[klasse][:index_for_schueler][a] <=> @@zeugnisliste_for_klasse[klasse][:index_for_schueler][b]
            end
        end

        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :landscape, :margin => 0) do
            font_families.update("RobotoCondensed" => {
                :normal => "/app/fonts/RobotoCondensed-Regular.ttf",
                :italic => "/app/fonts/RobotoCondensed-Italic.ttf",
                :bold => "/app/fonts/RobotoCondensed-Bold.ttf",
                :bold_italic => "/app/fonts/RobotoCondensed-BoldItalic.ttf"
            })
            font_families.update("Roboto" => {
                :normal => "/app/fonts/Roboto-Regular.ttf",
                :italic => "/app/fonts/Roboto-Italic.ttf",
                :bold => "/app/fonts/Roboto-Bold.ttf",
                :bold_italic => "/app/fonts/Roboto-BoldItalic.ttf"
            })
            first_page = true
            line_width 0.1.mm
            font('Roboto') do
                klassen_for_shorthands.keys.sort do |a, b|
                    a.downcase <=> b.downcase
                end.each do |shorthand|
                    ZEUGNIS_KLASSEN_ORDER.each do |klasse|
                        next unless klassen_for_shorthands[shorthand].include?(klasse)
                        next if consider_sus_for_klasse[klasse].empty?
                        liste = @@zeugnisliste_for_klasse[klasse]
                        nr_width = 8.mm
                        name_width = 4.cm
                        fach_width = (267.mm - (nr_width + name_width)) / liste[:faecher].size
                        n_klasse = consider_sus_for_klasse[klasse].size
                        n_per_page = 10
                        n_pages = ((n_klasse - 1) / n_per_page).floor + 1
                        page = 0
                        offset = 0
                        while n_klasse > 0 do
                            page += 1
                            start_new_page unless first_page
                            first_page = false
                            font('Roboto') do
                                bounding_box([15.mm, 197.mm], width: 2.5.cm, height: 1.5.cm) do
                                    move_down 4.mm
                                    text "<b>#{Main.tr_klasse(klasse)}</b>", :align => :center, :inline_format => true, :size => 24
                                    stroke_bounds
                                end
                                bounding_box([257.mm, 197.mm], width: 2.5.cm, height: 1.5.cm) do
                                    move_down 4.mm
                                    text "<b>#{shorthand}</b>", :align => :center, :inline_format => true, :size => 24
                                    stroke_bounds
                                end
                            end
                            bounding_box([15.mm, 210.mm - 13.mm], width: 267.mm, height: 18.cm) do
                                float do
                                    text "<b>Anlage zum Protokoll der Zeugniskonferenz</b>", :align => :center, :inline_format => true
                                    move_down(1.mm)
                                    text "#{ZEUGNIS_HALBJAHR}. Halbjahr, Schuljahr #{ZEUGNIS_SCHULJAHR.gsub('_', '/')}", :align => :center, :inline_format => true
                                    move_down(3.mm)
                                    text "Seite #{page} von #{n_pages}", :align => :center, :inline_format => true
                                end
                            end
                            bounding_box([15.mm, 210.mm - 35.mm], width: 267.mm, height: 15.cm) do
                                n = [n_per_page, n_klasse].min
                                row_height = 15.cm / (n_per_page + 1)

                                (0..n).each do |i|
                                    if i % 2 == 1
                                        rectangle [0.mm, row_height * (n_per_page + 1 - i)], 267.mm, row_height
                                    end
                                end
                                fill_color 'f0f0f0'
                                fill
                                fill_color '000000'

                                (0..(n+1)).each do |i|
                                    line [0.mm, row_height * (11 - i)], [267.mm, row_height * (n_per_page + 1 - i)]
                                end
                                stops = []
                                stops << 0.mm
                                stops << nr_width
                                stops << nr_width + name_width
                                (0..liste[:faecher].size).each do |i|
                                    stops << (nr_width + name_width) + fach_width * i
                                end

                                stops.each do |x|
                                    line [x, row_height * 11], [x, row_height * (n_per_page + 1 - n - 1)]
                                end
                                stroke

                                font('RobotoCondensed') do
                                    bounding_box([0.mm, row_height * (n_per_page + 1)], width: nr_width - 1.mm, height: row_height) do
                                        move_down row_height * 0.5 - 6
                                        text "<b>Nr.</b>", :align => :right, :inline_format => true, :size => 12
                                    end
                                    bounding_box([nr_width + 2.mm, row_height * (n_per_page + 1)], width: name_width - 2.mm, height: row_height) do
                                        move_down row_height * 0.5 - 6
                                        text "<b>Name</b>", :align => :left, :inline_format => true, :size => 12
                                    end
                                    (0...liste[:faecher].size).each do |x|
                                        bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page + 1)], width: fach_width, height: row_height) do
                                            move_down row_height * 0.5 - 6
                                            text "<b>#{liste[:faecher][x]}</b>", :align => :center, :inline_format => true, :size => 12
                                            # stroke_bounds
                                        end
                                    end
                                    (0...n).each do |i|
                                        j = i + offset
                                        email = consider_sus_for_klasse[klasse][j]
                                        bounding_box([0.mm, row_height * (n_per_page - i)], width: nr_width - 1.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            text "#{i + offset + 1}.", :align => :right, :inline_format => true, :size => 12
                                            # stroke_bounds
                                        end
                                        bounding_box([nr_width + 2.mm, row_height * (n_per_page - i)], width: name_width - 2.mm, height: row_height) do
                                            move_down row_height * 0.5 - 12
                                            s = "#{@@user_info[email][:last_name]}"
                                            text elide_string(s, name_width - 2.mm, {:size => 12}), :align => :left, :inline_format => true, :size => 12
                                            s = "#{@@user_info[email][:official_first_name]}"
                                            text elide_string(s, name_width - 2.mm, {:size => 12}), :align => :left, :inline_format => true, :size => 12
                                            # stroke_bounds
                                        end
                                        (0...liste[:faecher].size).each do |x|
                                            fach = liste[:faecher][x]
                                            bounding_box([(nr_width + name_width) + fach_width * x, row_height * (n_per_page - i)], width: fach_width, height: row_height) do
                                                if FAECHER_SPRACHEN.include?(fach)
                                                    bounding_box([0.mm, row_height], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_AT/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        stroke_circle [0, 0], 8
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        stroke_bounds
                                                    end
                                                    bounding_box([0.mm, row_height / 2], width: fach_width / 2, height: row_height / 2) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}_SL/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 4)
                                                                        stroke_circle [0, 0], 8
                                                                    end
                                                                end
                                                            end
                                                        end
                                                        stroke_bounds
                                                    end
                                                    bounding_box([fach_width / 2, row_height], width: fach_width / 2, height: row_height) do
                                                        note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                        if note
                                                            float do
                                                                text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :size => 12, :final_gap => false, :valign => :center
                                                                if NOTEN_MARK.include?(note)
                                                                    save_graphics_state do
                                                                        translate(fach_width / 4, row_height / 2)
                                                                        stroke_circle [0, 0], 8
                                                                    end
                                                                end
                                                            end
                                                        end
                                                    end
                                                else
                                                    note = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"]
                                                    if note
                                                        text "#{note.gsub('-', '–').gsub('×', '')}", :align => :center, :inline_format => true, :size => 12, :valign => :center
                                                        if NOTEN_MARK.include?(note)
                                                            save_graphics_state do
                                                                translate(fach_width / 2, row_height / 2)
                                                                stroke_circle [0, 0], 8
                                                            end
                                                        end
                                                    end
                                                end
                                                # stroke_bounds
                                            end
                                        end
                                    end
                                end

                                # float do
                                # end
                                # stroke_bounds
                            end
                            n_klasse -= n_per_page
                            offset += n_per_page
                        end
                    end
                end
            end
        end
        respond(:yay => 'sure', :pdf_base64 => Base64.strict_encode64(doc.render), :name => 'Zeugniskonferenzen.pdf')
    end

end

