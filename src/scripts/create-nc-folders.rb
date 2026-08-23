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
    'create-nc-folders.rb'
]

Open3.popen2(*command, chdir: repository_root) do |fin, fout, wait|
    fin.close
    fout.each_line do |line|
        if line[0, 8] == '__RUN__ '
            line = line.gsub('__RUN__ ', '')
            puts line.gsub("\r", '')
        end
    end
    exit(1) unless wait.value.success?
end
