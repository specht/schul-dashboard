#!/usr/bin/env ruby

require 'mail'
require 'yaml'
require 'net/imap'
require './main.rb'

MAIL_FORWARDER_SLEEP = DEVELOPMENT ? 10 : 60
MAIL_FORWARD_BATCH_SIZE = 30

Mail.defaults do
    # delivery_method :logger
    delivery_method :smtp, {
        :address => SMTP_SERVER,
        :port => 587,
        :domain => SMTP_DOMAIN,
        :user_name => SMTP_USER,
        :password => SMTP_PASSWORD,
        :authentication => 'login',
        :enable_starttls_auto => true
    }
end

class Script
    def initialize
#         @shutdown = false
#         Signal.trap("TERM") do
#             STDERR.puts "Caught SIGTERM"
#             @shutdown = true
#         end
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@teachers_for_klasse = Main.class_variable_get(:@@teachers_for_klasse)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@user_info = Main.class_variable_get(:@@user_info)
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        @@mailing_lists = nil
        @@mailing_list_mtime = 0
        begin
            imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
        rescue
            STDERR.puts "Unable to resolve #{SCHUL_MAIL_LOGIN_IMAP_HOST}, exiting..."
            exit(1)
        end
        STDERR.puts "Mail forwarder ready with #{fresh_mailing_list().size} mailing lists at #{MAILING_LIST_EMAIL}!"
    end

    def fresh_mailing_list()
        refresh = false
        path = '/internal/mailing_lists.yaml'
        if @@mailing_lists.nil?
            refresh = true
        elsif File.mtime(path) > @@mailing_list_mtime
            refresh = true
        end
        if refresh
            STDERR.puts "Re-reading mailing lists from disk..."
            @@mailing_list = YAML.load(File.read(path), aliases: true)
            @@mailing_list_mtime = File.mtime(path)
        end
        @@mailing_list
    end

    def allowed_senders()
        results = Set.new()
        results |= Set.new(@@users_for_role[:can_use_mailing_lists])
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {ev: true})
            RETURN u.email;
        END_OF_QUERY
        temp.each do |row|
            results << 'eltern.' + row[:email]
        end
        path = '/app/mail-forwarder-emails.txt'
        if File.exist?(path)
            File.open(path) do |f|
                f.each do |line|
                    line.strip!
                    next if line[0] == '#' || line.empty?
                    results << line
                end
            end
        end
        @@klassen_order.each do |klasse|
            results << "ev.#{klasse}@mail.gymnasiumsteglitz.de"
        end
        results.map { |x| x.downcase }
    end

    def run
        t1 = Thread.new do
            # First thread: check for new mails
            # - if /mails/<message-id> does not exist:
            #   - write mail to /mails/<message-id>/mail
            #   - write recipients to /mails/<message-id>/recipients.yaml
            #     - pending: [...]
            #     - sent: []
            # - delete mail from Inbox
            loop do
                imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST, :ssl => true)
                imap.authenticate('PLAIN', MAILING_LIST_EMAIL, MAILING_LIST_PASSWORD)
                imap.select('INBOX')
                imap.search(['NOT', 'DELETED']).each do |mid|
                    body = imap.fetch(mid, 'RFC822')[0].attr['RFC822']
                    mail = Mail.read_from_string(body)
                    from_address = Mail::Address.new(mail.from.first).address
                    from_address_suffix_with_at = '@' + from_address.split('@').last
                    mail_body = mail.body
                    mail_subject = mail.subject
                    message_id = mail.message_id
                    storage_path = "/mails/#{message_id}"
                    mail_path = File.join(storage_path, 'mail')
                    recipients_path = File.join(storage_path, 'recipients.yaml')
                    unless File.exist?(mail_path)
                        FileUtils.mkpath(storage_path)
                        File.open(mail_path, 'w') do |f|
                            f.puts body
                        end
                        unless allowed_senders().include?(from_address.downcase) && MAILING_LIST_FORWARDER_ACCOUNTS.include?(from_address_suffix_with_at)
                            STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Bouncing mail back to invalid sender #{mail.from[0]}: #{mail.subject}"
                            deliver_mail do |m2|
                                m2.reply_to = "#{MAIL_SUPPORT_NAME} <#{MAIL_SUPPORT_EMAIL}>"
                                m2.to = ["#{mail.from[0]}"]
                                m2.from = [SMTP_FROM]
                                m2.cc = []
                                m2.bcc = []
                                m2.subject = "[Nicht zustellbar: Ungültige Absender-Adresse] #{mail.subject}"
                                m2.body = "Sie haben versucht, eine E-Mail an den Verteiler zu schicken,  allerdings ist Ihre Absender-Adresse nicht für den Versand an Verteileradressen freigeschaltet.\r\n\r\nBitte verwenden Sie Ihre schulische E-Mail-Adresse oder schreiben Sie eine E-Mail an #{MAIL_SUPPORT_EMAIL}, um sich für den Versand freischalten zu lassen.\r\n\r\n"
                            end
                            imap.copy(mid, 'Bounced')
                        else
                            all_recipients = Set.new
                            recipients = ((mail.to || []) + (mail.cc || []) + (mail.bcc || []))
                            mailing_list_email_suffix = MAILING_LIST_EMAIL.split('@').last
                            non_existing_mailing_list_addresses = Set.new()
                            existing_mailing_list_addresses = Set.new()
                            relocated_mailing_list_addresses = Set.new()
                            recipients.each do |m|
                                suffix = m.downcase.split('@').last
                                if suffix == mailing_list_email_suffix
                                    if m.downcase != MAILING_LIST_EMAIL.downcase
                                        if fresh_mailing_list().include?(m.downcase)
                                            all_recipients |= Set.new(fresh_mailing_list()[m.downcase][:recipients])
                                            existing_mailing_list_addresses << m.downcase
                                        else
                                            non_existing_mailing_list_addresses << m.downcase
                                        end
                                    end
                                else
                                    if suffix == mailing_list_email_suffix.split('.').map.with_index { |x, i| i == 0 ? 'mail' : x }.join('.')
                                        relocated_mailing_list_addresses << m.split('@').first + '@' + mailing_list_email_suffix
                                    end
                                end
                            end
                            unless all_recipients.empty?
                                File.open(recipients_path, 'w') do |f|
                                    data = {:pending => all_recipients.to_a.sort,
                                            :sent => []}
                                    f.puts data.to_yaml
                                end
                                STDERR.puts "Received new mail: #{mail_subject} (#{mail.message_id}) for #{all_recipients.size} recipients..."
                                imap.copy(mid, 'Forwarded')
                            end
                            if all_recipients.empty? || (!non_existing_mailing_list_addresses.empty?) || (!relocated_mailing_list_addresses.empty?)
                                STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Bouncing mail back to sender #{mail.from[0]}: #{mail.subject}"
                                mail.reply_to = "#{MAIL_SUPPORT_NAME} <#{MAIL_SUPPORT_EMAIL}>"
                                mail.to = ["#{mail.from[0]}"]
                                mail.from = [SMTP_FROM]
                                mail.cc = []
                                mail.bcc = []
                                if non_existing_mailing_list_addresses.empty? && relocated_mailing_list_addresses.empty?
                                    mail.subject = "[Nicht zustellbar: Keine Empfänger] #{mail.subject}"
                                else
                                    mail.subject = "[Nicht zustellbar: Ungültige Verteiler-Adresse] #{mail.subject}"
                                end
                                mail.body = StringIO.open do |io|
                                    io.puts "Sie haben versucht, eine E-Mail an den Verteiler zu senden.\r\n\r\n"
                                    unless existing_mailing_list_addresses.empty?
                                        io.puts "Die E-Mail wurde an folgende Verteiler ausgeliefert:\r\n\r\n"
                                        io.puts existing_mailing_list_addresses.to_a.sort.join("\r\n")
                                        io.puts "\r\n"
                                    end
                                    unless non_existing_mailing_list_addresses.empty?
                                        io.puts "Die E-Mail wurde an folgende Verteiler nicht ausgeliefert, da diese Verteiler nicht existieren:\r\n\r\n"
                                        io.puts non_existing_mailing_list_addresses.to_a.sort.join("\r\n")
                                        io.puts "\r\n"
                                    end
                                    unless relocated_mailing_list_addresses.empty?
                                        io.puts "Bitte beachten Sie, dass sich alle Verteileradressen geändert haben. Statt @#{MAILING_LIST_DOMAIN.split('.').map.with_index { |x, i| i == 0 ? 'mail' : x }.join('.')} verwenden Sie nun bitte immer @#{MAILING_LIST_DOMAIN}. Die neue Verteileradresse lautet also:\r\n\r\n"
                                        io.puts relocated_mailing_list_addresses.to_a.sort.join("\r\n")
                                        io.puts "\r\n"
                                    end
                                    if all_recipients.empty?
                                        io.puts "Die E-Mail wurde an niemanden weitergeleitet."
                                        io.puts "\r\n"
                                    end
                                    io.string
                                end
                                mail.deliver!
                                imap.copy(mid, 'Bounced')
                            end
                        end
                    end
                    imap.store(mid, '+FLAGS', [:Deleted])
                end
                imap.expunge
                imap.logout
                imap.disconnect
                sleep MAIL_FORWARDER_SLEEP
            end
        end
        t2 = Thread.new do
            # Second thread: check for e-mails to send
            # - glob for /mails/*/recipients.yaml
            #   - read /mails/*/recipients.yaml
            #   - for each pending recipient:
            #     - send mail from disk to recipient
            #     - move recipient from pending to sent, write recipients.yaml to disk
            #     - wait 1s
            #   - we're done, delete recipients.yaml and clear contents of /mails/<message-id>/mail
            loop do
                Dir["/mails/*/recipients.yaml"].each do |path|
                    mail_path = File.join(File.dirname(path), 'mail')
                    STDERR.puts "mail_path: #{mail_path}"
                    mail = Mail.read_from_string(File.read(mail_path))
                    from_address = Mail::Address.new(mail.from.first).address
                    from_address_suffix_with_at = '@' + from_address.split('@').last
                    mail.delivery_method :smtp, MAILING_LIST_FORWARDER_ACCOUNTS[from_address_suffix_with_at]
                    mail.to = nil
                    mail.cc = []
                    mail.bcc = []
                    mail.reply_to = mail[:from].formatted.first
