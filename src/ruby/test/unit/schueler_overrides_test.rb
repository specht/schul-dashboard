require_relative 'test_helper'
require 'tmpdir'

# Rufname and gender the dashboard uses instead of LUSD's (Parser,
# schueler/overrides.yaml): applied to every list, the address stays,
# report cards keep the official values.
class SchuelerOverridesTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            @parser = Parser.new
        end
    end

    def list(lines)
        dir = Dir.mktmpdir
        path = File.join(dir, '2099-01-01.TXT')
        File.write(path, lines.join("\n") + "\n")
        path
    end

    def parse(path, overrides)
        records = []
        @parser.parse_schueler(path, all_classes: true, overrides: overrides) { |r| records << r }
        records.to_h { |r| [r[:email], r] }
    end

    def test_rufname_and_gender
        path = list(["Muster\tAnna Maria\t5a\tw\t2014-01-01\t\t\tanna.muster@#{SCHUL_MAIL_DOMAIN}"])
        email = "anna.muster@#{SCHUL_MAIL_DOMAIN}"
        r = parse(path, { email => { 'rufname' => 'Alex', 'geschlecht' => 'd' } })[email]
        assert_equal 'Alex', r[:first_name]
        assert_equal 'Alex Muster', r[:display_name]
        assert_equal 'd', r[:geschlecht]
        # the account and the official values stay
        assert_equal email, r[:email]
        assert_equal 'Anna Maria', r[:official_first_name]
        assert_equal 'w', r[:official_geschlecht]
        assert_equal({ 'rufname' => ['Anna', 'Alex'], 'geschlecht' => ['w', 'd'] }, r[:overrides])
    end

    def test_without_override
        path = list(["Muster\tBen\t5a\tm\t2014-01-01\t\t\tben.muster@#{SCHUL_MAIL_DOMAIN}"])
        r = parse(path, {})["ben.muster@#{SCHUL_MAIL_DOMAIN}"]
        assert_equal 'Ben', r[:first_name]
        assert_equal 'm', r[:official_geschlecht]
        assert_nil r[:overrides]
    end

    # only what differs counts; an unknown gender is ignored
    def test_same_value_or_invalid_is_no_override
        path = list(["Muster\tBen\t5a\tm\t2014-01-01\t\t\tben.muster@#{SCHUL_MAIL_DOMAIN}"])
        r = parse(path, { "ben.muster@#{SCHUL_MAIL_DOMAIN}" => { 'rufname' => 'Ben', 'geschlecht' => 'x' } })["ben.muster@#{SCHUL_MAIL_DOMAIN}"]
        assert_nil r[:overrides]
        assert_equal 'm', r[:geschlecht]
    end

    def test_broken_file_means_none
        dir = Dir.mktmpdir
        path = File.join(dir, 'overrides.yaml')
        File.write(path, "a: [b\n")
        assert_equal({}, Parser.schueler_overrides(path))
        assert_equal({}, Parser.schueler_overrides(File.join(dir, 'missing.yaml')))
    end

    # report cards: the official first name and gender, never an override
    def test_report_cards_use_official_values
        source = File.read(File.join(APP_ROOT, 'include', 'zeugnisse.rb'))
        refute_match(/@@user_info\[email\]\[:first_name\]/, source)
        refute_match(/[^(]@@user_info\[email\]\[:geschlecht\]\s*$/, source)
        assert_match(/:official_geschlecht/, source)
    end
end
