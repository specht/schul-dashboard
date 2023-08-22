#!/usr/bin/env ruby
SKIP_COLLECT_DATA = true
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

HTTP_READ_TIMEOUT = 60 * 10

# This is a really ugly way to monkey patch an increased HTTP read timeout into the dachinat/nextcloud gem.

module Nextcloud
    class Api
        # Sends API request to Nextcloud
        #
        # @param method [Symbol] Request type. Can be :get, :post, :put, etc.
        # @param path [String] Nextcloud OCS API request path
        # @param params [Hash, nil] Parameters to send
        # @return [Object] Nokogiri::XML::Document
        def request(method, path, params = nil, body = nil, depth = nil, destination = nil, raw = false)
            response = Net::HTTP.start(@url.host, @url.port,
            use_ssl: @url.scheme == "https") do |http|
                http.read_timeout = HTTP_READ_TIMEOUT
                req = Kernel.const_get("Net::HTTP::#{method.capitalize}").new(@url.request_uri + path)
                req["OCS-APIRequest"] = true
                req.basic_auth @username, @password
                req["Content-Type"] = "application/x-www-form-urlencoded"
        
                req["Depth"] = 0 if depth
                req["Destination"] = destination if destination
        
                req.set_form_data(params) if params
                req.body = body if body
        
                http.request(req)
            end
    
            # if ![201, 204, 207].include? response.code
            #   raise Errors::Error.new("Nextcloud received invalid status code")
            # end
            raw ? response.body : Nokogiri::XML.parse(response.body)
        end
    end
end

class Script
    def initialize
        @ocs = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                             username: NEXTCLOUD_USER, 
                             password: NEXTCLOUD_PASSWORD)
    end
    
    def run
        STDERR.print "Getting users: "
        all_users = Set.new(@ocs.user.all.map { |x| x.id })
        STDERR.puts "found #{all_users.size}"

        all_users.each do |user_id|
            next if user_id == 'Dashboard'
            ocs_user = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                username: user_id,
                password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL)
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
