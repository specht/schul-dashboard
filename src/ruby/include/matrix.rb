class Main < Sinatra::Base

    def matrix_request(method, path, data = {}, access_token = nil)
        assert([:get, :post].include?(method))
        response = nil
        success = false
        methods = {:get => Curl.method(:get),
                   :post => Curl.method(:post)}
        3.times do
            c = methods[method].call("https://#{MATRIX_DOMAIN}#{path}", data.nil? ? nil : data.to_json) do |http|
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
                success = true
                break
            end
        end
        unless success
            raise "unable to complete matrix_request: #{path} / #{data.to_json}"
        end
        response
    end

    def matrix_get(path, access_token = nil)
        matrix_request(:get, path, nil, access_token)
    end

    def matrix_post(path, data = {}, access_token = nil)
        matrix_request(:post, path, data, access_token)
    end

    def matrix_login(user, password, &block)
        # login
        response = matrix_post("/_matrix/client/r0/login", {
            :type => 'm.login.password',
            :user => user,
            :password => password
        })
        access_token = response['access_token'] || ''
        assert(!access_token.empty?)

        yield(access_token)

        matrix_post("/_matrix/client/r0/logout", {}, access_token)
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
            :managedCommunityIds => [],
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
                :displayName => info[:teacher] ? info[:display_last_name] : info[:display_name],
                :avatarUri => "#{NEXTCLOUD_URL}/index.php/avatar/#{info[:nc_login]}/512",
                :joinedCommunityIds => [],
                :joinedRoomIds => [],
            }
        end
        result[:hooks] << {
            :id => 'dashboard-hook-before-create-room',
            :eventType => 'beforeAuthenticatedRequest',
            :matchRules => [
                {:type => 'method', :regex => 'POST'},
                {:type => 'route', :regex => '^/_matrix/client/r0/createRoom'}
            ],
            :action => 'consult.RESTServiceURL',
            :RESTServiceURL => "#{WEB_ROOT}/api/matrix_hook",
            :RESTServiceRequestHeaders => {
                "Authorization" => "Bearer #{MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN}",
            },
            :RESTServiceRequestTimeoutMilliseconds => 10000,
            :RESTServiceRetryAttempts => 1,
            :RESTServiceRetryWaitTimeMilliseconds => 5000
        }
        result[:hooks] << {
            :id => 'dashboard-hook-before-leave-room',
            :eventType => 'beforeAuthenticatedRequest',
            :matchRules => [
                {:type => 'method', :regex => 'POST'},
                {:type => 'route', :regex => '^/_matrix/client/r0/rooms/([^/]+)/leave'}
            ],
            :action => 'consult.RESTServiceURL',
            :RESTServiceURL => "#{WEB_ROOT}/api/matrix_hook",
            :RESTServiceRequestHeaders => {
                "Authorization" => "Bearer #{MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN}",
            },
            :RESTServiceRequestTimeoutMilliseconds => 10000,
            :RESTServiceRetryAttempts => 1,
            :RESTServiceRetryWaitTimeMilliseconds => 5000
        }
        result[:hooks] << {
            :id => 'dashboard-hook-before-enable-encryption',
            :eventType => 'beforeAuthenticatedRequest',
            :matchRules => [
                {:type => 'method', :regex => 'PUT'},
                {:type => 'route', :regex => '^/_matrix/client/r0/rooms/([^/]+)/state/m.room.encryption/'}
            ],
            :action => 'consult.RESTServiceURL',
            :RESTServiceURL => "#{WEB_ROOT}/api/matrix_hook",
            :RESTServiceRequestHeaders => {
                "Authorization" => "Bearer #{MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN}",
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
        assert(request.env['HTTP_AUTHORIZATION'] == "Bearer #{MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN}")
        request = JSON.parse(body_str)
        hook_id = request['meta']['hookId']
        assert(!hook_id.nil?)
        matrix_login = request['meta']['authenticatedMatrixUserId']
        assert(@@email_for_matrix_login.include?(matrix_login))
        email = @@email_for_matrix_login[matrix_login]
        if hook_id == 'dashboard-hook-before-create-room'
            payload = JSON.parse(request['request']['payload'])
            STDERR.puts '-' * 40
            STDERR.puts "HOOK ID #{hook_id}"
            STDERR.puts "FROM #{email}"
            STDERR.puts payload.to_yaml
            if !@@user_info[email][:teacher]
                # user is SuS
                prevent_this = true
                if ['private_chat', 'trusted_private_chat'].include?(payload['preset'])
                    # private chat: if it's a SuS, only agree if single teacher invited
                    if payload['invite'].size == 1
                        other_matrix_login = payload['invite'].first
                        assert(@@email_for_matrix_login.include?(other_matrix_login))
                        other_email = @@email_for_matrix_login[other_matrix_login]
                        if @@user_info[other_email][:teacher]
                            # invited user is a teacher
                            prevent_this = false
                        end
                        if (!DEMO_ACCOUNT_EMAIL.nil?) && email == DEMO_ACCOUNT_EMAIL
                            prevent_this = (other_email != WEBSITE_MAINTAINER_EMAIL)
                        end
                    end
                end
            end
            raise 'nope' if prevent_this
        elsif hook_id == 'dashboard-hook-before-leave-room'
            if @@user_info[email][:teacher]
                room_url = request['request']['URI'].sub('/_matrix/client/r0/rooms/', '').split('/').first
                matrix_login(MATRIX_ADMIN_USER, MATRIX_ADMIN_PASSWORD) do |access_token|
                    result = matrix_get("/_synapse/admin/v1/rooms/#{room_url}/members", access_token)
                    members = result['members'] || []
                    members.delete(matrix_login)
                    unless members.empty?
                        # there's still someone else in the room after we'd have left
                        # check if there's at least one teacher left in the room
                        unless members.any? { |x| @@user_info[@@email_for_matrix_login[x]][:teacher]}
                            # only SuS left, prevent teacher from leaving the room
                            raise 'nope'
                        end
                    end
                end
            end
        elsif hook_id == 'dashboard-hook-before-enable-encryption'
            # cannot enable encryption unless user is a teacher
            raise 'nope' unless @@user_info[email][:teacher]
            room_url = request['request']['URI'].sub('/_matrix/client/r0/rooms/', '').split('/').first
            matrix_login(MATRIX_ADMIN_USER, MATRIX_ADMIN_PASSWORD) do |access_token|
                STDERR.puts "ROOM DETAILS"
                result = matrix_get("/_synapse/admin/v1/rooms/#{room_url}", access_token)
                STDERR.puts result.to_yaml

                STDERR.puts "MEMBERS"
                result = matrix_get("/_synapse/admin/v1/rooms/#{room_url}/members", access_token)
                STDERR.puts result.to_yaml

                STDERR.puts "STATE"
                result = matrix_get("/_synapse/admin/v1/rooms/#{room_url}/state", access_token)
                STDERR.puts result.to_yaml
            end
            # raise 'nope'
            respond(:action => 'reject',
                :responseStatusCode => 403,
                :rejectionErrorCode => 'M_FORBIDDEN',
                :rejectionErrorMessage => 'Well, you know...')

            return
        end
        respond(:action => 'pass.unmodified')
    end

    options '/api/store_matrix_access_token' do
        response.headers['Access-Control-Allow-Origin'] = "https://chat.gymnasiumsteglitz.de"
        response.headers['Access-Control-Allow-Headers'] = "Content-Type, Access-Control-Allow-Origin"
    end
    
    post '/api/store_matrix_access_token' do
        response.headers['Access-Control-Allow-Origin'] = "https://chat.gymnasiumsteglitz.de"
        data = parse_request_data(:required_keys => [:matrix_id, :access_token, :code])
        matrix_id = data[:matrix_id]
        access_token = data[:access_token]
        chat_code = data[:code]
        tag = chat_code.split('/').first
        code = chat_code.split('/').last
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => tag)
            MATCH (l:LoginCode {tag: {tag}, performed: true})-[:BELONGS_TO]->(u:User)
            SET l.tries = COALESCE(l.tries, 0) + 1
            RETURN l, u;
        END_OF_QUERY
        user = result['u'].props
        # make sure we've got the right user
        assert(@@user_info[user[:email]][:matrix_login] == matrix_id)
        login_code = result['l'].props
        assert(code == login_code[:code])
        assert(Time.at(login_code[:valid_to]) >= Time.now)
        neo4j_query(<<~END_OF_QUERY, :email => user[:email], :access_token => access_token)
            MATCH (u:User {email: {email}})
            CREATE (:MatrixAccessToken {access_token: {access_token}})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :tag => tag)
            MATCH (l:LoginCode {tag: {tag}})
            DETACH DELETE l;
        END_OF_QUERY
        respond(:teacher => @@user_info[user[:email]][:teacher])
    end

    post '/api/fetch_matrix_groups' do
        data = parse_request_data(:required_keys => [:access_token])
        email = neo4j_query_expect_one(<<~END_OF_QUERY, :access_token => data[:access_token])['u.email']
            MATCH (:MatrixAccessToken {access_token: {access_token}})-[:BELONGS_TO]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        STDERR.puts "Fetching matrix groups for #{email}..."
        group_order = []
        groups = {}
        (@@klassen_for_shorthand[@@user_info[email][:shorthand]] || []).each do |klasse|
            group_name = "Klasse #{klasse}"
            group_order << group_name
            groups[group_name] = @@schueler_for_klasse[klasse].map do |email|
                @@user_info[email][:matrix_login]
            end
        end
        respond(:groups => groups, :group_order => group_order)
    end
end
