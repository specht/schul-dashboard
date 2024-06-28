class Main < Sinatra::Base
    def user_logged_in?
        !@session_user.nil?
    end

    def self.user_has_role(email, role)
        assert(AVAILABLE_ROLES.include?(role), "Unknown role: #{role}")
        @@user_info[email] && @@user_info[email][:roles].include?(role)
    end

    def user_has_role(email, role)
        Main.user_has_role(email, role)
    end

    def user_with_role_logged_in?(role)
        assert(AVAILABLE_ROLES.include?(role), "Unknown role: #{role}")
        user_logged_in? && (@session_user[:roles].include?(role))
    end

    def user_who_can_upload_files_logged_in?
        user_with_role_logged_in?(:can_upload_files)
    end

    def user_who_can_manage_news_logged_in?
        user_with_role_logged_in?(:can_manage_news)
    end

    def user_who_can_manage_monitors_logged_in?
        user_with_role_logged_in?(:can_manage_monitors)
    end

    # def developer_logged_in?
    #     user_with_role_logged_in?(:developer)
    # end

    def external_user_logged_in?
        return !(teacher_logged_in? || schueler_logged_in?)
    end

    def technikteam_logged_in?
        user_with_role_logged_in?(:technikteam)
    end

    def user_who_can_use_aula_logged_in?
        user_with_role_logged_in?(:can_use_aula)
    end

    def user_who_can_manage_tablets_logged_in?
        user_with_role_logged_in?(:can_manage_tablets)
    end

    def user_who_can_manage_antikenfahrt_logged_in?
        user_with_role_logged_in?(:can_manage_antikenfahrt)
    end

    def admin_logged_in?
        user_with_role_logged_in?(:admin)
    end

    def sekretariat_logged_in?
        user_with_role_logged_in?(:sekretariat)
    end

    def zeugnis_admin_logged_in?
        user_with_role_logged_in?(:zeugnis_admin)
    end

    def admin_2fa_hotline_logged_in?
        admin_logged_in? && user_with_role_logged_in?(:datentresor_hotline)
    end

    def can_see_all_timetables_logged_in?
        user_with_role_logged_in?(:can_see_all_timetables)
    end

    def can_manage_salzh_logged_in?
        user_with_role_logged_in?(:can_manage_salzh)
    end

    def teacher_logged_in?
        user_with_role_logged_in?(:teacher)
    end

    def schueler_logged_in?
        user_with_role_logged_in?(:schueler)
    end

    def gev_logged_in?
        user_with_role_logged_in?(:admin)
    end

    def device_logged_in?
        !@session_device.nil?
    end

    def monitor_logged_in?
        user_logged_in? && @session_user[:is_monitor]
    end

    def tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet]
    end

    def teacher_tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :teacher
    end

    def kurs_tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :kurs
    end

    def klassenraum_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :klassenraum
    end

    def klassenleiter_for_klasse_logged_in?(klasse)
        return false unless @@klassenleiter[klasse]
        teacher_logged_in? && @@klassenleiter[klasse].include?(@session_user[:shorthand])
    end

    def klassenleiter_for_klasse_or_admin_logged_in?(klasse)
        return false unless @@klassenleiter[klasse]
        admin_logged_in? || (teacher_logged_in? && @@klassenleiter[klasse].include?(@session_user[:shorthand]))
    end

    def teacher_for_lesson_or_ha_amt_logged_in?(lesson_key)
        if teacher_logged_in?
            return true
        else
            return get_ha_amt_lesson_keys.include?(lesson_key)
        end
    end

    def user_who_can_report_tech_problems_logged_in?
        user_logged_in? && check_has_technikamt(@session_user[:email])
    end

    # def user_who_can_report_tech_problems_or_better_logged_in?
    #     user_logged_in? && (@session_user[:can_manage_tablets] || check_has_technikamt(@session_user[:email]))
    # end

    def can_manage_agr_app_logged_in?
        user_with_role_logged_in?(:can_manage_agr_app)
    end

    def can_manage_bib_logged_in?
        flag = user_with_role_logged_in?(:can_manage_bib)
        if flag
            unless teacher_logged_in?
                unless device_logged_in?
                    flag = false
                end
            end
        end
        flag
    end

    def can_manage_bib_special_access_logged_in?
        user_with_role_logged_in?(:can_manage_bib_special_access)
    end

    def can_manage_bib_members_logged_in?
        user_with_role_logged_in?(:can_manage_bib_members)
    end

    def can_manage_bib_payment_logged_in?
        user_with_role_logged_in?(:can_manage_bib_payment)
    end

    def running_phishing_training?
        start = PHISHING_START
        ende = PHISHING_END
        user_logged_in? && (schueler_logged_in? || teacher_logged_in?) && Time.now.strftime('%Y-%m-%dT%H:%M:%S') >= start && Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= ende
    end

    def running_phishing_training_hint?
        start = PHISHING_HINT_START
        ende = PHISHING_HINT_END
        (schueler_logged_in? || teacher_logged_in?) && Time.now.strftime('%Y-%m-%dT%H:%M:%S') >= start && Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= ende
    end

    def require_device!
        assert(!@session_device.nil?)
    end

    def require_user!
        assert(user_logged_in?, 'User is logged in', true)
    end

    def require_admin!
        assert(admin_logged_in?)
    end

    def require_user_with_role!(role)
        assert(user_with_role_logged_in?(role))
    end

    def require_admin_or_sekretariat!
        assert(admin_logged_in? || sekretariat_logged_in?)
    end

    def require_zeugnis_admin!
        assert(zeugnis_admin_logged_in?)
    end

    def require_admin_2fa_hotline!
        assert(admin_2fa_hotline_logged_in?)
    end

    def require_teacher!
        assert(teacher_logged_in?)
    end

    def require_teacher_tablet!
        assert(teacher_tablet_logged_in?)
    end

    def require_user_who_can_upload_files!
        assert(user_who_can_upload_files_logged_in?)
    end

    def require_user_who_can_manage_news!
        assert(user_who_can_manage_news_logged_in?)
    end

    def require_user_who_can_manage_monitors!
        assert(user_who_can_manage_monitors_logged_in?)
    end

    # def require_developer!
    #     assert(developer_logged_in?)
    # end

    def require_technikteam!
        assert(technikteam_logged_in?)
    end

    def require_user_who_can_report_tech_problems!
        assert(user_who_can_report_tech_problems_logged_in?)
    end

    # def require_user_who_can_report_tech_problems_or_better!
    #     assert(user_who_can_report_tech_problems_or_better_logged_in?)
    # end

    def require_user_who_can_use_aula!
        assert(user_who_can_use_aula_logged_in?)
    end

    def require_user_who_can_manage_tablets!
        assert(user_who_can_manage_tablets_logged_in?)
    end

    def require_user_who_can_manage_antikenfahrt!
        assert(user_who_can_manage_antikenfahrt_logged_in?)
    end

    def require_user_who_can_manage_agr_app!
        assert(can_manage_agr_app_logged_in?)
    end

    def require_user_who_can_manage_bib!
        assert(can_manage_bib_logged_in?)
    end

    def require_monitor_or_user_who_can_manage_monitors!
        assert(monitor_logged_in? || user_who_can_manage_monitors_logged_in?)
    end

    def require_user_who_can_manage_salzh!
        assert(can_manage_salzh_logged_in?)
    end

    def require_teacher_for_lesson_or_ha_amt_logged_in(lesson_key)
        assert(teacher_for_lesson_or_ha_amt_logged_in?(lesson_key))
    end

    def require_running_phishing_training!
        assert(running_phishing_training?)
    end

    def require_running_phishing_training_hint!
        assert(running_phishing_training_hint?)
    end
    
    def this_is_a_page_for_logged_in_users
        unless user_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_devices
        if @session_device.nil?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_users_who_can_manage_salzh
        unless can_manage_salzh_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_gev
        unless gev_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_user_with_role(role)
        unless user_with_role_logged_in?(role)
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_admins
        unless admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_zeugnis_admins
        unless zeugnis_admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_teachers
        unless teacher_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_people_who_can_upload_files
        unless user_who_can_upload_files_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_people_who_can_manage_news
        unless user_who_can_manage_news_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_people_who_can_manage_monitors
        unless user_who_can_manage_monitors_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # def this_is_a_page_for_logged_in_developers
    #     unless developer_logged_in?
    #         redirect "#{WEB_ROOT}/", 303
    #     end
    # end

    # Put this on top of a webpage to assert that this page can be opened during a phishing training only
    def this_is_a_page_for_phishing_training
        unless running_phishing_training?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Return a <div> with a background image taken from a user's Nextcloud account,
    # with a gray background as a default fallback.
    # @param email [String] the user's email address
    # @param c [String] a CSS class to apply to the div (e. g. avatar-lg)
    # @return [String] the HTML string describing the <div>
    def user_icon(email, c = nil)
        "<div style='background-image: url(#{NEXTCLOUD_URL}/index.php/avatar/#{@@user_info[email][:nc_login]}/128), url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mO88h8AAq0B1REmZuEAAAAASUVORK5CYII=);' class='#{c}'></div>"
    end

    def klassen_for_session_user()
        require_teacher!
        if can_see_all_timetables_logged_in?
            @@klassen_order.dup
        else
            klassen = []
            @@klassen_order.each do |klasse|
                next unless (@@klassen_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(klasse)
                klassen << klasse
            end
            klassen
        end
    end

    def lessons_for_session_user_and_klasse(klasse)
        require_teacher!
        faecher = Set.new()
        (@@lessons_for_shorthand[@session_user[:shorthand]] || []).each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            next unless lesson_info[:klassen].include?(klasse)
            faecher << lesson_info[:fach]
        end
        faecher = faecher.to_a.sort do |a, b|
            a = @@faecher[a] if @@faecher[a]
            b = @@faecher[b] if @@faecher[b]
            a <=> b
        end
        {:fach_order => faecher, :fach_tr => @@faecher}
    end

    post '/api/set_sus_may_contact_me' do
        require_teacher!
        data = parse_request_data(:required_keys => [:allowed])
        allowed = data[:allowed] == 'true'
        allowed = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :allowed => allowed)['allowed']
            MATCH (u:User {email: $email})
            SET u.sus_may_contact_me = $allowed
            RETURN u.sus_may_contact_me AS allowed;
        END_OF_QUERY
        @session_user[:sus_may_contact_me] = allowed
        respond(:allowed => allowed);
    end

    def klasse_for_sus
        assert(user_with_role_logged_in?(:can_manage_tablets) || user_with_role_logged_in?(:teacher))
        result = {}
        @@user_info.each_pair do |email, info|
            next if info[:teacher]
            next unless info[:klasse]
            result[email] = Main.tr_klasse(info[:klasse])
        end
        result
    end

    def get_omit_ical_types
        types = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['types']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.omit_ical_types, []) AS types;
        END_OF_QUERY
        types
    end

    post '/api/set_preferred_login_method' do
        require_user!
        data = parse_request_data(:required_keys => [:method])
        assert(%w(email sms otp).include?(data[:method]))
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :method => data[:method])
            MATCH (u:User {email: $email})
            SET u.preferred_login_method = $method
            RETURN u.email;
        END_OF_QUERY
        respond(:method => data[:method])
    end

    def session_user_preferred_login_method
        require_user!
        method = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['method']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.preferred_login_method, "email") AS method;
        END_OF_QUERY
        method
    end

    post '/api/set_jump_table_direction' do
        require_user!
        data = parse_request_data(:required_keys => [:method])
        assert(%w(rows columns).include?(data[:method]))
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :method => data[:method])
            MATCH (u:User {email: $email})
            SET u.jump_table_direction = $method
            RETURN u.email;
        END_OF_QUERY
        respond(:method => data[:method])
    end

    def session_user_jump_table_direction
        require_user!
        method = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['method']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.jump_table_direction, "rows") AS method;
        END_OF_QUERY
        method
    end

    post '/api/toggle_ical_omit_type' do
        require_user!
        data = parse_request_data(:required_keys => [:type])
        type = data[:type]
        assert(%w(website_event event lesson holiday birthday).include?(type))
        omitted_types = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['types']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.omit_ical_types, []) AS types;
        END_OF_QUERY
        if omitted_types.include?(type)
            omitted_types.delete(type)
        else
            omitted_types << type
        end
        omitted_types = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :types => omitted_types)['types']
            MATCH (u:User {email: $email})
            SET u.omit_ical_types = $types
            RETURN COALESCE(u.omit_ical_types, []) AS types;
        END_OF_QUERY
        trigger_update("_#{@session_user[:email]}")
        respond(:result => omitted_types.include?(type))
    end

    def print_summoned_books_panel()
        require_user!
        email = @session_user[:email]
        self.class.refresh_bib_data()
        result = ''
        if @@bib_summoned_books[email]
            n_to_s = {1 => 'Eines der', 2 => 'Zwei', 3 => 'Drei', 4 => 'Vier', 5 => 'Fünf'}
            result += StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<div><span style='font-size: 200%; float: left; margin-right: 8px;'>📚</span>#{n_to_s[@@bib_summoned_books[email].size] || 'Mehrere'} Bücher, die du ausgeliehen hast, #{@@bib_summoned_books[email].size == 1 ? 'wird' : 'werden'} dringend in der Bibliothek benötigt. Bitte bring #{@@bib_summoned_books[email].size == 1 ? 'es' : 'sie'} zurück und lege #{@@bib_summoned_books[email].size == 1 ? 'es' : 'sie'} ins <a target='_blank' href='https://rundgang.gymnasiumsteglitz.de/#g114'>Rückgaberegal</a> vor der Bibliothek.</div>"
                io.puts "<hr />"
                io.puts "<a href='/bibliothek' style='white-space: nowrap;' class='float-right btn btn-sm btn-success'>Zu deinen Büchern&nbsp;<i class='fa fa-angle-double-right'></i></a>"
                io.puts "<div style='clear: both;'></div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        # if @@bib_unconfirmed_books[email] && (!teacher_logged_in?)
        #     n_to_s = {1 => 'Eines', 2 => 'Zwei', 3 => 'Drei', 4 => 'Vier', 5 => 'Fünf'}
        #     result += StringIO.open do |io|
        #         io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
        #         io.puts "<div class='hint'>"
        #         io.puts "<div><span style='font-size: 200%; float: left; margin-right: 8px;'>🙁</span>#{n_to_s[@@bib_unconfirmed_books[email].size] || 'Mehrere'} deiner ent&shy;lieh&shy;enen Bücher #{@@bib_unconfirmed_books[email].size == 1 ? 'wurde' : 'wurden'} von dir noch nicht bestätigt. <strong>Bitte scanne #{@@bib_unconfirmed_books[email].size == 1 ? 'das Buch' : 'die Bücher'} jetzt ein.</strong></div>"
        #         io.puts "<hr />"
        #         io.puts "<a href='/bib_confirm' style='white-space: nowrap;' class='float-right btn btn-sm btn-success'><i class='fa fa-barcode'></i>&nbsp;&nbsp;Bücher bestätigen</a>"
        #         io.puts "<div style='clear: both;'></div>"
        #         io.puts "</div>"
        #         io.puts "</div>"
        #         io.string
        #     end
        # end
        result
    end

    def print_ad_hoc_2fa_panel()
        return '' unless admin_2fa_hotline_logged_in?
        require_admin_2fa_hotline!
        ts = Time.now.to_i
        neo4j_query(<<~END_OF_QUERY, {:ts => ts})
            MATCH (ahr:AdHocTwoFaRequest)-[:BELONGS_TO]->(s:Session)-[:BELONGS_TO]->(u:User)
            WHERE $ts > ahr.ts_expire
            DETACH DELETE ahr;
        END_OF_QUERY
        users = neo4j_query(<<~END_OF_QUERY).map { |x| x['u'] }
            MATCH (ahr:AdHocTwoFaRequest)-[:BELONGS_TO]->(s:Session)-[:BELONGS_TO]->(u:User)
            RETURN u;
        END_OF_QUERY
        return '' if users.empty?
        StringIO.open do |io|
            io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
            io.puts "<div class='hint'>"
            io.puts "<p><b>Datentresor-Hotline</b></p>"
            io.puts "<hr />"
            users.each do |user|
                io.puts "<button class='bu_open_ad_hoc_2fa_request button btn btn-success' data-email='#{user[:email]}' data-name='#{@@user_info[user[:email]][:display_name]}'><i class='fa fa-phone'></i>&nbsp;&nbsp;#{@@user_info[user[:email]][:display_name_official]}&nbsp;&nbsp;<i class='fa fa-angle-double-right'></i></button>"
            end
            # io.puts "<div><span style='font-size: 200%; opacity: 0.7; float: left; margin-right: 8px;'><i class='fa fa-book'></i></span>#{n_to_s[@@bib_summoned_books[email].size] || 'Mehrere'} Bücher, die du ausgeliehen hast, #{@@bib_summoned_books[email].size == 1 ? 'wird' : 'werden'} dringend in der Bibliothek benötigt. Bitte bring #{@@bib_summoned_books[email].size == 1 ? 'es' : 'sie'} zurück und lege #{@@bib_summoned_books[email].size == 1 ? 'es' : 'sie'} ins <a target='_blank' href='https://rundgang.gymnasiumsteglitz.de/#g114'>Rückgaberegal</a> vor der Bibliothek.</div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    def print_tresor_countdown_panel()
        return '' unless teacher_logged_in?
        deadline = DEADLINE_NOTENEINTRAGUNG
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline && (DateTime.parse(deadline) - DateTime.now).to_f < 7.0
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Noteneingabe im Datentresor</b></p>"
                io.puts "<hr />"
                d = DateTime.parse(deadline)
                io.puts "<p>Die Noteneingabe im Datentresor schließt am #{WEEKDAYS_LONG[d.wday]} um #{d.strftime('%H:%M')} Uhr.</p>"
                io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                io.puts "</div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        deadline = DEADLINE_CONSIDER
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline && (DateTime.parse(deadline) - DateTime.now).to_f < 7.0
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Markierung von SuS in den Listen für die Zeugniskonferenzen</b></p>"
                io.puts "<hr />"
                d = DateTime.parse(deadline)
                io.puts "<p>Klassenleitungen: Bitte markieren Sie SuS, die Sie in den Zeug&shy;nis&shy;kon&shy;feren&shy;zen besprechen möchten, bis #{WEEKDAYS_LONG[d.wday]} um #{d.strftime('%H:%M')} Uhr. Hinweis: Alle SuS mit einer Note ab 4– sind schon auto&shy;matisch markiert.</p>"
                io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                io.puts "</div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        if need_sozialverhalten()
            deadline = DEADLINE_SOZIALNOTEN
            if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline && (DateTime.parse(deadline) - DateTime.now).to_f < 7.0
                return StringIO.open do |io|
                    io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                    io.puts "<div class='hint'>"
                    io.puts "<p><b>Eintragung der Noten für das Arbeits- und Sozialverhalten</b></p>"
                    io.puts "<hr />"
                    d = DateTime.parse(deadline)
                    io.puts "<p>Die Möglichkeit für Eintragungen der Noten für das Arbeits- und Sozialverhalten endet am #{WEEKDAYS_LONG[d.wday]} um #{d.strftime('%H:%M')} Uhr. Bitte tragen Sie bis dahin fehlende Noten ein, damit die Klassenleitungen rechtzeitig vor der Zeugnisausgabe die Sozialzeugnisse drucken können.</p>"
                    io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                    io.puts "</div>"
                    io.puts "</div>"
                    io.puts "</div>"
                    io.string
                end
            end
        end
        return ''
    end

    def print_projektwahl_countdown_panel()
        if user_eligible_for_projektwahl?
            vote_count = neo4j_query_expect_one("MATCH (u:User {email: $email})-[:VOTED_FOR]->(p:Projekt) RETURN COUNT(p) AS count;", {:email => @session_user[:email]})['count']
            if vote_count == 0
                if projekttage_phase() == 3
                    return StringIO.open do |io|
                        io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                        io.puts "<div class='hint'>"
                        io.puts "<p><b>Wähle deine Lieblingsprojekte!</b></p>"
                        io.puts "<p>Du findest den Projektkatalog im Menü unter »Projekttage«."
                        io.puts "</div>"
                        io.puts "</div>"
                        io.string
                    end
                end
            end
        elsif (@session_user[:klassenstufe] || 0) == 11
            if projekttage_phase() > 0
                return StringIO.open do |io|
                    rows = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                        MATCH (p:Projekt)-[:ORGANIZED_BY]->(u:User {email: $email})
                        RETURN p;
                    END_OF_QUERY
                    unless rows.empty?
                        projekt = rows.first['p']
                        count = 0
                        count += 1 unless (projekt[:description] || '').strip.empty?
                        count += 1 unless (projekt[:photo] || '').strip.empty?
                        emoji = %w(😭 🥲 😄)[count]
                        if (projekt[:capacity] || 0) > 0
                            unless count == 2 && (Time.now.to_i - (projekt[:ts_updated] || 0) > 3600)
                                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                                io.puts "<div class='hint'>"
                                io.puts "<p><b>Dein Angebot für die Projekttage</b></p>"
                                io.puts "<hr />"
                                io.puts "<span style='font-size: 300%; float: right; margin-left: 10px; margin-bottom: 10px;'>#{emoji}</span>"
                                if count == 0
                                    io.puts "<p>Du hast noch keinen Werbetext für dein Projekt eingegeben und auch kein Bild hochgeladen. Bitte trage diese Informationen unter »Projekttage« nach und hilf mit, dass dieser arme Smiley wieder glücklich wird.</p>"
                                elsif count == 1
                                    if (projekt[:description] || '').strip.empty?
                                        io.puts "<p>Du hast zwar schon ein Bild hochgeladen, aber noch keinen Werbetext geschrieben. You can do it!</p>"
                                    else
                                        io.puts "<p>Du hast zwar schon einen Werbetext geschrieben, aber noch kein Bild hochgeladen. You can do it!</p>"
                                    end
                                elsif count == 2
                                    io.puts "<p>Danke, dass du alle Informationen eingetragen hast!</p>"
                                end
                                if count < 2
                                    io.puts "<p><a href='/projekttage_orga' class='btn btn-success' style='white-space: normal;'>Lass uns diesen Smiley wieder glücklich machen!</a></p>"
                                end
                                io.puts "</div>"
                                io.puts "</div>"
                            end
                        end
                    end
                    io.string
                end
            end
        end
        return ''
    end

    def print_phishing_panel()
        if running_phishing_training_hint?
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Phishing Prävention</b></p>"
                io.puts "<hr />"
                io.puts "<p>Die Statistiken zu der E-Mail vom #{PHISHING_RECEIVING_DATE} sind nun online.</p>"
                io.puts "<p><a href='/phishing' class='btn btn-primary'>Phishing Prävention&nbsp;<i class='fa fa-angle-double-right'></i></a></p>"
                io.puts "<p>Du kannst auch an unserer Umfrage teilnehmen.</p>"
                io.puts "<p><button class='btn btn-success bu-launch-poll' data-poll-run-id='#{PHISHING_POLL_RUN_ID}'>Zur Umfrage&nbsp;<i class='fa fa-angle-double-right'></i></button></p>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        return ''
    end


    # get '/api/get_timetable_pdf' do
    #     require_user!
    #     respond_raw_with_mimetype(get_timetable_pdf(@session_user[:klasse], @session_user[:color_scheme] || @@standard_color_scheme), 'application/pdf')
    # end

    get '/api/get_timetable_pdf_for_klasse/:klasse' do
        require_teacher!
        klasse = params[:klasse]
        STDERR.puts "Priting timetables for #{klasse}..."
        colors = []
        @@schueler_for_klasse[klasse].size.times do
            color_scheme = %w(
                lab8bbfa27776ab8bbe
                l7146749f6976cc8b79
                l94b2a1ff7d03e0ff03
                l55beedf9b935e5185d
                lcc1ccca66aaab4bbbb
                l0b2f3ad0a9f5f8e0f7
                la2c6e80d60aea2c6e8
                le8e33b6ca705f8f8df
            ).sample
            # d160520069960025061
            # d4aa03f003f2e80bc42
            color_scheme += [0, 1, 2, 5, 6, 7].sample.to_s
            colors << color_scheme
        end
        colors.shuffle!
        respond_raw_with_mimetype(get_timetables_pdf(klasse, colors), 'application/pdf')
    end

    get '/api/get_single_timetable_pdf' do
        require_user!
        use_png_addition = false
        respond_raw_with_mimetype(get_single_timetable_pdf(@session_user[:email], @session_user[:color_scheme] || @@standard_color_scheme, use_png_addition), 'application/pdf')
    end

    get '/api/get_single_timetable_with_png_addition_pdf' do
        require_user!
        use_png_addition = true
        respond_raw_with_mimetype(get_single_timetable_pdf(@session_user[:email], @session_user[:color_scheme] || @@standard_color_scheme, use_png_addition), 'application/pdf')
    end

    post '/api/set_color_options' do
        require_user!
        data = parse_request_data(:required_keys => [:hue, :saturation, :brightness, :contrast, :sepia, :analog],
                                  :types => {:hue => Numeric, :saturation => Numeric, :brightness => Numeric, :contrast => Numeric, :sepia => Numeric, :analog => Numeric})
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :hue => data[:hue], :saturation => data[:saturation], :brightness => data[:brightness], :contrast => data[:contrast], :sepia => data[:sepia], :analog => data[:analog])
            MATCH (u:User {email: $email})
            SET u.hue = $hue, u.saturation = $saturation, u.brightness = $brightness, u.contrast = $contrast, u.sepia = $sepia, u.analog = $analog
            RETURN u;
        END_OF_QUERY
        respond(:success => true)
    end

    def get_sitzplan_music_choice
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['u.music_choice'] || '01-preis'
            MATCH (u:User {email: $email})
            RETURN u.music_choice;
        END_OF_QUERY
    end

    post '/api/set_sitzplan_music_choice' do
        require_teacher!
        data = parse_request_data(:required_keys => [:music_choice])
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :music_choice => data[:music_choice])
            MATCH (u:User {email: $email})
            SET u.music_choice = $music_choice
            RETURN u;
        END_OF_QUERY
        respond(:success => true)
    end

    get '/api/get_music/:key' do
        require_user!
        respond_raw_with_mimetype(File.read("/data/sitzplan/#{params[:key]}.mp3"), 'audio/mpeg')
    end
end
