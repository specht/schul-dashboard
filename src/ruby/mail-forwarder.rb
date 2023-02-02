#!/usr/bin/env ruby

require 'mail'
require 'yaml'
require 'net/imap'
require './main.rb'

MAIL_FORWARDER_SLEEP = DEVELOPMENT ? 60 : 60
MAIL_FORWARD_BATCH_SIZE = 30

Mail.defaults do
  delivery_method :smtp, { 
      :address => SCHUL_MAIL_LOGIN_SMTP_HOST,
      :port => 587,
      :domain => SCHUL_MAIL_DOMAIN,
      :user_name => MAILING_LIST_EMAIL,
      :password => MAILING_LIST_PASSWORD,
      :authentication => 'plain',
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
        results |= Set.new(@@user_info.keys.select { |email| @@user_info[email][:teacher] })
        results |= Set.new(SV_USERS)
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
                    next if line[0] == '#'
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
                imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
                imap.authenticate('PLAIN', MAILING_LIST_EMAIL, MAILING_LIST_PASSWORD)
                imap.select('INBOX')
                imap.search(['NOT', 'DELETED']).each do |mid|
                    body = imap.fetch(mid, 'RFC822')[0].attr['RFC822']
                    mail = Mail.read_from_string(body)
                    from_address = Mail::Address.new(mail.from.first).address
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
                        unless allowed_senders().include?(from_address.downcase)
                            STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Bouncing mail back to invalid sender #{mail.from[0]}: #{mail.subject}"
                            mail.reply_to = "#{MAIL_SUPPORT_NAME} <#{MAIL_SUPPORT_EMAIL}>"
                            mail.to = ["#{mail.from[0]}"]
                            mail.from = [MAILING_LIST_EMAIL]
                            mail.cc = []
                            mail.bcc = []
                            mail.subject = "[Nicht zustellbar: Ungültige Absender-Adresse] #{mail.subject}"
                            mail.body = "Sie haben versucht, eine E-Mail an den Verteiler zu schicken,  allerdings ist Ihre Absender-Adresse nicht für den Versand an Verteileradressen freigeschaltet.\r\n\r\nBitte verwenden Sie Ihre schulische E-Mail-Adresse oder schreiben Sie eine E-Mail an #{MAIL_SUPPORT_EMAIL}, um sich für den Versand freischalten zu lassen.\r\n\r\n"
                            mail.deliver!
                            imap.copy(mid, 'Bounced')
                        else
                            all_recipients = Set.new
                            recipients = ((mail.to || []) + (mail.cc || []) + (mail.bcc || []))
                            recipients.each do |m|
                                if fresh_mailing_list().include?(m.downcase)
                                    all_recipients |= Set.new(fresh_mailing_list()[m.downcase][:recipients])
                                end
                            end
                            File.open(recipients_path, 'w') do |f|
                                data = {:pending => all_recipients.to_a.sort,
                                        :sent => []}
                                f.puts data.to_yaml
                            end
                            STDERR.puts "Received new mail: #{mail_subject} (#{mail.message_id}) for #{all_recipients.size} recipients..."
                            imap.copy(mid, 'Forwarded')
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
            sleep MAIL_FORWARDER_SLEEP / 2
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
                    mail = Mail.read_from_string(File.read(mail_path))
                    mail.to = nil
                    mail.cc = []
                    mail.bcc = []
                    mail.reply_to = mail[:from].formatted.first
#                     mail.from = ["#{mail[:from].formatted.first.gsub(/<[^>]+>/, '').strip} <#{MAILING_LIST_EMAIL}>"]
                    recipients = YAML::load(File.read(path))
                    while !recipients[:pending].empty?
                        recipient = recipients[:pending].first
                        mail.to = recipient
                        STDERR.puts "Forwarding mail to #{recipient...}"
                        mail.deliver!
                        recipients[:pending].delete_at(0)
                        recipients[:sent] << recipient
                        File.open(path, 'w') do |f|
                            f.puts recipients.to_yaml
                        end
                        sleep 0.1
                    end
                    FileUtils::mv(path, path + '.archived')
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