#                     mail.from = ["#{mail[:from].formatted.first.gsub(/<[^>]+>/, '').strip} <#{MAILING_LIST_EMAIL}>"]
                    recipients = YAML::load(File.read(path))
                    while !recipients[:pending].empty?
                        recipient = recipients[:pending].first
                        mail.to = recipient
                        # STDERR.puts mail
                        STDERR.puts "Forwarding mail to #{recipient}..."
                        File.open(File.join(File.dirname(path), 'last_forwarded_mail'), 'w') do |f|
                            f.write mail.to_s
                        end
                        begin
                            if DEVELOPMENT && !(VERTEILER_DEVELOPMENT_EMAILS.include?(recipient))
                                STDERR.puts "(skipping mail forwarding because we're in development mode)"
                            else
                                mail.deliver!
                            end
                        rescue StandardError => e
                            # sending failed!
                            STDERR.puts "Forwarding mail failed, notifying admin..."
                            # 1. notify WEBSITE_MAINTAINER_EMAIL
                            _sender = mail[:from].formatted.first
                            _subject = "E-Mail-Weiterleitung fehlgeschlagen: #{mail.subject}"
                            _body = StringIO.open do |io|
                                # "The mail forwarder failed to forward a mail from #{mail[:from].formatted.first} to #{recipient}.\r\n\r\n"
                                io.puts "Hallo!\r\n\r\n"
                                io.puts "Wir haben momentan leider bei manchen E-Mails technische Probleme mit der Weiterleitung. Die folgende E-Mail konnte leider nicht weitergeleitet werden:\r\n\r\n"
                                io.puts "Betreff: #{mail.subject}\r\n"
                                io.puts "Absender: #{mail[:from].formatted.first}\r\n\r\n"
                                io.puts "Die meisten Mails gehen durch, aber manche nicht. Wir arbeiten an einer Lösung des Problems. Bitte entschuldigen Sie die Unannehmlichkeiten.\r\n\r\n"
                                io.puts "Bitte senden Sie Ihre E-Mail noch einmal direkt an die folgenden Empfängeraddressen, die Sie per Copy & Paste in BCC setzen können:\r\n\r\n"
                                io.puts "#{recipients[:pending].join(', ')}\r\n\r\n"
                                io.puts "Bitte beachten Sie, dass sich die oben stehenden Empfängeradressen in Zukunft ändern können. Wir bitten Sie deshalb um Geduld und darum, weiterhin die E-Mail-Verteileradressen zu verwenden.\r\n\r\n"
                                io.puts "Bei Fragen schreiben Sie bitte an #{WEBSITE_MAINTAINER_EMAIL}.\r\n\r\n"
                                io.puts "Vielen Dank für Ihr Verständnis!\r\n\r\n"
                                io.string
                            end
                            deliver_mail(_body) do
                                to _sender
                                cc WEBSITE_MAINTAINER_EMAIL
                                bcc SMTP_FROM
                                from SMTP_FROM
                                subject _subject
                            end
                            # 2. rename recipients.yaml to recipients.yaml.failed
                            FileUtils::mv(path, path + '.failed')
                            # 3. break from loop
                            break
                        end
                        recipients[:pending].delete_at(0)
                        recipients[:sent] << recipient
                        File.open(path, 'w') do |f|
                            f.puts recipients.to_yaml
                        end
                        sleep 0.1
                    end
                    if File.exist?(path)
                        FileUtils::mv(path, path + '.archived')
                    end
#                     File.open(mail_path, 'w') { |f| f.puts 'nothing to see here' }
                end
                sleep MAIL_FORWARDER_SLEEP
            end
        end
        t1.join
        t2.join
    end
end

script = Script.new
script.run
