class Main < Sinatra::Base

    MONITOR_MESSAGE_PATH = '/vplan/message.json'

    def get_monitor_messages()
        data = {}
        if File.exist?(MONITOR_MESSAGE_PATH)
            data = JSON.parse(File.read(MONITOR_MESSAGE_PATH))
        end
        result = {
            :messages => [],
            :images => []
        }
        [:messages, :images].each do |key|
            (data[key.to_s] || '').split("\n").each do |line|
                line.strip!
                result[key] << line unless line.empty?
            end
        end
        result
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
            ws.send({:command => 'update_monitor_messages', :data => get_monitor_messages}.to_json)
        end
    end

    def update_monitors_vplan
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            monitor_data = {:klassen => {}, :timestamp => ''}
            monitor_data_path = '/vplan/monitor/monitor.json'
            if File.exist?(monitor_data_path)
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
        data = parse_request_data(:required_keys => [:messages, :images],
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        File.open(MONITOR_MESSAGE_PATH, 'w') do |f|
            d = {:messages => data[:messages], :images => data[:images]}
            f.print d.to_json
        end
        update_monitors_message()
    end

    post '/api/get_monitor_messages_raw' do
        require_user_who_can_manage_monitors!
        data = {'messages': '', 'images': ''}
        if File.exist?(MONITOR_MESSAGE_PATH)
            data = JSON.parse(File.read(MONITOR_MESSAGE_PATH))
        end
        respond(:data => data)
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

    def get_monitor_zeugniskonferenzen
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (m:MonitorZeugniskonferenz)
            RETURN m.key, COALESCE(m.value, FALSE) AS value;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row['m.key']] = row['value']
        end
        result['flur'] ||= false
        result['lz'] ||= false
        result['sek'] ||= false
        result
    end

    post '/api/get_monitor_zeugniskonferenzen' do
        respond(:result => get_monitor_zeugniskonferenzen())
    end

    post '/api/toggle_monitor_zeugniskonferenzen' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:key])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:key => data[:key]})
            MERGE (m:MonitorZeugniskonferenz {key: $key})
            SET m.value = NOT COALESCE(m.value, FALSE)
            RETURN COALESCE(m.value, FALSE) AS result;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond(:result => result['result'])
    end

    def running_zeugniskonferenzen
        sha1_and_t0_list = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i}).map { |x| [x['m.sha1'], x['m.t0']] }
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            RETURN m.sha1, m.t0;
        END_OF_QUERY
        sha1_list = Set.new(sha1_and_t0_list.map { |x| x[0] })
        t0_for_sha1 = {}
        sha1_and_t0_list.each do |entry|
            t0_for_sha1[entry[0]] = entry[1]
        end
        result = {}
        today = Date.today.strftime('%Y-%m-%d')
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            sha1 = Digest::SHA1.hexdigest([today, entry].to_json)[0, 16]
            STDERR.puts "#{sha1} #{entry.to_json}"
            if sha1_list.include?(sha1)
                result[entry[0]] = t0_for_sha1[sha1]
            end
        end
        result
    end

    def finished_zeugniskonferenzen
        sha1_list = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i}).map { |x| x['m.sha1'] }
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NOT NULL
            RETURN m.sha1;
        END_OF_QUERY
        sha1_list = Set.new(sha1_list)
        result = []
        today = Date.today.strftime('%Y-%m-%d')
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            sha1 = Digest::SHA1.hexdigest([today, entry].to_json)[0, 16]
            if sha1_list.include?(sha1)
                result << entry[0]
            end
        end
        result
    end

    post '/api/start_zeugniskonferenz' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:start_time])
        start_time = data[:start_time]
        today = Date.today.strftime('%Y-%m-%d')
        found_entry = nil
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            if entry[0] == start_time
                found_entry = entry
                break
            end
        end
        result = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i})
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            SET m.t1 = $t1;
        END_OF_QUERY
        if found_entry
            sha1 = Digest::SHA1.hexdigest([today, found_entry].to_json)[0, 16]
            STDERR.puts sha1
            result = neo4j_query_expect_one(<<~END_OF_QUERY, {:sha1 => sha1, :t0 => Time.now.to_i})
                MERGE (m:MonitorZeugniskonferenzState {sha1: $sha1})
                SET m.t0 = $t0
                REMOVE m.t1
                RETURN m;
            END_OF_QUERY
            self.class.force_reload_monitors()
        end
        respond()
    end

    post '/api/stop_zeugniskonferenz' do
        require_user_who_can_manage_monitors!
        today = Date.today.strftime('%Y-%m-%d')

        result = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i})
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            SET m.t1 = $t1;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond()
    end
end
