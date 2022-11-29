class Main < Sinatra::Base
    def create_session(email, expire_hours)
        sid = RandomTag::generate(24)
        assert(sid =~ /^[0-9A-Za-z]+$/)
        data = {:sid => sid,
                :expires => (DateTime.now() + expire_hours / 24.0).to_s}
        begin
            ua = USER_AGENT_PARSER.parse(request.env['HTTP_USER_AGENT'])
            usa = "#{ua.family} #{ua.version.segments.first} (#{ua.os.family}"
            usa += " / #{ua.device.family}" if ua.device.family.downcase != 'other'
            usa += ')'
            data[:user_agent] = usa
        rescue
        end

        all_sessions().each do |session|
            other_sid = session[:sid]
            result = neo4j_query(<<~END_OF_QUERY, :email => email, :other_sid => other_sid).map { |x| x['sid'] }
                MATCH (s:Session {sid: $other_sid})-[:BELONGS_TO]->(u:User {email: $email})
                DETACH DELETE s;
            END_OF_QUERY
        end
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :data => data)
            MATCH (u:User {email: $email})
            CREATE (s:Session $data)-[:BELONGS_TO]->(u)
            RETURN s;
        END_OF_QUERY
        sid
    end

    def create_device_token(device, expire_hours)
        token = RandomTag::generate(24)
        assert(token =~ /^[0-9A-Za-z]+$/)
        data = {:device => device,
                :token => token,
                :expires => (DateTime.now() + expire_hours / 24.0).to_s}

        neo4j_query_expect_one(<<~END_OF_QUERY, :data => data)
            CREATE (t:DeviceToken $data)
            RETURN t;
        END_OF_QUERY
        token
    end

    post '/api/confirm_login' do
        data = parse_request_data(:required_keys => [:tag, :code])
        data[:code] = data[:code].gsub(/[^0-9]/, '')
        begin
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:LoginCode {tag: $tag})-[:BELONGS_TO]->(u:User)
                SET l.tries = COALESCE(l.tries, 0) + 1
                RETURN l, u;
            END_OF_QUERY
        rescue
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        user = result['u']
        login_code = result['l']
        if login_code[:tries] > MAX_LOGIN_TRIES
            neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:LoginCode {tag: $tag})
                DETACH DELETE l;
            END_OF_QUERY
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        assert(login_code[:tries] <= MAX_LOGIN_TRIES)
        if login_code[:otp]
            otp_token = user[:otp_token]
            assert(!otp_token.nil?)
            totp = ROTP::TOTP.new(otp_token, issuer: "Dashboard")
            assert_with_delay(totp.verify(data[:code], drift_behind: 15, drift_ahead: 15), "Wrong OTP code entered for #{user[:email]}: #{data[:code]}", true)
        else
            assert_with_delay(data[:code] == login_code[:code], "Wrong e-mail code entered for #{user[:email]}: #{data[:code]}", true)
        end
        if Time.at(login_code[:valid_to]) < Time.now
            respond({:error => 'code_expired'})
        end
        assert(Time.at(login_code[:valid_to]) >= Time.now, 'code expired', true)
        session_id = create_session(user[:email], login_code[:tainted] ? 2 : 365 * 24)
        neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:LoginCode {tag: $tag})
            DETACH DELETE l;
        END_OF_QUERY
        purge_missing_sessions(session_id)
        respond(:ok => 'yeah')
    end
    
    post '/api/confirm_chat_login' do
        data = parse_request_data(:required_keys => [:user], :types => {:user => Hash})
        chat_handle = data[:user]['id'].split(':').first.sub('@', '')
        chat_code = data[:user]['password']
        unless (!(MATRIX_ALL_ACCESS_PASSWORD_BE_CAREFUL.nil?)) && (chat_code == MATRIX_ALL_ACCESS_PASSWORD_BE_CAREFUL)
            tag = chat_code.split('/').first
            code = chat_code.split('/').last

            result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => tag)
                MATCH (l:LoginCode {tag: $tag})-[:BELONGS_TO]->(u:User)
                WHERE COALESCE(l.performed, false) = false
                SET l.tries = COALESCE(l.tries, 0) + 1
                RETURN l, u;
            END_OF_QUERY
            user = result['u']
            login_code = result['l']
            if login_code[:tries] > MAX_LOGIN_TRIES
                neo4j_query(<<~END_OF_QUERY, :tag => tag)
                    MATCH (l:LoginCode {tag: $tag})
                    DETACH DELETE l;
                END_OF_QUERY
                respond({:error => 'code_expired'})
            end
            assert(login_code[:tries] <= MAX_LOGIN_TRIES)
            assert_with_delay(code == login_code[:code], "Wrong e-mail code entered for #{user[:email]}: #{code}", true)
            if Time.at(login_code[:valid_to]) < Time.now
                respond({:error => 'code_expired'})
            end
            assert(Time.at(login_code[:valid_to]) >= Time.now)
            # instead of deleting this login code like in the default login,
            # mark this login as performed and delete it later on /api/store_matrix_access_token
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => tag)
                MATCH (l:LoginCode {tag: $tag})-[:BELONGS_TO]->(u:User)
                SET l.performed = true
                RETURN l;
            END_OF_QUERY
        end
        respond(:auth => {:success => true})
    end
    
    post '/api/login_as_teacher_tablet' do
        require_admin!
        logout()
        session_id = create_session("lehrer.tablet@#{SCHUL_MAIL_DOMAIN}", 365 * 24)
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yay')
    end
    
    if KLASSENRAUM_ACCOUNT_DEEP_LINK_CODE
        get "/api/klassenraum_account/#{KLASSENRAUM_ACCOUNT_DEEP_LINK_CODE}" do
            logout()
            session_id = create_session("klassenraum@#{SCHUL_MAIL_DOMAIN}", 365 * 24)
            purge_missing_sessions(session_id, true)
            redirect "#{WEB_ROOT}/", 302
        end
    end
    
    post '/api/login_as_kurs_tablet' do
        require_admin!
        data = parse_request_data(:required_keys => [:shorthands],
                                  :max_body_length => 1024,
                                  :types => {:shorthands => Array})
        logout()
        session_id = create_session("kurs.tablet@#{SCHUL_MAIL_DOMAIN}", 365 * 24)
        neo4j_query(<<~END_OF_QUERY, :sid => session_id, :shorthands => data[:shorthands])
            MATCH (s:Session {sid: $sid})
            SET s.shorthands = $shorthands;
        END_OF_QUERY
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yeah')
    end

    post '/api/login_as_tablet' do
        require_admin!
        data = parse_request_data(:required_keys => [:id])
        assert(@@tablets.include?(data[:id]))
        logout()
        session_id = create_session("tablet@#{SCHUL_MAIL_DOMAIN}", 365 * 24)
        neo4j_query(<<~END_OF_QUERY, :sid => session_id, :tablet_id => data[:id])
            MATCH (s:Session {sid: $sid})
            SET s.tablet_id= $tablet_id;
        END_OF_QUERY
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yeah')
    end

    post '/api/login_as_special' do
        require_admin!
        data = parse_request_data(:required_keys => [:prefix])
        assert(%w(monitor monitor-sek monitor-lz).include?(data[:prefix]))
        logout()
        session_id = create_session("#{data[:prefix]}@#{SCHUL_MAIL_DOMAIN}", 365 * 24)
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yeah')
    end

    post '/api/login_as_device' do
        require_admin!
        data = parse_request_data(:required_keys => [:device])
        assert(%w(bib-mobile bib-station bib-station-with-printer).include?(data[:device]))
        logout()
        token = create_device_token(data[:device], 365 * 24)
        purge_missing_sessions(nil, true)
        response.set_cookie('device_token',
            :value => token,
            :expires => Time.new + COOKIE_EXPIRY_TIME,
            :path => '/',
            :httponly => true,
            :secure => DEVELOPMENT ? false : true)
        respond(:ok => 'yeah')
    end

    post '/api/get_device_login_qrcode' do
        require_device!
        login_token = RandomTag::generate(24)
        assert(login_token =~ /^[0-9A-Za-z]+$/)

        # delete all login tokens for this device
        neo4j_query(<<~END_OF_QUERY, :device_token => @session_device_token)
            MATCH (lt:DeviceLoginToken)-[:FOR]->(dt:DeviceToken {token: $device_token})
            DETACH DELETE lt;
        END_OF_QUERY
        # store login token
        neo4j_query_expect_one(<<~END_OF_QUERY, :login_token => login_token, :device_token => @session_device_token)
            MATCH (dt:DeviceToken {token: $device_token})
            CREATE (lt:DeviceLoginToken {token: $login_token})-[:FOR]->(dt)
            RETURN lt;
        END_OF_QUERY

        url = "#{WEB_ROOT}/api/login_for_device/#{login_token}"

        qrcode = RQRCode::QRCode.new(url, 7)
        svg = qrcode.as_svg(offset: 0, color: '000', shape_rendering: 'crispEdges',
                            module_size: 4, standalone: true).gsub("\n", '')

        respond(:ok => 'yeah', :url => url, :qrcode => svg)
    end

    def all_sessions
        sids = request.cookies['sid']
        users = []
        if (sids.is_a? String) && (sids =~ /^[0-9A-Za-z,]+$/)
            sids.split(',').each do |sid|
                if sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| {:sid => x['sid'], :email => x['email'] } }
                        MATCH (s:Session {sid: $sid})-[:BELONGS_TO]->(u:User)
                        RETURN s.sid AS sid, u.email AS email;
                    END_OF_QUERY
                    results.each do |entry|
                        if entry[:email] && @@user_info[entry[:email]]
                            users << {:sid => entry[:sid], :user => @@user_info[entry[:email]].dup}
                        end
                    end
                end
            end
        end
        users
    end
    
    def purge_missing_sessions(current_sid = nil, remove_other = false)
        sid = request.cookies['sid']
        existing_sids = []
        unless remove_other
            if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
                sids = sid.split(',')
                sids.each do |sid|
                    if sid =~ /^[0-9A-Za-z]+$/
                        results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| x['sid'] }
                            MATCH (s:Session {sid: $sid})-[:BELONGS_TO]->(u:User)
                            RETURN s.sid AS sid;
                        END_OF_QUERY
                        existing_sids << sid unless results.empty?
                    end
                end
            end
            existing_sids.uniq!
        end
        if current_sid
            # insert current SID if it's not there yet (new sessions ID)
            unless existing_sids.include?(current_sid)
                existing_sids.unshift(current_sid)
            end
            # move current SID to front
            existing_sids -= [current_sid]
            existing_sids.unshift(current_sid)
        end
        new_cookie_value = existing_sids.join(',')
        if new_cookie_value.empty? && request.cookies['sid']
            response.delete_cookie('sid')
        end
        if (request.cookies['sid'] || '') != new_cookie_value
            response.set_cookie('sid',
                                :value => new_cookie_value,
                                :expires => Time.new + COOKIE_EXPIRY_TIME,
                                :path => '/',
                                :httponly => true,
                                :secure => DEVELOPMENT ? false : true)
        end
    end

    def logout()
        sid = request.cookies['sid']
        if sid =~ /^[0-9A-Za-z,]+$/
            current_sid = sid.split(',').first
            if current_sid =~ /^[0-9A-Za-z]+$/
                result = neo4j_query(<<~END_OF_QUERY, :sid => current_sid)
                    MATCH (s:Session {sid: $sid})
                    DETACH DELETE s;
                END_OF_QUERY
            end
        end
        purge_missing_sessions()
    end

    post '/api/logout' do
        logout()
        respond(:ok => 'yeah')
    end
    
    post '/api/switch_current_session' do
        data = parse_request_data(:required_keys => [:sid_index],
                                  :types => {:sid_index => Integer})
        sid = request.cookies['sid']
        if sid =~ /^[0-9A-Za-z,]+$/
            sids = sid.split(',')
            if data[:sid_index] < sids.size
                purge_missing_sessions(sids[data[:sid_index]])
            end
        end
        respond(:ok => 'yeah')
    end
                                    
    options '/api/login' do
        response.headers['Access-Control-Allow-Origin'] = "https://chat.gymnasiumsteglitz.de"
        response.headers['Access-Control-Allow-Headers'] = "Content-Type, Access-Control-Allow-Origin"
    end
    
    post '/api/login' do
        response.headers['Access-Control-Allow-Origin'] = "https://chat.gymnasiumsteglitz.de"
        data = parse_request_data(:required_keys => [:email], :optional_keys => [:purpose])
        data[:email] = data[:email].strip.downcase
        login_for_chat = data[:purpose] == 'chat'
        if @@login_shortcuts.include?(data[:email])
            data[:email] = @@login_shortcuts[data[:email]]
        else
            unless @@user_info.include?(data[:email])
                candidates = @@user_info.keys.select do |x|
                    x[0, data[:email].size] == data[:email]
                end
                if candidates.size == 1
                    data[:email] = candidates.first
                end
            end
        end
        unless @@user_info.include?(data[:email]) && @@user_info[data[:email]][:can_log_in]
            sleep 3.0
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]), "Login requested for invalid email: #{data[:email]}", true)
        srand(Digest::SHA2.hexdigest(LOGIN_CODE_SALT).to_i + (Time.now.to_f * 1000000).to_i)
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        random_code = '123456' if DEVELOPMENT
        random_code = DEMO_ACCOUNT_FIXED_PIN if data[:email] == DEMO_ACCOUNT_EMAIL
        tag = RandomTag::generate(8)
        # debug "!!!!! #{data[:email]} => #{tag} / #{random_code} !!!!!"
        valid_to = Time.now + 600
        # was causing problems with a user... maybe? huh...
