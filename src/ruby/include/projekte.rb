PROJEKTTAGE_KEYS = [
    :name,
    :ziel,
    :teilnehmer_min,
    :teilnehmer_max,
    :klassenstufe_min,
    :klassenstufe_max,
    :grobplanung1,
    :grobplanung2,
    :grobplanung3,
    :produkt,
    :praesentationsidee,
    :material,
    :kosten_finanzierungsidee,
    :lehrkraft_wunsch,
    :raumwunsch,
    :planung_exkursion,
    :planung_tablets,
]

PROJEKTTAGE_KEY_LABELS = {
    :name => 'Name des Projekts',
    :ziel => 'Ziel',
    :teilnehmer_min => 'Gewünschte Teilnehmerzahl (min.)',
    :teilnehmer_max => 'Gewünschte Teilnehmerzahl (max.)',
    :klassenstufe_min => 'Klassenstufe (min.)',
    :klassenstufe_max => 'Klassenstufe (max.)',
    :grobplanung1 => 'Grobplanung 1. Tag (Donnerstag)',
    :grobplanung2 => 'Grobplanung 2. Tag (Freitag)',
    :grobplanung3 => 'Grobplanung 3. Tag (Montag)',
    :produkt => 'Produkt, das erarbeitet wird',
    :praesentationsidee => 'Präsentationsidee für das Schulfest',
    :material => 'Benötigtes Material',
    :kosten_finanzierungsidee => 'Entstehende Kosten und Finanzierungsidee',
    :lehrkraft_wunsch => 'Wunsch für betreuende Lehrkraft',
    :raumwunsch => 'Raumwunsch',
    :planung_exkursion => 'Planung Exkursion',
    :planung_tablets => 'Benötigte Tablets',
}

