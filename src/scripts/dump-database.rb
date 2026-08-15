#!/usr/bin/env ruby

progress_mode = STDERR.tty? ? 'pretty' : 'plain'
system("cd ../.. && ./config.rb exec ruby env NEO4J_BOLT_PROGRESS=#{progress_mode} neo4j_bolt --host neo4j:7687 dump #{ARGV.map { |x| '\"' + x + '\"' }.join(' ') }&& cd src/scripts")
