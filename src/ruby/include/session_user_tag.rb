# Which user a page was loaded for (code.js sends it with every request, the
# before filter in main.rb refuses a request for someone else: a login or
# logout in another tab).
class Main < Sinatra::Base
    # not secret: the page's own user; a hash so the address isn't in every request
    def self.session_user_tag(user)
        return '' unless user && user[:email]
        Digest::SHA256.hexdigest("dashboard-user:#{user[:email]}")[0, 16]
    end

    # the page's <meta>: only where the user comes from the session cookie,
    # which the page's requests carry as well – a page whose user comes from
    # its address (the monitors' deep links) sends nothing and works as before
    def dashboard_user_meta
        return '' unless @session_user && @used_session
        "<meta name='dashboard-user' content='#{Main.session_user_tag(@session_user)}'>"
    end
end
