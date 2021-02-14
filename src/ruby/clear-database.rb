#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
require './main.rb'

class ClearDatabase
    include QtsNeo4j
    
    def run
        if ARGV.include?('--srsly')
            transaction do
                neo4j_query('MATCH (n) DETACH DELETE n;')
            end
        else
            STDERR.puts "Not doing anything unless you provide --srsly as an argument."
        end
    end
end

script = ClearDatabase.new
script.run
