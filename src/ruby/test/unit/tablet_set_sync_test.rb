require_relative 'test_helper'
require_app 'tablet_set_sync'

class TabletSetSyncTest < Minitest::Test
    def test_removes_sets_that_are_no_longer_configured
        assert_equal ['Satz 3'], TabletSetSync.ids_to_remove(['Satz 1', 'Satz 2', 'Satz 3'], ['Satz 1', 'Satz 2'])
    end

    def test_keeps_everything_if_nothing_is_configured
        # missing or empty tablet_sets.yaml must not delete all sets and bookings
        assert_equal [], TabletSetSync.ids_to_remove(['Satz 1', 'Satz 2'], [])
        assert_equal [], TabletSetSync.ids_to_remove(['Satz 1'], nil)
    end

    def test_nothing_to_remove
        assert_equal [], TabletSetSync.ids_to_remove(['Satz 1'], ['Satz 1', 'Satz 2'])
    end
end
