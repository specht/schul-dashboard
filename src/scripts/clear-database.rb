#!/usr/bin/env ruby
# Deletes everything in the running database (works from any directory):
#   ./clear-database.rb --srsly

Dir.chdir(File.expand_path('../..', __dir__))
system('./config.rb', 'exec', '-T', 'ruby', 'neo4j_bolt', '--host', 'neo4j:7687', 'clear', *ARGV)
