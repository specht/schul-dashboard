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
        @mailing_lists = {}
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@teachers_for_klasse = Main.class_variable_get(:@@teachers_for_klasse)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@user_info = Main.class_variable_get(:@@user_info)
        @@klassen_order.each do |klasse|
            next unless @@schueler_for_klasse.include?(klasse)
            @mailing_lists["klasse.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "Klasse #{klasse}",
                :recipients => @@schueler_for_klasse[klasse]
            }
            @mailing_lists["eltern.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "Eltern der Klasse #{klasse}",
                :recipients => @@schueler_for_klasse[klasse].map do |email|
                    "eltern.#{email}"
                end
            }
            @mailing_lists["lehrer.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "Lehrer der Klasse #{klasse}",
                :recipients => ((@@teachers_for_klasse[klasse] || {}).keys.sort).map do |shorthand|
                    email = @@shorthands[shorthand]
                end.reject do |email|
                    email.nil?
                end
            }
        end
        if DEVELOPMENT
            VERTEILER_TEST_EMAILS.each do |email|
                @mailing_lists[email] = {
                    :label => "Dev-Verteiler #{email}",
                    :recipients => VERTEILER_DEVELOPMENT_EMAILS
                }
            end
        end
        begin
            imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
        rescue
            STDERR.puts "Unable to resolve #{SCHUL_MAIL_LOGIN_IMAP_HOST}, exiting..."
            exit(1)
        end
        STDERR.puts "Mail forwarder ready with #{@mailing_lists.size} mailing lists at #{MAILING_LIST_EMAIL}!"
    end
    
    def allowed_senders()
        results = Set.new()
        results |= Set.new(@@user_info.keys.select { |email| @@user_info[email][:teacher] })
        results |= Set.new(SV_USERS)
        path = '/app/mail-forwarder-emails.txt'
        if File.exists?(path)
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
            imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
            imap.authenticate('LOGIN', MAILING_LIST_EMAIL, MAILING_LIST_PASSWORD)
            imap.select('INBOX')
            loop do
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
                    unless File.exists?(mail_path)
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
                                if @mailing_lists.include?(m.downcase)
                                    all_recipients |= Set.new(@mailing_lists[m.downcase][:recipients])
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
                    FileUtils::rm_f(path)
                    File.open(mail_path, 'w') { |f| f.puts 'nothing to see here' }
                end
                sleep MAIL_FORWARDER_SLEEP
            end
        end
        t1.join
        t2.join
#         
#         while !@shutdown do
#             imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
#             imap.authenticate('LOGIN', MAILING_LIST_EMAIL, MAILING_LIST_PASSWORD)
#             imap.select('INBOX')
#             
#             imap.search(['NOT', 'DELETED']).each do |mid|
#                 STDERR.puts "[#{mid}]"
#                 body = imap.fetch(mid, 'RFC822')[0].attr['RFC822']
#                 mail = Mail.read_from_string(body)
#                 mail_body = mail.body
#                 mail_subject = mail.subject
#                 message_id = mail.message_id
#                 storage_path = "/mails/#{message_id[0, 2]}/#{message_id}/mail"
#                 STDERR.puts storage_path
#                 if File.exists?(storage_path) || mail.header[VERTEILER_MAIL_HEADER]
#                     imap.store(mid, '+FLAGS', [:Deleted])
#                     next
#                 end
#                 FileUtils.mkpath(File::dirname(storage_path))
#                 FileUtils.mkpath(File.join(File::dirname(storage_path), 'recipients'))
#                 File.open(storage_path, 'w') do |f|
#                     f.puts body
#                 end
#                 STDERR.puts mail_subject
#                 STDERR.puts mail.message_id
#                 recipients = ((mail.to || []) + (mail.cc || []) + (mail.bcc || [])).sort.uniq
#                 recipients.each do |m|
#                     real_emails = [m]
#                     if @mailing_lists.include?(m.downcase)
#                         real_emails = @mailing_lists[m.downcase][:recipients]
#                     end
#                     real_emails.each do |email|
#                         File.open(File.join(File::dirname(storage_path), 'recipients', email), 'w') do |f|
#                         end
#                     end
#                 end
#                 next
#                 if recipients.include?(MAILING_LIST_EMAIL)
#                     STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Bouncing mail back to #{mail.from[0]}: #{mail.subject}"
#                     mail.reply_to = "#{MAIL_SUPPORT_NAME} <#{MAIL_SUPPORT_EMAIL}>"
#                     mail.to = ["#{mail.from[0]}"]
#                     mail.from = [MAILING_LIST_EMAIL]
#                     mail.cc = []
#                     mail.subject = "[Nicht zustellbar: Keine gültige Verteiler-Adresse] #{mail_subject}"
#                     mail.body = "Sie haben versucht, eine E-Mail an den Verteiler zu schicken, ohne eine gültige Empfänger-E-Mail-Adresse anzugeben. Die angegebene Empfänger-E-Mail-Adresse lautete:\r\n\r\n#{MAILING_LIST_EMAIL}\r\n\r\nÜberprüfen Sie bitte die E-Mail-Adresse und versuchen Sie es erneut.\r\n\r\nBei Fragen wenden Sie sich bitte an #{MAIL_SUPPORT_EMAIL}\r\n\r\n"
#                     mail.deliver!
#                     imap.copy(mid, 'Bounced')
#                     imap.store(mid, '+FLAGS', [:Deleted])
#                 else
#                     recipients.each do |to|
#                         key = to.downcase
#                         if @mailing_lists.include?(key) && !mail.from[0].include?('@kundenserver.de')
#                             STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Forwarding mail from #{mail.from[0]} to #{@mailing_lists[key][:label]} (#{@mailing_lists[key][:recipients].size} recipients): #{mail.subject}"
#                             @mailing_lists[key][:recipients].each_slice(MAIL_FORWARD_BATCH_SIZE) do |batch|
#                                 STDERR.puts "Forwarding mail to batch of #{batch.size} recipients..."
#                                 mail.reply_to = mail[:from].formatted.first
#                                 mail.from = ["#{mail[:from].formatted.first.gsub(/<[^>]+>/, '').strip} <#{MAILING_LIST_EMAIL}>"]
#                                 mail.cc = []
#                                 mail.bcc = batch
#                                 mail.to = ["#{@mailing_lists[key][:label]} <#{key}>"]
#         #                         mail.sender = [MAILING_LIST_EMAIL]
#                                 mail.header[VERTEILER_MAIL_HEADER] = 'yes'
#                                 mail.deliver!
#                                 sleep 1.0
#                             end
#                         end
#                     end
#                     imap.copy(mid, 'Forwarded')
#                     imap.store(mid, '+FLAGS', [:Deleted])
#                 end
#             end
#             imap.expunge
#             imap.logout
#             imap.disconnect
#             MAIL_FORWARDER_SLEEP.times do 
#                 sleep 1
#                 break if @shutdown
#             end
#         end
#         STDERR.puts "Shutting down mail forwarder..."
    end
end

script = Script.new
script.run
