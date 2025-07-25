
NOBILIARY_PREFIX_REGEX = "/\\b(von|van|de|da|di|le)\\b/i"

class Main < Sinatra::Base
    def self.iterate_kurse(&block)
        @@lessons[:lesson_keys].keys.sort do |a, b|
            @@lessons[:lesson_keys][a][:pretty_folder_name].downcase <=> @@lessons[:lesson_keys][b][:pretty_folder_name].downcase
        end.each do |lesson_key|
            info = @@lessons[:lesson_keys][lesson_key]
            klassen = info[:klassen] || Set.new()
            next unless klassen.include?('11') || klassen.include?('12')
            yield lesson_key
        end
    end

    def print_kurslisten
        assert(user_with_role_logged_in?(:can_see_kurslisten))
        StringIO.open do |io|
            Main.iterate_kurse do |lesson_key|
                info = @@lessons[:lesson_keys][lesson_key]
                io.puts "<h4>#{info[:pretty_folder_name]} &ndash; #{info[:lehrer].join(', ')} <span style='font-size: 80%;'>[#{lesson_key}]</span></h4>"
                io.puts "<table class='table table-sm table-striped'>"
                (@@schueler_for_lesson[lesson_key] || []).each.with_index do |email, index|
                    io.puts "<tr><td style='width: 2em; text-align: right;'>#{index + 1}.</td><td>#{@@user_info[email][:display_name]}</td></tr>"
                end
                io.puts "</table>"
            end
            io.string
        end
    end

    def self.determine_hide_from_sus
        hide_from_sus = false
        now = Time.now
        if now.strftime('%Y-%m-%d') < @@config[:first_school_day]
            hide_from_sus = true
        elsif now.strftime('%Y-%m-%d') == @@config[:first_school_day]
            hide_from_sus = now.strftime('%H:%M:%S') < '08:10:00'
        end
        # hide_from_sus = false if DEVELOPMENT
        hide_from_sus
    end

    def mail_addresses_table(klasse)
        assert((teacher_logged_in?) || (@session_user[:klasse] == klasse))
        klassenleiter_logged_in = (@@klassenleiter[klasse] || []).include?(@session_user[:shorthand]) || admin_logged_in?
        all_homeschooling_users = Main.get_all_homeschooling_users()
        salzh_status = Main.get_salzh_status_for_emails(Main.class_variable_get(:@@schueler_for_klasse)[klasse] || [])
        dashboard_amt = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
            MATCH (u:User {has_dashboard_amt: TRUE})
            RETURN u.email;
        END_OF_QUERY
        dashboard_amt = Set.new(dashboard_amt)
        dashboard_amt_names = []
        is_klasse = KLASSEN_ORDER.include?(klasse)
        StringIO.open do |io|
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-12'>"
            # io.puts "<div class='alert alert-warning'>"
            # io.puts "Bitte überprüfen Sie die <strong>Gruppenzuordnung (A/B)</strong> und markieren Sie alle Kinder, die aus gesundheitlichen Gründen / Quarantäne nicht in die Schule kommen können, als <strong>»zu Hause«</strong>."
            # io.puts "Auf die Jitsi-Streams können momentan nur SuS zugreifen, die laut ihrer Gruppenzuordnung in der aktuellen Woche zu Hause sind oder explizit als »zu Hause« markiert sind."
            # io.puts "</div>"
            # if teacher_logged_in?
            #     io.puts "<div class='pull-right' style='position: relative; top: 10px;'>"
            #     [:salzh, :contact_person, :hotspot_klasse].each do |status|
            #         salzh_label = "<span style='margin-left: 2em;'><span class='salzh-badge salzh-badge-big bg-#{SALZH_MODE_COLORS[status]}'><i class='fa #{SALZH_MODE_ICONS[status]}'></i></span>&nbsp;#{SALZH_MODE_LABEL[status]}</span>"
            #         io.puts salzh_label
            #     end
            #     io.puts "</div>"
            # end
            if is_klasse
                io.puts "<h3>Klasse #{tr_klasse(klasse)}</h3>"
            else
                io.puts "<h3>#{@@lessons[:lesson_keys][klasse][:pretty_folder_name]}</h3>"
            end
            io.puts "<p>"
            io.puts "</p>"
            # <div style='max-width: 100%; overflow-x: auto;'>
            # <table class='table' style='width: unset; min-width: 100%;'>

            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='klassen_table table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Nr.</th>"
            io.puts "<th></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            unless is_klasse
                io.puts "<th>Klasse</th>"
            end
            if teacher_logged_in?
                io.puts "<th>Geburtsdatum</th>"
                io.puts "<th>Bildungsgang</th>"
                io.puts "<th>Stufe</th>"
            end
            # io.puts "<th>Status</th>"
            # if can_manage_salzh_logged_in?
            #     io.puts "<th>Reguläre Testung</th>"
            #     io.puts "<th>Freiwilliges saLzH bis</th>"
            # end
            # if klassenleiter_logged_in
            #     io.puts "<th>Freiwillige Testung</th>"
            # end
            io.puts "<th>E-Mail-Adresse</th>"
            # io.puts "<th style='width: 140px;'>Homeschooling</th>"
            if teacher_logged_in?
                if ['11', '12'].include?(klasse)
                    io.puts "<th>Antikenfahrt</th>"
                end
                if ['5', '6'].include?(klasse[0])
                    io.puts "<th>Forschertage</th>"
                end
            end
            if teacher_logged_in?
                if klassenleiter_for_klasse_logged_in?(klasse)
                    io.puts "<th>Dashboard-Amt</th>"
                end
                io.puts "<th>A/B</th>"
                io.puts "<th>Letzter Zugriff</th>"
                io.puts "<th>Eltern-E-Mail-Adresse</th>"
                if klassenleiter_for_klasse_logged_in?(klasse) || admin_logged_in? || user_with_role_logged_in?(:sekretariat)
                    io.puts "<th>E-Mail-Brief</th>"
                end
            end
            schueler_liste = @@schueler_for_klasse[klasse] || @@schueler_for_lesson[klasse] || []
            has_oberstufe = schueler_liste.any? { |email| (@@user_info[email][:klassenstufe] || 7) >= 11 }
            if teacher_logged_in? && has_oberstufe
                io.puts "<th>Tutor:in</th>"
            end
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            results = neo4j_query(<<~END_OF_QUERY, :email_addresses => schueler_liste)
                MATCH (u:User)
                WHERE u.email IN $email_addresses
                RETURN u.email, u.last_access, COALESCE(u.group2, 'A') AS group2, COALESCE(u.group_af, '') AS group_af, COALESCE(u.group_ft, '') AS group_ft;
            END_OF_QUERY
            last_access = {}
            group2_for_email = {}
            group_af_for_email = {}
            group_ft_for_email = {}
            results.each do |x|
                last_access[x['u.email']] = x['u.last_access']
                group2_for_email[x['u.email']] = x['group2']
                group_af_for_email[x['u.email']] = x['group_af']
                group_ft_for_email[x['u.email']] = x['group_ft']
            end

            (schueler_liste || []).sort do |a, b|
                (@@user_info[a][:last_name].unicode_normalize(:nfd) == @@user_info[b][:last_name].unicode_normalize(:nfd)) ?
                (@@user_info[a][:first_name].unicode_normalize(:nfd) <=> @@user_info[b][:first_name].unicode_normalize(:nfd)) :
                (@@user_info[a][:last_name].unicode_normalize(:nfd) <=> @@user_info[b][:last_name].unicode_normalize(:nfd))
            end.each.with_index do |email, _|
                record = @@user_info[email]
                dashboard_amt_names << record[:display_name] if dashboard_amt.include?(email)
                io.puts "<tr class='user_row' data-email='#{email}' data-display-name='#{record[:display_name]}' data-first-name='#{record[:first_name]}' data-pronoun='#{record[:geschlecht] == 'm' ? 'er' : 'sie'}'>"
                io.puts "<td>#{_ + 1}.</td>"
                io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                salzh_style = ''
                salzh_class = ''
                if teacher_logged_in?
                    if salzh_status[email] && [:contact_person, :salzh].include?(salzh_status[email][:status])
                        salzh_style = 'padding: 2px 4px; margin: -2px -4px; display: inline-block; border-radius: 4px;'
                        salzh_class = "bg-#{SALZH_MODE_COLORS[(salzh_status[email] || {})[:status]]}"
                    end
                end
                io.puts "<td><div class='#{salzh_class}' style='#{salzh_style}'>#{record[:last_name]}</div></td>"
                io.puts "<td><div class='#{salzh_class}' style='#{salzh_style}'>#{record[:first_name]}</div></td>"
                unless is_klasse
                    io.puts "<td>#{tr_klasse(record[:klasse])}</td>"
                end
                if teacher_logged_in?
                    if record[:geburtstag]
                        io.puts "<td>#{Date.parse(record[:geburtstag]).strftime('%d.%m.%Y')}</td>"
                    else
                        io.puts "<td>&ndash;</td>"
                    end
                    io.puts "<td>#{tr_bildungsgang(record[:bildungsgang])}</td>"
                    io.puts "<td>#{record[:klassenstufe]}</td>"
                end
                # salzh_label = ''
                # if salzh_status[email][:status]
                #     salzh_label = "<span class='salzh-badge salzh-badge-big bg-#{SALZH_MODE_COLORS[(salzh_status[email] || {})[:status]]}'><i class='fa #{SALZH_MODE_ICONS[(salzh_status[email] || {})[:status]]}'></i></span>&nbsp;&nbsp;bis #{Date.parse(salzh_status[email][:status_end_date]).strftime('%d.%m.')}"

                #     # salzh_label = "<div class='bg-#{SALZH_MODE_COLORS[(salzh_status[email] || {})[:status]]}' style='text-align: center; padding: 4px; margin: -4px; border-radius: 4px;'><i class='fa #{SALZH_MODE_ICONS[(salzh_status[email] || {})[:status]]}'></i>&nbsp;&nbsp;bis #{Date.parse(salzh_status[email][:status_end_date]).strftime('%d.%m.')}</div>"
                # end
                # io.puts "<td>#{salzh_label}</td>"
                # if can_manage_salzh_logged_in?
                #     io.puts "<td>"
                #     testing_required = salzh_status[email][:testing_required]
                #     if testing_required
                #         io.puts "<button class='btn btn-sm btn-success bu_toggle_testing_required'><i class='fa fa-check'></i>&nbsp;&nbsp;notwendig</button>"
                #     else
                #         io.puts "<button class='btn btn-sm btn-outline-secondary bu_toggle_testing_required'><i class='fa fa-times'></i>&nbsp;&nbsp;nicht notwendig</button>"
                #     end
                #     io.puts "</td>"

                #     io.puts "<td>"
                #     freiwillig_salzh = salzh_status[email][:freiwillig_salzh]
                #     io.puts "<div class='input-group'><input type='date' class='form-control ti_freiwillig_salzh' value='#{freiwillig_salzh}' /><div class='input-group-append'><button #{freiwillig_salzh.nil? ? 'disabled' : ''} class='btn #{freiwillig_salzh.nil? ? 'btn-outline-secondary' : 'btn-danger'} bu_delete_freiwillig_salzh'><i class='fa fa-trash'></i></button></div></div>"
                #     io.puts "</td>"
                # end
                # if klassenleiter_logged_in
                #     io.puts "<td>"
                #     voluntary_testing = salzh_status[email][:voluntary_testing]
                #     if voluntary_testing
                #         io.puts "<button class='btn btn-sm btn-success bu_toggle_voluntary_testing'><i class='fa fa-check'></i>&nbsp;&nbsp;nimmt teil</button>"
                #     else
                #         io.puts "<button class='btn btn-sm btn-outline-secondary bu_toggle_voluntary_testing'><i class='fa fa-times'></i>&nbsp;&nbsp;nimmt nicht teil</button>"
                #     end
                #     io.puts "</td>"
                # end
                io.puts "<td>"
                print_email_field(io, record[:email])
                io.puts "</td>"
                # homeschooling_button_disabled = klassenleiter_logged_in ? '' : 'disabled'
                # if all_homeschooling_users.include?(email)
                #     io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-info btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-home'></i>&nbsp;&nbsp;zu Hause</button></td>"
                # else
                #     io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-secondary btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-building'></i>&nbsp;&nbsp;Präsenz</button></td>"
                # end
                if teacher_logged_in?
                    if ['11', '12'].include?(klasse)
                        io.puts "<td><div class='group-af-button #{user_who_can_manage_antikenfahrt_logged_in? ? '' : 'disabled'}' data-email='#{email}'>#{GROUP_AF_ICONS[group_af_for_email[email]]}</div></td>"
                    end
                    if ['5', '6'].include?(klasse[0])
                        io.puts "<td><div class='group-ft-button #{admin_logged_in? ? '' : 'disabled'}' data-email='#{email}'>#{GROUP_FT_ICONS[group_ft_for_email[email]] || '❓'}</div></td>"
                    end
                end
                if teacher_logged_in?
                    if klassenleiter_for_klasse_logged_in?(klasse)
                        if dashboard_amt.include?(email)
                            io.puts "<td><button class='bu-toggle-dashboard-amt btn btn-sm btn-success' data-state='true'><i class='fa fa-check'></i>&nbsp;&nbsp;Dashboard-Amt</button></td>"
                        else
                            io.puts "<td><button class='bu-toggle-dashboard-amt btn btn-sm btn-outline-secondary' data-state='false'><i class='fa fa-times'></i>&nbsp;&nbsp;Dashboard-Amt</button></td>"
                        end
                    end
                    io.puts "<td><div class='group2-button group2-#{group2_for_email[email]}' data-email='#{email}'>#{group2_for_email[email]}</div></td>"
                    la_label = 'noch nie angemeldet'
                    today = Date.today.to_s
                    if last_access[email]
                        days = (Date.today - Date.parse(last_access[email])).to_i
                        if days == 0
                            la_label = 'heute'
                        elsif days == 1
                            la_label = 'gestern'
                        elsif days == 2
                            la_label = 'vorgestern'
                        elsif days == 3
                            la_label = 'vor 3 Tagen'
                        elsif days == 4
                            la_label = 'vor 4 Tagen'
                        elsif days == 5
                            la_label = 'vor 5 Tagen'
                        elsif days == 6
                            la_label = 'vor 6 Tagen'
                        elsif days < 14
                            la_label = 'vor 1 Woche'
                        elsif days < 21
                            la_label = 'vor 2 Wochen'
                        elsif days < 28
                            la_label = 'vor 3 Wochen'
                        elsif days < 35
                            la_label = 'vor 4 Wochen'
                        else
                            la_label = 'vor mehreren Wochen'
                        end
                    end
                    io.puts "<td>#{la_label}</td>"
                    io.puts "<td>"
                    print_email_field(io, "eltern.#{record[:email]}")
                    io.puts "</td>"
                    if klassenleiter_for_klasse_logged_in?(klasse) || admin_logged_in? || user_with_role_logged_in?(:sekretariat)
                        io.puts "<td>"
                        io.puts "<button class='bu_print_email_letter btn btn-outline-secondary btn-sm'><i class='fa fa-envelope-o'></i>&nbsp;&nbsp;E-Mail-Brief</button>"
                        io.puts "</td>"
                    end
                    if has_oberstufe
                        tutor = '&ndash;'
                        if record[:tutor]
                            tutor = @@user_info[record[:tutor]][:display_name]
                        end
                        io.puts "<td>#{tutor}</td>"
                    end
                end
                io.puts "</tr>"
            end
            if teacher_logged_in?
                if is_klasse
                    io.puts "<tr>"
                    io.puts "<td colspan='4'></td>"
                    io.puts "<td colspan='2'><b>E-Mail an die Klasse #{tr_klasse(klasse)}</b></td>"
                    io.puts "<td></td>"
                    io.puts "<td colspan='3'><b>E-Mail an alle Eltern der Klasse #{tr_klasse(klasse)}</b></td>"
                    io.puts "</tr>"
                    io.puts "<tr class='user_row'>"
                    io.puts "<td colspan='4'></td>"
                    io.puts "<td colspan='2'>"
                    print_email_field(io, "klasse.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase)
                    io.puts "</td>"
                    io.puts "<td></td>"
                    io.puts "<td colspan='3'>"
                    print_email_field(io, "eltern.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase)
                    io.puts "</td>"
                    io.puts "</tr>"
                else
                    io.puts "<tr>"
                    io.puts "<td colspan='4'></td>"
                    io.puts "<td colspan='2'><b>E-Mail an alle SuS des #{@@lessons[:lesson_keys][klasse][:pretty_folder_name]}</b></td>"
                    io.puts "<td></td>"
                    io.puts "<td colspan='3'><b>E-Mail an alle Eltern des #{@@lessons[:lesson_keys][klasse][:pretty_folder_name]}</b></td>"
                    io.puts "</tr>"
                    io.puts "<tr class='user_row'>"
                    io.puts "<td colspan='4'></td>"
                    io.puts "<td colspan='2'>"
                    print_email_field(io, "#{@@lessons[:lesson_keys][klasse][:list_email]}@#{MAILING_LIST_DOMAIN}".downcase)
                    io.puts "</td>"
                    io.puts "<td></td>"
                    io.puts "<td colspan='3'>"
                    print_email_field(io, "eltern.#{@@lessons[:lesson_keys][klasse][:list_email]}@#{MAILING_LIST_DOMAIN}".downcase)
                    io.puts "</td>"
                    io.puts "</tr>"
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            if is_klasse
                unless klassenleiter_for_klasse_logged_in?(klasse)
                    unless dashboard_amt_names.empty?
                        io.puts "<p>Das Dashboard-Amt wird ausgeübt von #{join_with_sep(dashboard_amt_names, ', ', ' und ')}.</p>"
                    end
                end
                if teacher_logged_in?
                    io.puts "<a class='btn btn-primary' href='/show_login_codes/#{klasse}'><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Live-Anmeldungen der Klasse zeigen</a>"
                    io.puts "<a class='btn btn-warning' href='/email_overview/#{klasse}'><i class='fa fa-envelope-o'></i>&nbsp;&nbsp;E-Mails aus dem Unterricht</a>"
                end
            end
            # if teacher_logged_in?
            #     io.puts "<a class='btn btn-warning' href='/at_overview/#{klasse}'><i class='fa fa-star-o'></i>&nbsp;&nbsp;AT-Notizen</a>"
            # end
            # io.puts print_stream_restriction_table(klasse)
            if teacher_logged_in?
                io.puts "<hr>"
                if is_klasse
                    io.puts "<h3>Schülerlisten Klasse #{tr_klasse(klasse)}</h3>"
                else
                    io.puts "<h3>Schülerlisten #{@@lessons[:lesson_keys][klasse][:pretty_folder_name]}</h3>"
                end
    #             io.puts "<div style='text-align: center;'>"
                io.puts "<a href='/api/directory_xlsx/#{klasse}' class='btn btn-primary'><i class='fa fa-file-excel-o'></i>&nbsp;&nbsp;Excel-Tabelle herunterladen</a>"
                io.puts "<a href='/api/directory_timetex_pdf/by_last_name/#{klasse}' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Timetex-PDF herunterladen</a>"
                io.puts "<a href='/api/directory_timetex_pdf/by_first_name/#{klasse}' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Timetex-PDF herunterladen (nach Vornamen sortiert)</a>"
                io.puts "<a href='/api/directory_json/#{klasse}' class='btn btn-primary'><i class='fa fa-file-code-o'></i>&nbsp;&nbsp;JSON herunterladen</a>"
            end
            if is_klasse
                io.puts "<hr>"
                hide_from_sus = Main.determine_hide_from_sus()
                if teacher_logged_in?
                    io.puts "<h3>Stundenpläne der Klasse #{tr_klasse(klasse)} zum Ausdrucken</h3>"
                elsif schueler_logged_in?
                    unless hide_from_sus
                        io.puts "<h3>Stundenpläne zum Ausdrucken</h3>"
                        io.puts "<p>Den Hintergrund der Stundenpläne kannst über dein Profil verändern, da immer der Hintergrund aus deinem Dashboard genommen wird.</p>"
                    end
                end
                if teacher_logged_in?
                    io.puts "<a href='/api/get_timetable_pdf_for_klasse/#{klasse}' target='_blank' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Klassensatz Stundenpläne (#{@@schueler_for_klasse[klasse].size} Seiten)</a>"
                    unless ['11', '12'].include?(klasse)
                        io.puts "<a href='/api/get_room_timetable_pdf/#{klasse}' target='_blank' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Raumplan für die Klassenzimmertür</a>"
                    end
                    io.puts "<div id='additional_teacher_content'></div>"
                elsif schueler_logged_in?
                    unless hide_from_sus
                        io.puts "<a href='/api/get_single_timetable_pdf' target='_blank' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;PDF herunterladen</a>"
                        io.puts "<a href='/api/get_single_timetable_with_png_addition_pdf' target='_blank' class='btn btn-success'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;PDF herunterladen (mit Symbolen)</a>"
                    end
                end
                unless schueler_logged_in? && hide_from_sus
                    io.puts "<hr>"
                    io.puts "<h3>Lehrkräfte der Klasse #{tr_klasse(klasse)}</h3>"
                    io.puts "<div class='table-responsive'>"
                    io.puts "<table class='table table-condensed table-striped narrow'>"
                    io.puts "<thead>"
                    io.puts "<tr>"
                    io.puts "<th>Kürzel</th>"
                    io.puts "<th>Name</th>"
                    io.puts "<th>Fächer (Wochenstunden)</th>"
                    io.puts "<th>E-Mail-Adresse</th>"
                    io.puts "</tr>"
                    io.puts "</thead>"
                    io.puts "<tbody>"
                    old_is_klassenleiter = true
                    (@@teachers_for_klasse[klasse] || {}).keys.sort do |a, b|
                        name_comp = begin
                            @@user_info[@@shorthands[a]][:last_name].unicode_normalize(:nfd) <=> @@user_info[@@shorthands[b]][:last_name].unicode_normalize(:nfd)
                        rescue
                            a <=> b
                        end

                        a_kli = (@@klassenleiter[klasse] || []).index(a)
                        b_kli = (@@klassenleiter[klasse] || []).index(b)

                        if a_kli.nil?
                            if b_kli.nil?
                                name_comp
                            else
                                1
                            end
                        else
                            if b_kli.nil?
                                -1
                            else
                                a_kli <=> b_kli
                            end
                        end
                    end.each do |shorthand|
                        lehrer = @@user_info[@@shorthands[shorthand]]
                        next if lehrer.nil?
                        is_klassenleiter = (@@klassenleiter[klasse] || []).include?(shorthand)

                        if old_is_klassenleiter && !is_klassenleiter
                            io.puts "<tr class='sep user_row'>"
                        else
                            io.puts "<tr class='user_row'>"
                        end
                        old_is_klassenleiter = is_klassenleiter
                        io.puts "<td>#{shorthand}#{is_klassenleiter ? ' (KL)' : ''}</td>"
        #                 io.puts "<td>#{((lehrer[:titel] || '') + ' ' + (lehrer[:last_name] || shorthand)).strip}</td>"
                        io.puts "<td>#{lehrer[teacher_logged_in? ? :display_name : :display_name_official] || ''}</td>"
                        hours = @@teachers_for_klasse[klasse][shorthand].keys.sort do |a, b|
                            @@teachers_for_klasse[klasse][shorthand][b] <=> @@teachers_for_klasse[klasse][shorthand][a]
                        end.map do |x|
                            fach = x.gsub('.', '')
                            fach = @@faecher[fach] if @@faecher[fach]
                            "#{fach} (#{@@teachers_for_klasse[klasse][shorthand][x]})"
                        end.join(', ')
                        io.puts "<td>#{hours}</td>"
                        if lehrer.empty?
                            io.puts "<td></td>"
                        else
                            io.puts "<td>"
                            print_email_field(io, lehrer[:email])
                            io.puts "</td>"
                        end
                        io.puts "</tr>"
                    end
                    if teacher_logged_in?
                        io.puts "<tr>"
                        io.puts "<td colspan='3'></td>"
                        io.puts "<td><b>E-Mail an alle Lehrer/innen der Klasse #{tr_klasse(klasse)}</b></td>"
                        io.puts "</tr>"
                        io.puts "<tr class='user_row'>"
                        io.puts "<td colspan='3'></td>"
                        io.puts "<td>"
                        print_email_field(io, "lehrer.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase)
                        io.puts "</td>"
                        io.puts "</tr>"
                    end
                    io.puts "</tbody>"
                    io.puts "</table>"
                    io.puts "</div>"
                end
            end
            io.puts "</div>"
            io.string
        end
    end

    def self.get_all_homeschooling_users()
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {homeschooling: true})
            RETURN u.email
        END_OF_QUERY
        all_homeschooling_users = Set.new()
        temp.each do |user|
            all_homeschooling_users << user['u.email']
        end
        all_homeschooling_users
    end

    def self.get_switch_week_for_date(d)
        ds = d.strftime('%Y-%m-%d')
        d_info = SWITCH_WEEKS.keys.sort.select do |d|
            ds >= d
        end.last
        info = SWITCH_WEEKS[d_info]
        return nil if info.nil?
        week_number = (d.strftime('%-V').to_i - Date.parse(d_info).strftime('%-V').to_i)
        return (((week_number + (info[0].ord - 'A'.ord)) % info[1]) + 'A'.ord).chr
    end

    # Returns A or B or nil
    def self.get_current_ab_week()
        get_switch_week_for_date(Date.today)
    end

    def self.get_homeschooling_for_user_by_dauer_salzh(email)
        info = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.homeschooling, false) AS homeschooling
        END_OF_QUERY
        marked_as_homeschooling = info['homeschooling']
        marked_as_homeschooling
    end

    def self.get_homeschooling_for_user_by_switch_week(email, datum, group2_for_email)
        group2 = nil
        if group2_for_email.nil?
            info = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})
                MATCH (u:User {email: $email})
                RETURN COALESCE(u.group2, 'A') AS group2
            END_OF_QUERY
            group2 = info['group2']
        else
            group2 = group2_for_email
        end
        current_week = get_switch_week_for_date(Date.parse(datum))
        marked_as_homeschooling_by_week = (current_week != group2)
        marked_as_homeschooling_by_week
    end

    def self.get_homeschooling_for_user(email, datum = nil, is_homeschooling_user = nil, group2_for_email = nil)
        datum ||= Date.today.strftime('%Y-%m-%d')
        if is_homeschooling_user.nil?
            self.get_homeschooling_for_user_by_switch_week(email, datum, group2_for_email) || self.get_homeschooling_for_user_by_dauer_salzh(email)
        else
            self.get_homeschooling_for_user_by_switch_week(email, datum, group2_for_email)
        end
    end

    def self.update_antikenfahrt_groups()
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:email => x['email'], :group_af => x['group_af'] }}
            MATCH (u:User)
            RETURN u.email AS email, COALESCE(u.group_af, '') AS group_af;
        END_OF_QUERY
        groups = {}
        main_user_info = @@user_info
        results.each do |row|
            next unless ['gr', 'it'].include?(row[:group_af])
            user_info = main_user_info[row[:email]]
            next unless user_info
            next unless user_info[:teacher] == false
            next unless ['11', '12'].include?(user_info[:klasse])
            groups[user_info[:klasse]] ||= {}
            groups[user_info[:klasse]][row[:group_af]] ||= []
            groups[user_info[:klasse]][row[:group_af]] << row[:email]
        end
        @@antikenfahrt_recipients = {
            :recipients => {},
            :groups => []
        }
        @@antikenfahrt_mailing_lists = {}
        ['11', '12'].each do |klasse|
            ['gr', 'it'].each do |group_af|
                next if ((groups[klasse] || {})[group_af] || []).empty?
                @@antikenfahrt_recipients[:groups] << "/af/#{klasse}/#{group_af}/sus"
                @@antikenfahrt_recipients[:recipients]["/af/#{klasse}/#{group_af}/sus"] = {
                    :label => "Antikenfahrt #{GROUP_AF_ICONS[group_af]} – SuS #{klasse}",
                    :entries => groups[klasse][group_af]
                }
                @@antikenfahrt_recipients[:groups] << "/af/#{klasse}/#{group_af}/eltern"
                @@antikenfahrt_recipients[:recipients]["/af/#{klasse}/#{group_af}/eltern"] = {
                    :label => "Antikenfahrt #{GROUP_AF_ICONS[group_af]} – Eltern #{klasse} (extern)",
                    :external => true,
                    :entries => groups[klasse][group_af].map { |x| 'eltern.' + x }
                }
                @@antikenfahrt_mailing_lists["antikenfahrt.#{group_af}.#{klasse}@#{MAILING_LIST_DOMAIN}"] = {
                    :label => "Antikenfahrt #{GROUP_AF_ICONS[group_af]} – SuS Klassenstufe #{klasse}",
                    :recipients => groups[klasse][group_af]
                }
                @@antikenfahrt_mailing_lists["antikenfahrt.#{group_af}.eltern.#{klasse}@#{MAILING_LIST_DOMAIN}"] = {
                    :label => "Antikenfahrt #{GROUP_AF_ICONS[group_af]} – Eltern Klassenstufe #{klasse}",
                    :recipients => groups[klasse][group_af].map { |x| 'eltern.' + x }
                }
            end
        end
    end

    def self.update_forschertage_groups()
        results = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:email => x['email'], :group_ft => x['group_ft'] }}
            MATCH (u:User)
            RETURN u.email AS email, COALESCE(u.group_ft, '') AS group_ft;
        END_OF_QUERY
        groups = {}
        main_user_info = @@user_info
        results.each do |row|
            next unless ['nawi', 'gewi', 'musik', 'medien'].include?(row[:group_ft])
            user_info = main_user_info[row[:email]]
            next unless user_info
            next unless user_info[:teacher] == false
            next unless ['5', '6'].include?(user_info[:klasse][0])
            groups[user_info[:klasse][0]] ||= {}
            groups[user_info[:klasse][0]][row[:group_ft]] ||= []
            groups[user_info[:klasse][0]][row[:group_ft]] << row[:email]
        end
        @@forschertage_recipients = {
            :recipients => {},
            :groups => []
        }
        @@forschertage_mailing_lists = {}
        ['5', '6'].each do |klasse|
            ['nawi', 'gewi', 'musik', 'medien'].each do |group_ft|
                next if ((groups[klasse] || {})[group_ft] || []).empty?
                @@forschertage_recipients[:groups] << "/ft/#{klasse}/#{group_ft}/sus"
                @@forschertage_recipients[:recipients]["/ft/#{klasse}/#{group_ft}/sus"] = {
                    :label => "Forschertage #{GROUP_FT_ICONS[group_ft]} – SuS #{klasse}",
                    :entries => groups[klasse][group_ft]
                }
                @@forschertage_recipients[:groups] << "/af/#{klasse}/#{group_ft}/eltern"
                @@forschertage_recipients[:recipients]["/af/#{klasse}/#{group_ft}/eltern"] = {
                    :label => "Forschertage #{GROUP_FT_ICONS[group_ft]} – Eltern #{klasse} (extern)",
                    :external => true,
                    :entries => groups[klasse][group_ft].map { |x| 'eltern.' + x }
                }
                @@forschertage_mailing_lists["forschertage.#{group_ft}.#{klasse}@#{MAILING_LIST_DOMAIN}"] = {
                    :label => "Forschertage #{GROUP_FT_ICONS[group_ft]} – SuS Klassenstufe #{klasse}",
                    :recipients => groups[klasse][group_ft]
                }
                @@forschertage_mailing_lists["forschertage.#{group_ft}.eltern.#{klasse}@#{MAILING_LIST_DOMAIN}"] = {
                    :label => "Forschertage #{GROUP_FT_ICONS[group_ft]} – Eltern Klassenstufe #{klasse}",
                    :recipients => groups[klasse][group_ft].map { |x| 'eltern.' + x }
                }
            end
        end
    end

    def self.update_techpost_groups()
        results = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)-[:HAS_AMT {amt: 'technikamt'}]->(v:Techpost)
            RETURN u.email
        END_OF_QUERY
        techpost_users = results.map { |row| row['u.email'] }

        @@techpost_recipients = {
            :recipients => {},
            :groups => []
        }
        @@techpost_mailing_lists = {}

        @@techpost_recipients[:groups] << "/techpost/sus"
        @@techpost_recipients[:recipients]["/techpost/sus"] = {
            :label => "Technikamt",
            :entries => techpost_users
        }

        @@techpost_recipients[:groups] << "/techpost/eltern"
        @@techpost_recipients[:recipients]["/techpost/eltern"] = {
            :label => "Technikamt - Eltern (extern)",
            :external => true,
            :entries => techpost_users.map { |email| 'eltern.' + email }
        }

        @@techpost_mailing_lists["technikamt@#{MAILING_LIST_DOMAIN}"] = {
            :label => "Technikamt",
            :recipients => techpost_users
        }

        @@techpost_mailing_lists["eltern.technikamt@#{MAILING_LIST_DOMAIN}"] = {
            :label => "Technikamt (Eltern)",
            :recipients => techpost_users.map { |email| 'eltern.' + email }
        }
    end

    def self.update_angebote_groups()
        @@angebote_mailing_lists = {}
        $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:info => x['a'], :recipient => x['u.email'], :owner => x['ou.email'] } }.each do |row|
            MATCH (a:Angebot)-[:DEFINED_BY]->(ou:User)
            WITH a, ou
            OPTIONAL MATCH (u:User)-[r:IS_PART_OF]->(a)
            RETURN a, u.email, ou.email
            ORDER BY a.created DESC, a.id;
        END_OF_QUERY
            ['', 'eltern.'].each do |who|
                list_email = who + remove_accents(row[:info][:name].downcase).split(/[^a-z0-9]+/).map { |x| x.strip }.reject { |x| x.empty? }.join('-') + '@' + MAILING_LIST_DOMAIN
                @@angebote_mailing_lists[list_email] ||= {
                    :label => row[:info][:name] + (who.empty? ? '' : ' (Eltern)'),
                    :recipients => [],
                }
                @@angebote_mailing_lists[list_email][:recipients] << who + row[:recipient]
            end
        end
    end

    def self.update_projekttage_groups()
        @@projekttage_mailing_lists = {}
        $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| {:recipient => x['u.email'] } }.each do |row|
            MATCH (u:User)
            WHERE NOT (u)-[:VOTED_FOR]->(:Projekttage)
            RETURN u.email;
        END_OF_QUERY
            email = row[:recipient]
            next unless user_has_role(email, :schueler) && ((@@user_info[email][:klassenstufe] || 7) < 10)
            ['', 'eltern.'].each do |who|
                list_email = who + 'kein.projekt.gewaehlt' + '@' + MAILING_LIST_DOMAIN
                @@projekttage_mailing_lists[list_email] ||= {
                    :label => 'Kein Projekt gewählt' + (who.empty? ? '' : ' (Eltern)'),
                    :recipients => [],
                }
                @@projekttage_mailing_lists[list_email][:recipients] << who + email
            end
        end
    end

    def self.update_lehrbuchverein_groups()
        @@lehrbuchverein_mailing_lists = {}
        KLASSEN_ORDER.each do |klasse|
            (@@schueler_for_klasse[klasse] || []).each do |email|
                target = @@lehrmittelverein_state_cache[email] ? :empfaenger : :selbstzahler
                next if target == :selbstzahler && klasse.to_i < 7
                ['', 'eltern.'].each do |who|
                    list_email = "#{who}lmv-#{target}@#{MAILING_LIST_DOMAIN}"
                    @@lehrbuchverein_mailing_lists[list_email] ||= {
                        :label => "Lehrmittelverein #{target == :empfaenger ? 'Empfänger' : 'Selbstzahler ab Klassenstufe 7'}#{who.empty? ? '' : ' (Eltern)'}",
                        :recipients => [],
                    }
                    @@lehrbuchverein_mailing_lists[list_email][:recipients] << who + email
                end
            end
        end
    end

    post '/api/toggle_homeschooling' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        unless admin_logged_in?
            klasse = @@user_info[email][:klasse]
            assert(@@klassenleiter[klasse].include?(@session_user[:shorthand]))
        end
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: $email})
            SET u.homeschooling = NOT COALESCE(u.homeschooling, FALSE)
            RETURN u.homeschooling;
        END_OF_QUERY
        trigger_update("_#{email}")
        respond(:ok => true, :homeschooling => result['u.homeschooling'])
    end

    def self.iterate_directory(which, first_key = :last_name, second_key = :first_name, &block)
        email_list = @@schueler_for_klasse[which]
        if email_list.nil?
            # try lesson key
            email_list = @@schueler_for_lesson[which]
        end
        email_list ||= []
        (email_list).sort do |a, b|
            (@@user_info[a][first_key].unicode_normalize(:nfd) == @@user_info[b][first_key].unicode_normalize(:nfd)) ?
            (@@user_info[a][second_key].unicode_normalize(:nfd) <=> @@user_info[b][second_key].unicode_normalize(:nfd)) :
            (@@user_info[a][first_key].unicode_normalize(:nfd) <=> @@user_info[b][first_key].unicode_normalize(:nfd))
        end.each.with_index do |email, i|
            yield email, i
        end
    end

    def iterate_directory(which, first_key = :last_name, second_key = :first_name, &block)
        Main.iterate_directory(which, first_key, second_key, &block)
    end

    get '/api/directory_timetex_pdf/by_last_name/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_timetex_pdf/by_last_name/', '')
        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait,
                                :margin => 0) do
            font('/app/fonts/RobotoCondensed-Regular.ttf') do
                font_size 12
                main.iterate_directory(klasse) do |email, i|
                    user = @@user_info[email]
                    y = 297.mm - 20.mm - 20.7.pt * i
                    draw_text "#{user[:last_name].unicode_normalize(:nfc)}, #{user[:first_name].unicode_normalize(:nfc)}", :at => [30.mm, y + 6.pt]
                    line_width 0.2.mm
                    stroke { line [30.mm, y + 20.7.pt], [77.mm, y + 20.7.pt] } if i == 0
                    stroke { line [30.mm, y], [77.mm, y] }
                end
            end
        end
        # respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    get '/api/directory_timetex_pdf/by_first_name/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_timetex_pdf/by_first_name/', '')
        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait,
                                :margin => 0) do
            font('/app/fonts/RobotoCondensed-Regular.ttf') do
                font_size 12
                main.iterate_directory(klasse, :display_name, nil) do |email, i|
                    user = @@user_info[email]
                    y = 297.mm - 20.mm - 20.7.pt * i
                    draw_text "#{user[:display_name].unicode_normalize(:nfc)}", :at => [30.mm, y + 6.pt]
                    line_width 0.2.mm
                    stroke { line [30.mm, y + 20.7.pt], [77.mm, y + 20.7.pt] } if i == 0
                    stroke { line [30.mm, y], [77.mm, y] }
                end
            end
        end
        # respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    get '/api/print_offline_users' do
        require_admin!
        emails = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
            MATCH (u:User) WHERE NOT EXISTS(u.last_access)
            RETURN u.email;
        END_OF_QUERY
        never_seen_users = Set.new(emails)
        emails = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
            MATCH (u:User) WHERE EXISTS(u.last_access)
            RETURN u.email;
        END_OF_QUERY
        seen_users = Set.new(emails)

        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait,
                                  :margin => 2.cm) do
            @@klassen_order.each_with_index do |klasse, i|
                font_size 12
                if ['11', '12'].include?(klasse)
                    font_size 10
                end
                start_new_page if i > 0
                text "<b>Klasse #{klasse}</b>\n\n", inline_format: true
                unless ['11', '12'].include?(klasse)
                    text "Klassenleitung: #{(@@klassenleiter[klasse] || ['-']).join(', ')}\n\n"
                end
                seen_count = (Set.new(@@schueler_for_klasse[klasse]) & seen_users).size
                text "Bisher mindestens einmal am Dashboard angemeldet haben sich <b>#{seen_count}</b> von <b>#{@@schueler_for_klasse[klasse].size}</b> SuS.\n\n", inline_format: true
                text "Folgende SuS haben sich bisher <b>noch nicht</b> am Dashboard angemeldet und können deshalb auch bisher nicht auf die Nextcloud zugreifen:\n\n", inline_format: true
                @@schueler_for_klasse[klasse].each do |email|
                    next unless never_seen_users.include?(email)
                    user = @@user_info[email]
                    text "#{user[:display_name].unicode_normalize(:nfc)}\n"
                end
                text "\n\nBitte erinnern Sie die SuS daran, schnellstmöglich ihr E-Mail-Postfach einzurichten, sich am Dashboard anzumelden und sich bei der Nextcloud anzumelden. ", inline_format: true
                text "Wer seinen E-Mail-Zettel verloren hat, schreibt bitte eine E-Mail an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} – <b>#{WEBSITE_MAINTAINER_EMAIL}</b> – dort bekommt jeder die Zugangsdaten zur Not noch einmal als PDF.\n\n", inline_format: true
                text "Zuerst muss das E-Mail-Postfach eingerichtet werden. Den Zugangscode für das Dashboard bekommt man per E-Mail und die Zugangsdaten für die Nextcloud finden sich im Dashboard im Menü ganz rechts: <em>In Nextcloud anmelden…</em>\n\n", inline_format: true
                text "Bei Fällen, in denen ein E-Mail-Postfach abgelehnt wird, suchen Sie bitte das Gespräch und erfragen Sie die Gründe für diese Entscheidung. Es lassen sich für dieses Problem fast immer Lösungen im gegenseitigen Einvernehmen finden und deshalb bitte ich Sie, auch in diesen Fällen einen Kontakt zu #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} herzustellen."
            end
        end
        STDERR.puts "Noch nie angemeldete Lehrer:"
        @@lehrer_order.each do |email|
            next unless never_seen_users.include?(email)
            user = @@user_info[email]
            STDERR.puts user[:display_name]
        end
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    get '/api/directory_xlsx/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_xlsx/', '')
        file = Tempfile.new('foo')
        result = nil
        begin
            workbook = WriteXLSX.new(file.path)
            sheet = workbook.add_worksheet
            format_header = workbook.add_format({:bold => true})
            sheet.write(0, 0, 'Nachname', format_header)
            sheet.write(0, 1, 'Vorname', format_header)
            sheet.write(0, 2, 'Geburtsdatum', format_header)
            sheet.write(0, 3, 'Klasse', format_header)
            sheet.write(0, 4, 'Gruppe', format_header)
            sheet.write(0, 5, 'E-Mail', format_header)
            sheet.write(0, 6, 'E-Mail der Eltern', format_header)
            sheet.set_column(0, 1, 16)
            sheet.set_column(5, 6, 48)
            iterate_directory(klasse) do |email, i|
                user = @@user_info[email]
                group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
                    MATCH (u:User {email: $email})
                    RETURN COALESCE(u.group2, 'A') AS group2;
                END_OF_QUERY
                sheet.write(i + 1, 0, user[:last_name])
                sheet.write(i + 1, 1, user[:first_name])
                sheet.write(i + 1, 2, Date.parse(user[:geburtstag]).strftime('%d.%m.%Y')) if user[:geburtstag]
                sheet.write(i + 1, 3, user[:klasse])
                sheet.write(i + 1, 4, group2)
                sheet.write(i + 1, 5, user[:email])
                sheet.write(i + 1, 6, 'eltern.' + user[:email])
            end
            workbook.close
            result = File.read(file.path)
        ensure
            file.close
            file.unlink
        end
        respond_raw_with_mimetype_and_filename(result, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', "Klasse #{klasse}.xlsx")
    end

    get '/api/directory_json/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_json/', '')
        entries = []
        iterate_directory(klasse) do |email, i|
            user = @@user_info[email]
            entries << {
                :first_name => user[:first_name],
                :last_name => user[:last_name],
                :display_name => user[:display_name],
                :email => user[:email],
                :geschlecht => user[:geschlecht],
                :nc_login => user[:nc_login],
            }
        end
        respond_raw_with_mimetype(entries.to_json, 'application/json')
    end

    post '/api/toggle_group2_for_user' do
        require_teacher!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        if group2 == 'A'
            group2 = 'B'
        else
            group2 = 'A'
        end
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :group2 => group2)['group2']
            MATCH (u:User {email: $email})
            SET u.group2 = $group2
            RETURN u.group2 AS group2;
        END_OF_QUERY
        respond(:group2 => group2)
    end

    post '/api/toggle_group_af_for_user' do
        require_user_who_can_manage_antikenfahrt!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        group_af = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group_af']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.group_af, '') AS group_af;
        END_OF_QUERY
        index = GROUP_AF_ICON_KEYS.index(group_af) || 0
        index = (index + 1) % GROUP_AF_ICON_KEYS.size
        group_af = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :group_af => GROUP_AF_ICON_KEYS[index])['group_af']
            MATCH (u:User {email: $email})
            SET u.group_af = $group_af
            RETURN u.group_af AS group_af;
        END_OF_QUERY
        Main.update_antikenfahrt_groups()
        Main.update_mailing_lists()

        respond(:group_af => group_af)
    end

    post '/api/toggle_group_ft_for_user' do
        assert(user_with_role_logged_in?(:can_manage_forschertage))
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        group_ft = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group_ft']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.group_ft, '') AS group_ft;
        END_OF_QUERY
        index = GROUP_FT_ICON_KEYS.index(group_ft) || 0
        index = (index + 1) % GROUP_FT_ICON_KEYS.size
        group_ft = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :group_ft => GROUP_FT_ICON_KEYS[index])['group_ft']
            MATCH (u:User {email: $email})
            SET u.group_ft = $group_ft
            RETURN u.group_ft AS group_ft;
        END_OF_QUERY
        Main.update_forschertage_groups()
        Main.update_mailing_lists()

        respond(:group_ft => group_ft)
    end

    def schueler_for_lesson(lesson_key)
        results = (@@schueler_for_lesson[lesson_key] || []).map do |email|
            i = {}
            [:email, :first_name, :last_name, :display_name, :nc_login, :group2].each do |k|
                i[k] = @@user_info[email][k]
            end
            i
        end
        temp = neo4j_query(<<~END_OF_QUERY, :email_addresses => (@@schueler_for_lesson[lesson_key] || []))
            MATCH (u:User)
            WHERE u.email IN $email_addresses
            RETURN u.email, COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        temp = Hash[temp.map { |x| [x['u.email'], x['group2']] }]
        results.map! do |x|
            x[:group2] = temp[x[:email]]
            x
        end
        results
    end

    def print_mailing_list(io, list_email)
        return unless @@mailing_lists.include?(list_email)
        assert(user_with_role_logged_in?(:can_use_mailing_lists))
        io.puts "<tr class='user_row'>"
        info = @@mailing_lists[list_email]
        io.puts "<td class='list_email_label'>#{info[:label]}</td>"
        io.puts "<td>"
        print_email_field(io, list_email)
        io.puts "</td>"
        if teacher_logged_in? || technikteam_logged_in?
            io.puts "<td style='text-align: right;'><button data-list-email='#{list_email}' class='btn btn-warning btn-sm bu-toggle-adresses'>#{info[:recipients].size} Adressen&nbsp;&nbsp;<i class='fa fa-chevron-down'></i></button></td>"
            io.puts "</tr>"
            io.puts "<tbody style='display: none;' class='list_email_emails' data-list-email='#{list_email}'>"
            emails = []
            # STDERR.puts list_email
            # STDERR.puts info[:recipients].to_yaml
            info[:recipients].sort do |a, b|
                an = ((@@user_info[a.sub(/^eltern\./, '')] || {})[:display_name] || '').downcase.unicode_normalize(:nfd)
                bn = ((@@user_info[b.sub(/^eltern\./, '')] || {})[:display_name] || '').downcase.unicode_normalize(:nfd)
                an <=> bn
            end.each do |email|
                emails << email
                name = (@@user_info[email] || {})[:display_name] || ''
                if email[0, 7] == 'eltern.'
                    name = (@@user_info[email.sub('eltern.', '')] || {})[:display_name] || ''
                    name = "Eltern von #{name}"
                end
                io.puts "<tr class='user_row'>"
                io.puts "<td>#{name}</td>"
                io.puts "<td colspan='2'>"
                print_email_field(io, email)
                io.puts "</td>"
                io.puts "</tr>"
            end
            io.puts "<tr class='user_row'>"
            io.puts "<td>Bei Verteiler-Ausfall (bitte in BCC)</td>"
            io.puts "<td colspan='2'>"
            print_email_field(io, emails.join('; '))
            io.puts "</td>"
            io.puts "</tr>"
        else
            io.puts "<td style='text-align: right;'>#{info[:recipients].size} Adressen</td>"
        end
        io.puts "</tbody>"
    end

    def print_mailing_lists()
        StringIO.open do |io|
            io.puts "<table class='table table-condensed narrow' style='width: unset; min-width: 100%;'>"
            remaining_mailing_lists = Set.new(@@mailing_lists.keys)
            @@klassen_order.each do |klasse|
                io.puts "<tr><th colspan='3'>Klasse #{tr_klasse(klasse)}</th></tr>"
                ["klasse.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase,
                 "eltern.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase,
                 "lehrer.#{klasse}@#{MAILING_LIST_DOMAIN}".downcase].each do |list_email|
                    print_mailing_list(io, list_email)
                    remaining_mailing_lists.delete(list_email)
                end
                if ['11', '12'].include?(klasse)
                    ['gr', 'it'].each do |group_af|
                        ['', '.eltern'].each do |extra|
                            list_email = "antikenfahrt.#{group_af}#{extra}.#{klasse}@#{MAILING_LIST_DOMAIN}"
                            if @@mailing_lists[list_email]
                                print_mailing_list(io, list_email)
                                remaining_mailing_lists.delete(list_email)
                            end
                        end
                    end
                end
                if ['5', '6'].include?(klasse)
                    ['nawi', 'gewi', 'musik', 'medien'].each do |group_ft|
                        ['', '.eltern'].each do |extra|
                            list_email = "forschertage.#{group_ft}#{extra}.#{klasse}@#{MAILING_LIST_DOMAIN}"
                            if @@mailing_lists[list_email]
                                print_mailing_list(io, list_email)
                                remaining_mailing_lists.delete(list_email)
                            end
                        end
                    end
                end
            end
            [5, 6, 7, 8, 9, 10, 11, 12].each do |klasse|
                io.puts "<tr><th colspan='3'>Klassenstufe #{klasse}</th></tr>"
                ['sus', 'eltern', 'lehrer'].each do |role|
                    list_email = "#{role}.klassenstufe.#{klasse}@#{MAILING_LIST_DOMAIN}"
                    print_mailing_list(io, list_email)
                    remaining_mailing_lists.delete(list_email)
                end
            end
            io.puts "<tr><th colspan='3'>Klassenleiter-Teams</th></tr>"
            [5, 6, 7, 8, 9, 10].each do |klasse|
                list_email = "team.#{klasse}@#{MAILING_LIST_DOMAIN}"
                print_mailing_list(io, list_email)
                remaining_mailing_lists.delete(list_email)
            end
            print_mailing_list(io, "kl@#{MAILING_LIST_DOMAIN}")
            remaining_mailing_lists.delete("kl@#{MAILING_LIST_DOMAIN}")
            io.puts "<tr><th colspan='3'>Gesamte Schule</th></tr>"
            ["sus@#{MAILING_LIST_DOMAIN}",
             "lehrer@#{MAILING_LIST_DOMAIN}",
             "eltern@#{MAILING_LIST_DOMAIN}",
             "ev@#{MAILING_LIST_DOMAIN}",
            ].each do |list_email|
                print_mailing_list(io, list_email)
                remaining_mailing_lists.delete(list_email)
            end
            @@shorthands_for_fach.keys.sort do |a, b|
                a.downcase <=> b.downcase
            end.each do |fach|
                list_email = "lehrer.#{fach.downcase}@#{MAILING_LIST_DOMAIN}"
                if @@mailing_lists[list_email]
                    print_mailing_list(io, list_email)
                    remaining_mailing_lists.delete(list_email)
                end
            end
            # io.puts "<tr><th colspan='3'>Oberstufen-Kurse</th></tr>"
            Main.iterate_kurse do |lesson_key|
                info = @@lessons[:lesson_keys][lesson_key]
                ['', 'eltern.'].each do |extra|
                    list_email = "#{extra}#{info[:list_email]}@#{MAILING_LIST_DOMAIN}"
                    if @@mailing_lists[list_email]
                        # print_mailing_list(io, list_email)
                        remaining_mailing_lists.delete(list_email)
                    end
                end
            end
            io.puts "<tr><th colspan='3'>Forschertage</th></tr>"
            ['gewi', 'medien', 'musik', 'nawi'].each do |group_ft|
                [5, 6].each do |klasse|
                    ['', '.eltern'].each do |extra|
                        list_email = "forschertage.#{group_ft}#{extra}.#{klasse}@#{MAILING_LIST_DOMAIN}"
                        if @@mailing_lists[list_email]
                            print_mailing_list(io, list_email)
                            remaining_mailing_lists.delete(list_email)
                        end
                    end
                end
            end
            io.puts "<tr><th colspan='3'>AGs und Angebote</th></tr>"
            @@angebote_mailing_lists.keys.reject { |x| x[0, 7] == 'eltern.'}.sort do |a, b|
                a.downcase <=> b.downcase
            end.each do |email|
                ['', 'eltern.'].each do |extra|
                    list_email = "#{extra}#{email}"
                    if @@mailing_lists[list_email]
                        print_mailing_list(io, list_email)
                        remaining_mailing_lists.delete(list_email)
                    end
                end
            end
            if user_with_role_logged_in?(:schulbuchverein) || user_with_role_logged_in?(:can_manage_bib_payment)
                io.puts "<tr><th colspan='3'>Lehrmittelverein</th></tr>"
            end
            @@lehrbuchverein_mailing_lists.each_pair do |list_email, v|
                if @@mailing_lists[list_email]
                    if user_with_role_logged_in?(:schulbuchverein) || user_with_role_logged_in?(:can_manage_bib_payment)
                        print_mailing_list(io, list_email)
                    end
                    remaining_mailing_lists.delete(list_email)
                end
            end
            unless remaining_mailing_lists.empty?
                io.puts "<tr><th colspan='3'>Weitere E-Mail-Verteiler</th></tr>"
                remaining_mailing_lists.to_a.sort do |a, b|
                    ia = @@mailing_lists[a]
                    ib = @@mailing_lists[b]
                    ia[:label].downcase.unicode_normalize(:nfd) <=> ib[:label].downcase.unicode_normalize(:nfd)
                end.each do |list_email|
                    print_mailing_list(io, list_email)
                end
            end
            io.puts "</table>"
            io.string
        end
    end

    get '/api/sus_by_birthday_cutoff' do
        require_admin!
        sus_per_bracket = {}
        s = StringIO.open do |io|
            [:sub14, :sub16, :ge16].each do |bracket|
                emails = @@users_for_role[:schueler].select do |email|
                    if bracket == :sub14
                        @@user_info[email][:geburtstag] > "2011-03-14"
                    elsif bracket == :sub16
                        @@user_info[email][:geburtstag] <= "2011-03-14" && @@user_info[email][:geburtstag] > "2009-03-14"
                    else
                        @@user_info[email][:geburtstag] <= "2009-03-14"
                    end
                end
                io.puts "#{bracket}"
                io.puts
                io.puts emails.join('; ')
                io.puts
            end
            io.string
        end
        respond_raw_with_mimetype(s, "text/plain")
    end

    def inactive_sus_table()
        assert(admin_logged_in?)
        StringIO.open do |io|
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-12'>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='klassen_table table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>Klasse</th>"
            io.puts "<th>Geburtsdatum</th>"
            io.puts "<th>Bildungsgang</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "<th>Letzter Zugriff</th>"
            io.puts "<th>Eltern-E-Mail-Adresse</th>"
            io.puts "<th>Klassenleitung / Tutor:in</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            schueler_liste = []
            KLASSEN_ORDER.each do |klasse|
                schueler_liste += @@schueler_for_klasse[klasse]
            end
            last_access = {}
            neo4j_query(<<~END_OF_QUERY).each do |x|
                MATCH (u:User)
                RETURN u.email, u.last_access;
            END_OF_QUERY
                last_access[x['u.email']] = x['u.last_access']
            end

            (schueler_liste || []).sort do |a, b|
                ((KLASSEN_ORDER.index(@@user_info[a][:klasse]) == KLASSEN_ORDER.index(@@user_info[b][:klasse]))) ?
                ((@@user_info[a][:last_name].unicode_normalize(:nfd) == @@user_info[b][:last_name].unicode_normalize(:nfd)) ?
                (@@user_info[a][:first_name].unicode_normalize(:nfd) <=> @@user_info[b][:first_name].unicode_normalize(:nfd)) :
                (@@user_info[a][:last_name].unicode_normalize(:nfd) <=> @@user_info[b][:last_name].unicode_normalize(:nfd))) :
                (KLASSEN_ORDER.index(@@user_info[a][:klasse]) <=> KLASSEN_ORDER.index(@@user_info[b][:klasse]))
            end.each.with_index do |email, _|
                la_label = 'noch nie angemeldet'
                today = Date.today.to_s
                if last_access[email]
                    days = (Date.today - Date.parse(last_access[email])).to_i
                    if days < 35
                        next
                    else
                        la_label = "vor #{days / 7} Wochen"
                    end
                end

                record = @@user_info[email]
                io.puts "<tr class='user_row' data-email='#{email}' data-display-name='#{record[:display_name]}' data-first-name='#{record[:first_name]}' data-pronoun='#{record[:geschlecht] == 'm' ? 'er' : 'sie'}'>"
                io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                io.puts "<td>#{record[:last_name]}</td>"
                io.puts "<td>#{record[:first_name]}</td>"
                io.puts "<td>#{tr_klasse(record[:klasse])}</td>"
                if record[:geburtstag]
                    io.puts "<td>#{Date.parse(record[:geburtstag]).strftime('%d.%m.%Y')}</td>"
                else
                    io.puts "<td>&ndash;</td>"
                end
                io.puts "<td>#{tr_bildungsgang(record[:bildungsgang])}</td>"
                io.puts "<td>"
                print_email_field(io, record[:email])
                io.puts "</td>"
                io.puts "<td>#{la_label}</td>"
                io.puts "<td>"
                print_email_field(io, "eltern.#{record[:email]}")
                io.puts "</td>"
                tutor = '&ndash;'
                if record[:tutor]
                    tutor = @@user_info[record[:tutor]][:display_name]
                else
                    tutor = @@klassenleiter[record[:klasse]].map { |x| @@user_info[@@shorthands[x]][:display_name] }.join(', ')
                end
                io.puts "<td>#{tutor}</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end
end
