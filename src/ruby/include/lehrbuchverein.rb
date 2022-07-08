class Main < Sinatra::Base
    def print_lehrbuchverein_table()
        assert(can_manage_bib_members_logged_in? || can_manage_bib_payment_logged_in?)
        temp = neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {lehrbuchverein_mitglied: true})
            RETURN u.email;
        END_OF_QUERY
        mitglieder = Set.new()
        temp.each do |row|
            mitglieder << row[:email]
        end
        temp = neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR}).map { |x| { :email => x['u.email'] } }
            MATCH (u:User)-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        paid = Set.new()
        temp.each do |row|
            paid << row[:email]
        end
        StringIO.open do |io|
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>Klasse</th>"
            if can_manage_bib_members_logged_in?
                io.puts "<th>Vereinsmitglied</th>"
            end
            io.puts "<th>Bezahlt für #{LEHRBUCHVEREIN_JAHR}/#{(LEHRBUCHVEREIN_JAHR % 100) + 1}</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            all_schueler = []
            @@klassen_order.each do |klasse|
                (@@schueler_for_klasse[klasse] || []).each do |email|
                    all_schueler << email
                end
            end
            all_schueler.sort! do |a, b|
                @@user_info[a][:last_name] == @@user_info[b][:last_name] ?
                (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
                (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
            end
            all_schueler.each do |email|
                unless can_manage_bib_members_logged_in?
                    next unless mitglieder.include?(email)
                end
                io.puts "<tr class='user_row' data-email='#{email}'>"
                user = @@user_info[email]
                io.puts "<td>#{user[:last_name]}</td>"
                io.puts "<td>#{user[:first_name]}</td>"
                io.puts "<td>#{tr_klasse(user[:klasse])}</td>"
                if can_manage_bib_members_logged_in?
                    io.puts "<td>"
                    if mitglieder.include?(email)
                        io.puts "<button class='btn btn-xs btn-success bu_toggle_vereinsmitglied'><i class='fa fa-check'></i>&nbsp;&nbsp;Vereinsmitglied</button>"
                    else
                        io.puts "<button class='btn btn-xs btn-outline-secondary bu_toggle_vereinsmitglied'><i class='fa fa-times'></i>&nbsp;&nbsp;kein Mitglied</button>"
                    end
                    io.puts "</td>"
                end
                io.puts "<td>"
                if paid.include?(email)
                    io.puts "<button class='btn btn-xs btn-success bu_toggle_paid' #{can_manage_bib_payment_logged_in? ? '' : 'disabled'}><i class='fa fa-check'></i>&nbsp;&nbsp;bezahlt</button>"
                else
                    io.puts "<button class='btn btn-xs btn-outline-secondary bu_toggle_paid' #{can_manage_bib_payment_logged_in? ? '' : 'disabled'}><i class='fa fa-times'></i>&nbsp;&nbsp;nicht bezahlt</button>"
                end
                io.puts "</td>"
            io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/toggle_lehrbuchverein_mitglied' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_members_logged_in?)
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.lehrbuchverein_mitglied = NOT COALESCE(u.lehrbuchverein_mitglied, FALSE)
            RETURN u.lehrbuchverein_mitglied;
        END_OF_QUERY
        respond(:ok => true, :lehrbuchverein_mitglied => result['u.lehrbuchverein_mitglied'])
    end

    post '/api/toggle_lehrbuchverein_paid' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_payment_logged_in?)
        paid = neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size > 0
            MATCH (u:User {email: $email})-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        if paid
            neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size
                MATCH (u:User {email: $email})-[r:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
                DELETE r;
            END_OF_QUERY
            respond(:ok => true, :paid => false)
        else
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email])
                MATCH (u:User {email: $email})
                MERGE (j:Lehrbuchvereinsjahr {jahr: $jahr})
                CREATE (u)-[:PAID_FOR]->(j)
                RETURN u.lehrbuchverein_mitglied;
            END_OF_QUERY
            respond(:ok => true, :paid => true)
        end
    end
end