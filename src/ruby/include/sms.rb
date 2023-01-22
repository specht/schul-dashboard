class Main < Sinatra::Base

    def user_is_eligible_for_sms?
        return false unless user_logged_in?
        return true if SMS_AUTH_UNLOCKED_FOR.nil?
        return SMS_AUTH_UNLOCKED_FOR.include?(@session_user[:email])
    end

    def session_user_telephone_number
        require_user!
        telephone_number = @session_user[:telephone_number]
        return nil if telephone_number.nil?
        return telephone_number
    end

    post '/api/save_telephone_number' do
        data = parse_request_data(:required_keys => [:telephone_number])
        number = data[:telephone_number]
    end

    get '/ws_sms' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)

            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:sms] ||= {}
                @@ws_clients[:sms][client_id] = {:ws => ws, :authenticated => false}
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
                STDERR.puts "Got #{@@ws_clients[:sms].size} connected SMS gateways."
            end

            ws.rack_response
        end
    end
end
