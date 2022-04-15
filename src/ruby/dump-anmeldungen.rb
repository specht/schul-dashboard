#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
require './main.rb'

class DumpDatabase
    include QtsNeo4j
    
    def run
        transaction do
            rows = neo4j_query(<<~END_OF_QUERY, :mode => ARGV.first).map { |x| x['n'] }
                MATCH (n:PublicEventPerson {mode: $mode})-[:SIGNED_UP_FOR]->(e:PublicEvent {name: "Info-Abend für Viertklässler-Eltern"})
                RETURN n
                ORDER BY n.timestamp;
            END_OF_QUERY
            rows.each do |row|
                puts "#{row[:name]} <#{row[:email]}>"
            end
        end
    end
end

dump = DumpDatabase.new
dump.run
