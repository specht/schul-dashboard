require_relative 'test_helper'
require 'cgi'
require 'date'
require 'fileutils'
require 'tmpdir'
require_app 'ical_import'

# An external calendar in one's own timetable (ical_import.rb): what a feed
# turns into. The feed below is shaped like the agenda tool's (Berlin times
# with a VTIMEZONE block, folded lines, CRLF, all-day items, cancelled and
# tentative ones).
class IcalImportTest < Minitest::Test
    FEED = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//test//DE',
        'X-WR-CALNAME:Fachbegleitung',
        'BEGIN:VTIMEZONE',
        'TZID:Europe/Berlin',
        'BEGIN:STANDARD',
        'DTSTART:19701025T030000',
        'TZOFFSETFROM:+0200',
        'TZOFFSETTO:+0100',
        'END:STANDARD',
        'END:VTIMEZONE',
        'BEGIN:VEVENT',
        'UID:aaa@fachbegleitung-agenda',
        'DTSTART;TZID=Europe/Berlin:20261124T093000',
        'DTEND;TZID=Europe/Berlin:20261124T111500',
        'SUMMARY:UB 2\, Besuch <b>fett</b> & so',
        'LOCATION:Gymnasium Beispiel\, Hauptstraße 1',
        'DESCRIPTION:Unterrichtsbesuch.\nTermin der Fachbegleitung Informa',
        ' tik.',
        'STATUS:CONFIRMED',
        'BEGIN:VALARM',
        'TRIGGER:-PT15M',
        'DESCRIPTION:Erinnerung',
        'END:VALARM',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:bbb@fachbegleitung-agenda',
        'DTSTART:20261125T130000Z',
        'DTEND:20261125T143000Z',
        'SUMMARY:Basismodul',
        'STATUS:TENTATIVE',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:ccc@fachbegleitung-agenda',
        'DTSTART;TZID=Europe/Berlin:20261126T080000',
        'DTEND;TZID=Europe/Berlin:20261126T090000',
        'SUMMARY:Abgesagt: Hospitation',
        'STATUS:CANCELLED',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:ddd@fachbegleitung-agenda',
        'DTSTART;VALUE=DATE:20261127',
        'DTEND;VALUE=DATE:20261128',
        'SUMMARY:Seminartag',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:eee@test',
        'DTSTART;TZID=Europe/Berlin:20261130T080000',
        'DURATION:PT45M',
        'RRULE:FREQ=WEEKLY;COUNT=5',
        'SUMMARY:Serie',
        'END:VEVENT',
        'BEGIN:VEVENT',
        'UID:fff@test',
        'DTSTART;TZID=Europe/Berlin:20250101T080000',
        'DTEND;TZID=Europe/Berlin:20250101T090000',
        'SUMMARY:Lange her',
        'END:VEVENT',
        'END:VCALENDAR',
    ].join("\r\n") + "\r\n"

    def parsed
        IcalImport.parse(FEED, Date.new(2026, 11, 1), Date.new(2027, 7, 31))
    end

    def test_reads_the_appointments_in_berlin_time
        p = parsed
        assert_equal 'Fachbegleitung', p[:calname]
        assert_equal %w(aaa@fachbegleitung-agenda bbb@fachbegleitung-agenda ddd@fachbegleitung-agenda), p[:events].map { |e| e[:uid] }
        ub = p[:events][0]
        assert_equal '2026-11-24T09:30', ub[:start]
        assert_equal '2026-11-24T11:15', ub[:end]
        assert_equal 'UB 2, Besuch <b>fett</b> & so', ub[:title]
        assert_equal 'Gymnasium Beispiel, Hauptstraße 1', ub[:location]
        # folded lines joined, \n a line break, the alarm's text not taken
        assert_equal "Unterrichtsbesuch.\nTermin der Fachbegleitung Informatik.", ub[:description]
        # UTC in winter: one hour later in Berlin
        assert_equal '2026-11-25T14:00', p[:events][1][:start]
        assert p[:events][1][:tentative]
    end

    def test_leaves_out_cancelled_series_and_the_past
        p = parsed
        refute p[:events].any? { |e| e[:title].start_with?('Abgesagt') }
        refute p[:events].any? { |e| e[:title] == 'Lange her' }
        assert_equal 1, p[:skipped][:recurring]
        assert_equal 1, p[:skipped][:cancelled]
    end

    def test_all_day
        day = parsed[:events].find { |e| e[:uid].start_with?('ddd') }
        assert day[:all_day]
        assert_equal ['2026-11-27', '2026-11-28'], [day[:start], day[:end]]
    end

    def test_no_calendar
        assert_nil IcalImport.parse('<html>Anmeldung</html>', Date.today, Date.today + 1)
    end

    # text from the feed is escaped where the timetable inserts HTML, the
    # items carry their source, and they are no Termine of the dashboard
    def test_week_events_are_escaped_and_marked
        e = IcalImport.week_event(parsed[:events][0], 'Fach<begleitung>')
        assert_equal 'agenda', e[:event_type]
        assert_equal 'ical', e[:source]
        assert_equal 'aaa@fachbegleitung-agenda', e[:uid]
        assert_equal 'UB 2, Besuch &lt;b&gt;fett&lt;/b&gt; &amp; so', e[:event_title]
        assert_equal 'UB 2, Besuch <b>fett</b> & so', e[:title]
        assert_equal 'Fach&lt;begleitung&gt;', e[:organized_by]
        assert_includes e[:description], 'Ort: Gymnasium Beispiel, Hauptstraße 1<br />'
        assert_equal 'Gymnasium Beispiel', e[:room_name]
        assert_equal false, e[:jitsi]
        assert_nil e[:organized_by_email]
        tentative = IcalImport.week_event(parsed[:events][1], 'X')
        assert_equal 'Basismodul (vorläufig)', tentative[:title]
        day = IcalImport.week_event(parsed[:events][2], 'X')
        assert day[:allDay]
        refute day[:is_event]
        assert_equal 'Seminartag', day[:label]
    end

    def test_events_by_week
        dir = Dir.mktmpdir
        IcalImport.stub_const_dir(dir) do
            assert IcalImport.write('a@b.de', parsed, 'example.org')
            # the same again: nothing changed
            refute IcalImport.write('a@b.de', parsed, 'example.org')
            weeks = IcalImport.events_by_week('a@b.de')
            assert_equal ['2026-48'], weeks.keys
            assert_equal 3, weeks['2026-48'].size
            assert IcalImport.remove('a@b.de')
            assert_equal({}, IcalImport.events_by_week('a@b.de'))
        end
    ensure
        FileUtils.rm_rf(dir) if dir
    end
end

module IcalImport
    # tests only: the cache in a temporary directory
    def self.stub_const_dir(dir)
        old = DIR
        silence = $VERBOSE
        $VERBOSE = nil
        const_set(:DIR, dir)
        yield
    ensure
        const_set(:DIR, old)
        $VERBOSE = silence
    end
end
