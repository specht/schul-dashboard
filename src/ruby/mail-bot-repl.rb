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

$neo4j = Neo4jGlobal.new

class MailBotRepl < Sinatra::Base
    configure do
        set :show_exceptions, false
    end

    def self.perform_update()
        @@lessons = Main.class_variable_get(:@@lessons)
        @@user_info = Main.class_variable_get(:@@user_info)
        STDERR.puts "Sending pending emails!"
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
            lehrer_email = row['ut.email']
            sus_email = row['us.email']
            reason = mail[:reason]
            details = mail[:details]
            tag = mail[:tag]
            STDERR.puts "#{tag} / #{lesson_key} / #{lesson_offset} / #{lehrer_email} / #{sus_email} / #{reason} / #{details}"
            $neo4j.transaction do
                deliver_mail do
                    from SMTP_FROM
                    reply_to lehrer_email
                    cc sus_email
                    to "eltern." + sus_email
                    bcc lehrer_email
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
