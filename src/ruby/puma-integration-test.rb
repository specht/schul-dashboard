#!/usr/bin/env ruby

require 'eventmachine'
require 'faye/websocket'
require 'json'
require 'net/http'
require 'socket'
require 'timeout'

test_rackup = File.expand_path('puma-integration-test.ru', __dir__)
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
server.close

server_pid = Process.spawn(
    'bundle', 'exec', 'rackup', test_rackup,
    '--server', 'puma',
    '--env', 'production',
    '--host', '127.0.0.1',
    '--port', port.to_s,
    :pgroup => true,
    :out => '/tmp/puma-integration-test.log',
    :err => [:child, :out],
)

begin
    response = nil
    Timeout.timeout(15) do
        loop do
            begin
                response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/c/gt1z2sb3"))
                break
            rescue Errno::ECONNREFUSED, Errno::ECONNRESET
                sleep 0.05
            end
        end
    end

    raise "Unexpected HTTP status: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    result = JSON.parse(response.body)
    raise "Unexpected request path: #{result['path'].inspect}" unless result['path'] == '/c/gt1z2sb3'
    raise "Request path was not UTF-8: #{result['encoding']}" unless result['encoding'] == 'UTF-8'
    raise "Login tag was not UTF-8: #{result['tag_encoding']}" unless result['tag_encoding'] == 'UTF-8'
    unless result['tag_packstream_marker'] == 0x88
        raise "Login tag was not serialized as PackStream text: 0x#{result['tag_packstream_marker'].to_s(16)}"
    end

    websocket_result = nil
    websocket_error = nil
    EventMachine.run do
        websocket = Faye::WebSocket::Client.new("ws://127.0.0.1:#{port}/websocket")
        timer = EventMachine.add_timer(10) do
            websocket_error = 'WebSocket test timed out'
            websocket.close
            EventMachine.stop
        end
        websocket.on(:open) { websocket.send('dashboard-puma-test') }
        websocket.on(:message) do |event|
            websocket_result = event.data
            websocket.close
        end
        websocket.on(:error) { |event| websocket_error = event.message }
        websocket.on(:close) do
            EventMachine.cancel_timer(timer)
            EventMachine.stop
        end
    end

    raise websocket_error unless websocket_error.nil?
    raise "Unexpected WebSocket echo: #{websocket_result.inspect}" unless websocket_result == 'dashboard-puma-test'

    puts "request.path=#{result['path'].inspect}"
    puts "request.path.encoding=#{result['encoding']}"
    puts "login_tag.packstream_marker=0x#{result['tag_packstream_marker'].to_s(16)} (text)"
    puts 'websocket_echo=ok'
ensure
    begin
        Process.kill('TERM', -server_pid)
    rescue Errno::ESRCH
    end
    begin
        Timeout.timeout(10) { Process.wait(server_pid) }
    rescue Errno::ECHILD
    rescue Timeout::Error
        Process.kill('KILL', -server_pid)
        Process.wait(server_pid)
    end
end
