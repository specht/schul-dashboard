#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby archive-nc-folders.rb #{ARGV.join(' ')} && cd src/scripts")
