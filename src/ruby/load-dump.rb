#!/usr/bin/env ruby
require './main.rb'

class LoadDump
    include QtsNeo4j
    
    def run(path)
        unless ARGV.include?('--append-srsly')
            transaction do
                node_count = neo4j_query_expect_one('MATCH (n) RETURN COUNT(n) as count;')['count']
                unless node_count == 0
                    STDERR.puts "Error: There are nodes in this database, exiting now."
                    exit(1)
                end
            end
        end
        n_count = 0
        r_count = 0
        node_tr = {}
        File.open(path) do |f|
            while true do
                transaction do
                    t = Time.now
                    f.each_line do |line|
                        line.strip!
                        next if line.empty?
                        if line[0] == 'n'
                            line = line[2, line.size - 2]
                            node = JSON.parse(line)
                            node_id = neo4j_query_expect_one("CREATE (n:#{node['labels'].join(':')} {props}) RETURN id(n) as id", :props => node['properties'])
                            node_tr[node['id']] = node_id['id']
                            n_count += 1
                        elsif line[0] == 'r'
                            line = line[2, line.size - 2]
                            relationship = JSON.parse(line)
                            neo4j_query_expect_one("MATCH (from), (to) WHERE ID(from) = #{node_tr[relationship['from']]} AND ID(to) = #{node_tr[relationship['to']]} CREATE (from)-[r:#{relationship['type']} {props}]->(to) RETURN r;", :props => relationship['properties'])
                            r_count += 1
                        else
                            STDERR.puts "Invalid entry: #{line}"
                            exit(1)
                        end
                        STDERR.print "\rLoaded #{n_count} nodes, #{r_count} relationships..."
                        break if Time.now - t > 3
                    end
                end
                break if f.eof?
            end
        end
        STDERR.puts
    end
end

load = LoadDump.new
load.run(ARGV.first)
