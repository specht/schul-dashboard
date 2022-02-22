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
        paths = Dir['/raw/uploads/images/*'].sort
        paths.each do |path|
            tag = File.basename(path).split('.').first
            last_jpg_path = path
            (GEN_IMAGE_WIDTHS.reverse + [:p]).each do |width|
                jpg_path = File.join("/gen/i/#{tag}-#{width}.jpg")
                unless File.exists?(jpg_path)
                    STDERR.puts jpg_path
                    if width == :p
                        system("convert -auto-orient -colorspace RGB \"#{last_jpg_path}\" -blur 0x8 -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
                    else
                        system("convert -auto-orient -colorspace RGB \"#{last_jpg_path}\" -resize #{width}x\\> -quality 85 -sampling-factor 4:2:0 -strip \"#{jpg_path}\"")
                    end
                    file_count += 1
                end
                webp_path = File.join("/gen/i/#{tag}-#{width}.webp")
                unless File.exists?(webp_path)
                    STDERR.puts webp_path
                    system("cwebp -quiet \"#{jpg_path}\" -q #{webp_path.include?('-b') ? 100 : 85} -o \"#{webp_path}\"")
                    file_count += 1
                end
                last_jpg_path = jpg_path
            end
        end
        end_time = Time.now
        STDERR.puts sprintf("<<< Finished refreshing uploaded images in %1.2f seconds, wrote #{file_count} files.", (end_time - start_time).to_f)
        STDERR.puts '-' * 59

        STDERR.puts ">>> Refreshing background images!"
        file_count = 0
        start_time = Time.now
        # convert background images
        paths = Dir['/gen/bg/*.svg'].sort
        paths.each do |svg_path|
            tag = File.basename(svg_path).split('.').first
            png_path = "/gen/bg/#{tag}.png"
            jpg_path = "/gen/bg/#{tag}.jpg"
            jpg_512_path = "/gen/bg/#{tag}-512.jpg"
            unless File.exists?(png_path)
                STDERR.puts "Creating #{png_path}..."
                system("inkscape --export-filename=#{png_path} #{svg_path}")
                file_count += 1
            end
            unless File.exists?(jpg_path)
                STDERR.puts "Creating #{jpg_path}..."
                system("convert #{png_path} #{jpg_path}")
                file_count += 1
            end
            unless File.exists?(jpg_512_path)
                STDERR.puts "Creating #{jpg_512_path}..."
                system("convert #{jpg_path} -resize 512x #{jpg_512_path}")
                file_count += 1
            end
        end
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
