#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby clear-database.rb #{ARGV[1, ARGV.size - 1].join(' ')} && cd src/scripts")
