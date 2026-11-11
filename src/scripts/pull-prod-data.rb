#!/usr/bin/env ruby
# Copies the production data into the local development instance: the Neo4j
# database and DATA_PATH/{raw,gen,vplan}.
#
#   ./pull-prod-data.rb                     show what would happen (changes nothing)
#   ./pull-prod-data.rb --srsly             do it (database and files)
#   ./pull-prod-data.rb --srsly --db-only   only the database
#   ./pull-prod-data.rb --srsly --files-only
#   ./pull-prod-data.rb --restore-previous  bring back the database from before the last pull
#   --bwlimit=KBPS                          rsync bandwidth limit (default 20000, 0 = none)
#
# Needs in the local env.rb (development only):
#   PROD_SSH_HOST = 'name-from-ssh-config'
#   PROD_CHECKOUT_PATH = 'dashboard'        # optional, relative to the server's home
#
# The server is only read: the database is dumped online with neo4j_bolt (the
# same as dump-database.rb, no locks) and streamed through SSH, without a copy
# on the server's disk; files come via rsync. Both run with the lowest CPU and
# I/O priority. On the server nothing is written and nothing is restarted.
#
# Locally the development stack is stopped, the files are mirrored (files that
# don't exist on the server are deleted), the old database is moved to
# DATA_PATH/neo4j.previous and the dump is loaded into a fresh Neo4j.
#
# Deliberately not copied: DATA_PATH/mails (mail contents), INTERNAL_PATH
# (keys, internal documents) and INPUT_DATA_PATH (its own repository).

require 'fileutils'
require 'json'
require 'shellwords'
require 'tmpdir'
require 'zlib'

DATA_DIRS = %w(raw gen vplan)
SSH_OPTIONS = ['-o', 'BatchMode=yes']
# reserve on the local disk on top of the files and the new database
FREE_SPACE_RESERVE = 2 * 1024 ** 3

def fail!(message)
    STDERR.puts "\nAbgebrochen: #{message}"
    exit 1
end

def step(message)
    STDERR.puts "\n== #{message}"
end

def run!(*cmd, **opts)
    system(*cmd, **opts) || fail!("Befehl fehlgeschlagen: #{cmd.join(' ')}")
end

def human(bytes)
    units = %w(B KB MB GB TB)
    i = 0
    value = bytes.to_f
    while value >= 1024 && i < units.size - 1
        value /= 1024
        i += 1
    end
    format(i == 0 ? '%d %s' : '%.1f %s', value, units[i])
end

args = ARGV.dup
srsly = !!args.delete('--srsly')
db_only = !!args.delete('--db-only')
files_only = !!args.delete('--files-only')
restore_previous = !!args.delete('--restore-previous')
bwlimit = 20000
args.reject! do |a|
    if a =~ /\A--bwlimit=(\d+)\z/
        bwlimit = $1.to_i
        true
    end
end
fail!("Unbekannte Argumente: #{args.join(' ')}") unless args.empty?
fail!('--db-only und --files-only schließen sich aus.') if db_only && files_only
do_db = !files_only
do_files = !db_only

Dir.chdir(File.expand_path('../..', __dir__))

# --- local safety checks: only ever write into a development instance ------

fail!('DASHBOARD_ENV ist gesetzt – das Skript arbeitet nur mit der Entwicklungsinstanz (env.rb).') if ENV['DASHBOARD_ENV']
fail!('env.rb fehlt.') unless File.exist?('env.rb')
require './env.rb'
fail!('env.rb ist keine Entwicklungskonfiguration (DEVELOPMENT ist nicht true).') unless DEVELOPMENT == true

local_data_path = File.expand_path(DATA_PATH)
fail!("DATA_PATH #{local_data_path} existiert nicht.") unless File.directory?(local_data_path)
local_neo4j = File.join(local_data_path, 'neo4j')
local_neo4j_previous = local_neo4j + '.previous'

# ./config.rb always exits with 0, whatever docker compose returns – so
# everything below checks the result itself instead of the exit status.
def compose(*args)
    system('./config.rb', *args)
end

