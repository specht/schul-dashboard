class Main < Sinatra::Base

    def matrixRequest(path, data = {}, access_token = nil)
        response = nil
        3.times do
            c = Curl.post("https://#{MATRIX_DOMAIN}#{path}", data.to_json) do |http|
                http.headers['Authorization'] = "Bearer #{access_token}" if access_token
            end
            begin
                response = JSON.parse(c.body_str)
            rescue JSON::ParserError => e
                STDERR.puts c.body_str
                raise e
            end
            if response['retry_after_ms']
                sleep response['retry_after_ms'].to_f / 1000.0
            else
                break
            end
        end
        response
    end

    def matrixLogin(email, &block)
        # login
        response = matrixRequest("/_matrix/client/r0/login", {
            :type => 'm.login.password',
            :user => @@user_info[email][:matrix_login],
            :password => MATRIX_ALL_ACCESS_PASSWORD_BE_CAREFUL
        })
        access_token = response['access_token'] || ''
        assert(!access_token.empty?)

        yield(access_token)

        matrixRequest("/_matrix/client/r0/logout", {}, access_token)
    end

    get '/api/matrix_test' do
        require_admin!
        matrixLogin(WEBSITE_MAINTAINER_EMAIL) do |access_token|
            @@user_info.each_pair do |email, info|
                next unless info[:teacher]
                STDERR.puts info[:matrix_login]
                response = matrixRequest("/_matrix/client/r0/rooms/#{CGI.escape('!wfEDbfgjOMXXvsYmHq:nhcham.org')}/invite", {
                    :user_id => info[:matrix_login]
                }, access_token)
                STDERR.puts response.to_yaml
                matrixLogin(info[:email]) do |sub_token|
                    response = matrixRequest("/_matrix/client/r0/rooms/#{CGI.escape('!wfEDbfgjOMXXvsYmHq:nhcham.org')}/join", {}, sub_token)
                    STDERR.puts response.to_yaml
                end
            end
        end
    end

    def generate_matrix_corporal_policy
        result = {
            :schemaVersion => 1,
            :flags => {
                :allowCustomUserDisplayNames => false,
                :allowCustomUserAvatars => false,
                :allowCustomPassthroughUserPasswords => false,
                :allowUnauthenticatedPasswordResets => false,
                :forbidRoomCreation => false,
                :forbidEncryptedRoomCreation => false,
                :forbidUnencryptedRoomCreation => false
            },
            :managedCommunityIds => ["+alle:#{MATRIX_DOMAIN_SHORT}"],
            :managedRoomIds => [],
            :users => [],
            :hooks => [],
        }
        matrix_handle_to_email = {}
        @@user_info.each_pair do |email, info|
            handle = info[:matrix_login]
            matrix_handle_to_email[handle] = email
            result[:users] << {
                :id => handle,
                :active => true,
                :authType => 'rest',
                :authCredential => "#{WEB_ROOT}/api/confirm_chat_login",
                :displayName => info[:display_name],
                :avatarUri => "#{NEXTCLOUD_URL}/index.php/avatar/#{info[:nc_login]}/256",
                :joinedCommunityIds => [""],
                :joinedRoomIds => [],
            }
        end
        result[:hooks] << {
            :id => 'dashboard-hook',
            :eventType => 'beforeAuthenticatedRequest',
            :matchRules => [
                {:type => 'method', :regex => 'POST'},
                {:type => 'route', :regex => '^/_matrix/client/r0/createRoom'}
            ],
            :action => 'consult.RESTServiceURL',
            :RESTServiceURL => "#{WEB_ROOT}/api/matrix_hook",
            :RESTServiceRequestHeaders => {
                "Authorization" => 'Bearer 123456',
            },
            :RESTServiceRequestTimeoutMilliseconds => 10000,
            :RESTServiceRetryAttempts => 1,
            :RESTServiceRetryWaitTimeMilliseconds => 5000
        }
        result
    end

    get '/api/generate_matrix_corporal_policy' do
        require_admin!
        respond(generate_matrix_corporal_policy)
    end

    post '/api/matrix_hook' do
        body_str = request.body.read(2048).to_s
        STDERR.puts body_str
        respond(:action => 'pass.unmodified')
    end
end