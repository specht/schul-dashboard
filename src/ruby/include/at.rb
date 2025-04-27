class Main < Sinatra::Base
    post '/api/get_at_notes_sus_list' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key])
        start_date = @@lessons[:start_date_for_date][Date.today.strftime('%Y-%m-%d')]
        lesson_info = @@lessons[:timetables][start_date][data[:lesson_key]]

        days = Set.new()
        lesson_info[:stunden].each_pair do |day, info|
            days << day
        end
        occasions = days.size

        # give everyone a grade all 4 weeks on average
        n = @@schueler_for_lesson[data[:lesson_key]].size / 4 / occasions
        n = 1 if n < 1
        n = 5 if n > 5
        latest_ts_for_email = {}
        ts_midnight = Time.now.to_i - (Time.now.to_i % 86400)
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :ts_midnight => ts_midnight}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:AT)-[:REGARDING]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WHERE at.ts < $ts_midnight
            RETURN us.email AS email, MAX(at.ts) AS ts;
        END_OF_QUERY
            latest_ts_for_email[row['email']] = Time.at(row['ts']).strftime('%g-%W')
        end
        todays_notes = {}
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :ts_midnight => ts_midnight}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:AT)-[:REGARDING]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WHERE at.ts >= $ts_midnight
            RETURN us.email AS email, at.value AS value;
        END_OF_QUERY
            todays_notes[row['email']] = row['value']
        end
        srand(Date.today.year * 10000 + Date.today.month * 100 + Date.today.day)
        sus_emails = @@schueler_for_lesson[data[:lesson_key]].sort do |a, b|
            ts_a = latest_ts_for_email[a] || 0
            ts_b = latest_ts_for_email[b] || 0
            if (ts_a == ts_b)
                rand <=> rand
            else
                ts_a <=> ts_b
            end
        end

        sus_list = sus_emails.map do |email|
            {:email => email, :first_name => @@user_info[email][:first_name], :last_name => @@user_info[email][:last_name]}
        end

        respond(:sus_list => sus_list, :recommended_count => n, :todays_notes => todays_notes)
    end

    post '/api/set_at_note_for_sus' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset, :email, :value],
                                  :types => {:lesson_offset => Integer, :value => Integer})
        ts = Time.now.to_i
        assert(data[:value] >= 0 && data[:value] <= 5)
        if (data[:value] != 0)
            neo4j_query_expect_one(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :sus_email => data[:email], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :ts => ts, :value => data[:value]})
                MATCH (ut:User {email: $teacher_email})
                MATCH (us:User {email: $sus_email})
                MERGE (l:Lesson {key: $lesson_key})
                MERGE (i:LessonInfo {offset: $lesson_offset})-[:BELONGS_TO]->(l)
                MERGE (us)<-[:FOR]-(at:AT)-[:SET_BY]->(ut)
                SET at.ts = $ts, at.value = $value
                MERGE (at)-[:REGARDING]->(i)
                RETURN at;
            END_OF_QUERY
        else
            neo4j_query(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :sus_email => data[:email], :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :ts => ts})
                MATCH (us:User {email: $sus_email})<-[:FOR]-(at:AT)-[:REGARDING]->(i:LessonInfo {offset: $lesson_offset})-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
                DETACH DELETE at;
            END_OF_QUERY
        end
    end
end
