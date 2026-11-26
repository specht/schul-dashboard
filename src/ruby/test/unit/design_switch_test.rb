require_relative 'test_helper'

# From NEW_DESIGN_FOR_ALL_FROM everyone has the new design, with no way back;
# only admins can still switch it off to compare (include/design_preview.rb).
class DesignSwitchTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) { require_app 'include/design_preview' }
        @day = Main::NEW_DESIGN_FOR_ALL_FROM
    end

    def test_before_the_day_the_own_choice
        before = @day - 1
        refute Main.new_design_for_all?(before)
        refute Main.ui_preview_for_account({}, false, before)
        assert Main.ui_preview_for_account({ :ui_preview => true }, false, before)
        refute Main.ui_preview_for_account({ :ui_preview => false }, true, before)
    end

    def test_from_the_day_everyone
        assert Main.new_design_for_all?(@day)
        # never switched on, switched off before: the new design all the same
        assert Main.ui_preview_for_account({}, false, @day)
        assert Main.ui_preview_for_account({ :ui_preview => false, :ui_preview_ts => (@day - 10).to_time.to_i }, false, @day)
        # no way back for anyone but admins
        assert Main.ui_preview_for_account({ :ui_preview => false, :ui_preview_ts => (@day + 1).to_time.to_i }, false, @day + 2)
        refute Main.ui_preview_for_account({ :ui_preview => false, :ui_preview_ts => (@day + 1).to_time.to_i }, true, @day + 2)
        # an admin's switch-off from before doesn't count either
        assert Main.ui_preview_for_account({ :ui_preview => false, :ui_preview_ts => (@day - 1).to_time.to_i }, true, @day)
    end
end
