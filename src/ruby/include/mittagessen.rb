class Main < Sinatra::Base
    def mittagessen_choices
        require_user!
        today = Date.today.strftime("%Y-%m-%d")
        # clear all Mittagessen days that are older than today
        neo4j_query(<<~END_OF_QUERY, {:today => today})
            MATCH (m:MittagessenTag) WHERE m.datum < $today
            DETACH DELETE m;
        END_OF_QUERY
        choices = {}
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
            MATCH (u:User {email: $email})-[r:CHOSE]->(m:MittagessenTag)
            RETURN m.datum, r.choice;
        END_OF_QUERY
            choices[row['m.datum']] = row['r.choice']
        end
        choices
    end

    def mittagessen_overview
        require_user_with_role!(:mittagessen)
        choices = {}
        neo4j_query(<<~END_OF_QUERY,).each do |row|
            MATCH (u:User)-[r:CHOSE]->(m:MittagessenTag)
            RETURN m.datum, r.choice;
        END_OF_QUERY
            choices[row['m.datum']] ||= {}
            choices[row['m.datum']][row['r.choice'].to_s] ||= 0
            choices[row['m.datum']][row['r.choice'].to_s] += 1
        end
        choices
    end

    def self.update_mittagessen
        path = '/data/mittagessen/mittagessen.yaml'
        @@mittagessen_mtime ||= 0
        mtime = File.mtime(path)
        if mtime > @@mittagessen_mtime
            debug "Reloading #{path}..."
            @@mittagessen = YAML.load(File.read(path)).map do |x|
                x['order'].map! do |y|
                    Time.parse(y).to_i
                end
                x
            end
            @@mittagessen_mtime = mtime
            @@mittagessen_rev = {}
            @@mittagessen.each do |entry|
                p = Date.parse(entry['d0'])
                p1 = Date.parse(entry['d1'])
                while p <= p1
                    @@mittagessen_rev[p.strftime('%Y-%m-%d')] = entry['order']
                    p += 1
                end
            end
            debug @@mittagessen_rev.to_yaml
        end
    end

    post '/api/choose_mittagessen' do
        require_user!
        Main.update_mittagessen
        data = parse_request_data(:required_keys => [:datum, :choice], :types => {:choice => Integer})
        assert(@@mittagessen_rev.include?(data[:datum]))
        ts_now = Time.now.to_i
        assert(ts_now >= @@mittagessen_rev[data[:datum]][0] && ts_now < @@mittagessen_rev[data[:datum]][1])
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :datum => data[:datum], :choice => data[:choice]})
            MATCH (u:User {email: $email})-[r:CHOSE]->(m:MittagessenTag {datum: $datum})
            DELETE r;
        END_OF_QUERY
        if data[:choice] > 0
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :datum => data[:datum], :choice => data[:choice]})
                MATCH (u:User {email: $email})
                WITH u
                MERGE (m:MittagessenTag {datum: $datum})
                WITH u, m
                CREATE (u)-[:CHOSE {choice: $choice}]->(m);
            END_OF_QUERY
        end
        respond(:ok => 'sure')
    end
end
