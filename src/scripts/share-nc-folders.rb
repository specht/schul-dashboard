#!/usr/bin/env ruby

system("cd ../.. && ./config.rb run --rm ruby2 ruby share-nc-folders.rb #{ARGV.join(' ')} && cd src/scripts")
