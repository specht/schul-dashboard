class Main < Sinatra::Base
    post '/api/update_salzh_for_sus' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email, :end_date, :mode])
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email], :end_date => data[:end_date], :mode => data[:mode])
            MATCH (u:User {email: {email}})
            MERGE (s:Salzh)-[:BELONGS_TO]->(u)
            SET s.end_date = {end_date}
            SET s.mode = {mode}
            RETURN s;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_salzh_entry' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email])
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User {email: {email}})
            DETACH DELETE s;
        END_OF_QUERY
        respond(:ok => true)
    end

    def self.get_current_salzh_sus
        today = Date.today.strftime('%Y-%m-%d')
        # purge stale salzh entries
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            WHERE s.end_date < {today}
            DETACH DELETE s;
        END_OF_QUERY
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            RETURN s, u
            ORDER BY s.end_date;
        END_OF_QUERY
        entries = rows.map do |x|
            email = x['u'].props[:email]
            {
                :email => email,
                :name => @@user_info[email][:display_name],
                :first_name => @@user_info[email][:display_first_name],
                :last_name => @@user_info[email][:display_last_name],
                :klasse => @@user_info[email][:klasse],
                :klasse_tr => tr_klasse(@@user_info[email][:klasse]),
                :mode => x['s'].props[:mode] || 'salzh',
                :end_date => x['s'].props[:end_date]
            }
        end
        entries.sort! do |a, b|
            if a[:klasse] == b[:klasse]
                if a[:last_name] == b[:last_name]
                    a[:first_name] <=> b[:first_name]
                else
                    a[:last_name] <=> b[:last_name]
                end
            else
                (KLASSEN_ORDER.index(a[:klasse]) <=> KLASSEN_ORDER.index(b[:klasse]))
            end
        end
        entries
    end

    def get_current_salzh_sus
        Main.get_current_salzh_sus
    end

    def get_current_salzh_sus_for_logged_in_teacher
        entries = get_current_salzh_sus
        entries.select! do |entry|
            (@@schueler_for_teacher[@session_user[:shorthand]] || []).include?(entry[:email])
        end
        entries
    end

    def self.get_current_salzh_sus_for_all_teachers
        all_entries = Main.get_current_salzh_sus
        result = {}
        @@lehrer_order.each do |email|
            shorthand = @@user_info[email][:shorthand]
            entries = all_entries.select do |entry|
                (@@schueler_for_teacher[shorthand] || []).include?(entry[:email])
            end
            result[shorthand] = entries
        end
        result
    end

    def print_salzh_panel
        require_user!
        unless teacher_logged_in?
            rows = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                MATCH (s:Salzh)-[:BELONGS_TO]->(u:User {email: {email}})
                RETURN s.end_date AS end_date;
            END_OF_QUERY
            return '' if rows.empty?
            StringIO.open do |io|
                io.puts "<div class='hint'>"
                io.puts "<p><strong>Unterricht im saLzH</strong></p>"
                end_date = rows.first['end_date']
                io.puts "<p>Du bist <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> für das schulisch angeleite Lernen zu Hause (saLzH) eingetragen. Bitte schau regelmäßig in deinem Stundenplan nach, ob du Aufgaben in der Nextcloud oder im Lernraum bekommst oder ob Stunden per Jitsi durchgeführt werden.</p>"
                io.puts "</div>"
                io.string
            end
        else
            entries = get_current_salzh_sus_for_logged_in_teacher()
            return '' if entries.empty?
            StringIO.open do |io|
                io.puts "<div class='hint'>"
                # io.puts "<p><strong><div style='display: inline-block; padding: 4px; margin: -4px; border-radius: 4px' class='bg-warning'>SuS im saLzH</div></strong></p>"
                contact_person_count = 0
                salzh_count = 0
                all_klassen = {}
                entry_for_email = {}
                email_for_klasse_and_mode = {}
                entries.each do |x| 
                    entry_for_email[x[:email]] = x
                    if x[:mode] == 'contact_person'
                        contact_person_count += 1
                    else
                        salzh_count += 1
                    end
                    all_klassen[x[:klasse]] ||= []
                    all_klassen[x[:klasse]] << x[:email]
                    email_for_klasse_and_mode[x[:klasse]] ||= {}
                    email_for_klasse_and_mode[x[:klasse]][x[:mode]] ||= []
                    email_for_klasse_and_mode[x[:klasse]][x[:mode]] << x[:email]
                end

                io.puts "<p>"
                if contact_person_count > 0
                    io.puts "Sie haben momentan <span class='bg-warning' style='padding: 0.2em 0.5em; font-weight: bold; border-radius: 0.25em;'>#{contact_person_count}&nbsp;SuS</span>, die Kontaktpersonen sind."
                end
                if salzh_count > 0
                    io.puts "Sie haben momentan <span class='bg-danger' style='padding: 0.2em 0.5em; font-weight: bold; border-radius: 0.25em; color: #fff;'>#{salzh_count}&nbsp;SuS</span>, die im saLzH sind."
                end
                io.puts "</p>"
                io.puts "<div style='margin: 0 -10px 0 -10px;'><table class='table table-narrow narrow'>"
                io.puts "<tr><th>Klasse</th><th>Status</th></tr>"
                KLASSEN_ORDER.each do |klasse|
                    next unless all_klassen.include?(klasse)
                    io.puts "<tbody>"
                    io.puts "<tr class='klasse-click-row' data-klasse='#{klasse}'><td><strong>Klasse #{tr_klasse(klasse)}</strong></td>"
                    io.puts "<td>"
                    ['contact_person', 'salzh'].each do |mode|
                        io.puts "<span class='salzh-badge salzh-badge-big bg-#{mode == 'contact_person' ? 'warning': 'danger'}'><span>#{(email_for_klasse_and_mode[klasse][mode] || []).size}</span></span>"
                    end
                    io.puts "</td></tr>"
                    io.puts "</tbody>"
                    io.puts "<tbody style='display: none;'>"
                    all_klassen[klasse].each do |email|
                        badge =  
                        badge = "<span class='salzh-badge #{entry_for_email[email][:mode] == 'contact_person' ? 'bg-warning' : 'bg-danger'}'></span>"
                        io.puts "<tr><td colspan='2'>#{badge}#{@@user_info[email][:display_name]}</td></tr>"
                    end
                    io.puts "</tbody>"
                end
                io.puts "</table></div>"
                io.puts "<hr />"
                io.puts "<p>"
                io.puts "<strong>Was bedeutet das?</strong>"
                io.puts "</p>"
                if contact_person_count > 0
                    io.puts "<hr />"
                    io.puts "<p>"
                    io.puts "<strong><span class='bg-danger' style='padding: 0.2em 0.5em; font-weight: bold; border-radius: 0.25em; color: #fff;'>saLzH:</span></strong> Es handelt sich um SuS, die entweder positiv getestet wurden oder als Kontaktperson nach Rückmeldung der Eltern bestätigt freiwillig im saLzH sind. Bitte ermöglichen Sie diesen SuS eine Teilnahme am Unterricht."
                    io.puts "</p>"
                end
                if contact_person_count > 0
                    io.puts "<hr />"
                    io.puts "<p>"
                    io.puts "<strong><span class='bg-warning' style='padding: 0.2em 0.5em; font-weight: bold; border-radius: 0.25em;'>Kontaktpersonen:</span></strong> Diese SuS wurden als Kontaktperson identifiziert, besuchen aber trotzdem weiterhin die Schule. Für sie gilt:"
                    io.puts "</p>"
                    io.puts "<ul style='padding-left: 1.5em;'>"
                    io.puts "<li>tägliche Testung vor Beginn der Schultages (ein Test vom Vortag, z. B. aus einem Schnelltestzentrum, kann bei diesen SuS nicht akzeptiert werden)</li>"
                    io.puts "<li>durch die Klassenleitung wird am Freitag für jeden Tag des Wochenendes, der in diesen Status fällt, ein Schnelltest mitgegeben</li>"
                    io.puts "<li>zeigen diese Kinder Symptome (Husten, Fieber, Kopfschmerzen, …), dürfen sie das Schulhaus nicht mehr betreten</li>"
                    io.puts "<li>am gemeinsamen Essen in der Mensa darf nicht mehr teilgenommen werden</li>"
                    io.puts "<li>während des Sportunterrichts (Umkleide, Sport in der Halle) muss durchgehend eine Maske getragen werden – ist dies aufgrund der körperlichen Betätigung nicht möglich, nehmen diese Kinder nicht am Sportunterricht teil</li>"
                    io.puts "</ul>"
                end
                io.puts "</div>"
                io.string
            end
        end
    end
end
