#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby neo4j_bolt --host neo4j:7687 clear #{ARGV.join(' ')} && cd src/scripts")
