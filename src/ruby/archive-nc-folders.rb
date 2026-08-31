#!/usr/bin/env ruby

require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'cgi'
require 'yaml'
require 'json'
require 'securerandom'

ARCHIVE_FOLDER = 'Archiv-Jahresbeginn-26-27'

SHARE_READ = 1
SHARE_UPDATE = 2
SHARE_CREATE = 4
SHARE_DELETE = 8
SHARE_SHARE = 16

class Script
    def initialize
        @ocs = DashboardNextcloud.admin
    end

    def native_share_move_rpc_dir
        '/internal/nextcloud-share-move-rpc'
    end

    def native_share_move!(share, user_id, wanted_target)
        target = DashboardNextcloud.canonical_share_target(wanted_target)

        rpc_dir = native_share_move_rpc_dir
        ready_path = File.join(rpc_dir, 'ready')

        unless File.exist?(ready_path)
            raise(
                'Nextcloud native share move worker is not running. ' \
                'Run this script via src/scripts/archive-nc-folders.rb.'
            )
        end

        request_id = "#{Process.pid}-#{SecureRandom.hex(8)}"
        request_path = File.join(
            rpc_dir,
            'requests',
            "#{request_id}.json"
        )
        request_tmp_path = "#{request_path}.tmp"
        response_path = File.join(
            rpc_dir,
            'responses',
            "#{request_id}.json"
        )

        request = {
            'share_id' => share['id'].to_s,
            'recipient' => user_id,
            'expected_owner' =>
                share['uid_file_owner'] ||
                share['uid_owner'] ||
                NEXTCLOUD_USER,
            'target' => target
        }

        File.write(request_tmp_path, JSON.generate(request))
        File.rename(request_tmp_path, request_path)

        deadline =
            Process.clock_gettime(Process::CLOCK_MONOTONIC) +
            DashboardNextcloud::HTTP_READ_TIMEOUT

        until File.exist?(response_path)
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                raise(
                    "Timed out waiting for Nextcloud native share move " \
                    "worker for share #{share['id']}"
                )
            end

            sleep 0.02
        end

        response = JSON.parse(File.read(response_path))

        unless response['ok']
            raise(
                "#{response['error_class']}: #{response['message']}"
            )
        end

        unless response['target'] == target
            raise(
                "Native share move returned unexpected target " \
                "#{response['target'].inspect}; expected " \
                "#{target.inspect} for share #{share['id']}"
            )
        end

        response
    ensure
        if defined?(request_tmp_path) && request_tmp_path
            FileUtils.rm_f(request_tmp_path)
        end

        if defined?(request_path) && request_path
            FileUtils.rm_f(request_path)
        end

        if defined?(response_path) && response_path
            FileUtils.rm_f(response_path)
        end
    end

    def resolve_wanted_nc_ids(args)
        return nil if args.empty?

        known_nc_ids = Set.new(
            @@user_info.values.map { |user| user[:nc_login] }.compact
        )

        Set.new(
            args.map do |value|
                if @@user_info[value]
                    @@user_info[value][:nc_login]
                elsif known_nc_ids.include?(value)
                    value
                else
                    raise(
                        "Could not resolve #{value.inspect} as an email " \
                        "address or Nextcloud login"
                    )
                end
            end
        )
    end

    def archive_share_candidates(wanted_nc_ids)
        prefix = "/#{ARCHIVE_FOLDER}/"

        (@ocs.file_sharing.all || []).select do |share|
            target = share['file_target'].to_s
            owner =
                share['uid_file_owner'] ||
                share['uid_owner']
            recipient = share['share_with'].to_s

            share['share_type'].to_i == 0 &&
                owner == NEXTCLOUD_USER &&
                !recipient.empty? &&
                target.start_with?(prefix) &&
                (
                    wanted_nc_ids.nil? ||
                    wanted_nc_ids.include?(recipient)
                )
        end.sort_by do |share|
            [
                share['share_with'].to_s,
                share['file_target'].to_s,
                share['id'].to_i
            ]
        end
    end

    def canonicalize_archive_share_targets!(wanted_nc_ids, srsly)
        shares = archive_share_candidates(wanted_nc_ids)

        STDERR.puts(
            "Found #{shares.size} archive share" \
            "#{shares.size == 1 ? '' : 's'} to check for target canonicalization."
        )

        failures = 0

        shares.each_with_index do |share, index|
            recipient = share['share_with']
            old_target = share['file_target']
            target =
                DashboardNextcloud.canonical_share_target(old_target)

            STDERR.puts(
                "#{index + 1}/#{shares.size}: " \
                "share ##{share['id']} " \
                "[#{recipient}] " \
                "#{old_target.inspect} -> #{target.inspect}"
            )

            next unless srsly

            begin
                native_share_move!(
                    share,
                    recipient,
                    target
                )
            rescue StandardError => e
                failures += 1

                STDERR.puts(
                    "ERROR: Could not canonicalize " \
                    "share ##{share['id']} for #{recipient}: " \
                    "#{e.class}: #{e.message}"
                )
            end
        end

        if failures > 0
            raise(
                "Failed to canonicalize #{failures} archive share " \
                "target#{failures == 1 ? '' : 's'}."
            )
        end

        if !srsly && !shares.empty?
            STDERR.puts(
                'Dry run only. Re-run with --srsly to ' \
                'canonicalize these share targets.'
            )
        elsif srsly
            STDERR.puts(
                "Canonicalized #{shares.size} archive share " \
                "target#{shares.size == 1 ? '' : 's'}."
            )
        end
    end

    def run
        args = ARGV.dup

        srsly = !args.delete('--srsly').nil?
        repair_share_targets =
            !args.delete('--repair-share-targets').nil?

        unless srsly
            STDERR.puts(
                'Notice: Not making any modifications unless ' \
                'you specify --srsly'
            )
        end

        @@user_info =
            Main.class_variable_get(:@@user_info)
        @@users_for_role =
            Main.class_variable_get(:@@users_for_role)

        wanted_nc_ids = resolve_wanted_nc_ids(args)

        unless repair_share_targets
            @@user_info.keys.sort.each do |email|
                user_id = @@user_info[email][:nc_login]

                next if user_id.nil?

                unless wanted_nc_ids.nil?
                    next unless wanted_nc_ids.include?(user_id)
                end

                STDERR.puts(
                    "Moving [#{user_id}]/Unterricht " \
                    "to /#{ARCHIVE_FOLDER}..."
                )

                next unless srsly

                ocs_user =
                    DashboardNextcloud.as_user(user_id)

                result =
                    ocs_user.webdav.directory.move(
                        '/Unterricht',
                        "/#{ARCHIVE_FOLDER}"
                    )

                if result[:status] != 'ok'
                    STDERR.puts 'Error!'
                    STDERR.puts result.to_json
                end
            end
        end

        # A MOVE of a parent directory containing received-share
        # mounts can leave their oc_share.file_target values with a
        # trailing slash:
        #
        #   /Archiv-.../Erdkunde GK/Ausgabeordner/
        #
        # Nextcloud's path-specific mount loading strips the trailing
        # slash from the requested DAV path and then compares
        # file_target exactly. Such shares are therefore visible in
        # Files but opening them returns DAV 404.
        #
        # Canonicalize these targets through Nextcloud's share manager
        # rather than changing oc_share directly. The native worker
        # also invalidates the recipient's mount cache.
        canonicalize_archive_share_targets!(
            wanted_nc_ids,
            srsly
        )
    end
end

Script.new.run