require_relative 'test_helper'
require 'tmpdir'

# Students added by hand (not yet in LUSD) and students marked as gone
# (still in LUSD): Parser#parse_schueler applies both to every list it
# reads (schueler/zusaetzlich.yaml, schueler/abgaenge.yaml). Made-up names.
class SchuelerExtrasTest < Minitest::Test
    def setup
        skip 'needs the test stack (./test.sh unit)' unless in_test_stack?
        Dir.chdir(APP_ROOT) do
            require_app 'parser'
            @parser = Parser.new
        end
    end

    def mail(local)
        "#{local}@#{SCHUL_MAIL_DOMAIN}"
    end

    def list(lines)
        dir = Dir.mktmpdir
        path = File.join(dir, '2099-01-01.TXT')
        File.write(path, lines.join("\n") + "\n")
        path
    end

    def parse(path, extras, keep_gone: false)
        records = []
        @parser.parse_schueler(path, all_classes: true, overrides: {}, extras: extras, keep_gone: keep_gone) { |r| records << r }
        records
    end

    def added_entry(overrides = {})
        { 'nachname' => 'Neu', 'vornamen' => 'Nora Lea', 'rufname' => '', 'klasse' => '7a', 'geschlecht' => 'w',
          'geburtstag' => '2013-04-05', 'bildungsgang' => 'altsprachlich', 'by' => mail('admin'), 'at' => '2026-11-23' }.merge(overrides)
    end

    BASE = ["Muster\tBen\t7a\tm\t01.02.2013\t\t\tben.muster@%s"]

    def base_list
        list(BASE.map { |l| l % SCHUL_MAIL_DOMAIN })
    end

    def test_added_student_counts_like_any_other
        records = parse(base_list, { :added => { mail('nora.neu') => added_entry }, :gone => {} })
        nora = records.find { |r| r[:email] == mail('nora.neu') }
        assert nora
        assert nora[:manual]
        assert_equal 'Nora', nora[:first_name]
        assert_equal 'Nora Lea', nora[:official_first_name]
        assert_equal '7a', nora[:klasse]
        assert_equal '2013-04-05', nora[:geburtstag]
        assert_equal :altsprachlich, nora[:bildungsgang]
        assert_equal 2, records.size
    end

    # once LUSD has the student (an import takes the entry's address, or at
    # least name and birthday match), the entry is not added a second time
    def test_added_student_once_in_lusd_is_not_doubled
        same_address = list(BASE.map { |l| l % SCHUL_MAIL_DOMAIN } + ["Neu\tNora Lea\t7a\tw\t05.04.2013\t\t\t#{mail('nora.neu')}"])
        records = parse(same_address, { :added => { mail('nora.neu') => added_entry }, :gone => {} })
        assert_equal 1, records.count { |r| r[:last_name] == 'Neu' }
        refute records.find { |r| r[:last_name] == 'Neu' }[:manual]
        # another address in LUSD, but the same person (accents, case)
        other_address = list(BASE.map { |l| l % SCHUL_MAIL_DOMAIN } + ["NEU\tNóra\t7b\tw\t05.04.2013\t\t\t#{mail('nora.neu2')}"])
        records = parse(other_address, { :added => { mail('nora.neu') => added_entry }, :gone => {} })
        assert_equal [mail('nora.neu2')], records.select { |r| r[:last_name].downcase == 'neu' }.map { |r| r[:email] }
    end

    def test_gone_student_is_left_out
        extras = { :added => {}, :gone => { mail('ben.muster') => { 'name' => 'Ben Muster', 'klasse' => '7a' } } }
        assert_empty parse(base_list, extras)
        # to recognise them in an export that still has them
        kept = parse(base_list, extras, keep_gone: true)
        assert_equal [mail('ben.muster')], kept.map { |r| r[:email] }
        assert kept.first[:gone]
    end

    # gone wins over added: a student added by hand who left again
    def test_gone_wins_over_added
        extras = { :added => { mail('nora.neu') => added_entry }, :gone => { mail('nora.neu') => {} } }
        assert_equal [mail('ben.muster')], parse(base_list, extras).map { |r| r[:email] }
    end

    # a broken entry is skipped, not the whole list
    def test_broken_added_entry_is_skipped
        extras = { :added => { mail('kaputt') => added_entry('geschlecht' => 'x') }, :gone => {} }
        assert_equal [mail('ben.muster')], parse(base_list, extras).map { |r| r[:email] }
    end

    def test_files_in_the_data_dir
        dir = Dir.mktmpdir
        File.write(File.join(dir, 'zusaetzlich.yaml'), { mail('nora.neu') => added_entry }.to_yaml)
        File.write(File.join(dir, 'abgaenge.yaml'), "a: [b\n")
        extras = Parser.schueler_extras(dir)
        assert_equal [mail('nora.neu')], extras[:added].keys
        assert_equal({}, extras[:gone])
        assert_equal({ :added => {}, :gone => {} }, Parser.schueler_extras(File.join(dir, 'missing')))
    end
end
