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
