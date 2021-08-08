class Main < Sinatra::Base

    post '/api/force_reload_monitors' do
        require_user_who_can_manage_news!
        ((@@ws_clients || {})[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'force_reload'}.to_json)
        end
    end

    def update_monitors
        ((@@ws_clients || {})[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send('UPDATE INCOMING!')
        end
    end
end