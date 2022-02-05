SALZH_MODE_COLORS = {:contact_person => 'warning', :salzh => 'danger', :hotspot_klasse => 'pink'}
SALZH_MODE_ICONS = {:contact_person => 'fa-exclamation', :salzh => 'fa-home', :hotspot_klasse => 'fa-fire'}
SALZH_MODE_LABEL = {:contact_person => 'Kontaktperson', :salzh => 'saLzH', :hotspot_klasse => 'Hotspot-Klasse'}

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
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (k:Klasse)
            WHERE k.hotspot_end_date < {today}
            DETACH DELETE k;
        END_OF_QUERY
        temp = []
        temp2 = []

        hotspot_dates = {}
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (k:Klasse)
            RETURN k.klasse, k.hotspot_end_date;
        END_OF_QUERY
        rows.each do |x|
            hotspot_dates[x['k.klasse']] = x['k.hotspot_end_date']
        end

        if emails.nil?
            temp = $neo4j.neo4j_query(<<~END_OF_QUERY)
                MATCH (s:Salzh)-[:BELONGS_TO]->(u:User)
                RETURN COALESCE(s.mode, 'salzh') AS smode, s.end_date, u.email;
            END_OF_QUERY
            temp2 = $neo4j.neo4j_query(<<~END_OF_QUERY)
                MATCH (u:User)
                RETURN u.email, u.freiwillig_salzh, COALESCE(u.testing_required, TRUE) AS testing_required;
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
                RETURN u.email, u.freiwillig_salzh, COALESCE(u.testing_required, TRUE) AS testing_required;
            END_OF_QUERY
        end

        result = {}
        temp2.each do |row|
            email = row['u.email']
            result[email] = {
                :freiwillig_salzh => row['u.freiwillig_salzh'], # end_date or nil
                :testing_required => row['testing_required']
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
            if status.nil?
                # see if it's a hotspot klasse
                if @@user_info[email]
                    klasse = @@user_info[email][:klasse]
                    if hotspot_dates[klasse]
                        status = :hotspot_klasse
                        status_end_date = hotspot_dates[klasse]
                    end
                end
            end
            info[:status] = status
            info[:status_end_date] = status_end_date
            wday = DateTime.now.wday
            needs_testing_today = true
            unless info[:testing_required]
                needs_testing_today = false
            end
            info[:needs_testing_today] = needs_testing_today
            
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

    post '/api/set_hotspot_klasse_end_date' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:klasse, :end_date])
        neo4j_query(<<~END_OF_QUERY, :klasse => data[:klasse], :end_date => data[:end_date])
            MERGE (k:Klasse {klasse: $klasse})
            SET k.hotspot_end_date = $end_date;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_hotspot_klasse_end_date' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:klasse])
        neo4j_query(<<~END_OF_QUERY, :klasse => data[:klasse])
            MERGE (k:Klasse {klasse: $klasse})
            REMOVE k.hotspot_end_date;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/minimize_salzh_explanation' do
        require_teacher!
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: $email})
            SET u.hide_salzh_panel_explanation = true;
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/toggle_testing_required' do
        require_user_who_can_manage_salzh!
        data = parse_request_data(:required_keys => [:email])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.testing_required = NOT (COALESCE(u.testing_required, TRUE))
            RETURN u.testing_required;
        END_OF_QUERY
        respond(:ok => true, :testing_required => result['u.testing_required'])
    end

    def self.get_hotspot_klassen
        # purge stale entries
        today = Date.today.strftime('%Y-%m-%d')
        $neo4j.neo4j_query(<<~END_OF_QUERY, :today => today)
            MATCH (k:Klasse)
            WHERE k.hotspot_end_date < {today}
            DETACH DELETE k;
        END_OF_QUERY

        hotspot_dates = {}
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (k:Klasse)
            RETURN k.klasse, k.hotspot_end_date;
        END_OF_QUERY
        rows.each do |x|
            hotspot_dates[x['k.klasse']] = x['k.hotspot_end_date']
        end
        StringIO.open do |io|
            KLASSEN_ORDER.each do |klasse|
                next if ['11', '12'].include?(klasse)
                io.puts "<tr data-klasse='#{klasse}'>"
                io.puts "<td>#{tr_klasse(klasse)}</td>"
                # io.puts "<td>#{@@schueler_for_klasse[klasse].size}</td>"
                io.puts "<td>"
                hotspot_end_date = hotspot_dates[klasse]
                io.puts "<div class='input-group input-group-sm'><input type='date' class='form-control ti_hotspot_end_date' value='#{hotspot_end_date}' /><div class='input-group-append'><button #{hotspot_end_date.nil? ? 'disabled' : ''} class='btn #{hotspot_end_date.nil? ? 'btn-outline-secondary' : 'btn-danger'} bu_delete_hotspot_end_date'><i class='fa fa-trash'></i></button></div></div>"
                io.puts "</td>"
            io.puts "</tr>"
            end
            io.string
        end
    end

    def get_hotspot_klassen
        Main.get_hotspot_klassen
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
                    p = Date.parse(end_date) + 1
                    while [0, 6].include?(p.wday) || @@holiday_dates.include?(p.strftime("%Y-%m-%d"))
                        p += 1
                    end
                    io.puts "<div class='hint'>"
                    io.puts "<p><strong>Unterricht im saLzH</strong></p>"
                    io.puts "<p>Du bist <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> für das schulisch angeleite Lernen zu Hause (saLzH) eingetragen. Bitte schau regelmäßig in deinem Stunden&shy;plan nach, ob du Aufgaben in der Nextcloud oder im Lernraum bekommst oder ob Stunden per Jitsi durch&shy;geführt werden. <strong>Ab dem #{p.strftime('%d.%m.')}</strong> erwarten wir dich wieder in der Schule.</p>"
                    io.puts "</div>"
                elsif salzh_status[:status] == :contact_person
                    io.puts "<div class='hint'>"
                    io.puts "<p><strong>Kontaktperson</strong></p>"
                    io.puts "<p>Du bist <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> als Kontakt&shy;person markiert. Das heißt, dass du weiterhin in die Schule kommen darfst, aber einige Regeln beachten musst. Falls du freiwillig zu Hause bleiben möchtest, müssen deine Eltern dem Sekretariat <a href='mailto:sekretariat@gymnasiumsteglitz.de'>per E-Mail Bescheid geben</a>. Die folgenden Regeln gelten für dich:</p>"
                    io.puts "<hr />"
                    io.puts "<ul style='padding-left: 1.5em;'>"
                    io.puts "<li>tägliche Testung vor Beginn der Schultages (ein Test vom Vortag, z. B. aus einem Schnell&shy;test&shy;zentrum, kann nicht akzeptiert werden)</li>"
                    if ['11', '12'].include?(@session_user[:klasse])
                        io.puts "<li>du bekommst von deiner Tutorin / deinem Tutor am Freitag für jeden Tag des Wochenendes, an du noch Kontakt&shy;person bist, einen Schnelltest mit nach Hause</li>"
                    else
                        io.puts "<li>du bekommst von deiner Klassen&shy;leitung (#{@@klassenleiter[@session_user[:klasse]].map { |shorthand| @@user_info[@@shorthands[shorthand]][:display_last_name] }.join(' oder ')}) am Freitag für jeden Tag des Wochenendes, an du noch Kontakt&shy;person bist, einen Schnelltest mit nach Hause</li>"
                    end
                    io.puts "<li>falls du Symptome (Husten, Fieber, Kopfschmerzen, …) zeigst, darfst du das Schulhaus nicht mehr betreten</li>"
                    io.puts "<li>du darfst nicht mehr am gemeinsamen Essen in der Mensa teilnehmen</li>"
                    io.puts "<li>während des Sport&shy;unter&shy;richts (Umkleide, Sport in der Halle) musst du durch&shy;gehend eine Maske tragen – ist dies aufgrund der körperlichen Betätigung nicht möglich, nimmst du nicht am Sportunterricht teil</li>"
                    io.puts "</ul>"
                    io.puts "</div>"
                elsif salzh_status[:status] == :hotspot_klasse
                    io.puts "<div class='hint'>"
                    io.puts "<p><strong>Klasse mit erhöhtem Infektionsaufkommen</strong></p>"
                    io.puts "<p>Da in deiner Klasse momentan ein erhöhtes Infektionsgeschehen herrscht, wirst du <strong>bis zum #{Date.parse(end_date).strftime('%d.%m.')}</strong> täglich getestet.</p>"
                    io.puts "</div>"
                end
                io.string
            end
        else
            entries = get_current_salzh_status_for_logged_in_teacher()
            return '' if entries.empty?
            hide_explanations = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})['hide']
                MATCH (u:User {email: $email})
                RETURN COALESCE(u.hide_salzh_panel_explanation, false) AS hide;
            END_OF_QUERY
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
                        next unless [:salzh, :contact_person].include?(entry_for_email[email][:status])
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
                io.puts "<div id='salzh_explanation' style='display: #{hide_explanations ? 'none': 'block'};'>"
                if salzh_count > 0
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
                io.puts "<button class='btn btn-xs btn-outline-secondary' id='bu_minimize_salzh_explanation'>Diese Information minimieren</button>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
    end

    get '/api/test_list' do
        require_user_who_can_manage_salzh!
        klassenleiter = Main.class_variable_get(:@@klassenleiter)
        shorthands = Main.class_variable_get(:@@shorthands)
        user_info = Main.class_variable_get(:@@user_info)
        main = self
        salzh_status = Main.get_salzh_status_for_emails()
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, 
                                :margin => 0) do
            font_families.update("RobotoCondensed" => {
                :normal => "/app/fonts/RobotoCondensed-Regular.ttf",
                :italic => "/app/fonts/RobotoCondensed-Italic.ttf",
                :bold => "/app/fonts/RobotoCondensed-Bold.ttf",
                :bold_italic => "/app/fonts/RobotoCondensed-BoldItalic.ttf"
                })
            font_families.update("Roboto" => {
                :normal => "/app/fonts/Roboto-Regular.ttf",
                :italic => "/app/fonts/Roboto-Italic.ttf",
                :bold => "/app/fonts/Roboto-Bold.ttf",
                :bold_italic => "/app/fonts/Roboto-BoldItalic.ttf"
                })
            font('RobotoCondensed') do
                KLASSEN_ORDER.each.with_index do |klasse, index|
                    next if ['11', '12'].include?(klasse)

                    # found_one = false
                    # main.iterate_directory(klasse) do |email, i|
                    #     status = salzh_status[email]
                    #     if status[:needs_testing_today]
                    #         found_one = true
                    #         break
                    #     end
                    # end
                    # next unless found_one

                    start_new_page if index > 0
                    font_size 11
                    any_strike = false
                    bounding_box([2.cm, 297.mm - 2.cm], width: 17.cm, height: 257.mm) do
                        float do
                            text "#{DateTime.now.strftime("%d.%m.%Y")}", :align => :right
                        end
                        text "<b>Testliste Klasse #{Main.tr_klasse(klasse)}</b>   (#{(klassenleiter[klasse] || []).map { |shorthand| (user_info[shorthands[shorthand]] || {})[:display_last_name] }.reject { |x| x.nil? }.join(' / ')})", :inline_format => true

                        line_width 0.2.mm

                        main.iterate_directory(klasse) do |email, i|
                            status = salzh_status[email]
                            label_type = Main.get_test_list_label_type(status[:status], status[:testing_required], true)
                            # status is salzh / contact_person / hotspot_klasse
                            # needs_testing_today: true / false
                            if label_type == :enabled
                                fill_color '000000'
                                stroke_color '000000'
                            elsif label_type == :disabled
                                fill_color 'a0a0a0'
                                stroke_color 'a0a0a0'
                            end
                            user = @@user_info[email]
                            y = 242.mm - 6.7.mm * i
                            draw_text "#{i + 1}.", :at => [0.mm, y]
                            draw_text "#{label_type == :disabled ? '(' : ''}#{user[:last_name]}, #{user[:first_name]}#{label_type == :disabled ? ')' : ''}", :at => [7.mm, y]

                            # TK pos neg TZ Verspätung

                            dist = 20.0

                            %w(TK pos. neg. TZ).each.with_index do |label, i|
                                x = 76 + dist * i
                                stroke { rectangle [x.mm, y + 3.mm], 3.mm, 3.mm }
                                draw_text label, :at => [x.mm + 5.mm, y]
                            end


                            stroke_color '000000'
                            fill_color '000000'

                            if label_type == :strike
                                stroke { rectangle [(76 + dist * 4).mm, y + 3.mm], 3.mm, 3.mm }
                                draw_text "Sek", :at => [(76 + dist * 4).mm + 5.mm, y]
                                stroke { line [0.mm, y + 1.mm], [7.3.cm, y + 1.mm] }
                                any_strike = true
                            end

                            stroke { line [0.mm, y + 5.2.mm], [17.cm, y + 5.2.mm] } if i == 0
                            stroke { line [0.mm, y - 2.mm], [17.cm, y - 2.mm] }
                        end
                        bounding_box([0, 1.5.cm], width: 17.cm, height: 4.cm) do
                            float do
                                text "<b>Legende</b>", :inline_format => true, :leading => 3.mm
                                text "Nachname, Vorname", :inline_format => true, :leading => 1.mm
                                fill_color 'a0a0a0'
                                text "(Nachname, Vorname)", :inline_format => true, :leading => 1.mm
                                fill_color '000000'
                                stroke_color '000000'
                                text "Nachname, Vorname", :inline_format => true, :leading => 1.mm
                                stroke { line [0.mm, 21.mm], [3.1.cm, 21.mm] }
                            end
                        end

                        bounding_box([3.5.cm, 1.5.cm], width: 11.cm, height: 4.cm) do
                            float do
                                text " ", :inline_format => true, :leading => 3.mm
                                text "–", :inline_format => true, :leading => 1.mm
                                text "–", :inline_format => true, :leading => 1.mm
                                text "–", :inline_format => true, :leading => 1.mm
                            end
                        end

                        bounding_box([3.8.cm, 1.5.cm], width: 11.cm, height: 4.cm) do
                            float do
                                text " ", :inline_format => true, :leading => 3.mm
                                text "muss heute getestet werden", :inline_format => true, :leading => 1.mm
                                text "kann heute getestet werden", :inline_format => true, :leading => 1.mm
                                text "wurde für heute <b>nicht</b> in der Schule erwartet – bitte zunächst <b>keine Eintragung</b> machen und zur Abklärung ins Sekretariat schicken", :inline_format => true, :leading => 1.mm
                            end
                        end

                        bounding_box([0, 244.mm - 6.7.mm * @@schueler_for_klasse[klasse].size], width: 6.2.cm, height: 2.cm) do
                            text "Testkassette abgegeben", :align => :right
                            text "im Testzentrum getestet", :align => :right
                            if any_strike
                                text "war im Sekretariat", :align => :right
                            end
                        end
                        bounding_box([6.4.cm, 249.mm - 6.7.mm * @@schueler_for_klasse[klasse].size], width: 16.2.cm, height: 2.5.cm) do
                            stroke do
                                line [0.cm, 18.mm], [1.35.cm, 18.mm]
                                line [1.35.cm, 18.mm], [1.35.cm, 21.mm]
                            end
                            stroke do
                                line [0.cm, 18.mm - 11.0], [7.35.cm, 18.mm - 11.0]
                                line [7.35.cm, 18.mm - 11.0], [7.35.cm, 21.mm]
                            end
                            if any_strike
                                stroke do
                                    line [0.cm, 18.mm - 22.0], [9.35.cm, 18.mm - 22.0]
                                    line [9.35.cm, 18.mm - 22.0], [9.35.cm, 21.mm]
                                end
                            end
                        end
                        stroke { rectangle [14.5.cm, 0.5.cm], 2.5.cm, 1.5.cm }
                        font_size 8
                        draw_text "Kürzel", :at => [154.mm, -13.1.mm]
                        font_size 11
                    end

                        # stroke { rectangle [0, 0], 12.85.cm, 8.5.cm }
                        # bounding_box([5.mm, -5.mm], width: 11.85.cm) do
                        #     font_size 10
                            
                        #     text "<b>Code für Online-Abstimmung #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</b>", inline_format: true

                end
            end
        end
        # respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    def self.get_test_list_label_type(status, regular_test_required, regular_test_day)
        if status == :salzh
            return :strike
        end
        if regular_test_required == false
            return :disabled
        end
        if regular_test_required && !regular_test_day && status == nil
            return :disabled
        end
        return :enabled
    end

    def get_test_regime_html()
        StringIO.open do |io|
            [true, false].each do |regular_test_day|
                [true, false].each do |regular_test_required|
                    [:salzh, :contact_person, :hotspot_klasse, nil].each do |status|
                        io.puts "<tr>"
                        io.puts "<td><span style='position: relative; top: -1px;' class='salzh-badge salzh-badge-big bg-#{SALZH_MODE_COLORS[status]}'><i class='fa #{SALZH_MODE_ICONS[status]}'></i></span>#{SALZH_MODE_LABEL[status] || '&ndash;'}</td>"
                        io.puts "<td>#{regular_test_required ? 'notwendig' : 'nicht notwendig'}</td>"
                        io.puts "<td>#{regular_test_day ? 'ja' : 'nein'}</td>"
                        label_type = Main.get_test_list_label_type(status, regular_test_required, regular_test_day)
                        if label_type == :enabled
                            io.puts "<td>Vorname Nachname</td>"
                        elsif label_type == :disabled
                            io.puts "<td style='color: #aaa;'>(Vorname Nachname)</td>"
                        elsif label_type == :strike
                            io.puts "<td><s style='color: #000;'>Vorname Nachname</s></td>"
                        else
                            io.puts "<td>???</td>"
                        end
                        io.puts "</tr>"
                    end
                end
            end
            io.string
        end
    end

end
