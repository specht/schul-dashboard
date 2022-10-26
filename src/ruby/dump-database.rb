#!/usr/bin/env ruby

require './neo4j.rb'
require 'json'
require 'yaml'

class DumpDatabase
    include QtsNeo4j

    def run
        tr_id = {}
        id = 0
        neo4j_query("MATCH (n) RETURN n;") do |row|
            tr_id[row['n'].id] = id
            node = {
                :id => id,
                :labels => row['n'].labels,
                :properties => row['n']
            }
            puts "n #{node.to_json}"
            id += 1
        end
        neo4j_query("MATCH ()-[r]->() RETURN r;") do |row|
            rel = {
                :from => tr_id[row['r'].start_node_id],
                :to => tr_id[row['r'].end_node_id],
                :type => row['r'].type,
                :properties => row['r']
            }
            puts "r #{rel.to_json}"
        end
    end
end

dump = DumpDatabase.new
dump.run
