class Main < Sinatra::Base

    # check whether we can book a list of tablet sets for a specific lesson
    def already_booked_tablets_for_timespan(datum, start_time, end_time)
        require_teacher!
        data = {
            :datum => datum,
            :start_time => start_time,
            :end_time => end_time
        }
        neo4j_query(<<~END_OF_QUERY, data).map { |x| {:tablet_set_id => x['t.id'], :lesson_key => x['l.key'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking {datum: {datum}})
            WHERE NOT ((b.end_time <= {start_time}) OR (b.start_time >= {end_time}))
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, l.key;
        END_OF_QUERY
    end

    # book a list of tablet sets for a specific lesson, or unbook all tablet sets
    def book_tablet_set_for_lesson(lesson_key, offset, datum, start_time, end_time, tablet_sets = [])
        require_teacher!
        conflicting_tablets = []
        unless tablet_sets.empty?
            # check if it's bookable
            conflicting_tablets = already_booked_tablets_for_timespan(datum, start_time, end_time).reject do |x|
                x[:lesson_key] == lesson_key
            end
        end
        if conflicting_tablets.empty?
            transaction do
                # make sure tablet sets exist in database
                tablet_sets.each do |tablet_set_id|
                    neo4j_query("MERGE (:TabletSet {id: '#{tablet_set_id}'})")
                end
                timestamp = Time.now.to_i
                data = {
                    :lesson_key => lesson_key,
                    :offset => offset,
                    :tablet_set_ids => tablet_sets,
                    :timestamp => timestamp,
                    :datum => datum,
                    :start_time => start_time,
                    :end_time => end_time
                }
                neo4j_query(<<~END_OF_QUERY, data)
                    MERGE (l:Lesson {key: {lesson_key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    MERGE (b:Booking)-[:FOR]->(i)
                    SET b.updated = {timestamp}
                    SET b.datum = {datum}
                    SET b.start_time = {start_time}
                    SET b.end_time = {end_time}

                    WITH b
                    MATCH (b)-[r:BOOKED]->(:TabletSet)
                    DELETE r

                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, data)
                    MERGE (l:Lesson {key: {lesson_key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    MERGE (b:Booking)-[:FOR]->(i)
                    SET b.updated = {timestamp}
                    SET b.datum = {datum}
                    SET b.start_time = {start_time}
                    SET b.end_time = {end_time}

                    WITH l, i, b
                    MATCH (t:TabletSet) WHERE t.id IN {tablet_set_ids}

                    WITH l, i, b, t
                    MERGE (b)-[:BOOKED]->(t)
                END_OF_QUERY
            end
        else
            debug "Cannot book tablet sets because of these:"
            debug conflicting_tablets.to_yaml
            raise :unable_to_book_tablet_sets
        end
    end

    post '/api/find_available_tablet_sets_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :datum, 
                                                     :start_time, :end_time],
                                  :types => {:offset => Integer})

        available_tablet_sets = []
        @@tablet_sets.keys.each do |tablet_id|
            available_tablet_sets << tablet_id
        end

        # consider klasse
        klassen = @@lessons[:lesson_keys][data[:lesson_key]][:klassen]
        klasse5or6 = klassen.any? { |x| [5, 6].include?(x.to_i) }

        # sort by :prio_unterstufe
        available_tablet_sets.sort! do |a, b|
            a_prio = (!!@@tablet_sets[a][:prio_unterstufe]) ? 1 : 0
            b_prio = (!!@@tablet_sets[b][:prio_unterstufe]) ? 1 : 0
            dir = a_prio <=> b_prio
            if dir == 0
                a <=> b
            else
                dir * (klasse5or6 ? -1 : 1)
            end
        end

        # also consider room
        timetable_date = @@lessons[:start_date_for_date][data[:datum]]
        wday = (Date.parse(data[:datum]).wday + 6) % 7
        raum = @@lessons[:timetables][timetable_date][data[:lesson_key]][:stunden][wday].values.first[:raum]

        available_tablet_sets.select! do |x|
            if @@tablet_sets[x][:only_these_rooms]
                @@tablet_sets[x][:only_these_rooms].include?(raum)
            else
                true
            end
        end

        # also consider number of students + teacher
        sus_count = (@@schueler_for_lesson[data[:lesson_key]] || []).size

        result = neo4j_query(<<~END_OF_QUERY, :datum => data[:datum]).map { |x| {:tablet_set_id => x['t.id'], :booking => x['b'].props, :lesson_key => x['l.key']} }
            MATCH (t:TabletSet)<-[:WHICH]-(b:Booking {datum: {datum}})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, b, l.key
            ORDER BY b.start_time;
        END_OF_QUERY
        # remove bookings of tablet sets which aren't available for this room
        result.select! do |x|
            available_tablet_sets.include?(x)
        end
        bookings = {}
        result.each do |x|
            bookings[x[:tablet_set_id]] ||= []
            bookings[x[:tablet_set_id]] << {
                :booking => x[:booking]
            }
        end

        tablet_sets = {}
        available_tablet_sets.each do |x|
            tablet_sets[x] = {
                :count => @@tablet_sets[x][:count],
                :standort => @@tablet_sets[x][:standort],
                :label => @@tablet_sets[x][:label]
            }
        end

        respond(:bookings => bookings, :available_tablet_sets => tablet_sets, 
            :available_tablet_sets_order => available_tablet_sets, :sus_count => sus_count)
    end

    post '/api/book_tablet_set_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :datum, 
                                                     :start_time, :end_time, :tablet_set_id],
                                  :types => {:offset => Integer})
        timestamp = Time.now.to_i
        data[:timestamp] = timestamp
        neo4j_query(<<~END_OF_QUERY, data)
            MERGE (l:Lesson {key: {lesson_key}})
            MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
            
            WITH l, i
            MATCH (t:TabletSet {id: {tablet_set_id}})
            
            WITH l, i, t
            MERGE (i)<-[:FOR]-(b:Booking)-[:WHICH]->(t)
            SET b.updated = {timestamp}
            SET b.datum = {datum}
            SET b.start_time = {start_time}
            SET b.end_time = {end_time}
            SET b.confirmed = false;
        END_OF_QUERY
        respond(:tablet_set_id => data[:tablet_set_id], :tablet_set_info => @@tablet_sets[data[:tablet_set_id]])
    end
    
    post '/api/unbook_tablet_set_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :tablet_set_id],
                                  :types => {:offset => Integer})

        transaction do
            timestamp = Time.now.to_i
            data[:timestamp] = timestamp
            # delete unconfirmed bookings for this lesson_key / offset
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: {lesson_key}})<-[:BELONGS_TO]-(i:LessonInfo {offset: {offset}})<-[:FOR]-(b:Booking {confirmed: false})-[:WHICH]->(t:TabletSet {id: {tablet_set_id}})
                DETACH DELETE b;
            END_OF_QUERY
            # mark confirmed bookings for this lesson_key / offset as 'to be deleted'
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: {lesson_key}})<-[:BELONGS_TO]-(i:LessonInfo {offset: {offset}})<-[:FOR]-(b:Booking {confirmed: true})-[:WHICH]->(t:TabletSet {id: {tablet_set_id}})
                SET b.to_be_deleted = true
                SET b.updated = {timestamp};
            END_OF_QUERY
        end
        respond(:ok => 'yay')
    end 
end