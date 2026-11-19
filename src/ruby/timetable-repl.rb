#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 1
# external calendars (ical_import.rb): fetched this often, and right after
# someone saved or removed an address (/api/ical_import/<email>)
ICAL_IMPORT_INTERVAL = defined?(ICAL_IMPORT_INTERVAL_SECONDS) ? ICAL_IMPORT_INTERVAL_SECONDS : 15 * 60
DELAYED_UPDATE_TIME = DEVELOPMENT ? 0 : 0

class TimetableRepl < Sinatra::Base
    include Neo4jBolt

    configure do
        set :show_exceptions, false
    end

    def self.perform_update(which)
        begin
            debug ">>> Updating #{which}!"
            start_time = Time.now
            file_count = 0
            if which == 'all'
                file_count = @@timetable.update(nil)
            else
                file_count = @@timetable.update(Set.new([which]))
            end
            end_time = Time.now
            debug sprintf("<<< Finished updating #{which} in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        rescue StandardError => e
            STDERR.puts e
            STDERR.puts e.backtrace
        end
    end

    configure do
        @@timetable = Timetable.new
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
        # Write all timetables on start, in development like in production.
        # With real data this takes a few minutes; in development `rerun`
        # restarts this service (and the update) on every change in src/ruby.
        debug "Full timetable update on start" + (DEVELOPMENT ? " (runs again after every code change via rerun)" : '')
        @@queue << {:which => 'all'}
        @@worker_thread = Thread.new do
            future_queue = {}
            while true do
                entry = @@queue.pop
                if entry[:ping]
                    now = Time.now.to_i
                    keys = future_queue.keys
                    keys.each do |which|
                        if now - future_queue[which] > DELAYED_UPDATE_TIME
                            self.perform_update(which)
                            future_queue.delete(which)
                        end
                    end
                else
                    which = entry[:which]
                    if entry[:wait]
                        future_queue[which] ||= Time.now.to_i
                    else
                        self.perform_update(which)
                    end
                end
            end
        end
        # a worker thread that dies shows up on /dienste and in the watchdog's mail
        ServiceStatus.watch('worker', @@worker_thread)
        @@ping_thread = Thread.new do
            while true do
                @@queue << {:ping => true}
                sleep PING_TIME
            end
        end
        # External calendars in their own thread: a slow server never holds
        # up the timetable. Changed appointments queue an update of that
        # person's week files.
        @@ical_queue = Queue.new
        @@ical_queue << nil   # once at the start: all feeds
        @@ical_thread = Thread.new do
            while true do
                which = @@ical_queue.pop(timeout: ICAL_IMPORT_INTERVAL)
                begin
                    changed = IcalImport.refresh(which)
                    changed.each { |email| @@queue << {:which => "_#{email}"} }
                rescue StandardError => e
                    STDERR.puts "ical import: #{e}"
                end
            end
        end
        ServiceStatus.watch('ical_import', @@ical_thread)
        debug "REPL is ready."
    end
    
    get '/api/update/*' do
        data = request.path.sub('/api/update/', '')
        if data == 'all_messages'
            @@queue << {:which => :all_messages, :wait => true}
        elsif data =~ /^_event_.+/ || data =~ /^_poll_run_.+/ || data =~ /^_groups_.+/ || data =~ /^_angebote_.+/
            @@queue << {:which => data, :wait => true}
        else
            parts = data.split('/')
            parts.each do |which|
                @@queue << {:which => which, :wait => (parts[1] == 'wait')}
            end
        end
    end

    # someone saved or removed the address of their calendar: fetch it now
    get '/api/ical_import/*' do
        email = CGI.unescape(request.path.sub('/api/ical_import/', ''))
        @@ical_queue << email unless email.empty?
        'ok'
    end

    get '/api/update_messages' do
        @@queue << {:which => :all_messages, :wait => true}
    end

    run! if app_file == $0
end
