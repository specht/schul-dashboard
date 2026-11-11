#!/usr/bin/env ruby
# Writes a dump of the running database to stdout (works from any directory):
#   ./dump-database.rb > /pfad/ausserhalb/des/repos/dump.txt
# Further arguments go to `neo4j_bolt dump`. -T: no pseudo-terminal, so the
# progress display (stderr) never ends up in the dump.

progress_mode = STDERR.tty? ? 'pretty' : 'plain'
Dir.chdir(File.expand_path('../..', __dir__))
system('./config.rb', 'exec', '-T', 'ruby', 'env', "NEO4J_BOLT_PROGRESS=#{progress_mode}",
       'neo4j_bolt', '--host', 'neo4j:7687', 'dump', *ARGV)
