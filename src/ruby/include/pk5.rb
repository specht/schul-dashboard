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
    :fragestellung => 'Problemorientierte Frage-/Themenstellung',
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
                result[:sus].map! { |teacher_email| @@user_info[teacher_email][:display_name_official] }
            end
            if result[:betreuende_lehrkraft]
                result[:betreuende_lehrkraft_display_name] = @@user_info[result[:betreuende_lehrkraft]][:display_name_official]
                result[:betreuende_lehrkraft_is_confirmed] = result[:betreuende_lehrkraft] == result[:betreuende_lehrkraft_confirmed_by]
            end
            if result[:betreuende_lehrkraft_fas]
                result[:betreuende_lehrkraft_fas_display_name] = @@user_info[result[:betreuende_lehrkraft_fas]][:display_name_official]
            end
            extra_consultations = {}
            (result[:extra_consultations] || '').split(',').each do |shorthand|
                teacher_email = @@shorthands[shorthand]
                extra_consultations[teacher_email] = {:want => true, :display_name => @@user_info[teacher_email][:display_name_official], :display_name_dativ => @@user_info[teacher_email][:display_name_official_dativ]}
            end
            if result[:referenzfach]
                result[:referenzfach_fbl] = @@pk5_faecher[result[:referenzfach]].map { |x| @@user_info[x][:display_name_official]}.join(', ')
                @@pk5_faecher[result[:referenzfach]].each do |teacher_email|
                    extra_consultations[teacher_email] ||= {:want => false, :display_name => @@user_info[teacher_email][:display_name_official], :display_name_dativ => @@user_info[teacher_email][:display_name_official_dativ]}
                end
            end
            if result[:fas]
                result[:fas_fbl] = @@pk5_faecher[result[:fas]].map { |x| @@user_info[x][:display_name_official]}.join(', ')
                @@pk5_faecher[result[:fas]].each do |teacher_email|
                    extra_consultations[teacher_email] ||= {:want => false, :display_name => @@user_info[teacher_email][:display_name_official], :display_name_dativ => @@user_info[teacher_email][:display_name_official_dativ]}
                end
            end
            if result[:betreuende_lehrkraft] && result[:betreuende_lehrkraft_is_confirmed]
                extra_consultations.delete(result[:betreuende_lehrkraft])
            end
            if result[:betreuende_lehrkraft_fas]
                extra_consultations.delete(result[:betreuende_lehrkraft_fas])
            end
            result[:extra_consultations] = extra_consultations
            result[:extra_consultation_events] = []
            neo4j_query(<<~END_OF_QUERY, {:email => email}).each do |row|
                MATCH (u:User {email: $email})-[:IS_PARTICIPANT]->(e:Event {zentraler_beratungstermin: TRUE})-[:ORGANIZED_BY]->(t:User)
                RETURN e, t.email
                ORDER BY e.date, e.start_time;
            END_OF_QUERY
                event = row['e']
                result[:extra_consultation_events] << {
                    :date => Date.parse(event[:date]).strftime('%d.%m.%Y'),
                    :start_time => event[:start_time],
                    :teacher => @@user_info[row['t.email']][:display_name_official_dativ],
                    :room => (event[:description] || '').match(/Raum ([^\s<>]+)/)
                }
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
                            io.puts "<div class='history_entry'>Vorgang erstellt durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                        current_date = entry_date
                    end
                    if pc[:type] == 'update_value'
                        key = pc[:key].to_sym
                        value = pc[:value]
                        if key == :betreuende_lehrkraft || key == :betreuende_lehrkraft_fas
                            value = (@@user_info[value] || {})[:display_name_official] || value
                        end
                        if (value || '').empty?
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} gelöscht durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        else
                            io.puts "<div class='history_entry'>#{PK5_KEY_LABELS[key]} geändert auf <strong>»#{value}«</strong> durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                        end
                    elsif pc[:type] == 'invite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> zur Gruppenprüfung eingeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
                    elsif pc[:type] == 'uninvite_sus'
                        io.puts "<div class='history_entry'><strong>#{@@user_info[pc[:other_email]][:display_name]}</strong> von der Gruppenprüfung ausgeladen durch #{@@user_info[entry['eu.email']][:display_name_official_dativ]}</div>"
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
        if teacher_logged_in?
            sus_email = data[:sus_email] if data[:sus_email]
        end
        respond(:html => my_pk5_history(sus_email))
    end

    def fix_pk5(sus_email)
        # make sure extra_consultation shorthands are in line
        # with referenzfach and fas
        p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
            MATCH (u:User {email: $sus_email})
            MATCH (p:Pk5)-[:BELONGS_TO]->(u)
            RETURN p;
        END_OF_QUERY
        if p[:extra_consultations]
            valid_emails = Set.new()
            valid_emails |= Set.new(@@pk5_faecher[p[:referenzfach]] || [])
            valid_emails |= Set.new(@@pk5_faecher[p[:fas]] || [])
            shorthands = p[:extra_consultations].split(',').select do |shorthand|
                email = @@shorthands[shorthand]
                valid_emails.include?(email)
            end
            new_consultations = shorthands.uniq.join(',')
            if p[:extra_consultations] != new_consultations
                neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :extra_consultations => new_consultations})
                    MATCH (u:User {email: $sus_email})
                    MATCH (p:Pk5)-[:BELONGS_TO]->(u)
                    SET p.extra_consultations = $extra_consultations
                    RETURN p;
                END_OF_QUERY
            end
        end
    end

    post '/api/update_pk5' do
        require_user!
        data = parse_request_data(
            :optional_keys => [
                :sus_email,
                :themengebiet,
                :referenzfach,
                :betreuende_lehrkraft,
                :fas,
                :betreuende_lehrkraft_fas,
                :fragestellung,
            ],
            :max_body_length => 16384,
            :max_string_length => 8192
        )
        sus_email = @session_user[:email]
        if teacher_logged_in?
            sus_email = data[:sus_email] if data[:sus_email]
        end
        assert(@@user_info[sus_email][:klasse] == PK5_CURRENT_KLASSE)
        unless user_with_role_logged_in?(:oko)
            assert(!$pk5.phases[$pk5.get_current_phase][:flags].include?(:no_sus_edit))
        end
        ts = Time.now.to_i
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MERGE (p:Pk5)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            [:themengebiet, :referenzfach, :betreuende_lehrkraft, :fas, :betreuende_lehrkraft_fas, :fragestellung].each do |key|
                if data.include?(key)
                    value = data[key]
                    if key == :referenzfach || key == :fas
                        value = nil unless @@pk5_faecher.include?(value)
                    end
                    if key == :betreuende_lehrkraft || key == :betreuende_lehrkraft_fas
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
            fix_pk5(sus_email)
        end
        respond(:yay => 'sure', :result => get_my_pk5(sus_email))
    end

    def pk5_overview_rows
        require_teacher!

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

        fachleiter_for_faecher = @@pk5_faecher_for_email[@session_user[:email]]
        fachleiter_for_faecher ||= Set.new()

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

            rows << {
                :email => email,
                :pk5 => pk5,
                :sus_index => sus_index,
                :sus => (pk5[:sus] || [email]).map { |x| @@user_info[x][:last_name] + ', ' + @@user_info[x][:first_name]}.join(' / '),
                :betreuende_lehrkraft => if pk5[:betreuende_lehrkraft] == @session_user[:email]
                    if pk5[:betreuende_lehrkraft_confirmed_by] != @session_user[:email]
                        if $pk5.get_current_phase >= 2
                            "<i class='fa fa-clock-o'></i>&nbsp;&nbsp;<span class='hl'>#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}</span> <em>Anfrage erhalten &ndash; bitte bestätigen oder ablehnen</em>"
                        else
                            "<i class='fa fa-clock-o'></i>&nbsp;&nbsp;#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}"
                        end
                    else
                        "#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}"
                    end
                else
                    if pk5[:betreuende_lehrkraft_confirmed_by] != pk5[:betreuende_lehrkraft]
                        "<i class='fa fa-clock-o'></i>&nbsp;&nbsp;#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}"
                    else
                        "#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft]] || {})[:display_name_official]) || '–')}"
                    end
                end,
                :betreuende_lehrkraft_fas => if fachleiter_for_faecher.include?(pk5[:fas]) && pk5[:betreuende_lehrkraft_fas].nil?
                    "<i class='fa fa-clock-o'></i>&nbsp;&nbsp;bitte Lehrkraft zuweisen"
                else
                    "#{CGI.escapeHTML(((@@user_info[pk5[:betreuende_lehrkraft_fas]] || {})[:display_name_official]) || '–')}"
                end
            }
        end
        rows
    end

    post '/api/pk5_overview' do
        require_teacher!

        rows = pk5_overview_rows()
        rows.sort! do |a, b|
            a_primary = a[:pk5][:betreuende_lehrkraft] == @session_user[:email]
            b_primary = b[:pk5][:betreuende_lehrkraft] == @session_user[:email]
            a_secondary = a[:pk5][:betreuende_lehrkraft_fas] == @session_user[:email]
            b_secondary = b[:pk5][:betreuende_lehrkraft_fas] == @session_user[:email]
            a_sus_index = a[:sus_index]
            b_sus_index = b[:sus_index]
            (a_primary == b_primary) ? (a_secondary == b_secondary ? (a_sus_index <=> b_sus_index) : (a_secondary ? -1 : 1)) : (a_primary ? -1 : 1)
        end

        respond(:rows => rows)
    end

    def pk5_termine_rows
        assert(user_with_role_logged_in?(:oko) || admin_logged_in?)

        rows = []

        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (e:Event {zentraler_beratungstermin: TRUE})-[:ORGANIZED_BY]->(t:User)
            WITH e, t
            MATCH (e)<-[:IS_PARTICIPANT]-(u:User)
            RETURN e, t.email AS organizer, COLLECT(u.email) AS participants;
        END_OF_QUERY
            rows << row
        end
        rows
    end

    post '/api/pk5_termine' do
        assert(user_with_role_logged_in?(:oko) || user_with_role_logged_in?(:sekretariat) || admin_logged_in?)

        rows = pk5_termine_rows()
        rows.sort! do |a, b|
            a_primary = a['e'][:start_time]
            b_primary = b['e'][:start_time]
            a_secondary = @@user_info[a['organizer']][:last_name].downcase
            b_secondary = @@user_info[b['organizer']][:last_name].downcase
            (a_primary == b_primary) ? (a_secondary <=> b_secondary) : (a_primary <=> b_primary)
        end

        respond(:rows => rows)
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

    post '/api/accept_pk5_invitation' do
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

    post '/api/reject_pk5_invitation' do
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

    post '/api/want_extra_consultation' do
        assert($pk5.get_current_phase() == 9)
        data = parse_request_data(:required_keys => [:email, :flag], :optional_keys => [:sus_email])
        sus_email = @session_user[:email]
        if teacher_logged_in?
            sus_email = data[:sus_email] if data[:sus_email]
        end
        transaction do
            p = neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email})['p']
                MATCH (u:User {email: $sus_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u)
                RETURN p;
            END_OF_QUERY
            extra_consultations = (p[:extra_consultations] || '').split(',')
            if (data[:flag] == 'no')
                extra_consultations.delete(@@user_info[data[:email]][:shorthand])
            else
                extra_consultations << @@user_info[data[:email]][:shorthand]
            end
            neo4j_query_expect_one(<<~END_OF_QUERY, {:sus_email => sus_email, :extra_consultations => extra_consultations.join(',')})
                MATCH (u:User {email: $sus_email})
                MATCH (p:Pk5)-[:BELONGS_TO]->(u)
                SET p.extra_consultations = $extra_consultations
                RETURN p;
            END_OF_QUERY
        end
        respond(:yay => 'sure', :result => get_my_pk5(sus_email))
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

    get '/api/print_voucher_1' do
        assert(user_with_role_logged_in?(:oko))
        require_teacher!

        rows = pk5_overview_rows()
        rows.sort! do |a, b|
            a[:sus_index] <=> b[:sus_index]
        end
        respond_raw_with_mimetype(Main.print_voucher_1(rows), 'application/pdf')
    end

    get '/api/print_voucher_2' do
        assert(user_with_role_logged_in?(:oko))
        require_teacher!

        rows = pk5_overview_rows()
        rows.sort! do |a, b|
            a[:sus_index] <=> b[:sus_index]
        end
        respond_raw_with_mimetype(Main.print_voucher_2(rows), 'application/pdf')
    end
end

