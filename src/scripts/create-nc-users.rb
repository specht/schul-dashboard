#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby create-nc-users.rb #{ARGV.join(' ')} && cd src/scripts")
