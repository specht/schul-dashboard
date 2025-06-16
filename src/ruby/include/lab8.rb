LAB8_KEYS = [
    :nr,
    :titel,
    :produkt,
    :orte,
    :reflexion1,
]

LAB8_KEY_LABELS = {
    :nr => 'Nr.',
    :titel => 'Titel',
    :produkt => 'Produkt',
    :orte => 'Orte, an denen gearbeitet werden soll',
    :reflexion1 => 'Protokoll und Reflexion des 1. Tages',
}

class Main < Sinatra::Base
    def parse_lab8_node(p)
        {
            :nr => p[:nr],
            :titel => p[:titel],
            :produkt => p[:produkt],
            :orte => p[:orte],
            :reflexion1 => p[:reflexion1],
            :members => [],
        }
    end

    def get_lab8_projekte
        projekte = {}
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User)
            RETURN p, u.email;
        END_OF_QUERY
            p = row['p']
            next if (p[:nr] || '').strip.empty?
            projekte[p[:nr]] ||= parse_projekt_node(p)
            projekte[p[:nr]][:members] << row['u.email']
        end

        projekte_list = []
        projekte.each_pair do |nr, p|
            p[:organized_by] = p[:organized_by].sort.uniq
            projekte_list << p
        end

        projekte_list.sort! do |a, b|
            (a[:nr].to_i == b[:nr].to_i) ?
            (a[:nr] <=> b[:nr]) :
            (a[:nr].to_i <=> b[:nr].to_i)
        end

        projekte_list
    end

    post '/api/get_lab8_projekte' do
        require_user!
        result = {:projekte => get_projekte()}
        respond(result)
    end    

    def get_my_lab8_projekt(email)
        require_user!
        result = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
            MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $email})
            WITH p
            MATCH (p)-[:BELONGS_TO]->(ou:User)
            RETURN p, ou.email;
        END_OF_QUERY
            if result.nil?
                result = row['p']
                result[:sus] = []
            end
            result[:sus] << row['ou.email']
        end
        if result.nil?
            {
                :sus => [@@user_info[email][:display_name]],
            }
        else
            if result[:sus]
                result[:sus].sort! do |a, b|
                    @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
                end
                result[:sus].map! { |teacher_email| @@user_info[teacher_email][:display_name_official] }
            end
            result
        end
    end

    def my_lab8_projekt_history(email)
        StringIO.open do |io|
            entries = neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a
                MATCH (eu:User)<-[:BY]-(pc:Lab8ProjektChange)-[:TO]->(p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $email})
                RETURN pc, eu.email
                ORDER BY pc.ts;
            END_OF_QUERY
            if entries.empty?
                io.puts "<em>(keine Einträge)</em>"
            else
                current_date = nil
                entries.each do |entry|
                    pc = entry['pc']
                    ts = pc[:ts]
                    ts_d = Time.at(ts)
                    entry_date = "#{WEEKDAYS_LONG[ts_d.wday]}, den #{ts_d.strftime("%d.%m.%Y")}"
                    if entry_date != current_date
                        io.puts "<div class='history_date'>#{entry_date}</div>"
                        if current_date.nil?
                            io.puts "<div class='history_entry'>Vorgang erstellt durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                        current_date = entry_date
                    end
                    if pc[:type] == 'update_value'
                        key = pc[:key].to_sym
                        value = pc[:value]
                        if value.nil?
                            io.puts "<div class='history_entry'>#{LAB8_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{LAB8_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                    elsif pc[:type] == 'invite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> zum Projekt eingeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'uninvite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> vom Projekt ausgeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'accept_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt angenommen</div>"
                    elsif pc[:type] == 'reject_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt abgelehnt</div>"
                    else
                        io.puts pc.to_json
                    end
                end
            end
            io.string
        end
    end

    post '/api/my_lab8_projekt_history' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if teacher_logged_in?
            sus_email = data[:sus_email] if data[:sus_email]
        end
        respond(:html => my_lab8_projekt_history(sus_email))
    end

    post '/api/update_lab8_projekt' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :nr,
                :titel,
                :produkt,
                :orte,
                :reflexion1,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        sus_email = data[:sus_email] if data[:sus_email]
        if sus_email != @session_user[:email]
            require_teacher!
        end
        assert(email_is_eligible_for_lab8?(@@user_info, sus_email))
        # unless user_with_role_logged_in?(:can_manage_projekttage)
            # assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        # end
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Lab8Projekt)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            LAB8_KEYS.each do |key|
                if data.include?(key)
                    value = data[key]
                    debug "#{key} => #{value}"
                    if (value || '') != (p[key] || '')
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, key => value})
                            MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $sus_email})
                            SET p.#{key.to_s} = $#{key.to_s}
                            RETURN p;
                        END_OF_QUERY
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :key => key, :value => value, :ts => ts, :editor_email => @session_user[:email]})
                            MATCH (eu:User {email: $editor_email})
                            MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(:User {email: $sus_email})
                            CREATE (eu)<-[:BY]-(c:Lab8ProjektChange)-[:TO]->(p)
                            SET c.type = 'update_value'
                            SET c.key = $key
                            SET c.value = $value
                            SET c.ts = $ts
                            RETURN p;
                        END_OF_QUERY
                    end
                end
            end
        end
        respond(:yay => 'sure', :result => get_my_lab8_projekt(sus_email))
    end

    def lab8_overview_rows
        assert(teacher_logged_in? || email_is_eligible_for_lab8?(@@user_info, @session_user[:email]))

        seen_sus = Set.new()
        projekt_hash = {}
        projekt_by_email = {}
        rows = []
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User)
            RETURN ID(p) AS id, p, u.email;
        END_OF_QUERY
            id = row['id']
            unless projekt_hash.include?(id)
                projekt_hash[id] = row['p']
                projekt_hash[id][:sus] = []
            end
            projekt_hash[id][:sus] << row['u.email']
            projekt_by_email[row['u.email']] = id
        end

        sus_index = 0
        @@user_info.keys.each do |email|
            next unless email_is_eligible_for_lab8?(@@user_info, email)
            next if seen_sus.include?(email)
            seen_sus << email
            projekt = nil
            if projekt_by_email[email]
                projekt = projekt_hash[projekt_by_email[email]]
            end
            if projekt
                projekt[:sus].each do |x|
                    seen_sus << x
                end
            end
            projekt ||= {}
            # STDERR.puts projekttage[:sus].to_yaml

            rows << {
                :email => email,
                :projekt => projekt,
                :sus_index => sus_index,
                :sus => (projekt[:sus] || [email]).map { |x| @@user_info[x][:display_name] }.join(' / '),
            }
        end
        rows.sort! do |a, b|
            a[:sus] <=> b[:sus]
        end
        rows
    end

    post '/api/lab8_overview' do
        assert(teacher_logged_in? || email_is_eligible_for_lab8?(@@user_info, @session_user[:email]))

        rows = lab8_overview_rows()
        rows.sort! do |a, b|
            a_nr = a[:projekt][:nr] || ''
            b_nr = b[:projekt][:nr] || ''
            a_sus_index = a[:sus_index]
            b_sus_index = b[:sus_index]
            a_nr.to_i == b_nr.to_i ? a_nr <=> b_nr : (a_nr.to_i == b_nr.to_i ? a_sus_index <=> b_sus_index : a_nr.to_i <=> b_nr.to_i)
        end

        respond(:rows => rows)
    end

    post '/api/send_invitation_for_lab8_projekt' do
        data = parse_request_data(:required_keys => [:sus_email, :name])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_lab8)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = @@user_info.keys.select do |email|
            @@user_info[email][:display_name] == data[:name]
        end.first
        assert(other_email != nil)
        assert(email_is_eligible_for_lab8?(@@user_info, sus_email))
        # assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Lab8Projekt)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size == 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (ou:User {email: $other_email})
                CREATE (p)-[:INVITATION_FOR]->(ou)
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:Lab8ProjektChange)-[:TO]->(p)
                SET c.type = 'invite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_invitation_for_lab8_projekt' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_lab8)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_eligible_for_lab8?(@@user_info, sus_email))
        # assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size > 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:Lab8ProjektChange)-[:TO]->(p)
                SET c.type = 'uninvite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    def print_pending_lab8_projekt_invitations_incoming(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User)<-[:BELONGS_TO]-(p:Lab8Projekt)-[r:INVITATION_FOR]->(u:User {email: $email})
            RETURN ou.email, ID(p) AS id;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            invitations = {}
            pending_invitations.each do |row|
                invitations[row['id']] ||= []
                invitations[row['id']] << row['ou.email']
            end
            invitations.values.each do |emails|
                io.puts "<p>Du hast eine Einladung von <strong>#{join_with_sep(emails.map { |x| @@user_info[x][:display_name]}, ', ', ' und ')}</strong> für ein gemeinsames Lab 8-Projekt erhalten.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-success bu-accept-invitation' data-email='#{emails.first}'><i class='fa fa-check'></i>&nbsp;&nbsp;Einladung annehmen</button>"
                io.puts "<button class='btn btn-danger bu-reject-invitation' data-email='#{emails.first}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung ablehnen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    def pending_lab8_projekt_invitations_outgoing(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User {email: $email})<-[:BELONGS_TO]-(p:Lab8Projekt)-[r:INVITATION_FOR]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            pending_invitations.each do |row|
                io.puts "<p>Du hast <strong>#{@@user_info[row['u.email']][:display_name]}</strong> für dein Lab 8-Projekt eingeladen.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-danger bu-delete-invitation' data-email='#{row['u.email']}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung zurücknehmen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    post '/api/pending_lab8_projekt_invitations_outgoing' do
        data = parse_request_data(:required_keys => [:sus_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_lab8)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        respond(:html => pending_lab8_projekt_invitations_outgoing(sus_email))
    end

    post '/api/accept_lab8_projekt_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_lab8)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_eligible_for_lab8?(@@user_info, sus_email))
        # assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Lab8Projekt)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r
                CREATE (p)-[:BELONGS_TO]->(u);
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c: Lab8ProjektChange)-[:TO]->(p)
                SET c.type = 'accept_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/reject_lab8_projekt_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_lab8)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(email_is_eligible_for_lab8?(@@user_info, sus_email))
        # assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Lab8Projekt)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Lab8Projekt)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c:Lab8ProjektChange)-[:TO]->(p)
                SET c.type = 'reject_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end
end

