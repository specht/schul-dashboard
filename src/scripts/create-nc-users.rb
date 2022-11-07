#!/usr/bin/env ruby

system("cd ../.. && ./config.rb run --rm ruby2 ruby create-nc-users.rb #{ARGV.join(' ')} && cd src/scripts")
