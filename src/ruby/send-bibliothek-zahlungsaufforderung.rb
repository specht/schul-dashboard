#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'digest/sha2'
require 'yaml'

class Script
    def run

        path = "/data/bibliothek/Beitragsaufforderung.docx"
        sha1 = Digest::SHA1.hexdigest(File.read(path))
        out_path = File.join("/internal/bibliothek/formulare/#{sha1}")
        unless File.exist?(out_path)
            FileUtils.mkpath(File.dirname(out_path))
            system("unzip -d \"#{out_path}\" \"#{path}\"")
        end
        doc = File.read(File.join(out_path, 'word', 'document.xml'))
        tags = doc.scan(/[#\$][A-Za-z0-9_]+\./).uniq
        key = File.basename(path).sub('.docx', '')
        debug "#{key} (#{out_path}): #{tags.to_json}"

        parser = Parser.new()
        entries = []

        parser.parse_schueler do |record|
            entries << {:email => record[:email],
                        :display_name => record[:display_name],
                        :display_first_name => record[:display_first_name],
                        :last_name => record[:last_name],
                        :display_last_name => record[:display_last_name],
                        :klasse => record[:klasse]
                       }
        end
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        entries.sort do |a, b|
            (a[:klasse] == b[:klasse]) ?
            ([a[:last_name], a[:display_first_name]].join('/') <=> [b[:last_name], b[:display_first_name]].join('/')) :
            ((@@klassen_order.index(a[:klasse]) || -1) <=> (@@klassen_order.index(b[:klasse]) || -1))
        end.each do |record|
            STDERR.puts record.to_yaml
            email = record[:email]
            email = 'specht@gymnasiumsteglitz.de'
            klassenstufe = record[:klasse].to_i
            klassenstufe_next = klassenstufe + 1
            STDERR.puts "next: #{klassenstufe_next}"
            brief_id = "#{ZEUGNIS_SCHULJAHR}/Beitragsaufforderung/#{email}"
            brief_sha1 = Digest::SHA1.hexdigest(brief_id).to_i(16).to_s(36)

            out_path_docx = File.join("/internal/bibliothek/out/#{brief_sha1}.docx")
            out_path_pdf = File.join("/internal/bibliothek/out/#{brief_sha1}.pdf")
            out_path_dir = File.join("/internal/bibliothek/out/#{brief_sha1}")
            FileUtils.mkpath(out_path_dir)
            formular_sha1 = sha1
            FileUtils.cp_r("/internal/bibliothek/formulare/#{formular_sha1}/", out_path_dir)
            doc = File.read(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'))
            doc.gsub!('#SUS_NAME.', record[:display_name])
            doc.gsub!('#DATUM.', Date.today.strftime('%d.%m.%Y'))
            doc.gsub!('#MV_DATUM.', '6. Mai 2024')
            doc.gsub!('#NEXT_SCHULJAHR.', '2024/25')


            File.open(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'), 'w') do |f|
                f.write doc
            end
            command = "cd \"#{File.join(out_path_dir, formular_sha1)}\"; zip -r \"#{out_path_docx}\" ."
            system(command)
            FileUtils::rm_rf(File.join(out_path_dir))
            command = "HOME=/internal/lowriter_home lowriter --headless --convert-to 'pdf:writer_pdf_Export:{\"ExportFormFields\":{\"type\":\"boolean\",\"value\":\"false\"}}' #{out_path_docx} --outdir \"#{File.dirname(out_path_docx)}\""
            STDERR.puts command
            system(command)

            break
        end
    end
end

script = Script.new
script.run
