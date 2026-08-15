#!/usr/bin/env ruby

progress_mode = STDERR.tty? ? 'pretty' : 'plain'
system("cd ../.. && cat \"#{File.expand_path(ARGV.first)}\" | docker exec -i $(./config.rb ps -q ruby) env NEO4J_BOLT_PROGRESS=#{progress_mode} neo4j_bolt --host neo4j:7687 load /dev/stdin #{(ARGV[1, ARGV.size - 1] || []).join(' ')} && cd src/scripts")
