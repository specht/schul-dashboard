#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby clear-database.rb #{(ARGV[0, ARGV.size] || []).join(' ')} && cd src/scripts")
