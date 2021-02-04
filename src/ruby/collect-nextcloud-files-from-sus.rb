#!/usr/bin/env ruby

at_exit do
    unless $!.nil?
        puts "__FAIL__"
    end
end

require './main.rb'

DRY_RUN = !ARGV.include?('--srsly')

if DRY_RUN
    STDERR.puts "DRY RUN (not making any changes to the filesystem)"
    STDERR.puts "To make changes to the filesystem, specify --srsly on the command line."
end

unless NEXTCLOUD_DASHBOARD_DATA_DIRECTORY[0] == '/'
    raise "Fehler: NEXTCLOUD_DASHBOARD_DATA_DIRECTORY muss ein absoluter Pfad sein.\nNEXTCLOUD_DASHBOARD_DATA_DIRECTORY = #{NEXTCLOUD_DASHBOARD_DATA_DIRECTORY}"
end

class Script
    def emit(s)
        puts "__RUN__ #{s}"
    end
    
    def run
        script = File.read('collect-nextcloud-files-from-sus.script.rb')
        script = script.gsub('__NEXTCLOUD_DASHBOARD_DATA_DIRECTORY__', "\"#{NEXTCLOUD_DASHBOARD_DATA_DIRECTORY}\"")
        script = script.gsub('__DRY_RUN__', DRY_RUN.to_s)
        script = script.gsub('__NEXTCLOUD_WAIT_SECONDS__', NEXTCLOUD_WAIT_SECONDS.to_s)
        script.split("\n").each do |line|
            emit line
        end
        emit "# Hinweis: Die oben stehenden Befehle wurden noch nicht ausgeführt."
        emit "# Falls die Nextcloud z. B. in einem Docker-Container läuft, können sie"
        emit "# z. B. so ausgeführt werden:"
        emit "# $ ./#{File.basename(__FILE__)} | docker exec -i schuldashboarddev_nextcloud_1 ruby -"
    end
end
    
script = Script.new
script.run
