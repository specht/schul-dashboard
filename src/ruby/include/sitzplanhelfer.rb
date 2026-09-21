class Main < Sinatra::Base

    # Darf diese Person den Sitzplanhelfer für die angegebene Klasse benutzen?
    # Gleiches Muster wie z. B. die /directory/:klasse-Route in main.rb.
    def sph_can_manage?(klasse)
        admin_logged_in? || can_see_all_timetables_logged_in? || (@@teachers_for_klasse[klasse] || {}).include?(@session_user[:shorthand])
    end

    def require_sph_access!(klasse)
        require_teacher!
        assert(sph_can_manage?(klasse), 'Kein Zugriff auf den Sitzplanhelfer für diese Klasse.')
    end

    # Bricht mit einer Meldung ab, die die Lehrkraft tatsächlich zu sehen
    # bekommt. Ein blosses assert landet nur im Server-Log - im Browser käme
    # dann nur "Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten" an
    # (siehe api_call in code.js). Gleiches Muster wie in login.rb: respond()
    # setzt die Antwort, assert bricht die Verarbeitung ab. Bewusst nur für
    # erwartete, behebbare Situationen - nicht für Zugriffsschutz, wo eine
    # generische Meldung richtig ist.
    def sph_fail!(message)
        respond(:error => message)
        assert(false, message, true)
    end

    # Hinweis: Ein eigener "hier ist dein Sitzplatzwunsch"-Banner ist nicht
    # nötig - #{print_current_polls()} (poll.rb) zeigt jeder eingeloggten
    # Person (auch SuS) bereits automatisch jede offene Umfrage an, bei der
    # sie Teilnehmer:in ist, inkl. "Zur Umfrage"-Knopf. Da sph_start_cycle
    # unten eine ganz normale PollRun mit IS_PARTICIPANT-Kanten anlegt,
    # erscheint der Sitzplatzwunsch dort von selbst.

    # Liest eine laufende Wunschrunde aus und löst die Umfrage-Antworten zu
    # E-Mail-Adressen der Klasse auf. Umfrage-Antworten für radio/checkbox
    # werden von _template.html als ANTWORT-INDIZES gespeichert (Index in
    # item['answers']), nicht als Namens-Strings - siehe collect_poll_run_data()
    # in _template.html.
    def sph_read_wishes(klasse, cycle, poll_run_items)
        sus_emails = @@schueler_for_klasse[klasse] || []
        name_to_email = {}
        sus_emails.each { |e| name_to_email[@@user_info[e][:display_name_official]] = e }
        want_answers = (poll_run_items[0] || {})['answers'] || []
        avoid_answers = (poll_run_items[1] || {})['answers'] || []

        status_by_email = {}
        neo4j_query(<<~END_OF_QUERY, :cycle_id => cycle[:id]).each do |row|
            MATCH (sw:SeatWish)-[:FOR_CYCLE]->(:SeatingCycle {id: $cycle_id})
            MATCH (sw)-[:BELONGS_TO_USER]->(u:User)
            RETURN u.email AS email, sw;
        END_OF_QUERY
            status_by_email[row['email']] = row['sw']
        end

        wishes = {}
        neo4j_query(<<~END_OF_QUERY, :prid => cycle[:poll_run_id]).each do |row|
            MATCH (u:User)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(:PollRun {id: $prid})
            RETURN u.email AS email, prs.response AS response;
        END_OF_QUERY
            email = row['email']
            next unless sus_emails.include?(email)
            response = JSON.parse(row['response'] || '{}')
            want_indices = response['0'] || []
            avoid_index = response['1']
            # Alle genannten Wunschpartner sind gleichberechtigt (kein 1./2./3.
            # Wunsch) - da an einem Tisch ohnehin nur 1 Nachbar möglich ist,
            # zählt ohnehin immer nur "trifft mindestens einer".
            wants = want_indices.map { |i| name_to_email[want_answers[i]] }.compact.reject { |e| e == email }
            avoids = avoid_index.nil? ? [] : [name_to_email[avoid_answers[avoid_index]]].compact.reject { |e| e == email }
            status = status_by_email[email] || {}
            wishes[email] = {
                :want1 => wants[0], :want1_status => status[:want1_status] || 'pending',
                :want2 => wants[1], :want2_status => status[:want2_status] || 'pending',
                :want3 => wants[2], :want3_status => status[:want3_status] || 'pending',
                :avoid1 => avoids[0], :avoid1_status => status[:avoid1_status] || 'pending',
            }
        end
        wishes
    end

    # Namen der Klassenleitung(en) für Anzeige/Fehlermeldungen.
    def sph_klassenleiter_names(klasse)
        (@@klassenleiter[klasse] || []).map { |sh| @@user_info[@@shorthands[sh]] }.compact.map { |u| u[:display_name_official] }
    end

    post '/api/sph_start_cycle' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :raum], :optional_keys => [:duration_days, :carry_over],
                                  :types => {:duration_days => Integer})
        klasse = data[:klasse]
        raum = data[:raum]
        duration_days = data[:duration_days] || 4
        assert((1..60).include?(duration_days), 'Umfragedauer muss zwischen 1 und 60 Tagen liegen.')
        # Nur die Klassenleitung (oder Admin) darf eine Wunschrunde STARTEN -
        # sonst könnte jede Fachlehrkraft, die die Klasse aufruft, spontan eine
        # Umfrage an alle SuS auslösen. Verwaltung eines bereits laufenden
        # Zyklus (Wünsche bestätigen, Paare/Regeln, Plan erzeugen/speichern)
        # bleibt bewusst für alle Lehrkräfte der Klasse offen (sph_can_manage?).
        unless klassenleiter_for_klasse_or_admin_logged_in?(klasse)
            namen = sph_klassenleiter_names(klasse).join(', ')
            sph_fail!("Nur die Klassenleitung (#{namen.empty? ? 'nicht hinterlegt' : namen}) kann eine Sitzplatzwunsch-Umfrage starten.")
        end
        sus_emails = @@schueler_for_klasse[klasse] || []
        sph_fail!('Für diese Klasse sind keine SuS hinterlegt.') if sus_emails.empty?

        existing = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
            MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE sc.saved_at IS NULL
            RETURN sc
            ORDER BY sc.created_at DESC
            LIMIT 1;
        END_OF_QUERY

        if existing.size > 0
            sc = existing.first['sc']
            respond(:ok => true, :cycle_id => sc[:id], :poll_run_id => sc[:poll_run_id])
        else
            answers = sus_emails.map { |e| @@user_info[e][:display_name_official] }.sort
            items = [
                {'type' => 'checkbox', 'title' => 'Neben wem würdest du gerne sitzen? (bis zu 3 Personen, alle gleich wichtig)', 'answers' => answers, 'max_checks' => 3},
                {'type' => 'radio', 'title' => 'Neben wem möchtest du auf keinen Fall sitzen? (optional)', 'answers' => answers},
            ]
            poll_id = RandomTag.generate(12)
            cycle_id = RandomTag.generate(12)
            poll_run_id = RandomTag.generate(12)
            timestamp = Time.now.to_i
            now_date = Date.today.strftime('%Y-%m-%d')
            now_time = Time.now.strftime('%H:%M')
            end_date = (Date.today + duration_days).strftime('%Y-%m-%d')

            # Optional: Zwangspaare/Verbote/feste Plätze vom letzten GESPEICHERTEN
            # Plan für dieselbe Klasse+Raum übernehmen, damit die Lehrkraft nicht
            # jede Wunschrunde wieder bei Null anfängt. Bewusst nur gleiche
            # Klasse+Raum, da die Koordinaten fester Plätze raumspezifisch sind.
            carry_over = {:forced_pairs => '[]', :forbidden_pairs => '[]', :fixed_rules => '[]'}
            if data[:carry_over] == 'yes'
                last_rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
                    MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
                    WHERE sc.saved_at IS NOT NULL
                    RETURN sc
                    ORDER BY sc.saved_at DESC
                    LIMIT 1;
                END_OF_QUERY
                unless last_rows.empty?
                    last_sc = last_rows.first['sc']
                    carry_over = {
                        :forced_pairs => last_sc[:forced_pairs] || '[]',
                        :forbidden_pairs => last_sc[:forbidden_pairs] || '[]',
                        :fixed_rules => last_sc[:fixed_rules] || '[]',
                    }
                end
            end

            transaction do
                neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :pid => poll_id, :title => "Sitzplatzwunsch #{klasse} (Raum #{raum})", :items => items.to_json)
                    MATCH (a:User {email: $session_email})
                    CREATE (p:Poll {id: $pid, title: $title, items: $items})
                    SET p.created = $timestamp
                    SET p.updated = $timestamp
                    CREATE (p)-[:ORGANIZED_BY]->(a)
                    RETURN p;
                END_OF_QUERY
                neo4j_query_expect_one(<<~END_OF_QUERY, :pid => poll_id, :prid => poll_run_id, :timestamp => timestamp, :items => items.to_json, :now_date => now_date, :now_time => now_time, :end_date => end_date)
                    MATCH (p:Poll {id: $pid})
                    CREATE (pr:PollRun {id: $prid, anonymous: false, start_date: $now_date, start_time: $now_time, end_date: $end_date, end_time: '23:59', visible: 'yes', items: $items})
                    SET pr.created = $timestamp
                    SET pr.updated = $timestamp
                    CREATE (pr)-[:RUNS]->(p)
                    RETURN pr;
                END_OF_QUERY
                neo4j_query(<<~END_OF_QUERY, :prid => poll_run_id, :emails => sus_emails)
                    MATCH (pr:PollRun {id: $prid})
                    WITH pr
                    MATCH (u:User)
                    WHERE u.email IN $emails
                    CREATE (u)-[:IS_PARTICIPANT]->(pr);
                END_OF_QUERY
                neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => cycle_id, :klasse => klasse, :raum => raum, :pid => poll_id, :prid => poll_run_id, :forced_pairs => carry_over[:forced_pairs], :forbidden_pairs => carry_over[:forbidden_pairs], :fixed_rules => carry_over[:fixed_rules])
                    MATCH (a:User {email: $session_email})
                    CREATE (sc:SeatingCycle {id: $id, klasse: $klasse, raum: $raum, poll_id: $pid, poll_run_id: $prid, created_at: $timestamp, forced_pairs: $forced_pairs, forbidden_pairs: $forbidden_pairs, fixed_rules: $fixed_rules})
                    CREATE (sc)-[:STARTED_BY]->(a)
                    RETURN sc;
                END_OF_QUERY
            end
            respond(:ok => true, :cycle_id => cycle_id, :poll_run_id => poll_run_id)
        end
    end

    # Setzt das Enddatum/-zeit der zur Wunschrunde gehörenden Umfrage auf
    # "jetzt", damit sie sofort aus #{print_current_polls()} verschwindet.
    # Wird sowohl vom expliziten "Wunschrunde schließen"-Knopf als auch beim
    # Speichern eines Plans aufgerufen - ein gespeicherter/abgeschlossener
    # Zyklus darf NIE eine noch tagelang laufende Umfrage hinterlassen, sonst
    # sehen SuS nach dem Start einer neuen Runde plötzlich zwei gleichzeitig.
    def sph_close_poll_run!(poll_run_id)
        now_date = Date.today.strftime('%Y-%m-%d')
        now_time = (Time.now - 60).strftime('%H:%M')
        neo4j_query(<<~END_OF_QUERY, :prid => poll_run_id, :now_date => now_date, :now_time => now_time)
            MATCH (pr:PollRun {id: $prid})
            SET pr.end_date = $now_date
            SET pr.end_time = $now_time;
        END_OF_QUERY
    end

    post '/api/sph_close_wishes' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id])
        rows = neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id])
            MATCH (sc:SeatingCycle {id: $id})
            RETURN sc;
        END_OF_QUERY
        assert(rows.size > 0, 'Zyklus nicht gefunden.')
        sc = rows.first['sc']
        require_sph_access!(sc[:klasse])
        sph_close_poll_run!(sc[:poll_run_id])
        respond(:ok => true)
    end

    post '/api/sph_get_state' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :raum])
        klasse = data[:klasse]
        raum = data[:raum]
        require_sph_access!(klasse)

        sus_emails = (@@schueler_for_klasse[klasse] || []).sort do |a, b|
            @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
        end
        sus = sus_emails.map { |e| {:email => e, :display_name => @@user_info[e][:display_name_official]} }

        can_start_cycle = klassenleiter_for_klasse_or_admin_logged_in?(klasse)
        klassenleiter_names = sph_klassenleiter_names(klasse)

        open_cycle = nil
        wishes = {}
        rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
            MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE sc.saved_at IS NULL
            OPTIONAL MATCH (sc)-[:REOPENED_FROM]->(src:SeatingCycle)
            RETURN sc, src.saved_at AS reopened_from
            ORDER BY sc.created_at DESC
            LIMIT 1;
        END_OF_QUERY
        unless rows.empty?
            sc = rows.first['sc']
            # Gesetzt, wenn dieser offene Zyklus per "Bearbeiten" aus einem
            # gespeicherten Plan entstanden ist (Zeitstempel des Originals).
            # Dann ist es KEINE laufende Wunschrunde, sondern eine Bearbeitung -
            # die Oberfläche muss das anders benennen, sonst droht sie mit dem
            # Verlust von Wünschen, die in Wirklichkeit gar nicht betroffen sind.
            reopened_from = rows.first['reopened_from']
            pr_rows = neo4j_query(<<~END_OF_QUERY, :prid => sc[:poll_run_id])
                MATCH (pr:PollRun {id: $prid})
                RETURN pr;
            END_OF_QUERY
            pr = pr_rows.empty? ? nil : pr_rows.first['pr']
            now_s = DateTime.now.strftime('%Y-%m-%dT%H:%M:%S')
            wishes_open = pr && now_s >= "#{pr[:start_date]}T#{pr[:start_time]}:00" && now_s <= "#{pr[:end_date]}T#{pr[:end_time]}:00"
            open_cycle = {
                :id => sc[:id],
                :poll_run_id => sc[:poll_run_id],
                :start_date => pr && pr[:start_date],
                :start_time => pr && pr[:start_time],
                :end_date => pr && pr[:end_date],
                :end_time => pr && pr[:end_time],
                :wishes_open => !!wishes_open,
                :reopened_from => reopened_from,
                :forced_pairs => JSON.parse(sc[:forced_pairs] || '[]'),
                :forbidden_pairs => JSON.parse(sc[:forbidden_pairs] || '[]'),
                :fixed_rules => JSON.parse(sc[:fixed_rules] || '[]'),
            }
            wishes = sph_read_wishes(klasse, sc, pr ? JSON.parse(pr[:items]) : [])
        end

        last_cycle = nil
        last_rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
            MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE sc.saved_at IS NOT NULL
            RETURN sc
            ORDER BY sc.saved_at DESC
            LIMIT 1;
        END_OF_QUERY
        unless last_rows.empty?
            sc = last_rows.first['sc']
            last_cycle = {
                :id => sc[:id],
                :saved_at => sc[:saved_at],
                :seats => JSON.parse(sc[:seats] || '{}'),
                :unresolved => JSON.parse(sc[:unresolved] || '[]'),
                :satisfied_emails => JSON.parse(sc[:satisfied_emails] || '[]'),
            }
        end

        respond(:ok => true, :klasse => klasse, :raum => raum, :sus => sus,
                :can_start_cycle => can_start_cycle, :klassenleiter_names => klassenleiter_names,
                :open_cycle => open_cycle, :wishes => wishes, :last_cycle => last_cycle)
    end

    # Öffentliche (Lehrkraft + eigene Klasse), wunsch-freie Sicht auf einen
    # GESPEICHERTEN Sitzplan - für die SuS-Ansicht (sitzplananzeige.html).
    # Absichtlich getrennt von sph_get_state: liefert NUR Namen + Plätze,
    # nichts zu Wünschen/Bestätigungen/Paaren/Regeln (Lehrergeheimnis).
    # Ohne cycle_id: der zuletzt gespeicherte Plan. Mit cycle_id: genau
    # dieser (frühere) Plan - für die Historien-Liste im Sitzplanhelfer.
    post '/api/sph_get_public_plan' do
        require_user!
        data = parse_request_data(:required_keys => [:klasse, :raum], :optional_keys => [:cycle_id])
        klasse = data[:klasse]
        raum = data[:raum]
        assert(sph_can_manage?(klasse) || @session_user[:klasse] == klasse,
               'Kein Zugriff auf den Sitzplan dieser Klasse.')

        if data[:cycle_id]
            rows = neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id], :klasse => klasse, :raum => raum)
                MATCH (sc:SeatingCycle {id: $id, klasse: $klasse, raum: $raum})
                WHERE sc.saved_at IS NOT NULL
                RETURN sc;
            END_OF_QUERY
        else
            rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
                MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
                WHERE sc.saved_at IS NOT NULL
                RETURN sc
                ORDER BY sc.saved_at DESC
                LIMIT 1;
            END_OF_QUERY
        end
        if rows.empty?
            respond(:ok => true, :klasse => klasse, :raum => raum, :saved_at => nil, :places => [])
        else
            sc = rows.first['sc']
            seats_by_email = JSON.parse(sc[:seats] || '{}')
            places = seats_by_email.map do |email, idx|
                next nil unless @@user_info[email]
                {:display_name => @@user_info[email][:display_name_official], :seat_index => idx}
            end.compact
            respond(:ok => true, :klasse => klasse, :raum => raum, :saved_at => sc[:saved_at], :places => places)
        end
    end

    post '/api/sph_set_wish_status' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :email, :slot, :status])
        assert(['want1_status', 'want2_status', 'want3_status', 'avoid1_status'].include?(data[:slot]), 'Unbekannter Wunsch-Slot.')
        # Wünsche gelten automatisch ("pending" zählt also wie ein normaler,
        # aktiver Wunsch) - nur "rejected" nimmt einen Wunsch aus der Planung.
        assert(['pending', 'rejected'].include?(data[:status]), 'Unbekannter Status.')
        rows = neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id])
            MATCH (sc:SeatingCycle {id: $id})
            RETURN sc;
        END_OF_QUERY
        assert(rows.size > 0, 'Zyklus nicht gefunden.')
        sc = rows.first['sc']
        require_sph_access!(sc[:klasse])
        slot = data[:slot]
        neo4j_query(<<~END_OF_QUERY, :cycle_id => data[:cycle_id], :email => data[:email], :status => data[:status])
            MATCH (sc:SeatingCycle {id: $cycle_id})
            MATCH (u:User {email: $email})
            MERGE (u)<-[:BELONGS_TO_USER]-(sw:SeatWish)-[:FOR_CYCLE]->(sc)
            SET sw.#{slot} = $status;
        END_OF_QUERY
        respond(:ok => true)
    end

    def sph_load_cycle_for_edit!(cycle_id)
        rows = neo4j_query(<<~END_OF_QUERY, :id => cycle_id)
            MATCH (sc:SeatingCycle {id: $id})
            RETURN sc;
        END_OF_QUERY
        assert(rows.size > 0, 'Zyklus nicht gefunden.')
        sc = rows.first['sc']
        require_sph_access!(sc[:klasse])
        sc
    end

    post '/api/sph_set_pair' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :email_a, :email_b, :kind])
        assert(['forced', 'forbidden'].include?(data[:kind]), 'Unbekannte Paar-Art.')
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        prop = data[:kind] == 'forced' ? :forced_pairs : :forbidden_pairs
        other_prop = data[:kind] == 'forced' ? :forbidden_pairs : :forced_pairs
        wanted_pair = [data[:email_a], data[:email_b]].sort
        # Ein Paar darf nie gleichzeitig Zwangs- UND Verbotspaar sein - das
        # wäre ein direkter Widerspruch der Lehrkraft mit sich selbst.
        other_pairs = JSON.parse(sc[other_prop] || '[]')
        name_a = (@@user_info[data[:email_a]] || {})[:display_name_official] || data[:email_a]
        name_b = (@@user_info[data[:email_b]] || {})[:display_name_official] || data[:email_b]
        if other_pairs.any? { |p| p.sort == wanted_pair }
            sph_fail!("#{name_a} und #{name_b} sind bereits als " \
                      "\"#{data[:kind] == 'forced' ? 'darf nicht zusammensitzen' : 'muss zusammensitzen'}\" gesetzt - " \
                      "bitte das zuerst entfernen.")
        end
        # Ein Verbotspaar widerspricht sich auch, wenn beide bereits über
        # exakte feste Plätze (siehe sph_set_fixed_rule) zu Tischnachbarn
        # gemacht wurden - genau der umgekehrte Fall zur Prüfung dort.
        if data[:kind] == 'forbidden'
            fixed = JSON.parse(sc[:fixed_rules] || '[]')
            rule_a = fixed.find { |r| r[0] == data[:email_a] && r[1][0] == r[1][1] && r[2][0] == r[2][1] }
            rule_b = fixed.find { |r| r[0] == data[:email_b] && r[1][0] == r[1][1] && r[2][0] == r[2][1] }
            if rule_a && rule_b && rule_a[2][0] == rule_b[2][0] && (rule_a[1][0] - rule_b[1][0]).abs == 1
                sph_fail!("#{name_a} und #{name_b} sitzen bereits über feste Plätze nebeneinander - " \
                          "bitte zuerst einen der beiden festen Plätze entfernen.")
            end
        end
        pairs = JSON.parse(sc[prop] || '[]')
        pairs << [data[:email_a], data[:email_b]] unless pairs.any? { |p| p.sort == wanted_pair }
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id], :value => pairs.to_json)
            MATCH (sc:SeatingCycle {id: $id})
            SET sc.#{prop} = $value;
        END_OF_QUERY
        respond(:ok => true, :pairs => pairs)
    end

    post '/api/sph_remove_pair' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :email_a, :email_b, :kind])
        assert(['forced', 'forbidden'].include?(data[:kind]), 'Unbekannte Paar-Art.')
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        prop = data[:kind] == 'forced' ? :forced_pairs : :forbidden_pairs
        pairs = JSON.parse(sc[prop] || '[]')
        pairs.reject! { |p| p.sort == [data[:email_a], data[:email_b]].sort }
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id], :value => pairs.to_json)
            MATCH (sc:SeatingCycle {id: $id})
            SET sc.#{prop} = $value;
        END_OF_QUERY
        respond(:ok => true, :pairs => pairs)
    end

    post '/api/sph_set_fixed_rule' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :email, :x_min, :x_max, :y_min, :y_max],
                                  :types => {:x_min => Integer, :x_max => Integer, :y_min => Integer, :y_max => Integer})
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        rules = JSON.parse(sc[:fixed_rules] || '[]')
        # Ein exakter Platz (x_min == x_max und y_min == y_max, siehe
        # sitzplanhelfer.html/#sph_rule_seatmap) ist physisch nur einer Person
        # zuweisbar - anders als eine grobe Bereichsvorgabe (z. B. "vorne"),
        # die für mehrere SuS gleichzeitig gelten darf.
        if data[:x_min] == data[:x_max] && data[:y_min] == data[:y_max]
            conflict = rules.find { |r| r[0] != data[:email] && r[1] == [data[:x_min], data[:x_max]] && r[2] == [data[:y_min], data[:y_max]] }
            if conflict
                conflict_name = (@@user_info[conflict[0]] || {})[:display_name_official] || conflict[0]
                sph_fail!("Dieser Platz ist bereits #{conflict_name} fest zugewiesen - bitte das zuerst entfernen.")
            end
            # Genauso widersprüchlich: der Nachbarplatz ist bereits fest an
            # jemanden vergeben, mit dem diese Person als Verbotspaar
            # ("dürfen nicht zusammensitzen") markiert ist - umgekehrter Fall
            # zur Prüfung in sph_set_pair.
            neighbor_rule = rules.find { |r| r[0] != data[:email] && r[1][0] == r[1][1] && r[2][0] == r[2][1] && r[2][0] == data[:y_min] && (r[1][0] - data[:x_min]).abs == 1 }
            if neighbor_rule
                forbidden_pairs = JSON.parse(sc[:forbidden_pairs] || '[]')
                if forbidden_pairs.any? { |p| p.sort == [data[:email], neighbor_rule[0]].sort }
                    neighbor_name = (@@user_info[neighbor_rule[0]] || {})[:display_name_official] || neighbor_rule[0]
                    sph_fail!("#{neighbor_name} sitzt bereits fest auf dem Nachbarplatz, ist aber als \"dürfen nicht zusammensitzen\" markiert - bitte das zuerst entfernen.")
                end
            end
        end
        rules.reject! { |r| r[0] == data[:email] }
        rules << [data[:email], [data[:x_min], data[:x_max]], [data[:y_min], data[:y_max]]]
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id], :value => rules.to_json)
            MATCH (sc:SeatingCycle {id: $id})
            SET sc.fixed_rules = $value;
        END_OF_QUERY
        respond(:ok => true, :rules => rules)
    end

    post '/api/sph_remove_fixed_rule' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :email])
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        rules = JSON.parse(sc[:fixed_rules] || '[]')
        rules.reject! { |r| r[0] == data[:email] }
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id], :value => rules.to_json)
            MATCH (sc:SeatingCycle {id: $id})
            SET sc.fixed_rules = $value;
        END_OF_QUERY
        respond(:ok => true, :rules => rules)
    end

    # Verwirft einen noch offenen (nicht gespeicherten) Zyklus komplett - für
    # "das wollte ich so nicht, nochmal von vorne". Anders als sph_delete_cycle
    # (nur für bereits gespeicherte Pläne) gibt es sonst keinen Weg, einen
    # begonnenen Zyklus loszuwerden: sph_start_cycle liefert für dieselbe
    # Klasse+Raum immer denselben offenen Zyklus zurück, solange er nicht
    # gespeichert ist. Poll/PollRun bleiben unangetastet (werden bei
    # sph_reopen_saved_cycle mit dem Ursprungsplan geteilt, dürfen also nicht
    # mitgelöscht werden).
    post '/api/sph_discard_open_cycle' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id])
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        assert(sc[:saved_at].nil?, 'Nur eine noch offene (nicht gespeicherte) Wunschrunde kann verworfen werden.')
        # Erst die Umfrage schließen, dann den Zyklus löschen: sonst bliebe eine
        # Umfrage ohne zugehörigen Zyklus tagelang bei den SuS sichtbar, deren
        # Antworten nirgends mehr ankommen - und beim Start der nächsten Runde
        # sähen sie zwei gleichzeitig. Bei einem per sph_reopen_saved_cycle
        # geöffneten Zyklus ist die Umfrage ohnehin längst geschlossen, ein
        # erneutes Schließen ändert dort nichts.
        sph_close_poll_run!(sc[:poll_run_id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id])
            MATCH (sc:SeatingCycle {id: $id})
            OPTIONAL MATCH (sw:SeatWish)-[:FOR_CYCLE]->(sc)
            DETACH DELETE sw, sc;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/sph_save_cycle' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id, :seats, :unresolved],
                                  :optional_keys => [:satisfied_emails],
                                  :max_body_length => 256 * 1024, :max_string_length => 256 * 1024)
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        # Die drei JSON-Felder kommen roh vom Client. Ungeprüft abgelegt würde
        # kaputtes JSON später JEDE Anzeige dieses Plans mit einem Fehler
        # abbrechen lassen - auch die der SuS -, und fremde E-Mail-Adressen im
        # seats-Feld würden Namen aus anderen Klassen in die SuS-Ansicht
        # tragen. Deshalb einmal parsen, auf SuS dieser Klasse beschränken und
        # neu serialisiert speichern.
        begin
            seats = JSON.parse(data[:seats])
            unresolved = JSON.parse(data[:unresolved])
            satisfied = JSON.parse(data[:satisfied_emails] || '[]')
        rescue JSON::ParserError
            assert(false, 'Ungültige Plandaten.')
        end
        assert(seats.is_a?(Hash) && unresolved.is_a?(Array) && satisfied.is_a?(Array), 'Ungültige Plandaten.')
        sus_emails = @@schueler_for_klasse[sc[:klasse]] || []
        seats = seats.select { |email, idx| sus_emails.include?(email) && idx.is_a?(Integer) }
        satisfied = satisfied.select { |email| sus_emails.include?(email) }
        unresolved = unresolved.select { |f| f.is_a?(Hash) && sus_emails.include?(f['email']) }
        sph_close_poll_run!(sc[:poll_run_id])
        timestamp = Time.now.to_i
        params = {:id => data[:cycle_id], :seats => seats.to_json, :unresolved => unresolved.to_json,
                  :satisfied_emails => satisfied.to_json, :timestamp => timestamp}
        neo4j_query(<<~END_OF_QUERY, params)
            MATCH (sc:SeatingCycle {id: $id})
            SET sc.seats = $seats
            SET sc.unresolved = $unresolved
            SET sc.satisfied_emails = $satisfied_emails
            SET sc.saved_at = $timestamp;
        END_OF_QUERY
        respond(:ok => true)
    end

    # Liste aller GESPEICHERTEN Sitzpläne für Klasse+Raum, neueste zuerst -
    # für die Historien-Ansicht im Sitzplanhelfer (nachträglich einsehbar,
    # löschbar, pro Eintrag einzeln für SuS anzeigbar).
    post '/api/sph_list_saved_cycles' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :raum])
        klasse = data[:klasse]
        raum = data[:raum]
        require_sph_access!(klasse)
        rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :raum => raum)
            MATCH (sc:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE sc.saved_at IS NOT NULL
            RETURN sc
            ORDER BY sc.saved_at DESC;
        END_OF_QUERY
        cycles = rows.map do |row|
            sc = row['sc']
            {
                :id => sc[:id],
                :saved_at => sc[:saved_at],
                :seats_count => JSON.parse(sc[:seats] || '{}').size,
                :satisfied_count => JSON.parse(sc[:satisfied_emails] || '[]').size,
                :unresolved_count => JSON.parse(sc[:unresolved] || '[]').map { |f| f['email'] }.uniq.size,
            }
        end
        respond(:ok => true, :cycles => cycles)
    end

    # Löscht einen versehentlich gespeicherten Sitzplan wieder. Bewusst nur
    # für bereits GESPEICHERTE Zyklen (nie den gerade offenen/laufenden) -
    # sonst könnte man sich die laufende Wunschrunde unter dem Bearbeiten
    # wegreißen.
    post '/api/sph_delete_cycle' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id])
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        assert(sc[:saved_at], 'Nur gespeicherte Sitzpläne können gelöscht werden.')
        neo4j_query(<<~END_OF_QUERY, :id => data[:cycle_id])
            MATCH (sc:SeatingCycle {id: $id})
            OPTIONAL MATCH (sw:SeatWish)-[:FOR_CYCLE]->(sc)
            DETACH DELETE sw, sc;
        END_OF_QUERY
        respond(:ok => true)
    end

    # Öffnet einen bereits gespeicherten Sitzplan erneut zur Bearbeitung -
    # OHNE eine neue Umfrage zu starten. Dafür wird ein neuer Zyklus angelegt,
    # der dieselbe (bereits geschlossene) Wunschrunde referenziert sowie die
    # Paare/Regeln/Wunsch-Ablehnungen des Ursprungs übernimmt. Der Ursprung
    # bleibt unverändert in der Historie erhalten - "leicht ändern und neu
    # ausmixen", nicht "von vorne anfangen".
    post '/api/sph_reopen_saved_cycle' do
        require_teacher!
        data = parse_request_data(:required_keys => [:cycle_id])
        sc = sph_load_cycle_for_edit!(data[:cycle_id])
        assert(sc[:saved_at], 'Nur gespeicherte Sitzpläne können erneut bearbeitet werden.')
        existing_open = neo4j_query(<<~END_OF_QUERY, :klasse => sc[:klasse], :raum => sc[:raum])
            MATCH (x:SeatingCycle {klasse: $klasse, raum: $raum})
            WHERE x.saved_at IS NULL
            RETURN x
            LIMIT 1;
        END_OF_QUERY
        unless existing_open.empty?
            sph_fail!('Es ist bereits eine Wunschrunde oder eine Bearbeitung offen. Bitte diese zuerst speichern oder oben verwerfen, bevor du einen anderen Plan bearbeitest.')
        end

        new_id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        params = {
            :id => new_id, :klasse => sc[:klasse], :raum => sc[:raum],
            :poll_id => sc[:poll_id], :poll_run_id => sc[:poll_run_id],
            :forced_pairs => sc[:forced_pairs] || '[]', :forbidden_pairs => sc[:forbidden_pairs] || '[]',
            :fixed_rules => sc[:fixed_rules] || '[]', :timestamp => timestamp,
            :session_email => @session_user[:email], :source_id => sc[:id],
        }
        neo4j_query(<<~END_OF_QUERY, params)
            MATCH (a:User {email: $session_email})
            MATCH (old:SeatingCycle {id: $source_id})
            CREATE (nc:SeatingCycle {id: $id, klasse: $klasse, raum: $raum, poll_id: $poll_id, poll_run_id: $poll_run_id,
                                      created_at: $timestamp, forced_pairs: $forced_pairs, forbidden_pairs: $forbidden_pairs,
                                      fixed_rules: $fixed_rules})
            CREATE (nc)-[:STARTED_BY]->(a)
            CREATE (nc)-[:REOPENED_FROM]->(old);
        END_OF_QUERY
        # Bisherige Wunsch-Ablehnungen mit in die Kopie übernehmen, damit die
        # Lehrkraft nicht wieder bei Null anfängt.
        neo4j_query(<<~END_OF_QUERY, :old_id => sc[:id], :new_id => new_id)
            MATCH (sw:SeatWish)-[:FOR_CYCLE]->(:SeatingCycle {id: $old_id})
            MATCH (sw)-[:BELONGS_TO_USER]->(u:User)
            MATCH (nc:SeatingCycle {id: $new_id})
            CREATE (u)<-[:BELONGS_TO_USER]-(:SeatWish {
                want1_status: sw.want1_status, want2_status: sw.want2_status,
                want3_status: sw.want3_status, avoid1_status: sw.avoid1_status
            })-[:FOR_CYCLE]->(nc);
        END_OF_QUERY
        respond(:ok => true, :cycle_id => new_id)
    end
end
