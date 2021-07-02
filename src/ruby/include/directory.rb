class Main < Sinatra::Base
    def mail_addresses_table(klasse)
        require_teacher!
        all_homeschooling_users = Main.get_all_homeschooling_users()
        StringIO.open do |io|
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-12'>"
            io.puts "<div class='alert alert-warning'>"
            io.puts "Bitte überprüfen Sie die <strong>Gruppenzuordnung (A/B)</strong> und markieren Sie alle Kinder, die von der Aussetzung der Präsenzpflicht Gebrauch machen oder die aus gesundheitlichen Gründen / Quarantäne nicht in die Schule kommen können, als <strong>»zu Hause«</strong>."
#             io.puts "Auf die Jitsi-Streams können momentan nur SuS zugreifen, die laut ihrer Gruppenzuordnung in der aktuellen Woche zu Hause sind oder explizit als »zu Hause« markiert sind."
            io.puts "</div>"
            io.puts "<h3>Klasse #{tr_klasse(klasse)}</h3>"
            io.puts "<div class='table-responsive'>"
            io.puts "<table class='klassen_table table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Nr.</th>"
            io.puts "<th style='width: 64px;'></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "<th style='width: 140px;'>Homeschooling</th>"
            io.puts "<th style='width: 100px;'>Gruppe A/B</th>"
            io.puts "<th style='width: 180px;'>Letzter Zugriff</th>"
            io.puts "<th>Eltern-E-Mail-Adresse</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            results = neo4j_query(<<~END_OF_QUERY, :email_addresses => @@schueler_for_klasse[klasse])
                MATCH (u:User)
                WHERE u.email IN {email_addresses}
                RETURN u.email, u.last_access, COALESCE(u.group2, 'A') AS group2;
            END_OF_QUERY
            last_access = {}
            group2_for_email = {}
            results.each do |x|
                last_access[x['u.email']] = x['u.last_access']
                group2_for_email[x['u.email']] = x['group2']
            end
            
            (@@schueler_for_klasse[klasse] || []).sort do |a, b|
                (@@user_info[a][:last_name] == @@user_info[b][:last_name]) ?
                (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
                (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
            end.each.with_index do |email, _|
                record = @@user_info[email]
                io.puts "<tr class='user_row'>"
                io.puts "<td>#{_ + 1}.</td>"
                io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                io.puts "<td>#{record[:last_name]}</td>"
                io.puts "<td>#{record[:first_name]}</td>"
                io.puts "<td>"
                print_email_field(io, record[:email])
                io.puts "</td>"
                homeschooling_button_disabled = (@@klassenleiter[klasse] || []).include?(@session_user[:shorthand]) ? '' : 'disabled'
                if all_homeschooling_users.include?(email)
                    io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-info btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-home'></i>&nbsp;&nbsp;zu Hause</button></td>"
                else
                    io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-secondary btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-building'></i>&nbsp;&nbsp;Präsenz</button></td>"
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
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td><b>E-Mail an die Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "<td></td>"
            io.puts "<td></td>"
            io.puts "<td colspan='2'><b>E-Mail an alle Eltern der Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "</tr>"
            io.puts "<tr class='user_row'>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td>"
            print_email_field(io, "klasse.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "<td></td>"
            io.puts "<td></td>"
            io.puts "<td colspan='2'>"
            print_email_field(io, "eltern.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "</tr>"
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.puts "<a class='btn btn-primary' href='/show_login_codes/#{klasse}'><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Live-Anmeldungen der Klasse zeigen</a>"
            io.puts print_stream_restriction_table(klasse)
            io.puts "<hr style='margin: 3em 0;'/>"
            io.puts "<h3>Schülerlisten Klasse #{tr_klasse(klasse)}</h3>"
#             io.puts "<div style='text-align: center;'>"
            io.puts "<a href='/api/directory_xlsx/#{klasse}' class='btn btn-primary'><i class='fa fa-file-excel-o'></i>&nbsp;&nbsp;Excel-Tabelle herunterladen</a>"
            io.puts "<a href='/api/directory_timetex_pdf/#{klasse}' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Timetex-PDF herunterladen</a>"
#             io.puts "</div>"
            io.puts "<hr style='margin: 3em 0;'/>"
            io.puts "<h3>Lehrer der Klasse #{tr_klasse(klasse)}</h3>"
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
            @@teachers_for_klasse[klasse].keys.sort do |a, b|
                name_comp = begin
                    @@user_info[@@shorthands[a]][:last_name] <=> @@user_info[@@shorthands[b]][:last_name]
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
                io.puts "<td>#{lehrer[:display_name] || ''}</td>"
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
            io.puts "<tr>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td><b>E-Mail an alle Lehrer/innen der Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "</tr>"
            io.puts "<tr class='user_row'>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td>"
            print_email_field(io, "lehrer.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "</tr>"
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
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
            MATCH (u:User {email: {email}})
            RETURN COALESCE(u.homeschooling, false) AS homeschooling
        END_OF_QUERY
        marked_as_homeschooling = info['homeschooling']
        marked_as_homeschooling
    end
    
    def self.get_homeschooling_for_user_by_switch_week(email, datum, group2_for_email)
        group2 = nil
        if group2_for_email.nil?
            info = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})
                MATCH (u:User {email: {email}})
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
    
    post '/api/toggle_homeschooling' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        unless admin_logged_in?
            klasse = @@user_info[email][:klasse]
            assert(@@klassenleiter[klasse].include?(@session_user[:shorthand]))
        end
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: {email}})
            SET u.homeschooling = NOT COALESCE(u.homeschooling, FALSE)
            RETURN u.homeschooling;
        END_OF_QUERY
        trigger_update("_#{email}")
        respond(:ok => true, :homeschooling => result['u.homeschooling'])
    end

    def iterate_directory(which, &block)
        (@@schueler_for_klasse[which] || []).sort do |a, b|
            (@@user_info[a][:last_name] == @@user_info[b][:last_name]) ?
            (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
            (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
        end.each.with_index do |email, i|
            yield email, i
        end
    end
    
    get '/api/directory_timetex_pdf/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_timetex_pdf/', '')
        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, 
                                :margin => 0) do
            font('/app/fonts/RobotoCondensed-Regular.ttf') do
                font_size 12
                main.iterate_directory(klasse) do |email, i|
                    user = @@user_info[email]
                    y = 297.mm - 20.mm - 20.7.pt * i
                    draw_text "#{user[:last_name]}, #{user[:first_name]}", :at => [30.mm, y + 6.pt]
                    line_width 0.2.mm
                    stroke { line [30.mm, y + 20.7.pt], [77.mm, y + 20.7.pt] } if i == 0
                    stroke { line [30.mm, y], [77.mm, y] }
                end
            end
        end
        respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
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
                text "Folgende SuS haben sich bisher <b>noch nicht</b> am Dashboard angemeldet und können deshalb auch bisher nicht auf die NextCloud zugreifen:\n\n", inline_format: true
                @@schueler_for_klasse[klasse].each do |email|
                    next unless never_seen_users.include?(email)
                    user = @@user_info[email]
                    text "#{user[:display_name]}\n"
                end
                text "\n\nBitte erinnern Sie die SuS daran, schnellstmöglich ihr E-Mail-Postfach einzurichten, sich am Dashboard anzumelden und sich bei der NextCloud anzumelden. ", inline_format: true
                text "Wer seinen E-Mail-Zettel verloren hat, schreibt bitte eine E-Mail an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} – <b>#{WEBSITE_MAINTAINER_EMAIL}</b> – dort bekommt jeder die Zugangsdaten zur Not noch einmal als PDF.\n\n", inline_format: true
                text "Zuerst muss das E-Mail-Postfach eingerichtet werden. Den Zugangscode für das Dashboard bekommt man per E-Mail und die Zugangsdaten für die NextCloud finden sich im Dashboard im Menü ganz rechts: <em>In Nextcloud anmelden…</em>\n\n", inline_format: true
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
            sheet.write(0, 2, 'Klasse', format_header)
            sheet.write(0, 3, 'Gruppe', format_header)
            sheet.write(0, 4, 'E-Mail', format_header)
            sheet.write(0, 5, 'E-Mail der Eltern', format_header)
            sheet.set_column(0, 1, 16)
            sheet.set_column(4, 5, 48)
            iterate_directory(klasse) do |email, i|
                user = @@user_info[email]
                group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
                    MATCH (u:User {email: {email}})
                    RETURN COALESCE(u.group2, 'A') AS group2;
                END_OF_QUERY
                sheet.write(i + 1, 0, user[:last_name])
                sheet.write(i + 1, 1, user[:first_name])
                sheet.write(i + 1, 2, user[:klasse])
                sheet.write(i + 1, 3, group2)
                sheet.write(i + 1, 4, user[:email])
                sheet.write(i + 1, 5, 'eltern.' + user[:email])
            end
            workbook.close
            result = File.read(file.path)
        ensure
            file.close
            file.unlink
        end
        respond_raw_with_mimetype_and_filename(result, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', "Klasse #{klasse}.xlsx")
    end
    
    post '/api/toggle_group2_for_user' do
        require_teacher!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
            MATCH (u:User {email: {email}})
            RETURN COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        if group2 == 'A'
            group2 = 'B'
        else
            group2 = 'A'
        end
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :group2 => group2)['group2']
            MATCH (u:User {email: {email}})
            SET u.group2 = {group2}
            RETURN u.group2 AS group2;
        END_OF_QUERY
        respond(:group2 => group2)
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
            WHERE u.email IN {email_addresses}
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
        io.puts "<tr class='user_row'>"
        info = @@mailing_lists[list_email]
        io.puts "<td class='list_email_label'>#{info[:label]}</td>"
        io.puts "<td>"
        print_email_field(io, list_email)
        io.puts "</td>"
        io.puts "<td style='text-align: right;'><button data-list-email='#{list_email}' class='btn btn-warning btn-sm bu-toggle-adresses'>#{info[:recipients].size} Adressen&nbsp;&nbsp;<i class='fa fa-chevron-down'></i></button></td>"
        io.puts "</tr>"
        io.puts "<tbody style='display: none;' class='list_email_emails' data-list-email='#{list_email}'>"
        info[:recipients].sort do |a, b|
            an = ((@@user_info[a.sub(/^eltern\./, '')] || {})[:display_name] || '').downcase
            bn = ((@@user_info[b.sub(/^eltern\./, '')] || {})[:display_name] || '').downcase
            an <=> bn
        end.each do |email|
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
        io.puts "</tbody>"
    end
    
    def print_mailing_lists()
        StringIO.open do |io|
            io.puts "<table class='table table-condensed narrow'>"
            remaining_mailing_lists = Set.new(@@mailing_lists.keys)
            @@klassen_order.each do |klasse|
                io.puts "<tr><th colspan='3'>Klasse #{tr_klasse(klasse)}</th></tr>"
                ["klasse.#{klasse}@#{SCHUL_MAIL_DOMAIN}",
                 "eltern.#{klasse}@#{SCHUL_MAIL_DOMAIN}",
                 "lehrer.#{klasse}@#{SCHUL_MAIL_DOMAIN}"].each do |list_email|
                    print_mailing_list(io, list_email)
                    remaining_mailing_lists.delete(list_email)
                end
            end
            io.puts "<tr><th colspan='3'>Gesamte Schule</th></tr>"
            ["sus@#{SCHUL_MAIL_DOMAIN}",
             "eltern@#{SCHUL_MAIL_DOMAIN}",
             "lehrer@#{SCHUL_MAIL_DOMAIN}"].each do |list_email|
                print_mailing_list(io, list_email)
                remaining_mailing_lists.delete(list_email)
            end
            unless remaining_mailing_lists.empty?
                io.puts "<tr><th colspan='3'>Weitere E-Mail-Verteiler</th></tr>"
                remaining_mailing_lists.to_a.sort.each do |list_email|
                    print_mailing_list(io, list_email)
                end
            end
            io.puts "</table>"
            io.string
        end
    end

    def generate_matrix_corporal_policy
        result = {
            :schemaVersion => 1,
            :flags => {
                :allowCustomUserDisplayNames => false,
                :allowCustomUserAvatars => false,
                :allowCustomPassthroughUserPasswords => false,
                :allowUnauthenticatedPasswordResets => false,
                :forbidRoomCreation => true,
                :forbidEncryptedRoomCreation => true,
                :forbidUnencryptedRoomCreation => true
            },
            :managedCommunityIds => [],
            :managedRoomIds => [],
            :users => []
        }
        matrix_handle_to_email = {}
        @@user_info.each_pair do |email, info|
            handle = "@#{email.split('@').first}:nhcham.org"
            matrix_handle_to_email[handle] = email
            result[:users] << {
                :id => handle,
                :active => true,
                :authType => 'rest',
                :authCredential => "#{WEB_ROOT}/api/confirm_chat_login",
                :displayName => info[:display_name],
                :avatarUri => "#{NEXTCLOUD_URL}/index.php/avatar/#{info[:nc_login]}/256",
                :joinedCommunityIds => [],
                :joinedRoomIds => [],
                :forbidRoomCreation => info[:teacher] ? false : true,
                :forbidUnencryptedRoomCreation => info[:teacher] ? false : true
            }
        end
        result[:managedRoomsIds] << '!wfEDbfgjOMXXvsYmHq:nhcham.org'
        result[:users] = result[:users].map do |info|
            email = matrix_handle_to_email[info[:id]]
            if @@user_info[email][:teacher]
                info[:joinedRoomIds] << '!wfEDbfgjOMXXvsYmHq:nhcham.org'
            end
            info
        end
        result
    end

    get '/api/generate_matrix_corporal_policy' do
        require_admin!
        respond(generate_matrix_corporal_policy)
    end

end
