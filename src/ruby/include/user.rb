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
    
    # Returns true if a teacher or SV is logged in.
    def teacher_or_sv_logged_in?
        user_logged_in? && (teacher_logged_in? || @session_user[:sv])
    end
    
    # Returns true if an admin is logged in.
    def admin_logged_in?
        user_logged_in? && ADMIN_USERS.include?(@session_user[:email])
        # TODO: Erm
#         false
    end
    
    # Returns true if a user who can see all timetables is logged in.
    def can_see_all_timetables_logged_in?
        user_logged_in? && (admin_logged_in? || @session_user[:can_see_all_timetables])
    end
    
    # Returns true if a teacher is logged in.
    def teacher_logged_in?
        user_logged_in? && (@session_user[:teacher] == true)
    end
    
    # Returns true if a SuS is logged in.
    def sus_logged_in?
        user_logged_in? && (!(@session_user[:teacher] == true))
    end
    
    # Returns true if a teacher tablet is logged in.
    def teacher_tablet_logged_in?
        user_logged_in? && @session_user[:email] == "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
    end
    
    # Returns true if a kurs tablet is logged in.
    def kurs_tablet_logged_in?
        user_logged_in? && @session_user[:email] == "kurs.tablet@#{SCHUL_MAIL_DOMAIN}"
    end
    
    # Returns true if a tablet is logged in.
    def tablet_logged_in?
        teacher_tablet_logged_in? || kurs_tablet_logged_in?
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
    
    # Assert that a user is logged in
    def require_user!
        assert(user_logged_in?)
    end
    
    # Assert that an admin is logged in
    def require_admin!
        assert(admin_logged_in?)
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
    
    # Assert that a teacher or SV is logged in
    def require_teacher_or_sv!
        assert(teacher_or_sv_logged_in?)
    end
    
    # Put this on top of a webpage to assert that this page can be opened by logged in users only
    def this_is_a_page_for_logged_in_users
        unless user_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    # Put this on top of a webpage to assert that this page can be opened by admins only
    def this_is_a_page_for_logged_in_admins
        unless admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    # Put this on top of a webpage to assert that this page can be opened by teachers only
    def this_is_a_page_for_logged_in_teachers
        unless teacher_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    # Put this on top of a webpage to assert that this page can be opened by teachers or SV only
    def this_is_a_page_for_logged_in_teachers_or_sv
        unless teacher_or_sv_logged_in?
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
    
    # Return a <div> with a background image taken from a user's Nextcloud account,
    # with a gray background as a default fallback.
    # @param email [String] the user's email address
    # @param c [String] a CSS class to apply to the div (e. g. avatar-lg)
    # @return [String] the HTML string describing the <div>
    def user_icon(email, c = nil)
        "<div style='background-image: url(#{NEXTCLOUD_URL}/index.php/avatar/#{@@user_info[email][:nc_login]}/128), url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mO88h8AAq0B1REmZuEAAAAASUVORK5CYII=);' class='#{c}'></div>"
    end
end
