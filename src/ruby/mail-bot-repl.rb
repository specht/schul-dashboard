#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 60

class Neo4jGlobal
    include Neo4jBolt
end

Thread.abort_on_exception = true

$neo4j = Neo4jGlobal.new

class MailBotRepl < Sinatra::Base
    configure do
        set :show_exceptions, false
    end

    def self.perform_update()
        @@config = Main.class_variable_get(:@@config)
        @@klassenleiter = Main.class_variable_get(:@@klassenleiter)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@user_info = Main.class_variable_get(:@@user_info)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        ts = Time.now.to_i
        ts += 20 * 60 if DEVELOPMENT
        $neo4j.neo4j_query(<<~END_OF_QUERY, {:ts => ts}).each do |row|
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:REGARDING]-(m:Mail)-[:SENT_BY]->(ut:User)
            MATCH (m)-[:SENT_TO]->(us:User)
            WHERE m.ts_sent IS NULL AND $ts > m.ts
            RETURN m, l, i, ut.email, us.email;
        END_OF_QUERY
            mail = row['m']
            lesson_key = row['l'][:key]
            lesson_offset = row['i'][:offset]
            begin
                lehrer_email = @@shorthands[@@lessons[:lesson_keys][lesson_key][:lehrer].first]
            rescue
                lehrer_email = row['ut.email']
            end
            sus_email = row['us.email']
            reason = mail[:reason]
            details = mail[:details]
            tag = mail[:tag]
            current_year = @@config[:first_school_day].split('-').first.to_i
            year_key = "#{current_year}_#{(current_year + 1) % 100}"
            klasse = @@user_info[sus_email][:klasse]
            kl_cc_key = "#{year_key}/#{klasse}"
            cc_emails = []
            cc_emails << sus_email
            cc_emails << row['ut.email']
            if EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC.include?(kl_cc_key) || reason == 'disturbance_otium'
                @@klassenleiter[klasse].each do |shorthand|
                    if @@shorthands[shorthand]
                        cc_emails << @@shorthands[shorthand]
                    end
                end
            end
            STDERR.puts "#{tag} / #{lesson_key} / #{lesson_offset} / #{lehrer_email} / #{sus_email} / #{reason} / #{details}"
            $neo4j.transaction do
                deliver_mail do
                    from SMTP_FROM
                    reply_to lehrer_email
                    cc cc_emails
                    to "eltern." + sus_email
                    bcc SMTP_FROM
                    if reason == 'material'
                        subject "Fehlendes Arbeitsmaterial im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]}"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "hat heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} das Arbeitsmaterial nicht oder nicht vollständig dabei gehabt"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.puts "Bitte üben Sie mit #{@@user_info[sus_email][:display_first_name]}, die Schultasche sorgfältig zu packen.</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'homework'
                        subject "Fehlende Hausaufgaben im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]}"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "hat heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} die Hausaufgaben nicht oder nicht vollständig vorlegen können"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.puts "Bitte sprechen auch Sie mit #{@@user_info[sus_email][:display_first_name]} über die Notwendigkeit, die Hausaufgaben sorgfältig und vollständig anzufertigen und mitzubringen.</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'signature'
                        subject "Fehlende Unterschrift"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "hat heute eine geforderte Unterschrift nicht vorlegen können"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.puts "Bitte geben Sie diese Ihrem Kind morgen mit.</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'disturbance'
                        subject "Störverhalten"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "fiel heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} durch "
                            io.print "Störverhalten und Unaufmerksamkeit auf"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.print "Dies hatte nicht nur negative Folgen für #{@@user_info[sus_email][:geschlecht] == 'm' ? 'seine' : 'ihre'} eigene Konzentration, sondern war "
                            io.print "auch zum Nachteil für die gesamte Klasse. Bitte sprechen Sie mit #{@@user_info[sus_email][:display_first_name]} über die "
                            io.print "Notwendigkeit, dem Unterricht aufmerksam zu folgen und Störverhalten im Unterricht zu unterlassen."
                            io.puts "</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'disturbance_otium'
                        subject "Störverhalten (Otium)"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "zeigte heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} ein derart "
                            io.print "ausgeprägtes Störverhalten"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}), "
                            else
                                io.print ", "
                            end
                            io.print "dass ich #{@@user_info[sus_email][:geschlecht] == 'm' ? 'ihn' : 'sie'} "
                            io.print "im Sinne #{@@user_info[sus_email][:geschlecht] == 'm' ? 'seiner' : 'ihrer'} Mitschüler:innen "
                            io.print "als pädagogische Maßnahme vorübergehend vom Unterricht ausschließen musste."
                            io.puts "</p>"
                            io.puts "<p>"
                            io.print "#{@@user_info[sus_email][:geschlecht] == 'm' ? 'Er' : 'Sie'} hat die Zeit im Otium verbracht "
                            io.print "und muss die versäumten Unterrichtsinhalte selbständig nacharbeiten."
                            io.print "Bitte sprechen Sie eingehend mit #{@@user_info[sus_email][:display_first_name]} über die "
                            io.print "Konsequenzen #{@@user_info[sus_email][:geschlecht] == 'm' ? 'seines' : 'ihres'} Verhaltens."
                            io.puts "</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'late'
                        subject "Verspätung"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "hat heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} einen "
                            io.print "Klassenbucheintrag aufgrund einer Verspätung erhalten"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.puts "</p>"
                            io.puts "<p>"
                            io.print "Bitte beachten Sie, dass diese E-Mail nur eine einzelfallbezogene "
                            io.print "Rückmeldung darstellt und sich daraus kein Anspruch auf die vollständige "
                            io.print "Meldung vergangener und zukünftiger Verspätungen ergibt."
                            io.puts "</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    elsif reason == 'praise'
                        subject "Lob"
                        StringIO.open do |io|
                            io.puts "<p>Liebe Eltern,</p>"
                            io.print "<p>"
                            io.print "ich freue mich, Ihnen mitteilen zu können, dass "
                            io.print @@user_info[sus_email][:geschlecht] == 'm' ? 'Ihr Sohn' : 'Ihre Tochter'
                            io.print ' '
                            io.print @@user_info[sus_email][:display_first_name]
                            io.print ' '
                            io.print "heute im Fach #{@@lessons[:lesson_keys][lesson_key][:pretty_fach]} durch "
                            io.print "besonders erwähnenswerte positive Leistungen aufgefallen ist"
                            unless (details || '').strip.empty?
                                io.print " (#{details.strip}). "
                            else
                                io.print ". "
                            end
                            io.print "Bitte loben Sie #{@@user_info[sus_email][:geschlecht] == 'm' ? 'ihn' : 'sie'} "
                            io.print "für #{@@user_info[sus_email][:geschlecht] == 'm' ? 'sein' : 'ihr'} Engagement "
                            io.print "und #{@@user_info[sus_email][:geschlecht] == 'm' ? 'seine' : 'ihre'} Leistungsbereitschaft."
                            io.puts "</p>"
                            io.puts "<p>Mit freundlichen Grüßen<br>"
                            io.puts "#{@@user_info[lehrer_email][:display_name]}</p>"

                            io.string
                        end
                    end
                end
                $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, {:tag => tag, :ts => ts})
                    MATCH (m:Mail {tag: $tag})
                    WHERE m.ts_sent IS NULL
                    SET m.ts_sent = $ts
                    RETURN m;
                END_OF_QUERY
            end
        end
    end

    configure do
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
        @@worker_thread = Thread.new do
            future_queue = {}
            while true do
                entry = @@queue.pop
                self.perform_update()
            end
        end
    end

    get '/api/send_pending_mails' do
        @@queue << {:which => :all}
    end

    run! if app_file == $0
end
