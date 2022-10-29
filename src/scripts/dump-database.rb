#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby neo4j_bolt --host neo4j:7687 dump #{ARGV.map { |x| '"' + x + '"' }.join(' ') }&& cd src/scripts")
