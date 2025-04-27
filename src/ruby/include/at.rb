class Main < Sinatra::Base

    def at_datum_now
        # return '2025-04-28' if DEVELOPMENT
        Date.today.strftime('%Y-%m-%d')
    end
    
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
        week_freq_count = {}
        [4, 3, 2, 1].each do |freq|
            n = (@@schueler_for_lesson[data[:lesson_key]].size.to_f / freq / occasions).ceil
            n = 1 if n < 1
            week_freq_count[n] = freq
        end
        latest_datum_for_email = {}
        datum = at_datum_now()
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :datum => datum}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:AT {key: 'at'})-[:REGARDING]->(l:Lesson {key: $lesson_key})
            WHERE at.datum < $datum
            RETURN us.email AS email, MAX(at.datum) AS datum;
        END_OF_QUERY
            latest_datum_for_email[row['email']] = row['datum']
        end
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :datum => datum}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:ATPlaceholder)-[:REGARDING]->(l:Lesson {key: $lesson_key})
            WHERE at.datum < $datum
            RETURN us.email AS email, MAX(at.datum) AS datum;
        END_OF_QUERY
            latest_datum_for_email[row['email']] ||= row['datum']
            latest_datum_for_email[row['email']] = row['datum'] if row['datum'] > latest_datum_for_email[row['email']]
        end
        todays_notes = {}
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :datum => datum}).each do |row|
            MATCH (us:User)<-[:FOR]-(at:AT {datum: $datum})-[:REGARDING]->(l:Lesson {key: $lesson_key})
            RETURN us.email AS email, at.key AS key, at.value AS value;
        END_OF_QUERY
            todays_notes[row['email']] ||= {}
            todays_notes[row['email']][row['key']] = row['value'].nil? ? true : row['value']
        end
        s = at_datum_now().split('-').map { |x| x.to_i }
        srand(((s[0] * 1000) + s[1] * 31) + s[2])
        sus_index = {}
        @@schueler_for_lesson[data[:lesson_key]].each.with_index do |email, index|
            sus_index[email] = index
            ts = latest_datum_for_email[email] || '2000-01-01'
            ts2 = Date.parse(ts).strftime('%G-%V')
            STDERR.puts "#{ts} #{ts2} #{email}"
        end
        sus_emails = @@schueler_for_lesson[data[:lesson_key]].sort do |a, b|
            ts_a = latest_datum_for_email[a] || '2000-01-01'
            ts_b = latest_datum_for_email[b] || '2000-01-01'
            ts_a = Date.parse(ts_a).strftime('%G-%V')
            ts_b = Date.parse(ts_b).strftime('%G-%V')
            if (ts_a == ts_b)
                Digest::SHA1.hexdigest("#{a}#{datum}") <=> Digest::SHA1.hexdigest("#{b}#{datum}")
            else
                ts_a <=> ts_b
            end
        end

        sus_list = sus_emails.map do |email|
            {:email => email, :first_name => @@user_info[email][:first_name], :last_name => @@user_info[email][:last_name]}
        end

        respond(:sus_list => sus_list, :todays_notes => todays_notes, :week_freq_count => week_freq_count, :sus_index => sus_index)
    end

    post '/api/set_at_note_for_sus' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :email, :key, :value],
                                  :types => {:value => Integer})
        datum = at_datum_now()
        assert(data[:value] >= 0 && data[:value] <= 5)
        if (data[:value] != 0)
            neo4j_query_expect_one(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :sus_email => data[:email], :lesson_key => data[:lesson_key], :key => data[:key], :value => data[:value], :datum => datum})
                MATCH (ut:User {email: $teacher_email})
                MATCH (us:User {email: $sus_email})
                MERGE (l:Lesson {key: $lesson_key})
                MERGE (us)<-[:FOR]-(at:AT {key: $key, datum: $datum})-[:REGARDING]->(l)
                SET at.value = $value
                MERGE (at)-[:SET_BY]->(ut)
                RETURN at;
            END_OF_QUERY
        else
            neo4j_query(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :sus_email => data[:email], :lesson_key => data[:lesson_key], :key => data[:key], :datum => datum})
                MATCH (us:User {email: $sus_email})<-[:FOR]-(at:AT {key: $key, datum: $datum})-[:REGARDING]->(l:Lesson {key: $lesson_key})
                DETACH DELETE at;
            END_OF_QUERY
        end
    end

    # api_call('/api/toggle_at_missing_for_sus', {email: email, lesson_key: event.lesson_key, key: key}, function(data) {

    post '/api/toggle_at_missing_for_sus' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :email, :key])
        assert(['hausaufgaben', 'material', 'unterschrift'].include?(data[:key]))
        datum = at_datum_now()
        currently_missing = false
        neo4j_query(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :email => data[:email], :key => data[:key], :datum => datum}).each do |row|
            MATCH (us:User {email: $email})<-[:FOR]-(at:AT {key: $key, datum: $datum})-[:REGARDING]->(l:Lesson {key: $lesson_key})
            RETURN COUNT(at) AS count;
        END_OF_QUERY
            currently_missing = true if row['count'] > 0
        end
        if currently_missing
            neo4j_query_expect_one(<<~END_OF_QUERY, {:lesson_key => data[:lesson_key], :email => data[:email], :key => data[:key], :datum => datum})
                MATCH (us:User {email: $email})<-[:FOR]-(at:AT {key: $key, datum: $datum})-[:REGARDING]->(l:Lesson {key: $lesson_key})
                DETACH DELETE at
                RETURN us;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, {:teacher_email => @session_user[:email], :lesson_key => data[:lesson_key], :sus_email => data[:email], :key => data[:key], :datum => datum})
                MATCH (ut:User {email: $teacher_email})
                MATCH (us:User {email: $sus_email})
                MERGE (l:Lesson {key: $lesson_key})
                MERGE (us)<-[:FOR]-(at:AT {key: $key, datum: $datum})-[:REGARDING]->(l)
                MERGE (at)-[:SET_BY]->(ut)
                RETURN at;
            END_OF_QUERY
        end
        respond(:missing => !currently_missing)
    end
end
