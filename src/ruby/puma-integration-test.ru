require 'faye/websocket'
require 'json'
require 'neo4j/driver'
require 'rack'

Faye::WebSocket.load_adapter('puma')

app = lambda do |env|
    request = Rack::Request.new(env)

    if request.path == '/websocket' && Faye::WebSocket.websocket?(env)
        websocket = Faye::WebSocket.new(env)
        websocket.on(:message) { |event| websocket.send(event.data) }
        websocket.rack_response
    elsif request.path == '/c/gt1z2sb3'
        tag = request.path.split('/').last
        packed_tag = Neo4j::Driver::PackStream::Packer.new(nil).pack(tag).bytes
        body = JSON.generate({
            :path => request.path,
            :encoding => request.path.encoding.name,
            :tag_encoding => tag.encoding.name,
            :tag_packstream_marker => packed_tag.getbyte(0),
        })
        [200, {'content-type' => 'application/json'}, [body]]
    else
        [404, {'content-type' => 'text/plain'}, ["Not found\n"]]
    end
end

run app
