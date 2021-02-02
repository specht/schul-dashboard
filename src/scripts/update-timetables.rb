#!/usr/bin/env ruby

which = 'all'
which = ARGV.join('/') unless ARGV.empty?
system("cd ../.. && ./config.rb exec ruby curl http://timetable_1:8080/api/update/#{which} && cd src/scripts")
