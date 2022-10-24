#!/usr/bin/env ruby

require './neo4j.rb'
require 'json'
require 'yaml'

class DumpDatabase
    include QtsNeo4j

    def run
        transaction do
            neo4j_query("MATCH (n) RETURN id(n) as id, labels(n) as labels, n as n;") do |result|
                node = {
                    :id => result['id'],
                    :labels => result['labels'],
                    :properties => result['n']
                }
                puts "n #{node.to_json}"
            end
        end
        transaction do
            neo4j_query("MATCH ()-[r]->() RETURN type(r) as type, id(r) as id, id(startnode(r)) as from, id(endnode(r)) as to, r as r;") do |result|
                relationship = {
                    :id => result['id'],
                    :type => result['type'],
                    :from => result['from'],
                    :to => result['to'],
                    :properties => result['r']
                }
                puts "r #{relationship.to_json}"
            end
        end
    end
end

dump = DumpDatabase.new
dump.run

# MATCH (n) RETURN id(n) as id, labels(n) as labels, n as n;
# MATCH ()-[r]->() RETURN type(r) as type, id(r) as id, id(startnode(r)) as from, id(endnode(r)) as to, r as r;
