#!/usr/bin/env ruby

system("cd ../.. && ./config.rb run --rm --entrypoint ruby ruby unshare-shares-to-klassen.rb #{ARGV.join(' ')} && cd src/scripts")
