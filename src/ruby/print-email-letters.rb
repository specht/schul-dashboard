#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'digest/sha2'
require 'yaml'

class Script
    CHARS = 'BCDFGHJKMNPQRSTVWXYZ23456789'.split('')
    SPECIAL = '-'.split('')

    def gen_password_for_email(email)
        sha2 = Digest::SHA256.new()
        sha2 << EMAIL_PASSWORD_SALT
        sha2 << email
        srand(sha2.hexdigest.to_i(16))
        password = ''
        while true do
            if password =~ /[a-z]/ &&
            password =~ /[A-Z]/ &&
            password =~ /[0-9]/ &&
            password.include?('-')
                break
            end
            password = ''
            8.times do 
                c = CHARS.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
            password += '-'
            4.times do 
                c = CHARS.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
        end
        password
    end

    def run
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
        FileUtils::mkpath('/gen/E-Mail-Briefe')
        FileUtils::mkpath('/gen/E-Mail-Briefe/ids')
        FileUtils::mkpath('/gen/E-Mail-Briefe/klassen')
        system("cp email-templates/*.pdf /gen/E-Mail-Briefe/")
        system("cp email-templates/*.pdf_tex /gen/E-Mail-Briefe/")
        system("cp email-templates/*.pdf /gen/E-Mail-Briefe/ids/")
        system("cp email-templates/*.pdf_tex /gen/E-Mail-Briefe/ids/")
        system("cp email-templates/*.pdf /gen/E-Mail-Briefe/klassen/")
        system("cp email-templates/*.pdf_tex /gen/E-Mail-Briefe/klassen/")
        letters_for_klasse = {}
        File.open('/gen/E-Mail-Briefe/E-Mail-Briefe.tex', 'w') do |f|
            f.write(File.read('email-templates/letter-template.tex'))
            page = File.read('email-templates/letter-page.tex')
            page = File.read('email-templates/letter-page.ru.tex')
            count = 0
            entries.sort do |a, b|
                (a[:klasse] == b[:klasse]) ?
                (a[:last_name] <=> b[:last_name]) :
                ((@@klassen_order.index(a[:klasse]) || -1) <=> (@@klassen_order.index(b[:klasse]) || -1))
            end.each do |record|
                next unless @@klassen_order.include?(record[:klasse])
                entry = page.dup
                password = gen_password_for_email(record[:email])
                password_parents = gen_password_for_email('eltern.' + record[:email])
                entry.gsub!('#{SCHUL_NAME}', SCHUL_NAME)
                entry.gsub!('#{SCHUL_NAME_AN_DATIV}', SCHUL_NAME_AN_DATIV)
                entry.gsub!('#{SCHUL_MAIL_DOMAIN}', SCHUL_MAIL_DOMAIN)
                entry.gsub!('#{SCHUL_MAIL_LOGIN_URL}', SCHUL_MAIL_LOGIN_URL)
                entry.gsub!('#{SCHUL_MAIL_LOGIN_SMTP_HOST}', SCHUL_MAIL_LOGIN_SMTP_HOST)
                entry.gsub!('#{SCHUL_MAIL_LOGIN_IMAP_HOST}', SCHUL_MAIL_LOGIN_IMAP_HOST)
                entry.gsub!('#{WEBSITE_HOST}', WEBSITE_HOST)
                
                entry.gsub!('#{EMAIL}', record[:email])
                entry.gsub!('#{EMAIL_PARENTS}', 'eltern.' + record[:email])
                entry.gsub!('#{FIRST_NAME}', record[:display_first_name])
                entry.gsub!('#{LAST_NAME}', record[:last_name])
                entry.gsub!('#{DISPLAY_NAME}', record[:display_name])
                entry.gsub!('#{DISPLAY_LAST_NAME}', record[:display_last_name])
                entry.gsub!('#{KLASSE}', record[:klasse].gsub('o', '\\textomega'))
                entry.gsub!('#{PASSWORD}', password)
                entry.gsub!('#{PASSWORD_PARENTS}', password_parents)
                entry.gsub!('#{INITIALS}', "#{(record[:display_first_name][0] || '').upcase}#{record[:last_name][0].upcase}")
                f.puts entry
                File.open("/gen/E-Mail-Briefe/ids/E-Mail-Brief #{record[:display_name]}.tex", 'w') do |fs|
                    fs.write(File.read('email-templates/letter-template.tex'))
                    fs.puts entry
                    fs.puts("\\end{document}")
                end
                letters_for_klasse[record[:klasse]] ||= []
                letters_for_klasse[record[:klasse]] << entry
            end
            f.puts("\\end{document}")
        end
        letters_for_klasse.each_pair do |klasse, entries|
            File.open("/gen/E-Mail-Briefe/klassen/E-Mail-Briefe Klasse #{klasse}.tex", 'w') do |fs|
                fs.write(File.read('email-templates/letter-template.tex'))
                fs.puts entries.join("\n")
                fs.puts("\\end{document}")
            end
        end
    end
end

script = Script.new
script.run
