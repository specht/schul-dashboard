class Main < Sinatra::Base
    # returns bits 1 for paid, 2 for zahlungsbefreit, 4 for lehrmittelfreiheit
    def determine_lehrmittelverein_state_for_email(email)
        result = 0
        temp = neo4j_query(<<~END_OF_QUERY, {:email => email})
            MATCH (u:User {email: $email, lmv_no_pay: true})
            RETURN u.email;
        END_OF_QUERY
        result += 2 if temp.size > 0
        result += 4 if [5, 6].include?(((@@user_info[email] || {})[:klasse] || '').to_i)
        temp = neo4j_query(<<~END_OF_QUERY, {:email => email, :jahr => LEHRBUCHVEREIN_JAHR})
            MATCH (u:User {email: $email})-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        result += 1 if temp.size > 0
        return result
    end

    def can_checkout_books(email)
        determine_lehrmittelverein_state_for_email(email) > 0
    end

    def print_lehrbuchverein_table()
        assert(can_manage_bib_members_logged_in? || can_manage_bib_payment_logged_in?)
        temp = neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {lmv_no_pay: true})
            RETURN u.email;
        END_OF_QUERY
        no_pay = Set.new()
        temp.each do |row|
            no_pay << row[:email]
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
                io.puts "<th>Bezahlt für #{LEHRBUCHVEREIN_JAHR}/#{(LEHRBUCHVEREIN_JAHR % 100) + 1}</th>"
                io.puts "<th>Zahlungsbefreit</th>"
                io.puts "<th>Selbstzahler</th>"
            end
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            all_schueler = []
            @@klassen_order.each do |klasse|
                (@@schueler_for_klasse[klasse] || []).each do |email|
                    all_schueler << email
                end
            end
            # all_schueler.sort! do |a, b|
            #     @@user_info[a][:last_name] == @@user_info[b][:last_name] ?
            #     (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
            #     (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
            # end
            all_schueler.each do |email|
                unless can_manage_bib_members_logged_in?
                    next unless mitglieder.include?(email)
                end
                state = 0
                state += 1 if paid.include?(email)
                state += 2 if no_pay.include?(email)
                state += 4 if [5, 6].include?(((@@user_info[email] || {})[:klasse] || '').to_i)
                io.puts "<tr class='user_row' data-email='#{email}'>"
                user = @@user_info[email]
                io.puts "<td>#{user[:last_name]}</td>"
                io.puts "<td>#{user[:first_name]}</td>"
                io.puts "<td>#{tr_klasse(user[:klasse])}</td>"
                if can_manage_bib_members_logged_in?
                    io.puts "<td>"
                    io.puts "<button class='btn btn-xs #{((state >> 0) & 1) == 1 ? 'btn-success' : 'btn-outline-secondary'} bu_toggle_paid'>bezahlt für #{LEHRBUCHVEREIN_JAHR}/#{(LEHRBUCHVEREIN_JAHR % 100) + 1}</button>"
                    io.puts "</td>"
                    io.puts "<td>"
                    io.puts "<button class='btn btn-xs #{(((state >> 1) & 1) == 1) || (((state >> 2) & 1) == 1) ? 'btn-primary' : 'btn-outline-secondary'} bu_toggle_no_pay' #{state & 4 == 4 ? 'disabled' : ''}>zahlungsbefreit</button>"
                    io.puts "</td>"
                    io.puts "<td>"
                    io.puts "<button class='btn btn-xs #{state == 0 ? 'btn-danger' : 'btn-outline-secondary'} bu_no_book_for_you disabled'>Selbstzahler</button>"
                    io.puts "</td>"
                end
            io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/toggle_lehrbuchverein_no_pay' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_members_logged_in?)
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.lmv_no_pay = NOT COALESCE(u.lmv_no_pay, FALSE)
            RETURN u.lmv_no_pay;
        END_OF_QUERY
        respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
    end

    post '/api/toggle_lehrbuchverein_paid' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        assert(can_manage_bib_members_logged_in?)
        paid = neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size > 0
            MATCH (u:User {email: $email})-[:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
            RETURN u.email;
        END_OF_QUERY
        if paid
            neo4j_query(<<~END_OF_QUERY, {:jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email]}).size
                MATCH (u:User {email: $email})-[r:PAID_FOR]->(j:Lehrbuchvereinsjahr {jahr: $jahr})
                DELETE r;
            END_OF_QUERY
            respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
        else
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :jahr => LEHRBUCHVEREIN_JAHR, :email => data[:email])
                MATCH (u:User {email: $email})
                MERGE (j:Lehrbuchvereinsjahr {jahr: $jahr})
                CREATE (u)-[:PAID_FOR]->(j)
                RETURN u.lehrbuchverein_mitglied;
            END_OF_QUERY
            respond(:ok => true, :state => determine_lehrmittelverein_state_for_email(email))
        end
    end
end
