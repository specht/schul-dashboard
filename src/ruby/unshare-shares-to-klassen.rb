#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'cgi'
require 'yaml'

SHARE_READ = 1
SHARE_UPDATE = 2
SHARE_CREATE = 4
SHARE_DELETE = 8
SHARE_SHARE = 16

class Script
    def initialize
        @ocs = DashboardNextcloud.admin
    end
    
    def run
        STDERR.print "Getting users: "
        all_users = Set.new(@ocs.user.all.map { |x| x.id })
        STDERR.puts "found #{all_users.size}"

        all_users.each do |user_id|
            next if user_id == 'Dashboard'
            ocs_user = DashboardNextcloud.as_user(user_id)
            (ocs_user.file_sharing.all || []).each do |share|
                next if share['share_with'].nil?
                next if share['uid_owner'] == 'Dashboard'
                next unless share['share_with'][0, 7] == 'Klasse '
                STDERR.puts "#{user_id}: #{share['share_with']} #{share['path']}"
                if ARGV.include?('--srsly')
                    ocs_user.file_sharing.destroy(share['id'])
                end
            end
        end
    end
end

script = Script.new
script.run
