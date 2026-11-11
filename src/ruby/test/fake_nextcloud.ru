# A stand-in for Nextcloud in the test stack (env.test.rb, service
# "nextcloud"): answers the one OCS call the password page makes – setting a
# user's password – and records it, so the E2E tests can check which login got
# which password. Not for anything else; other requests get a 404.
#
#   PUT    /ocs/v2.php/cloud/users/<login>   key=password&value=…   (OCS, XML)
#   GET    /_requests                       recorded password changes (JSON)
#   POST   /_fail?login=<login>             refuse the next change for <login>
#
# Reachable from the host on 127.0.0.1:8127 (tests), from the stack as
# http://nextcloud.

require 'json'
require 'rack'

RECORDED = []
FAIL_NEXT = {}
LOCK = Mutex.new

def ocs(status, statuscode, message)
    body = <<~XML
        <?xml version="1.0"?>
        <ocs><meta><status>#{status}</status><statuscode>#{statuscode}</statuscode><message>#{message}</message></meta><data/></ocs>
    XML
    [200, {'content-type' => 'application/xml'}, [body]]
end

run lambda { |env|
    request = Rack::Request.new(env)
    if request.put? && request.path =~ %r{\A/ocs/v2\.php/cloud/users/([^/]+)\z}
        login = Rack::Utils.unescape_path($1)
        params = Rack::Utils.parse_query(request.body.read)
        auth = Rack::Auth::Basic::Request.new(env)
        LOCK.synchronize do
            if FAIL_NEXT.delete(login)
                next ocs('failure', 403, 'refused by the test')
            end
            RECORDED << {
                :login => login,
                :key => params['key'],
                :value => params['value'],
                :admin => auth.provided? ? auth.username : nil,
                :ocs_api_request => env['HTTP_OCS_APIREQUEST'],
            }
            ocs('ok', 200, 'OK')
        end
    elsif request.get? && request.path == '/_requests'
        [200, {'content-type' => 'application/json'}, [LOCK.synchronize { RECORDED.to_json }]]
    elsif request.post? && request.path == '/_fail'
        LOCK.synchronize { FAIL_NEXT[request.params['login'].to_s] = true }
        [200, {'content-type' => 'application/json'}, ['{"ok":true}']]
    else
        [404, {'content-type' => 'text/plain'}, ['not found']]
    end
}
