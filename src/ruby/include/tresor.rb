class Main < Sinatra::Base

    def user_is_eligible_for_tresor?
        return false unless user_logged_in?
        return false if DATENTRESOR_UNLOCKED_FOR.nil?
        return false unless teacher_logged_in?
        return teacher_logged_in? && DATENTRESOR_UNLOCKED_FOR.include?(@session_user[:email])
    end

end