def running_containers(service = nil)
    cmd = ['docker', 'ps', '-q', '--filter', "label=com.docker.compose.project=#{PROJECT_NAME}"]
    cmd += ['--filter', "label=com.docker.compose.service=#{service}"] if service
    IO.popen(cmd, &:read).split
end

def stop_dev_stack!
    compose('stop')
    fail!("Die Entwicklungsinstanz läuft noch (#{running_containers.size} Container).") unless running_containers.empty?
end

def start_dev_stack!
    compose('up', '-d')
    STDERR.puts 'Warnung: der ruby-Container läuft nicht – bitte ./config.rb logs ruby prüfen.' if running_containers('ruby').empty?
end

# runs a query in the local Neo4j, returns the output or nil
def local_cypher(query)
    container = running_containers('neo4j').first
    return nil unless container
    out = IO.popen(['docker', 'exec', container, 'cypher-shell', '-a', 'bolt://localhost:7687',
                    '--format', 'plain', query], err: File::NULL, &:read)
    $?.success? ? out : nil
end

def local_count(query)
    out = local_cypher(query)
    out && out.lines.last.to_s.strip =~ /\A\d+\z/ ? out.lines.last.to_i : nil
end

def wait_for_neo4j!
    STDERR.print 'Warte auf Neo4j'
    90.times do
        if local_count('MATCH (n) RETURN count(n);')
            STDERR.puts ' ok'
            return
        end
        STDERR.print '.'
        sleep 2
    end
    fail!('Neo4j ist nicht hochgekommen.')
end

def restore_previous_database!(neo4j, previous)
    fail!("Es gibt keine vorherige Datenbank (#{previous}).") unless File.directory?(previous)
    stop_dev_stack!
    FileUtils.rm_rf(neo4j)
    File.rename(previous, neo4j)
    start_dev_stack!
end

if restore_previous
    step "Stelle die Datenbank von vor dem letzten Abruf wieder her (#{local_neo4j_previous})"
    unless srsly
        STDERR.puts "Nichts geändert. Mit --srsly wird die aktuelle Datenbank durch #{local_neo4j_previous} ersetzt."
        exit 0
    end
    restore_previous_database!(local_neo4j, local_neo4j_previous)
    STDERR.puts 'Fertig.'
    exit 0
end

fail!("PROD_SSH_HOST ist in env.rb nicht gesetzt (Name des Servers aus der SSH-Konfiguration).") unless defined?(PROD_SSH_HOST) && PROD_SSH_HOST.to_s.strip != ''
prod_host = PROD_SSH_HOST
prod_checkout = defined?(PROD_CHECKOUT_PATH) ? PROD_CHECKOUT_PATH : 'dashboard'

def ssh_capture(host, command)
    out = IO.popen(['ssh', *SSH_OPTIONS, host, command], &:read)
    fail!("SSH-Befehl auf #{host} fehlgeschlagen.") unless $?.success?
    out
end

# --- read the server's configuration (read-only) ---------------------------

step "Lese die Konfiguration auf #{prod_host}"
info_code = 'load "./env.rb"; require "json"; puts JSON.generate(project: PROJECT_NAME, development: DEVELOPMENT, data_path: File.expand_path(DATA_PATH))'
prod = JSON.parse(ssh_capture(prod_host, "cd #{Shellwords.escape(prod_checkout)} && ruby -e #{Shellwords.escape(info_code)}").lines.last)
fail!('Der Server ist als Entwicklungsinstanz konfiguriert – falscher Host?') if prod['development']
fail!("Unerwarteter DATA_PATH auf dem Server: #{prod['data_path'].inspect}") unless prod['data_path'].to_s.start_with?('/') && prod['data_path'].size > 1
container_filter = "--filter label=com.docker.compose.project=#{Shellwords.escape(prod['project'])} --filter label=com.docker.compose.service=ruby"
prod_container = ssh_capture(prod_host, "docker ps -q #{container_filter}").strip
fail!('Auf dem Server läuft kein ruby-Container.') if do_db && prod_container.empty?
STDERR.puts "Projekt #{prod['project']}, DATA_PATH #{prod['data_path']}"

