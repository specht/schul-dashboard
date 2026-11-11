#!/usr/bin/env ruby
# Loads a dump into the running database (works from any directory):
#   ./load-dump.rb /pfad/zum/dump.txt [Optionen für neo4j_bolt load]
# A relative path is taken relative to the directory the script was started in.

abort 'Aufruf: ./load-dump.rb <dump.txt> [Optionen für neo4j_bolt load]' if ARGV.empty?
dump_path = File.expand_path(ARGV.first)
abort "#{dump_path} existiert nicht." unless File.file?(dump_path)

progress_mode = STDERR.tty? ? 'pretty' : 'plain'
Dir.chdir(File.expand_path('../..', __dir__))
container = IO.popen(['./config.rb', 'ps', '-q', 'ruby'], &:read).strip
abort 'Der ruby-Container läuft nicht.' if container.empty?
system('docker', 'exec', '-i', container, 'env', "NEO4J_BOLT_PROGRESS=#{progress_mode}",
       'neo4j_bolt', '--host', 'neo4j:7687', 'load', '/dev/stdin', *ARGV[1..], in: dump_path)
