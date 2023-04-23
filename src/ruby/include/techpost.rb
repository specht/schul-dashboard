class Main < Sinatra::Base
    post '/api/report_tech_problem' do
        require_user!
        data = parse_request_data(:required_keys => [:problem, :date, :device],)
        possible_codes = (0..9999).to_a
        Dir['/internal/tech_problem/*.json'].each do |path|
            code = File.basename(path).gsub('.json', '').to_i
            possible_codes.delete(code)
        end
        code = possible_codes.sample

        problem_data = {
            :token => RandomTag.generate(24),
            :problem => data[:problem],
            :date => data[:date],
            :device => data[:device],
        }
        File.open(sprintf('/internal/tech_problem/%04d.json', code), 'w') { |f| f.write(problem_data.to_json) }
        neo4j_query(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (u:User {email: $email})
            CREATE (v:TechProblem {code: $code})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/get_tech_problems' do
        require_user!
        codes = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['v.code'] }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(:User {email: $email})
            RETURN v.code;
        END_OF_QUERY
        results = codes.map do |code|
            begin
                problem_data = {}
                STDERR.puts "/api/get_tech_problems: #{code}"
                File.open(sprintf("/internal/tech_problem/%04d.json", code)) do |f|
                    problem_data = JSON.parse(f.read)
                end
                problem_data[:code] = code
                problem_data
            rescue 
                STDERR.puts "Unable to read #{sprintf('/internal/tech_problem/%04d.json', code)}"
                nil
            end
        end.reject { |x| x.nil? }
        results = results.sort do |a, b|
            a['date'] <=> b['date']
        end
        respond(:tech_problems => results)
    end
    
    post '/api/get_tech_problems_admin' do
        require_user_who_can_manage_tablets!
        codes = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['v.code'] }
            MATCH (v:TechProblem)
            RETURN v.code;
        END_OF_QUERY
        results = codes.map do |code|
            begin
                problem_data = {}
                STDERR.puts "/api/get_tech_problems_admin: #{code}"
                File.open(sprintf("/internal/tech_problem/%04d.json", code)) do |f|
                    problem_data = JSON.parse(f.read)
                end
                problem_data[:code] = code
                problem_data
            rescue 
                STDERR.puts "Unable to read #{sprintf('/internal/tech_problem/%04d.json', code)}"
                nil
            end
        end.reject { |x| x.nil? }
        results = results.sort do |a, b|
            a['date'] <=> b['date']
        end
        respond(:tech_problems => results)
    end

    post '/api/delete_tech_problem' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:code],
                                  :types => {:code => Integer})
        code = data[:code]
        neo4j_query_expect_one(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (v:TechProblem {code: $code})-[:BELONGS_TO]->(u:User {email: $email})
            DETACH DELETE v
            RETURN u.email;
        END_OF_QUERY
        STDERR.puts "Deleting #{code}..."
        FileUtils::rm_f(sprintf('/internal/tech_problem/%04d.json', code));
        FileUtils::rm_f(sprintf('/internal/tech_problem/%04d.pdf', code));
        respond(:ok => true)
    end

    post '/api/delete_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:code],
                                  :types => {:code => Integer})
        code = data[:code]
        neo4j_query(<<~END_OF_QUERY, :code => code)
            MATCH (v:TechProblem {code: $code})
            DETACH DELETE v
        END_OF_QUERY
        STDERR.puts "Deleting #{code}..."
        FileUtils::rm_f(sprintf('/internal/tech_problem/%04d.json', code));
        respond(:ok => true)
    end

end