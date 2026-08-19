#!/usr/bin/env ruby
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
        srsly = false
        args = ARGV.dup
        if args.include?('--srsly')
            args.delete('--srsly')
            srsly = true
        else
            STDERR.puts "Notice: Not making any modifications unless you specify --srsly"
        end

        @@user_info = Main.class_variable_get(:@@user_info)
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        wanted_nc_ids = nil
        unless args.empty?
            wanted_nc_ids = Set.new(args.map { |email| (@@user_info[email] || {})[:nc_login] })
        end

        @@user_info.keys.sort.each do |email|
            user_id = @@user_info[email][:nc_login]
            unless wanted_nc_ids.nil?
                next unless wanted_nc_ids.include?(user_id)
            end
            ocs_user = DashboardNextcloud.as_user(user_id)
            STDERR.puts "Moving [#{user_id}]/Unterricht to /Archiv-Jahresbeginn-26-27..."
            if srsly
                result = ocs_user.webdav.directory.move('/Unterricht', '/Archiv-Jahresbeginn-26-27')
                if result[:status] != 'ok'
                    STDERR.puts "Error!"
                    STDERR.puts result.to_json
                end
            end
        end

    end
end

script = Script.new
script.run
