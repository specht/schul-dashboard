class Main < Sinatra::Base
    post '/api/save_lesson_data' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offsets, :data],
                                  :optional_keys => [:breakout_rooms, :booked_tablet_sets,
                                                     :booked_tablet_sets_timespan,
                                                     :datum_for_offset],
                                  :max_body_length => 65536,
                                  :types => {
                                      :lesson_offsets => Array, :data => Hash,
                                      :breakout_rooms => Hash, :booked_tablet_sets => Array,
                                      :booked_tablet_sets_timespan => Hash,
                                      :datum_for_offset => Hash})
        transaction do
            timestamp = Time.now.to_i
            data[:lesson_offsets].each do |lesson_offset|
                results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :data => data[:data], :timestamp => timestamp)
                    MERGE (l:Lesson {key: $key})
                    MERGE (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l)
                    SET i += $data
                    SET i.updated = $timestamp;
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                    MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                    SET b.confirmed = true
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                    MATCH (t:Tablet)<-[:WHICH]-(b:Booking {to_be_deleted: true})-[:FOR]->(i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                    DETACH DELETE b;
                END_OF_QUERY
                if data[:data]['lesson_fixed']
                    datum = data[:datum_for_offset][lesson_offset.to_s]
                    debug "Fixing lesson #{lesson_offset} to #{datum}!"
                    neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :datum => datum)
                        MATCH (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                        SET i.lesson_fixed_for = $datum;
                    END_OF_QUERY
                end
                if data.include?(:breakout_rooms)
                    if data[:breakout_rooms].empty?
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset)
                            MATCH (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                            REMOVE i.breakout_rooms
                            REMOVE i.breakout_room_participants
                            REMOVE i.breakout_rooms_roaming
                        END_OF_QUERY
                    else
                        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :breakout_rooms => data[:breakout_rooms]['rooms'] || [], :breakout_room_participants => data[:breakout_rooms]['participants'], :breakout_rooms_roaming => data[:breakout_rooms]['roaming'])
                            MATCH (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                            SET i.breakout_rooms = $breakout_rooms
                            SET i.breakout_room_participants = $breakout_room_participants
                            SET i.breakout_rooms_roaming = $breakout_rooms_roaming
                        END_OF_QUERY
                    end
                end
                if data.include?(:booked_tablet_sets) && data.include?(:booked_tablet_sets_timespan)
                    book_tablet_set_for_lesson(data[:booked_tablet_sets_timespan]['datum'],
                        data[:booked_tablet_sets_timespan]['start_time'],
                        data[:booked_tablet_sets_timespan]['end_time'],
                        data[:booked_tablet_sets], data[:lesson_key], lesson_offset)
                end
            end
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end

    def get_ha_amt_lesson_keys()
        return [] unless user_logged_in?
        return [] if teacher_logged_in?
        results = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: $email})-[r:HAS_AMT {amt: 'hausaufgaben'}]->(l:Lesson)
            RETURN l.key;
        END_OF_QUERY
        return results.map { |x| x['l.key'] }
    end

    post '/api/set_ha_amt_text_for_lesson' do
        # require teacher OR require schueler with HA amt enabled
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset, :ha_amt_text],
                                  :max_body_length => 1024,
                                  :types => {:lesson_offset => Integer})
        require_teacher_for_lesson_or_ha_amt_logged_in(data[:lesson_key])
        timestamp = Time.now.to_i
        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :ha_amt_text => data[:ha_amt_text], :timestamp => timestamp)
            MERGE (l:Lesson {key: $key})
            MERGE (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l)
            SET i.ha_amt_text = $ha_amt_text
            SET i.updated = $timestamp;
        END_OF_QUERY
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end

    post '/api/get_ha_amt_text_for_lesson' do
        # require teacher OR require schueler with HA amt enabled
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        require_teacher_for_lesson_or_ha_amt_logged_in(data[:lesson_key])
        ha_amt_text = nil
        begin
            ha_amt_text = neo4j_query_expect_one(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :ha_amt_text => data[:ha_amt_text])['i.ha_amt_text']
                MATCH (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l:Lesson {key: $key})
                RETURN i.ha_amt_text;
            END_OF_QUERY
        rescue StandardError => e
            STDERR.puts e
        end
        ha_amt_text ||= ''
        respond(:ha_amt_text => ha_amt_text)
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
                MERGE (l:Lesson {key: $key})
                MERGE (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l)
                SET i += $data
                SET i.updated = $timestamp;
            END_OF_QUERY
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end

    def self.get_lesson_data(lesson_key)
        # purge unconfirmed tablet bookings for this lesson_key
        $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $key})
            DETACH DELETE b;
        END_OF_QUERY
        # purge unconfirmed tablet bookings for any lesson key older than 30 minutes
        $neo4j.neo4j_query(<<~END_OF_QUERY, :timestamp => (Time.now - 30 * 60).to_i)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: false})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            WHERE b.updated < $timestamp
            DETACH DELETE b;
        END_OF_QUERY
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| x['i'] }
            MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $key})
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
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'], :user => x['u'], :text_comment_from => x['tcf.email'] } }
            MATCH (u:User)<-[:TO]-(c:TextComment)-[:BELONGS_TO]->(l:Lesson {key: $key})
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
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'], :user => x['u'], :audio_comment_from => x['acf.email'] } }
            MATCH (u:User)<-[:TO]-(c:AudioComment)-[:BELONGS_TO]->(l:Lesson {key: $key})
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
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:offset => x['li.offset'], :feedback => x['hf'], :user => x['u.email'] }}
            MATCH (u:User)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $key})
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

        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key)
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $key})
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

        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :key => lesson_key)
            MATCH (t:TabletSet)<-[:BOOKED]-(b:Booking)-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $key})
            RETURN t.id, i.offset
            ORDER BY t.id;
        END_OF_QUERY
        rows.each do |entry|
            offset = entry['i.offset']
            tablet_set_id = entry['t.id']
            next if @@tablet_sets[tablet_set_id].nil?
            results[offset] ||= {}
            results[offset][:info] ||= {}
            results[offset][:info][:booked_tablet_sets] ||= []
            results[offset][:info][:booked_tablet_sets] << tablet_set_id
            results[offset][:info][:booked_tablet_sets_tablet_count] ||= 0
            results[offset][:info][:booked_tablet_sets_tablet_count] += @@tablet_sets[tablet_set_id][:count]
        end

        results
    end

    post '/api/get_lesson_data' do
        data = parse_request_data(:required_keys => [:lesson_key])
        results = Main.get_lesson_data(data[:lesson_key])
        respond(:results => results)
    end

    post '/api/insert_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :shift],
                                  :types => {:offset => Integer, :shift => Integer})
        timestamp = Time.now.to_i
        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:offset], :shift => data[:shift], :timestamp => timestamp)
            MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: $key})
            WHERE n.offset >= $offset
            SET n.offset = n.offset + $shift
            SET n.updated = $timestamp;
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
                MATCH (n:LessonInfo {offset: $offset})-[:BELONGS_TO]->(:Lesson {key: $key})
                DETACH DELETE n;
            END_OF_QUERY
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => offset - cumulative_offset, :timestamp => timestamp)
                MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: $key})
                WHERE n.offset > $offset
                SET n.offset = n.offset - 1
                SET n.updated = $timestamp;
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
        bookings = neo4j_query(<<~END_OF_QUERY, :datum => data[:datum]).map { |x| {:tablet_id => x['t.id'], :booking => x['b'], :lesson_key => x['l.key']} }
            MATCH (t:Tablet)<-[:WHICH]-(b:Booking {datum: $datum})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
            RETURN t.id, b, l.key;
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
            entry_shorthands = @@lessons[:lesson_keys][item[:lesson_key]][:lehrer]
            unless (request_shorthands & entry_shorthands).empty?
                favoured_tablets << tablet_id
            else
                unless request_end_time < start_time && request_start_time > end_time
                    available_tablets.delete(tablet_id)
                end
            end
        end

