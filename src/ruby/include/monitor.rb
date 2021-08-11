class Main < Sinatra::Base

    MONITOR_MESSAGE_PATH = '/vplan/message.txt'

    def get_monitor_messages()
        text = ''
        if File.exists?(MONITOR_MESSAGE_PATH)
            text = File.read(MONITOR_MESSAGE_PATH)
        end
        messages = []
        text.split("\n").each do |line|
            line.strip!
            messages << line unless line.empty?
        end
        messages
    end

    def self.force_reload_monitors
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'force_reload'}.to_json)
        end
    end

    post '/api/force_reload_monitors' do
        require_user_who_can_manage_monitors!
        self.class.force_reload_monitors()
    end

    def update_monitors_message
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'update_monitor_messages', :messages => get_monitor_messages}.to_json)
        end
    end

    def update_monitors_vplan
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            monitor_data = {:klassen => {}, :timestamp => ''}
            monitor_data_path = '/vplan/monitor/monitor.json'
            if File.exists?(monitor_data_path)
                monitor_data = JSON.parse(File.read(monitor_data_path))
            end
            ws.send({:command => 'update_vplan', :data => monitor_data}.to_json)
        end
    end

    def update_monitors
        update_monitors_message()
        update_monitors_vplan()
    end

    post '/api/update_monitor_messages' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:text],
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        File.open(MONITOR_MESSAGE_PATH, 'w') { |f| f.puts data[:text] }
        update_monitors_message()
    end

    post '/api/get_monitor_messages_raw' do
        require_user_who_can_manage_monitors!
        text = ''
        if File.exists?(MONITOR_MESSAGE_PATH)
            text = File.read(MONITOR_MESSAGE_PATH)
        end
        respond(:text => text)
    end

    get '/api/update_monitors' do
        update_monitors()
    end

    get '/ws_monitor' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
        
            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:monitor] ||= {}
                @@ws_clients[:monitor][client_id] = {:ws => ws}
                STDERR.puts "Got #{@@ws_clients[:monitor].size} connected monitors."
                ws.send({command: 'update_time', time: Time.now.to_i }.to_json)
                update_monitors()
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
                @@ws_clients[:monitor] ||= {}
                @@ws_clients[:monitor].delete(client_id)
                STDERR.puts "Got #{@@ws_clients[:monitor].size} connected monitors."
            end
        
            ws.rack_response
        end
    end
end