#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 60
# a parent mail that fails this often is skipped
MAX_SEND_ERRORS = 3
# classes ("2026_27/5a") whose class teachers get a copy of every mail;
# set in credentials.rb
EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC = [] unless defined?(EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC)

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
        # texts changed by admins on /unterrichtsmails, defaults otherwise
        templates = LessonMailTemplates.from_nodes($neo4j.neo4j_query("MATCH (t:LessonMailTemplate) RETURN t;").map { |row| row['t'] })
        $neo4j.neo4j_query(<<~END_OF_QUERY, {:ts => ts, :max_errors => MAX_SEND_ERRORS}).each do |row|
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:REGARDING]-(m:Mail)-[:SENT_BY]->(ut:User)
            MATCH (m)-[:SENT_TO]->(us:User)
            WHERE m.ts_sent IS NULL AND $ts > m.ts AND COALESCE(m.send_errors, 0) < $max_errors
            RETURN m, l, i, ut.email, us.email;
        END_OF_QUERY
            # One mail that cannot be sent (e.g. its student left the school) must
            # not stop the others: before, the error ended the process, and after the
            # restart the same mail came first again. Failed mails are counted and
            # skipped after MAX_SEND_ERRORS attempts.
            begin
                mail = row['m']
                lesson_key = row['l'][:key]
                lesson_offset = row['i'][:offset]
                # the person who sends the mail signs it and gets the replies
                # (for Otium mails the teacher on Otium duty)
                lehrer_email = row['ut.email']
                sus_email = row['us.email']
                reason = mail[:reason]
                details = mail[:details]
                tag = mail[:tag]
                current_year = @@config[:first_school_day].split('-').first.to_i
                year_key = "#{current_year}_#{(current_year + 1) % 100}"
                klasse = @@user_info[sus_email][:klasse]
                kl_cc_key = "#{year_key}/#{klasse}"
                # a mail with an own template in the state 'test' (marked when
                # it was sent) goes to the sender alone
                test = mail[:test] == true
                info = LessonMailTemplates.find(templates, reason) || {}
                klassenleitung = []
                # the class teachers get a copy where the reason says so
                # (/unterrichtsmails) or for the classes set in credentials.rb
                if EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC.include?(kl_cc_key) || info[:cc_klassenleitung]
                    klassenleitung = (@@klassenleiter[klasse] || []).map { |shorthand| @@shorthands[shorthand] }.compact
                end
                # the lesson's teacher hears about mails others send (Otium)
                # the teacher of the lesson: the one of a Vertretung, kept with the mail
                envelope = LessonMailTemplates.envelope(test: test, sender: lehrer_email, student: sus_email,
                                                        lesson_teacher: mail[:lesson_teacher] || Main.lesson_mail_lesson_teacher(lesson_key),
                                                        klassenleitung: klassenleitung)
                # no addresses or details (about a student) in the log
                debug "Sending parent mail #{tag} / #{lesson_key} / #{lesson_offset} / #{reason}#{test ? ' (test)' : ''}"
                template = LessonMailTemplates.effective(templates, reason)
                raise "no text for #{reason}" if template.nil?
                vars = Main.lesson_mail_vars(sus_email, lesson_key, lehrer_email, details, mail[:comment], mail[:datum],
                                             {:fach => mail[:fach], :lesson_teacher => mail[:lesson_teacher]}.compact)
                # a text the teacher changed for this student, else the template's
                rendered = LessonMailTemplates.render(template, vars, mail[:text])
                if test
                    rendered = LessonMailTemplates.mark_as_test(rendered, info[:label] || reason, "#{vars[:name]} (#{vars[:klasse]})")
                end
                $neo4j.transaction do
                    deliver_mail do
                        from SMTP_FROM
                        reply_to lehrer_email
                        cc envelope[:cc] unless envelope[:cc].empty?
                        to envelope[:to]
                        bcc SMTP_FROM if envelope[:archive]
                        subject rendered[:subject]
                        rendered[:html]
                    end
                    $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, {:tag => tag, :ts => ts})
                        MATCH (m:Mail {tag: $tag})
                        WHERE m.ts_sent IS NULL
                        SET m.ts_sent = $ts
                        RETURN m;
                    END_OF_QUERY
                end
            rescue StandardError => e
                debug_error "Mail #{(row['m'] || {})[:tag]} not sent: #{e.class}: #{e.message.to_s[0, 200]}"
                $neo4j.neo4j_query(<<~END_OF_QUERY, {:tag => (row['m'] || {})[:tag]})
                    MATCH (m:Mail {tag: $tag})
                    SET m.send_errors = COALESCE(m.send_errors, 0) + 1;
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
        # a worker thread that dies shows up on /dienste and in the watchdog's mail
        ServiceStatus.watch('worker', @@worker_thread)
    end

    get '/api/send_pending_mails' do
        @@queue << {:which => :all}
    end

    run! if app_file == $0
end
