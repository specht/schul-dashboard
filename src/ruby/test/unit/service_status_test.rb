require_relative 'test_helper'
require_app 'service_status'
require 'tmpdir'

class ServiceStatusTest < Minitest::Test
    def test_heartbeat_is_written_and_read
        Dir.mktmpdir do |dir|
            ServiceStatus.write('timetable', dir: dir, now: Time.at(1000))
            statuses = ServiceStatus.read_all(dir: dir)
            assert_equal ['timetable'], statuses.map { |s| s['service'] }
            assert_equal 1000, statuses.first['time']
            assert_equal ['timetable.json'], Dir.children(dir)
        end
    end

    def test_healthy_service_has_no_problem
        s = [{'service' => 'timetable', 'time' => 1000, 'dead_threads' => []}]
        assert_empty ServiceStatus.problems(s, now: Time.at(1000 + 60))
    end

    def test_silent_service_is_a_problem
        s = [{'service' => 'mail_bot', 'time' => 1000, 'dead_threads' => []}]
        problems = ServiceStatus.problems(s, now: Time.at(1000 + ServiceStatus::STALE_AFTER + 60))
        assert_match(/keine Rückmeldung seit 6 Minuten/, problems['mail_bot'])
    end

    def test_dead_worker_thread_is_a_problem
        s = [{'service' => 'mail_forwarder', 'time' => 1000, 'dead_threads' => ['send']}]
        assert_equal 'Arbeits-Thread beendet: send', ServiceStatus.problems(s, now: Time.at(1010))['mail_forwarder']
    end

    def test_watched_threads_are_reported
        t = Thread.new { }
        t.join
        ServiceStatus.watch('test-worker', t)
        assert_includes ServiceStatus.snapshot('x')['dead_threads'], 'test-worker'
    ensure
        ServiceStatus.instance_variable_get(:@threads).delete('test-worker')
    end

    def test_changes_report_each_problem_once
        new_problems, resolved = ServiceStatus.changes({}, {'mail_bot' => 'down'})
        assert_equal({'mail_bot' => 'down'}, new_problems)
        assert_empty resolved
        # still the same problem (only the minutes changed): nothing new
        assert_equal [{}, []], ServiceStatus.changes({'mail_bot' => 'seit 6 Minuten'}, {'mail_bot' => 'seit 7 Minuten'})
        # resolved
        assert_equal [{}, ['mail_bot']], ServiceStatus.changes({'mail_bot' => 'down'}, {})
    end
end
