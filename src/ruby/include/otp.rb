class Main < Sinatra::Base
    def delete_session_user_otp_token()
        require_user!
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: $email})
            REMOVE u.otp_token
            REMOVE u.preferred_login_method;
        END_OF_QUERY
    end

    post '/api/regenerate_otp_token' do
        require_user!
        delete_session_user_otp_token()
        token = ROTP::Base32.random()
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :token => token)
            MATCH (u:User {email: $email})
            SET u.otp_token = $token;
        END_OF_QUERY
        @session_user[:otp_token] = token
        session_user = @session_user.dup

        deliver_mail do
            to session_user[:email]
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Dashboard: OTP-Anmeldung aktiviert"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Die OTP-Anmeldung wurde aktiviert.</p>"
                io.puts "<p>Falls Sie diese Aktivierung nicht selbst veranlasst haben, setzen Sie sich bitte dringend mit #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} unter der E-Mail-Adresse <a href='mailto:#{WEBSITE_MAINTAINER_EMAIL}'>#{WEBSITE_MAINTAINER_EMAIL}</a> in Verbindung.</p>"
                io.puts "<p>Die Aktivierung erfolgte am #{DateTime.now.strftime('%d.%m.%Y')} um #{DateTime.now.strftime('%H:%M')} Uhr (Gerät: #{session_user[:user_agent]}, IP: #{session_user[:ip]}).</p>"
                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                io.string
            end
        end

        respond(:qr_code => session_user_otp_qr_code(true))
    end

    post '/api/delete_otp_token' do
        require_user!
        delete_session_user_otp_token()
        respond(:ok => 'yeah')
    end

    def session_user_otp_qr_code(reveal = false)
        require_user!
        otp_token = @session_user[:otp_token]
        return nil if otp_token.nil?
        return '(redacted)' unless reveal
        totp = ROTP::TOTP.new(otp_token, issuer: "Dashboard")
        uri = totp.provisioning_uri(@session_user[:email])
        qrcode = RQRCode::QRCode.new(uri, 7)
        svg = qrcode.as_svg(offset: 0, color: '000', shape_rendering: 'crispEdges',
                            module_size: 4, standalone: true)
        svg.gsub("\n", '')
    end

    post '/api/login_otp' do
        data = parse_request_data(:required_keys => [:email])
        data[:email] = data[:email].strip.downcase
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
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]))
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: $email})
            DETACH DELETE l;
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :valid_to => valid_to.to_i)
            MATCH (n:User {email: $email})
            CREATE (l:LoginCode {tag: $tag, otp: true, valid_to: $valid_to})-[:BELONGS_TO]->(n)
            RETURN n;
        END_OF_QUERY
        respond(:tag => tag)
    end
end
