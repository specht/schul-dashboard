REASON_TO_KEY = {
    'material' => 'material',
    'homework' => 'hausaufgaben',
    'signature' => 'unterschrift',
}

class Main < Sinatra::Base
    post '/api/send_email' do
        assert(teacher_logged_in? || user_with_role_logged_in?(:otium))
        data = parse_request_data(:required_keys => [:email, :reason, :details, :lesson_key, :lesson_offset, :datum],
                                  :types => {:lesson_offset => Integer})
        debug data.to_yaml
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
        neo4j_query_expect_one(<<~END_OF_QUERY, {:tag => tag, :teacher_email => @session_user[:email], :sus_email => data[:email], :reason => data[:reason], :details => data[:details], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :datum => data[:datum], :ts => ts_i})
            MATCH (ut:User {email: $teacher_email})
            MATCH (us:User {email: $sus_email})
            MERGE (l:Lesson {key: $lesson_key})
            MERGE (i:LessonInfo {offset: $lesson_offset})-[:BELONGS_TO]->(l)
            CREATE (us)<-[:SENT_TO]-(m:Mail {tag: $tag, reason: $reason, details: $details, ts: $ts})-[:SENT_BY]->(ut)
            CREATE (m)-[:REGARDING]->(i)
            RETURN m;
        END_OF_QUERY

        entry = {
            :tag => tag,
            :reason => data[:reason],
            :details => data[:details],
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
            RETURN m.tag AS tag, m.reason AS reason, m.details AS details, m.ts AS ts, m.ts_sent AS ts_sent, us.email AS email
            ORDER BY ts;
        END_OF_QUERY
            results[row['email']] ||= []
            results[row['email']] << {
                :tag => row['tag'],
                :reason => row['reason'],
                :details => row['details'],
                :ts => row['ts'],
                :ts_h => Time.at(row['ts']).strftime('%H:%M'),
                :ts_sent => row['ts_sent'],
                :ts_sent_h => row['ts_sent'].nil? ? nil : Time.at(row['ts_sent']).strftime('%H:%M'),
            }
        end
        respond(:results => results)
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
