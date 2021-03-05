class Main < Sinatra::Base
    post '/api/save_lesson_data' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offsets, :data],
                                  :optional_keys => [:breakout_rooms],
                                  :max_body_length => 65536,
                                  :types => {:lesson_offsets => Array, :data => Hash, :breakout_rooms => Hash})
        transaction do 
            timestamp = Time.now.to_i
            data[:lesson_offsets].each do |lesson_offset|
                results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :data => data[:data], :timestamp => timestamp)
                    MERGE (l:Lesson {key: {key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    SET i += {data}
                    SET i.updated = {timestamp};
                END_OF_QUERY
                if data.include?(:breakout_rooms)
                    if data[:breakout_rooms].empty?
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                            MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                            REMOVE i.breakout_rooms
                            REMOVE i.breakout_room_participants;
                        END_OF_QUERY
                    else
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :breakout_rooms => data[:breakout_rooms]['rooms'] || [], :breakout_room_participants => data[:breakout_rooms]['participants'])
                            MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                            SET i.breakout_rooms = {breakout_rooms}
                            SET i.breakout_room_participants = {breakout_room_participants}
                        END_OF_QUERY
                    end
                end
            end
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end
    
    post '/api/force_jitsi_for_lesson' do
        require_teacher_tablet!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset],
                                  :max_body_length => 1024,
                                  :types => {:lesson_offset => Integer})
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :data => {:lesson_jitsi => true}, :timestamp => timestamp)
                MERGE (l:Lesson {key: {key}})
                MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                SET i += {data}
                SET i.updated = {timestamp};
            END_OF_QUERY
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end
    
    def get_lesson_data(lesson_key)
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| x['i'].props }
            MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            RETURN i
            ORDER BY i.offset;
        END_OF_QUERY
        results = {}
        rows.each do |row|
            results[row[:offset]] ||= {}
            results[row[:offset]][:info] = row.reject do |k, v|
                [:offset, :updated].include?(k)
            end
        end
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'].props, :user => x['u'].props, :text_comment_from => x['tcf.email'] } }
            MATCH (u:User)<-[:TO]-(c:TextComment)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            MATCH (c)-[:FROM]->(tcf:User)
            RETURN c, u, tcf.email
            ORDER BY c.offset;
        END_OF_QUERY
        rows.each do |row|
            results[row[:comment][:offset]] ||= {}
            results[row[:comment][:offset]][:comments] ||= {}
            results[row[:comment][:offset]][:comments][row[:user][:email]] ||= {}
            if row[:comment][:comment]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:text_comment] = row[:comment][:comment]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:text_comment_from] = row[:text_comment_from] 
            end
        end
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'].props, :user => x['u'].props, :audio_comment_from => x['acf.email'] } }
            MATCH (u:User)<-[:TO]-(c:AudioComment)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            MATCH (c)-[:FROM]->(acf:User)
            RETURN c, u, acf.email
            ORDER BY c.offset;
        END_OF_QUERY
        rows.each do |row|
            results[row[:comment][:offset]] ||= {}
            results[row[:comment][:offset]][:comments] ||= {}
            results[row[:comment][:offset]][:comments][row[:user][:email]] ||= {}
            if row[:comment][:tag]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:audio_comment_tag] = row[:comment][:tag]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:duration] = row[:comment][:duration]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:audio_comment_from] = row[:audio_comment_from] 
            end
        end
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:offset => x['li.offset'], :feedback => x['hf'].props, :user => x['u.email'] }}
            MATCH (u:User)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            RETURN hf, li.offset, u.email;
        END_OF_QUERY
        rows.each do |row|
            results[row[:offset]] ||= {}
            results[row[:offset]][:feedback] ||= {}
            results[row[:offset]][:feedback][:sus] ||= {}
            results[row[:offset]][:feedback][:sus][row[:user]] = row[:feedback].reject do |k, v|
                [:done].include?(k)
            end
            results[row[:offset]][:feedback][:sus][row[:user]][:name] = (@@user_info[row[:user]] || {})[:display_name]
        end
        results.each_pair do |offset, info|
            next unless info[:feedback]
            results[offset][:feedback][:summary] = 'Es liegt bisher kein Feedback zu dieser Stunde vor.'
            feedback_str = StringIO.open do |io|
                state_histogram = {}
                time_spent_values = []
                info[:feedback][:sus].each_pair do |email, feedback|
                    if feedback[:state]
                        state_histogram[feedback[:state]] ||= 0
                        state_histogram[feedback[:state]] += 1
                    end
                    if feedback[:time_spent]
                        time_spent_values << feedback[:time_spent]
                    end
                end
                unless state_histogram.empty?
                    io.puts "<p>"
                    parts = []
                    HOMEWORK_FEEDBACK_STATES.each do |x|
                        parts << "#{HOMEWORK_FEEDBACK_EMOJIS[x]} × #{state_histogram[x]}" if state_histogram[x]
                    end
                    io.puts parts.join(', ')
                    io.puts "</p>"
                end
                time_spent_values.sort!
                unless time_spent_values.empty?
                    io.puts "<p>"
                    io.puts "SuS haben zwischen #{time_spent_values.first} und #{time_spent_values.last} Minuten für diese Hausaufgabe benötigt (#{time_spent_values.size} Angabe#{time_spent_values.size == 1 ? '' : 'n'})."
                    io.puts "</p>"
                end
                io.string
            end
            results[offset][:feedback][:summary] = feedback_str
        end

        results
    end
    
    post '/api/get_lesson_data' do
        data = parse_request_data(:required_keys => [:lesson_key])
        results = get_lesson_data(data[:lesson_key])
        respond(:results => results)
    end
    
    post '/api/insert_lesson' do 
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :shift],
                                  :types => {:offset => Integer, :shift => Integer})
        timestamp = Time.now.to_i
        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:offset], :shift => data[:shift], :timestamp => timestamp)
            MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: {key}}) 
            WHERE n.offset >= {offset}
            SET n.offset = n.offset + {shift}
            SET n.updated = {timestamp};
        END_OF_QUERY
        trigger_update(data[:lesson_key])
        respond(:ok => 'yeah')
    end
    
    post '/api/delete_lessons' do 
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offsets],
                                  :types => {:offsets => Array},
                                  :max_body_length => 65536)
        data[:offsets].each do |offset|
            raise 'no a number' unless offset.is_a?(Integer)
        end
        STDERR.puts data.to_yaml
        data[:offsets].sort!
        cumulative_offset = 0
        timestamp = Time.now.to_i
        data[:offsets].each do |offset|
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => offset - cumulative_offset, :timestamp => timestamp)
                MATCH (n:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(:Lesson {key: {key}}) 
                DETACH DELETE n;
            END_OF_QUERY
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => offset - cumulative_offset, :timestamp => timestamp)
                MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: {key}}) 
                WHERE n.offset > {offset}
                SET n.offset = n.offset - 1
                SET n.updated = {timestamp};
            END_OF_QUERY
            cumulative_offset += 1
        end
        trigger_update(data[:lesson_key])
        respond(:ok => 'yeah')
    end
end
