class Main < Sinatra::Base
    def external_users_for_session_user
        result = {:groups => [], :recipients => {}, :order => []}
        return result unless teacher_logged_in?
        # add pre-defined external users
        @@predefined_external_users[:groups].each do |x|
            result[:groups] << x
        end
        @@predefined_external_users[:recipients].each_pair do |k, v|
            result[:recipients][k] = v
        end
        
        # add external users from user's address book
        ext_users = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email]).map { |x| x['e'] }
            MATCH (u:User {email: $session_email})-[:ENTERED_EXT_USER]->(e:ExternalUser)
            RETURN e
            ORDER BY e.name
        END_OF_QUERY
        ext_users.each do |entry|
            result[:recipients][entry[:email]] = {:label => entry[:name]}
            result[:order] << entry[:email]
        end

        result
    end
    
    post '/api/add_external_users' do
        require_teacher!
        data = parse_request_data(:required_keys => [:text],
                                  :max_body_length => 1024 * 4,
                                  :max_string_length => 1024 * 4,
                                  :max_value_lengths => {:text => 1024 * 4})
        raw_addresses = Mail::AddressList.new(data[:text].gsub("\n", ','))
        raw_addresses.addresses.each do |a|  
            email = (a.address || '').strip
            display_name = (a.display_name || '').strip
            if email.size > 0 && display_name.size > 0
                neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :email => email, :name => display_name)
                    MATCH (u:User {email: $session_email})
                    MERGE (u)-[:ENTERED_EXT_USER]->(e:ExternalUser {email: $email, entered_by: $session_email})
                    SET e.name = $name
                END_OF_QUERY
            end
        end
        respond(:ext_users => external_users_for_session_user)
    end
    
    post '/api/delete_external_user' do
        require_teacher!
        data = parse_request_data(:required_keys => [:email])
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :email => data[:email])
            MATCH (u:User {email: $session_email})-[:ENTERED_EXT_USER]->(e:ExternalUser {email: $email})
            DETACH DELETE e;
        END_OF_QUERY
        respond(:ext_users => external_users_for_session_user)
    end
end
