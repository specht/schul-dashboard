#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby curl http://timetable:8080/api/update/#{ARGV.first || 'all_messages'} && cd src/scripts")