#         debug "available_tablets: #{available_tablets.to_a.sort.join(', ')}"
#         debug "tablets_booked_today: #{tablets_booked_today.to_a.sort.join(', ')}"
#         debug "favoured_tablets: #{favoured_tablets.to_a.sort.join(', ')}"

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
                    MERGE (l:Lesson {key: $lesson_key})
                    MERGE (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l)

                    WITH l, i
                    MATCH (i)<-[:FOR]->(b2:Booking)-[:WHICH]->(:Tablet)
                    DETACH DELETE b2
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, data)
                    MERGE (l:Lesson {key: $lesson_key})
                    MERGE (i:LessonInfo {offset: $offset})-[:BELONGS_TO]->(l)

                    WITH l, i
                    MATCH (t:Tablet {id: $tablet_id})

                    WITH l, i, t
                    MERGE (i)<-[:FOR]-(b:Booking)-[:WHICH]->(t)
                    SET b.updated = $timestamp
                    SET b.datum = $datum
                    SET b.start_time = $start_time
                    SET b.end_time = $end_time
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
            # delete unconfirmed bookings for this lesson_key / offset
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: $lesson_key})<-[:BELONGS_TO]-(i:LessonInfo {offset: $offset})<-[:FOR]-(b:Booking {confirmed: false})-[:WHICH]->(t:Tablet)
                DETACH DELETE b;
            END_OF_QUERY
            # mark confirmed bookings for this lesson_key / offset as 'to be deleted'
            neo4j_query(<<~END_OF_QUERY, data)
                MATCH (l:Lesson {key: $lesson_key})<-[:BELONGS_TO]-(i:LessonInfo {offset: $offset})<-[:FOR]-(b:Booking {confirmed: true})-[:WHICH]->(t:Tablet)
                SET b.to_be_deleted = true
                SET b.updated = $timestamp;
            END_OF_QUERY
        end
    end

    post '/api/get_tablet_bookings' do
        require_admin!
        d0 = DateTime.now.strftime('%Y-%m-%d')
        d1 = (DateTime.now + 7).strftime('%Y-%m-%d')
        rows = neo4j_query(<<~END_OF_QUERY, {:d0 => d0, :d1 => d1})
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:FOR]-(b:Booking {confirmed: true})-[:WHICH]->(t:Tablet)
            WHERE b.datum >= $d0 AND b.datum <= $d1
            RETURN l, i, b, t
            ORDER BY t.id
        END_OF_QUERY
        results = {}
        rows.each do |row|
            lesson = row['l']
            lesson_key = lesson[:key]
            lesson_info = row['i']
            booking = row['b']
            tablet = row['t']
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

    def self.get_stream_restriction_for_lesson_key(lesson_key)
        results = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, :key => lesson_key)['restriction']
            MERGE (l:Lesson {key: $key})
            RETURN COALESCE(l.stream_restriction, []) AS restriction
        END_OF_QUERY
        while results.size < 5
            results << 0
        end
        results
    end

    def self.get_all_stream_restrictions()
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (l:Lesson)
            RETURN l.key AS lesson_key, COALESCE(l.stream_restriction, []) AS restriction
        END_OF_QUERY
        results = {}
        temp.each do |entry|
            lesson_key = entry['lesson_key']
            restriction = entry['restriction']
            while restriction.size < 5
                restriction << 0
            end
            results[lesson_key] = restriction
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
            io.puts "Falls Sie einschränken möchten, welche Kinder in Ihrem Unterricht am Streaming teilnehmen dürfen, können Sie dies hier tun. Standardmäßig ist der Stream, falls Sie ihn aktivieren, für alle Kinder aktiviert. Sie können zwei Einschränkungen vornehmen: a) nur für Kinder, die planmäßig gerade nicht in der Schule sind + Kinder, die dauerhaft zu Hause sind (»nicht für Wechselgruppe in Präsenz«) oder b) nur für Kinder, die dauerhaft zu Hause, also oben als »zu Hause« markiert sind (»nur für Dauer-saLzH«)."
            io.puts "</div>"
            io.puts "<div class='table-responsive'>"
            io.puts "<table class='table stream-restriction-table'>"
            io.puts "<tr>"
            io.puts "<th style='text-align: left;'>Fach</th>"
            io.puts "<th>Montag</th>"
            io.puts "<th>Dienstag</th>"
            io.puts "<th>Mittwoch</th>"
            io.puts "<th>Donnerstag</th>"
            io.puts "<th>Freitag</th>"
            io.puts "</tr>"
            lesson_keys.each do |lesson_key|
                io.puts "<tr>"
                restrictions = self.class.get_stream_restriction_for_lesson_key(lesson_key)
                io.puts "<td style='text-align: left;'>"
                lesson_info = @@lessons[:lesson_keys][lesson_key]
                io.puts "#{lesson_info[:pretty_folder_name]}"
                io.puts "</td>"
                restrictions.each.with_index do |r, i|
                    btn_style = 'btn-primary'
                    btn_label = 'für alle'
                    if r == 1
                        btn_style = 'btn-info'
                        btn_label = 'nur für Dauer-saLzH'
                    elsif r == 2
                        btn_style = 'btn-warning'
                        btn_label = 'nicht für Wechselgruppe in Präsenz'
                    end
                    io.puts "<td>"
                    io.puts "<button data-lesson-key='#{lesson_key}' data-day='#{i}' class='bu-toggle-stream-restriction btn #{btn_style}'>#{btn_label}</button>"
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
        restrictions = self.class.get_stream_restriction_for_lesson_key(data[:lesson_key]);
        restrictions[day] = (restrictions[day] + 2) % 3
        neo4j_query(<<~END_OF_QUERY, {:restrictions => restrictions, :lesson_key => data[:lesson_key]})
            MERGE (l:Lesson {key: $lesson_key})
            SET l.stream_restriction = $restrictions
        END_OF_QUERY
        trigger_update(data[:lesson_key])
        respond(:state => restrictions[day])
    end

    get '/api/get_lesson_info_archive' do
        require_admin!
        file = Tempfile.new('lesson_info_archive')
        zip = nil
        begin
            Zip.unicode_names = true
            Zip.force_entry_names_encoding = 'UTF-8'
            Zip::File.open(file.path, Zip::File::CREATE) do |zipfile|
                @@lessons[:lesson_keys].keys.each do |lesson_key|
                    info = @@lessons[:lesson_keys][lesson_key]
                    temp = neo4j_query(<<~END_OF_QUERY, {:lesson_key => lesson_key}).map { |x| x['li'] }
                        MATCH (li:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
                        RETURN li
                        ORDER BY li.offset;
                    END_OF_QUERY
                    unless temp.empty?
                        info[:lehrer].each do |shorthand|
                            path = "#{shorthand}/#{lesson_key} – #{info[:pretty_folder_name]}.json"
                            zipfile.get_output_stream(path) do |f|
                                info = {:lesson_key => lesson_key, :entries => temp}
                                f.write(info.to_json)
                            end
                        end
                    end
                end
            end
        ensure
            file.close
            zip = File.read(file.path)
            file.unlink
        end

        respond_raw_with_mimetype_and_filename(zip, 'application/zip', "lesson_info_archive.zip")
    end

    post '/api/add_sus_to_amt' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:lesson_key, :amt, :email])

        neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :amt => data[:amt], :email => data[:email])
            MATCH (u:User {email: $email})
            MERGE (l:Lesson {key: $key})
            WITH u, l
            MERGE (u)-[r:HAS_AMT {amt: $amt}]->(l);
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/remove_sus_from_amt' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:lesson_key, :amt, :email])

        neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :amt => data[:amt], :email => data[:email])
            MATCH (u:User {email: $email})-[r:HAS_AMT {amt: $amt}]->(l:Lesson {key: $key})
            DELETE r;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/get_amt_sus' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:lesson_key])

        rows = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key])
            MATCH (u:User)-[r:HAS_AMT]->(l:Lesson {key: $key})
            RETURN u.email, r.amt;
        END_OF_QUERY
        results = {}
        rows.each do |row|
            email = row['u.email']
            amt = row['r.amt']
            results[email] ||= []
            results[email] << amt
        end
        respond(:results => results)
    end

    get '/api/kursbuch_pdf/*' do
        require_teacher!
        lesson_key = request.path.sub('/api/kursbuch_pdf/', '')
        lesson_key_id = @@lessons[:lesson_keys][lesson_key][:id]
        lesson_data = Main.get_lesson_data(lesson_key)
        lesson_events = nil
        Zlib::GzipReader.open("/gen/w/#{lesson_key_id}/all.json.gz") do |f|
            lesson_events = JSON.parse(f.read)
        end
        main = self
        y = 0
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait,
                                  :margin => 0) do
            font_families.update(
                "Roboto Condensed" => {
                    :bold        => "/app/fonts/RobotoCondensed-Bold.ttf",
                    :italic      => "/app/fonts/RobotoCondensed-Italic.ttf",
                    :bold_italic => "/app/fonts/RobotoCondensed-BoldItalic.ttf",
                    :normal      => '/app/fonts/RobotoCondensed-Regular.ttf' })
            font('Roboto Condensed') do
                font_size 10
                line_width 0.1.mm
                px = 1.mm
                py = 1.mm
                lesson_events.each do |event|
                    next unless event['lesson']
                    lesson_offset = event['lesson_offset']
                    count = event['count']
                    height = 20.33.mm
                    bounding_box([10.mm, 297.0.mm - 22.mm - height * y], width: 189.mm, height: height) do
                        x = 0.mm
                        width = 14.mm
                        bounding_box([x, height], width: width, height: height) do
                            stroke_bounds
                            d = Date.parse(event['datum'])
                            text_box d.strftime("%d.%m.\n%Y"), at: [px, height - py], width: width - px * 2, height: height - py * 2, align: :center
                        end
                        x += width
                        width = 12.mm
                        bounding_box([x, height], width: width, height: height) do
                            stroke_bounds
                            stunde = count > 1 ? "#{event['stunde']}.–#{event['stunde'].to_i + count - 1}." : "#{event['stunde']}."
                            text_box stunde, at: [px, height - py], width: width - px * 2, height: height - py * 2, align: :center
                        end
                        x += width
                        width = 69.mm
                        stundenthema_text = Set.new()
                        hausaufgaben_text = Set.new()
                        (0...count).each do |offset|
                            info = lesson_data[lesson_offset + offset]
                            next if info.nil?
                            stundenthema_text << info[:info][:stundenthema_text]
                            parts = []
                            parts << info[:info][:hausaufgaben_text]
                            parts << info[:info][:ha_amt_text]
                            parts.reject! { |x| x.nil? || x.empty? }
                            hausaufgaben_text << parts.join("\n")
                        end
                        bounding_box([x, height], width: width, height: height) do
                            stroke_bounds
                            begin
                                text_box stundenthema_text.to_a.join("\n").unicode_normalize(:nfc), at: [px, height - py], width: width - px * 2, height: height - py * 2
                            rescue
                            end
                        end
                        x += width
                        width = 93.mm
                        bounding_box([x, height], width: width, height: height) do
                            stroke_bounds
                            begin
                                text_box hausaufgaben_text.to_a.join("\n").unicode_normalize(:nfc), at: [px, height - py], width: width - px * 2, height: height - py * 2
                            rescue
                            end
                        end
                    end
                    y += 1
                    if y > 12
                        start_new_page
                        y = 0
                    end
                end
                # y = 297.mm - 20.mm
                # draw_text "#{lesson_key}", :at => [30.mm, y + 6.pt]
                # line_width 0.2.mm
                # stroke { line [30.mm, y + 20.7.pt], [77.mm, y + 20.7.pt] } if i == 0
                # stroke { line [30.mm, y], [77.mm, y] }
            end
        end
        # respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    post '/api/set_hybrid_notes' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset, :text],
            :max_body_length => 4096,
            :max_string_length => 4096,
            :types => {:lesson_offset => Integer})
        text = data[:text].strip
        timestamp = Time.now.to_i
        neo4j_query(<<~END_OF_QUERY, :lesson_key => data[:lesson_key], :lesson_offset => data[:lesson_offset], :text => text, :email => @session_user[:email], :timestamp => timestamp)
            MERGE (u:User {email: $email})
            MERGE (l:Lesson {key: $lesson_key})
            MERGE (i:LessonInfo {offset: $lesson_offset})-[:BELONGS_TO]->(l)
            MERGE (u)<-[:BY]-(n:LessonNote)-[:FOR]->(i)
            SET n.text = $text
            SET n.updated = $timestamp;
        END_OF_QUERY
        trigger_update("_#{@session_user[:email]}")
        ((@@lessons[:lesson_keys][data[:lesson_key]] || {})[:lehrer] || []).each do |shorthand|
            teacher_email = @@shorthands[shorthand]
            trigger_update("_#{teacher_email}")
        end
        respond(:ok => true)
    end
end
