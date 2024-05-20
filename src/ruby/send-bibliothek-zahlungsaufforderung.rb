#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'digest/sha2'
require 'girocode'
require 'yaml'

LETTERS = 'BCDFHJLMNPQRSTVWYZ'
DIGITS = '23456789'

# Please change these values in /data/bibliothek/config.rb
LBV_EMPFAENGER = nil
LBV_IBAN = nil
LBV_BIC = nil
LBV_BANK = nil
LBV_NEXT_SCHULJAHR = nil
LBV_ZAHLUNGSFRIST = nil

LBV_BEITRAG_AS_1 = nil
LBV_BEITRAG_AS_2 = nil
LBV_BEITRAG_AS_3 = nil
LBV_BEITRAG_SESB_1 = nil
LBV_BEITRAG_SESB_2 = nil
LBV_BEITRAG_SESB_3 = nil

if File.exist?('/data/bibliothek/config.rb')
    verbose = $VERBOSE
    $VERBOSE = nil
    require '/data/bibliothek/config.rb'
    $VERBOSE = verbose
end

if LBV_EMPFAENGER.nil?
    STDERR.puts "Please set LBV_EMPFAENGER etc. in /data/bibliothek/config.rb"
    exit(1)
end

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
        @@user_info = Main.class_variable_get(:@@user_info)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        sesb_sus = Set.new(parser.parse_sesb(@@user_info.reject { |x, y| y[:teacher] }, @@schueler_for_klasse))

        entries.sort do |a, b|
            (a[:klasse] == b[:klasse]) ?
            ([a[:last_name], a[:display_first_name]].join('/') <=> [b[:last_name], b[:display_first_name]].join('/')) :
            ((@@klassen_order.index(a[:klasse]) || -1) <=> (@@klassen_order.index(b[:klasse]) || -1))
        end.each do |record|
            email = record[:email]
            # next if (@@user_info[email][:siblings_next_year] || []).empty?
            next unless email == 'carolina.hoffmann@mail.gymnasiumsteglitz.de'
            subject_i = Digest::SHA1.hexdigest("BIB/#{LBV_NEXT_SCHULJAHR}/#{email}").to_i(16)
            subject = ''
            2.times do
                subject += LETTERS[subject_i % LETTERS.length]
                subject_i /= LETTERS.length
            end
            subject += '-'
            2.times do
                subject += LETTERS[subject_i % LETTERS.length]
                subject_i /= LETTERS.length
            end
            subject += '-'
            3.times do
                subject += DIGITS[subject_i % DIGITS.length]
                subject_i /= DIGITS.length
            end
            subject += ' '
            subject += email.split('@')[0].split('.').join(' ').upcase
            sesb = sesb_sus.include?(email)
            klassenstufe = record[:klasse].to_i
            klassenstufe_next = klassenstufe + 1
            next if klassenstufe_next < 7
            STDERR.puts "next: #{klassenstufe_next}"
            brief_id = "#{ZEUGNIS_SCHULJAHR}/Beitragsaufforderung/#{email}"
            brief_sha1 = Digest::SHA1.hexdigest(brief_id).to_i(16).to_s(36)
            brief_sha1 = "Beitragsaufforderung #{LBV_NEXT_SCHULJAHR.gsub('/', '-')} #{record[:display_name]}"

            out_path_docx = File.join("/internal/bibliothek/out/#{brief_sha1}.docx")
            out_path_pdf = File.join("/internal/bibliothek/out/#{brief_sha1}.pdf")
            out_path_dir = File.join("/internal/bibliothek/out/#{brief_sha1}")
            FileUtils.mkpath(out_path_dir)
            formular_sha1 = sha1
            FileUtils.cp_r("/internal/bibliothek/formulare/#{formular_sha1}/", out_path_dir)
            doc = File.read(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'))
            doc.gsub!('#SUS_NAME.', record[:display_name])
            doc.gsub!('#SUS_VORNAME.', record[:display_first_name])
            doc.gsub!('#DATUM.', Date.today.strftime('%d.%m.%Y'))
            doc.gsub!('#MV_DATUM.', '6. Mai 2024')
            doc.gsub!('#NEXT_SCHULJAHR.', '2024/25')
            doc.gsub!('#ZAHLUNGSFRIST.', LBV_ZAHLUNGSFRIST)
            doc.gsub!('#EMPFAENGER.', LBV_EMPFAENGER)
            doc.gsub!('#IBAN.', LBV_IBAN.chars.each_slice(4).to_a.map { |x| x.join('') }.join(' '))
            doc.gsub!('#BIC.', LBV_BIC)
            doc.gsub!('#BANK.', LBV_BANK)
            doc.gsub!('#BEITRAG_AS_1.', "#{LBV_BEITRAG_AS_1.to_s} €")
            doc.gsub!('#BEITRAG_AS_2.', "#{LBV_BEITRAG_AS_2.to_s} €")
            doc.gsub!('#BEITRAG_AS_3.', "#{LBV_BEITRAG_AS_3.to_s} €")
            doc.gsub!('#BEITRAG_SESB_1.', "#{LBV_BEITRAG_SESB_1.to_s} €")
            doc.gsub!('#BEITRAG_SESB_2.', "#{LBV_BEITRAG_SESB_2.to_s} €")
            doc.gsub!('#BEITRAG_SESB_3.', "#{LBV_BEITRAG_SESB_3.to_s} €")
            doc.gsub!('#SUS_KLASSENSTUFE.', klassenstufe_next.to_s)
            doc.gsub!('#SUS_ZUG_DATIV.', sesb ? 'SESB-Zug' : 'altsprachlichen Zug')
            doc.gsub!('#VERWENDUNGSZWECK.', subject)

            amount = 0

            sibling_index_next_year = @@user_info[email][:sibling_index_next_year] || 0
            satz = StringIO.open do |io|
                if sibling_index_next_year == 0
                    amount = sesb ? LBV_BEITRAG_SESB_1 : LBV_BEITRAG_AS_1
                    io.puts "Da uns keine weiteren, älteren Geschwisterkinder bekannt sind, beträgt der Beitrag für Ihr Kind im nächsten Schuljahr #{sprintf('%d', amount).sub('.', ',')} €."
                elsif sibling_index_next_year == 1
                    amount = sesb ? LBV_BEITRAG_SESB_2 : LBV_BEITRAG_AS_2
                    older_siblings = join_with_sep(@@user_info[email][:older_siblings].reverse.map { |x| @@user_info[x][:display_first_name] }, ', ', ' und ')
                    io.puts "Da uns ein weiteres, älteres Geschwisterkind bekannt ist (#{older_siblings}), beträgt der Beitrag für Ihr Kind im nächsten Schuljahr #{sprintf('%d', amount).sub('.', ',')} €."
                elsif sibling_index_next_year >= 2
                    amount = sesb ? LBV_BEITRAG_SESB_3 : LBV_BEITRAG_AS_3
                    older_siblings = join_with_sep(@@user_info[email][:older_siblings].reverse.map { |x| @@user_info[x][:display_first_name] }, ', ', ' und ')
                    io.puts "Da uns #{sibling_index_next_year > 2 ? 'mindestens ' : ''}zwei weitere, ältere Geschwisterkinder bekannt sind (#{older_siblings}), beträgt der Beitrag für Ihr Kind im nächsten Schuljahr #{sprintf('%d', amount).sub('.', ',')} €."
                end
                io.string
            end
            doc.gsub!('#SUS_GESCHWISTER_UND_BEITRAG_SATZ.', satz)
            doc.gsub!('#BETRAG.', sprintf('%.2f €', amount).sub('.', ','))

            File.open(File.join(out_path_dir, formular_sha1, 'word', 'document.xml'), 'w') do |f|
                f.write doc
            end
            code = Girocode.new(
                iban: LBV_IBAN,
                bic: LBV_BIC,
                name: LBV_EMPFAENGER,
                currency: 'EUR',
                amount: amount,
                bto_info: subject,
                reference: subject.split(' ').first,
            )
            File.open(File.join(out_path_dir, formular_sha1, 'word', 'media', 'image2.png'), 'w') do |f|
                f.write code.to_png(module_px_size: 8)
            end

            command = "convert \"#{File.join(out_path_dir, formular_sha1, 'word', 'media', 'image2.png')}\" -trim +repage \"#{File.join(out_path_dir, formular_sha1, 'word', 'media', 'image3.png')}\""
            system(command)
            FileUtils.mv(File.join(out_path_dir, formular_sha1, 'word', 'media', 'image3.png'), File.join(out_path_dir, formular_sha1, 'word', 'media', 'image2.png'))

            command = "cd \"#{File.join(out_path_dir, formular_sha1)}\"; zip -r \"#{out_path_docx}\" ."
            system(command)
            FileUtils::rm_rf(File.join(out_path_dir))
            command = "HOME=/internal/lowriter_home lowriter --headless --convert-to 'pdf:writer_pdf_Export:{\"ExportFormFields\":{\"type\":\"boolean\",\"value\":\"false\"}}' \"#{out_path_docx}\" --outdir \"#{File.dirname(out_path_docx)}\""
            STDERR.puts command
            system(command)
            FileUtils::rm_rf(out_path_docx)

            pdf_path = File.join(File.dirname(out_path_docx), File.basename(out_path_docx).sub('.docx', '.pdf'))

            email = 'eltern.' + email
            act_as_sender = 'schulbuchverein@gymnasiumsteglitz.de'
            mail = Mail.new do
                charset = 'UTF-8'
                to email
                bcc [SMTP_FROM, act_as_sender]
                from act_as_sender
                reply_to act_as_sender

                subject "Beitragszahlung zum Schulbuchverein für das Schuljahr #{LBV_NEXT_SCHULJAHR}"
                content_type 'multipart/mixed'

                message = StringIO.open do |io|
                    io.puts <<~END_OF_MAIL
                        <p>Sehr geehrte Eltern von #{record[:display_name]},</p>
                        <p>hiermit möchten wir Sie daran erinnern, dass die jährliche Zahlung des Beitrags zum Schulbuchverein zum #{LBV_ZAHLUNGSFRIST} fällig wird.</p>
                        <p>Alle Informationen zur Beitragshöhe und Zahlungsweise finden Sie in der angehängten Beitragsaufforderung.</p>
                        <p>Bitte beachten Sie, dass wir das Verfahren für die Beitragszahlung in diesem Jahr angepasst haben, um die Zuordnung der Zahlungseingänge zu erleichtern:</p>
                        <p><b>--- Bitte tätigen Sie für jedes beitragspflichtige Kind eine eigene Überweisung und nutzen Sie nur den im Schreiben angegebenen Verwendungszweck! ---</b></p>
                        <p>Für Rückfragen stehen wir gerne per E-Mail unter <a href='mailto:schulbuchverein@gymnasiumsteglitz.de'>schulbuchverein@gymnasiumsteglitz.de</a> zur Verfügung.</p>
                        <p>Mit freundlichen Grüßen</p>
                        <p>
                        Dr Christoph Hellriegel<br>
                        Vorsitzender
                        </p>
                        <p>
                        Alice Beaucamp<br>
                        Stellvertretende Vorsitzende
                        </p>
                        <p>
                        Lehr- und Lernmittelhilfe des Gymnasium Stegltz e.V.<br>
                        E-Mail: <a href='mailto:schulbuchverein@gymnasiumsteglitz.de'>schulbuchverein@gymnasiumsteglitz.de</a><br>
                        Web: <a href='https://gymnasiumsteglitz.de/lehrbuchverein'>https://gymnasiumsteglitz.de/lehrbuchverein</a><br>
                        </p>
                    END_OF_MAIL
                    io.string
                end

                part(:content_type => 'multipart/alternative') do |p|
                    p.part 'text/html' do |p|
                        p.content_type = 'text/html; charset=UTF-8'
                        p.body = message
                    end
                    p.part 'text/plain' do |p|
                        p.body = mail_html_to_plain_text(message)
                    end
                end

                add_file :content_type => 'application/pdf', :content => File.read(pdf_path), :filename => "#{brief_sha1}.pdf"
            end
            if ARGV.include?('--srsly')
                mail.deliver!
            else
                STDERR.puts "Not sending mail to #{email} unless you specify --srsly!"
            end
        end
    end
end

script = Script.new
script.run
