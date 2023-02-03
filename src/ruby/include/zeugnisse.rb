# zip -r ../final.docx *
# unzip -d temp 5.docx
# d = Docx::Document.open('example.docx')
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.text }};
# d.paragraphs.each { |p| p.each_text_run { |tr| puts tr.substitute('A', 'B') }};
# d.save('out.docx')
# lowriter --convert-to pdf [in path]

class Main < Sinatra::Base
    def self.parse_zeugnisformulare
        @@zeugnisse = {}
        @@zeugnisse[:formulare] ||= {}
        begin
            debug "Parsing Zeugnisformulare..."
            Dir["/data/zeugnisse/formulare/#{ZEUGNIS_SCHULJAHR}/#{ZEUGNIS_HALBJAHR}/*.docx"].each do |path|
                sha1 = Digest::SHA1.hexdigest(File.read(path))
                out_path = File.join("/internal/zeugnisse/formulare/#{sha1}")
                unless File.exist?(out_path)
                    FileUtils.mkpath(File.dirname(out_path))
                    system("unzip -d \"#{out_path}\" \"#{path}\"")
                end
                doc = File.read(File.join(out_path, 'word', 'document.xml'))
                tags = doc.scan(/[#\$][A-Za-z0-9_]+/)
                key = File.basename(path).sub('.docx', '')
                @@zeugnisse[:formulare][key] ||= {}
                @@zeugnisse[:formulare][key][:sha1] = sha1
                @@zeugnisse[:formulare][key][:tags] = tags
            end
        rescue StandardError => e
            debug e
            debug e.backtrace
            debug "Something went wrong parsing Zeugnisformulare, skipping..."
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
        # for (let klasse of zeugnis_klassen_order) {
        #     let lesson_keys_for_fach = {};
        #     let shorthands_for_fach = {};
        #     for (let kurs of kurse_for_klasse[klasse]) {
        #         lesson_keys_for_fach[kurs.fach] ??= [];
        #         lesson_keys_for_fach[kurs.fach].push(kurs.lesson_key);
        #         for (let lehrer of kurs.lehrer) {
        #             let fach = consolidate_fach(kurs.fach);
        #             shorthands_for_fach[fach] ??= {};
        #             shorthands_for_fach[fach][lehrer] = true;
        #         }
        #     }
        #     let tr = $(`<tr style='line-height: 1em;'>`).appendTo(table);
        #     tr.append($(`<td style='width: 4em;'>`).html(`${klassen_tr[klasse] ?? klasse}<br /><span style='font-size: 85%; color: #888;'>(${schueler_for_klasse[klasse].length} SuS)</span>`));
        #     let faecher = faecher_for_emails(schueler_for_klasse[klasse]);
        #     for (let fach of faecher) {
        #         fach = consolidate_fach(fach);
        #         let fach_label = fach;
        #         if (fach_label.charAt(0) === '$') {
        #             fach_label = `(${fach_label.substring(1)})`;
        #             fach = fach.substring(1);
        #         }
        #         tr.append($(`<td style='width: 3em;'>`).html(`<span>${fach_label}</span><br /><span style='font-size: 85%; color: #888;'>${Object.keys(shorthands_for_fach[fach] ?? {}).join('/')}</span>`));
        #     }
        # }
    end

    def check_zeugnisformular(key)
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
end
