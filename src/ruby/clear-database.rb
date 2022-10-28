#!/usr/bin/env ruby
require 'neo4j_bolt'

class ClearDatabase
    include Neo4jBolt

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
