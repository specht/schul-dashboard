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

    def find_user!(user_id)
        user = @ocs.user.find(user_id)
        assert_ocs_success!(user, "Reading Nextcloud user #{user_id}")
        user
    end

    def ensure_group!(group_id, all_groups, srsly)
        return if all_groups.include?(group_id)

        STDERR.puts "@ocs.group.create(#{group_id.inspect})"
        return unless srsly

        result = @ocs.group.create(group_id)
        assert_ocs_success!(result, "Creating Nextcloud group #{group_id}")
        all_groups << group_id
    end

    def update_user!(user_id, key, value, attribute)
        result = @ocs.user.update(user_id, key, value)
        assert_ocs_success!(result, "Updating #{key} for Nextcloud user #{user_id}")

        updated = find_user!(user_id)
        actual = updated.public_send(attribute)
        return updated if actual == value

        raise "Updating #{key} for #{user_id} reported success, but Nextcloud returned #{actual.inspect} instead of #{value.inspect}"
    end

    def add_user_to_group!(user_id, group_id)
        result = @ocs.user(user_id).group.create(group_id)
        assert_ocs_success!(result, "Adding Nextcloud user #{user_id} to group #{group_id}")
    end

    def remove_user_from_group!(user_id, group_id)
        result = @ocs.user(user_id).group.destroy(group_id)
        assert_ocs_success!(result, "Removing Nextcloud user #{user_id} from group #{group_id}")
    end

    def group_members!(group_id)
        members = @ocs.group(group_id).members
        assert_ocs_success!(members, "Reading members of Nextcloud group #{group_id}")
        Set.new(members)
    end

    def reconcile_group_members!(group_id, wanted_members, srsly)
        current_members = group_members!(group_id)
        missing = wanted_members - current_members
        stale = current_members - wanted_members

        missing.to_a.sort.each do |user_id|
            STDERR.puts "@ocs.user(#{user_id}).group.create(#{group_id.inspect})"
            add_user_to_group!(user_id, group_id) if srsly
        end

        stale.to_a.sort.each do |user_id|
            STDERR.puts "@ocs.user(#{user_id}).group.destroy(#{group_id.inspect})"
            remove_user_from_group!(user_id, group_id) if srsly
        end

        return unless srsly

        actual_members = group_members!(group_id)
        return if actual_members == wanted_members

        missing_after = (wanted_members - actual_members).to_a.sort
        stale_after = (actual_members - wanted_members).to_a.sort
        raise "Failed to reconcile #{group_id}: still missing #{missing_after.inspect}, still stale #{stale_after.inspect}"
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
        group_list = @ocs.group.all
        assert_ocs_success!(group_list, 'Listing Nextcloud groups')
        all_groups = Set.new(group_list)
        STDERR.puts "found #{all_groups.size}"

        ensure_group!('Lehrbuchverein', all_groups, srsly)
        ensure_group!('Lehrer', all_groups, srsly)
        ensure_group!('SuS', all_groups, srsly)

        all_klassen = Set.new()
        @@klassen_for_shorthand.values.each { |x| all_klassen |= x }
        all_klassen.to_a.sort.each do |x|
            ensure_group!("Lehrer #{x}", all_groups, srsly)
            ensure_group!("Klasse #{x}", all_groups, srsly)
        end

        STDERR.print "Getting users: "
        user_list = @ocs.user.all
        assert_ocs_success!(user_list, 'Listing Nextcloud users')
        all_users = Set.new(user_list.map { |x| x.id })
        STDERR.puts "found #{all_users.size}"
        all_possible_klassen_order = Set.new(KLASSEN_ORDER)
        (5..10).each do |klasse|
            ['a', 'b', 'c', 'd', 'e', 'o'].each { |x| all_possible_klassen_order << "#{klasse}#{x}" }
        end

        desired_class_members = Hash.new { |hash, key| hash[key] = Set.new }
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :schueler)

            group_id = "Klasse #{user[:klasse]}"
            desired_class_members[group_id] << user[:nc_login]
            ensure_group!(group_id, all_groups, srsly)
        end
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :teacher)
            next unless user[:can_log_in]
            STDERR.print '.'
            klassen = @@klassen_for_shorthand[user[:shorthand]] || []
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = find_user!(user_id)
            if user_info.displayname != user[:display_last_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name].unicode_normalize(:nfc)})"
                update_user!(
                    user_id,
                    'displayname',
                    user[:display_last_name].unicode_normalize(:nfc),
                    :displayname
                ) if srsly
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                update_user!(user_id, 'email', email, :email) if srsly
            end
            unless user_info.groups.include?('Lehrer')
                STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer')"
                add_user_to_group!(user_id, 'Lehrer') if srsly
            end
            # Lehrer zu allen Klassen hinzufügen
            klassen.each do |klasse|
                unless user_info.groups.include?("Lehrer #{klasse}")
                    STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrer #{klasse}')"
                    add_user_to_group!(user_id, "Lehrer #{klasse}") if srsly
                end
            end
            # Lehrer aus allen alten Klassen entfernen
            all_possible_klassen_order.each do |klasse|
                unless klassen.include?(klasse)
                    if user_info.groups.include?("Lehrer #{klasse}")
                        STDERR.puts "@ocs.user(#{user_id}).group.destroy('Lehrer #{klasse}')"
                        remove_user_from_group!(user_id, "Lehrer #{klasse}") if srsly
                    end
                end
            end
        end
        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :schueler)
            STDERR.print '.'
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = find_user!(user_id)
            if user_info.displayname != user[:display_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_name].unicode_normalize(:nfc)})"
                update_user!(
                    user_id,
                    'displayname',
                    user[:display_name].unicode_normalize(:nfc),
                    :displayname
                ) if srsly
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                update_user!(user_id, 'email', email, :email) if srsly
            end
            unless user_info.groups.include?('SuS')
                STDERR.puts "@ocs.user(#{user_id}).group.create('SuS')"
                add_user_to_group!(user_id, 'SuS') if srsly
            end
            # Class-group membership is reconciled globally below. Doing this at
            # group level also catches former students that no longer occur in
            # @@user_info and therefore can never be cleaned up by this loop.
        end
        all_possible_klassen_order.to_a.sort.each do |klasse|
            group_id = "Klasse #{klasse}"
            next unless all_groups.include?(group_id)

            reconcile_group_members!(group_id, desired_class_members[group_id], srsly)
        end

        @@user_info.each_pair do |email, user|
            next unless user_has_role(email, :schulbuchverein)
            next unless user[:can_log_in]
            STDERR.print '.'
            user_id = user[:nc_login]
            next unless ensure_internal_user!(user_id, user[:initial_nc_password], all_users, srsly)

            user_info = find_user!(user_id)
            if user_info.displayname != user[:display_last_name].unicode_normalize(:nfc)
                STDERR.puts "@ocs.user.update(#{user_id}, 'displayname', #{user[:display_last_name].unicode_normalize(:nfc)})"
                update_user!(
                    user_id,
                    'displayname',
                    user[:display_last_name].unicode_normalize(:nfc),
                    :displayname
                ) if srsly
            end
            if user_info.email != email
                STDERR.puts "@ocs.user.update(#{user_id}, 'email', #{email})"
                update_user!(user_id, 'email', email, :email) if srsly
            end
            unless user_info.groups.include?('Lehrbuchverein')
                STDERR.puts "@ocs.user(#{user_id}).group.create('Lehrbuchverein')"
                add_user_to_group!(user_id, 'Lehrbuchverein') if srsly
            end
        end
        STDERR.puts
    end
end

script = Script.new
script.run
