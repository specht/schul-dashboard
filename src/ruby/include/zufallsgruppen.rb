class Main < Sinatra::Base

    # Zufallsgruppen für Gruppenarbeiten - unabhängig vom Sitzplan. Öffnen
    # darf die Seite jede Lehrkraft der Klasse (wie "Sitzplan ansehen").
    def zg_can_use?(klasse)
        teacher_logged_in? && @@schueler_for_klasse.include?(klasse) && sph_can_view?(klasse)
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

        sus_emails = (@@schueler_for_klasse[klasse] || []).sort do |a, b|
            @@user_info[a][:last_name].downcase <=> @@user_info[b][:last_name].downcase
        end
        sus = sus_emails.map do |e|
            {:email => e,
             :display_name => @@user_info[e][:display_name_official],
             :first_name => @@user_info[e][:first_name],
             :geschlecht => @@user_info[e][:geschlecht]}
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
        is_klassenleitung = sph_can_manage?(klasse)
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

        respond(:ok => true, :klasse => klasse, :sus => sus, :last => last,
                :is_klassenleitung => is_klassenleitung, :distribution => distribution)
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
        sus_emails = @@schueler_for_klasse[klasse] || []
        groups = groups.map { |g| g.select { |e| e.is_a?(String) && sus_emails.include?(e) }.uniq }
        # Nur bekannte Einstellungen in einfacher Form übernehmen.
        clean = {}
        clean['size'] = settings['size'].to_i if settings['size'].is_a?(Integer)
        clean['rest'] = settings['rest'] if %w(bigger smaller).include?(settings['rest'])
        clean['gender'] = settings['gender'] if %w(egal gemischt getrennt).include?(settings['gender'])
        clean['distribution'] = !!settings['distribution'] if sph_can_manage?(klasse)
        neo4j_query(<<~END_OF_QUERY, :key => zg_key(klasse), :groups => groups.to_json, :settings => clean.to_json, :ts => Time.now.to_i)
            MERGE (r:RandomGroups {key: $key})
            SET r.groups = $groups
            SET r.settings = $settings
            SET r.ts = $ts;
        END_OF_QUERY
        respond(:ok => true)
    end
end
