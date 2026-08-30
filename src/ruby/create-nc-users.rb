#!/usr/bin/env ruby
require './main.rb'

require 'set'

class Script
    include UserRoleHelper

    INTERNAL_BACKENDS = Set.new([
        'Database',
        'OC\\User\\Database',
    ]).freeze

    EXTERNAL_BASIC_AUTH_BACKENDS = Set.new([
        'OCA\\UserExternal\\BasicAuth',
        'OC_User_BasicAuth',
    ]).freeze

    def initialize
        @ocs = DashboardNextcloud.admin
    end

    def response_meta(response)
        if response.respond_to?(:meta) && response.meta
            return response.meta
        end

        return {} unless response.respond_to?(:xpath)

        response.xpath('//meta/*').each_with_object({}) do |node, meta|
            meta[node.name] = node.text
        end
    end

    def assert_ocs_success!(response, action)
        meta = response_meta(response)
        return response if meta['status'] == 'ok'

        details = [
            meta['statuscode'],
            meta['message'],
        ].compact.reject(&:empty?).join(' / ')

        details = 'unknown OCS error' if details.empty?
        raise "#{action} failed: #{details}"
    end

    def user_backend(user_id)
        response = @ocs.request(:get, "users/#{user_id}")
        assert_ocs_success!(response, "Reading Nextcloud user #{user_id}")

        backend = response.xpath('//data/backend').text
        raise "Nextcloud returned no backend for #{user_id}" if backend.empty?

        backend
    end

    def internal_backend?(backend)
        INTERNAL_BACKENDS.include?(backend)
    end

    def external_basic_auth_backend?(backend)
        EXTERNAL_BASIC_AUTH_BACKENDS.include?(backend) ||
            (backend.include?('UserExternal') && backend.end_with?('BasicAuth'))
    end

    def create_internal_user!(user_id, password)
        STDERR.puts "@ocs.user.create(#{user_id}, [password hidden])"
        result = @ocs.user.create(user_id, password)
        assert_ocs_success!(result, "Creating internal Nextcloud user #{user_id}")

        backend = user_backend(user_id)
        unless internal_backend?(backend)
            raise "Created #{user_id}, but Nextcloud reports backend #{backend.inspect} instead of an internal database backend"
        end
    end

    def ensure_internal_user!(user_id, password, all_users, srsly)
        unless all_users.include?(user_id)
            if srsly
                create_internal_user!(user_id, password)
                all_users << user_id
                return true
            end

            STDERR.puts "@ocs.user.create(#{user_id}, [password hidden])"
            return false
        end

        backend = user_backend(user_id)
        return true if internal_backend?(backend)

        unless external_basic_auth_backend?(backend)
            raise "Refusing to replace existing Nextcloud user #{user_id}: unexpected backend #{backend.inspect}"
        end

        STDERR.puts "Converting #{user_id} from #{backend} to internal user"
        return false unless srsly

        # These external BasicAuth users are accidental placeholders created by
        # WebDAV authentication with NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL.
        # Delete the placeholder through Nextcloud so its backend registration
        # and associated transient user state are cleaned up, then immediately
        # recreate the same UID in the internal database backend.
        result = @ocs.user.destroy(user_id)
        assert_ocs_success!(result, "Deleting external Nextcloud placeholder #{user_id}")

        all_users.delete(user_id)
        create_internal_user!(user_id, password)
        all_users << user_id

        true
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
        @@users_for_role = Main.class_variable_get(:@@users_for_role)
        @@klassen_for_shorthand = Main.class_variable_get(:@@klassen_for_shorthand)
        STDERR.print "Getting groups: "
        all_groups = @ocs.group.all
        STDERR.puts "found #{all_groups.size}"
        if srsly
            @ocs.group.create('Lehrbuchverein') unless all_groups.include?('Lehrbuchverein')
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
        all_possible_klassen_order = Set.new(KLASSEN_ORDER)
        (5..10).each do |klasse|
            ['a', 'b', 'c', 'd', 'e', 'o'].each { |x| all_possible_klassen_order << "#{klasse}#{x}" }
        end
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :teacher)
            next unless user[:can_log_in]
            STDERR.print '.'
            klassen = @@klassen_for_shorthand[user[:shorthand]] || []
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = @ocs.user.find(user_id)
            if user_info.displayname != user[:display_last_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name].unicode_normalize(:nfc)})"
                if srsly
                    @ocs.user.update(user_id, 'displayname', user[:display_last_name].unicode_normalize(:nfc))
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
            # Lehrer zu allen Klassen hinzufügen
            klassen.each do |klasse|
                unless user_info.groups.include?("Lehrer #{klasse}")
                    STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer #{klasse}')"
                    if srsly
                        @ocs.user(user_id).group.create("Lehrer #{klasse}")
                    end
                end
            end
            # Lehrer aus allen alten Klassen entfernen
            all_possible_klassen_order.each do |klasse|
                unless klassen.include?(klasse)
                    if user_info.groups.include?("Lehrer #{klasse}")
                        STDERR.puts "@ocs.user(#{user_id}).group.destroy('Lehrer #{klasse}')"
                        if srsly
                            @ocs.user(user_id).group.destroy("Lehrer #{klasse}")
                        end
                    end
                end
            end
        end
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :schueler)
            STDERR.print '.'
            klasse = user[:klasse]
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = @ocs.user.find(user_id)
            if user_info.displayname != user[:display_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_name].unicode_normalize(:nfc)})"
                if srsly
                    @ocs.user.update(user_id, 'displayname', user[:display_name].unicode_normalize(:nfc))
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
            # Schüler aus allen alten Klassen entfernen
            all_possible_klassen_order.each do |k|
                unless k == klasse
                    if user_info.groups.include?("Klasse #{k}")
                        STDERR.puts "@ocs.user(#{user_id}).group.destroy('Klasse #{k}')"
                        if srsly
                            @ocs.user(user_id).group.destroy("Klasse #{k}")
                        end
                    end
                end
            end
        end
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :schulbuchverein)
            next unless user[:can_log_in]
            STDERR.print '.'
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = @ocs.user.find(user_id)
            if user_info.displayname != user[:display_last_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name].unicode_normalize(:nfc)})"
                if srsly
                    @ocs.user.update(user_id, 'displayname', user[:display_last_name].unicode_normalize(:nfc))
                end
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                if srsly
                    @ocs.user.update(user_id, 'email', email)
                end
            end
            unless user_info.groups.include?('Lehrbuchverein')
                STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrbuchverein')"
                if srsly
                    @ocs.user(user_id).group.create('Lehrbuchverein')
                end
            end
        end
        STDERR.puts
    end
end

script = Script.new
script.run
