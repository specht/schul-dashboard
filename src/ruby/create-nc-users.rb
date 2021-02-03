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
        # CREATE DIRECTORIES on WEBSERVER: data/[user_id]/files/
        # docker-compose exec -u www-data app /bin/bash
        # ./occ files:scan [user_id]
        @@user_info = Main.class_variable_get(:@@user_info)
        @@klassen_for_shorthand = Main.class_variable_get(:@@klassen_for_shorthand)
        STDERR.puts "Getting groups..."
        all_groups = @ocs.group.all
        result = @ocs.group.create('Lehrer') unless all_groups.include?('Lehrer')
        @ocs.group.create('SuS') unless all_groups.include?('SuS')
        all_klassen = Set.new()
        @@klassen_for_shorthand.values.each { |x| all_klassen |= x }
        all_klassen.to_a.sort.each do |x|
            @ocs.group.create("Lehrer #{x}") unless all_groups.include?("Lehrer #{x}")
        end
        all_klassen.to_a.sort.each do |x|
            @ocs.group.create("Klasse #{x}") unless all_groups.include?("Klasse #{x}")
        end
        STDERR.puts "Getting users..."
        all_users = Set.new(@ocs.user.all.map { |x| x.id })
        @@user_info.each_pair do |email, user|
            next unless user[:teacher]
            next unless user[:can_log_in]
            STDERR.print '.'
            klassen = @@klassen_for_shorthand[user[:shorthand]] || []
            user_id = user[:nc_login]
            unless all_users.include?(user_id)
                STDERR.puts "@ocs.user.create(#{user_id}, #{user[:initial_nc_password]})"
                @ocs.user.create(user_id, user[:initial_nc_password])
            end
            user_info = @ocs.user.find(user_id)
# #             @ocs.user.destroy(user_id)
# #             next
            if user_info.displayname != user[:display_last_name]
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name]})"
                @ocs.user.update(user_id, 'displayname', user[:display_last_name])
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                @ocs.user.update(user_id, 'email', email)
            end
            unless user_info.groups.include?('Lehrer')
                STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer')"
                @ocs.user(user_id).group.create('Lehrer')
            end
            klassen.each do |klasse|
                unless user_info.groups.include?("Lehrer #{klasse}")
                    STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer #{klasse}')"
                    @ocs.user(user_id).group.create("Lehrer #{klasse}")
                end
            end
#             klassen.each do |klasse|
#                 @ocs.user(user_id).group.create("Lehrer #{klasse} (19/20)")
#             end
        end
        @@user_info.each_pair do |email, user|
            next if user[:teacher]
            STDERR.print '.'
            display_name = user[:display_name]
            klasse = user[:klasse]
            user_id = email.split('@').first
#             STDERR.puts user_id
            unless all_users.include?(user_id)
                STDERR.puts "@ocs.user.create(#{user_id}, #{user[:initial_nc_password]})"
                @ocs.user.create(user_id, user[:initial_nc_password])
            end
            user_info = @ocs.user.find(user_id)
            if user_info.displayname != user[:display_name]
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_name]})"
                @ocs.user.update(user_id, 'displayname', user[:display_name])
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                @ocs.user.update(user_id, 'email', email)
            end
            unless user_info.groups.include?('SuS')
                STDERR.puts "@ocs.user(#{user_id}).group.create('SuS')"
                @ocs.user(user_id).group.create('SuS')
            end
            unless user_info.groups.include?("Klasse #{klasse}")
                STDERR.puts "@ocs.user(#{user_id}).group.create('Klasse #{klasse}')"
                @ocs.user(user_id).group.create("Klasse #{klasse}")
            end
        end
        STDERR.puts
    end
end

script = Script.new
script.run
