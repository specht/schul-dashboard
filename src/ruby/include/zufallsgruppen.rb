class Main < Sinatra::Base

    # Zufallsgruppen für Gruppenarbeiten - unabhängig vom Sitzplan. Öffnen
    # darf die Seite jede Lehrkraft der Klasse (wie "Sitzplan ansehen").
    # Unter /zufallsgruppen/kollegium gibt es dieselbe Seite für das Kollegium
    # (z. B. für Konferenzen). Öffnen dürfen sie Admins und die Lehrkräfte,
    # die ein Admin dafür freigegeben hat.
    ZG_KOLLEGIUM = 'kollegium'

    def zg_kollegium?(klasse)
        klasse == ZG_KOLLEGIUM
    end

    def zg_kollegium_allowed_emails
        rows = neo4j_query("MATCH (a:RandomGroupsAccess {id: $id}) RETURN a.emails AS emails;", :id => ZG_KOLLEGIUM)
        return [] if rows.empty? || rows.first['emails'].nil?
        emails = JSON.parse(rows.first['emails']) rescue []
        emails.is_a?(Array) ? emails.select { |e| @@user_info[e] && @@user_info[e][:teacher] } : []
    end

    def zg_can_use?(klasse)
        if zg_kollegium?(klasse)
            return false unless teacher_logged_in?
            return true if admin_logged_in?
            return zg_kollegium_allowed_emails.include?(@session_user[:email])
        end
        teacher_logged_in? && @@schueler_for_klasse.include?(klasse) && sph_can_view?(klasse)
    end

    # Wer eingeteilt werden kann: die Klasse oder alle Lehrkräfte (ohne
    # Funktionskonten, deren Kürzel mit "_" beginnt).
    def zg_member_emails(klasse)
        if zg_kollegium?(klasse)
            @@lehrer_order.select { |e| @@user_info[e] && !(@@user_info[e][:shorthand] || '').start_with?('_') }
        else
            (@@schueler_for_klasse[klasse] || []).sort do |a, b|
                @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
            end
        end
    end

    def require_zg_access!(klasse)
        require_teacher!
        assert(zg_can_use?(klasse), 'Kein Zugriff auf die Zufallsgruppen dieser Klasse.')
    end

    def zg_path_klasse
        CGI.unescape(request.path.split('/')[2] || '')
    end

    # Die zuletzt gemischten Gruppen gehören der Lehrkraft, die gemischt hat -
    # andere Lehrkräfte derselben Klasse sehen sie nicht.
    def zg_key(klasse)
        "#{@session_user[:email]}/#{klasse}"
    end

    post '/api/zg_get_state' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse])
        klasse = data[:klasse]
        require_zg_access!(klasse)

        kollegium = zg_kollegium?(klasse)
        sus_emails = zg_member_emails(klasse)
        sus = sus_emails.map do |e|
            if kollegium
                # Im Kollegium gibt es keine Regel nach Geschlecht. Für den
                # Beamer zählt vor allem das Kürzel: bei vielen Lehrkräften
                # sind ganze Namen von hinten nicht mehr lesbar.
                {:email => e, :display_name => @@user_info[e][:display_name],
                 :shorthand => @@user_info[e][:shorthand],
                 :nc_login => @@user_info[e][:nc_login]}
            else
                {:email => e,
                 :display_name => @@user_info[e][:display_name_official],
                 :first_name => @@user_info[e][:first_name],
                 :geschlecht => @@user_info[e][:geschlecht]}
            end
        end

        rows = neo4j_query(<<~END_OF_QUERY, :key => zg_key(klasse))
            MATCH (r:RandomGroups {key: $key})
            RETURN r.groups AS groups, r.settings AS settings, r.ts AS ts;
        END_OF_QUERY
        last = nil
        unless rows.empty?
            begin
                last = {:groups => JSON.parse(rows.first['groups']),
                        :settings => JSON.parse(rows.first['settings'] || '{}'),
                        :ts => rows.first['ts']}
            rescue JSON::ParserError
                last = nil
            end
        end

        # Verteilungslisten und Zwangspaare aus dem Sitzplanhelfer gibt es nur
        # für die Klassenleitung - für alle anderen kommen sie gar nicht erst
        # in den Browser.
        is_klassenleitung = !kollegium && sph_can_manage?(klasse)
        distribution = nil
        if is_klassenleitung
            forced = []
            fp_rows = neo4j_query(<<~END_OF_QUERY, :klasse => klasse)
                MATCH (sc:SeatingCycle {klasse: $klasse})
                WHERE sc.created_at IS NOT NULL AND sc.forced_pairs IS NOT NULL
                RETURN sc.forced_pairs AS forced_pairs
                ORDER BY sc.created_at DESC
                LIMIT 1;
            END_OF_QUERY
            unless fp_rows.empty?
                forced = (JSON.parse(fp_rows.first['forced_pairs']) rescue [])
                forced = forced.select { |p| p.is_a?(Array) && p.size == 2 && p.all? { |e| sus_emails.include?(e) } }
            end
            distribution = {:lists => sph_load_seating_groups(klasse), :forced_pairs => forced}
        end

        # Wer außer den Admins die Kollegium-Gruppen nutzen darf, sehen und
        # ändern nur Admins.
        access = nil
        if kollegium && admin_logged_in?
            access = {:emails => zg_kollegium_allowed_emails}
        end

        respond(:ok => true, :klasse => klasse, :kollegium => kollegium, :sus => sus, :last => last,
                :is_klassenleitung => is_klassenleitung, :distribution => distribution, :access => access)
    end

    post '/api/zg_save_last' do
        require_teacher!
        data = parse_request_data(:required_keys => [:klasse, :groups, :settings],
                                  :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        klasse = data[:klasse]
        require_zg_access!(klasse)
        begin
            groups = JSON.parse(data[:groups])
            settings = JSON.parse(data[:settings])
        rescue JSON::ParserError
            assert(false, 'Ungültige Gruppen.')
        end
        assert(groups.is_a?(Array) && groups.size <= 60 && groups.all? { |g| g.is_a?(Array) }, 'Ungültige Gruppen.')
        assert(settings.is_a?(Hash), 'Ungültige Einstellungen.')
        kollegium = zg_kollegium?(klasse)
        sus_emails = zg_member_emails(klasse)
        groups = groups.map { |g| g.select { |e| e.is_a?(String) && sus_emails.include?(e) }.uniq }
        # Nur bekannte Einstellungen in einfacher Form übernehmen.
        clean = {}
        clean['size'] = settings['size'].to_i if settings['size'].is_a?(Integer)
        clean['rest'] = settings['rest'] if %w(bigger smaller).include?(settings['rest'])
        if kollegium
            clean['labels'] = settings['labels'] if %w(shorthand name).include?(settings['labels'])
        else
            clean['gender'] = settings['gender'] if %w(egal gemischt getrennt).include?(settings['gender'])
            clean['distribution'] = !!settings['distribution'] if sph_can_manage?(klasse)
        end
        neo4j_query(<<~END_OF_QUERY, :key => zg_key(klasse), :groups => groups.to_json, :settings => clean.to_json, :ts => Time.now.to_i)
            MERGE (r:RandomGroups {key: $key})
            SET r.groups = $groups
            SET r.settings = $settings
            SET r.ts = $ts;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/zg_save_kollegium_access' do
        require_admin!
        data = parse_request_data(:required_keys => [:emails], :max_body_length => 64 * 1024, :max_string_length => 64 * 1024)
        begin
            emails = JSON.parse(data[:emails])
        rescue JSON::ParserError
            assert(false, 'Ungültige Liste.')
        end
        assert(emails.is_a?(Array), 'Ungültige Liste.')
        teachers = zg_member_emails(ZG_KOLLEGIUM)
        emails = emails.select { |e| e.is_a?(String) && teachers.include?(e) }.uniq
        neo4j_query(<<~END_OF_QUERY, :id => ZG_KOLLEGIUM, :emails => emails.to_json, :ts => Time.now.to_i)
            MERGE (a:RandomGroupsAccess {id: $id})
            SET a.emails = $emails
            SET a.updated = $ts;
        END_OF_QUERY
        respond(:ok => true, :emails => emails)
    end
end
