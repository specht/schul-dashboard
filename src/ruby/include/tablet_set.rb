# TODO: move these to credentials
TABLET_SET_WARNING_BEFORE_MINUTES = 15
TABLET_SET_WARNING_AFTER_MINUTES = 15

class Main < Sinatra::Base

    post '/api/get_tablet_set_bookings' do
        require_admin!
        d0 = (DateTime.now - 28).strftime('%Y-%m-%d')
        rows = neo4j_query(<<~END_OF_QUERY, {:d0 => d0})
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking)-[:BOOKED_BY]->(u:User)
            WHERE b.datum >= {d0}
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t, l, b, i, u.email;
        END_OF_QUERY
        results = {}
        rows.each do |row|
            booking = row['b'].props
            tablet_set = row['t'].props
            email = row['u.email']
            results[booking[:datum]] ||= {}
            results[booking[:datum]][tablet_set[:id]] ||= []
            entry = {
                :booking => booking,
                :last_name => (@@user_info[email] || {})[:display_last_name] || 'NN',
                :shorthand => (@@user_info[email] || {})[:shorthand] || 'NN',
                :tablet_set => tablet_set[:id]
            }
            if row['l']
                lesson = row['l'].props
                lesson_key = lesson[:key]
                lesson_info = row['i'].props
                lesson_data = @@lessons[:lesson_keys][lesson_key] || {}
                entry[:lesson] = lesson_data[:pretty_folder_name]
            end
            results[booking[:datum]][tablet_set[:id]] << entry
        end
        respond(:bookings => results)
    end
        
    # check whether we can book a list of tablet sets for a specific time span
    def already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
        require_teacher!
        data = {
            :datum => datum,
            :start_time => start_time,
            :end_time => end_time
        }
        rows = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:tablet_set_id => x['t.id'], :lesson_key => x['l.key'], :email => x['u.email'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking {datum: {datum}})-[:BOOKED_BY]->(u:User)
            WHERE NOT ((b.end_time <= {start_time}) OR (b.start_time >= {end_time}))
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, l.key, u.email;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row[:tablet_set_id]] ||= []
            result[row[:tablet_set_id]] << {
                :lesson_key => row[:lesson_key],
                :email => row[:email],
                :display_name => (@@user_info[row[:email]] || {})[:display_last_name_dativ] || 'NN'
            }
        end
        result
    end

    # return all booked tablet sets for a specific day
    def already_booked_tablet_sets_for_day(datum)
        require_teacher!
        rows = neo4j_query(<<~END_OF_QUERY, { :datum => datum }).map { |x| {:tablet_set_id => x['t.id'], :lesson_key => x['l.key'], :start_time => x['b.start_time'], :end_time => x['b.end_time'], :email => x['u.email'] } }
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking {datum: {datum}})-[:BOOKED_BY]->(u:User)
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, l.key, b.start_time, b.end_time, u.email;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row[:tablet_set_id]] ||= []
            result[row[:tablet_set_id]] << {
                :lesson_key => row[:lesson_key],
                :email => row[:email],
                :display_name => (@@user_info[row[:email]] || {})[:display_last_name_dativ] || 'NN',
                :start_time => row[:start_time],
                :end_time => row[:end_time]
            }
        end
        result
    end

    # book a list of tablet sets for a specific lesson, or unbook all tablet sets
    def book_tablet_set_for_lesson(datum, start_time, end_time, tablet_sets = [], lesson_key, offset)
        require_teacher!
        conflicting_tablets = []
        unless tablet_sets.empty?
            # check if it's bookable
            temp = already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
            conflicting_tablets = temp.keys.reject do |x|
                temp[x].reject do |y|
                    y[:lesson_key] == lesson_key
                end.empty?
            end
            conflicting_tablets.select! { |x| tablet_sets.include?(x) }
        end
        if conflicting_tablets.empty?
            transaction do
                # make sure tablet sets exist in database
                tablet_sets.each do |tablet_set_id|
                    neo4j_query("MERGE (:TabletSet {id: '#{tablet_set_id}'})")
                end
                timestamp = Time.now.to_i
                data = {
                    :email => @session_user[:email],
                    :lesson_key => lesson_key,
                    :offset => offset,
                    :tablet_set_ids => tablet_sets,
                    :timestamp => timestamp,
                    :datum => datum,
                    :start_time => start_time,
                    :end_time => end_time
                }
                # create booking node
                neo4j_query(<<~END_OF_QUERY, data)
                    MATCH (u:User {email: {email}})
                    MERGE (l:Lesson {key: {lesson_key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    MERGE (b:Booking)-[:FOR]->(i)
                    MERGE (u)<-[:BOOKED_BY]-(b)
                    SET i.updated = {timestamp}
                    SET b.updated = {timestamp}
                    SET b.datum = {datum}
                    SET b.start_time = {start_time}
                    SET b.end_time = {end_time}

                    WITH b
                    MATCH (b)-[r:BOOKED]->(:TabletSet)
                    DELETE r
                END_OF_QUERY
                # connect booked tablet sets to booking node
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

    # book a list of tablet sets for a specific lesson, or unbook all tablet sets
    def book_tablet_set_for_timespan(datum, start_time, end_time, tablet_sets)
        require_admin!
        conflicting_tablets = []
        unless tablet_sets.empty?
            # check if it's bookable
            temp = already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
            conflicting_tablets = temp.keys
            conflicting_tablets.select! { |x| tablet_sets.include?(x) }
        end
        if conflicting_tablets.empty?
            transaction do
                # make sure tablet sets exist in database
                tablet_sets.each do |tablet_set_id|
                    neo4j_query("MERGE (:TabletSet {id: '#{tablet_set_id}'})")
                end
                timestamp = Time.now.to_i
                data = {
                    :email => @session_user[:email],
                    :tablet_set_ids => tablet_sets,
                    :timestamp => timestamp,
                    :datum => datum,
                    :start_time => start_time,
                    :end_time => end_time
                }
                # create booking node
                neo4j_query(<<~END_OF_QUERY, data)
                    MATCH (u:User {email: {email}})
                    CREATE (u)<-[:BOOKED_BY]-(b:Booking {datum: {datum}, start_time: {start_time}, end_time: {end_time}})
                    SET b.updated = {timestamp}

                    WITH b
                    MATCH (t:TabletSet)
                    WHERE t.id IN {tablet_set_ids}
                    CREATE (b)-[:BOOKED]->(t)
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

    def fach_for_lesson_key(lesson_key)
        (@@lessons[:lesson_keys][lesson_key] || {})[:pretty_folder_name] || 'NN'
    end

    post '/api/already_booked_tablet_sets_for_timespan' do
        require_admin!
        data = parse_request_data(:required_keys => [:datum, :start_time, :end_time])
        respond(:bookings => already_booked_tablet_sets_for_timespan(data[:datum], data[:start_time], data[:end_time]))
    end

    def find_available_tablet_sets(datum, start_time, end_time, lesson_key = nil, offset = nil)
        available_tablet_sets = []
        @@tablet_sets.keys.each do |tablet_id|
            available_tablet_sets << tablet_id
        end

        booked_tablet_sets_timespan = already_booked_tablet_sets_for_timespan(datum, start_time, end_time)
        booked_tablet_sets_day = already_booked_tablet_sets_for_day(datum)
        klasse5or6 = nil

        if lesson_key
            # consider klasse
            klassen = @@lessons[:lesson_keys][lesson_key][:klassen]
            klasse5or6 = klassen.any? { |x| [5, 6].include?(x.to_i) }

            # sort by :prio_unterstufe
            # available_tablet_sets.sort! do |a, b|
            #     a_prio = (!!@@tablet_sets[a][:prio_unterstufe]) ? 1 : 0
            #     b_prio = (!!@@tablet_sets[b][:prio_unterstufe]) ? 1 : 0
            #     dir = a_prio <=> b_prio
            #     if dir == 0
            #         a <=> b
            #     else
            #         dir * (klasse5or6 ? -1 : 1)
            #     end
            # end

            # also consider room
            begin
                timetable_date = @@lessons[:start_date_for_date][datum]
                wday = (Date.parse(datum).wday + 6) % 7
                raum = @@lessons[:timetables][timetable_date][lesson_key][:stunden][wday].values.first[:raum]
                available_tablet_sets.select! do |x|
                    if @@tablet_sets[x][:only_these_rooms_strict]
                        if @@tablet_sets[x][:only_these_rooms]
                            @@tablet_sets[x][:only_these_rooms].include?(raum)
                        else
                            true
                        end
                    else
                        true
                    end
                end
            rescue StandardError => e
                debug("An error occured while trying to determine the room for a lesson: #{e}, ignoring the room now...")
            end
        end

        tablet_sets = {}
        available_tablet_sets.each do |x|
            blocked_by = booked_tablet_sets_timespan[x]
            if lesson_key
                if blocked_by
                    blocked_by.reject! { |x| x[:lesson_key] == lesson_key}
                end
            end
            tablet_sets[x] = {
                :count => @@tablet_sets[x][:count],
                :standort => @@tablet_sets[x][:standort],
                :label => @@tablet_sets[x][:label],
                :blocked_by => blocked_by
            }
            hints = []
            if booked_tablet_sets_timespan[x]
                booked_tablet_sets_timespan[x].to_a.each do |entry|
                    if entry[:lesson_key] != @session_user[:lesson_key]
                        pretty_fach = fach_for_lesson_key(entry[:lesson_key])
                        hints << "<span class='text-danger'><i class='fa fa-warning'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wurde bereits von #{entry[:display_name]} gebucht#{entry[:lesson_key] ? ': ' + pretty_fach : ''}"
                    end
                end
            elsif booked_tablet_sets_day[x]
                bookings_before = []
                bookings_after = []
                booked_tablet_sets_day[x].each do |entry|
                    if entry[:end_time] <= start_time
                        bookings_before << entry
                    else
                        bookings_after << entry
                    end
                end
                unless bookings_before.empty?
                    booking = bookings_before.last
                    t = hh_mm_to_i(start_time) - hh_mm_to_i(booking[:end_time])
                    if t <= TABLET_SET_WARNING_BEFORE_MINUTES
                        pretty_fach = fach_for_lesson_key(booking[:lesson_key])
                        hints << "<span class='text-danger'><i class='fa fa-clock-o'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wird bis #{t} Minuten vor Stundenbeginn noch von #{booking[:display_name]} benötigt#{booking[:lesson_key] ? ': ' + pretty_fach : ''}"
                    end
                end
                unless bookings_after.empty?
                    booking = bookings_after.first
                    t = hh_mm_to_i(booking[:start_time]) - hh_mm_to_i(end_time)
                    if t <= TABLET_SET_WARNING_AFTER_MINUTES
                        pretty_fach = fach_for_lesson_key(booking[:lesson_key])
                        hints << "<span class='text-danger'><i class='fa fa-clock-o'></i></span>&nbsp;&nbsp;Dieser Tabletsatz wird bereits #{t} Minuten nach Stundenende von #{booking[:display_name]} benötigt#{booking[:lesson_key] ? ': ' + pretty_fach : ''}"
                    end
                end
            end
            if lesson_key && @@tablet_sets[x][:only_these_rooms]
                timetable_date = @@lessons[:start_date_for_date][datum]
                wday = (Date.parse(datum).wday + 6) % 7
                raum = nil
                begin
                    raum = @@lessons[:timetables][timetable_date][lesson_key][:stunden][wday].values.first[:raum]
                rescue
                end
                if raum
                    unless @@tablet_sets[x][:only_these_rooms].include?(raum)
                        hints << "<span class='text-danger'><i class='fa fa-warning'></i></span>&nbsp;&nbsp;Dieser Tabletsatz ist weit vom Raum #{raum} entfernt. Bitte wählen Sie deshalb – falls möglich – einen anderen Tabletsatz."
                    end
                end
            end
            unless klasse5or6.nil?
                if klasse5or6 && !@@tablet_sets[x][:prio_unterstufe]
                    hints << "<span class='text-danger'><i class='fa fa-warning'></i></span>&nbsp;&nbsp;Sie buchen einen Tabletsatz für eine Unterstufenklasse, dieser Tabletsatz ist allerdings für die Unterstufe nicht so leicht zu transportieren. Bitte wählen Sie deshalb – falls möglich – einen anderen Tabletsatz."
                elsif !klasse5or6 && @@tablet_sets[x][:prio_unterstufe]
                    hints << "<span class='text-danger'><i class='fa fa-warning'></i></span>&nbsp;&nbsp;Sie buchen einen Tabletsatz für die Mittel- oder Oberstufe, dieser Tabletsatz ist allerdings für die Unterstufe besonders leicht zu transportieren. Bitte wählen Sie deshalb – falls möglich – einen anderen Tabletsatz."
                end
            end
            if hints.empty?
                hints << "<span class='text-success'><i class='fa fa-check'></i></span>&nbsp;&nbsp;Dieser Tabletsatz ist eine gute Wahl für Ihre Unterrichtsstunde."
            end
            unless hints.empty?
                tablet_sets[x][:hint] = hints.join('<br />')
            end
        end
        return tablet_sets, available_tablet_sets
    end

    post '/api/find_available_tablet_sets_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :datum, 
                                                     :start_time, :end_time],
                                  :types => {:offset => Integer})

        tablet_sets, available_tablet_sets = find_available_tablet_sets(
            data[:datum], data[:start_time], data[:end_time], data[:lesson_key], data[:offset])

        respond(:available_tablet_sets => tablet_sets,
            :available_tablet_sets_order => available_tablet_sets)
    end

    post '/api/find_available_tablet_sets_for_timespan' do
        require_teacher!
        data = parse_request_data(:required_keys => [:datum, :start_time, :end_time])

        tablet_sets, available_tablet_sets = find_available_tablet_sets(
            data[:datum], data[:start_time], data[:end_time])

        respond(:available_tablet_sets => tablet_sets,
            :available_tablet_sets_order => available_tablet_sets)
    end

    post '/api/unbook_tablet_set_booking' do
        require_admin!
        data = parse_request_data(:required_keys => [:datum, :start_time, :end_time, :tablet_set])
        data[:timestamp] = Time.now.to_i
        result = neo4j_query_expect_one(<<~END_OF_QUERY, data)
            MATCH (u:User)<-[:BOOKED_BY]-(b:Booking {datum: {datum}, start_time: {start_time}, end_time: {end_time}})-[r:BOOKED]->(t:TabletSet {id: {tablet_set}})
            OPTIONAL MATCH (b)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            WITH DISTINCT r, u, l, i, b
            SET b.updated = {timestamp}
            SET i.updated = {timestamp}
            DELETE r
            RETURN u.email, l.key
        END_OF_QUERY

        lesson_key = result['l.key']
        email = result['u.email']
        session_user_name = @session_user[:display_last_name_dativ]

        if lesson_key
            trigger_update(lesson_key)
            fach = fach_for_lesson_key(lesson_key)
            deliver_mail do
                to email
                bcc SMTP_FROM
                from SMTP_FROM
                
                subject "Tabletsatz-Reservierung aufgehoben: #{fach}"

                StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>Es tut mir leid, aber Ihre Tabletsatz-Reservierung für #{fach} am #{data[:datum]} von #{data[:start_time]} bis #{data[:end_time]} wurde von #{session_user_name} aufgehoben. Sie können ggfs. einen neuen Tabletsatz buchen.</p>"
                    io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                    io.string
                end
            end
        else
            deliver_mail do
                to email
                bcc SMTP_FROM
                from SMTP_FROM
                
                subject "Tabletsatz-Reservierung aufgehoben"
    
                StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>Es tut mir leid, aber Ihre Tabletsatz-Reservierung am #{data[:datum]} von #{data[:start_time]} bis #{data[:end_time]} wurde von #{session_user_name} aufgehoben. Sie können ggfs. einen neuen Tabletsatz buchen.</p>"
                    io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                    io.string
                end
            end
        end

        STDERR.puts result.to_yaml
        respond(:ok => 'yay')
    end 

    post '/api/book_tablet_sets_for_timespan' do
        require_admin!
        data = parse_request_data(:required_keys => [:datum, :start_time, :end_time, :tablet_sets],
            :types => {:tablet_sets => Array})

        book_tablet_set_for_timespan(data[:datum], data[:start_time], data[:end_time], data[:tablet_sets])
        respond(:yay => 'ok')
    end
end