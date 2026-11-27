require_relative 'test_helper'

# The student's page (include/schueler_seite.rb): the lessons with the LKs
# first, then by subject.
class SchuelerSeiteTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'include/schuelerliste'
            require_app 'include/schueler_seite'
        end
    end

    def row(key, fach_code, fach, klassen = ['11'])
        { :key => key, :fach => fach, :info => { :fach => fach_code, :klassen => klassen } }
    end

    def test_lks_first_then_by_subject
        rows = [
            row('bio_11', 'bio', 'Biologie'),
            row('EN_11', 'EN', 'Englisch LK'),
            row('de_11', 'de', 'Deutsch'),
            row('MA_11', 'MA', 'Mathematik LK'),
            row('ZK_11', 'ZK', 'Zusatzkurs'),
        ]
        assert_equal %w(EN_11 MA_11 bio_11 de_11 ZK_11), Main.schueler_seite_order(rows).map { |r| r[:key] }
    end

    def test_below_11_by_subject_only
        rows = [row('Nawi_5a', 'Nawi', 'Naturwissenschaften', ['5a']), row('Ma_5a', 'Ma', 'Mathematik', ['5a'])]
        assert_equal %w(Ma_5a Nawi_5a), Main.schueler_seite_order(rows).map { |r| r[:key] }
    end
end
