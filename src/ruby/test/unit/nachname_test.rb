require_relative 'test_helper'
require 'tmpdir'

# Name particles (von, de, van der): kept behind the name like the
# dashboard's lists always had them (»Hofe, von«), shown in front (»von
# Hofe«), and the same person whatever form a list or an entry has – LUSD
# writes »von Hofe«, which marked every such student as changed. Made-up
# names.
class NachnameTest < Minitest::Test
    def test_kept_behind_shown_in_front
        require_app 'nachname'
        {
            'von Hofe' => 'Hofe, von', 'Hofe, von' => 'Hofe, von', 'Hofe,von' => 'Hofe, von',
            'van der Berg' => 'Berg, van der', 'de la Cruz' => 'Cruz, de la',
            'Müller' => 'Müller', "d'Angelo" => "d'Angelo", 'Meyer-Lüdenscheid' => 'Meyer-Lüdenscheid',
        }.each do |given, kept|
            assert_equal kept, Nachname.intern(given), given
            assert_equal Nachname.anzeige(kept), Nachname.anzeige(Nachname.intern(given)), given
        end
        assert_equal 'von Hofe', Nachname.anzeige('Hofe, von')
        assert_equal 'van der Berg', Nachname.anzeige('Berg, van der')
        assert_equal 'Müller', Nachname.anzeige('Müller')
    end

    def test_lists_read_the_same_whatever_the_form
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            # main.rb's gems bring the locales remove_accents needs; alone the
            # parser has none (passed only after a test that set this)
            I18n.enforce_available_locales = false
            records = []
            dir = Dir.mktmpdir
            path = File.join(dir, '2099-01-01.TXT')
            File.write(path, ["von Hofe\tHans\t7a\tm\t03.03.2013\t\t\thans.von.hofe@#{SCHUL_MAIL_DOMAIN}",
                              "Berg, van der\tLea\t7a\tw\t04.04.2013\t\t\tlea.van.der.berg@#{SCHUL_MAIL_DOMAIN}"].join("\n") + "\n")
            Parser.new.parse_schueler(path, all_classes: true, overrides: {}, extras: Parser::NO_EXTRAS) { |r| records << r }
            hans = records.find { |r| r[:official_first_name] == 'Hans' }
            assert_equal 'Hofe, von', hans[:last_name]
            assert_equal 'Hans von Hofe', hans[:display_name]
            assert_equal 'Berg, van der', records.find { |r| r[:official_first_name] == 'Lea' }[:last_name]
            # the same person, however the name was written
            assert_equal Parser.manual_person_key('von Hofe', 'Hans', '2013-03-03'),
                         Parser.manual_person_key('Hofe, von', 'Hans Peter', '2013-03-03')
            # the address as before (the particle in front)
            assert_equal "hans.von.hofe@#{SCHUL_MAIL_DOMAIN}", Parser.new.name_to_email('Hans', 'Hofe, von', false)
        end
    end
end
