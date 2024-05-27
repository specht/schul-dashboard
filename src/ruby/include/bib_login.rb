class Main < Sinatra::Base

    get '/ws_bib_login' do
        require_device!
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)

            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:bib_login] ||= {}
                @@ws_clients[:bib_login][client_id] = {:ws => ws, :device_token => @session_device_token}
                STDERR.puts "Got #{@@ws_clients[:bib_login].size} connected bib clients."
                # ws.send({command: 'update_time', time: Time.now.to_i }.to_json)
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                data = nil
                begin
                    data = JSON.parse(msg.data)
                rescue
                end
                if data
                    STDERR.puts data.to_yaml
                end
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:bib_login] ||= {}
                @@ws_clients[:bib_login].delete(client_id)
                STDERR.puts "Got #{@@ws_clients[:bib_login].size} connected bib clients."
            end

            ws.rack_response
        end
    end

    post '/api/login_for_device_do_login' do
        require_device!
        begin
            email = neo4j_query_expect_one(<<~END_OF_QUERY, {:device_token => @session_device_token, :now => Time.now.to_i})['email']
                MATCH (dt:DeviceToken {token: $device_token})-[r:DEVICE_LOGIN_AS]->(u:User)
                WHERE r.expires > $now
                RETURN u.email AS email;
            END_OF_QUERY
            neo4j_query(<<~END_OF_QUERY, {:device_token => @session_device_token})
                MATCH (dt:DeviceToken {token: $device_token})-[r:DEVICE_LOGIN_AS]->(:User)
                DELETE r;
            END_OF_QUERY
            assert(CAN_MANAGE_BIB.include?(email))
            session_id = create_session(email, 365 * 24)
            purge_missing_sessions(session_id, true)
            neo4j_query(<<~END_OF_QUERY, {:sid => session_id, :device_token => @session_device_token})
                MATCH (s:Session {sid: $sid})
                SET s.tied_to_device_token = $device_token;
            END_OF_QUERY
        rescue
            redirect "#{WEB_ROOT}/", 302
        end
        respond(:yay => 'sure')
    end

    get '/api/login_for_device/:token' do
        unless user_logged_in?
            redirect "#{WEB_ROOT}/", 302
            return
        end
        require_user!
        login_token = params[:token]
        # fetch device token for login token
        begin
            device_token = neo4j_query_expect_one(<<~END_OF_QUERY, {:login_token => login_token})['device_token']
                MATCH (lt:DeviceLoginToken {token: $login_token})-[:FOR]->(dt:DeviceToken)
                RETURN dt.token AS device_token;
            END_OF_QUERY
            @@ws_clients[:bib_login].values.each do |info|
                if info[:device_token] == device_token
                    neo4j_query(<<~END_OF_QUERY, {:device_token => device_token})
                        MATCH (dt:DeviceToken {token: $device_token})-[r:DEVICE_LOGIN_AS]->(:User)
                        DELETE r;
                    END_OF_QUERY
                    neo4j_query_expect_one(<<~END_OF_QUERY, {:device_token => device_token, :email => @session_user[:email], :expires => Time.now.to_i + 60})
                        MATCH (dt:DeviceToken {token: $device_token})
                        MATCH (u:User {email: $email})
                        CREATE (dt)-[r:DEVICE_LOGIN_AS {expires: $expires}]->(u)
                        RETURN u;
                    END_OF_QUERY
                    info[:ws].send({command: 'do_login'}.to_json)
                    break
                end
            end
        # rescue
        end
        # respond(:alright => 'yeah')
        redirect "#{WEB_ROOT}/", 302
    end
end
