#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby curl http://timetable_1:8080/api/update/#{ARGV.first || 'all_messages'} && cd src/scripts")
