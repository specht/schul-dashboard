require_relative 'test_helper'

# Parses the files in src/example-data (mounted at /data in the test stack).
class ParserTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            @parser = Parser.new
        end
    end

    def test_faecher
        faecher = {}
        @parser.parse_faecher { |fach, bezeichnung| faecher[fach] = bezeichnung }
        assert_equal 'Biologie', faecher['Bio']
        assert_equal 'Altgriechisch', faecher['Agr']
    end

    def test_lehrer
        lehrer = []
        @parser.parse_lehrer { |record| lehrer << record }
        clarke = lehrer.find { |r| r[:email] == 'clarke@beispielschule.de' }
        refute_nil clarke
        assert_equal 'Cl', clarke[:shorthand]
        assert clarke[:can_log_in]
    end

    def test_ferien_feiertage_are_date_ranges
        ranges = []
        @parser.parse_ferien_feiertage { |from, to, title| ranges << [from, to, title] }
        refute_empty ranges
        ranges.each do |from, to, title|
            assert Date.parse(from) <= Date.parse(to), "#{title}: #{from} > #{to}"
        end
    end
end

# Class names from the Untis substitution plan (no data needed).
class ParserKlasseFromUntisTest < Minitest::Test
    ORDER = ['8a', '8o', '9o', '10a']
    TR = {'8o' => '8ω'}

    def setup
        Dir.chdir(APP_ROOT) { require_app 'parser' } unless defined?(Parser)
    rescue LoadError, StandardError
        skip 'parser.rb needs the test stack (./test.sh unit)'
    end

    def tr(name) = Parser.klasse_from_untis(name, ORDER, TR)

    def test_known_names_stay
        assert_equal '8a', tr('8a')
        assert_equal '8o', tr('8o')
    end

    def test_omega_spellings_map_to_the_dashboard_name
        assert_equal '8o', tr('8omega')
        assert_equal '8o', tr('8ω')
        # Untis entries abbreviate omega as "w"
        assert_equal '8o', tr('8w')
        assert_equal '9o', tr('9w')
        # no KLASSEN_TR entry, but "9o" exists
        assert_equal '9o', tr('9omega')
    end

    def test_unknown_names_are_kept
        assert_equal '7omega', tr('7omega')
        assert_equal 'Bereitschaft', tr('Bereitschaft')
        assert_equal '', tr('')
    end
end
