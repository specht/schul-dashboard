class Main < Sinatra::Base

    def print_gev_table()
        assert(gev_logged_in?)
        temp = neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {ev: true})
            RETURN u.email;
        END_OF_QUERY
        gev = Set.new()
        temp.each do |row|
            gev << row[:email]
        end
        gev = gev.to_a.sort do |a, b|
            (@@user_info[a][:klasse] == @@user_info[b][:klasse]) ?
            (@@user_info[a][:last_name] <=> @@user_info[b][:last_name]) :
            ((KLASSEN_ORDER.index(@@user_info[a][:klasse]) || 0) <=> (KLASSEN_ORDER.index(@@user_info[b][:klasse]) || 0))
        end
        StringIO.open do |io|
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Elternvertreter:innen</th>"
            io.puts "<th>Klasse</th>"
            io.puts "<th></th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            gev.each do |email|
                io.puts "<tr class='user_row' data-email='#{email}'>"
                user = @@user_info[email]
                io.puts "<td>Eltern von #{user[:display_name]}</td>"
                io.puts "<td>#{tr_klasse(user[:klasse])}</td>"
                io.puts "<td><button class='btn btn-xs btn-danger bu-remove-ev'><i class='fa fa-trash'></i>&nbsp;&nbsp;Löschen</button></td>"
            io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/add_ev' do
        assert(gev_logged_in?)
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.ev = TRUE
            RETURN u.ev;
        END_OF_QUERY
        Main.update_mailing_lists()
        session_user_email = @session_user[:email]
        session_user_name = @session_user[:display_name]
        klasse_s = tr_klasse(@@user_info[email][:klasse])
        deliver_mail do
            to 'eltern.' + email
            bcc SMTP_FROM
            from SMTP_FROM
            cc session_user_email
            reply_to session_user_email

            subject "Eintragung als Elternvertreter:in"

            StringIO.open do |io|
                io.puts "<p>Sehr geehrte Eltern von #{@@user_info[email][:first_name]}</p>"
                io.puts "<p>Sie sind nun als Elternvertreter:in der Klasse #{klasse_s} im Dashboard registriert. Sie können somit folgende E-Mail-Verteiler nutzen, wenn Sie von Ihrer schulischen Eltern-E-Mail-Adresse aus schreiben:</p>"
                io.puts "<ul>"
                %w(eltern lehrer klasse).each do |key|
                    io.puts "<li><a href='mailto:#{key}.#{@@user_info[email][:klasse]}@mail.gymnasiumsteglitz.de'>#{key}.#{@@user_info[email][:klasse]}@mail.gymnasiumsteglitz.de</a> (#{key == 'klasse' ? 'alle Schülerinnen und Schüler' : "alle #{key.capitalize}"})</li>"
                end
                io.puts "</ul>"
                io.puts "<p>Viele Grüße,<br />#{session_user_name}</p>"
                io.string
            end
        end
        respond(:ok => true)
    end

    post '/api/remove_ev' do
        assert(gev_logged_in?)
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.ev = FALSE
            RETURN u.ev;
        END_OF_QUERY
        Main.update_mailing_lists()
        session_user_email = @session_user[:email]
        session_user_name = @session_user[:display_name]
        deliver_mail do
            to 'eltern.' + email
            bcc SMTP_FROM
            from SMTP_FROM
            cc session_user_email
            reply_to session_user_email

            subject "Aufgehoben: Eintragung als Elternvertreter:in"

            StringIO.open do |io|
                io.puts "<p>Sehr geehrte Eltern von #{@@user_info[email][:first_name]}</p>"
                io.puts "<p>Sie sind nun nicht mehr als Elternvertreter:in im Dashboard registriert. Sie können somit die E-Mail-Verteiler nicht mehr nutzen.</p>"
                io.puts "<p>Vielen Dank für Ihr Engagement!</p>"
                io.puts "<p>Viele Grüße,<br />#{session_user_name}</p>"
                io.string
            end
        end
        respond(:ok => true)
    end
end
