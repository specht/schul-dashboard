#!/usr/bin/env ruby

require 'open3'

Open3.popen2("sh -c '(cd ../../ && ./config.rb run --rm ruby2 ruby create-nc-folders.rb)'") do |fin, fout, wait|
    fout.each_line do |line|
        if line[0, 8] == '__RUN__ '
            line = line.gsub('__RUN__ ', '')
            puts line.gsub("\r", '')
        end
    end
end
