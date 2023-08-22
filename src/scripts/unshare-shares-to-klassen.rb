#!/usr/bin/env ruby

system("cd ../.. && ./config.rb run --rm ruby2 ruby unshare-shares-to-klassen.rb #{ARGV.join(' ')} && cd src/scripts")
