require_relative 'test_helper'
require_app 'switch_weeks'

class SwitchWeeksTest < Minitest::Test
    WEEKS = {'2023-08-28' => ['A', 2]}

    def letter(ds)
        SwitchWeeks.letter(Date.parse(ds), WEEKS)
    end

    def test_alternates_from_the_reference_monday
        assert_equal 'A', letter('2023-08-28')
        assert_equal 'A', letter('2023-09-01')
        assert_equal 'B', letter('2023-09-04')
        assert_nil letter('2023-08-27')
    end

    # 2026 has 53 ISO weeks: the weeks must keep alternating across the new year
    def test_alternates_across_a_year_with_53_weeks
        letters = %w(2026-12-21 2026-12-28 2027-01-04 2027-01-11).map { |d| letter(d) }
        assert_equal letters.each_cons(2).map { |a, b| a != b }, [true, true, true]
    end

    # same results as before for every week up to the end of 2026 (the old
    # formula: difference of ISO week numbers)
    def test_same_as_before_until_the_end_of_2026
        old = lambda do |d|
            week_number = d.strftime('%-V').to_i - Date.parse('2023-08-28').strftime('%-V').to_i
            (((week_number + 0) % 2) + 'A'.ord).chr
        end
        d = Date.parse('2023-08-28')
        while d <= Date.parse('2026-12-31')
            assert_equal old.call(d), SwitchWeeks.letter(d, WEEKS), d.to_s
            d += 1
        end
    end
end
