class Main < Sinatra::Base

    def user_eligible_for_projekt_katalog?
        return true if @session_user[:teacher]
        return @session_user[:klassenstufe] >= 5
    end

    def user_eligible_for_projektwahl?
        return false if @session_user[:teacher]
        return @session_user[:klassenstufe] >= 5 && @session_user[:klassenstufe] <= 9
    end

    def get_projekte
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= {
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
            projekte[p[:nr]][:organized_by] << row['u.email']
        end

        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekt)-[:SUPERVISED_BY]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            projekte[p[:nr]] ||= {
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
        respond(:projekte => get_projekte())
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
        data = parse_request_data(:required_keys => [:nr, :title, :description, :exkursion_hint, :extra_hint])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :title => data[:title], :description => data[:description], :exkursion_hint => data[:exkursion_hint], :extra_hint => data[:extra_hint]})['p']
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.title = $title
            SET p.description = $description
            SET p.exkursion_hint = $exkursion_hint
            SET p.extra_hint = $extra_hint
            RETURN p;
        END_OF_QUERY
    end

    post '/api/set_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr, :photo])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email], :photo => data[:photo]})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            SET p.photo = $photo
            RETURN p;
        END_OF_QUERY
    end

    post '/api/delete_photo_for_project' do
        require_user!
        data = parse_request_data(:required_keys => [:nr])
        projekt = neo4j_query_expect_one(<<~END_OF_QUERY, {:nr => data[:nr], :email => @session_user[:email]})
            MATCH (p:Projekt {nr: $nr})-[:ORGANIZED_BY]->(u:User {email: $email})
            REMOVE p.photo
            RETURN p;
        END_OF_QUERY
    end
end
