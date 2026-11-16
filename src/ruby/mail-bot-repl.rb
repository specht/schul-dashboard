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
        templates = {}
        $neo4j.neo4j_query("MATCH (t:LessonMailTemplate) RETURN t;").each do |row|
            templates[row['t'][:reason]] = {:subject => row['t'][:subject], :body => row['t'][:body]}
        end
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
                cc_emails = []
                cc_emails << sus_email
                cc_emails << row['ut.email']
                # the lesson's teacher hears about mails others send (Otium)
                lesson_teacher_email = Main.lesson_mail_lesson_teacher(lesson_key)
                cc_emails << lesson_teacher_email if lesson_teacher_email && lesson_teacher_email != lehrer_email
                if EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC.include?(kl_cc_key) || reason == 'disturbance_otium'
                    @@klassenleiter[klasse].each do |shorthand|
                        if @@shorthands[shorthand]
                            cc_emails << @@shorthands[shorthand]
                        end
                    end
                end
                # no addresses or details (about a student) in the log
                debug "Sending parent mail #{tag} / #{lesson_key} / #{lesson_offset} / #{reason}"
                rendered = LessonMailTemplates.render(LessonMailTemplates.effective(templates, reason),
                                                      Main.lesson_mail_vars(sus_email, lesson_key, lehrer_email, details))
                $neo4j.transaction do
                    deliver_mail do
                        from SMTP_FROM
                        reply_to lehrer_email
                        cc cc_emails.uniq
                        to "eltern." + sus_email
                        bcc SMTP_FROM
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
