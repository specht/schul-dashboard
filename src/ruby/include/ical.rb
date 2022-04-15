class Main < Sinatra::Base
    def delete_session_user_ical_link()
        require_user!
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['u.ical_token'] }
            MATCH (u:User {email: $email})
            WHERE EXISTS(u.ical_token)
            RETURN u.ical_token;
        END_OF_QUERY
        result.each do |token|
            path = "/gen/ical/#{token}.ics"
            STDERR.puts path
            if File.exists?(path)
                FileUtils.rm(path)
            end
        end
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: $email})
            REMOVE u.ical_token;
        END_OF_QUERY
    end
    
    post '/api/regenerate_ical_link' do
        require_user!
        delete_session_user_ical_link()
        token = RandomTag.generate(32)
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :token => token)
            MATCH (u:User {email: $email})
            SET u.ical_token = $token;
        END_OF_QUERY
        trigger_update("_#{@session_user[:email]}")
        respond(:token => token)
    end
    
    post '/api/delete_ical_link' do
        require_user!
        delete_session_user_ical_link()
        respond(:ok => 'yeah')
    end
end
