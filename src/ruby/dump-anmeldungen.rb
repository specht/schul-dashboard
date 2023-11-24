#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
require './main.rb'

class DumpDatabase
    include Neo4jBolt
    
    def run
        puts "Track\tTimestamp\tName\tE-Mail"
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (n:PublicEventPerson)-[:SIGNED_UP_FOR]->(e:PublicEventTrack)
            RETURN n, e
            ORDER BY e.track, n.timestamp;
        END_OF_QUERY
            puts "#{row['e'][:track]}\t#{row['n'][:timestamp]}\t#{row['n'][:name]}\t#{row['n'][:email]}"
        end
    end
end

dump = DumpDatabase.new
dump.run