def rsync_command(host, remote_dir, local_dir, bwlimit, dry_run:)
    cmd = ['rsync', '-rlt', '--delete',
           '-e', (['ssh'] + SSH_OPTIONS).join(' '),
           '--rsync-path=nice -n 19 ionice -c3 rsync']
    cmd << "--bwlimit=#{bwlimit}" if bwlimit > 0
    cmd += dry_run ? ['--dry-run', '--stats'] : ['--info=progress2']
    cmd + ["#{host}:#{remote_dir}/", "#{local_dir}/"]
end

# --- plan ------------------------------------------------------------------

# Space: what the local disk holds afterwards minus what it holds now, in
# disk blocks (gen has hundreds of thousands of small files). Files that are
# only replaced or deleted don't need extra space, so the rsync transfer size
# would overestimate a lot. The directories are synced one after another,
# the database comes last – the peak counts.
def local_usage(path)
    File.exist?(path) ? IO.popen(['du', '-s', '--block-size=1', path], err: File::NULL, &:read).to_i : 0
end

def file_device(path)
    path = File.dirname(path) until File.exist?(path)
    File.stat(path).dev
end

needed = 0
growth = 0
if do_files
    step 'Prüfe die Dateien (Probelauf von rsync)'
    remote_usage = {}
    du_command = "cd #{Shellwords.escape(prod['data_path'])} && for d in #{DATA_DIRS.join(' ')}; do " \
                 "[ -d \"$d\" ] && nice -n 19 ionice -c3 du -s --block-size=1 \"$d\"; done; true"
    ssh_capture(prod_host, du_command).each_line do |line|
        size, dir = line.split("\t", 2)
        remote_usage[dir.to_s.strip] = size.to_i
    end
    DATA_DIRS.each do |dir|
        remote_dir = File.join(prod['data_path'], dir)
        local_dir = File.join(local_data_path, dir)
        stats = IO.popen(rsync_command(prod_host, remote_dir, local_dir, 0, dry_run: true), &:read)
        fail!("rsync-Probelauf für #{dir} fehlgeschlagen.") unless $?.success?
        transfer = stats[/Total transferred file size: ([\d,.]+)/, 1].to_s.delete(',.').to_i
        deleted = stats[/Number of deleted files: ([\d,.]+)/, 1].to_s.delete(',.').to_i
        count = stats[/Number of regular files transferred: ([\d,.]+)/, 1].to_s.delete(',.').to_i
        local = local_usage(local_dir)
        # without a size from the server: assume every transferred byte is new
        delta = remote_usage.key?(dir) ? remote_usage[dir] - local : transfer
        growth += delta
        needed = [needed, growth].max
        STDERR.puts format('%-6s %8d Dateien zu übertragen (%s), %d lokal zu löschen; Server %s, lokal %s, %s %s',
                           dir, count, human(transfer), deleted, human(remote_usage[dir] || 0), human(local),
                           delta >= 0 ? 'Zuwachs' : 'frei werden', human(delta.abs))
    end
end
if do_db
    # neo4j.previous is deleted, neo4j becomes neo4j.previous, the new
    # database is about as large as the current one
    db_size = [local_usage(local_neo4j), 1024 ** 3].max
    db_growth = db_size - local_usage(local_neo4j_previous)
    needed = [needed, growth + db_growth].max
    # the dump is downloaded into a temporary directory (gzip, then unpacked)
    if file_device(Dir.tmpdir) == file_device(local_data_path)
        needed = [needed, growth + db_size].max
    else
        tmp_free = IO.popen(['df', '-Pk', Dir.tmpdir], &:read).lines.last.split[3].to_i * 1024
        STDERR.puts "Temporärer Dump in #{Dir.tmpdir}: frei #{human(tmp_free)}"
        fail!("Nicht genug freier Speicherplatz in #{Dir.tmpdir} für den Dump.") if db_size > tmp_free
    end
end
free = IO.popen(['df', '-Pk', local_data_path], &:read).lines.last.split[3].to_i * 1024
STDERR.puts "\nPlatz: benötigt etwa #{human([needed, 0].max)} + #{human(FREE_SPACE_RESERVE)} Reserve, frei #{human(free)}"
fail!('Nicht genug freier Speicherplatz.') if needed + FREE_SPACE_RESERVE > free

