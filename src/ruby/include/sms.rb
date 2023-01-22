class Main < Sinatra::Base

    def user_is_eligible_for_sms?
        return false unless user_logged_in?
        return true if SMS_AUTH_UNLOCKED_FOR.nil?
        return SMS_AUTH_UNLOCKED_FOR.include?(@session_user[:email])
    end

    def self.sms_gateway_ready?
        (@@ws_clients[:authenticated_sms] || {}).values.size > 0
    end

    def session_user_telephone_number
        require_user!
        telephone_number = @session_user[:telephone_number]
        return nil if telephone_number.nil?
        return telephone_number
    end

    def send_sms(telephone_number, message)
        data = {:telephone_number => telephone_number, :message => message}
        @@ws_clients[:authenticated_sms].values.first[:ws].send(data.to_json)
    end

    post '/api/save_telephone_number' do
        require_user!
        data = parse_request_data(:required_keys => [:telephone_number])
        number = TelephoneNumber.parse(data[:telephone_number], :de)
        raise 'oops' unless number.valid?
        number = number.e164_number()
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        send_sms(number, "Dein Bestätigungscode zur Aktivierung der SMS-Anmeldung lautet #{random_code}.")
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :telephone_number => number, :tag => tag, :code => random_code, :valid_to => valid_to.to_i})
            MATCH (u:User {email: $email})
            CREATE (l:PhoneNumberConfirmation {tag: $tag, code: $code, valid_to: $valid_to, telephone_number: $telephone_number})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        respond(:telephone_number => number, :next => 'confirm', :tag => tag)
    end

    post '/api/confirm_telephone_number' do
        data = parse_request_data(:required_keys => [:tag, :code])
        data[:code] = data[:code].gsub(/[^0-9]/, '')
        begin
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:PhoneNumberConfirmation {tag: $tag})-[:BELONGS_TO]->(u:User)
                SET l.tries = COALESCE(l.tries, 0) + 1
                RETURN l, u;
            END_OF_QUERY
        rescue
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        user = result['u']
        sms_code = result['l']
        if sms_code[:tries] > MAX_LOGIN_TRIES
            neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:PhoneNumberConfirmation {tag: $tag})
                DETACH DELETE l;
            END_OF_QUERY
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        assert(sms_code[:tries] <= MAX_LOGIN_TRIES)
        assert_with_delay(data[:code] == sms_code[:code], "Wrong SMS confirmation code entered for #{user[:email]}: #{data[:code]}", true)
        if Time.at(sms_code[:valid_to]) < Time.now
            respond({:error => 'code_expired'})
        end
        assert(Time.at(sms_code[:valid_to]) >= Time.now, 'code expired', true)

        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :telephone_number => sms_code[:telephone_number])
            MATCH (u:User {email: $email})
            SET u.telephone_number = $telephone_number;
        END_OF_QUERY
        send_sms(sms_code[:telephone_number], "Die Anmeldung per SMS ist nun aktiviert.")

        neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:PhoneNumberConfirmation {tag: $tag})
            DETACH DELETE l;
        END_OF_QUERY
        respond(:ok => 'yeah', :telephone_number => sms_code[:telephone_number])
    end

    post '/api/delete_telephone_number' do
        require_user!
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            REMOVE u.telephone_number;
        END_OF_QUERY
        respond(:yay => 'sure')
    end

    get '/ws_sms' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)

            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:sms] ||= {}
                @@ws_clients[:sms][client_id] = {:ws => ws, :authenticated => false}
                @@ws_clients[:authenticated_sms] ||= {}
                STDERR.puts "Got #{@@ws_clients[:sms].size} connected SMS gateways."
                ws.send({command: 'hello', time: Time.now.to_i }.to_json)
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                data = nil
                begin
                    data = JSON.parse(msg.data)
                rescue
                end
                if data
                    if data['hello'] == SMS_GATEWAY_SECRET
                        @@ws_clients[:sms][client_id][:authenticated] = true
                        @@ws_clients[:authenticated_sms][client_id] = {:ws => ws, :authenticated => true}
                    else
                        ws.close()
                    end
                    STDERR.puts data.to_yaml
                end
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:sms] ||= {}
                @@ws_clients[:sms].delete(client_id)
                @@ws_clients[:authenticated_sms] ||= {}
                @@ws_clients[:authenticated_sms].delete(client_id)
                STDERR.puts "Got #{@@ws_clients[:sms].size} connected SMS gateways."
            end

            ws.rack_response
        end
    end
end
