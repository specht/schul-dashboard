class Main < Sinatra::Base
    def create_session(email)
        sid = RandomTag::generate(24)
        assert(sid =~ /^[0-9A-Za-z]+$/)
        data = {:sid => sid,
                :expires => (DateTime.now() + 365).to_s}
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
                MATCH (s:Session {sid: {other_sid}})-[:BELONGS_TO]->(u:User {email: {email}})
                DETACH DELETE s;
            END_OF_QUERY
        end
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :data => data)
            MATCH (u:User {email: {email}})
            CREATE (s:Session {data})-[:BELONGS_TO]->(u)
            RETURN s; 
        END_OF_QUERY
        sid
    end
    
    post '/api/confirm_login' do
        data = parse_request_data(:required_keys => [:tag, :code])
        data[:code] = data[:code].gsub(/[^0-9]/, '')
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:LoginCode {tag: {tag}})-[:BELONGS_TO]->(u:User)
            RETURN l, u;
        END_OF_QUERY
        user = result['u'].props
        login_code = result['l'].props
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
        assert(Time.at(login_code[:valid_to]) >= Time.now)
        session_id = create_session(user[:email])
        result = neo4j_query(<<~END_OF_QUERY, :tag => data[:tag], :code => data[:code])
            MATCH (l:LoginCode {tag: {tag}, code: {code}})
            DETACH DELETE l;
        END_OF_QUERY
        purge_missing_sessions(session_id)
        respond(:ok => 'yeah')
    end
    
    post '/api/login_as_teacher_tablet' do
        require_admin!
        logout()
        session_id = create_session("lehrer.tablet@#{SCHUL_MAIL_DOMAIN}")
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yay')
    end
    
    post '/api/login_as_kurs_tablet' do
        require_admin!
        data = parse_request_data(:required_keys => [:shorthands],
                                  :max_body_length => 1024,
                                  :types => {:shorthands => Array})
        logout()
        session_id = create_session("kurs.tablet@#{SCHUL_MAIL_DOMAIN}")
        neo4j_query(<<~END_OF_QUERY, :sid => session_id, :shorthands => data[:shorthands])
            MATCH (s:Session {sid: {sid}})
            SET s.shorthands = {shorthands};
        END_OF_QUERY
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yeah')
    end

    def all_sessions
        sids = request.cookies['sid']
        users = []
        if (sids.is_a? String) && (sids =~ /^[0-9A-Za-z,]+$/)
            sids.split(',').each do |sid|
                if sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| {:sid => x['sid'], :email => x['email'] } }
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
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
                            MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
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
                    MATCH (s:Session {sid: {sid}})
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
    
    post '/api/login' do
        data = parse_request_data(:required_keys => [:email])
        data[:email] = data[:email].strip.downcase
        unless @@user_info.include?(data[:email]) && @@user_info[data[:email]][:can_log_in]
            sleep 3.0
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]), "Login requested for invalid email: #{data[:email]}", true)
        srand(Digest::SHA2.hexdigest(LOGIN_CODE_SALT).to_i + (Time.now.to_f * 1000000).to_i)
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        STDERR.puts "!!!!! #{data[:email]} => #{random_code} !!!!!"
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        # was causing problems with a user... maybe? huh...
#         neo4j_query(<<~END_OF_QUERY, :email => data[:email])
#             MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: {email}})
#             DETACH DELETE l;
#         END_OF_QUERY
        result = neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :code => random_code, :valid_to => valid_to.to_i)
            MATCH (n:User {email: {email}})
            CREATE (l:LoginCode {tag: {tag}, code: {code}, valid_to: {valid_to}})-[:BELONGS_TO]->(n)
            RETURN n, l;
        END_OF_QUERY
        begin
            deliver_mail do
                to data[:email]
                bcc SMTP_FROM
                from SMTP_FROM
                
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
        rescue StandardError => e
            if DEVELOPMENT
                STDERR.puts "Cannot send e-mail in DEVELOPMENT mode, continuing anyway:"
                STDERR.puts e
            else
                raise e
            end
        end
        respond(:tag => tag)
    end
    
    def get_sessions_for_user(email)
        require_user!
        sessions = neo4j_query(<<~END_OF_QUERY, :email => email).map { |x| x['s'].props }
            MATCH (s:Session)-[:BELONGS_TO]->(u:User {email: {email}})
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
                d = Time.parse(s[:expires]).strftime('%d.%m.%Y');
                io.puts "<td>#{d}</td>"
                d = Time.parse(s[:last_access]).strftime('%d.%m.%Y');
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
                MATCH (s:Session)-[:BELONGS_TO]->(:User {email: {email}})
                DETACH DELETE s;
            END_OF_QUERY
        else
            sessions = get_current_user_sessions().select { |x| x[:scrambled_sid] == data[:scrambled_sid] }
            sessions.each do |s|
                neo4j_query(<<~END_OF_QUERY, :sid => s[:sid])
                    MATCH (s:Session {sid: {sid}})
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
                MATCH (s:Session {sid: {sid}})
                DETACH DELETE s;
            END_OF_QUERY
        end
        respond(:ok => true)
    end
end
