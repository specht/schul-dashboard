class Main < Sinatra::Base
    post '/api/update_salzh_for_sus' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email, :end_date])
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email], :end_date => data[:end_date])
            MATCH (u:User {email: {email}})
            MERGE (s:Salzh)-[:BELONGS_TO]->(u)
            SET s.end_date = {end_date}
            RETURN s;
        END_OF_QUERY
        respond(:ok => true)
    end

    def get_current_salzh_sus
        today = Date.today.strftime('%Y-%m-%d')
        # purge stale salzh entries
        neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            WHERE s.end_date < {today}
            DETACH DELETE s;
        END_OF_QUERY
        rows = neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            RETURN s, u
            ORDER BY s.end_date;
        END_OF_QUERY
        entries = rows.map do |x|
            email = x['u'].props[:email]
            {
                :email => email,
                :name => @@user_info[email][:display_name],
                :klasse => @@user_info[email][:klasse],
                :end_date => x['s'].props[:end_date]
            }
        end
        entries.sort! do |a, b|
            (a[:klasse] == b[:klasse]) ?
            (a[:name] <=> b[:name]) :
            (KLASSEN_ORDER.index(a[:klasse]) <=> KLASSEN_ORDER.index(b[:klasse]))
        end
        entries
    end

    def get_current_salzh_sus_for_logged_in_teacher
        entries = get_current_salzh_sus
        entries.select! do |entry|
            @@klassen_for_shorthand[@session_user[:shorthand]].include?(entry[:klasse])
        end
        entries
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
                io.puts "<p><strong>SuS im saLzH</strong></p>"
                all_klassen = {}
                entries.each do |x| 
                    all_klassen[x[:klasse]] ||= []
                    all_klassen[x[:klasse]] << x[:email]
                end
                io.puts "<p>Momentan befinde#{entries.size == 1 ? 't' : 'n'} sich <strong>#{entries.size} SuS</strong> in <strong>#{all_klassen.size} Klasse#{all_klassen.size == 1 ? '' : 'n'}</strong> im pandemiebedingten saLzH. Bitte ermöglichen Sie diesen SuS nach Möglichkeit eine Teilnahme am Unterricht im saLzH.</p>"
                io.puts "<div style='margin: 0 -10px 0 -10px;'><table class='table table-narrow narrow'>"
                # io.puts "<tr><th>Klasse</th><th>SuS</th></tr>"
                KLASSEN_ORDER.each do |klasse|
                    next unless all_klassen.include?(klasse)
                    io.puts "<tr class='klasse-click-row' data-klasse='#{klasse}'><td><strong>Klasse #{klasse}</strong></td><td>#{all_klassen[klasse].size} SuS</td></tr>"
                end
                io.puts "</table></div>"
                io.puts "</div>"
                io.string
            end
        end
    end
end
