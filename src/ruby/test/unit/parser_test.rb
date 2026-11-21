require_relative 'test_helper'
require 'tmpdir'

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

# Dated student lists (uploads on /datenpflege): the newest list whose date
# has come is valid, else ASCII.TXT.
class ParserSchuelerPathTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) { require_app 'parser' }
        # main.rb's gems bring the locales remove_accents needs; alone the
        # parser has none
        I18n.enforce_available_locales = false
    end

    def test_newest_list_whose_date_has_come
        Dir.mktmpdir do |dir|
            assert_equal File.join(dir, 'ASCII.TXT'), Parser.schueler_path(Date.new(2026, 11, 20), dir)
            ['2026-08-01', '2026-11-20', '2027-08-01'].each { |d| File.write(File.join(dir, "#{d}.TXT"), '') }
            File.write(File.join(dir, 'notes.TXT'), '')
            assert_equal File.join(dir, '2026-08-01.TXT'), Parser.schueler_path(Date.new(2026, 11, 19), dir)
            assert_equal File.join(dir, '2026-11-20.TXT'), Parser.schueler_path(Date.new(2026, 11, 20), dir)
            assert_equal File.join(dir, '2027-08-01.TXT'), Parser.schueler_path(Date.new(2027, 8, 1), dir)
            assert_equal File.join(dir, 'ASCII.TXT'), Parser.schueler_path(Date.new(2026, 7, 1), dir)
            assert_equal ['2026-08-01', '2026-11-20', '2027-08-01'], Parser.schueler_files(dir).keys
        end
    end

    # a bad line no longer ends the process (an upload would take the web
    # service down): it raises, with the line's name
    def test_bad_gender_raises_instead_of_exiting
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'liste.TXT')
            File.write(path, "Mustermann\tMax\t5a\tm\t01.01.2014\nMustermann\tMia\t5a\tx\t02.01.2014\n")
            e = assert_raises(Parser::SchuelerLineError) { Parser.new.parse_schueler(path) { |_| } }
            assert_match(/Mia Mustermann: Geschlecht »x« \(erlaubt: m, w, d\)/, e.message)
        end
    end

    # lists from /datenpflege: divers, and the Bildungsgang as 7th column
    def test_divers_and_bildungsgang
        Dir.mktmpdir do |dir|
            path = File.join(dir, '2026-11-20.TXT')
            File.write(path, "Mustermann\tMax\t5a\td\t01.01.2014\t\tregulaer\nMustermann\tMia\t5a\tw\t02.01.2014\tMimi\tsesb\nMustermann\tMo\t5a\tm\t03.01.2014\n")
            records = []
            Parser.new.parse_schueler(path) { |r| records << r }
            assert_equal [['d', :regulaer, 'Max'], ['w', :sesb, 'Mimi'], ['m', nil, 'Mo']],
                         records.first(3).map { |r| [r[:geschlecht], r[:bildungsgang], r[:first_name]] }
        end
    end

    def test_all_classes_includes_unknown_classes
        Dir.mktmpdir do |dir|
            path = File.join(dir, 'liste.TXT')
            File.write(path, "Mustermann\tMax\t5a\tm\t01.01.2014\nMustermann\tQuentin\tq9\tm\t02.01.2008\n")
            known = []
            Parser.new.parse_schueler(path) { |r| known << r[:klasse] }
            all = []
            Parser.new.parse_schueler(path, all_classes: true) { |r| all << r[:klasse] }
            refute_includes known, 'q9'
            assert_includes all, 'q9'
        end
    end
end
