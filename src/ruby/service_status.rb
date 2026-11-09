require 'json'
require 'fileutils'

# Heartbeats of the dashboard's services (web service, timetable, bots, mail
# forwarder) and their evaluation.
#
# Every service writes /internal/status/<service>.json once a minute
# (start_heartbeat, started in main.rb). Services register their important
# worker threads with watch(): a worker thread that died silently while the
# process lives on (as happened with the mail forwarder) shows up as well.
# The web service checks all status files (problems) – see the watchdog in
# main.rb – and lists them on /dienste.
module ServiceStatus
    DIR = '/internal/status'
    INTERVAL = 60
    # no heartbeat for this long: the service counts as down
    STALE_AFTER = 5 * 60

    @threads = {}
    @started = Time.now.to_i

    def self.watch(name, thread)
        @threads[name] = thread
        # report right away – the first heartbeat may have been written before
        # the service had registered its threads
        begin
            write(@service, dir: @dir) if @service
        rescue StandardError
        end
    end

    def self.snapshot(service, now: Time.now)
        {
            'service' => service,
            'pid' => Process.pid,
            'started' => @started,
            'time' => now.to_i,
            'threads' => @threads.keys.sort,
            'dead_threads' => @threads.reject { |_, t| t.alive? }.keys.sort,
        }
    end

    def self.write(service, dir: DIR, now: Time.now)
        FileUtils.mkpath(dir)
        path = File.join(dir, "#{service}.json")
        tmp = "#{path}.tmp-#{Process.pid}"
        File.write(tmp, snapshot(service, now: now).to_json)
        File.rename(tmp, path)
    end

    def self.start_heartbeat(service, dir: DIR)
        @service = service
        @dir = dir
        Thread.new do
            loop do
                begin
                    write(service, dir: dir)
                rescue StandardError => e
                    STDERR.puts "Heartbeat for #{service} failed: #{e.class}: #{e}"
                end
                sleep INTERVAL
            end
        end
    end

    def self.read_all(dir: DIR)
        Dir[File.join(dir, '*.json')].sort.map do |path|
            begin
                JSON.parse(File.read(path))
            rescue StandardError
                {'service' => File.basename(path, '.json'), 'time' => 0, 'unreadable' => true}
            end
        end
    end

    # service => problem description (German, for the status page and mails)
    def self.problems(statuses, now: Time.now)
        result = {}
        statuses.each do |s|
            age = now.to_i - s['time'].to_i
            if s['unreadable']
                result[s['service']] = 'Statusdatei nicht lesbar'
            elsif age > STALE_AFTER
                result[s['service']] = "keine Rückmeldung seit #{age / 60} Minuten"
            elsif !(s['dead_threads'] || []).empty?
                result[s['service']] = "Arbeits-Thread beendet: #{s['dead_threads'].join(', ')}"
            end
        end
        result
    end

    # Compares the problems of two checks: [new problems, resolved services].
    # A service counts once per problem – the description changes over time
    # ("for 6 minutes", "for 7 minutes"), the problem does not.
    def self.changes(before, now)
        [now.reject { |service, _| before.key?(service) }, before.keys - now.keys]
    end
end
