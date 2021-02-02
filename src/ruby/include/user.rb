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
    
    def all_sessions
        sids = request.cookies['sid']
        users = []
        if (sids.is_a? String) && (sids =~ /^[0-9A-Za-z,]+$/)
            sids.split(',').each do |sid|
                if sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| {:sid => x['sid'], :email => x['email'] } }
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                        RETURN s.sid AS sid, u.email AS email;
                    END_OF_QUERY
                    results.each do |entry|
                        if entry[:email] && @@user_info[entry[:email]]
                            users << {:sid => entry[:sid], :user => @@user_info[entry[:email]].dup}
                        end
                    end
                end
            end
        end
        users
    end
    
    def purge_missing_sessions(current_sid = nil, remove_other = false)
        sid = request.cookies['sid']
        existing_sids = []
        unless remove_other
            if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
                sids = sid.split(',')
                sids.each do |sid|
                    if sid =~ /^[0-9A-Za-z]+$/
                        results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| x['sid'] }
                            MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                            RETURN s.sid AS sid;
                        END_OF_QUERY
                        existing_sids << sid unless results.empty?
                    end
                end
            end
            existing_sids.uniq!
        end
        if current_sid
            # insert current SID if it's not there yet (new sessions ID)
            unless existing_sids.include?(current_sid)
                existing_sids.unshift(current_sid)
            end
            # move current SID to front
            existing_sids -= [current_sid]
            existing_sids.unshift(current_sid)
        end
        new_cookie_value = existing_sids.join(',')
        if new_cookie_value.empty? && request.cookies['sid']
            response.delete_cookie('sid')
        end
        if (request.cookies['sid'] || '') != new_cookie_value
            response.set_cookie('sid', 
                                :value => new_cookie_value,
                                :expires => Time.new + COOKIE_EXPIRY_TIME,
                                :path => '/',
                                :httponly => true,
                                :secure => DEVELOPMENT ? false : true)
        end
    end
end