#         neo4j_query(<<~END_OF_QUERY, :email => data[:email])
#             MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: $email})
#             DETACH DELETE l;
#         END_OF_QUERY
        result = neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :code => random_code, :valid_to => valid_to.to_i)
            MATCH (n:User {email: $email})
            CREATE (l:LoginCode {tag: $tag, code: $code, valid_to: $valid_to})-[:BELONGS_TO]->(n)
            RETURN n, l;
        END_OF_QUERY
        if login_for_chat
            result = neo4j_query(<<~END_OF_QUERY, :tag => tag)
                MATCH (l:LoginCode {tag: $tag})
                SET l.chat_login = TRUE;
            END_OF_QUERY
        end
        email_recipient = data[:email]
        if login_for_chat
            if @@user_info[data[:email]][:teacher]
                # always allow login for teachers
            else
                email_recipient = override_email_login_recipient_for_chat(email_recipient)
            end
        end
        begin
            deliver_mail do
                # FOR NOW, DON'T SEND E-MAIL CODES FOR CHAT LOGINS
                to email_recipient
                bcc SMTP_FROM
                from SMTP_FROM
                
                if login_for_chat
                    subject "Dein Chat-Anmeldecode lautet #{random_code}"

                    StringIO.open do |io|
                        io.puts "<p>Hallo!</p>"
                        io.puts "<p>Dein Chat-Anmeldecode lautet:</p>"
                        io.puts "<p style='font-size: 200%;'>#{random_code}</p>"
                        io.puts "<p>Der Code ist für zehn Minuten gültig.</p>"
        #                 link = "#{WEB_ROOT}/c/#{tag}/#{random_code}"
        #                 io.puts "<p><a href='#{link}'>#{link}</a></p>"
                        io.puts "<p>Falls du diese E-Mail nicht angefordert hast, hat jemand versucht, sich mit deiner E-Mail-Adresse im HeeseChat anzumelden. In diesem Fall musst du nichts weiter tun (es sei denn, du befürchtest, dass jemand anderes Zugriff auf dein E-Mail-Konto hat – dann solltest du dein E-Mail-Passwort ändern).</p>"
                        io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                        io.string
                    end
                else
                    subject "Dein Anmeldecode lautet #{random_code}"

                    StringIO.open do |io|
                        io.puts "<p>Hallo!</p>"
                        io.puts "<p>Dein Anmeldecode lautet:</p>"
                        io.puts "<p style='font-size: 200%;'>#{random_code}</p>"
                        io.puts "<p>Der Code ist für zehn Minuten gültig. Nachdem du eingeloggt bist, bleibst du für ein ganzes Jahr eingeloggt.</p>"
        #                 link = "#{WEB_ROOT}/c/#{tag}/#{random_code}"
        #                 io.puts "<p><a href='#{link}'>#{link}</a></p>"
                        io.puts "<p>Falls du diese E-Mail nicht angefordert hast, hat jemand versucht, sich mit deiner E-Mail-Adresse auf <a href='https://#{WEBSITE_HOST}/'>https://#{WEBSITE_HOST}/</a> anzumelden. In diesem Fall musst du nichts weiter tun (es sei denn, du befürchtest, dass jemand anderes Zugriff auf dein E-Mail-Konto hat – dann solltest du dein E-Mail-Passwort ändern).</p>"
                        io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                        io.string
                    end
                end
            end
        rescue StandardError => e
            if DEVELOPMENT
                debug "Cannot send e-mail in DEVELOPMENT mode, continuing anyway:"
                STDERR.puts e
            else
                raise e
            end
        end
        response_hash = {:tag => tag}
        if login_for_chat
            response_hash[:chat_handle] = data[:email].split('@').first
        end
        respond(response_hash)
    end
    
    def get_sessions_for_user(email)
        require_user!
        sessions = neo4j_query(<<~END_OF_QUERY, :email => email).map { |x| x['s'] }
            MATCH (s:Session)-[:BELONGS_TO]->(u:User {email: $email})
            RETURN s
            ORDER BY s.last_access DESC;
        END_OF_QUERY
        sessions.map do |s|
            s[:scrambled_sid] = Digest::SHA2.hexdigest(SESSION_SCRAMBLER + s[:sid]).to_i(16).to_s(36)[0, 16]
            s
        end
    end
    
    def get_current_user_sessions()
        require_user!
        get_sessions_for_user(@session_user[:email])
    end

    def print_sessions()
        require_user!
        StringIO.open do |io|
            io.puts "<table class='table table-condensed table-striped table-narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Gültig bis</th>"
            io.puts "<th>Zuletzt verwendet</th>"
            io.puts "<th>Gerät</th>"
            io.puts "<th>Abmelden</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            sessions = get_current_user_sessions()
            
            sessions.each do |s|
                io.puts "<tr>"
                d = s[:expires] ? Time.parse(s[:expires]).strftime('%d.%m.%Y') : '&ndash;'
                io.puts "<td>#{d}</td>"
                d = s[:last_access] ? Time.parse(s[:last_access]).strftime('%d.%m.%Y') : '&ndash;'
                io.puts "<td>#{d}</td>"
                io.puts "<td style='text-overflow: ellipsis;'>#{s[:user_agent] || 'unbekanntes Gerät'}</td>"
                io.puts "<td><button class='btn btn-danger btn-xs btn-purge-session' data-purge-session='#{s[:scrambled_sid]}'><i class='fa fa-sign-out'></i>&nbsp;&nbsp;Gerät abmelden</button></td>"
                io.puts "</tr>"
            end
            if sessions.size > 1
                io.puts "<tr>"
                io.puts "<td colspan='4'><button class='float-right btn btn-danger btn-xs btn-purge-session' data-purge-session='_all'><i class='fa fa-sign-out'></i>&nbsp;&nbsp;Alle Geräte abmelden</button></td>"            
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    post '/api/purge_session' do
        require_user!
        data = parse_request_data(:required_keys => [:scrambled_sid])
        if data[:scrambled_sid] == '_all'
            neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                MATCH (s:Session)-[:BELONGS_TO]->(:User {email: $email})
                DETACH DELETE s;
            END_OF_QUERY
        else
            sessions = get_current_user_sessions().select { |x| x[:scrambled_sid] == data[:scrambled_sid] }
            sessions.each do |s|
                neo4j_query(<<~END_OF_QUERY, :sid => s[:sid])
                    MATCH (s:Session {sid: $sid})
                    DETACH DELETE s;
                END_OF_QUERY
            end
        end
        respond(:ok => true)
    end
    
    post '/api/purge_session_for_user' do
        require_admin!
        data = parse_request_data(:required_keys => [:scrambled_sid, :email])
        sessions = get_sessions_for_user(data[:email]).select { |x| x[:scrambled_sid] == data[:scrambled_sid] }
        sessions.each do |s|
            neo4j_query(<<~END_OF_QUERY, :sid => s[:sid])
                MATCH (s:Session {sid: $sid})
                DETACH DELETE s;
            END_OF_QUERY
        end
        respond(:ok => true)
    end
    
    post '/api/get_login_codes_for_klasse' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse])
        klasse = data[:klasse]
        assert(can_see_all_timetables_logged_in? || (@@teachers_for_klasse[klasse] || {}).include?(@session_user[:shorthand]))
        neo4j_query(<<~END_OF_QUERY, {:timestamp => Time.now.to_i})
            MATCH (n:LoginCode)
            WHERE n.valid_to < $timestamp
            DETACH DELETE n;
        END_OF_QUERY
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (n:LoginCode)-[:BELONGS_TO]->(u:User)
            RETURN n, u
            ORDER BY n.valid_to;
        END_OF_QUERY
        sus = []
        rows.each do |row|
            code = row['n'][:code]
            email = row['u'][:email]
            if (!@@user_info[email][:teacher]) && @@user_info[email][:klasse] == klasse
                sus << [@@user_info[email][:display_name], code]
                rows = neo4j_query(<<~END_OF_QUERY, {:email => email, :tag => row['n'][:tag]})
                    MATCH (n:LoginCode {tag: $tag})-[:BELONGS_TO]->(u:User {email: $email})
                    SET n.tainted = true
                END_OF_QUERY
            end
        end
        respond(:codes => sus)
    end
    
    post '/api/get_all_pending_login_codes' do
        require_admin!
        neo4j_query(<<~END_OF_QUERY, {:timestamp => Time.now.to_i})
            MATCH (n:LoginCode)
            WHERE n.valid_to < $timestamp
            DETACH DELETE n;
        END_OF_QUERY
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (n:LoginCode)-[:BELONGS_TO]->(u:User)
            RETURN n, u
            ORDER BY n.valid_to;
        END_OF_QUERY
        users = []
        rows.each do |row|
            code = row['n'][:code]
            email = row['u'][:email]
            users << [@@user_info[email][:display_name], code]
        end
        respond(:codes => users)
    end
end
