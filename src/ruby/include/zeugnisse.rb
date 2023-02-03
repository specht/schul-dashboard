# zip -r ../final.docx *
# unzip -d temp 5.docx
# d = Docx::Document.open('example.docx')
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.text }};
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.substitute('A', 'B') }};
# d.save('out.docx')
# lowriter --convert-to pdf [in path]

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
            @@zeugnisse[:formulare][key] ||= {}
            @@zeugnisse[:formulare][key][:sha1] = sha1
            @@zeugnisse[:formulare][key][:tags] = tags.map { |x| x[0, x.size - 1] }
            @@zeugnisse[:formulare][key][:formular_fehler] = self.check_zeugnisformular(key)
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
        @@zeugnisliste_for_klasse = {}
        @@zeugnisliste_for_lehrer = {}
        kurse_for_klasse = Hash[ZEUGNIS_KLASSEN_ORDER.map do |klasse|
            [klasse, @@lessons_for_klasse[klasse].map { |x| @@lessons[:lesson_keys][x].merge({:lesson_key => x})}]
        end]
        ZEUGNIS_KLASSEN_ORDER.each do |klasse|
            lesson_keys_for_fach = {}
            shorthands_for_fach = {}
            kurse_for_klasse[klasse].each do |kurs|
                lesson_keys_for_fach[kurs[:fach]] ||= []
                lesson_keys_for_fach[kurs[:fach]] << kurs[:lesson_key]
                kurs[:lehrer].each do |shorthand|
                    fach = ZEUGNIS_CONSOLIDATE_FACH[kurs[:fach]] || kurs[:fach]
                    shorthands_for_fach[fach] ||= {};
                    shorthands_for_fach[fach][shorthand] = true
                    @@zeugnisliste_for_lehrer[shorthand] ||= {}
                    @@zeugnisliste_for_lehrer[shorthand]["#{klasse}/#{fach}"] = true
                end
            end
            faecher = self.zeugnis_faecher_for_emails(@@schueler_for_klasse[klasse])
            @@zeugnisliste_for_klasse[klasse] = {}
            @@zeugnisliste_for_klasse[klasse][:faecher] = faecher.map do |x|
                x[0] == '$' ? x[1, x.size - 1] : x
            end
            @@zeugnisliste_for_klasse[klasse][:wahlfach] = Hash[faecher.map do |x|
                [x.sub('$', ''), x[0] == '$' ? true : false]
            end]
            @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach] = {}
            @@zeugnisliste_for_klasse[klasse][:faecher].each do |fach|
                @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach][fach] = (shorthands_for_fach[fach] || {}).keys
            end
            @@zeugnisliste_for_klasse[klasse][:schueler] = @@schueler_for_klasse[klasse].map do |email|
                {
                    :email => email,
                    :zeugnis_key => self.zeugnis_key_for_email(email),
                    :official_first_name => @@user_info[email][:official_first_name],
                    :last_name => @@user_info[email][:last_name],
                    :geburtstag => @@user_info[email][:geburtstag],
                    :geschlecht => @@user_info[email][:geschlecht],
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
                required_tags << "$WF#{wf_count}"
                required_tags << "#WF#{wf_count}"
            else
                required_tags << "##{tag}"
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
        missing_tags = Set.new(required_tags) - Set.new(@@zeugnisse[:formulare][key][:tags])
        superfluous_tags = Set.new(@@zeugnisse[:formulare][key][:tags]) - Set.new(required_tags)
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
        require_zeugnis_admin!
        data = parse_request_data(
            :required_keys => [:schueler, :paths, :values],
            :types => {:schueler => Array, :paths => Array, :values => Array},
            :max_body_length => 1024 * 1024 * 10,
            :max_string_length => 1024 * 1024 * 10,
        )
        cache = parse_paths_and_values(data[:paths], data[:values])
        pdf_path = ''
        data[:schueler].each do |schueler|
            parts = schueler.split('/')
            klasse = parts[0]
            index = parts[1].to_i
            sus_info = @@zeugnisliste_for_klasse[klasse][:schueler][index]
            email = sus_info[:email]
            zeugnis_key = sus_info[:zeugnis_key]
            faecher_info = @@zeugnisliste_for_klasse[klasse][:faecher]
            wahlfach_info = @@zeugnisliste_for_klasse[klasse][:wahlfach]
            # :zeugnis_key => self.zeugnis_key_for_email(email),
            # :official_first_name => @@user_info[email][:official_first_name],
            # :last_name => @@user_info[email][:last_name],
            # :geburtstag => @@user_info[email][:geburtstag],
            # :geschlecht => @@user_info[email][:geschlecht],
            info = {}
            info['#Name'] = "#{sus_info[:official_first_name]} #{sus_info[:last_name]}"
            info['#Geburtsdatum'] = "#{Date.parse(sus_info[:geburtstag]).strftime('%d.%m.%Y')}"
            info['#Klasse'] = Main.tr_klasse(klasse)
            info['#Zeugnisdatum'] = ZEUGNIS_DATUM
            info['@Geschlecht'] = sus_info[:geschlecht]
            faecher_info.each do |fach|
                info["##{fach}"] = cache["Schuljahr:#{ZEUGNIS_SCHULJAHR}/Halbjahr:#{ZEUGNIS_HALBJAHR}/Fach:#{fach}/Email:#{email}"] || '--'
            end
            zeugnis_id = "#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/#{zeugnis_key}/#{info.to_json}"
            zeugnis_sha1 = Digest::SHA1.hexdigest(zeugnis_id)
            debug "Printing Zeugnis for #{sus_info[:official_first_name]} #{sus_info[:last_name]} => #{zeugnis_sha1}"
            out_path_docx = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}.docx")
            out_path_pdf = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}.pdf")
            out_path_dir = File.join("/internal/zeugnisse/out/#{zeugnis_sha1}")
            FileUtils.mkpath(out_path_dir)
            formular_sha1 = @@zeugnisse[:formulare][zeugnis_key][:sha1]
            FileUtils.cp_r("/internal/zeugnisse/formulare/#{formular_sha1}/", out_path_dir)
            doc = File.read(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'))
            @@zeugnisse[:formulare][zeugnis_key][:tags].each do |tag|
                doc.gsub!("#{tag}.", info[tag] || '')
            end
            File.open(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'), 'w') do |f|
                f.write doc
            end
            command = "cd \"#{File.join(out_path_dir, formular_sha1)}\"; zip -r \"#{out_path_docx}\" ."
            system(command)
            command = "HOME=/internal/lowriter_home lowriter --convert-to pdf \"#{out_path_docx}\" --outdir \"#{File.dirname(out_path_docx)}\""
            system(command)
            final_path = File.join('/gen', 'zeugnisse', "#{zeugnis_sha1}.pdf")
            FileUtils.mkpath(File.join('/gen', 'zeugnisse'))
            FileUtils.cp(out_path_pdf, final_path)
            pdf_path = final_path
        end
        respond(:yay => 'sure', :pdf_path => pdf_path)
    end
end