REASON_TO_KEY = {
    'material' => 'material',
    'homework' => 'hausaufgaben',
    'signature' => 'unterschrift',
}

class Main < Sinatra::Base
    post '/api/send_email' do
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        # comment: for this one student, in addition to the note (details)
        # that is the same for all students the teacher picked; text: the
        # whole text of the mail, changed by the teacher for this student
        data = parse_request_data(:required_keys => [:email, :reason, :details, :lesson_key, :lesson_offset, :datum],
                                  :optional_keys => [:comment, :text],
                                  :types => {:lesson_offset => Integer},
                                  :max_value_lengths => {:details => 2048, :comment => 2048, :text => LessonMailTemplates::MAX_BODY_LENGTH},
                                  :max_body_length => 16 * 1024)
        comment = data[:comment].to_s.strip
        text = data[:text].to_s.gsub(/\r\n?/, "\n").strip
        # a lesson, or a class teacher's mail about a student of their class
        # (one LessonInfo per day)
        assert(lesson_mail_key_allowed?(data[:lesson_key], data[:email]), 'unknown lesson')
        data[:lesson_offset] = Main.class_mail_offset if Main.class_mail_klasse(data[:lesson_key])
        # rules of the reason (/unterrichtsmails): own templates in the state
        # 'test' only for admins, their mails go to the sender alone
        # (mail-bot-repl.rb); reasons the Otium sends only for the Otium
        reason_info = LessonMailTemplates.find(stored_lesson_mail_templates, data[:reason])
        assert(LessonMailTemplates.sendable?(reason_info, admin_logged_in?, user_with_role_logged_in?(:otium)), 'unknown reason')
        test = reason_info[:status] == 'test'
        # no student address, reason or details in the log
        debug "Mail about a lesson: #{data[:lesson_key]}/#{data[:lesson_offset]}#{test ? ' (test)' : ''}"
        t = DateTime.parse(DateTime.now.strftime("%Y-%m-%dT%H:%M:00%z")).to_time
        unless DEVELOPMENT
            while t.min % 10 != 0
                t += 60
            end
            t += 600
        end
        ts = t.strftime("%Y-%m-%dT%H:%M:%S")
        ts_h = t.strftime("%H:%M")
        ts_i = t.to_i
        tag = RandomTag.generate(24)
        datum = Date.today.strftime('%Y-%m-%d')
        neo4j_query_expect_one(<<~END_OF_QUERY, {:tag => tag, :teacher_email => @session_user[:email], :sus_email => data[:email], :reason => data[:reason], :details => data[:details], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :datum => data[:datum], :ts => ts_i, :test => test, :comment => comment.empty? ? nil : comment, :text => text.empty? ? nil : text})
            MATCH (ut:User {email: $teacher_email})
            MATCH (us:User {email: $sus_email})
            MERGE (l:Lesson {key: $lesson_key})
            MERGE (i:LessonInfo {offset: $lesson_offset})-[:BELONGS_TO]->(l)
            CREATE (us)<-[:SENT_TO]-(m:Mail {tag: $tag, reason: $reason, details: $details, ts: $ts})-[:SENT_BY]->(ut)
            SET m.test = CASE WHEN $test THEN true ELSE null END, m.comment = $comment, m.text = $text
            CREATE (m)-[:REGARDING]->(i)
            RETURN m;
        END_OF_QUERY

        entry = {
            :tag => tag,
            :reason => data[:reason],
            :test => test,
            :details => data[:details],
            :comment => comment,
            :ts => ts_i,
            :ts_h => Time.at(ts_i).strftime('%H:%M'),
            :ts_sent => nil,
            :ts_sent_h => nil,
        }
        respond(:entry => entry)
    end

    post '/api/get_pending_mails' do
        # get pending mails for current teacher
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        results = {}
        neo4j_query(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset]}).each do |row|
            MATCH (l:Lesson {key: $lesson_key})<-[:BELONGS_TO]-(i:LessonInfo {offset: $lesson_offset})<-[:REGARDING]-(m:Mail)-[:SENT_BY]->(u:User {email: $teacher_email})
            MATCH (m)-[:SENT_TO]->(us:User)
            RETURN m.tag AS tag, m.reason AS reason, m.details AS details, m.ts AS ts, m.ts_sent AS ts_sent, us.email AS email, m.test AS test, m.comment AS comment
            ORDER BY ts;
        END_OF_QUERY
            results[row['email']] ||= []
            results[row['email']] << {
                :tag => row['tag'],
                :reason => row['reason'],
                :test => row['test'] == true,
                :details => row['details'],
                :comment => row['comment'] || '',
                :ts => row['ts'],
                :ts_h => Time.at(row['ts']).strftime('%H:%M'),
                :ts_sent => row['ts_sent'],
                :ts_sent_h => row['ts_sent'].nil? ? nil : Time.at(row['ts_sent']).strftime('%H:%M'),
            }
        end
        respond(:results => results)
    end

    # The whole mail of a queued or sent mail, for the list below the
    # students in the mail dialog; only for the person who sent it. Rendered
    # with today's text of the reason, test mails marked like the mail bot does.
    post '/api/preview_queued_email' do
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        data = parse_request_data(:required_keys => [:tag])
        rows = neo4j_query(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :tag => data[:tag]})
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:REGARDING]-(m:Mail {tag: $tag})-[:SENT_BY]->(u:User {email: $teacher_email})
            MATCH (m)-[:SENT_TO]->(us:User)
            RETURN m, l.key AS lesson_key, us.email AS sus_email;
        END_OF_QUERY
        assert(rows.size == 1, 'unknown mail')
        row = rows.first
        mail = row['m']
        stored = stored_lesson_mail_templates
        template = LessonMailTemplates.effective(stored, mail[:reason])
        assert(template, 'unknown reason')
        vars = Main.lesson_mail_vars(row['sus_email'], row['lesson_key'], @session_user[:email], mail[:details], mail[:comment])
        rendered = LessonMailTemplates.render(template, vars, mail[:text])
        if mail[:test] == true
            info = LessonMailTemplates.find(stored, mail[:reason]) || {}
            rendered = LessonMailTemplates.mark_as_test(rendered, info[:label] || mail[:reason], "#{vars[:name]} (#{vars[:klasse]})")
        end
        respond(:subject => rendered[:subject], :html => rendered[:html])
    end

    post '/api/cancel_email' do
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        data = parse_request_data(:required_keys => [:tag],
                                  :types => {:lesson_offset => Integer})
        transaction do
            neo4j_query_expect_one(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :tag => data[:tag]})
                MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:REGARDING]-(m:Mail {tag: $tag})-[:SENT_BY]->(u:User {email: $teacher_email})
                WHERE m.ts_sent IS NULL
                RETURN m;
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :tag => data[:tag]})
                MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:REGARDING]-(m:Mail {tag: $tag})-[:SENT_BY]->(u:User {email: $teacher_email})
                WHERE m.ts_sent IS NULL
                DETACH DELETE m;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end
end
