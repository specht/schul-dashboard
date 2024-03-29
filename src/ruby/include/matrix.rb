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

    post '/api/matrix_hook' do
        body_str = request.body.read(2048).to_s
        assert(request.env['HTTP_AUTHORIZATION'] == "Bearer #{MATRIX_CORPORAL_CALLBACK_BEARER_TOKEN}")
        request = JSON.parse(body_str)
        hook_id = request['meta']['hookId']
        assert(!hook_id.nil?)
        matrix_login = request['meta']['authenticatedMatrixUserId']
        assert(@@email_for_matrix_login.include?(matrix_login))
        email = @@email_for_matrix_login[matrix_login]
        if hook_id == 'dashboard-hook-before-create-room'
            payload = JSON.parse(request['request']['payload'])
            prevent_this = false
            unless @@user_info[email][:teacher]
                prevent_this = true
                # user is SuS
                if ['private_chat', 'trusted_private_chat'].include?(payload['preset'])
                    # private chat: if it's a SuS, only agree if single teacher invited
                    if (payload['invite'] || []).size == 1
                        other_matrix_login = payload['invite'].first
                        assert(@@email_for_matrix_login.include?(other_matrix_login))
                        other_email = @@email_for_matrix_login[other_matrix_login]
                        if @@user_info[other_email][:teacher]
                            # invited user is a teacher
                            # now we have to check whether this teacher has allowed 
                            # direct DMs from SuS
                            allowed = neo4j_query_expect_one(<<~END_OF_QUERY, :email => other_email)['u.sus_may_contact_me'] || false
                                MATCH (u:User {email: $email})
                                RETURN u.sus_may_contact_me;
                            END_OF_QUERY
                            if allowed
                                prevent_this = false
                            end
                        end
                        if (!DEMO_ACCOUNT_EMAIL.nil?) && email == DEMO_ACCOUNT_EMAIL
                            prevent_this = (other_email != WEBSITE_MAINTAINER_EMAIL)
                        end
                    end
                end
            end
            if prevent_this
                respond(:action => 'reject',
                    :responseStatusCode => 403,
                    :rejectionErrorCode => 'M_FORBIDDEN',
                    :rejectionErrorMessage => 'noPermission')
                return
            end
        elsif hook_id == 'dashboard-hook-before-leave-room'
            if @@user_info[email][:teacher]
                room_url = request['request']['URI'].sub('/_matrix/client/r0/rooms/', '').split('/').first
                matrix_login(MATRIX_ADMIN_USER, MATRIX_ADMIN_PASSWORD) do |access_token|
                    result = matrix_get("/_synapse/admin/v1/rooms/#{room_url}/members", access_token)
                    members = result['members'] || []
                    members.delete(matrix_login)
                    if members.size > 1
                        # there's still more than one person in the room after we'd have left
                        # check if there's at least one teacher left in the room
                        unless members.any? { |x| @@user_info[@@email_for_matrix_login[x]][:teacher]}
                            # only SuS left, prevent teacher from leaving the room
                            respond(:action => 'reject',
                                :responseStatusCode => 403,
                                :rejectionErrorCode => 'M_FORBIDDEN',
                                :rejectionErrorMessage => 'cantLeaveSuSAlone')
                            return
                        end
                    end
                end
            end
        elsif hook_id == 'dashboard-hook-before-enable-encryption'
            # cannot enable encryption unless user is a teacher
            unless @@user_info[email][:teacher]
                respond(:action => 'reject',
                    :responseStatusCode => 403,
                    :rejectionErrorCode => 'M_FORBIDDEN',
                    :rejectionErrorMessage => 'noPermission')
                return
            end
            room_url = request['request']['URI'].sub('/_matrix/client/r0/rooms/', '').split('/').first
            matrix_login(MATRIX_ADMIN_USER, MATRIX_ADMIN_PASSWORD) do |access_token|
                state = matrix_get("/_synapse/admin/v1/rooms/#{room_url}/state", access_token)
                member_entries = state['state'].select do |entry|
                    entry['type'] == 'm.room.member'
                end
                STDERR.puts member_entries.to_yaml
                if member_entries.size == 2
                    if member_entries.all? { |entry| @@user_info[@@email_for_matrix_login[entry['state_key']]][:teacher] }
                        if member_entries.any? { |entry| (entry['content'] || {})['is_direct'] == true }
                            respond(:action => 'pass.unmodified')
                            return
                        end
                    end
                end
                respond(:action => 'reject',
                    :responseStatusCode => 403,
                    :rejectionErrorCode => 'M_FORBIDDEN',
                    :rejectionErrorMessage => 'canOnlyEnableE2EEInTeacherDirectChats')
                return
            end
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
            MATCH (l:LoginCode {tag: $tag, performed: true})-[:BELONGS_TO]->(u:User)
            SET l.tries = COALESCE(l.tries, 0) + 1
            RETURN l, u;
        END_OF_QUERY
        user = result['u']
        # make sure we've got the right user
        assert(@@user_info[user[:email]][:matrix_login] == matrix_id)
        login_code = result['l']
        assert(code == login_code[:code])
        assert(Time.at(login_code[:valid_to]) >= Time.now)
        neo4j_query(<<~END_OF_QUERY, :email => user[:email], :access_token => access_token)
            MATCH (u:User {email: $email})
            CREATE (:MatrixAccessToken {access_token: $access_token})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :tag => tag)
            MATCH (l:LoginCode {tag: $tag})
            DETACH DELETE l;
        END_OF_QUERY
        respond(:teacher => @@user_info[user[:email]][:teacher])
    end

    post '/api/fetch_matrix_groups' do
        data = parse_request_data(:required_keys => [:access_token])
        email = neo4j_query_expect_one(<<~END_OF_QUERY, :access_token => data[:access_token])['u.email']
            MATCH (:MatrixAccessToken {access_token: $access_token})-[:BELONGS_TO]->(u:User)
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
