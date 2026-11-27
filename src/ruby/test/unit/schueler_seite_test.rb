require_relative 'test_helper'

# The student's page (include/schueler_seite.rb): the lessons with the LKs
# first, then by lessons per week, then by subject.
class SchuelerSeiteTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'include/schuelerliste'
            require_app 'include/schueler_seite'
        end
    end

    def row(key, fach_code, fach, hours, klassen = ['11'])
        { :key => key, :fach => fach, :hours => hours, :info => { :fach => fach_code, :klassen => klassen } }
    end

    def test_lks_first_then_by_lessons_per_week
        rows = [
            row('bio_11', 'bio', 'Biologie', 3),
            row('EN_11', 'EN', 'Englisch LK', 5),
            row('de_11', 'de', 'Deutsch', 4),
            row('MA_11', 'MA', 'Mathematik LK', 5),
            row('ZK_11', 'ZK', 'Zusatzkurs', 2),
            row('ch_11', 'ch', 'Chemie', 3),
        ]
        assert_equal %w(EN_11 MA_11 de_11 bio_11 ch_11 ZK_11), Main.schueler_seite_order(rows).map { |r| r[:key] }
    end

    def test_below_11_by_lessons_per_week
        rows = [row('Mu_5a', 'Mu', 'Musik', 2, ['5a']), row('Nawi_5a', 'Nawi', 'Naturwissenschaften', 4, ['5a']),
                row('Ma_5a', 'Ma', 'Mathematik', 5, ['5a']), row('Ku_5a', 'Ku', 'Kunst', 2, ['5a'])]
        assert_equal %w(Ma_5a Nawi_5a Ku_5a Mu_5a), Main.schueler_seite_order(rows).map { |r| r[:key] }
    end
end
