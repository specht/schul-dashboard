#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require './timetable.rb'
require 'json'
require 'zlib'
require 'fileutils'
require 'thread'

PING_TIME = DEVELOPMENT ? 1 : 60

class ImageBotRepl < Sinatra::Base
    configure do
        set :show_exceptions, false
    end

    def self.perform_update()
        STDERR.puts ">>> Refreshing uploaded images!"
        file_count = 0
        start_time = Time.now
        # convert uploaded images
        file_count += ImageConverter.refresh_uploaded_images('/raw/uploads/images', '/gen/i', GEN_IMAGE_WIDTHS)
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing uploaded images in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59

        STDERR.puts ">>> Refreshing background images!"
        file_count = 0
        start_time = Time.now
        # convert background images
        file_count += ImageConverter.refresh_background_images('/gen/bg')
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing background images in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59
    end

    configure do
        begin
            if @@worker_thread
                Thread.kill(@@worker_thread)
            end
        rescue
        end
        @@queue = Queue.new
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
                    self.perform_update()
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
        STDERR.puts "REPL is ready."
    end

    get '/api/update_all' do
        @@queue << {:which => :all}
    end

    run! if app_file == $0
end
