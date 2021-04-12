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
                neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                    MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                    SET b.confirmed = true
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                    MATCH (t:Tablet)<-[:WHICH]-(b:Booking {to_be_deleted: true})-[:FOR]->(i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                    DETACH DELETE b;
                END_OF_QUERY
                if data.include?(:breakout_rooms)
                    if data[:breakout_rooms].empty?
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                            MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                            REMOVE i.breakout_rooms
                            REMOVE i.breakout_room_participants
                            REMOVE i.breakout_rooms_roaming
                        END_OF_QUERY
                    else
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :breakout_rooms => data[:breakout_rooms]['rooms'] || [], :breakout_room_participants => data[:breakout_rooms]['participants'], :breakout_rooms_roaming => data[:breakout_rooms]['roaming'])
                            MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                            SET i.breakout_rooms = {breakout_rooms}
                            SET i.breakout_room_participants = {breakout_room_participants}
                            SET i.breakout_rooms_roaming = {breakout_rooms_roaming}
                        END_OF_QUERY
                    end
                end
            end
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end
    
    post '/api/force_jitsi_for_lesson' do
        assert(teacher_tablet_logged_in? || klassenraum_logged_in?)
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset],
                                  :max_body_length => 1024,
                                  :types => {:lesson_offset => Integer})
        STDERR.puts "force_jitsi_for_lesson: #{data.to_json}"
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
        # purge unconfirmed tablet bookings for this lesson_key
        neo4j_query(<<~END_OF_QUERY, :key => lesson_key)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            DETACH DELETE b;
        END_OF_QUERY
        # purge unconfirmed tablet bookings for any lesson key older than 30 minutes
        neo4j_query(<<~END_OF_QUERY, :timestamp => (Time.now - 30 * 60).to_i)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            WHERE b.updated < {timestamp}
            DETACH DELETE b;
        END_OF_QUERY
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
        
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            RETURN t.id, i.offset;
        END_OF_QUERY
        rows.each do |entry|
            offset = entry['i.offset']
            tablet_id = entry['t.id']
            results[offset] ||= {}
            results[offset][:info] ||= {}
            results[offset][:info][:booked_tablet] = {
                :tablet_id => tablet_id,
                :lagerort => @@tablets[tablet_id][:lagerort],
                :bg_color => @@tablets[tablet_id][:bg_color],
                :fg_color => @@tablets[tablet_id][:fg_color]
            }
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
    
    post '/api/book_streaming_tablet_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :datum, 
                                                     :start_time, :end_time],
                                  :types => {:offset => Integer})

        available_tablets = Set.new()
        @@tablets_for_school_streaming.each do |tablet_id|
            available_tablets << tablet_id
        end
        bookings = neo4j_query(<<~END_OF_QUERY, :datum => data[:datum]).map { |x| {:tablet_id => x['t.id'], :booking => x['b'].props, :lesson_key => x['l.id']} }
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {datum: {datum}})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, b, l.id;
        END_OF_QUERY
        
        request_start_time = DateTime.parse("#{data[:datum]}T#{data[:start_time]}:00")
        request_end_time = DateTime.parse("#{data[:datum]}T#{data[:end_time]}:00")
        
        favoured_tablets = Set.new()
        tablets_booked_today = Set.new()
        request_shorthands = @@lessons[:lesson_keys][data[:lesson_key]][:lehrer]

        bookings.each do |item|
            tablet_id = item[:tablet_id]
            tablets_booked_today << tablet_id
            booking = item[:booking]
            start_time = DateTime.parse("#{booking[:datum]}T#{booking[:start_time]}:00")
            end_time = DateTime.parse("#{booking[:datum]}T#{booking[:end_time]}:00")
            start_time -= STREAMING_TABLET_BOOKING_TIME_PRE / 24.0 / 60.0
            end_time += STREAMING_TABLET_BOOKING_TIME_POST / 24.0 / 60.0
            entry_shorthands = @@lessons[:lesson_keys][data[:lesson_key]][:lehrer]
            unless (request_shorthands & entry_shorthands).empty?
                favoured_tablets << tablet_id
            else
                unless request_end_time < start_time && request_start_time > end_time
                    available_tablets.delete(tablet_id)
                end
            end
        end
        
        favoured_tablets &= available_tablets
        
        if available_tablets.empty?
            respond(:found_tablet => false)
        else
            which_tablet = available_tablets.to_a.sample
            unless favoured_tablets.empty?
                # if user already booked a tablet this day, prefer the same tablet
                which_tablet = favoured_tablets.to_a.sample
            else
                unless (available_tablets - tablets_booked_today).empty?
                    # prefer a table which has not been booked for this day
                    which_tablet = (available_tablets - tablets_booked_today).to_a.sample
                end
            end
            data[:tablet_id] = which_tablet
            timestamp = Time.now.to_i
            data[:timestamp] = timestamp
            transaction do
                neo4j_query(<<~END_OF_QUERY, data)
                    MERGE (l:Lesson {key: {lesson_key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    
                    WITH l, i
                    MATCH (i)<-[:FOR]->(b2:Booking)-[:WHICH]->(:Tablet)
                    DETACH DELETE b2
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, data)
                    MERGE (l:Lesson {key: {lesson_key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    
                    WITH l, i
                    MATCH (t:Tablet {id: {tablet_id}})
                    
                    WITH l, i, t
                    MERGE (i)<-[:FOR]-(b:Booking)-[:WHICH]->(t)
                    SET b.updated = {timestamp}
                    SET b.datum = {datum}
                    SET b.start_time = {start_time}
                    SET b.end_time = {end_time}
                    SET b.confirmed = false;
                END_OF_QUERY
            end
            respond(:found_tablet => true, :tablet => which_tablet, :tablet_info => @@tablets[which_tablet])
        end
    end
    
    post '/api/unbook_streaming_tablet_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})

        transaction do
            timestamp = Time.now.to_i
            data[:timestamp] = timestamp
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: {lesson_key}})<-[:BELONGS_TO]-(i:LessonInfo {offset: {offset}})<-[:FOR]-(b:Booking {confirmed: false})-[:WHICH]->(t:Tablet)
                DETACH DELETE b;
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: {lesson_key}})<-[:BELONGS_TO]-(i:LessonInfo {offset: {offset}})<-[:FOR]-(b:Booking {confirmed: true})-[:WHICH]->(t:Tablet)
                SET b.to_be_deleted = true
                SET b.updated = {timestamp};
            END_OF_QUERY
        end
    end
    
    post '/api/get_tablet_bookings' do
        require_admin!
        d0 = DateTime.now.strftime('%Y-%m-%d')
        d1 = (DateTime.now + 7).strftime('%Y-%m-%d')
        rows = neo4j_query(<<~END_OF_QUERY, {:d0 => d0, :d1 => d1})
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:FOR]-(b:Booking {confirmed: true})-[:WHICH]->(t:Tablet)
            WHERE b.datum >= {d0} AND b.datum <= {d1}
            RETURN l, i, b, t
            ORDER BY t.id
        END_OF_QUERY
        results = {}
        rows.each do |row|
            lesson = row['l'].props
            lesson_key = lesson[:key]
            lesson_info = row['i'].props
            booking = row['b'].props
            tablet = row['t'].props
            lesson_data = @@lessons[:lesson_keys][lesson_key]
            results[booking[:datum]] ||= {}
            results[booking[:datum]][tablet[:id]] ||= []
            results[booking[:datum]][tablet[:id]] << {
                :booking => booking,
                :lesson => "<b>#{lesson_data[:lehrer].join(', ')}</b> #{lesson_data[:pretty_folder_name]}",
                :tablet => @@tablets[tablet[:id]]
            }
        end
        respond(:bookings => results)
    end
    
    def get_stream_restriction_for_lesson_key(lesson_key)
        results = neo4j_query_expect_one(<<~END_OF_QUERY, :key => lesson_key)['restriction']
            MERGE (l:Lesson {key: {key}})
            RETURN COALESCE(l.stream_restriction, []) AS restriction
        END_OF_QUERY
        while results.size < 5
            results << 0
        end
        results
    end
    
    def print_stream_restriction_table(klasse)
        lesson_keys = (@@lessons_for_shorthand[@session_user[:shorthand]] || []).select do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            (lesson_info[:klassen] || []).include?(klasse)
        end
        return '' if lesson_keys.empty?
        StringIO.open do |io|
            io.puts "<hr />"
            io.puts "<div class='alert alert-warning'>"
            io.puts "Falls Sie einschränken möchten, welche Kinder in Ihrem Unterricht am Streaming teilnehmen dürfen, können Sie dies hier tun. Standardmäßig ist der Stream, falls Sie ihn aktivieren, für alle Kinder aktiviert, die planmäßig gerade nicht in der Schule sind (»für alle«). Sie können den Stream bei Bedarf tageweise so einschränken, dass nur die Kinder darauf zugreifen können, die unten als »zu Hause« markiert sind (»nur für Dauer-saLzH«)."
            io.puts "</div>"
            io.puts "<div class='table-responsive'>"
            io.puts "<table class='table stream-restriction-table'>"
            io.puts "<tr>"
            io.puts "<th>Fach</th>"
            io.puts "<th>Montag</th>"
            io.puts "<th>Dienstag</th>"
            io.puts "<th>Mittwoch</th>"
            io.puts "<th>Donnerstag</th>"
            io.puts "<th>Freitag</th>"
            io.puts "</tr>"
            lesson_keys.each do |lesson_key|
                io.puts "<tr>"
                restrictions = get_stream_restriction_for_lesson_key(lesson_key)
                io.puts "<td style='text-align: left;'>"
                lesson_info = @@lessons[:lesson_keys][lesson_key]
                io.puts "#{lesson_info[:pretty_folder_name]}"
                io.puts "</td>"
                restrictions.each.with_index do |r, i|
                    io.puts "<td>"
                    io.puts "<button data-lesson-key='#{lesson_key}' data-day='#{i}' class='bu-toggle-stream-restriction btn #{r == 0 ? 'btn-primary' : 'btn-info'}'>#{r == 0 ? 'für alle' : 'nur für Dauer-saLzH'}</button>"
                    io.puts "</td>"
                end
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end
    
    post '/api/toggle_stream_restriction' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :day],
                                  :types => {:day => Integer})
        day = data[:day]
        restrictions = get_stream_restriction_for_lesson_key(data[:lesson_key]);
        restrictions[day] = (restrictions[day] + 1) % 2
        neo4j_query(<<~END_OF_QUERY, {:restrictions => restrictions, :lesson_key => data[:lesson_key]})
            MERGE (l:Lesson {key: {lesson_key}})
            SET l.stream_restriction = {restrictions}
        END_OF_QUERY
        trigger_update(data[:lesson_key])
        respond(:state => restrictions[day])
    end
end
