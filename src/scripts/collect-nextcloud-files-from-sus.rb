#!/usr/bin/env ruby

require 'open3'

Open3.popen2("sh -c '(cd ../../ && ./config.rb exec ruby2 ruby collect-nextcloud-files-from-sus.rb #{ARGV.join(' ')})'") do |fin, fout, wait|
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
    if failed
        STDERR.puts error_lines.join("\n")
        exit(1)
    else
        puts lines.join("\n")
    end
end
