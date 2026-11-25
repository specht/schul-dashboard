require_relative 'test_helper'
require 'tmpdir'
require 'yaml'

# Students abroad for a while (/datenpflege, schueler/im-ausland.yaml): away
# until their return date – the first day back – or until the entry ends.
# Made-up addresses.
class ParserAbroadTest < Minitest::Test
    def setup
        Dir.chdir(APP_ROOT) { require_app 'parser' }
    end

    def test_away_until_the_return_date
        Dir.mktmpdir do |dir|
            File.write(File.join(dir, 'im-ausland.yaml'), {
                'ohne@x' => { 'name' => 'Ohne Datum' },
                'morgen@x' => { 'zurueck' => '2026-03-02' },
                'heute@x' => { 'zurueck' => '2026-03-01' },
                'vorbei@x' => { 'zurueck' => '2026-02-01' },
            }.to_yaml)
            away = Parser.abroad_now(Date.new(2026, 3, 1), dir)
            assert_equal ['morgen@x', 'ohne@x'], away.keys.sort
            # all entries, also the ones that ended (tidied up by /datenpflege)
            assert_equal 4, Parser.schueler_abroad(dir).size
        end
    end

    def test_no_file_nobody
        Dir.mktmpdir { |dir| assert_equal({}, Parser.abroad_now(Date.today, dir)) }
    end
end
