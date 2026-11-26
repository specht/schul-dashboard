require_relative 'test_helper'

# The page's user for its requests (include/session_user_tag.rb): only where
# the user comes from the session cookie. The hallway monitors are opened by
# a deep link without a session – a tag there made the server refuse all
# their requests (»logged out in another tab«).
class SessionUserTagTest < Minitest::Test
    def setup
        Dir.chdir(APP_ROOT) { require_app 'include/session_user_tag' }
        @main = Main.allocate
    end

    def test_a_page_with_a_session_names_its_user
        @main.instance_variable_set(:@session_user, { :email => 'a@x' })
        @main.instance_variable_set(:@used_session, { :sid => 's' })
        assert_equal "<meta name='dashboard-user' content='#{Main.session_user_tag({ :email => 'a@x' })}'>", @main.dashboard_user_meta
        refute_equal Main.session_user_tag({ :email => 'a@x' }), Main.session_user_tag({ :email => 'b@x' })
    end

    def test_a_user_without_a_session_names_nobody
        # a monitor's deep link sets the user for the page only
        @main.instance_variable_set(:@session_user, { :email => 'monitor@x', :is_monitor => true })
        @main.instance_variable_set(:@used_session, nil)
        assert_equal '', @main.dashboard_user_meta
        @main.instance_variable_set(:@session_user, nil)
        assert_equal '', @main.dashboard_user_meta
    end
end
