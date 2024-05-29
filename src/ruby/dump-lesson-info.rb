#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'nextcloud'
require 'cgi'
require 'yaml'

class Script
    include Neo4jBolt

    def initialize
    end

    def run
        @@user_info = Main.class_variable_get(:@@user_info)
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        @@klassen_order = Main.class_variable_get(:@@klassen_order)
        @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
        @@lessons = Main.class_variable_get(:@@lessons)
        @@faecher = Main.class_variable_get(:@@faecher)
        @@shorthands = Main.class_variable_get(:@@shorthands)
        @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
        @@lessons_for_shorthand = Main.class_variable_get(:@@lessons_for_shorthand)

        lesson_info_archives_for_shorthand = {}

        @@lessons[:lesson_keys].keys.sort.each do |lesson_key|
            shorthands = @@lessons[:lesson_keys][lesson_key][:lehrer]
            lesson_info = neo4j_query(<<~END_OF_QUERY, {:lesson_key => lesson_key}).map { |x| x['i'] }
                MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: $lesson_key})
                RETURN i
                ORDER BY i.offset;
            END_OF_QUERY
            unless lesson_info.empty? || shorthands.empty?
                shorthands.each do |shorthand|
                    lesson_info_archives_for_shorthand[shorthand] ||= []
                    lesson_info_archives_for_shorthand[shorthand] << lesson_key
                end
                path = "/gen/lesson-info-archive/#{lesson_key}.json"
                FileUtils.mkpath(File.dirname(path))
                File.open(path, 'w') do |f|
                    f.puts lesson_info.to_json
                end
            end
        end
        File.open('/gen/lesson-info-archive/directory.json', 'w') do |f|
            f.puts lesson_info_archives_for_shorthand.to_json
        end
    end
end

script = Script.new
script.run
