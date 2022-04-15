class Main < Sinatra::Base
    post '/api/send_message' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:recipients, :message],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:message => 1024 * 1024})
        id = RandomTag.generate(12)
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        FileUtils::mkpath(File.dirname(path))
        Zlib::GzipWriter.open(path) do |f|
            f.print data[:message]
        end
        timestamp = Time.now.to_i
        message = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :recipients => data[:recipients])['m']
            MATCH (a:User {email: $session_email})
            CREATE (m:Message {id: $id})
            SET m.created = $timestamp
            SET m.updated = $timestamp
            CREATE (m)-[:FROM]->(a)
            WITH m
            MATCH (u:User)
            WHERE u.email IN $recipients
            CREATE (m)-[:TO]->(u)
            RETURN DISTINCT m;
        END_OF_QUERY
        t = Time.at(message[:created])
        message = {
            :date => t.strftime('%Y-%m-%d'),
            :dow => t.wday,
            :mid => message[:id],
            :recipients => data[:recipients]
        }
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :message => message)
    end
    
    post '/api/update_message' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:mid, :recipients, :message],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:message => 1024 * 1024})
        id = data[:mid]
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        FileUtils::mkpath(File.dirname(path))
        Zlib::GzipWriter.open(path) do |f|
            f.print data[:message]
        end
        timestamp = Time.now.to_i
        message = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :recipients => data[:recipients])['m']
            MATCH (m:Message {id: $id})-[:FROM]->(a:User {email: $session_email})
            SET m.updated = $timestamp
            WITH DISTINCT m
            MATCH (m)-[r:TO]->(u:User)
            DELETE r
            WITH DISTINCT m
            MATCH (u:User)
            WHERE u.email IN $recipients
            CREATE (m)-[:TO]->(u)
            RETURN DISTINCT m;
        END_OF_QUERY
        t = Time.at(message[:created])
        message = {
            :date => t.strftime('%Y-%m-%d'),
            :dow => t.wday,
            :mid => message[:id],
            :recipients => data[:recipients]
        }
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :message => message, :mid => data[:mid])
    end
    
    post '/api/delete_message' do
        require_teacher_or_sv!
        data = parse_request_data(:required_keys => [:mid])
        id = data[:mid]
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        # also delete message on file system
        FileUtils::rm_f(path)
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: $session_email})<-[:FROM]-(m:Message {id: $id})
                SET m.updated = $timestamp
                SET m.deleted = true
                WITH m
                OPTIONAL MATCH (m)-[rt:TO]->(r:User)
                SET rt.updated = $timestamp
                SET rt.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :mid => data[:mid])
    end
    
    post '/api/mark_as_read' do
        require_user!
        data = parse_request_data(:required_keys => [:ids],
                                  :types => {:ids => Array})
        transaction do 
            results = neo4j_query(<<~END_OF_QUERY, :ids => data[:ids], :email => @session_user[:email])
                MATCH (c)-[ruc:TO]->(:User {email: $email})
                WHERE (c:TextComment OR c:AudioComment OR c:Message) AND c.id IN $ids
                SET ruc.seen = true
            END_OF_QUERY
        end
        respond(:new_unread_ids => get_unread_messages(Time.now.to_i - MESSAGE_DELAY))
    end

    def get_unread_messages(now)
        require_user!
        # don't show messages which are not at least 5 minutes old
        rows = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :now => now).map { |x| x['c.id'] }
            MATCH (c)-[ruc:TO]->(u:User {email: $email}) 
            WHERE ((c:TextComment AND EXISTS(c.comment)) OR 
                    (c:AudioComment AND EXISTS(c.tag)) OR
                    (c:Message AND EXISTS(c.id))) AND
                    c.updated < $now AND COALESCE(ruc.seen, false) = false
            RETURN c.id
        END_OF_QUERY
        rows
    end
end