step 'Ablauf'
STDERR.puts "- Datenbank auf dem Server lesend exportieren und herunterladen" if do_db
STDERR.puts "- Entwicklungsinstanz anhalten (./config.rb stop)"
STDERR.puts "- #{DATA_DIRS.join(', ')} spiegeln (lokal fehlende Dateien werden gelöscht)" if do_files
if do_db
    STDERR.puts "- #{local_neo4j_previous} löschen" if File.directory?(local_neo4j_previous)
    STDERR.puts "- #{local_neo4j} → #{local_neo4j_previous}, Dump in eine leere Neo4j laden"
end
STDERR.puts "- Entwicklungsinstanz starten (./config.rb up -d)"

unless srsly
    STDERR.puts "\nNichts geändert. Mit --srsly ausführen."
    exit 0
end

# --- do it -----------------------------------------------------------------

Dir.mktmpdir('pull-prod-data-') do |tmp|
    FileUtils.chmod(0700, tmp)
    dump_path = File.join(tmp, 'dump.txt')

    if do_db
        step 'Exportiere die Datenbank auf dem Server'
        remote_dump = "set -o pipefail; docker exec -e NEO4J_BOLT_PROGRESS=plain #{Shellwords.escape(prod_container)} " \
                      "nice -n 19 neo4j_bolt --host neo4j:7687 dump | nice -n 19 gzip -1"
        gz_path = dump_path + '.gz'
        run!('ssh', *SSH_OPTIONS, prod_host, "bash -c #{Shellwords.escape(remote_dump)}", out: gz_path)
        nodes = 0
        relationships = 0
        File.open(dump_path, 'w', 0600) do |out|
            Zlib::GzipReader.open(gz_path) do |gz|
                gz.each_line do |line|
                    nodes += 1 if line.start_with?('n ')
                    relationships += 1 if line.start_with?('r ')
                    out.write(line)
                end
            end
        end
        File.delete(gz_path)
        fail!('Der Dump enthält keine Knoten.') if nodes == 0
        STDERR.puts "Dump: #{nodes} Knoten, #{relationships} Beziehungen"
    end

    step 'Halte die Entwicklungsinstanz an'
    stop_dev_stack!

    if do_files
        DATA_DIRS.each do |dir|
            step "Spiegele #{dir}"
            run!(*rsync_command(prod_host, File.join(prod['data_path'], dir), File.join(local_data_path, dir), bwlimit, dry_run: false))
        end
    end

    if do_db
        step 'Lade die Datenbank'
        if File.directory?(local_neo4j_previous)
            STDERR.puts "Lösche #{local_neo4j_previous}"
            FileUtils.rm_rf(local_neo4j_previous)
        end
        File.rename(local_neo4j, local_neo4j_previous) if File.directory?(local_neo4j)
        FileUtils.mkdir_p(local_neo4j)
        loaded = false
        begin
            compose('up', '-d', 'neo4j')
            wait_for_neo4j!
            system('./config.rb', 'run', '--rm', '--no-deps', '-T', '-e', 'NEO4J_BOLT_PROGRESS=plain',
                   '--entrypoint', 'neo4j_bolt --host neo4j:7687 load /dev/stdin', 'ruby',
                   in: dump_path)
            got_nodes = local_count('MATCH (n) RETURN count(n);')
            got_relationships = local_count('MATCH ()-[r]->() RETURN count(r);')
            STDERR.puts "Geladen: #{got_nodes.inspect} Knoten, #{got_relationships.inspect} Beziehungen"
            loaded = got_nodes == nodes && got_relationships == relationships
        ensure
            unless loaded
                STDERR.puts "\nLaden fehlgeschlagen – stelle die vorherige Datenbank wieder her."
                if File.directory?(local_neo4j_previous)
                    restore_previous_database!(local_neo4j, local_neo4j_previous)
                else
                    start_dev_stack!
                end
            end
        end
        fail!('Die Datenbank konnte nicht geladen werden.') unless loaded
    end
end

step 'Starte die Entwicklungsinstanz'
start_dev_stack!
STDERR.puts "\nFertig."
STDERR.puts "Vorherige Datenbank: #{local_neo4j_previous} (zurück mit --restore-previous --srsly)" if do_db && File.directory?(local_neo4j_previous)
