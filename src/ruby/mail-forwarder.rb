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
        @shutdown = false
        Signal.trap("TERM") do 
            STDERR.puts "Caught SIGTERM"
            @shutdown = true
        end
        @mailing_lists = {}
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@teachers_for_klasse = Main.class_variable_get(:@@teachers_for_klasse)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@klassen_order.each do |klasse|
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
            @mailing_lists[VERTEILER_TEST_ADRESSE] = {
                :label => "Dev-Verteiler",
                :recipients => VERTEILER_DEVELOPMENT_EMAILS
            }
        end
        STDERR.puts "Mail forwarder ready with #{@mailing_lists.size} mailing lists at #{MAILING_LIST_EMAIL}!"
    end
    
    def run
        while !@shutdown do
            imap = Net::IMAP.new(SCHUL_MAIL_LOGIN_IMAP_HOST)
            imap.authenticate('LOGIN', MAILING_LIST_EMAIL, MAILING_LIST_PASSWORD)
            imap.select('INBOX')
            
            imap.search(['NOT', 'DELETED']).each do |mid|
                STDERR.puts "[#{mid}]"
                env = imap.fetch(mid, 'ENVELOPE')[0].attr['ENVELOPE']
                body = imap.fetch(mid, 'RFC822')[0].attr['RFC822']
                mail = Mail.read_from_string(body)
                mail_body = mail.body
                mail_subject = mail.subject
                if mail.header[VERTEILER_MAIL_HEADER]
                    imap.store(mid, '+FLAGS', [:Deleted])
                else
                    recipients = ((mail.to || []) + (mail.cc || [])).sort.uniq
                    if recipients.include?(MAILING_LIST_EMAIL)
                        STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Bouncing mail back to #{mail.from[0]}: #{mail.subject}"
                        mail.reply_to = "#{MAIL_SUPPORT_NAME} <#{MAIL_SUPPORT_EMAIL}>"
                        mail.to = ["#{mail.from[0]}"]
                        mail.from = [MAILING_LIST_EMAIL]
                        mail.cc = []
                        mail.subject = "[Nicht zustellbar: Keine gültige Verteiler-Adresse] #{mail_subject}"
                        mail.body = "Sie haben versucht, eine E-Mail an den Verteiler zu schicken, ohne eine gültige Empfänger-E-Mail-Adresse anzugeben. Die angegebene Empfänger-E-Mail-Adresse lautete:\r\n\r\n#{MAILING_LIST_EMAIL}\r\n\r\nÜberprüfen Sie bitte die E-Mail-Adresse und versuchen Sie es erneut.\r\n\r\nBei Fragen wenden Sie sich bitte an #{MAIL_SUPPORT_EMAIL}\r\n\r\n"
                        mail.deliver!
                        imap.copy(mid, 'Bounced')
                        imap.store(mid, '+FLAGS', [:Deleted])
                    else
                        recipients.each do |to|
                            key = to.downcase
                            if @mailing_lists.include?(key) && !mail.from[0].include?('@kundenserver.de')
                                STDERR.puts "[#{Time.now.strftime('%Y-%m-%d %H:%M')}] Forwarding mail from #{mail.from[0]} to #{@mailing_lists[key][:label]} (#{@mailing_lists[key][:recipients].size} recipients): #{mail.subject}"
                                @mailing_lists[key][:recipients].each_slice(MAIL_FORWARD_BATCH_SIZE) do |batch|
                                    STDERR.puts "Forwarding mail to batch of #{batch.size} recipients..."
                                    mail.reply_to = mail[:from].formatted.first
                                    mail.from = ["#{mail[:from].formatted.first.gsub(/<[^>]+>/, '').strip} <#{MAILING_LIST_EMAIL}>"]
                                    mail.cc = []
                                    mail.bcc = batch
                                    mail.to = ["#{@mailing_lists[key][:label]} <#{key}>"]
            #                         mail.sender = [MAILING_LIST_EMAIL]
                                    mail.header[VERTEILER_MAIL_HEADER] = 'yes'
                                    mail.deliver!
                                    sleep 5.0
                                end
                            end
                        end
                        imap.copy(mid, 'Forwarded')
                        imap.store(mid, '+FLAGS', [:Deleted])
                    end
                end
            end
            imap.expunge
            imap.logout
            imap.disconnect
            MAIL_FORWARDER_SLEEP.times do 
                sleep 1
                break if @shutdown
            end
        end
    end
end

script = Script.new
script.run
