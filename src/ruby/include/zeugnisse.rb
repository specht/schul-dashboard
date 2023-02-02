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
        missing_tags.each do |tag|
            errors << "fehlt: #{tag}"
        end
        superfluous_tags.each do |tag|
            errors << "unbekannt: #{tag}"
        end
        return nil if errors.empty?
        return errors
    end
end
