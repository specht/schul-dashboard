#!/usr/bin/env ruby

system("cd ../.. && ./config.rb exec ruby ruby dump-lesson-info.rb #{ARGV.join(' ')} && cd src/scripts")
