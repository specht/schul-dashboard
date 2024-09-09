class Main < Sinatra::Base

    def check_has_technikamt(email)
        rows = neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})-[:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            RETURN CASE WHEN EXISTS((u)-[:HAS_AMT {amt: 'technikamt'}]->(v)) THEN true ELSE false END AS hasRelation;
        END_OF_QUERY
        return false if rows.empty?
        return rows.first['hasRelation']
    end

    def self.get_technikamt_users
        results = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)-[:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            RETURN u.email;
        END_OF_QUERY
        return results.map { |result| result["u.email"] } || []
    end

    def get_technikamt_users
        Main.get_technikamt_users()
    end

    def send_welcome_mail(recipients)
        for mail_adress in recipients do
            deliver_mail do
                to mail_adress
                bcc SMTP_FROM
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
        end
        respond(:ok => true)
    end


    post '/api/send_all_techpost_welcome_mail' do
        require_user_with_role!(:can_manage_tech_problems)
        recipients = get_technikamt_users()
        send_welcome_mail recipients
        display_name = @session_user[:display_name]
        deliver_mail do
            to WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Willkommens-E-Mail versandt!"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>#{display_name} hat soeben eine Willkommens-E-Mail an alle Technikämter versendet. Du musst/kannst nichts weiter tun, diese E-Mail dient nur als Info.</p>"
                io.string

            end
        end
    end

    post '/api/send_single_techpost_welcome_mail' do
        require_user_with_role!(:can_manage_tech_problems)
        data = parse_request_data(:required_keys => [:email],)
        recipients = []
        recipients.append(data[:email])
        send_welcome_mail recipients
    end

    post '/api/report_tech_problem' do
        require_user_with_role!(:can_report_tech_problems)
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
                io.puts "<p>Diese E-Mail dient nur als Bestätigung, du musst also nichts weiter tun.</p>"
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
        require_user_with_role!(:can_manage_tech_problems)
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
        require_user_with_role!(:can_manage_tech_problems)
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
        require_user_with_role!(:can_manage_tech_problems)
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
            x[:klasse] = tr_klasse(@@user_info[x[:email]][:klasse])
            x
        end
        respond(:tech_problems => problems)
    end

    post '/api/fix_tech_problem_admin' do
        require_user_with_role!(:can_manage_tech_problems)
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

    # post '/api/unfix_tech_problem_admin' do
    #     require_user_with_role!(:can_manage_tech_problems)
    #     data = parse_request_data(:required_keys => [:token])
    #     token = data[:token]
    #     problems = neo4j_query_expect_one(<<~END_OF_QUERY, :token => token)
    #         MATCH (v:TechProblem {token: $token})
    #         SET v.fixed = false
    #         SET v.not_fixed = false
    #         RETURN v;
    #     END_OF_QUERY
    #     respond(:ok => true)
    # end

    post '/api/not_fix_tech_problem_admin' do
        require_user_with_role!(:can_manage_tech_problems)
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
        require_user_with_role!(:can_report_tech_problems)
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
        require_user_with_role!(:can_report_tech_problems)
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
        require_user_with_role!(:can_manage_tech_problems)
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        data = neo4j_query(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})-[:BELONGS_TO]->(u:User)
            OPTIONAL MATCH (v:TechProblem {token: $token})-[:WILL_BE_FIXED_BY]->(f:User)
            SET v.mail_count = v.mail_count + 1
            RETURN v, u.email, f.email;
        END_OF_QUERY
        problem = data.first["v"]
        mail_adress = data.first["u.email"]
        femail = data.first["f.email"]

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
            reply_to femail

            subject "Neuigkeiten zu deinem Technikproblem"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Es gibt Neuigkeiten zu deinem Technikproblem:</p>"
                io.puts "<p>Das Problem hat jetzt den Status #{state}.#{comment}</p>"
                if femail
                    io.puts "<p>Zurzeit betreut #{@@user_info[femail][:display_name]} das Problem. Wende dich bei Fragen gerne an ihn/sie"
                end
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
                if femail
                    io.puts "<p>Zurzeit betreut #{@@user_info[femail][:display_name]} das Problem. Wende dich bei Fragen gerne an ihn/sie"
                end
                    # io.puts "<a href='#{WEBSITE_HOST}/techpost'>Probleme ansehen</a>"
                io.puts "<p>Viele Grüße<br>Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</p>"
                io.string

            end
        end
        respond(:ok => true)
    end

    post '/api/hide_tech_problem_admin' do
        require_user_with_role!(:can_manage_tech_problems)
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
        require_user_with_role!(:can_manage_tech_problems)
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
        require_user_with_role!(:can_manage_tech_problems)
        data = parse_request_data(:required_keys => [:token, :email])
        token = data[:token]
        email = data[:email]
        neo4j_query_expect_one(<<~END_OF_QUERY, :token => token, :email => email)
            MATCH (v:TechProblem {token: $token})
            MATCH (u:User {email: $email})
            MERGE (v)-[:WILL_BE_FIXED_BY]->(u)
            RETURN v;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/i_will_not_fix_tech_problem' do
        require_user_with_role!(:can_manage_tech_problems)
        data = parse_request_data(:required_keys => [:token])
        token = data[:token]
        neo4j_query(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})-[r:WILL_BE_FIXED_BY]->(u:User)
            DELETE r;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_tech_problem_admin' do
        require_user_with_role!(:can_manage_tech_problems)
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

    post '/api/kick_all_techposts_admin' do
        require_technikteam!
        neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)-[r:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            DELETE r;
        END_OF_QUERY
        (@@users_for_role[:technikamt] || []).each do |email|
            @@user_info[email][:roles].delete(:technikamt)
        end
        @@users_for_role[:technikamt] = Set.new()
        display_name = @session_user[:display_name]
        respond(:ok => true)
        deliver_mail do
            to WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Alle Technikämter entfernt"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>#{display_name} hat soeben alle Technikämter entfernt. Diese können deshalb keine Probleme mehr melden. Du musst/kannst nichts weiter tun, diese E-Mail dient nur als Info.</p>"
                io.string

            end
        end
    end

    post '/api/add_techpost' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        @@user_info[email][:roles] << :can_report_tech_problems
        @@users_for_role[:can_report_tech_problems] << email
        neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})
            MERGE (v:Techpost)
            MERGE (u)-[:HAS_AMT {amt: 'technikamt'}]->(v)
        END_OF_QUERY
        Main.update_techpost_groups()
        Main.update_mailing_lists()
        respond(:ok => true)
    end

    post '/api/delete_techpost' do
        require_technikteam!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        @@user_info[email][:roles].delete(:can_report_tech_problems)
        @@users_for_role[:can_report_tech_problems].delete(email)
        neo4j_query(<<~END_OF_QUERY, :email => email)
            MATCH (u:User {email: $email})-[r:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            DELETE r;
        END_OF_QUERY
        Main.update_techpost_groups()
        Main.update_mailing_lists()
        respond(:ok => true)
    end

    get '/api/get_tech_problem_pdf/*' do
        require_user_with_role!(:can_manage_tech_problems)
        token = request.path.sub('/api/get_tech_problem_pdf/', '')
        problems = neo4j_query(<<~END_OF_QUERY, :token => token)
            MATCH (v:TechProblem {token: $token})-[:BELONGS_TO]->(u:User)
            OPTIONAL MATCH (v:TechProblem {token: $token})-[:WILL_BE_FIXED_BY]->(f:User)
            RETURN v, u, f;
        END_OF_QUERY
        problem = problems.first["v"]
        user = problems.first["u"]
        fixer = problems.first["f"]
        fixed = "Behoben";
        progress = "In Bearbeitung";
        not_fixed = "Nicht behoben";
        see_comment = "Siehe Kommentar";
        current_state = "Unbekannt"
        if problem[:fixed]
            current_state = fixed
        elsif problem[:not_fixed]
            current_state = not_fixed
        elsif problem[:comment] && !problem[:fixed] && !problem[:not_fixed]
            current_state = see_comment
        else
            current_state = progress
        end
        today = Date.today.strftime('%d.%m.%Y')
        debug current_state
        pdf = StringIO.open do |io|
            io.puts "<style>"
            io.puts "body { font-family: Roboto; font-size: 12pt; line-height: 120%; }"
            io.puts "table { border-collapse: collapse; width: 100%; }"
            io.puts "td, th { border: 1px solid #dddddd; text-align: left; padding: 8px; }"
            io.puts ".pdf-space-above td {padding-top: 0.2em; }"
            io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
            io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
            io.puts ".footer { position: absolute; bottom: 0; width: 100%; }"
            io.puts "</style>"
            io.puts "<h1>Problemmeldung</h1>"
            io.puts "<br>"
            io.puts "<p>Es wurde folgendes Problem über das Dashboard #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME} gemeldet:</p>"
            io.puts "<table>"
            io.puts "<tbody>"
            io.puts "<tr>"
            io.puts "<td>Problem</td>"
            io.puts "<td><b>#{problem[:problem]}</b></td>"
            io.puts "</tr>"
            io.puts "<tr>"
            io.puts "<td>Gerät / Raum</td>"
            io.puts "<td><b>#{problem[:device]}</b></td>"
            io.puts "</tr>"
            io.puts "<tr>"
            io.puts "<td>Datum</td>"
            io.puts "<td><b>#{(Date.parse(problem[:date])).strftime('%d.%m.%Y')}</b></td>"
            io.puts "</tr>"
            io.puts "<tr>"
            io.puts "<td>Absender</td>"
            io.puts "<td><b>#{@@user_info[user[:email]][:display_name]}#{@@user_info[user[:email]][:klasse] ? " (#{@@user_info[user[:email]][:klasse]})" : ""}</b><br>#{user[:email]}</td>"
            io.puts "</tr>"
            if fixer
                io.puts "<tr>"
                io.puts "<td>Aktuelle Betreuung</td>"
                io.puts "<td><b>#{fixer ? @@user_info[fixer[:email]][:display_name] : ""}#{fixer ? @@user_info[fixer[:email]][:klasse] ? " (#{@@user_info[fixer[:email]][:klasse]})" : "" : ""}</b>#{fixer ? "<br>" + fixer[:email] : ""}</td>"
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td>Status</td>"
            io.puts "<td><b>#{current_state}</b></td>"
            io.puts "</tr>"
            if problem[:comment]
                io.puts "<tr>"
                io.puts "<td>Kommentar</td>"
                io.puts "<td><b>#{problem[:comment] ? "" + problem[:comment] + "": ""}</b></td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<div class='footer'>"
            io.puts "<p>Stand: <b>#{Time.now.strftime('%d.%m.%Y %H:%M')}</b></p>"
            io.puts "</div>"
            io.string
        end
        c = Curl.post('http://weasyprint:5001/pdf', {:data => pdf}.to_json)
        pdf = c.body_str
        respond_raw_with_mimetype(pdf, 'application/pdf')
    end

    def print_users_which_can_fix_tech_problems
        require_user_with_role!(:can_manage_tech_problems)
        StringIO.open do |io|
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
            io.puts "<table class='table narrow table-striped' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr><td>User</td><td>Auswählen</td></tr>"
            io.puts "</thead><tbody>"
            @@users_for_role[:can_manage_tech_problems].each do |user|
                display_name = @@user_info[user][:display_name]
                nc_login = @@user_info[user][:nc_login]
                klasse = tr_klasse(@@user_info[user][:klasse])
                io.puts "<tr><td><img src='#{NEXTCLOUD_URL}/index.php/avatar/#{nc_login}/256' class='icon avatar-md'>&nbsp;#{display_name}</td><td><button class='btn btn-xs btn-success bu-select-user-to-fix-problem' data-email='#{user}'><i class='fa fa-check'></i></button></td></tr>"
            end
            io.puts "</tbody></table>"
            io.puts "</div></div>"
            io.string
        end
    end

    def print_techpost_superuser()
        require_user_with_role!(:can_manage_tech_problems)
        problems = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:problem => x['v'], :email => x['u.email'], :femail => x['f.email']} }
            MATCH (v:TechProblem)-[:BELONGS_TO]->(u:User)
            OPTIONAL MATCH (v:TechProblem)-[:WILL_BE_FIXED_BY]->(f:User)
            RETURN v, u.email, f.email;
        END_OF_QUERY
        StringIO.open do |io|
            io.puts "<h3>Nutzer, die Probleme melden können</h3>"
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
            io.puts "<table class='table narrow table-striped' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr><td>User</td><td>Bearbeiten</td></tr>"
            io.puts "</thead><tbody>"
            get_technikamt_users.each do |technikamt|
                display_name = @@user_info[technikamt][:display_name]
                nc_login = @@user_info[technikamt][:nc_login]
                klasse = tr_klasse(@@user_info[technikamt][:klasse])
                id = @@user_info[technikamt][:id]
                io.puts "<tr><td><img src='#{NEXTCLOUD_URL}/index.php/avatar/#{nc_login}/256' class='icon avatar-md'>&nbsp;#{display_name} #{@@user_info[technikamt][:klasse] ? "(#{klasse})" : ""}</td>
                <td><a class='btn btn-xs btn-primary' href='mailto:#{technikamt}'><i class='fa fa-envelope'></i>&nbsp;&nbsp;E-Mail schreiben</a>&nbsp;
                <button class='btn btn-xs btn-success bu-send-single-welcome-mail' data-email='#{technikamt}'><i class='fa fa-envelope'></i>&nbsp;&nbsp;Willkommens-E-Mail versenden</button>&nbsp;
                <a class='btn btn-xs btn-secondary' href='/timetable/#{id}'><i class='fa fa-calendar'></i>&nbsp;&nbsp;Stundenplan</a>&nbsp;
                <button class='btn btn-xs btn-danger bu-edit-techpost' data-email='#{technikamt}'><i class='fa fa-trash'></i>&nbsp;&nbsp;Rechte entziehen</button>
                </td></tr>"
                
            end
            io.puts "</tbody></table>"
            io.puts "</div></div>"
            io.puts "<div class='json-data' style='display: none;'>"
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'><div class='alert alert-info'><code>#{get_technikamt_users()}</code></div></div></div>"
            unless problems == []
                io.puts "<br><h3>Aktuelle Probleme im JSON-Format</h3>"
                io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
                for problem in problems do
                    io.puts "<div class='alert alert-info'><code>#{problem.to_json}</code></div>"
                end
                io.puts "</div></div>"
            end
            io.puts "</div>"
            io.puts "<br><h3>Super Funktionen</h3>"
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
            io.puts "<button class='bu-clear-all btn btn-danger'><i class='fa fa-trash'></i>&nbsp;&nbsp;Alle Probleme löschen</button>&nbsp<button class='bu-kick-all btn btn-danger'><i class='fa fa-user-times'></i>&nbsp;&nbsp;Alle Technikamt-User entfernen</button>&nbsp<button class='bu-send-welcome-mail btn btn-warning'><i class='fa fa-envelope'></i>&nbsp;&nbsp;Willkommens-E-Mails versenden</button>&nbsp;<button class='bu-clear-aula-lights btn btn-danger'><i class='fa fa-lightbulb-o'></i>&nbsp;&nbsp;Plan der Aula-Scheinwerfer zurücksetzen</button>"
            io.puts "</div></div>"
            io.puts "<div class='row' style='margin-bottom: 15px;'><div class='col-md-12'>"
            io.puts "<div class='form-group'><input id='ti_recipients' class='form-control' placeholder='User suchen…' /><div class='recipient-input-dropdown' style='display: none;'></div></input></div>"
            io.puts "<div class='form-group row'><label for='ti_email' class='col-sm-1 col-form-label'>Name:</label><div class='col-sm-3'><input type='text' readonly class='form-control' id='ti_email' placeholder=''></div><div id='publish_message_btn_container'><button disabled id='bu_send_message' class='btn btn-outline-secondary'><i class='fa fa-plus'></i>&nbsp;&nbsp;<span>Hinzufügen</span></button></div></div>"
            io.puts "Hinweis: Die Änderungen werden erst nach dem Neuladen der Seite sichtbar.</div></div>"
            io.string
        end
    end

    def print_tablet_login()
        require_user_with_role!(:can_manage_tech_problems)
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
