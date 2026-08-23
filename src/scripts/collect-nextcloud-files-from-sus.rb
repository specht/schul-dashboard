#!/usr/bin/env ruby

require 'open3'

repository_root = File.expand_path('../..', __dir__)
command = [
    './config.rb',
    'exec',
    '-T',
    '-e',
    'DASHBOARD_SERVICE=script',
    'ruby',
    'ruby',
    'collect-nextcloud-files-from-sus.rb',
    *ARGV
]

Open3.popen2(*command, chdir: repository_root) do |fin, fout, wait|
    fin.close
    lines = []
    error_lines = []
    failed = false
    fout.each_line do |line|
        if line[0, 8] == '__RUN__ '
            line = line.gsub('__RUN__ ', '')
            lines << line.gsub("\r", '').rstrip
        elsif line[0, 8] == '__FAIL__'
            failed = true
        else
            error_lines << "# #{line.rstrip}"
        end
    end
    failed = true unless wait.value.success?
    if failed
        STDERR.puts error_lines.join("\n")
        exit(1)
    else
        puts lines.join("\n")
    end
end
