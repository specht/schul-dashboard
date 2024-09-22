class Main < Sinatra::Base
    def send_wifi_request_mail(request_details)
        deliver_mail do
            to Array(@@users_for_role[:can_manage_project_wifi_access]).flatten
            bcc SMTP_FROM
            from SMTP_FROM

            subject "New WIFI Access Request"

            StringIO.open do |io|
                io.puts "<p>Hallp!</p>"
                io.puts "<p>Eine neue Projekt-WLAN Anfrage wurde eingereicht:</p>"
                io.puts "<p>Name: #{request_details[:name]}</p>"
                io.puts "<p>Number of Devices: #{request_details[:num_devices]}</p>"
                io.puts "<p>Number of Days: #{request_details[:num_days]}</p>"
                io.puts "<p>Start Date/Time: #{request_details[:start_datetime]}</p>"
                io.puts "<p><a href='#{WEBSITE_HOST}/school_wifi'>Request genehmigen</a></p>"
                io.puts "<p>Viel Spaß beim Singen!<br>Peter-J. Germelmann</p>"
                io.string
            end
        end
    end

    post '/api/request_wifi_access' do
        require_user_with_role!(:can_open_project_wifi)

        data = parse_request_data(:required_keys => [:name, :start_datetime, :num_days, :num_devices])
        token = RandomTag.generate(24)
        neo4j_query(<<~END_OF_QUERY, :token => token, :email => @session_user[:email], :name => data[:name], :num_devices => data[:num_devices], :num_days => data[:num_days], :start_datetime => data[:start_datetime])
            MATCH (u:User {email: $email})
            CREATE (n:WifiRequest {token: $token, name: $name, num_devices: $num_devices, num_days: $num_days, start_datetime: $start_datetime, status: 'waiting'})
            CREATE (n)-[:BELONGS_TO]->(u)
            RETURN n;
        END_OF_QUERY

        send_wifi_request_mail(data)

        respond(:ok => true)
    end

    post '/api/get_wifis' do
        if user_with_role_logged_in?(:can_manage_project_wifi_access)
            requests = neo4j_query(<<~END_OF_QUERY).map { |x| {:request => x['n'], :email => x['u.email']} }
            MATCH (u:User)<-[:BELONGS_TO]-(n:WifiRequest)
            RETURN n, u.email;
            END_OF_QUERY
        else
            require_user_with_role!(:can_open_project_wifi)
            requests = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:request => x['n'], :email => x['u.email']} }
            MATCH (u:User {email: $email})<-[:BELONGS_TO]-(n:WifiRequest)
            RETURN n, u.email;
            END_OF_QUERY
        end

        requests.map! do |x|
            x[:display_name] = @@user_info[x[:email]][:display_name]
            x[:nc_login] = @@user_info[x[:email]][:nc_login]
            x
        end

        respond(:requests => requests)
    end

    post '/api/accept_wifi_request' do
        require_user_with_role!(:can_manage_project_wifi_access)
        
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]

        neo4j_query(<<~END_OF_QUERY, token: token)
            MATCH (n:WifiRequest {token: $token})
            WITH n
            SET n.status = CASE n.status WHEN 'accepted' THEN 'waiting' ELSE 'accepted' END
            RETURN n;
        END_OF_QUERY

        respond(:success => true)
    end

    post '/api/decline_wifi_request' do
        require_user_with_role!(:can_manage_project_wifi_access)
        
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]

        neo4j_query(<<~END_OF_QUERY, token: token)
            MATCH (n:WifiRequest {token: $token})
            WITH n
            SET n.status = CASE n.status WHEN 'declined' THEN 'waiting' ELSE 'declined' END
            RETURN n;
        END_OF_QUERY

        respond(:success => true)
    end
        
end