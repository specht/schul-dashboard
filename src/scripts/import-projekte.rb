#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby import-projekte.rb #{ARGV.join(' ')} && cd src/scripts")
