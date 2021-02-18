#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby share-nc-folders.rb #{ARGV.join(' ')} && cd src/scripts")
