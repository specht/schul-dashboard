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

    post '/api/force_reload_monitors' do
        require_user_who_can_manage_news!
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'force_reload'}.to_json)
        end
    end

    def update_monitors
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'update_monitor_messages', :messages => get_monitor_messages}.to_json)
        end
    end

    post '/api/update_monitor_messages' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:text],
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        File.open(MONITOR_MESSAGE_PATH, 'w') { |f| f.puts data[:text] }
        update_monitors()
    end

    post '/api/get_monitor_messages_raw' do
        require_user_who_can_manage_news!
        text = ''
        if File.exists?(MONITOR_MESSAGE_PATH)
            text = File.read(MONITOR_MESSAGE_PATH)
        end
        respond(:text => text)
    end
end