PK5_KEYS = [
    :themengebiet,
    :referenzfach,
    :betreuende_lehrkraft,
    :fas,
    :betreuende_lehrkraft_fas,
    :fragestellung
]

PK5_KEY_LABELS = {
    :themengebiet => 'Themengebiet',
    :referenzfach => 'Referenzfach',
    :betreuende_lehrkraft => 'Betreuende Lehrkraft im Referenzfach',
    :fas => 'fächerübergreifender Aspekt',
    :betreuende_lehrkraft_fas => 'Betreuende Lehrkraft im fächerübergreifenden Aspekt',
    :fragestellung => 'Fragestellung',
}

class Main < Sinatra::Base

    def get_my_pk5(email)
        require_user!
        result = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
            MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $email})
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
                result[:sus].map! { |email| @@user_info[email][:display_name_official] }
            end
            if result[:betreuende_lehrkraft]
                result[:betreuende_lehrkraft] = result[:betreuende_lehrkraft]
                result[:betreuende_lehrkraft_display_name] = @@user_info[result[:betreuende_lehrkraft]][:display_name_official]
                result[:betreuende_lehrkraft_is_confirmed] = result[:betreuende_lehrkraft] == result[:betreuende_lehrkraft_confirmed_by]
            end
            result
        end
    end

    def my_pk5_history(email)
        StringIO.open do |io|
            entries = neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a
                MATCH (eu:User)<-[:BY]-(pc:Pk5Change)-[:TO]->(p:Pk5)-[:BELONGS_TO]->(u:User {email: $email})
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
                            io.puts "<div class='history_entry'>Vorgang erstellt durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        end
                        current_date = entry_date
                    end
                    if pc[:type] == 'update_value'
                        key = pc[:key].to_sym
                        value = pc[:value]
                        if key == :betreuende_lehrkraft
                            value = (@@user_info[value] || {})[:display_name_official] || value
                        end
                        if value.nil?
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                        end
                    elsif pc[:type] == 'invite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> zur Gruppenprüfung eingeladen durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                    elsif pc[:type] == 'uninvite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> von der Gruppenprüfung ausgeladen durch #{@@user_info[entry['eu.email']][:display_name_official]}</div>"
                    elsif pc[:type] == 'accept_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zur Gruppenprüfung angenommen</div>"
                    elsif pc[:type] == 'reject_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zur Gruppenprüfung abgelehnt</div>"
                    elsif pc[:type] == 'accept_betreuung'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[entry['eu.email']][:display_name_official]}</strong> hat die Betreuung der Prüfung angenommen</div>"
                    elsif pc[:type] == 'reject_betreuung'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[entry['eu.email']][:display_name_official]}</strong> hat die Betreuung der Prüfung abgelehnt</div>"
                    else
                        io.puts pc.to_json
                    end
                end
            end
            io.string
        end
    end

    post '/api/my_pk5_history' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if user_with_role_logged_in?(:oko)
            sus_email = data[:sus_email] if data[:sus_email]
        end
        respond(:html => my_pk5_history(sus_email))
    end

    post '/api/update_pk5' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :themengebiet,
                :referenzfach,
                :betreuende_lehrkraft,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if user_with_role_logged_in?(:oko)
            sus_email = data[:sus_email] if data[:sus_email]
        end
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Pk5)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            [:themengebiet, :referenzfach, :betreuende_lehrkraft].each do |key|
                if data.include?(key)
                    value = data[key]
                    if key == :referenzfach
                        all_faecher = File.read('/data/pk5/faecher.txt').split("\n").map { |x| x.strip }.reject { |x| x.empty? }
                        value = nil unless all_faecher.include?(value)
                    end
                    if key == :betreuende_lehrkraft
                        value = @@users_for_role[:teacher].select do |email|
                            @@user_info[email][:display_name_official] == value
                        end.first
                    end
                    debug "#{key} => #{value}"
                    if (value || '') != (p[key] || '')
                        if key == :betreuende_lehrkraft
                            # reset confirmation if value has changed
                            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})
                                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                                REMOVE p.#{key.to_s}_confirmed_by
                                RETURN p;
                            END_OF_QUERY
                        end
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, key => value})
                            MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                            SET p.#{key.to_s} = $#{key.to_s}
                            RETURN p;
                        END_OF_QUERY
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :key => key, :value => value, :ts => ts, :editor_email => @session_user[:email]})
                            MATCH (eu:User {email: $editor_email})
                            MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $sus_email})
                            CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
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
        respond(:yay => 'sure', :result => get_my_pk5(sus_email))
    end

    def print_pk5_overview
        require_teacher!
        StringIO.open do |io|
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Prüfungskandidat:innen</th>"
            io.puts "<th>Themengebiet</th>"
            io.puts "<th>Referenzfach</th>"
            io.puts "<th>Lehrkraft</th>"
            io.puts "<th>fächerübergreifender Aspekt</th>"
            io.puts "<th>Lehrkraft</th>"
            # io.puts "<th>Fragestellung</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            seen_sus = Set.new()
            pk5_hash = {}
            pk5_by_email = {}
            rows = []
            neo4j_query(<<~END_OF_QUERY).each do |row|
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User)
                RETURN ID(p) AS id, p, u.email;
            END_OF_QUERY
                id = row['id']
                unless pk5_hash.include?(id)
                    pk5_hash[id] = row['p']
                    pk5_hash[id][:sus] = []
                end
                pk5_hash[id][:sus] << row['u.email']
                pk5_by_email[row['u.email']] = id
            end

            @@schueler_for_klasse[PK5_CURRENT_KLASSE].each.with_index do |email, sus_index|
                next if seen_sus.include?(email)
                seen_sus << email
                pk5 = nil
                if pk5_by_email[email]
                    pk5 = pk5_hash[pk5_by_email[email]]
                end
                if pk5
                    pk5[:sus].each do |x|
                        seen_sus << x
                    end
                end
                pk5 ||= {}
                row_s = StringIO.open do |io2|
                    io2.puts "<tr data-email='#{email}'>"
                    io2.puts "<td>#{(pk5[:sus] || [email]).map { |x| @@user_info[x][:display_name]}.join(', ')}</td>"
                    io2.puts "<td>#{CGI.escapeHTML(pk5[:themengebiet] || '–')}</td>"
                    io2.puts "<td>#{CGI.escapeHTML(pk5[:referenzfach] || '–')}</td>"
                    if pk5[:betreuende_lehrkraft] == @session_user[:email]
                        if pk5[:betreuende_lehrkraft_confirmed_by] != @session_user[:email]
                            if $pk5.get_current_phase >= 2
                                io2.puts "<td><i class='fa fa-clock-o'></i>&nbsp;&nbsp;<span class='hl'>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</span> <em>Anfrage erhalten &ndash; bitte bestätigen oder ablehnen</em></td>"
                            else
                                io2.puts "<td><i class='fa fa-clock-o'></i>&nbsp;&nbsp;#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</td>"
                            end
                        else
                            io2.puts "<td>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</td>"
                        end
                    else
                        if pk5[:betreuende_lehrkraft_confirmed_by] != pk5[:betreuende_lehrkraft]
                            io2.puts "<td><i class='fa fa-clock-o'></i>&nbsp;&nbsp;#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</td>"
                        else
                            io2.puts "<td>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</td>"
                        end
                    end
                    io2.puts "<td>#{CGI.escapeHTML(pk5[:fas] || '–')}</td>"
                    io2.puts "<td>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft_fas]] || {})[:display_name_official]) || '–')}</td>"
                    # io2.puts "<td>#{CGI.escapeHTML(pk5[:fragestellung] || '–')}</td>"
                    io2.puts "</tr>"
                    io2.string
                end
                rows << {:html => row_s, :email => email, :pk5 => pk5, :sus_index => sus_index}
            end
            rows.sort! do |a, b|
                a_primary = a[:pk5][:betreuende_lehrkraft] == @session_user[:email]
                b_primary = b[:pk5][:betreuende_lehrkraft] == @session_user[:email]
                a_secondary = a[:pk5][:betreuende_lehrkraft_fas] == @session_user[:email]
                b_secondary = b[:pk5][:betreuende_lehrkraft_fas] == @session_user[:email]
                a_sus_index = a[:sus_index]
                b_sus_index = b[:sus_index]
                (a_primary == b_primary) ? (a_secondary == b_secondary ? (a_sus_index <=> b_sus_index) : (a_secondary ? -1 : 1)) : (a_primary ? -1 : 1)
            end
            rows.each do |row|
                io.puts row[:html]
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/send_invitation_for_pk5' do
        data = parse_request_data(:required_keys => [:sus_email, :name])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:oko)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = @@user_info.keys.select do |email|
            @@user_info[email][:display_name] == data[:name]
        end.first
        assert(other_email != nil)
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Pk5)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size == 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (ou:User {email: $other_email})
                CREATE (p)-[:INVITATION_FOR]->(ou)
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
                SET c.type = 'invite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_invitation_for_pk5' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:oko)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size > 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
                SET c.type = 'uninvite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    def print_pending_pk5_invitations_incoming(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User)<-[:BELONGS_TO]-(p:Pk5)-[r:INVITATION_FOR]->(u:User {email: $email})
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
                io.puts "<p>Du hast eine Einladung von <strong>#{join_with_sep(emails.map { |x| @@user_info[x][:display_name]}, ', ', ' und ')}</strong> für eine Gruppenprüfung erhalten.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-success bu-accept-invitation' data-email='#{emails.first}'><i class='fa fa-check'></i>&nbsp;&nbsp;Einladung annehmen</button>"
                io.puts "<button class='btn btn-danger bu-reject-invitation' data-email='#{emails.first}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung ablehnen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    def pending_pk5_invitations_outgoing(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User {email: $email})<-[:BELONGS_TO]-(p:Pk5)-[r:INVITATION_FOR]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            pending_invitations.each do |row|
                io.puts "<p>Du hast <strong>#{@@user_info[row['u.email']][:display_name]}</strong> für eine Gruppenprüfung eingeladen.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-danger bu-delete-invitation' data-email='#{row['u.email']}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung zurücknehmen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    post '/api/pending_pk5_invitations_outgoing' do
        data = parse_request_data(:required_keys => [:sus_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:oko)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        respond(:html => pending_pk5_invitations_outgoing(sus_email))
    end

    post '/api/accept_5pk_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:oko)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Pk5)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r
                CREATE (p)-[:BELONGS_TO]->(u);
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
                SET c.type = 'accept_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/reject_5pk_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:oko)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Pk5)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
                SET c.type = 'reject_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/accept_or_reject_pk5_betreuung' do
        data = parse_request_data(:required_keys => [:email, :accept])
        sus_email = data[:email]
        accept = (data[:accept] == 'true')

        pk5 = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['pk5']
            MATCH (pk5:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
            RETURN pk5;
        END_OF_QUERY

        assert(pk5[:betreuende_lehrkraft] == @session_user[:email])
        assert(pk5[:betreuende_lehrkraft_confirmed_by] != @session_user[:email])
        result = get_remaining_pk5_projects_for_teacher()
        assert(result[:left] > 0)

        if accept
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :lehrer_email => @session_user[:email]})
                MATCH (pk5:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                SET pk5.betreuende_lehrkraft_confirmed_by = $lehrer_email
                RETURN pk5;
            END_OF_QUERY
        else
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})
                MATCH (pk5:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
                REMOVE pk5.betreuende_lehrkraft
                RETURN pk5;
            END_OF_QUERY
        end

        all_emails = []
        neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email}).each do |row|
            MATCH (pk5:Pk5)-[:BELONGS_TO]->(u:User {email: $sus_email})
            WITH pk5
            MATCH (pk5)-[:BELONGS_TO]->(ou:User)
            RETURN ou.email AS email;
        END_OF_QUERY
            all_emails << row['email']
        end
        all_emails.uniq!
        STDERR.puts all_emails.to_yaml
        lehrer_email = @session_user[:email]
        lehrer_display_name = @session_user[:display_name_official]

        deliver_mail do
            to all_emails
            cc lehrer_email
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Betreuung im Referenzfach #{accept ? 'angenommen' : 'abgelehnt'}"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                if accept
                    io.puts "<p>Dies ist eine automatische Benachrichtung darüber, dass #{lehrer_display_name} die Anfrage zur Betreuung #{all_emails.size == 1 ? 'deiner' : 'eurer'} 5. PK <b>angenommen</b> hat.</p>"
                else
                    io.puts "<p>Dies ist eine automatische Benachrichtung darüber, dass #{lehrer_display_name} die Anfrage zur Betreuung #{all_emails.size == 1 ? 'deiner' : 'eurer'} 5. PK <b>abgelehnt</b> hat.</p>"
                end
                io.puts "<p>Um den aktuellen Stand deiner 5. PK-Planung zu erfahren, schau einfach im Dashboard nach.</p>"
                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                io.string
            end
        end

        ts = Time.now.to_i
        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :editor_email => @session_user[:email], :type => accept ? 'accept_betreuung' : 'reject_betreuung'})
            MATCH (eu:User {email: $editor_email})
            MATCH (p:Pk5)-[:BELONGS_TO]->(:User {email: $sus_email})
            CREATE (eu)<-[:BY]-(c:Pk5Change)-[:TO]->(p)
            SET c.type = $type
            SET c.ts = $ts
            RETURN p;
        END_OF_QUERY

        respond(:yay => 'sure')
    end

    def get_remaining_pk5_projects_for_teacher
        return {} unless teacher_logged_in?
        invited = 0
        accepted = 0
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Pk5)-[:BELONGS_TO]->(u:User)
            WITH DISTINCT p
            RETURN p;
        END_OF_QUERY
            p = row['p']
            if p[:betreuende_lehrkraft] == @session_user[:email]
                invited += 1
                if p[:betreuende_lehrkraft] == p[:betreuende_lehrkraft_confirmed_by]
                    accepted += 1
                end
            end
        end
        left = 5 - accepted
        {:invited => invited, :accepted => accepted, :left => left}
    end

    def get_invited_and_accepted_pk5_for_teacher
        return '' unless teacher_logged_in?
        result = get_remaining_pk5_projects_for_teacher()
        invited = result[:invited]
        accepted = result[:accepted]
        left = result[:left]
        "Sie haben bisher #{accepted == 0 ? 'keine' : accepted} Prüfung#{accepted == 1 ? '' : 'en'} angenommen und #{(invited - accepted) == 0 ? 'keine' : (invited - accepted)} ausstehende Anfrage#{(invited - accepted) == 1 ? '' : 'n'}. Sie können insgesamt höchstens fünf Prüfungen annehmen, also nach aktuellem Stand noch #{left} Prüfung#{left == 1 ? '' : 'en'}."
    end
end

