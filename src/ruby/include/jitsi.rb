class Main < Sinatra::Base
    get '/api/jitsi_terms' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Nutzungshinweise-Meet.pdf'), 'application/pdf', "Nutzungshinweise-Meet.pdf")
    end
        
    get '/api/jitsi_dse' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Datenschutzerklärung-Meet.pdf'), 'application/pdf', "Datenschutzerklärung-Meet.pdf")
    end
    
    def gen_jwt_for_room(room = '', eid = nil, user = nil)
        payload = {
            :context => { :user => {}},
            :aud => JWT_APPAUD,
            :iss => JWT_APPISS,
            :sub => JWT_SUB,
            :room => room,
            :exp => DateTime.parse("#{Time.now.strftime('%Y-%m-%d')} 00:00:00").to_time.to_i + 24 * 60 * 60,
            :moderator => teacher_logged_in?
        }
        if user
            payload[:context][:user][:name] = user
        end
        if user_logged_in?
            use_user = @session_user
            if teacher_tablet_logged_in?
                use_user = @@user_info[@@shorthands[user]]
            elsif kurs_tablet_logged_in?
                use_user = {:display_name => 'Kursraum'}
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

        token = JWT.encode payload, JWT_APPKEY, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        token
    end
    
    def room_name_for_event(title, eid)
        "#{title} (#{eid[0, 8]})"
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
                result[:html] += "<hr />"
            else
                # it's a lesson, only allow between 07:00 and 18:00
                require_user!
                can_enter_room = true
                room_name = path
                if room_name.index('Klassenstream') == 0
                    if (!@session_user[:teacher]) && (!get_homeschooling_for_user(@session_user[:email])) && room_name.index('Klassenstream') == 0
                        result[:html] += "<div class='alert alert-danger'>Du bist momentan nicht für den Klassenstream freigeschaltet. Deine Klassenleiterin oder dein Klassenleiter kann dich dafür freischalten.</div>"
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
                    result[:html] = ''
                    lesson_key = path.sub('lesson/', '')
                    p_ymd = Date.today.strftime('%Y-%m-%d')
                    p_yw = Date.today.strftime('%Y-%V')
                    assert(user_logged_in?)
                    timetable_path = "/gen/w/#{@session_user[:id]}/#{p_yw}.json.gz"
                    timetable = nil
                    Zlib::GzipReader.open(timetable_path) do |f|
                        timetable = JSON.parse(f.read)
                    end
                    assert(!(timetable.nil?))
                    timetable = timetable['events'].select do |entry|
                        entry['lesson'] && entry['lesson_key'] == lesson_key && entry['datum'] == p_ymd && (entry['data'] || {})['lesson_jitsi']
                    end.sort { |a, b| a['start'] <=> b['start'] }
                    now_time = Time.now
                    old_timetable_size = timetable.size
                    timetable = timetable.reject do |entry|
                        t = Time.parse("#{entry['end']}:00") + JITSI_LESSON_POST_ENTRY_TOLERANCE * 60
                        now_time > t
                    end
                    if timetable.empty?
                        if old_timetable_size > 0
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht mehr geöffnet.</div>"
                        else
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht geöffnet.</div>"
                        end
                        can_enter_room = false
                    else
                        t = Time.parse("#{timetable.first['start']}:00") - JITSI_LESSON_PRE_ENTRY_TOLERANCE * 60
                        room_name = timetable.first['label_lehrer_lang'].gsub(/<[^>]+>/, '') + ' ' + timetable.first['klassen'].first.map { |x| tr_klasse(x) }.join(', ')
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
                room_name = CGI.escape(room_name.gsub(/[\:\?#\[\]@!$&\\'()*+,;=><\/"]/, '')).gsub('+', '%20')
                jwt = gen_jwt_for_room(room_name, eid, ext_name)
                result[:html] += "<div class='go_div'>\n"
                # edge firefox chrome safari opera internet-explorer
                if os_family == 'ios' || os_family == 'macosx'
                    result[:html] += "<a class='btn btn-success' href='org.jitsi.meet://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-apple'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet betreten (iPhone und iPad)</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://apps.apple.com/de/app/jitsi-meet/id1165103905' target='_blank'>App Store</a>.</em></p>"
                    unless browser_icon == 'safari'
                        result[:html] += "<a class='btn btn-outline-secondary' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                    end
                    if browser_icon == 'safari'
                        result[:html] += "<p style='font-size: 90%;'><em>Falls Sie einen Mac verwenden: Leider funktioniert Jitsi Meet nicht mit Safari. Verwenden Sie bitte einen anderen Web-Browser wie <a href='https://www.google.com/intl/de_de/chrome/' target='_blank'>Google Chrome</a> oder <a href='https://www.mozilla.org/de/firefox/new/' target='_blank'>Firefox</a>.</em></p>"
                    end
                elsif os_family == 'android'
                    result[:html] += "<a class='btn btn-success' href='intent://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}#Intent;scheme=org.jitsi.meet;package=org.jitsi.meet;end'><i class='fa fa-microphone'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet für Android betreten</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://play.google.com/store/apps/details?id=org.jitsi.meet' target='_blank'>Google Play Store</a> oder via <a href='https://f-droid.org/en/packages/org.jitsi.meet/' target='_blank' style=''>F&#8209;Droid</a>.</em></p>"
                    result[:html] += "<a class='btn btn-outline-secondary' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                else
                    result[:html] += "<a class='btn btn-success' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                end
                result[:html] += "</div>\n"
                result[:html] += "</div>\n"
            end
        rescue StandardError => e
            STDERR.puts "gen_jitsi_data failed for path [#{path}]"
            STDERR.puts e
            STDERR.puts e.backtrace
            result = {:html => "<p class='alert alert-danger'>Der Videochat konnte nicht gefunden werden.</p>"}
        end
        result
    end
end
