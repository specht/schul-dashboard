#!/usr/bin/env ruby
require 'neo4j_bolt'
include Neo4jBolt

Neo4jBolt.bolt_host = 'neo4j'
Neo4jBolt.bolt_port = 7687

dump_database do |line|
    puts line
end
