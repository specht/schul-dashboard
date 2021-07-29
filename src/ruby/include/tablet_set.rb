# TODO: move these to credentials
TABLET_SET_WARNING_BEFORE_MINUTES = 15
TABLET_SET_WARNING_AFTER_MINUTES = 15

class Main < Sinatra::Base

    # check whether we can book a list of tablet sets for a specific time span
    def already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
        require_teacher!
        data = {
            :datum => datum,
            :start_time => start_time,
            :end_time => end_time
        }
        rows = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:tablet_set_id => x['t.id'], :lesson_key => x['l.key'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking {datum: {datum}})
            WHERE NOT ((b.end_time <= {start_time}) OR (b.start_time >= {end_time}))
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, l.key;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row[:tablet_set_id]] ||= Set.new()
            result[row[:tablet_set_id]] << row[:lesson_key]
        end
        result
    end

    # return all booked tablet sets for a specific day
    def already_booked_tablet_sets_for_day(datum)
        require_teacher!
        rows = neo4j_query(<<~END_OF_QUERY, { :datum => datum }).map { |x| {:tablet_set_id => x['t.id'], :lesson_key => x['l.key'], :start_time => x['b.start_time'], :end_time => x['b.end_time'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking {datum: {datum}})
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, l.key, b.start_time, b.end_time;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row[:tablet_set_id]] ||= []
            result[row[:tablet_set_id]] << {
                :lesson_key => row[:lesson_key],
                :start_time => row[:start_time],
                :end_time => row[:end_time]
            }
        end
        result
    end

    # book a list of tablet sets for a specific lesson, or unbook all tablet sets
    def book_tablet_set_for_lesson(lesson_key, offset, datum, start_time, end_time, tablet_sets = [])
        require_teacher!
        conflicting_tablets = []
        unless tablet_sets.empty?
            # check if it's bookable
            temp = already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
            conflicting_tablets = temp.keys.reject do |x|
                temp[x][:lesson_key] == lesson_key
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
                    SET i.updated = {timestamp}
                    SET b.updated = {timestamp}
                    SET b.datum = {datum}
                    SET b.start_time = {start_time}
                    SET b.end_time = {end_time}

                    WITH b
                    MATCH (b)-[r:BOOKED]->(:TabletSet)
                    DELETE r
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, data)
                    MATCH (l:Lesson {key: {lesson_key}})
                    MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    MATCH (b:Booking)-[:FOR]->(i)
                    MATCH (t:TabletSet)
                    WHERE t.id IN {tablet_set_ids}
                    MERGE (b)-[:BOOKED]->(t)
                END_OF_QUERY
            end
        else
            debug "Cannot book tablet sets because of these:"
            debug conflicting_tablets.to_yaml
            raise :unable_to_book_tablet_sets
        end
    end

    def hh_mm_to_i(s)
        parts = s.split(':').map { |x| x.to_i }
        parts[0] * 60 + parts[1]
    end

    def teacher_names_and_fach_for_lesson_key(lesson_key)
        pretty_fach = (@@lessons[:lesson_keys][lesson_key] || {})[:pretty_folder_name] || 'NN'
        shorthands = (@@lessons[:lesson_keys][lesson_key] || {})[:lehrer] || ['NN']
        teacher_names = shorthands.map do |shorthand|
            email = @@shorthands[shorthand]
            (@@user_info[email] || {})[:display_last_name_dativ] || 'NN'
        end
        return pretty_fach, teacher_names
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

        booked_tablet_sets_timespan = already_booked_tablet_sets_for_timespan(data[:datum], data[:start_time], data[:end_time])
        booked_tablet_sets_day = already_booked_tablet_sets_for_day(data[:datum])

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

        tablet_sets = {}
        available_tablet_sets.each do |x|
            blocked_by = booked_tablet_sets_timespan[x]
            if blocked_by
                blocked_by.delete(data[:lesson_key])
            end
            tablet_sets[x] = {
                :count => @@tablet_sets[x][:count],
                :standort => @@tablet_sets[x][:standort],
                :label => @@tablet_sets[x][:label],
                :blocked_by => blocked_by.to_a
            }
            hints = []
            if booked_tablet_sets_timespan[x]
                booked_tablet_sets_timespan[x].to_a.each do |lesson_key|
                    if lesson_key != data[:lesson_key]
                        pretty_fach, teacher_names = teacher_names_and_fach_for_lesson_key(lesson_key)
                        hints << "<span class='text-danger'><i class='fa fa-warning'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wurde bereits von #{teacher_names.join(', ')} gebucht: #{pretty_fach}"
                    end
                end
            elsif booked_tablet_sets_day[x]
                bookings_before = []
                bookings_after = []
                booked_tablet_sets_day[x].each do |entry|
                    if entry[:end_time] <= data[:start_time]
                        bookings_before << entry
                    else
                        bookings_after << entry
                    end
                end
                debug bookings_before.to_yaml
                debug bookings_after.to_yaml
                unless bookings_before.empty?
                    booking = bookings_before.last
                    t = hh_mm_to_i(data[:start_time]) - hh_mm_to_i(booking[:end_time])
                    if t <= TABLET_SET_WARNING_BEFORE_MINUTES
                        lesson_key = booking[:lesson_key]
                        pretty_fach, teacher_names = teacher_names_and_fach_for_lesson_key(lesson_key)
                        hints << "<span class='text-danger'><i class='fa fa-clock-o'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wird bis #{t} Minuten vor Stundenbeginn noch von #{teacher_names.join(', ')} benötigt: #{pretty_fach}"
                    end
                end
                unless bookings_after.empty?
                    booking = bookings_after.first
                    t = hh_mm_to_i(booking[:start_time]) - hh_mm_to_i(data[:end_time])
                    if t <= TABLET_SET_WARNING_AFTER_MINUTES
                        lesson_key = booking[:lesson_key]
                        pretty_fach, teacher_names = teacher_names_and_fach_for_lesson_key(lesson_key)
                        hints << "<span class='text-danger'><i class='fa fa-clock-o'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wird bereits #{t} Minuten nach Stundenende von #{teacher_names.join(', ')} benötigt: #{pretty_fach}"
                    end
                end
            end
            unless hints.empty?
                tablet_sets[x][:hint] = hints.join('<br />')
            end
        end

        respond(:available_tablet_sets => tablet_sets,
            :available_tablet_sets_order => available_tablet_sets)
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