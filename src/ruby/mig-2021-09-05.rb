#!/usr/bin/env ruby
# SKIP_COLLECT_DATA = true
require './main.rb'
require './parser.rb'
require 'digest/sha2'
require 'yaml'
require 'http'

SRSLY = ARGV.first == '--srsly'

unless SRSLY
    STDERR.puts "Not making any changes unless you specify --srsly"
end

class Script
    include Neo4jBolt
    def run
        @@user_info = Main.class_variable_get(:@@user_info)
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        @@lesson_key_back_tr = Main.class_variable_get(:@@lesson_key_back_tr)
        rev = {}
        @@lesson_key_back_tr.each_pair do |a, b|
            rev[b] ||= Set.new()
            rev[b] << a
        end
        rev.keys.each do |k|
            rev[k] = rev[k].to_a.sort
        end
        rev.keys.sort.each do |k|
            next if rev[k].size > 1
            # next if DEVELOPMENT && k != 'Ma~62a'
            l = rev[k].first
            STDERR.puts "[#{k}] ==> [#{l}]"
            if SRSLY
                neo4j_query("MATCH (li:Lesson {key: $new_key}) DETACH DELETE li;", {:new_key => l})
                neo4j_query("MATCH (li:Lesson {key: $old_key}) SET li.key = $new_key;", {:old_key => k, :new_key => l})
            end
        end
    end
end

script = Script.new
script.run
