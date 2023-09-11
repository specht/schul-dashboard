class Main < Sinatra::Base

    def check_has_technikamt(email)
        results = neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})-[:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            RETURN CASE WHEN EXISTS((u)-[:HAS_AMT {amt: 'technikamt'}]->(v)) THEN true ELSE false END AS hasRelation;
        END_OF_QUERY
        return results
    end
    
    def get_technikamt
        results = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)-[:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            RETURN u.email;
        END_OF_QUERY
        debug results
        return results.map { |result| result["u.email"] }
    end

    post '/api/send_all_techpost_welcome_mail' do
        require_user_who_can_manage_tablets!
        deliver_mail do
            bcc get_technikamt
            from SMTP_FROM

            subject "Du bist Technikamt im Dashboard!"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Das TechnikTeam hat dir soeben die Funktion „Technikamt“ im Dashboard freigeschaltet. Herzlichen Glückwunsch, du gehörst zu den Ersten, die diese Funktion nutzen dürfen!</p>"
                io.puts "<p>Du solltest die Funktion schon im Rahmen eines Workshops kennengelernt haben. Gerne kannst du jetzt die Funktion testen (schreib aber bitte immer dazu, wenn es sich um einen Test handelt).</p>"
                io.puts "<p>Falls du diese Nachricht unerwartet bekommst oder Probleme beim Anmelden im Dashboard hast, melde dich einfach bei Peter-J. Germelmann (peter-julius.germelmann@mail.gymnasiumsteglitz.de).</p>"
                io.puts "<p>Viele Grüße<br>Das TechnikTeam #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string
            end
        end
        respond(:ok => true)
    end

    post '/api/send_single_techpost_welcome_mail' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:email],)
        deliver_mail do
            to data[:email]
            from SMTP_FROM

            subject "Du bist Technikamt im Dashboard!"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Das TechnikTeam hat dir soeben die Funktion „Technikamt“ im Dashboard freigeschaltet. Herzlichen Glückwunsch, du gehörst zu den Ersten, die diese Funktion nutzen dürfen!</p>"
                io.puts "<p>Du solltest die Funktion schon im Rahmen eines Workshops kennengelernt haben. Gerne kannst du jetzt die Funktion testen (schreib aber bitte immer dazu, wenn es sich um einen Test handelt).</p>"
                io.puts "<p>Falls du diese Nachricht unerwartet bekommst oder Probleme beim Anmelden im Dashboard hast, melde dich einfach bei Peter-J. Germelmann (peter-julius.germelmann@mail.gymnasiumsteglitz.de).</p>"
                io.puts "<p>Viele Grüße<br>Das TechnikTeam #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string
            end
        end
        respond(:ok => true)
    end

    post '/api/report_tech_problem' do
        require_user_who_can_report_tech_problems_or_better!
        data = parse_request_data(:required_keys => [:problem, :date, :device],)
        token = RandomTag.generate(24)
        neo4j_entry = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => @session_user[:email], :device => data[:device], :date => data[:date], :problem => data[:problem])
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
            RETURN v, u.email;
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
                # io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
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
                    io.puts "<p>es liegt ein neues Technikproblem vor. Das Problem betrifft #{data[:device]} und lautet: „#{data[:problem]}“ Das Problem wurde von #{name} abgesendet.</p>"
                    # io.puts "<a href='#{WEBSITE_HOST}/techpostadmin'>Probleme ansehen</a>"
                    io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                    io.string
                
                end
            end
        end
        deliver_mail do
            to WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Debug: Neues Technikproblem"

            StringIO.open do |io|
                io.puts "<p>#{neo4j_entry}</p>"
                io.string
            
            end
        end
        respond(:ok => true)
    end

    post '/api/report_tech_problem_quiet' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:problem, :date, :device],)
        token = RandomTag.generate(24)
        neo4j_entry = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => @session_user[:email], :device => data[:device], :date => data[:date], :problem => data[:problem])
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
            RETURN v, u.email;
        END_OF_QUERY
        respond(:ok => true)
        deliver_mail do
            to WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Debug: Neues Technikproblem"

            StringIO.open do |io|
                io.puts "<p>#{neo4j_entry}</p>"
                io.string
            
            end
        end
    end

    post '/api/comment_tech_problem_admin' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token, :comment],)
        token = data[:token]
        comment = data[:comment]
        if comment != ""
            problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :comment => comment)
                MATCH (v:TechProblem {token: $token})
                SET v.comment = $comment
                RETURN v;
            END_OF_QUERY
        else
            problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :comment => comment)
                MATCH (v:TechProblem {token: $token})
                SET v.comment = false
                RETURN v;
            END_OF_QUERY
        end
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
        problems = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:problem => x['v'], :email => x['u.email'], :femail => x['f.email']} }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(u:User)
            OPTIONAL MATCH (v:TechProblem)-[:WILL_BE_FIXED_BY]->(f:User)
            RETURN v, u.email, f.email;
        END_OF_QUERY
        problems.map! do |x|
            x[:display_name] = @@user_info[x[:email]][:display_name]
            x[:nc_login] = @@user_info[x[:email]][:nc_login]
            if x[:femail]
                x[:fnc_login] = @@user_info[x[:femail]][:nc_login]
                x[:fdisplay_name] = @@user_info[x[:femail]][:display_name]
            end
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
        elsif problem[:comment]
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
                # io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
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
                # io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
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

    post '/api/i_will_fix_tech_problem' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => @session_user[:email])
            MATCH (v:TechProblem {token: $token})
            MATCH (u:User {email: $email})
            MERGE (v)-[:WILL_BE_FIXED_BY]->(u)
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/i_will_not_fix_tech_problem' do
        require_user_who_can_manage_tablets!
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query(<<~END_OF_QUERY, :token => token, :email => @session_user[:email])
            MATCH (v:TechProblem {token: $token})-[r:WILL_BE_FIXED_BY]->(u:User {email: $email})
            DELETE r;
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

    post '/api/clear_all_tech_problems_admin' do
        require_technikteam!
        neo4j_query(<<~END_OF_QUERY)
            MATCH (v:TechProblem)
            DETACH DELETE v
        END_OF_QUERY
        display_name = @session_user[:display_name]
        respond(:ok => true)
        deliver_mail do
            to WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Alle Probleme gelöscht"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>#{display_name} hat soeben alle Technikprobleme gelöscht. Du musst/kannst nichts weiter tun, diese E-Mail dient nur als Info.</p>"
                io.string
            
            end
        end
    end

    post '/api/add_techpost' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})
            MERGE (v:Techpost)
            MERGE (u)-[:HAS_AMT {amt: 'technikamt'}]->(v)
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_techpost' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})-[r:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            DELETE r;
        END_OF_QUERY
        respond(:ok => true)
    end

    def print_techpost_superuser()
        require_user_who_can_manage_tablets!
        problems = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:problem => x['v'], :email => x['u.email'], :femail => x['f.email']} }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(u:User)
            OPTIONAL MATCH (v:TechProblem)-[:WILL_BE_FIXED_BY]->(f:User)
            RETURN v, u.email, f.email;
        END_OF_QUERY
        StringIO.open do |io|
            io.puts "<h3>User, die Zugriff auf diese Seite haben</h3>"
            io.puts "<div class='alert alert-danger'><code>"
            # for tech_admin in TECHNIKTEAM + CAN_MANAGE_TABLETS_USERS + ADMIN_USERS do
            #     display_name = @@user_info[tech_admin][:display_name]
            #     nc_login = @@user_info[tech_admin][:nc_login]
            #     io.puts "<img src='#{NEXTCLOUD_URL}/index.php/avatar/#{nc_login}/256' class='icon avatar-md'>&nbsp;#{display_name}"
            # end
            io.puts "</code><div class='text-muted'>Diese Funktion steht zurzeit, aufgrund eines technischen Fehlers, nicht zur Verfügung. Bitte nutzen Sie die Liste unten.</div><code>"
            io.puts "</code></div>"
            io.puts "<div class='alert alert-info'><code>#{TECHNIKTEAM + CAN_MANAGE_TABLETS_USERS + ADMIN_USERS}</code></div>"
            io.puts "<br><h3>User, die Probleme melden können (Alle oben genannten plus:)</h3>"
            io.puts "<div class='alert alert-warning'>"
            # io.puts "<div class='text-muted'>Klicke auf einen Nutzer, um ihm die Berechtigungen für das Technikamt zu entziehen.</div>"
            io.puts "<table class='table narrow table-striped' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr><td>User</td><td>Bearbeiten</td></tr>"
            io.puts "</thead><tbody>"
            for technikamt in get_technikamt do
                display_name = @@user_info[technikamt][:display_name]
                nc_login = @@user_info[technikamt][:nc_login]
                klasse = @@user_info[technikamt][:klasse]
                io.puts "<tr><td><code><img src='#{NEXTCLOUD_URL}/index.php/avatar/#{nc_login}/256' class='icon avatar-md'>&nbsp;#{display_name} (#{klasse})</code></td><td><button class='btn btn-xs btn-danger bu-edit-techpost' data-email='#{technikamt}'><i class='fa fa-trash'></i>&nbsp;&nbsp;Rechte entziehen</button>&nbsp;<button class='btn btn-xs btn-success bu-send-single-welcome-mail' data-email='#{technikamt}'><i class='fa fa-envelope'></i>&nbsp;&nbsp;Willkommens-E-Mail versenden</button></td></tr>"
            end
            io.puts "</table></tbody>"
            # io.puts "</code><div class='text-muted'>Diese Funktion steht zurzeit, aufgrund eines technischen Fehlers, nicht zur Verfügung. Bitte nutzen Sie die Liste unten.</div><code>"
            io.puts "</code></div>"
            io.puts "<div class='alert alert-warning'><code>#{get_technikamt}</code></div>"
            unless problems == []
                io.puts "<br><h3>Aktuelle Probleme im json-Format</h3>"
                for problem in problems do
                    io.puts "<div class='alert alert-success'><code>#{problem.to_json}</code></div>"
                end
            end
            io.puts "<br><h3>Super Funktionen</h3>"
            io.puts "<div class='alert alert-info'>"
            io.puts "<button class='bu-clear-all btn btn-danger'><i class='fa fa-trash'></i>&nbsp;&nbsp;Alle Probleme löschen</button>"
            io.puts "<button class='bu-send-welcome-mail btn btn-warning'><i class='fa fa-envelope'></i>&nbsp;&nbsp;Willkommens-E-Mail versenden</button>"
            io.puts "</div>"
            io.puts "<div class='alert alert-info'>"
            io.puts "<div class='form-group'><input id='ti_recipients' class='form-control' placeholder='User suchen…' /><div class='recipient-input-dropdown' style='display: none;'></div></input></div>"
            io.puts "<div class='form-group row'><label for='ti_email' class='col-sm-1 col-form-label'>Name:</label><div class='col-sm-3'><input type='text' readonly class='form-control' id='ti_email' placeholder=''></div><div id='publish_message_btn_container'><button disabled id='bu_send_message' class='btn btn-outline-secondary'><i class='fa fa-plus'></i>&nbsp;&nbsp;<span>Hinzufügen</span></button>&nbsp;&nbsp;<button disabled id='bu_delete_message' class='btn btn-outline-secondary'><i class='fa fa-times'></i>&nbsp;&nbsp;<span>Entfernen</span></button></div></div>"
            io.puts "Hinweis: Die Änderungen werden erst nach dem Neuladen der Seite sichtbar.</div>"
            io.string
        end
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
