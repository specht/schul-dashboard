# Reloading the input data (/data) without restarting the containers by hand.
#
# Writing a new version to /internal/data-version (DataVersion.bump!) makes
# every long-running service (web service, timetable and the bots) start
# again with its original command line, in the same process – so it reads
# all data again, the same in production, in development (under rerun) and
# in the test stack. Exiting and relying on Docker's restart policy would not
# work in development, where services are not restarted automatically.
#
# Each service checks the version every few seconds (watch). A service
# remembers the version it started with *before* reading the data, so a
# change while it is still starting is not lost.

require 'securerandom'

module DataVersion
    PATH = '/internal/data-version'
    INTERVAL = 10

    # The command line as started, captured when this file is loaded – later
    # puma rewrites the process title, which also changes /proc/self/cmdline.
    COMMAND = begin
        File.binread('/proc/self/cmdline').split("\0").freeze
    rescue StandardError
        nil
    end

    def self.read(path = PATH)
        File.exist?(path) ? File.read(path).strip : ''
    rescue StandardError
        ''
    end

    # Writes a new version and returns it; services pick it up within
    # INTERVAL seconds.
    def self.bump!(path = PATH, reason = '')
        version = "#{Time.now.strftime('%Y-%m-%dT%H:%M:%S')} #{SecureRandom.hex(4)} #{reason}".strip
        tmp = "#{path}.#{SecureRandom.hex(4)}.tmp"
        File.write(tmp, version + "\n")
        File.rename(tmp, path)
        version
    end

    # Calls the block once (in a background thread) as soon as the version
    # at path differs from known – or the value of state, if given, from
    # known_state (e.g. which dated student list is current: a list dated
    # tomorrow takes over at midnight without anyone writing a version).
    # Returns the thread.
    def self.watch(known, path: PATH, interval: INTERVAL, state: nil, known_state: nil, &on_change)
        Thread.new do
            loop do
                sleep interval
                current = read(path)
                next if current == known && (state.nil? || state.call == known_state)
                on_change.call(current)
                break
            end
        end
    end

    # Off in the test stack (DATA_RELOAD_RESTARTS = false in env.test.rb):
    # its services are shared by all E2E tests.
    def self.restarts?
        ENV['DASHBOARD_DATA_RELOAD'] != 'off'
    end

    # Replaces this process by a fresh start of the same command.
    def self.restart!(command = COMMAND)
        raise 'command line unknown' if command.nil? || command.empty?
        STDERR.puts "Data changed (#{read}), restarting: #{command.join(' ')}"
        STDOUT.flush
        STDERR.flush
        # [program, argv0] form: never through a shell, even for one word
        Process.exec([command[0], command[0]], *command[1..])
    end
end
