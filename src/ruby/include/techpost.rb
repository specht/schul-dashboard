class Main < Sinatra::Base
    post '/api/report_tech_problem' do
        require_user_who_can_report_tech_problems!
        data = parse_request_data(:required_keys => [:problem, :date, :device],)

        token = RandomTag.generate(24)
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => @session_user[:email], :device => data[:device], :date => data[:date], :problem => data[:problem])
            MATCH (u:User {email: $email})
            CREATE (v:TechProblem {token: $token})-[:BELONGS_TO]->(u)
            SET v.device = $device 
            SET v.date = $date
            SET v.problem = $problem
            SET v.fixed = false
            SET v.comment = false
            RETURN v.token;
        END_OF_QUERY

        deliver_mail do
            to TECHNIKTEAM
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Neues Technikproblem"

            StringIO.open do |io|
                io.puts "<p>Hallo TechnikTeam, "
                io.puts "<p>es liegt ein neues Technikproblem vor.</p>"
                io.puts "<p>Das Problem betrifft #{data[:device]} und lautet: „#{data[:problem]}“</p>"
                io.puts "<p>Viele Grüße</p>"
                io.string
            
            end
        end
        respond(:ok => true)
    end

    post '/api/comment_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token, :comment],)
        token = data[:token]
        comment = data[:comment]
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :comment => comment)
            MATCH (v:TechProblem {token: $token})
            SET v.comment = $comment
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/get_tech_problems' do
        require_user_who_can_report_tech_problems!
        problems = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:problem => x['v'], :email => x['u.email']} }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(:User {email: $email})
            RETURN v;
        END_OF_QUERY

        debug problems.to_yaml
        respond(:tech_problems => problems)
    end
    
    post '/api/get_tech_problems_admin' do
        require_user_who_can_manage_tablets!
        problems = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:problem => x['v'], :email => x['u.email']} }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(u:User)
            RETURN v, u.email;
        END_OF_QUERY
        problems.map! do |x|
            x[:display_name] = @@user_info[x[:email]][:display_name]
            x[:klasse] = @@user_info[x[:email]][:klasse]
            x
        end

        debug problems.to_yaml
        respond(:tech_problems => problems)
    end

    post '/api/fix_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        debug token
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.fixed = true
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/unfix_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        debug token
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.fixed = false
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    # post '/api/delete_tech_problem' do
    #     require_user_who_can_report_tech_problems!
    #     data = parse_request_data(:required_keys => [:token])
    #     token = data[:token]
    #     debug token
    #     neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
    #         MATCH (v:TechProblem {token: $token})
    #         DETACH DELETE v
    #         RETURN v;
    #     END_OF_QUERY
    #     respond(:ok => true)
    # end

    post '/api/delete_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        debug token
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            DETACH DELETE v
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

end
