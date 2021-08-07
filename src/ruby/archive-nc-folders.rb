#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'nextcloud'
require 'cgi'
require 'yaml'

SHARE_READ = 1
SHARE_UPDATE = 2
SHARE_CREATE = 4
SHARE_DELETE = 8
SHARE_SHARE = 16

class Script
    def initialize
        @ocs = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                             username: NEXTCLOUD_USER, 
                             password: NEXTCLOUD_PASSWORD)
    end
    
    def run
        srsly = false
        if ARGV.include?('--srsly')
            srsly = true
        else
            STDERR.puts "Notice: Not making any modifications unless you specify --srsly"
        end

        @@user_info = Main.class_variable_get(:@@user_info)
        wanted_nc_ids = nil
        unless ARGV.empty?
            wanted_nc_ids = Set.new(ARGV.map { |email| (@@user_info[email] || {})[:nc_login] })
        end

        wanted_shares.keys.sort.each do |user_id|
            unless wanted_nc_ids.nil?
                next unless wanted_nc_ids.include?(user_id)
            end
            ocs_user = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER, 
                                     username: user_id,
                                     password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL)
            STDERR.puts "Moving [#{user_id}]/Unterricht to /Archiv-20-21..."
            if srsly
                result = ocs_user.webdav.directory.move('/Unterricht', '/Archiv-20-21')
                if result[:status] != 'ok'
                    STDERR.puts "Error!"
                    exit(1)
                end
            end
        end

    end
end

script = Script.new
script.run
