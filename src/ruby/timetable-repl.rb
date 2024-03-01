#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 1
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
        @@queue << {:which => 'all'} unless DEVELOPMENT
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
        @@ping_thread = Thread.new do
            while true do
                @@queue << {:ping => true}
                sleep PING_TIME
            end
        end
        debug "REPL is ready."
    end
    
    get '/api/update/*' do
        data = request.env['REQUEST_PATH'].sub('/api/update/', '')
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

    get '/api/update_messages' do
        @@queue << {:which => :all_messages, :wait => true}
    end

    run! if app_file == $0
end
