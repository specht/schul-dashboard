#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'zlib'
require 'fileutils'

class Script
    include QtsNeo4j
    
    def initialize
        @ocs = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                             username: NEXTCLOUD_USER, 
                             password: NEXTCLOUD_PASSWORD)
        @known_dirs = Set.new()
    end
    
    def mk_path(path)
        parts = path.gsub(' ', '%20').split('/')
        parts.each.with_index do |part, i|
            partial_path = parts[0, i + 1].join('/')
            unless @known_dirs.include?(partial_path)
                result = @ocs.webdav.directory.find(partial_path)
                unless result.is_a? Nextcloud::Models::Directory
                    STDERR.puts "mkdir #{path}"
                    result = @ocs.webdav.directory.create(partial_path)
                    unless result.is_a?(Hash) && result[:status] == 'ok'
                        raise "Unable to create dir: #{partial_path}"
                    end
                end
                @known_dirs << partial_path
            end
        end
    end
    
    def run
        @@user_info = Main.class_variable_get(:@@user_info)
        @@faecher = Main.class_variable_get(:@@faecher)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
        @@lessons[:lesson_keys].keys.sort.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            next if (Set.new(lesson_info[:klassen]) & Set.new(@@klassen_order)).empty?
            folder_name = "#{lesson_key}"
            einsammel_path = "Auto-Einsammelordner (von SuS an mich)"
            rueckgabe_path = "Auto-Rückgabeordner (von mir an SuS)"
            STDERR.puts sprintf('%3d %-20s %-10s %s', (@@schueler_for_lesson[lesson_key] || []).size, lesson_key, lesson_info[:lehrer].join(', '), lesson_info[:klassen].join(', '))
            ['Ausgabeordner', einsammel_path, rueckgabe_path].each do |x|
                mk_path("Unterricht/#{folder_name}/#{x}")
            end
            (@@schueler_for_lesson[lesson_key] || []).each do |email|
                name = @@user_info[email][:display_name]
                ['Einsammelordner', 'Einsammelordner/Eingesammelt', 'Rückgabeordner'].each do |x|
                    mk_path("Unterricht/#{folder_name}/SuS/#{name}/#{x}")
                end
            end
        end
    end
end

script = Script.new
script.run
