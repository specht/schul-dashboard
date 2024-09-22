#!/usr/bin/env ruby

which = 'all'
which = ARGV.join('/') unless ARGV.empty?
system("cd ../.. && ./config.rb exec ruby curl http://mail_bot:8080/api/send_pending_mails && cd src/scripts")
