#!/usr/bin/env ruby
require './main.rb'
require 'nextcloud'

require 'set'

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
        # CREATE DIRECTORIES on WEBSERVER: data/[user_id]/files/
        # docker-compose exec -u www-data app /bin/bash
        # ./occ files:scan [user_id]
        @@user_info = Main.class_variable_get(:@@user_info)
        @@klassen_for_shorthand = Main.class_variable_get(:@@klassen_for_shorthand)
        STDERR.print "Getting groups: "
        all_groups = @ocs.group.all
        STDERR.puts "found #{all_groups.size}"
        if srsly
            @ocs.group.create('Lehrer') unless all_groups.include?('Lehrer')
            @ocs.group.create('SuS') unless all_groups.include?('SuS')
        end
        all_klassen = Set.new()
        @@klassen_for_shorthand.values.each { |x| all_klassen |= x }
        all_klassen.to_a.sort.each do |x|
            if srsly
                @ocs.group.create("Lehrer #{x}") unless all_groups.include?("Lehrer #{x}")
            end
        end
        all_klassen.to_a.sort.each do |x|
            if srsly
                @ocs.group.create("Klasse #{x}") unless all_groups.include?("Klasse #{x}")
            end
        end
        STDERR.print "Getting users: "
        all_users = Set.new(@ocs.user.all.map { |x| x.id })
        STDERR.puts "found #{all_users.size}"
        @@user_info.each_pair do |email, user|
            next unless email == 'specht@gymnasiumsteglitz.de'
            next unless user[:teacher]
            next unless user[:can_log_in]
            STDERR.print '.'
            klassen = @@klassen_for_shorthand[user[:shorthand]] || []
            user_id = user[:nc_login]
            unless all_users.include?(user_id)
                STDERR.puts "@ocs.user.create(#{user_id}, #{user[:initial_nc_password]})"
                if srsly
                    @ocs.user.create(user_id, user[:initial_nc_password])
                end
            end
            user_info = @ocs.user.find(user_id)
# #             @ocs.user.destroy(user_id)
# #             next
            if user_info.displayname != user[:display_last_name]
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name]})"
                if srsly
                    @ocs.user.update(user_id, 'displayname', user[:display_last_name])
                end
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                if srsly
                    @ocs.user.update(user_id, 'email', email)
                end
            end
            unless user_info.groups.include?('Lehrer')
                STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer')"
                if srsly
                    @ocs.user(user_id).group.create('Lehrer')
                end
            end
            klassen.each do |klasse|
                unless user_info.groups.include?("Lehrer #{klasse}")
                    STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer #{klasse}')"
                    if srsly
                        @ocs.user(user_id).group.create("Lehrer #{klasse}")
                    end
                end
            end
#             klassen.each do |klasse|
#                 @ocs.user(user_id).group.create("Lehrer #{klasse} (19/20)")
#             end
        end
        @@user_info.each_pair do |email, user|
            next
            next if user[:teacher]
            STDERR.print '.'
            display_name = user[:display_name]
            klasse = user[:klasse]
            user_id = email.split('@').first
#             STDERR.puts user_id
            unless all_users.include?(user_id)
                STDERR.puts "@ocs.user.create(#{user_id}, #{user[:initial_nc_password]})"
                if srsly
                    @ocs.user.create(user_id, user[:initial_nc_password])
                end
            end
            user_info = @ocs.user.find(user_id)
            if user_info.displayname != user[:display_name]
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_name]})"
                if srsly
                    @ocs.user.update(user_id, 'displayname', user[:display_name])
                end
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                if srsly
                    @ocs.user.update(user_id, 'email', email)
                end
            end
            unless user_info.groups.include?('SuS')
                STDERR.puts "@ocs.user(#{user_id}).group.create('SuS')"
                if srsly
                    @ocs.user(user_id).group.create('SuS')
                end
            end
            unless user_info.groups.include?("Klasse #{klasse}")
                STDERR.puts "@ocs.user(#{user_id}).group.create('Klasse #{klasse}')"
                if srsly
                    @ocs.user(user_id).group.create("Klasse #{klasse}")
                end
            end
        end
        STDERR.puts
    end
end

script = Script.new
script.run
