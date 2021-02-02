#!/usr/bin/env ruby

which = 'all'
which = ARGV.join('/') unless ARGV.empty?
system("cd ../.. && ./config.rb exec ruby curl http://image_bot_1:8080/api/update_all && cd src/scripts")
