class Main < Sinatra::Base

    def user_eligible_for_projekt_katalog?
        return true if @session_user[:teacher]
        return @session_user[:klassenstufe] && @session_user[:klassenstufe] >= 5
    end

    def user_eligible_for_projektwahl?
        return false unless DEVELOPMENT
        return false if @session_user[:teacher]
        return @session_user[:klassenstufe] && @session_user[:klassenstufe] >= 5 && @session_user[:klassenstufe] <= 9
    end

    def parse_projekt_node(p)
        {
            :nr => p[:nr],
            :title => p[:title],
            :description => p[:description],
            :photo => p[:photo],
            :exkursion_hint => p[:exkursion_hint],
            :extra_hint => p[:extra_hint],
            :categories => p[:categories],
            :min_klasse => p[:min_klasse],
            :max_klasse => p[:max_klasse],
            :capacity => p[:capacity],
            :organized_by => [],
            :supervised_by => [],
        }
    end

    def get_projekte
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:organized_by] << row['u.email']
        end

        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:SUPERVISED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:supervised_by] << row['u.email']
        end
        projekte_list = []
        projekte.each_pair do |nr, p|
            p[:organized_by] = p[:organized_by].sort.uniq
            p[:supervised_by] = p[:supervised_by].sort.uniq
            p[:klassen_label] = '–'
            if p[:min_klasse] && p[:max_klasse]
                if p[:min_klasse] == p[:max_klasse]
                    p[:klassen_label] = "nur #{p[:min_klasse]}."
                else
                    p[:klassen_label] = "#{p[:min_klasse]}. – #{p[:max_klasse]}."
                end
            end
            projekte_list << p
        end

        projekte_list.sort! do |a, b|
            (a[:nr].to_i == b[:nr].to_i) ?
            (a[:nr] <=> b[:nr]) :
            (a[:nr].to_i <=> b[:nr].to_i)
        end

        projekte_list
    end

    post '/api/get_projekte' do
        require_user!
        result = {:projekte => get_projekte()}
        if user_eligible_for_projektwahl?
            vote_for_project_nr = {}
            neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).each do |row|
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekt)
                RETURN p.nr, v.vote;
            END_OF_QUERY
                vote_for_project_nr[row['p.nr']] = row['v.vote']
            end
            result[:projekte].map! do |p|
                p[:session_user_vote] = vote_for_project_nr[p[:nr]] || 0
                p
            end
        end
        respond(result)
    end

    post '/api/get_projekte_for_orga_sus' do
        require_user!
        projekte = get_projekte()
        projekte.select! do |p|
            p[:organized_by].include?(@session_user[:email])
        end
        respond(:projekte => projekte)
    end

    post '/api/update_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr, :title, :description, :exkursion_hint, :extra_hint], :max_body_length => 16384, :max_string_length => 8192)
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :title => data[:title], :description => data[:description], :exkursion_hint => data[:exkursion_hint], :extra_hint => data[:extra_hint], :ts => Time.now.to_i})['p']
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.title = $title
            SET p.description = $description
            SET p.exkursion_hint = $exkursion_hint
            SET p.extra_hint = $extra_hint
            SET p.ts_updated = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/set_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr, :photo])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :photo => data[:photo], :ts => Time.now.to_i})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.photo = $photo
            SET p.ts_updates = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/delete_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => Time.now.to_i})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            REMOVE p.photo
            SET p.ts_updated = $ts
            RETURN p;
        END_OF_QUERY
    end

    post '/api/vote_for_project' do
        require_user!
        assert(user_eligible_for_projektwahl?)
        data = parse_request_data(:required_keys => [:nr, :vote], :types => {:vote => Integer})
        if data[:vote] == 0
            neo4j_query(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => Time.now.to_i, :vote => data[:vote]})
                MATCH (u:User {email: $email})-[v:VOTED_FOR]->(p:Projekt {nr: $nr})
                DELETE v;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :ts => Time.now.to_i, :vote => data[:vote]})
                MATCH (u:User {email: $email})
                MATCH (p:Projekt {nr: $nr})
                MERGE (u)-[v:VOTED_FOR]->(p)
                SET v.ts_updated = $ts
                SET v.vote = $vote
                RETURN p;
            END_OF_QUERY
        end
    end
end
