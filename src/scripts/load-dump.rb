#!/usr/bin/env ruby

system("cd ../.. && cat \"#{File.expand_path(ARGV.first)}\" | docker exec -i $(./config.rb ps -q ruby) neo4j_bolt --host neo4j:7687 load /dev/stdin #{(ARGV[1, ARGV.size - 1] || []).join(' ')} && cd src/scripts")
