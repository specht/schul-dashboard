class Main < Sinatra::Base
    def delete_session_user_otp_token()
        require_user!
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: {email}})
            REMOVE u.otp_token;
        END_OF_QUERY
    end
    
    post '/api/regenerate_otp_token' do
        require_user!
        delete_session_user_otp_token()
        token = ROTP::Base32.random()
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :token => token)
            MATCH (u:User {email: {email}})
            SET u.otp_token = {token};
        END_OF_QUERY
        @session_user[:otp_token] = token
        respond(:qr_code => session_user_otp_qr_code())
    end
    
    post '/api/delete_otp_token' do
        require_user!
        delete_session_user_otp_token()
        respond(:ok => 'yeah')
    end
    
    def session_user_otp_qr_code()
        require_user!
        otp_token = @session_user[:otp_token]
        return nil if otp_token.nil?
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
        unless @@user_info.include?(data[:email]) && @@user_info[data[:email]][:can_log_in]
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]))
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: {email}})
            DETACH DELETE l;
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :valid_to => valid_to.to_i)
            MATCH (n:User {email: {email}})
            CREATE (l:LoginCode {tag: {tag}, otp: true, valid_to: {valid_to}})-[:BELONGS_TO]->(n)
            RETURN n;
        END_OF_QUERY
        respond(:tag => tag)
    end
end
