require_relative 'test_helper'

# The comparison of two timetables on /datenpflege
# (include/datenpflege_stundenplan.rb): slot by slot per class, the
# Unterrichtsnummer doesn't count, Untis' class names as the dashboard's.
class StundenplanDiffTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            require_app 'include/datenpflege_stundenplan'
        end
    end

    def row(unr, klasse, lehrer, fach, raum, dow, stunde)
        [unr, klasse, lehrer, fach, raum, dow.to_s, stunde.to_s]
    end

    def test_changed_new_gone
        before = [row('1', '5a', 'Cl', 'Ma', '108', 2, 4), row('2', '5a', 'Cl', 'Nawi', '323', 4, 3), row('3', '8?', 'Ab', 'De', '201', 1, 1)]
        after = [row('9', '5a', 'Cl', 'Ma', '109', 2, 4), row('4', '5a', 'Fr', 'Ku', '205', 1, 5), row('3', '8o', 'Ab', 'De', '201', 1, 1)]
        d = Main.stundenplan_diff(before, after)
        assert_equal [1, 1, 1], d.values_at(:changed, :added, :removed)
        assert_equal ['5a'], d[:klassen].keys
        slots = d[:klassen]['5a'].to_h { |s| [[s[:dow], s[:stunde]], s] }
        assert_equal [['Cl', 'Ma', '108']], slots[[2, 4]][:before]
        assert_equal [['Cl', 'Ma', '109']], slots[[2, 4]][:after]
        assert_empty slots[[4, 3]][:after]
        assert_empty slots[[1, 5]][:before]
        assert_equal %w(Cl Fr), d[:lehrer]
    end

    def test_same_timetable_no_change
        rows = [row('1', '5a', 'Cl', 'Ma', '108', 2, 4)]
        d = Main.stundenplan_diff(rows, rows.map { |r| r.dup.tap { |x| x[0] = '7' } })
        assert_equal [0, 0, 0], d.values_at(:changed, :added, :removed)
        assert_empty d[:klassen]
    end

    def test_break_duties
        a = Main.stundenplan_aufsichten_diff([%w(Hof Cl 1 1)], [%w(Hof Cl 1 1), %w(Eingang Fr 2 3)])
        assert_equal [%w(Eingang Fr 2 3)], a[:added]
        assert_empty a[:removed]
    end
end