class Main < Sinatra::Base
    def get_my_projekttage(email)
        require_user!
        result = nil
        neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
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
            result[:teilnehmer_min] ||= 1
            result[:teilnehmer_min] ||= 20
            result[:klassenstufe_min] ||= 5
            result[:klassenstufe_max] ||= 9
            if result[:sus]
                result[:sus].sort! do |a, b|
                    @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
                end
                result[:sus].map! { |teacher_email| @@user_info[teacher_email][:display_name_official] }
            end
            result
        end
    end

    def my_projekttage_history(email)
        StringIO.open do |io|
            entries = neo4j_query(<<~END_OF_QUERY, {:email => email}).to_a
                MATCH (eu:User)<-[:BY]-(pc:ProjekttageChange)-[:TO]->(p:Projekttage)-[:BELONGS_TO]->(u:User {email: $email})
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
                            io.puts "<div class='history_entry'>#{PROJEKTTAGE_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{PROJEKTTAGE_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                    elsif pc[:type] == 'invite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> zum Projekt eingeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'uninvite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> vom Projekt ausgeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'accept_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt angenommen</div>"
                    elsif pc[:type] == 'reject_invitation'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:email]][:display_name]}</strong> hat die Einladung zum Projekt abgelehnt</div>"
                    elsif pc[:type] == 'comment'
                        io.puts "<div class='history_entry'>kommentiert von #{@@user_info[entry['eu.email']][:display_name_official_dativ]}: <b>#{pc[:comment].gsub("\n", '<br>')}</b></div>"
                    else
                        io.puts pc.to_json
                    end
                end
            end
            io.string
        end
    end

    post '/api/my_projekttage_history' do
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
        respond(:html => my_projekttage_history(sus_email))
    end

    post '/api/update_projekttage' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :name,
                :ziel,
                :teilnehmer_min,
                :teilnehmer_max,
                :klassenstufe_min,
                :klassenstufe_max,
                :grobplanung1,
                :grobplanung2,
                :grobplanung3,
                :produkt,
                :praesentationsidee,
                :material,
                :kosten_finanzierungsidee,
                :lehrkraft_wunsch,
                :raumwunsch,
                :planung_exkursion,
                :planung_tablets,
            ],
            :types => {
                :teilnehmer_min => Integer,
                :teilnehmer_max => Integer,
                :klassenstufe_min => Integer,
                :klassenstufe_max => Integer,
            },
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        sus_email = data[:sus_email] if data[:sus_email]
        if sus_email != @session_user[:email]
            require_teacher!
        end
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        unless user_with_role_logged_in?(:can_manage_projekttage)
            assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        end
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Projekttage)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            PROJEKTTAGE_KEYS.each do |key|
                if data.include?(key)
                    value = data[key]
                    debug "#{key} => #{value}"
                    if (value || '') != (p[key] || '')
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, key => value})
                            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                            SET p.#{key.to_s} = $#{key.to_s}
                            RETURN p;
                        END_OF_QUERY
                        neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :key => key, :value => value, :ts => ts, :editor_email => @session_user[:email]})
                            MATCH (eu:User {email: $editor_email})
                            MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                            CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
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
        respond(:yay => 'sure', :result => get_my_projekttage(sus_email))
    end

    def projekttage_overview_rows
        assert(teacher_logged_in? || (schueler_logged_in? && @session_user[:klasse] == PROJEKTTAGE_CURRENT_KLASSE))

        seen_sus = Set.new()
        projekttage_hash = {}
        projekttage_by_email = {}
        rows = []
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User)
            RETURN ID(p) AS id, p, u.email;
        END_OF_QUERY
            id = row['id']
            unless projekttage_hash.include?(id)
                projekttage_hash[id] = row['p']
                projekttage_hash[id][:sus] = []
            end
            projekttage_hash[id][:sus] << row['u.email']
            projekttage_by_email[row['u.email']] = id
        end

        @@schueler_for_klasse[PROJEKTTAGE_CURRENT_KLASSE].each.with_index do |email, sus_index|
            next if seen_sus.include?(email)
            seen_sus << email
            projekttage = nil
            if projekttage_by_email[email]
                projekttage = projekttage_hash[projekttage_by_email[email]]
            end
            if projekttage
                projekttage[:sus].each do |x|
                    seen_sus << x
                end
            end
            projekttage ||= {}
            # STDERR.puts projekttage[:sus].to_yaml

            rows << {
                :email => email,
                :projekttage => projekttage,
                :sus_index => sus_index,
                :sus => (projekttage[:sus] || [email]).map { |x| @@user_info[x][:last_name] + ', ' + @@user_info[x][:first_name]}.join(' / '),
            }
        end
        rows
    end

    post '/api/projekttage_overview' do
        assert(teacher_logged_in? || (schueler_logged_in? && @session_user[:klasse] == PROJEKTTAGE_CURRENT_KLASSE))

        rows = projekttage_overview_rows()
        rows.sort! do |a, b|
            a_sus_index = a[:sus_index]
            b_sus_index = b[:sus_index]
            a_sus_index <=> b_sus_index
        end

        respond(:rows => rows)
    end

    post '/api/send_invitation_for_projekttage' do
        data = parse_request_data(:required_keys => [:sus_email, :name])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = @@user_info.keys.select do |email|
            @@user_info[email][:display_name] == data[:name]
        end.first
        assert(other_email != nil)
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Projekttage)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size == 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (ou:User {email: $other_email})
                CREATE (p)-[:INVITATION_FOR]->(ou)
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'invite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
    end

    post '/api/delete_invitation_for_projekttage' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                RETURN r;
            END_OF_QUERY
            assert(rows.size > 0)
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                MATCH (p)-[r:INVITATION_FOR]->(ou:User {email: $other_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :ts => ts, :other_email => other_email, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $sus_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'uninvite_sus'
                SET c.other_email = $other_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    def print_pending_projekttage_invitations_incoming(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User)<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $email})
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
                io.puts "<p>Du hast eine Einladung von <strong>#{join_with_sep(emails.map { |x| @@user_info[x][:display_name]}, ', ', ' und ')}</strong> für ein gemeinsames Projekt erhalten.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-success bu-accept-invitation' data-email='#{emails.first}'><i class='fa fa-check'></i>&nbsp;&nbsp;Einladung annehmen</button>"
                io.puts "<button class='btn btn-danger bu-reject-invitation' data-email='#{emails.first}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung ablehnen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    def pending_projekttage_invitations_outgoing(user_email)
        pending_invitations = neo4j_query(<<~END_OF_QUERY, {:email => user_email}).to_a
            MATCH (ou:User {email: $email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User)
            RETURN u.email;
        END_OF_QUERY
        return '' if pending_invitations.empty?
        StringIO.open do |io|
            io.puts "<hr>"
            pending_invitations.each do |row|
                io.puts "<p>Du hast <strong>#{@@user_info[row['u.email']][:display_name]}</strong> für dein Projekt eingeladen.</p>"
                io.puts "<p>"
                io.puts "<button class='btn btn-danger bu-delete-invitation' data-email='#{row['u.email']}'><i class='fa fa-times'></i>&nbsp;&nbsp;Einladung zurücknehmen</button>"
                io.puts "</p>"
            end
            io.puts "<hr>"
            io.string
        end
    end

    post '/api/pending_projekttage_invitations_outgoing' do
        data = parse_request_data(:required_keys => [:sus_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        respond(:html => pending_projekttage_invitations_outgoing(sus_email))
    end

    post '/api/accept_projekttage_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_project_wifi_access)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r
                CREATE (p)-[:BELONGS_TO]->(u);
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c: ProjekttageChange)-[:TO]->(p)
                SET c.type = 'accept_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/reject_projektage_invitation' do
        data = parse_request_data(:required_keys => [:sus_email, :other_email])
        sus_email = data[:sus_email]
        if user_with_role_logged_in?(:can_manage_projekttage)
        elsif user_with_role_logged_in?(:schueler)
            assert(sus_email == @session_user[:email])
        else
            raise 'nope'
        end
        other_email = data[:other_email]
        assert(@@user_info.include?(other_email))
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        assert(!$projekttage.phases[$projekttage.get_current_phase][:flags].include?(:no_sus_edit))
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email})
                MATCH (ou:User {email: $other_email})<-[:BELONGS_TO]-(p:Projekttage)-[r:INVITATION_FOR]->(u:User {email: $sus_email})
                DELETE r;
            END_OF_QUERY
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :other_email => other_email, :ts => ts, :editor_email => @session_user[:email]})
                MATCH (eu:User {email: $editor_email})
                MATCH (p:Projekttage)-[:BELONGS_TO]->(:User {email: $other_email})
                CREATE (eu)<-[:BY]-(c:ProjekttageChange)-[:TO]->(p)
                SET c.type = 'reject_invitation'
                SET c.email = $sus_email
                SET c.ts = $ts
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure')
    end

    post '/api/send_projekttage_comment' do
        data = parse_request_data(:required_keys => [:sus_email, :comment], :max_body_length => 1024 * 1024, :max_string_length => 1024 * 1024, :max_value_lengths => {:comment => 1024 * 1024})
        sus_email = data[:sus_email]
        assert(user_with_role_logged_in?(:can_manage_projekttage))
        assert(@@user_info[sus_email][:klasse] == PROJEKTTAGE_CURRENT_KLASSE)
        ts = Time.now.to_i
        transaction do
            neo4j_query(<<~END_OF_QUERY, {:ts => ts, :sus_email => sus_email, :comment => data[:comment], :email => @session_user[:email]})
                MATCH (tu:User {email: $email})
                WITH tu
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                CREATE (p)<-[:TO]-(c:ProjekttageChange {type: 'comment', comment: $comment, ts: $ts})-[:BY]->(tu);
            END_OF_QUERY
            emails = neo4j_query(<<~END_OF_QUERY, {:sus_email => sus_email}).map { |x| x['ou.email'] }
                MATCH (p:Projekttage)-[:BELONGS_TO]->(u:User {email: $sus_email})
                WITH p
                MATCH (p)-[:BELONGS_TO]->(ou:User)
                RETURN ou.email;
            END_OF_QUERY
            session_user_email = @session_user[:email]
            deliver_mail do
                to emails
                cc @@users_for_role[:can_manage_projekttage].to_a.sort
                bcc SMTP_FROM
                from SMTP_FROM
                reply_to session_user_email

                subject "Kommentar zu deiner Projektplanung"

                StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>#{@@user_info[session_user_email][:display_name_official]} hat einen Kommentar zum aktuellen Planungsstand deines Projektes hinterlassen:</p>"
                    io.puts "<p>#{data[:comment].gsub('\n', '<br>')}</p>"
                    io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                    io.string
                end
            end
        end
        respond(:yay => 'sure')
    end
end

