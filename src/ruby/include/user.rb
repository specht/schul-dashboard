class Main < Sinatra::Base
    # Returns true if a user is logged in.
    def user_logged_in?
        !@session_user.nil?
    end

    # Returns true if a user who can upload vplan is logged in.
    def user_who_can_upload_vplan_logged_in?
        user_logged_in? && @session_user[:can_upload_vplan]
    end

    # Returns true if a user who can upload files is logged in.
    def user_who_can_upload_files_logged_in?
        user_logged_in? && @session_user[:can_upload_files]
    end

    # Returns true if a user who can manage news is logged in.
    def user_who_can_manage_news_logged_in?
        user_logged_in? && @session_user[:can_manage_news]
    end

    # Returns true if a user who can manage AGs is logged in.
    def user_who_can_manage_ags_logged_in?
        user_logged_in? && @session_user[:can_manage_ags]
    end

    # Returns true if a user who can manage monitors is logged in.
    def user_who_can_manage_monitors_logged_in?
        user_logged_in? && @session_user[:can_manage_monitors]
    end

    # Returns true if a TechnikTeam is logged in.
    def technikteam_logged_in?
        user_logged_in? && @session_user[:technikteam]
    end

    # # Returns true if a techpost user is logged in.
    # def user_who_can_report_tech_problems_logged_in?
    #     user_logged_in? && @session_user[:can_report_tech_problems]
    # end

    # Returns true if a user who can manage tablets is logged in.
    def user_who_can_manage_tablets_logged_in?
        user_logged_in? && @session_user[:can_manage_tablets]
    end

    # Returns true if a user who can manage tablets or teacher is logged in.
    def user_who_can_manage_tablets_or_teacher_logged_in?
        user_who_can_manage_tablets_logged_in? || teacher_logged_in?
    end

    def user_who_can_manage_tablets_or_sv_or_teacher_logged_in?
        return teacher_or_sv_logged_in? || user_who_can_manage_tablets_logged_in?
    end


    # Returns true if a user who can manage Antikenfahrt is logged in.
    def user_who_can_manage_antikenfahrt_logged_in?
        user_logged_in? && @session_user[:can_manage_antikenfahrt]
    end

    # Returns true if a teacher or SV is logged in.
    def teacher_or_sv_logged_in?
        user_logged_in? && (teacher_logged_in? || @session_user[:sv])
    end

    # Returns true if an admin is logged in.
    def admin_logged_in?
        user_logged_in? && ADMIN_USERS.include?(@session_user[:email])
    end

    def zeugnis_admin_logged_in?
        user_logged_in? && ZEUGNIS_ADMIN_USERS.include?(@session_user[:email])
    end

    def admin_2fa_hotline_logged_in?
        admin_logged_in? && DATENTRESOR_HOTLINE_USERS.include?(@session_user[:email])
    end

    # Returns true if a user who can see all timetables is logged in.
    def can_see_all_timetables_logged_in?
        user_logged_in? && (admin_logged_in? || @session_user[:can_see_all_timetables])
    end

    # Returns true if a user who can see all timetables is logged in.
    def can_manage_salzh_logged_in?
        user_logged_in? && (admin_logged_in? || @session_user[:can_manage_salzh])
    end

    # Returns true if a teacher is logged in.
    def teacher_logged_in?
        user_logged_in? && (@session_user[:teacher] == true)
    end

    # Returns true if GEV is logged in.
    def gev_logged_in?
        user_logged_in? && (GEV_USERS.include?(@session_user[:email]) || admin_logged_in?)
    end

    # Returns true if a device is logged in.
    def device_logged_in?
        !@session_device.nil?
    end

    # Returns true if a SuS is logged in.
    def sus_logged_in?
        user_logged_in? && (!(@session_user[:teacher] == true))
    end

    # Returns true if a teacher tablet is logged in.
    def teacher_tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :teacher
    end

    # Returns true if a kurs tablet is logged in.
    def kurs_tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :kurs
    end

    # Returns true if a kurs tablet is logged in.
    def klassenraum_logged_in?
        user_logged_in? && @session_user[:is_tablet] && @session_user[:tablet_type] == :klassenraum
    end

    # Returns true if a kurs tablet is logged in.
    def monitor_logged_in?
        user_logged_in? && @session_user[:is_monitor]
    end

    # Returns true if a tablet is logged in.
    def tablet_logged_in?
        user_logged_in? && @session_user[:is_tablet]
    end

    # Returns true if a klassenleiter for a given klasse is logged in.
    def klassenleiter_for_klasse_logged_in?(klasse)
        return false unless @@klassenleiter[klasse]
        teacher_logged_in? && @@klassenleiter[klasse].include?(@session_user[:shorthand])
    end

    # Returns true if a klassenleiter for a given klasse is logged in.
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

    # Returns true if a techpost user is logged in.
    def user_who_can_report_tech_problems_logged_in?
        user_logged_in? && check_has_technikamt(@session_user[:email]) == [{"hasRelation"=>true}]
    end

    # Returns true if a techpost or better user is logged in.
    def user_who_can_report_tech_problems_or_better_logged_in?
        user_logged_in? && (check_has_technikamt(@session_user[:email]) == [{"hasRelation"=>true}] || @session_user[:can_manage_tablets])
    end

    def can_manage_agr_app_logged_in?
        user_logged_in? && CAN_MANAGE_AGR_APP.include?(@session_user[:email])
    end

    def can_manage_bib_logged_in?
        flag = user_logged_in? && CAN_MANAGE_BIB.include?(@session_user[:email])
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
        user_logged_in? && CAN_MANAGE_BIB_SPECIAL_ACCESS.include?(@session_user[:email])
    end

    def teacher_or_can_manage_bib_logged_in?
        teacher_logged_in? || can_manage_bib_logged_in?
    end

    def can_manage_bib_members_logged_in?
        user_logged_in? && (CAN_MANAGE_BIB_MEMBERS.include?(@session_user[:email]))
    end

    def can_manage_bib_payment_logged_in?
        user_logged_in? && (CAN_MANAGE_BIB_PAYMENT.include?(@session_user[:email]))
    end

    def external_user_logged_in?
        user_logged_in? && (EXTERNAL_USERS.include?(@session_user[:email]))
    end

    def require_device!
        assert(!@session_device.nil?)
    end

    # Assert that a user is logged in
    def require_user!
        assert(user_logged_in?, 'User is logged in', true)
    end

    # Assert that an admin is logged in
    def require_admin!
        assert(admin_logged_in?)
    end

    def require_zeugnis_admin!
        assert(zeugnis_admin_logged_in?)
    end

    def require_admin_2fa_hotline!
        assert(admin_2fa_hotline_logged_in?)
    end

    # Assert that a teacher is logged in
    def require_teacher!
        assert(teacher_logged_in?)
    end

    # Assert that a teacher tablet is logged in
    def require_teacher_tablet!
        assert(teacher_tablet_logged_in?)
    end

    # Assert that a user who can upload vplan is logged in
    def require_user_who_can_upload_vplan!
        assert(user_who_can_upload_vplan_logged_in?)
    end

    # Assert that a user who can upload files is logged in
    def require_user_who_can_upload_files!
        assert(user_who_can_upload_files_logged_in?)
    end

    # Assert that a user who can manage news is logged in
    def require_user_who_can_manage_news!
        assert(user_who_can_manage_news_logged_in?)
    end

    # Assert that a user who can manage monitors is logged in
    def require_user_who_can_manage_monitors!
        assert(user_who_can_manage_monitors_logged_in?)
    end

    # Assert that a TechnikTeam user is logged in
    def require_technikteam!
        assert(technikteam_logged_in?)
    end

    # Assert that a techpost user is logged in
    def require_user_who_can_report_tech_problems!
        assert(user_who_can_report_tech_problems_logged_in?)
    end

    # Assert that a techpost user is logged in
    def require_user_who_can_report_tech_problems_or_better!
        assert(user_who_can_report_tech_problems_or_better_logged_in?)
    end

    # Assert that a user who can manage tablets is logged in
    def require_user_who_can_manage_tablets!
        assert(user_who_can_manage_tablets_logged_in?)
    end

    def require_user_who_can_manage_tablets_or_teacher!
        assert(user_who_can_manage_tablets_or_teacher_logged_in?)
    end

    # Assert that a user who can manage Antikenfahrt is logged in
    def require_user_who_can_manage_antikenfahrt!
        assert(user_who_can_manage_antikenfahrt_logged_in?)
    end

    # Assert that a user who can manage agrapp is logged in
    def require_user_who_can_manage_agr_app!
        assert(can_manage_agr_app_logged_in?)
    end

    def require_user_who_can_manage_bib!
        assert(can_manage_bib_logged_in?)
    end

    def require_teacher_or_user_who_can_manage_bib!
        assert(teacher_or_can_manage_bib_logged_in?)
    end

    # Assert that a teacher or SV is logged in
    def require_teacher_or_sv!
        assert(teacher_or_sv_logged_in?)
    end

    # Assert that an admin is logged in
    def require_monitor_or_user_who_can_manage_monitors!
        assert(monitor_logged_in? || user_who_can_manage_monitors_logged_in?)
    end

    def require_user_who_can_manage_salzh!
        assert(can_manage_salzh_logged_in?)
    end

    def require_teacher_for_lesson_or_ha_amt_logged_in(lesson_key)
        assert(teacher_for_lesson_or_ha_amt_logged_in?(lesson_key))
    end

    # Put this on top of a webpage to assert that this page can be opened by logged in users only
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

    # Put this on top of a webpage to assert that this page can be opened by admins only
    def this_is_a_page_for_logged_in_admins
        unless admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by zeugnis admins only
    def this_is_a_page_for_logged_in_zeugnis_admins
        unless zeugnis_admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by teachers only
    def this_is_a_page_for_logged_in_teachers
        unless teacher_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by teachers only or users who can manage the library
    def this_is_a_page_for_logged_in_teachers_or_can_manage_bib
        unless teacher_or_can_manage_bib_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by teachers or SV only
    def this_is_a_page_for_logged_in_teachers_or_sv
        unless teacher_or_sv_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    def this_is_a_page_for_logged_in_teachers_or_sv_or_users_who_can_manage_tablets
        unless teacher_or_sv_logged_in? || user_who_can_manage_tablets_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by users who can upload vplan only
    def this_is_a_page_for_people_who_can_upload_vplan
        unless user_who_can_upload_vplan_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by users who can upload files only
    def this_is_a_page_for_people_who_can_upload_files
        unless user_who_can_upload_files_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by users who can manage news only
    def this_is_a_page_for_people_who_can_manage_news
        unless user_who_can_manage_news_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # Put this on top of a webpage to assert that this page can be opened by users who can manage monitors only
    def this_is_a_page_for_people_who_can_manage_monitors
        unless user_who_can_manage_monitors_logged_in?
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
        require_user_who_can_manage_tablets_or_teacher!
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
        if @@bib_unconfirmed_books[email] && (!teacher_logged_in?)
            n_to_s = {1 => 'Eines', 2 => 'Zwei', 3 => 'Drei', 4 => 'Vier', 5 => 'Fünf'}
            result += StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<div><span style='font-size: 200%; float: left; margin-right: 8px;'>🙁</span>#{n_to_s[@@bib_unconfirmed_books[email].size] || 'Mehrere'} deiner ent&shy;lieh&shy;enen Bücher #{@@bib_unconfirmed_books[email].size == 1 ? 'wurde' : 'wurden'} von dir noch nicht bestätigt. <strong>Bitte scanne #{@@bib_unconfirmed_books[email].size == 1 ? 'das Buch' : 'die Bücher'} jetzt ein.</strong></div>"
                io.puts "<hr />"
                io.puts "<a href='/bib_confirm' style='white-space: nowrap;' class='float-right btn btn-sm btn-success'><i class='fa fa-barcode'></i>&nbsp;&nbsp;Bücher bestätigen</a>"
                io.puts "<div style='clear: both;'></div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
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
        deadline = '2023-06-26T09:00:00'
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Noteneingabe im Datentresor</b></p>"
                io.puts "<hr />"
                io.puts "<p>Die Noteneingabe im Datentresor schließt am Montag um 9:00 Uhr.</p>"
                io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                io.puts "</div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        deadline = '2023-06-28T09:00:00'
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Markierung von SuS in den Listen für die Zeugniskonferenzen</b></p>"
                io.puts "<hr />"
                io.puts "<p>Klassenleitungen: Bitte markieren Sie SuS, die Sie in den Zeug&shy;nis&shy;kon&shy;feren&shy;zen besprechen möchten, bis Mittwoch um 9:00 Uhr. Hinweis: Alle SuS mit einer Note ab 4– sind schon auto&shy;matisch markiert.</p>"
                io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                io.puts "</div>"
                io.puts "</div>"
                io.puts "</div>"
                io.string
            end
        end
        deadline = '2023-07-05T12:00:00'
        if Time.now.strftime('%Y-%m-%dT%H:%M:%S') <= deadline
            return StringIO.open do |io|
                io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
                io.puts "<div class='hint'>"
                io.puts "<p><b>Eintragung der Noten für das Arbeits- und Sozialverhalten</b></p>"
                io.puts "<hr />"
                io.puts "<p>Die Möglichkeit für Eintragungen der Noten für das Arbeits- und Sozialverhalten endet am Mittwoch um 12:00 Uhr. Bitte tragen Sie bis dahin fehlende Noten ein, damit die Klassenleitungen bis zu den Zeugniskonferenzen die Listen drucken können.</p>"
                io.puts "<div id='tresor_countdown_here' style='display: none;' data-deadline='#{Time.parse(deadline).to_i}'>"
                io.puts "</div>"
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
        respond_raw_with_mimetype(get_single_timetable_pdf(@session_user[:email]), 'application/pdf')
    end

end
