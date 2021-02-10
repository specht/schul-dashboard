class Main < Sinatra::Base
    def user_logged_in?
        !@session_user.nil?
    end
    
    def user_who_can_upload_vplan_logged_in?
        user_logged_in? && @session_user[:can_upload_vplan]
    end
    
    def user_who_can_upload_files_logged_in?
        user_logged_in? && @session_user[:can_upload_files]
    end
    
    def user_who_can_manage_news_logged_in?
        user_logged_in? && @session_user[:can_manage_news]
    end
    
    def teacher_or_sv_logged_in?
        teacher_logged_in? || @session_user[:sv]
    end
    
    def admin_logged_in?
        @session_user && ADMIN_USERS.include?(@session_user[:email])
        # TODO: Erm
#         false
    end
    
    def can_see_all_timetables_logged_in?
        @session_user && (admin_logged_in? || @session_user[:can_see_all_timetables])
    end
    
    def teacher_logged_in?
        @session_user && (@session_user[:teacher] == true)
    end
    
    def sus_logged_in?
        @session_user && (!(@session_user[:teacher] == true))
    end
    
    def teacher_tablet_logged_in?
        @session_user && @session_user[:email] == "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
    end
    
    def kurs_tablet_logged_in?
        @session_user && @session_user[:email] == "kurs.tablet@#{SCHUL_MAIL_DOMAIN}"
    end
    
    def tablet_logged_in?
        teacher_tablet_logged_in? || kurs_tablet_logged_in?
    end
    
    def klassenleiter_for_klasse_logged_in?(klasse)
        return false unless @@klassenleiter[klasse]
        teacher_logged_in? && @@klassenleiter[klasse].include?(@session_user[:shorthand])
    end
    
    def require_user!
        assert(user_logged_in?)
    end
    
    def require_admin!
        assert(admin_logged_in?)
    end
    
    def require_teacher!
        assert(teacher_logged_in?)
    end
    
    def require_teacher_tablet!
        assert(teacher_tablet_logged_in?)
    end
    
    def require_user_who_can_upload_vplan!
        assert(user_who_can_upload_vplan_logged_in?)
    end
    
    def require_user_who_can_upload_files!
        assert(user_who_can_upload_files_logged_in?)
    end
    
    def require_user_who_can_manage_news!
        assert(user_who_can_manage_news_logged_in?)
    end
    
    def require_teacher_or_sv!
        assert(teacher_or_sv_logged_in?)
    end
    
    def this_is_a_page_for_logged_in_users
        unless user_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_logged_in_admins
        unless admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_logged_in_teachers
        unless teacher_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_logged_in_teachers_or_sv
        unless teacher_or_sv_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_people_who_can_upload_vplan
        unless user_who_can_upload_vplan_logged_in?
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
    
    def user_icon(email, c = nil)
        "<div style='background-image: url(#{NEXTCLOUD_URL}/index.php/avatar/#{@@user_info[email][:nc_login]}/128), url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mO88h8AAq0B1REmZuEAAAAASUVORK5CYII=);' class='#{c}'></div>"
    end
end
