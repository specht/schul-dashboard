SALZH_MODE_COLORS = {:contact_person => 'warning', :salzh => 'danger'}
SALZH_MODE_ICONS = {:contact_person => 'fa-exclamation', :salzh => 'fa-home'}

class Main < Sinatra::Base
    def self.get_salzh_status_for_emails(emails = nil) 

        # purge stale salzh entries
        today = Date.today.strftime('%Y-%m-%d')
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            WHERE s.end_date < {today}
            DETACH DELETE s;
        END_OF_QUERY
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (u:User)
            WHERE EXISTS(u.freiwillig_salzh) AND u.freiwillig_salzh < {today}
            REMOVE u.freiwillig_salzh;
        END_OF_QUERY
        temp = []
        temp2 = []

        if emails.nil?
            temp = $neo4j.neo4j_query(<<~END_OF_QUERY)
                MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
                RETURN COALESCE(s.mode, 'salzh') AS smode, s.end_date, u.email;
            END_OF_QUERY
            temp2 = $neo4j.neo4j_query(<<~END_OF_QUERY)
                MATCH (u:User)
                RETURN u.email, u.freiwillig_salzh;
            END_OF_QUERY
        else
            emails = [emails] unless emails.is_a? Array
            temp = $neo4j.neo4j_query(<<~END_OF_QUERY, {:emails => emails})
                MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
                WHERE u.email IN $emails
                RETURN COALESCE(s.mode, 'salzh') AS smode, s.end_date, u.email;
            END_OF_QUERY
            temp2 = $neo4j.neo4j_query(<<~END_OF_QUERY, {:emails => emails})
                MATCH (u:User)
                WHERE u.email IN $emails
                RETURN u.email, u.freiwillig_salzh;
            END_OF_QUERY
        end

        result = {}
        temp2.each do |row|
            email = row['u.email']
            result[email] = {
                :freiwillig_salzh => row['u.freiwillig_salzh'] # end_date or nil
            }
        end
        temp.each do |row|
            result[row['u.email']][:salzh] = row['smode']
            result[row['u.email']][:salzh_end_date] = row['s.end_date']
        end
        result.each_pair do |email, info|
            status = nil
            status_end_date = nil
            if info[:freiwillig_salzh]
                status = :salzh
                status_end_date = info[:freiwillig_salzh]
                if info[:salzh] == 'salzh'
                    status_end_date = [status_end_date, info[:salzh_end_date]].max
                end
            else
                if info[:salzh] == 'salzh'
                    status = :salzh
                    status_end_date = info[:salzh_end_date]
                elsif info[:salzh] == 'contact_person'
                    status = :contact_person
                    status_end_date = info[:salzh_end_date]
                end
            end
            info[:status] = status
            info[:status_end_date] = status_end_date
        end
        result
    end

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

    post '/api/set_freiwillig_salzh' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email, :end_date])
        neo4j_query(<<~END_OF_QUERY, :email => data[:email], :end_date => data[:end_date])
            MATCH (u:User {email: $email})
            SET u.freiwillig_salzh = $end_date;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_freiwillig_salzh' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email])
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            REMOVE u.freiwillig_salzh;
        END_OF_QUERY
        respond(:ok => true)
    end

    def self.get_current_salzh_sus
        # purge stale salzh entries
        today = Date.today.strftime('%Y-%m-%d')
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            WHERE s.end_date < {today}
            DETACH DELETE s;
        END_OF_QUERY

        rows = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
            RETURN u.email, COALESCE(s.mode, 'salzh') AS smode, s.end_date;
        END_OF_QUERY

        entries = []
        rows.each do |row|
            email = row['u.email']
            mode = row['smode']
            end_date = row['s.end_date']
            entries << {
                :email => email,
                :name => @@user_info[email][:display_name],
                :first_name => @@user_info[email][:display_first_name],
                :last_name => @@user_info[email][:display_last_name],
                :klasse => @@user_info[email][:klasse],
                :klasse_tr => tr_klasse(@@user_info[email][:klasse]),
                :salzh_mode => mode,
                :salzh_end_date => end_date
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

    def self.get_current_salzh_status
        entries = []
        temp = self.get_salzh_status_for_emails()
        temp.each_pair do |email, info|
            next unless @@user_info[email]
            next if @@user_info[email][:teacher]
            next if info[:status].nil?
            entries << {
                :email => email,
                :name => @@user_info[email][:display_name],
                :first_name => @@user_info[email][:display_first_name],
                :last_name => @@user_info[email][:display_last_name],
                :klasse => @@user_info[email][:klasse],
                :klasse_tr => tr_klasse(@@user_info[email][:klasse]),
                :status => info[:status],
                :status_end_date => info[:status_end_date]
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

    def get_current_salzh_status
        Main.get_current_salzh_status
    end

    def get_current_salzh_status_for_logged_in_teacher
        entries = get_current_salzh_status
        entries.select! do |entry|
            (@@schueler_for_teacher[@session_user[:shorthand]] || []).include?(entry[:email])
        end
        entries
    end

    def self.get_current_salzh_status_for_all_teachers
        all_entries = Main.get_current_salzh_status
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
            salzh_status = Main.get_salzh_status_for_emails(@session_user[:email])[@session_user[:email]]
            return '' if salzh_status[:status].nil?
            StringIO.open do |io|
                end_date = salzh_status[:status_end_date]
                if salzh_status[:status] == :salzh
                    io.puts "<div class='hint'>"
                    io.puts "<p><strong>Unterricht im saLzH</strong></p>"
                    io.puts "<p>Du bist <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> für das schulisch angeleite Lernen zu Hause (saLzH) eingetragen. Bitte schau regelmäßig in deinem Stundenplan nach, ob du Aufgaben in der Nextcloud oder im Lernraum bekommst oder ob Stunden per Jitsi durchgeführt werden.</p>"
                    io.puts "</div>"
                elsif salzh_status[:status] == :contact_person
                    io.puts "<div class='hint'>"
                    io.puts "<p><strong>Kontaktperson</strong></p>"
                    io.puts "<p>Du bist <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> als Kontaktperson markiert. Das heißt, dass du weiterhin in die Schule kommen darfst, aber einige Regeln beachten musst. Falls du freiwillig zu Hause bleiben möchtest, müssen deine Eltern dem Sekretariat <a href='mailto:sekretariat@gymnasiumsteglitz.de'>per E-Mail Bescheid geben</a>. Die folgenden Regeln gelten für dich:</p>"
                    io.puts "<hr />"
                    io.puts "<ul style='padding-left: 1.5em;'>"
                    io.puts "<li>tägliche Testung vor Beginn der Schultages (ein Test vom Vortag, z. B. aus einem Schnelltestzentrum, kann nicht akzeptiert werden)</li>"
                    io.puts "<li>du bekommst von deiner Klassenleitung (#{@@klassenleiter[@session_user[:klasse]].map { |shorthand| @@user_info[@@shorthands[shorthand]][:display_last_name] }.join(' oder ')}) am Freitag für jeden Tag des Wochenendes, an du noch Kontaktperson bist, einen Schnelltest mit nach Hause</li>"
                    io.puts "<li>falls du Symptome (Husten, Fieber, Kopfschmerzen, …) zeigst, darfst du das Schulhaus nicht mehr betreten</li>"
                    io.puts "<li>du darfst nicht mehr am gemeinsamen Essen in der Mensa teilnehmen</li>"
                    io.puts "<li>während des Sportunterrichts (Umkleide, Sport in der Halle) musst du durchgehend eine Maske tragen – ist dies aufgrund der körperlichen Betätigung nicht möglich, nimmst du nicht am Sportunterricht teil</li>"
                    io.puts "</ul>"
                    io.puts "</div>"
                end
                io.string
            end
        else
            entries = get_current_salzh_status_for_logged_in_teacher()
            return '' if entries.empty?
            StringIO.open do |io|
                io.puts "<div class='hint'>"
                # io.puts "<p><strong><div style='display: inline-block; padding: 4px; margin: -4px; border-radius: 4px' class='bg-warning'>SuS im saLzH</div></strong></p>"
                contact_person_count = 0
                salzh_count = 0
                all_klassen = {}
                entry_for_email = {}
                email_for_klasse_and_status = {}
                entries.each do |x| 
                    entry_for_email[x[:email]] = x
                    if x[:status] == :contact_person
                        contact_person_count += 1
                    elsif x[:status] == :salzh
                        salzh_count += 1
                    end
                    all_klassen[x[:klasse]] ||= []
                    all_klassen[x[:klasse]] << x[:email]
                    email_for_klasse_and_status[x[:klasse]] ||= {}
                    email_for_klasse_and_status[x[:klasse]][x[:status]] ||= []
                    email_for_klasse_and_status[x[:klasse]][x[:status]] << x[:email]
                end

                spans = []
                if contact_person_count > 0
                    spans << "#{contact_person_count}&nbsp;SuS, die Kontaktpersonen sind"
                end
                if salzh_count > 0
                    spans << "#{salzh_count}&nbsp;SuS im saLzH"
                end
                io.puts "<p>"
                io.puts "Sie haben momentan #{spans.map { |x| '<strong>' + x + '</strong>'}.join(' und ')}."
                io.puts "</p>"
                io.puts "<div style='margin: 0 -10px 0 -10px;'><table class='table table-narrow narrow'>"
                io.puts "<tr><th>Klasse</th><th>Status</th></tr>"
                KLASSEN_ORDER.each do |klasse|
                    next unless all_klassen.include?(klasse)
                    io.puts "<tbody>"
                    io.puts "<tr class='klasse-click-row' data-klasse='#{klasse}'><td>Klasse #{tr_klasse(klasse)}</td>"
                    io.puts "<td>"
                    [:contact_person, :salzh].each do |status|
                        if (email_for_klasse_and_status[klasse][status] || []).size > 0
                            io.puts "<span class='salzh-badge salzh-badge-big bg-#{status == :contact_person ? 'warning': 'danger'}'><span>#{(email_for_klasse_and_status[klasse][status] || []).size}</span></span>"
                        end
                    end
                    io.puts "</td></tr>"
                    io.puts "</tbody>"
                    io.puts "<tbody style='display: none;'>"
                    all_klassen[klasse].each do |email|
                        badge =  
                        badge = "<span style='position: relative; top: -1px;' class='salzh-badge salzh-badge-big bg-#{SALZH_MODE_COLORS[entry_for_email[email][:status]]}'><i class='fa #{SALZH_MODE_ICONS[entry_for_email[email][:status]]}'></i></span>"
                        io.puts "<tr><td colspan='2'>#{badge}#{@@user_info[email][:display_name]}</td></tr>"
                    end
                    io.puts "</tbody>"
                end
                io.puts "</table></div>"
                io.puts "<hr />"
                io.puts "<p style='cursor: pointer;' onclick=\"$('#salzh_explanation').slideDown();\">"
                io.puts "<strong>Was bedeutet das?</strong>"
                io.puts "</p>"
                io.puts "<div id='salzh_explanation' style='display: none;'>"
                if contact_person_count > 0
                    io.puts "<hr />"
                    io.puts "<p>"
                    io.puts "<strong><span class='bg-danger' style='padding: 0.2em 0.5em; font-weight: bold; border-radius: 0.25em; color: #fff;'>saLzH:</span></strong> Es handelt sich um SuS, die aus unter&shy;schied&shy;lichen Gründen im saLzH sind (z. B. positiv getestet / als Kontaktperson nach Rückmeldung der Eltern bestätigt freiwillig im saLzH / Aussetzung der Präsenz&shy;pflicht). Bitte ermöglichen Sie diesen SuS eine Teilnahme am Unterricht."
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
                io.puts "</div>"
                io.string
            end
        end
    end
end
