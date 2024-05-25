class String
    def obfuscate(key)
        k = Digest::SHA256.digest(key).unpack('C*')
        m = self.bytes
        (0...m.size).each { |i| m[i] ^= k[i % 32] }
        Base64::strict_encode64(m.pack('C*'))
    end

    def deobfuscate(key)
        k = Digest::SHA256.digest(key).bytes
        m = Base64::strict_decode64(self).unpack('C*')
        (0...m.size).each { |i| m[i] ^= k[i % 32] }
        m.pack('C*')
    end
end

class Main < Sinatra::Base

    def user_is_eligible_for_sms?
        return false unless user_logged_in?
        return teacher_logged_in?
    end

    def self.sms_gateway_ready?
        (@@ws_clients[:authenticated_sms] || {}).values.size > 0
    end

    def session_user_telephone_number
        require_user!
        telephone_number = @session_user[:telephone_number]
        return nil if telephone_number.nil?
        return '(redacted)'
    end

    def session_user_telephone_number_good_for_tresor()
        require_user!
        telephone_number = @session_user[:telephone_number]
        return false if telephone_number.nil?
        return @session_user[:telephone_number_changed] < DateTime.now.strftime('%Y-%m-%d')
    end

    def send_sms(telephone_number, message)
        data = {:telephone_number => telephone_number, :message => message}
        debug "Sending SMS: #{data.to_json}"
        @@ws_clients[:authenticated_sms].values.first[:ws].send(data.to_json)
        ds = Date.today.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, {:ds => ds})
            MERGE (d:SmsDay {ds: $ds})
            SET d.count = COALESCE(d.count, 0) + 1;
        END_OF_QUERY
    end

    post '/api/save_telephone_number' do
        require_user!
        data = parse_request_data(:required_keys => [:telephone_number])
        telephone_number = data[:telephone_number].strip
        if telephone_number[0, 2] == '00'
            telephone_number = '+' + telephone_number[2, telephone_number.size - 2]
        end
        number = TelephoneNumber.parse(telephone_number, :de)
        raise 'oopsie daisy' unless number.valid?
        number = number.e164_number()
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        send_sms(number, "Dein Bestaetigungscode zur Aktivierung der SMS-Anmeldung lautet #{random_code}.")
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :telephone_number => number.obfuscate(SMS_PHONE_NUMBER_PASSPHRASE), :tag => tag, :code => random_code, :valid_to => valid_to.to_i})
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

        today = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :telephone_number => sms_code[:telephone_number], :today => today)
            MATCH (u:User {email: $email})
            SET u.telephone_number = $telephone_number
            SET u.telephone_number_changed = $today;
        END_OF_QUERY
        send_sms(sms_code[:telephone_number].deobfuscate(SMS_PHONE_NUMBER_PASSPHRASE), "Die Anmeldung per SMS ist nun aktiviert.")

        neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:PhoneNumberConfirmation {tag: $tag})
            DETACH DELETE l;
        END_OF_QUERY
        session_user = @session_user.dup
        deliver_mail do
            to session_user[:email]
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Dashboard: SMS-Anmeldung aktiviert"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Die SMS-Anmeldung wurde aktiviert.</p>"
                io.puts "<p>Falls Sie diese Aktivierung nicht selbst veranlasst haben, setzen Sie sich bitte dringend mit #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} unter der E-Mail-Adresse <a href='mailto:#{WEBSITE_MAINTAINER_EMAIL}'>#{WEBSITE_MAINTAINER_EMAIL}</a> in Verbindung.</p>"
                io.puts "<p>Die Aktivierung erfolgte am #{DateTime.now.strftime('%d.%m.%Y')} um #{DateTime.now.strftime('%H:%M')} Uhr (Gerät: #{session_user[:user_agent]}, IP: #{session_user[:ip]}).</p>"
                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                io.string
            end
        end
        respond(:ok => 'yeah', :telephone_number => sms_code[:telephone_number].deobfuscate(SMS_PHONE_NUMBER_PASSPHRASE))
    end

    post '/api/delete_telephone_number' do
        require_user!
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            REMOVE u.preferred_login_method
            REMOVE u.telephone_number_changed
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
