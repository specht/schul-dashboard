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
            SET v.not_fixed = false
            SET v.comment = false
            SET v.hidden = false
            SET v.hidden_admin = false
            SET v.mail_count = 0
            RETURN v.token;
        END_OF_QUERY
        name = @session_user[:display_name]
        mail_adress = @session_user[:email]
        deliver_mail do
            to mail_adress
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Neues Technikproblem"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Du hast soeben ein neues Technikproblem angelegt. Das Problem betrifft #{data[:device]} und lautet: „#{data[:problem]}“</p>"
                io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
                io.puts "<p>Diese E-Mail dient nur als Bestätigung, du musst also nicht weiter tun.</p>"
                io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string
            
            end
        end
        for mail_adress in TECHNIKTEAM do
            deliver_mail do
                to mail_adress
                bcc SMTP_FROM
                from SMTP_FROM

                subject "Neues Technikproblem"

                StringIO.open do |io|
                    io.puts "<p>Liebes TechnikTeam,</p>"
                    io.puts "<p>es liegt ein neues Technikproblem vor. Das Problem betrifft #{data[:device]} und lautet: „#{data[:problem]}“ Das Problem wurde von #{name} abgesendet</p>"
                    io.puts "<a href='#{WEBSITE_HOST}/techpostadmin'>Probleme ansehen</a>"
                    io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                    io.string
                
                end
            end
        end
        respond(:ok => true)
    end

    post '/api/report_tech_problem_quiet' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:problem, :date, :device],)
        token = RandomTag.generate(24)
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => @session_user[:email], :device => data[:device], :date => data[:date], :problem => data[:problem])
            MATCH (u:User {email: $email})
            CREATE (v:TechProblem {token: $token})-[:BELONGS_TO]->(u)
            SET v.device = $device 
            SET v.date = $date
            SET v.problem = $problem
            SET v.fixed = false
            SET v.not_fixed = false
            SET v.comment = false
            SET v.hidden = false
            SET v.hidden_admin = false
            SET v.mail_count = 0
            RETURN v.token;
        END_OF_QUERY
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
            x[:nc_login] = @@user_info[x[:email]][:nc_login]
            x[:klasse] = @@user_info[x[:email]][:klasse]
            x
        end
        respond(:tech_problems => problems)
    end

    post '/api/fix_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.fixed = true
            SET v.not_fixed = false
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/unfix_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.fixed = false
            SET v.not_fixed = false
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/not_fix_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.fixed = false
            SET v.not_fixed = true
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/hide_tech_problem' do
        require_user_who_can_report_tech_problems!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.hidden = true
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/unhide_tech_problem' do
        require_user_who_can_report_tech_problems!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.hidden = false
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/mail_tech_problem' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        data = neo4j_query(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})-[:BELONGS_TO]->(u:User)
            SET v.mail_count = v.mail_count + 1
            RETURN v, u.email;
        END_OF_QUERY
        problem = data.first["v"]
        mail_adress = data.first["u.email"]

        if problem[:fixed]
            state = "„Behoben“"
        elsif problem[:not_fixed]
            state = "„Nicht behoben“"
        elsif problem[:comment]
            state = "„Siehe Kommentar“" 
        else 
            state = "„In Bearbeitung“"
        end

        if problem[:comment] && state == "„Siehe Kommentar“"
            comment = " Der Kommentar lautet: „#{problem[:comment]}“."
        elsif
            comment = " Außerdem hat das TechnikTeam einen Kommentar geschrieben: „#{problem[:comment]}“."
        end
        deliver_mail do
            to mail_adress
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Neuigkeiten zu deinem Technikproblem"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Es gibt Neuigkeiten zu deinem Technikproblem:</p>"
                io.puts "<p>Das Problem hat jetzt den Status #{state}.#{comment}</p>"
                io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
                io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string
            
            end
        end
        admin_mail_adress = @session_user[:email]
        deliver_mail do
            to admin_mail_adress
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Kopie: Neuigkeiten zu deinem Technikproblem"

            StringIO.open do |io|
                io.puts "<p>Diese E-Mail wurde an #{mail_adress} gesendet.</p>"
                io.puts "<p></p>"
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Es gibt Neuigkeiten zu deinem Technikproblem:</p>"
                io.puts "<p>Das Problem hat jetzt den Status #{state}.#{comment}</p>"
                io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
                io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string
            
            end
        end
        respond(:ok => true)
    end

    post '/api/hide_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.hidden_admin = true
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/unhide_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            SET v.hidden_admin = false
            SET v.fixed = false
            SET v.not_fixed = false
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})
            DETACH DELETE v
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    def print_tablet_login()
        require_user_who_can_manage_tablets!
        StringIO.open do |io|
            io.puts "<p>Mit einem Klick auf diesen Button kannst du dieses Gerät dauerhaft als Lehrer-Tablet anmelden.</p>"
            io.puts "<button class='btn btn-primary bu_login_teacher_tablet'><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Lehrer-Tablet-Modus aktivieren</button>"
            io.puts "<hr />"
            io.puts "<p>Bitte wähle ein order mehrere Kürzel, um dieses Gerät dauerhaft als Kurs-Tablet anzumelden.</p>"
            @@shorthands.keys.sort.each do |shorthand|
                io.puts "<button class='btn-teacher-for-kurs-tablet-login btn btn-xs btn-outline-secondary' data-shorthand='#{shorthand}'>#{shorthand}</button>"
            end
            io.puts "<br /><br >"
            io.puts "<button class='btn btn-primary bu_login_kurs_tablet' disabled><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Kurs-Tablet-Modus aktivieren</button>"
            io.puts "<hr />"
            io.puts "<p>Bitte wähle ein Tablet, um dieses Gerät dauerhaft als dieses Tablet anzumelden.</p>"
            @@tablets.keys.each do |id|
                tablet = @@tablets[id]
                io.puts "<button class='btn-tablet-login btn btn-xs btn-outline-secondary' data-id='#{id}' style='background-color: #{tablet[:bg_color]}; color: #{tablet[:fg_color]};'>#{id}</button>"
            end
            io.puts "<hr />"
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Typ</th>"
            io.puts "<th>Gerät</th>"
            io.puts "<th>Abmelden</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            get_sessions_for_user("lehrer.tablet@#{SCHUL_MAIL_DOMAIN}").each do |session|
                io.puts "<tr>"
                io.puts "<td>Lehrer-Tablet</td>"
                io.puts "<td>#{session[:user_agent]}</td>"
                io.puts "<td><button class='btn btn-xs btn-danger btn-purge-session' data-email='lehrer.tablet@#{SCHUL_MAIL_DOMAIN}' data-scrambled-sid='#{session[:scrambled_sid]}'>Abmelden</button></td>"
                io.puts "</tr>"
            end
            get_sessions_for_user("kurs.tablet@#{SCHUL_MAIL_DOMAIN}").each do |session|
                io.puts "<tr>"
                io.puts "<td>Kurs-Tablet (#{(session[:shorthands] || []).sort.join(', ')})</td>"
                io.puts "<td>#{session[:user_agent]}</td>"
                io.puts "<td><button class='btn btn-xs btn-danger btn-purge-session' data-email='kurs.tablet@#{SCHUL_MAIL_DOMAIN}' data-scrambled-sid='#{session[:scrambled_sid]}'>Abmelden</button></td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end
end
