#!/usr/bin/env ruby

repository_root = File.expand_path('../..', __dir__)

success = system(
    './config.rb',
    'exec',
    '-T',
    '-e',
    'DASHBOARD_SERVICE=script',
    'ruby',
    'ruby',
    'remove-broken-nc-shares.rb',
    *ARGV,
    chdir: repository_root
)

exit(success ? 0 : 1)
