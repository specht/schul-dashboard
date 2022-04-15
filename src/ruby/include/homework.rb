class Main < Sinatra::Base
    post '/api/get_homework_feedback' do
        require_user!
        data = parse_request_data(:required_keys => [:entries],
                                  :types => {:entries => Array})
        results = {}
        data[:entries].each do |entry|
            parts = entry.split('/')
            lesson_key = parts[0]
            offset = parts[1].to_i
            hf = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => lesson_key, :offset => offset).map { |x| x['hf'].props }
                MATCH (u:User {email: $session_email})<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
                RETURN hf;
            END_OF_QUERY
            results[entry] = {}
            hf.each do |x|
                results[entry] = x
            end
        end
        respond(:homework_feedback => results)
    end
    
    def self.get_homework_feedback_for_lesson_key(lesson_key)
        hf = $neo4j.neo4j_query(<<~END_OF_QUERY, :lesson_key => lesson_key).map { |x| {:offset => x['li.offset'], :hf => x['hf'].props} }
            MATCH (u:User)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            RETURN hf, li.offset
            ORDER BY li.offset;
        END_OF_QUERY
        results = {}
        hf.each do |_entry|
            entry = _entry[:hf]
            offset = _entry[:offset]
            results[offset] ||= {
                :state_histogram => {},
                :time_spent_min => nil,
                :time_spent_max => nil
            }
            if entry[:state]
                results[offset][:state_histogram][entry[:state]] ||= 0
                results[offset][:state_histogram][entry[:state]] += 1
            end
            if entry[:time_spent]
                results[offset][:time_spent_min] ||= entry[:time_spent]
                results[offset][:time_spent_min] = entry[:time_spent] if entry[:time_spent] < results[offset][:time_spent_min]
                results[offset][:time_spent_max] ||= entry[:time_spent]
                results[offset][:time_spent_max] = entry[:time_spent] if entry[:time_spent] > results[offset][:time_spent_max]
            end
        end
        final_result = {}
        results.each_pair do |offset, data|
            result = {}
            if results[offset][:time_spent_min]
                if results[offset][:time_spent_min] != results[offset][:time_spent_max]
                    result[:time_spent] = "#{results[offset][:time_spent_min]} – #{results[offset][:time_spent_max]} Minuten"
                else
                    result[:time_spent] = "#{results[offset][:time_spent_min]} Minuten"
                end
            end
            unless results[offset][:state_histogram].empty?
                parts = []
                short_parts = []
                HOMEWORK_FEEDBACK_STATES.each do |state|
                    if results[offset][:state_histogram][state]
                        parts << "#{HOMEWORK_FEEDBACK_EMOJIS[state]} × #{results[offset][:state_histogram][state]}"
                        short_parts << "#{HOMEWORK_FEEDBACK_EMOJIS[state]}"
                    end
                end
                result[:state] = parts.join(', ')
                result[:short_state] = short_parts.join('')
            end
            final_result[offset] = result
        end
        final_result
    end
    
    post '/api/mark_homework_done' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})
         neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => data[:lesson_key], :offset => data[:offset])
            MATCH (u:User {email: $session_email}), (li:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WITH u, li
            MERGE (u)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li)
            SET hf.done = true
            RETURN hf;
        END_OF_QUERY
        respond(:yeah => 'sure')
    end
    
    post '/api/mark_homework_undone' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})
         neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => data[:lesson_key], :offset => data[:offset])
            MATCH (u:User {email: $session_email}), (li:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WITH u, li
            MERGE (u)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li)
            SET hf.done = false
            RETURN hf;
        END_OF_QUERY
        respond(:yeah => 'sure')
    end
    
    post '/api/update_homework_feedback' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :state, :time_spent],
                                  :types => {:offset => Integer, :time_spent => Integer})
        assert(['good', 'hmmm', 'lost', ''].include?(data[:state]))
        assert(data[:time_spent] >= 0)
        data[:state] = nil if data[:state].empty?
        data[:time_spent] = nil if data[:time_spent] == 0
        neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => data[:lesson_key], :offset => data[:offset], :state => data[:state], :time_spent => data[:time_spent])
            MATCH (u:User {email: $session_email}), (li:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
            WITH u, li
            MERGE (u)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li)
            SET hf.state = $state
            SET hf.time_spent = $time_spent
            RETURN hf;
        END_OF_QUERY
        respond(:yeah => 'sure')
    end
end
