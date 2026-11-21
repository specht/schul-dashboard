require_relative 'test_helper'
require 'tmpdir'
require 'timeout'
require_app 'data_version'

# Reloading the data: /internal/data-version and the watcher every
# long-running service starts (data_version.rb).
class DataVersionTest < Minitest::Test
    def with_path
        Dir.mktmpdir { |dir| yield File.join(dir, 'data-version') }
    end

    def test_missing_file_reads_as_empty
        with_path { |path| assert_equal '', DataVersion.read(path) }
    end

    def test_bump_writes_a_new_version_each_time
        with_path do |path|
            a = DataVersion.bump!(path, 'by admin@example.org')
            b = DataVersion.bump!(path)
            refute_equal a, b
            assert_equal b, DataVersion.read(path)
            assert_match(/by admin@example\.org\z/, a)
            assert_equal ['data-version'], Dir.children(File.dirname(path)), 'no temporary files left'
        end
    end

    def test_watch_fires_once_after_a_change
        with_path do |path|
            known = DataVersion.bump!(path)
            seen = Queue.new
            thread = DataVersion.watch(known, path: path, interval: 0.05) { |v| seen << v }
            sleep 0.2
            assert seen.empty?, 'no change, no reload'
            changed = DataVersion.bump!(path)
            assert_equal changed, Timeout.timeout(2) { seen.pop }
            thread.join(1)
            refute thread.alive?, 'the watcher stops after firing'
        end
    end

    # A version written while the service was still reading its data (before
    # the watcher started) must still trigger a reload.
    def test_change_before_the_watcher_starts_is_not_lost
        with_path do |path|
            known = DataVersion.read(path)
            DataVersion.bump!(path)
            seen = Queue.new
            DataVersion.watch(known, path: path, interval: 0.05) { |v| seen << v }
            refute_nil Timeout.timeout(2) { seen.pop }
        end
    end

    def test_restart_needs_a_command_line
        assert_raises(RuntimeError) { DataVersion.restart!([]) }
    end

    def test_command_line_is_captured_on_linux
        skip 'no /proc' unless File.exist?('/proc/self/cmdline')
        assert_kind_of Array, DataVersion::COMMAND
        assert_match(/ruby/, DataVersion::COMMAND.first)
    end
end
