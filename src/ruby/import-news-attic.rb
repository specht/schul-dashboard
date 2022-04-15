#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
require './main.rb'

class ImportNewsAttic
    include QtsNeo4j
    
    def run(base_path)
        STDERR.puts "Loading news attic from #{base_path}..."
        Dir[File.join(base_path, '*')].sort.each do |path|
            ts = File.basename(path)[0, 19]
            ts = "#{ts[0, 4]}-#{ts[5, 2]}-#{ts[8, 2]} #{ts[11, 2]}:#{ts[14, 2]}:#{ts[17, 2]}"
            nid = DateTime.parse(ts).to_time.to_i
            id = nid.to_s(36)
            STDERR.puts "#{nid} => #{id} => #{path}"
            entry = nil
            if path[-5, 5] == '.json'
                entry = JSON.parse(File.read(path))
                entry[:timestamp] = nid
            elsif path[-3, 3] == '.md'
                lines = File.read(path).split("\n")
                title = lines.shift
                entry = {
                    :timestamp => nid,
                    :title => title,
                    :date => ts,
                    :content => lines.join("\n").strip
                }
            end
            entry[:sticky] = false
            entry[:published] = true
            raise 'oops' if entry.nil?
            neo4j_query(<<~END_OF_QUERY, {:timestamp => nid, :entry => entry})
                MERGE (n:NewsEntry {timestamp: $timestamp})
                SET n = $entry;
            END_OF_QUERY
        end
    end
end

load = ImportNewsAttic.new
load.run(ARGV.first)
