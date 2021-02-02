#!/usr/bin/env ruby
require './main.rb'

class DumpDatabase
    include QtsNeo4j
    
    def run
        transaction do
            neo4j_query("MATCH (n) RETURN id(n) as id, labels(n) as labels, n as n;").each do |result|
                node = {
                    :id => result['id'],
                    :labels => result['labels'],
                    :properties => result['n'].props
                }
                puts "n #{node.to_json}"
            end
            neo4j_query("MATCH ()-[r]->() RETURN type(r) as type, id(r) as id, id(startnode(r)) as from, id(endnode(r)) as to, r as r;").each do |result|
                relationship = {
                    :id => result['id'],
                    :type => result['type'],
                    :from => result['from'],
                    :to => result['to'],
                    :properties => result['r'].props
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
