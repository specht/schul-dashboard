#!/usr/bin/env ruby

system("cd ../.. && ./config.rb run --rm --entrypoint ruby ruby share-nc-folders.rb #{ARGV.join(' ')} && cd src/scripts")
