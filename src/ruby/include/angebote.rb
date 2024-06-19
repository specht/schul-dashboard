class Main < Sinatra::Base

    def get_angebote
        # first, purge all connections to users which no longer exist
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (a:Angebot)<-[r:IS_PART_OF]->(u:User)
            RETURN DISTINCT u.email;
        END_OF_QUERY
            email = row['u.email']
            unless @@user_info[email]
                neo4j_query(<<~END_OF_QUERY, :email => email)
                    MATCH (u:User {email: $email})-[r:IS_PART_OF]->(a:Angebot)
                    DELETE r;
                END_OF_QUERY
            end
        end
        angebote = neo4j_query(<<~END_OF_QUERY).map { |x| {:info => x['a'], :recipient => x['u.email'], :owner => x['ou.email'] } }
            MATCH (a:Angebot)-[:DEFINED_BY]->(ou:User)
            WITH a, ou
            OPTIONAL MATCH (u:User)-[r:IS_PART_OF]->(a)
            RETURN a, u.email, ou.email
            ORDER BY a.created DESC, a.id;
        END_OF_QUERY
        temp = {}
        temp_order = []
        angebote.each do |x|
            unless temp[x[:info][:id]]
                temp[x[:info][:id]] = {
                    :recipients => [],
                    :aid => x[:info][:id],
                    :info => x[:info],
                    :owner => x[:owner],
                }
                temp_order << x[:info][:id]
            end
            temp[x[:info][:id]][:recipients] << x[:recipient]
        end
        angebote = temp_order.map do |x|
            temp[x]
        end
        angebote.sort! do |a, b|
            a[:info][:name].downcase <=> b[:info][:name].downcase
        end
        angebote.each do |angebot|
            angebot[:recipients].sort! do |a, b|
                (@@user_info[a][:klasse] == @@user_info[b][:klasse]) ?
                (@@user_info[a][:last_name] <=> @@user_info[b][:last_name]) :
                (KLASSEN_ORDER.index(@@user_info[a][:klasse]) <=> KLASSEN_ORDER.index(@@user_info[b][:klasse]))
            end
        end
        angebote
    end

    post '/api/save_angebot' do
        require_teacher!
        data = parse_request_data(:required_keys => [:name, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        angebot = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name])['a']
            MATCH (u:User {email: $session_email})
            CREATE (a:Angebot {id: $id, name: $name})
            SET a.created = $timestamp
            SET a.updated = $timestamp
            CREATE (a)-[:DEFINED_BY]->(u)
            RETURN a;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :aid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (a:Angebot {id: $aid})
            WITH DISTINCT a
            MATCH (u:User)
            WHERE u.email IN $recipients
            CREATE (u)-[:IS_PART_OF]->(a);
        END_OF_QUERY
        angebot = {
            :aid => angebot[:id],
            :info => angebot,
            :recipients => data[:recipients],
            :owner => @session_user[:email],
        }
        # update recipients
        trigger_update("_angebote_/#{@session_user[:email]}")
        Main.update_angebote_groups()
        Main.update_mailing_lists()
        respond(:ok => true, :angebot => angebot)
    end

    post '/api/update_angebot' do
        require_teacher!
        data = parse_request_data(:required_keys => [:aid, :name, :recipients],
                                :types => {:recipients => Array},
                                :max_body_length => 1024 * 1024,
                                :max_string_length => 1024 * 1024)

        id = data[:aid]
        STDERR.puts "Updating angebot #{id}"
        timestamp = Time.now.to_i
        angebot = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name], :recipients => data[:recipients])['a']
            MATCH (a:Angebot {id: $id})-[:DEFINED_BY]->(ou:User {email: $session_email})
            SET a.updated = $timestamp
            SET a.name = $name
            WITH DISTINCT a
            OPTIONAL MATCH (u)-[r:IS_PART_OF]->(a)
            DELETE r
            WITH DISTINCT a
            RETURN a;
        END_OF_QUERY
        ou_email = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :name => data[:name], :recipients => data[:recipients])['ou.email']
            MATCH (a:Angebot {id: $id})-[:DEFINED_BY]->(ou:User)
            RETURN ou.email;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :aid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (a:Angebot {id: $aid})
            WITH DISTINCT a
            MATCH (u:User)
            WHERE u.email IN $recipients
            MERGE (u)-[r:IS_PART_OF]->(a);
        END_OF_QUERY
        angebot = {
            :aid => angebot[:id],
            :info => angebot,
            :recipients => data[:recipients],
            :owner => ou_email,
        }
        # update recipients
        trigger_update("_angebote_/#{@session_user[:email]}")
        Main.update_angebote_groups()
        Main.update_mailing_lists()
        respond(:ok => true, :angebot => angebot, :aid => angebot[:aid])
    end

    post '/api/delete_angebot' do
        require_teacher!
        data = parse_request_data(:required_keys => [:aid])
        id = data[:aid]
        transaction do
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (ou:User {email: $session_email})<-[:DEFINED_BY]-(a:Angebot {id: $id})
                DETACH DELETE a;
            END_OF_QUERY
        end
        # update recipients
        trigger_update("_angebote_/#{@session_user[:email]}")
        Main.update_angebote_groups()
        Main.update_mailing_lists()
        respond(:ok => true, :aid => data[:aid])
    end

    def get_angebote_for_session_user
        require_user!
        angebote = []
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[:IS_PART_OF]->(a:Angebot)-[:DEFINED_BY]->(ou:User)
            RETURN a, ou.email;
        END_OF_QUERY
            owner = row['ou.email']
            angebot = row['a']
            next unless @@user_info[owner]
            angebote << {
                :owner => @@user_info[owner][:display_name],
                :name => angebot[:name],
            }
        end
        angebote.sort! do |a, b|
            a[:name].downcase <=> b[:name].downcase
        end
        angebote
    end

    def get_angebote_for_email
        require_teacher!
        angebote = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User)-[:IS_PART_OF]->(a:Angebot)-[:DEFINED_BY]->(ou:User)
            RETURN u.email, a.name, ou.email;
        END_OF_QUERY
            owner = row['ou.email']
            name = row['a.name']
            email = row['u.email']
            angebote[email] ||= []
            angebote[email] << {
                :owner => @@user_info[owner][:display_name],
                :name => name,
            }
        end
        angebote
    end
end
