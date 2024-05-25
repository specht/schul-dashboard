class Main < Sinatra::Base
    post '/api/save_group' do
        require_user_with_role!(:can_write_messages)
        data = parse_request_data(:required_keys => [:name, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        group = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name])['g']
            MATCH (a:User {email: $session_email})
            CREATE (g:Group {id: $id, name: $name})
            SET g.created = $timestamp
            SET g.updated = $timestamp
            CREATE (g)-[:DEFINED_BY]->(a)
            RETURN g;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (g:Group {id: $gid})
            WITH DISTINCT g
            MATCH (u:User)
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PART_OF]->(g);
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (g:Group {id: $gid})
            WITH DISTINCT g
            MATCH (u:ExternalUser {entered_by: $session_email})
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PART_OF]->(g);
        END_OF_QUERY
        # link external users (predefined)
        STDERR.puts data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) }.to_yaml
        temp = neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (g:Group {id: $gid})
            WITH DISTINCT g
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PART_OF]->(g);
        END_OF_QUERY
        group = {
            :gid => group[:id], 
            :info => group,
            :recipients => data[:recipients],
        }
        # update recipients
        trigger_update("_groups_/#{@session_user[:email]}")
        respond(:ok => true, :group => group)
    end
    
    post '/api/update_group' do
        require_user_with_role!(:can_write_messages)
        data = parse_request_data(:required_keys => [:gid, :name, :recipients],
                                :types => {:recipients => Array},
                                :max_body_length => 1024 * 1024,
                                :max_string_length => 1024 * 1024)

        id = data[:gid]
        STDERR.puts "Updating group #{id}"
        timestamp = Time.now.to_i
        group = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name], :recipients => data[:recipients])['g']
            MATCH (g:Group {id: $id})-[:DEFINED_BY]->(a:User {email: $session_email})
            SET g.updated = $timestamp
            SET g.name = $name
            WITH DISTINCT g
            OPTIONAL MATCH (u)-[r:IS_PART_OF]->(g)
            SET r.deleted = true
            WITH DISTINCT g
            RETURN g;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (g:Group {id: $gid})
            WITH DISTINCT g
            MATCH (u:User)
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PART_OF]->(g)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (g:Group {id: $gid})
            WITH DISTINCT g
            MATCH (u:ExternalUser {entered_by: $session_email})
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PART_OF]->(g)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users (predefined)
        neo4j_query(<<~END_OF_QUERY, :gid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (g:Event {id: $gid})
            WITH DISTINCT g
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PART_OF]->(g)
            REMOVE r.deleted
        END_OF_QUERY
        group = {
            :gid => group[:id], 
            :info => group,
            :recipients => data[:recipients]
        }
        # update recipients
        trigger_update("_groups_/#{@session_user[:email]}")
        respond(:ok => true, :group => group, :gid => group[:gid])
    end
    
    post '/api/delete_group' do
        require_user_with_role!(:can_write_messages)
        data = parse_request_data(:required_keys => [:gid])
        id = data[:gid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: $session_email})<-[:DEFINED_BY]-(g:Group {id: $id})
                SET g.updated = $timestamp
                SET g.deleted = true
                WITH g
                OPTIONAL MATCH (r:User)-[rt:IS_PART_OF]->(g)
                SET rt.updated = $timestamp
                SET rt.deleted = true
            END_OF_QUERY
        end
        # update recipients
        trigger_update("_groups_/#{@session_user[:email]}")
        respond(:ok => true, :gid => data[:gid])
    end
end
