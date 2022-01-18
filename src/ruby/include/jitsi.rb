# discard presence token after 600 seconds unless it's renewed in the meantime
PRESENCE_TOKEN_EXPIRY_TIME = 60 * 10

class Main < Sinatra::Base
    get '/api/jitsi_terms' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Nutzungshinweise-Meet.pdf'), 'application/pdf', "Nutzungshinweise-Meet.pdf")
    end
        
    get '/api/jitsi_dse' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Datenschutzerklärung-Meet.pdf'), 'application/pdf', "Datenschutzerklärung-Meet.pdf")
    end
    
    def gen_jwt_for_room(room = '', eid = nil, user = nil, email = nil)
        payload = {
            :context => { :user => {}},
            :aud => JWT_APPAUD,
            :iss => JWT_APPISS,
            :sub => JWT_SUB,
            :room => room.strip,
            :exp => DateTime.parse("#{Time.now.strftime('%Y-%m-%d')} 00:00:00").to_time.to_i + 24 * 60 * 60,
            :moderator => teacher_logged_in?
        }
        payload[:context][:user][:name] = user if user
        payload[:context][:user][:email] = email if email
        if user_logged_in?
            use_user = @session_user
            if teacher_tablet_logged_in?
                use_user = @@user_info[@@shorthands[user]]
            elsif kurs_tablet_logged_in?
                use_user = {:display_name => 'Kursraum'}
            elsif klassenraum_logged_in?
                use_user = {:display_name => 'Klassenraum'}
            elsif tablet_logged_in?
                if @@tablets[@session_user[:tablet_id]][:klassen_stream]
                    use_user = {:display_name => "Klassenstreaming-Tablet #{@@tablets[@session_user[:tablet_id]][:klassen_stream]}"}
                    payload[:moderator] = true
                else
                    use_user = {:display_name => 'Tablet'}
                end
            end
            payload[:context][:user][:name] = use_user[:teacher] ? use_user[:display_last_name] : use_user[:display_name]
            payload[:context][:user][:email] = use_user[:email]
            payload[:context][:user][:avatar] = "#{NEXTCLOUD_URL}/index.php/avatar/#{use_user[:nc_login]}/128"
            if eid
                organizer_email = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :session_email => use_user[:email])['ou.email']
                    MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                    WHERE COALESCE(e.deleted, false) = false
                    RETURN ou.email;
                END_OF_QUERY
                payload[:moderator] = admin_logged_in? || (organizer_email == use_user[:email])
            end
        end
        assert(!(payload[:context][:user][:name].nil?))
        assert(payload[:context][:user][:name].strip.size > 0)
        assert(room.strip.size > 0)
        
        debug "Generated Jitsi token for #{payload[:context][:user][:name]} for #{payload[:room]}" if DEVELOPMENT
        
        token = JWT.encode payload, JWT_APPKEY, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        token
    end
    
    def gen_jwt_for_stream(name)
        payload = {
            :context => { :user => { :name => name }},
            :aud => JWT_APPAUD_STREAM,
            :iss => JWT_APPISS,
            :sub => JWT_SUB,
            :exp => DateTime.parse("#{Time.now.strftime('%Y-%m-%d')} 00:00:00").to_time.to_i + 24 * 60 * 60
        }
        assert(!(payload[:context][:user][:name].nil?))
        assert(payload[:context][:user][:name].strip.size > 0)

        token = JWT.encode payload, JWT_APPKEY_STREAM, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        token
    end
    
    def room_name_for_event(title, eid)
        "#{title} (#{eid[0, 8]})"
    end
    
    def self.stream_allowed_for_date_lesson_key_and_email(datum, lesson_key, email, restrictions = nil, is_homeschooling_user = nil, group2_for_email = nil)
        restrictions ||= Main.get_stream_restriction_for_lesson_key(lesson_key)
        weekday = (Date.parse(datum).wday + 6) % 7
        return true if restrictions[weekday] == 0
        user = @@user_info[email]
        return true if user.nil?
        return true if user[:teacher]
        klassenstufe = user[:klasse].to_i
        return true unless WECHSELUNTERRICHT_KLASSENSTUFEN.include?(klassenstufe)
        if restrictions[weekday] == 1
            if is_homeschooling_user.nil?
                return get_homeschooling_for_user_by_dauer_salzh(email)
            else
                return is_homeschooling_user
            end
        elsif restrictions[weekday] == 2
            return get_homeschooling_for_user(email, datum, is_homeschooling_user, group2_for_email)
        else
            true
        end
    end
    
    def gen_jitsi_data(path)
        ua = USER_AGENT_PARSER.parse(request.env['HTTP_USER_AGENT'])
        browser_icon = 'fa-microphone'
        browser_name = 'Browser'
        ['edge', 'firefox', 'chrome', 'safari', 'opera'].each do |x|
            if ua.family.downcase.include?(x)
                browser_icon = x
                browser_name = x.capitalize
            end
        end
        os_family = ua.os.family.downcase.gsub(/\s+/, '').strip
        result = {:html => "<p class='alert alert-danger'>Der Videochat konnte nicht gefunden werden.</p>"}
        room_name = nil
        can_enter_room = false
        eid = nil
        ext_name = nil
        begin
            presence_token = nil
            event_stream_jwt = nil
            if path == 'Lehrerzimmer'
                if teacher_logged_in?
                    room_name = 'Lehrerzimmer'
                    can_enter_room = true
                    result[:html] = ''
                    result[:html] += "<div class='alert alert-warning'><strong>Hinweis:</strong> Wenn Sie das Lehrerzimmer betreten, wird allen Kolleginnen und Kollegen über dem Stundenplan angezeigt, dass Sie momentan im Lehrerzimmer sind. Das Lehrerzimmer steht nicht nur Lehrkräften, sondern auch unseren Kolleg*innen aus dem Otium und dem Sekretariat zur Verfügung. Für Schülerinnen und Schüler ist der Zutritt nicht möglich.</div>"
                end
            elsif path[0, 6] == 'event/'
                result[:html] = ''
                # it's an event!
                parts = path.split('/')
                eid = parts[1]
                code = parts[2]
                invitation = nil
                organizer_email = nil
                event = nil
                data = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid)
                    MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                    WHERE COALESCE(e.deleted, false) = false
                    RETURN e, ou.email;
                END_OF_QUERY
                organizer_email = data['ou.email']
                event = data['e'].props
                room_name = room_name_for_event(event[:title], eid)
                
                if code
                    # EVENT - EXTERNAL USER WITH CODE
                    rows = neo4j_query(<<~END_OF_QUERY, :eid => eid)
                        MATCH (u)-[rt:IS_PARTICIPANT]->(e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                        WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(e.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                        RETURN e, ou.email, u;
                    END_OF_QUERY
                    invitation = rows.select do |row|
                        row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['e'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                        code == row_code
                    end.first
                    ext_name = invitation['u'].props[:name]
                    event_stream_jwt = gen_jwt_for_stream(ext_name) if event[:stream]
                else
                    # EVENT - INTERNAL USER
                    require_user!
                    begin
                        # EVENT - INTERNAL USER IS ORGANIZER
                        invitation = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :email => @session_user[:email])
                            MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User {email: {email}})
                            WHERE COALESCE(e.deleted, false) = false
                            RETURN e, ou.email;
                        END_OF_QUERY
                    rescue
                        # EVENT - INTERNAL USER IS INVITED
                        invitation = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :email => @session_user[:email])
                            MATCH (u:User {email: {email}})-[rt:IS_PARTICIPANT]->(e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                            WHERE COALESCE(e.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                            RETURN e, ou.email, u;
                        END_OF_QUERY
                    end
                    event_stream_jwt = gen_jwt_for_stream(@session_user[:display_name]) if event[:stream]
                end
                assert(invitation != nil)

                now = Time.now
                event_start = Time.parse("#{event[:date]}T#{event[:start_time]}")
                event_end = Time.parse("#{event[:date]}T#{event[:end_time]}")
                result[:html] += "<b class='key'>Termin:</b>#{event[:title]}<br />\n"
                result[:html] += "<b class='key'>Eingeladen von:</b>#{(@@user_info[organizer_email] || {})[:display_name]}<br />\n"
                event_date = Date.parse(event[:date])
                result[:html] += "<b class='key'>Datum:</b>#{WEEKDAYS[event_date.wday]}, #{event_date.strftime('%d.%m.%Y')}<br />\n"
                result[:html] += "<b class='key'>Zeit:</b>#{event[:start_time]} &ndash; #{event[:end_time]} Uhr<br />\n"
                if now < event_start - JITSI_EVENT_PRE_ENTRY_TOLERANCE * 60
                    result[:html] += "<div class='alert alert-warning'>Sie können den Raum erst #{JITSI_EVENT_PRE_ENTRY_TOLERANCE} Minuten vor Beginn betreten. Bitte laden Sie die Seite dann neu, um in den Raum zu gelangen.</div>"
                    # room can't yet be entered (too early)
                elsif now > event_end + JITSI_EVENT_POST_ENTRY_TOLERANCE * 60
                    # room can't be entered anymore (too late)
                    result[:html] += "<div class='alert alert-danger'>Der Termin liegt in der Vergangenheit. Sie können den Videochat deshalb nicht mehr betreten.</div>"
                else
                    can_enter_room = true
                end
                can_enter_room = true if admin_logged_in?
                result[:html] += "<hr />"
            else
                # it's a lesson, only allow between 07:00 and 18:00
                result[:html] = ''
                require_user!
                can_enter_room = true
                room_name = path
                if room_name.index('Klassenstream') == 0
                    if (!@session_user[:teacher]) && (!Main.get_homeschooling_for_user(@session_user[:email])) && room_name.index('Klassenstream') == 0
                        result[:html] += "<div class='alert alert-danger'>Du bist momentan nicht für den Klassenstream freigeschaltet, da du in Gruppe #{@session_user[:group2]} eingeteilt bist und auch nicht als »zu Hause« markiert bist. Deine Klassenleiterin oder dein Klassenleiter kann dich freischalten.</div>"
                        can_enter_room = false
                    end
                    if can_enter_room
                        now_s = Time.now.strftime('%H:%M')
                        if now_s < '07:00' || now_s > '18:00'
                            result[:html] += "<div class='alert alert-warning'>Der #{PROVIDE_CLASS_STREAM ? 'Klassenstream' : 'Stream'} ist nur von 07:00 bis 18:00 Uhr geöffnet.</div>"
                            can_enter_room = false
                        end
                    end
                else
                    if teacher_tablet_logged_in?
                        ext_name = path.split('@')[1]
                        ext_name = URI.decode_www_form(ext_name).first.first
                        path = path.split('@')[0]
                    end
                    if kurs_tablet_logged_in?
                        ext_name = 'Kursraum'
                        path = path.split('@')[0]
                    end
                    timetable_id = @session_user[:id]
                    if @session_user[:is_tablet]
                        tablet_id = @session_user[:tablet_id]
                        if (@@tablets[tablet_id] || {})[:school_streaming]
                            # determine teacher who has booked the tablet now
                            today = DateTime.now.strftime('%Y-%m-%d')
                            results = neo4j_query(<<~END_OF_QUERY, {:tablet_id => tablet_id, :today => today})
                                MATCH (t:Tablet {id: {tablet_id}})<-[:WHICH]-(b:Booking {datum: {today}, confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
                                RETURN b, i, l
                            END_OF_QUERY
                            now = DateTime.now.strftime('%Y-%m-%dT%H:%M')
                            found_teachers = Set.new()
                            results.each do |item|
                                booking = item['b'].props
                                lesson = item['l'].props
                                lesson_key = lesson[:key]
                                lesson_info = item['i'].props
                                lesson_data = @@lessons[:lesson_keys][lesson_key]
                                start_time = "#{booking[:datum]}T#{booking[:start_time]}"
                                end_time = "#{booking[:datum]}T#{booking[:end_time]}"
                                start_time = (DateTime.parse("#{start_time}:00") - STREAMING_TABLET_BOOKING_TIME_PRE / 24.0 / 60.0).strftime('%Y-%m-%dT%H:%M')
                                end_time = (DateTime.parse("#{start_time}:00") + STREAMING_TABLET_BOOKING_TIME_POST / 24.0 / 60.0).strftime('%Y-%m-%dT%H:%M')
                                if now >= start_time && now <= end_time
                                    found_teachers |= Set.new(lesson_data[:lehrer])
                                end
                            end
                            unless found_teachers.empty?
                                # force timetable_id to teacher who's currently running the lesson
                                timetable_id = @@user_info[@@shorthands[found_teachers.to_a.sort.first]][:id]
                            end
                        end
                    end
                    result[:html] = ''
                    lesson_key = path.split('/')[1]
                    if kurs_tablet_logged_in? || teacher_tablet_logged_in? || klassenraum_logged_in?
                        timetable_id = @@user_info[@@shorthands[@@lessons[:lesson_keys][lesson_key][:lehrer].first]][:id]
                    end
                    breakout_room_name = path.split('/')[2]
                    # TODO: use code from get_jitsi_room_name_for_lesson_key
                    p_ymd = Date.today.strftime('%Y-%m-%d')
                    p_yw = Date.today.strftime('%Y-%V')
                    assert(user_logged_in?)
                    timetable_path = "/gen/w/#{timetable_id}/#{p_yw}.json.gz"
                    timetable = nil
                    Zlib::GzipReader.open(timetable_path) do |f|
                        timetable = JSON.parse(f.read)
                    end
                    assert(!(timetable.nil?))
                    timetable = timetable['events'].select do |entry|
                        entry['lesson'] && 
                                entry['lesson_key'] == lesson_key && 
                                ((entry['datum'] == p_ymd) || DEVELOPMENT || admin_logged_in?) && 
                                (entry['data'] || {})['lesson_jitsi']
                    end.sort { |a, b| a['start'] <=> b['start'] }
                    now_time = Time.now
                    old_timetable_size = timetable.size
                    unless admin_logged_in?
                        timetable = timetable.reject do |entry|
                            t = Time.parse("#{entry['end']}:00") + JITSI_LESSON_POST_ENTRY_TOLERANCE * 60
                            now_time > t
                        end
                    end
                    if timetable.empty?
                        if old_timetable_size > 0
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht mehr geöffnet.</div>"
                        else
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht geöffnet.</div>"
                        end
                        if tablet_logged_in?
                            result[:html] += "<div class='alert alert-info'>Falls Sie Jitsi gerade erst aktiviert haben sollten, versuchen Sie bitte, die Seite neu zu laden, da es manchmal ein paar Sekunden dauern kann, bis der Raum tatsächlich aktiviert ist.</div>"
                        end
                        can_enter_room = false
                    else
                        # check if we have streaming restrictions for this lesson
                        lesson_info = timetable.first
                        
                        unless self.class.stream_allowed_for_date_lesson_key_and_email(Date.today.strftime('%Y-%m-%d'), lesson_info['lesson_key'], @session_user[:email])
                            result[:html] += "<div class='alert alert-info'>Du bist für diesen Jitsi-Raum leider nicht freigeschaltet.</div>"
                            can_enter_room = false
                        else
                            t = Time.parse("#{lesson_info['start']}:00") - JITSI_LESSON_PRE_ENTRY_TOLERANCE * 60
                            room_name = lesson_info['label_lehrer_lang'].gsub(/<[^>]+>/, '') + ' ' + lesson_info['klassen'].first.map { |x| tr_klasse(x) }.join(', ')
                            unless ((lesson_info['data'] || {})['breakout_rooms'] || []).empty?
                                if teacher_logged_in?
                                    presence_token = RandomTag::generate(24)
                                else
                                    # SuS is logged in, generate a presence token if we have roaming breakout rooms
                                    if (lesson_info['data'] || {})['breakout_rooms_roaming']
                                        presence_token = RandomTag::generate(24)
                                    end
                                end
                                if presence_token
                                    query_data = {
                                        :token => presence_token, 
                                        :lesson_key => lesson_info['lesson_key'], 
                                        :offset => lesson_info['lesson_offset'], 
                                        :email => @session_user[:email], 
                                        :timestamp => (Time.now + PRESENCE_TOKEN_EXPIRY_TIME).to_i
                                    }
                                    if DEVELOPMENT
                                        debug "Generating presence token"
                                        debug query_data.to_yaml
                                    end
                                    neo4j_query_expect_one(<<~END_OF_QUERY, query_data)
                                        MATCH (u:User {email: {email}}), (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
                                        CREATE (n:PresenceToken {token: {token}, expiry: {timestamp}})
                                        CREATE (i)<-[:FOR]-(n)-[:BELONGS_TO]->(u)
                                        RETURN n;
                                    END_OF_QUERY
                                end
                            end
                            if breakout_room_name
                                room_name += " #{breakout_room_name}"
                            end
                            if now_time >= t
                                can_enter_room = true
                            else
                                timediff = ((t - now_time).to_f / 60.0).ceil
                                tds = "#{timediff} Minute#{timediff == 1 ? '' : 'n'}"
                                tds = "#{timediff / 60} Stunde#{timediff / 60 == 1 ? '' : 'n'} und #{timediff % 60} Minute#{(timediff % 60) == 1 ? '' : 'n'}" if timediff > 60
                                if timediff == 1
                                    tds = 'einer Minute'
                                elsif timediff == 2
                                    tds = 'zwei Minuten'
                                elsif timediff == 3
                                    tds = 'drei Minuten'
                                elsif timediff == 4
                                    tds = 'vier Minuten'
                                elsif timediff == 5
                                    tds = 'fünf Minuten'
                                end
                                result[:html] += "<div class='alert alert-warning'>Der Jitsi-Raum <strong>»#{room_name}«</strong> ist erst ab #{t.strftime('%H:%M')} Uhr geöffnet. Du kannst ihn in #{tds} betreten.</div>"
                                can_enter_room = false
                            end
                        end
                    end
                    room_name = CGI.unescape(room_name)
                end
            end
            if can_enter_room
                # room can be entered now
                if ext_name
                    temp_name = ext_name.dup
                    if teacher_tablet_logged_in?
                        temp_name = @@user_info[@@shorthands[ext_name]][:display_last_name]
                    end
                    result[:html] += "<p>Sie können dem Videochat jetzt als <b>#{temp_name}</b> beitreten.</p>\n"
                end
                result[:html] += "<div class='alert alert-secondary'>\n"
                result[:html] += "<p>Ich habe die <a href='/api/jitsi_terms'>Nutzerordnung</a> und die <a href='/api/jitsi_dse'>Datenschutzerklärung</a> zur Kenntnis genommen und willige ein.</p>\n"
                room_name = CGI.escape(remove_accents(room_name).gsub(/[\:\?#\[\]@!$&\\'()*+,;=><\/"]/, '')).gsub('+', '%20')
                jwt = gen_jwt_for_room(room_name, eid, ext_name)
                result[:html] += "<div class='go_div'>\n"
                # edge firefox chrome safari opera internet-explorer
                if os_family == 'ios' || os_family == 'macosx'
                    result[:html] += "<a class='btn btn-success' href='org.jitsi.meet://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-apple'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet betreten (iPhone und iPad)</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://apps.apple.com/de/app/jitsi-meet/id1165103905' target='_blank'>App Store</a>.</em></p>"
                    unless browser_icon == 'safari'
                        result[:html] += "<a class='btn btn-outline-secondary' href='https://#{JITSI_HOST}/#{room_name}?#{presence_token ? "presence_token=#{presence_token}&" : ''}jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                    end
                    if browser_icon == 'safari'
                        result[:html] += "<p style='font-size: 90%;'><em>Falls Sie einen Mac verwenden: Leider funktioniert Jitsi Meet nicht mit Safari. Verwenden Sie bitte einen anderen Web-Browser wie <a href='https://www.google.com/intl/de_de/chrome/' target='_blank'>Google Chrome</a> oder <a href='https://www.mozilla.org/de/firefox/new/' target='_blank'>Firefox</a>.</em></p>"
                    end
                elsif os_family == 'android'
                    result[:html] += "<a class='btn btn-success' href='intent://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}#Intent;scheme=org.jitsi.meet;package=org.jitsi.meet;end'><i class='fa fa-microphone'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet für Android betreten</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://play.google.com/store/apps/details?id=org.jitsi.meet' target='_blank'>Google Play Store</a> oder via <a href='https://f-droid.org/en/packages/org.jitsi.meet/' target='_blank' style=''>F&#8209;Droid</a>.</em></p>"
                    result[:html] += "<a class='btn btn-outline-secondary' href='https://#{JITSI_HOST}/#{room_name}?#{presence_token ? "presence_token=#{presence_token}&" : ''}jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                else
                    result[:html] += "<a class='btn btn-success' href='https://#{JITSI_HOST}/#{room_name}?#{presence_token ? "presence_token=#{presence_token}&" : ''}jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                end
                if event_stream_jwt
                    result[:html] += "<div class='alert alert-warning'>"
                    result[:html] += "<p>Falls Sie im Jitsi-Raum <strong>Verbindungsprobleme</strong> oder <strong>Zeitverzögerungen</strong> erleben sollten, probieren Sie bitte den Livestream, der für diesen Termin bereitgestellt wird. Sie finden dort einen Chat, über den Sie Wortmeldungen und Fragen senden können.</p>"
                    result[:html] += "<a class='btn btn-warning' href='/livestream?jwt=#{event_stream_jwt}'><i class='fa fa-video-camera'></i>&nbsp;&nbsp;Zum Livestream…</a>"
                    result[:html] += "</div>"
                end
                result[:html] += "</div>\n"
                result[:html] += "</div>\n"
            end
        rescue StandardError => e
            debug "gen_jitsi_data failed for path [#{path}]"
            debug e
            debug e.backtrace
            result = {:html => "<p class='alert alert-danger'>Der Videochat konnte nicht gefunden werden.</p>"}
        end
        result
    end
    
    def current_jitsi_rooms()
        @@current_jitsi_rooms ||= nil
        @@current_jitsi_rooms_timestamp ||= Time.now
        if @@current_jitsi_rooms.nil? || Time.now > @@current_jitsi_rooms_timestamp + 10
            @@current_jitsi_rooms_timestamp = Time.now
            begin
                debug "Refreshing Jitsi presence!"
                c = Curl::Easy.new(JITSI_ALL_ROOMS_URL)
                c.perform
                if c.status.to_i == 200
                    @@current_jitsi_rooms = JSON.parse(c.body_str)['rooms']
                else
                    @@current_jitsi_rooms = nil
                end
            rescue
                @@current_jitsi_rooms = nil
            end
        end
        return @@current_jitsi_rooms
    end
    
    def get_jitsi_room_name_for_lesson_key(lesson_key, user = nil)
        p_ymd = Date.today.strftime('%Y-%m-%d')
        p_yw = Date.today.strftime('%Y-%V')
        user_id = @@user_info[user || @session_user[:email]][:id]
        timetable_path = "/gen/w/#{user_id}/#{p_yw}.json.gz"
        timetable = nil
        Zlib::GzipReader.open(timetable_path) do |f|
            timetable = JSON.parse(f.read)
        end
        assert(!(timetable.nil?))
        timetable = timetable['events'].select do |entry|
            entry['lesson'] && 
                    (entry['lesson_key'] == lesson_key) && 
                    ((entry['datum'] == p_ymd) || DEVELOPMENT || (user && ADMIN_USERS.include?(user))) && 
                    (entry['data'] || {})['lesson_jitsi']
        end.sort { |a, b| a['start'] <=> b['start'] }
        now_time = Time.now
        old_timetable_size = timetable.size
        unless (user && ADMIN_USERS.include?(user))
            timetable = timetable.reject do |entry|
                t = Time.parse("#{entry['end']}:00") + JITSI_LESSON_POST_ENTRY_TOLERANCE * 60
                now_time > t
            end
        end
        if timetable.empty?
            return nil
        else
            room_name = timetable.first['label_lehrer_lang'].gsub(/<[^>]+>/, '') + ' ' + timetable.first['klassen'].first.map { |x| tr_klasse(x) }.join(', ')
            return room_name
        end
    end
    
    def get_current_jitsi_users_for_lesson(lesson_key, offset, user = nil)
        lesson_info = neo4j_query_expect_one(<<~END_OF_QUERY, {:lesson_key => lesson_key, :offset => offset})['i'].props
            MATCH (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
            RETURN i;
        END_OF_QUERY
        room_name = get_jitsi_room_name_for_lesson_key(lesson_key, user)
        assert(!(room_name.nil?), 'not today!', true)
        lesson_room_name = CGI.escape(room_name.gsub(/[\:\?#\[\]@!$&\\'()*+,;=><\/"]/, '')).gsub('+', '%20').downcase

        jitsi_rooms = current_jitsi_rooms()
        room_participants = []
        breakout_room_index = {}
        breakout_room_urls = []
        (lesson_info[:breakout_rooms] || []).each.with_index do |room_name, i|
            room_participants << []
            escaped_room_name = CGI.escape(room_name.gsub(/[\:\?#\[\]@!$&\\'()*+,;=><\/"]/, '')).gsub('+', '%20').downcase
            escaped_room_name = "#{lesson_room_name}%20#{escaped_room_name}"
            breakout_room_urls << escaped_room_name
            breakout_room_index[escaped_room_name] = {
                :room_name => room_name,
                :index => i
            }
        end
        lesson_room_participants = []
        present_sus = Set.new()
        if jitsi_rooms
            jitsi_rooms.each do |room|
                entry = breakout_room_index[room['roomName'].downcase]
                if entry
                    room_participants[entry[:index]] = room['participants'].select do |x|
                        !((@@user_info[x['jwtEMail']] || {})[:teacher])
                    end.map do |x|
                        present_sus << x['jwtEMail']
                        x['jwtName']
                    end.sort.uniq
                end
                if room['roomName'].downcase == lesson_room_name
                    lesson_room_participants = room['participants'].select do |x|
                        !((@@user_info[x['jwtEMail']] || {})[:teacher])
                    end.map do |x|
                        present_sus << x['jwtEMail']
                        x['jwtName']
                    end.sort.uniq
                end
            end
        end
        missing_sus = (Set.new((@@schueler_for_lesson[lesson_key] || [])) - present_sus).map do |email|
            @@user_info[email][:display_name]
        end.sort
        {:lesson_room => lesson_room_participants, 
         :breakout_rooms => room_participants, 
         :missing_sus => (@@user_info[user] || {})[:teacher] ? missing_sus : nil,
         :breakout_room_names => lesson_info[:breakout_rooms],
         :lesson_room_name => lesson_room_name,
         :breakout_room_index => breakout_room_index,
         :breakout_room_urls => breakout_room_urls}
    end
    
    post '/api/get_current_jitsi_users_for_lesson' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})
        assert((@@lessons_for_shorthand[@session_user[:shorthand]] || []).include?(data[:lesson_key]), 'get_current_jitsi_users_for_lesson', true)
        respond(get_current_jitsi_users_for_lesson(data[:lesson_key], data[:offset]))
    end
    
    options '/api/get_current_jitsi_users_for_presence_token' do
        response.headers['Access-Control-Allow-Origin'] = "https://#{JITSI_HOST}"
        response.headers['Access-Control-Allow-Headers'] = "Content-Type, Access-Control-Allow-Origin"
    end
    
    post '/api/get_current_jitsi_users_for_presence_token' do
        response.headers['Access-Control-Allow-Origin'] = "https://#{JITSI_HOST}"
        data = parse_request_data(:required_keys => [:presence_token])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:presence_token => data[:presence_token], :now => Time.now.to_i, :new_expiry => (Time.now + PRESENCE_TOKEN_EXPIRY_TIME).to_i})
            MATCH (l:Lesson)<-[:BELONGS_TO]-(i:LessonInfo)<-[:FOR]-(n:PresenceToken {token: {presence_token}})-[:BELONGS_TO]->(u:User)
            WHERE n.expiry > {now}
            SET n.expiry = {new_expiry}
            RETURN u.email, i.offset, l.key;
        END_OF_QUERY
        email = result['u.email']
        display_name_for_email = @@user_info[email][:teacher] ? @@user_info[email][:display_last_name] : @@user_info[email][:display_name]
        result = get_current_jitsi_users_for_lesson(result['l.key'], result['i.offset'], email)
        result[:presence_token] = data[:presence_token]
        result[:jwt_links] = {}
        room_name = result[:lesson_room_name]
        jwt = gen_jwt_for_room(room_name, nil, display_name_for_email, email)
        result[:lesson_room_jwt_link] = "https://#{JITSI_HOST}/#{room_name}?presence_token=#{data[:presence_token]}&jwt=#{jwt}"
        (result[:breakout_room_names] || []).each.with_index do |breakout_room_name, i|
            room_name = result[:breakout_room_urls][i]
            jwt = gen_jwt_for_room(room_name, nil, display_name_for_email, email)
            result[:jwt_links][breakout_room_name] = "https://#{JITSI_HOST}/#{room_name}?presence_token=#{data[:presence_token]}&jwt=#{jwt}"
        end
        respond(result)
    end
end
