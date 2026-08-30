#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'cgi'
require 'yaml'
require 'zip'
require 'uri'
require 'net/http'
require 'json'
require 'securerandom'
require 'rexml/document'

DEBUG_ARCHIVE_PATH = '/data/debug_archives/2023-07-23.zip'
SHARE_ARCHIVED_FILES = ARGV.include?('--share-archived')
SHARE_SOURCE_FOLDER = SHARE_ARCHIVED_FILES ? 'Unterricht-22-23' : 'Unterricht'
SHARE_TARGET_FOLDER = SHARE_ARCHIVED_FILES ? 'Archiv-Jahresbeginn-23-24' : 'Unterricht'
SRSLY = ARGV.include?('--srsly')

ALSO_SHARE_OS_FOLDERS = true

SHARE_READ = 1
SHARE_UPDATE = 2
SHARE_CREATE = 4
SHARE_DELETE = 8
SHARE_SHARE = 16

class Script
    def initialize
        @ocs = DashboardNextcloud.admin

        @verbose = false
        @debug_shares = false
        @errors = []
        @stats = Hash.new(0)
        @present_share_records = {}
    end

    def log(message = '')
        return unless @verbose || @debug_shares

        STDERR.puts message
    end

    def debug_log(message = '')
        return unless @debug_shares

        STDERR.puts message
    end

    def error(message, details = nil)
        @errors << message

        STDERR.puts "ERROR: #{message}"

        return if details.nil?

        if details.is_a?(String)
            STDERR.puts details
        else
            STDERR.puts details.to_yaml
        end
    end

    def warn(message)
        STDERR.puts "WARNING: #{message}"
    end

    def count(key, amount = 1)
        @stats[key] += amount
    end

    def set_count(key, value)
        @stats[key] = value
    end

    def selected_user?(wanted_nc_ids, user_id)
        wanted_nc_ids.nil? || wanted_nc_ids.include?(user_id)
    end

    def print_summary(failed_share_ids)
        STDERR.puts
        STDERR.puts "Summary:"
        STDERR.puts "  Mode: #{SRSLY ? 'changed Nextcloud' : 'dry run, no changes'}"

        STDERR.puts
        STDERR.puts "  Scope:"
        STDERR.puts "    wanted users:              #{@stats[:wanted_users]}"
        STDERR.puts "    wanted shares:             #{@stats[:wanted_shares]}"
        STDERR.puts "    users processed:           #{@stats[:users_processed]}"

        STDERR.puts
        STDERR.puts "  Shares:"
        STDERR.puts "    already correct:           #{@stats[:shares_already_correct]}"
        STDERR.puts "    newly shared:              #{@stats[:shares_created]}"
        STDERR.puts "    creation failures:         #{@stats[:share_create_errors]}"
        STDERR.puts "    recreated from stale info: #{@stats[:shares_recreated_from_stale_cache]}"
        STDERR.puts "    permissions updated:       #{@stats[:permissions_updated]}"
        STDERR.puts "    moved:                     #{@stats[:shares_moved]}"
        STDERR.puts "    stale shares removed:      #{@stats[:shares_removed]}"
        STDERR.puts "    duplicate shares removed:  #{@stats[:duplicate_shares_removed]}"
        STDERR.puts "    duplicate targets skipped: #{@stats[:duplicate_target_sources_skipped]}"

        unless SRSLY
            STDERR.puts "    would ensure shares:       #{@stats[:shares_would_ensure]}"
            STDERR.puts "    would remove shares:       #{@stats[:shares_would_remove]}"
        end

        STDERR.puts
        STDERR.puts "  Target folders:"
        STDERR.puts "    already wanted/in place:   #{@stats[:target_folders_already_wanted]}"
        STDERR.puts "    deleted:                   #{@stats[:target_folders_deleted]}"
        STDERR.puts "    empty move targets removed: #{@stats[:empty_move_targets_removed]}"
        STDERR.puts "    kept because non-empty:    #{@stats[:target_folders_kept_nonempty]}"
        STDERR.puts "    inspect/delete errors:     #{@stats[:target_folder_cleanup_errors]}"

        unless SRSLY
            STDERR.puts "    would delete:              #{@stats[:target_folders_would_delete]}"
        end

        STDERR.puts
        STDERR.puts "  Parent folders for moved shares:"
        STDERR.puts "    created:                   #{@stats[:parent_dirs_created]}"
        STDERR.puts "    already present:           #{@stats[:parent_dirs_already_present]}"
        STDERR.puts "    checks ok:                 #{@stats[:parent_checks_ok]}"

        STDERR.puts
        STDERR.puts "  Problems:"
        STDERR.puts "    errors:                    #{@errors.size}"
        STDERR.puts "    failed share ids:          #{failed_share_ids.size}"

        STDERR.puts
    end

    def take_option!(argv, name)
        index = argv.index(name)
        return nil if index.nil?

        argv.delete_at(index)
        value = argv.delete_at(index)

        if value.nil? || value.start_with?('--')
            raise "Missing value for #{name}"
        end

        value
    end

    def normalize_nc_path(path)
        DashboardNextcloud.normalize_dav_path(path)
    end

    def same_nc_path?(a, b)
        normalize_nc_path(a) == normalize_nc_path(b)
    end

    def dav_uri_for(user_id, path)
        DashboardNextcloud.dav_uri(user_id, path)
    end

    def raw_webdav_request(user_id, method, path, destination_path: nil, depth: nil, request_body: nil, headers: {})
        uri = dav_uri_for(user_id, path)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.read_timeout = DashboardNextcloud::HTTP_READ_TIMEOUT

            req = Net::HTTPGenericRequest.new(method.to_s.upcase, !request_body.nil?, true, uri.request_uri)
            req.basic_auth user_id, NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL
            req['Depth'] = depth.to_s unless depth.nil?
            headers.each_pair { |name, value| req[name] = value }

            unless request_body.nil?
                req['Content-Type'] = 'application/xml; charset=utf-8' if req['Content-Type'].nil?
                req.body = request_body
            end

            if destination_path
                destination_uri = dav_uri_for(user_id, destination_path)
                req['Destination'] = destination_uri.to_s

                # Do not silently overwrite an existing target. If the destination
                # exists, we want the real WebDAV status code.
                req['Overwrite'] = 'F'
            end

            http.request(req)
        end

        {
            :ok => response.code.to_i.between?(200, 299),
            :code => response.code.to_i,
            :message => response.message,
            :body => response.body.to_s,
            :source_uri => uri.to_s,
            :destination_uri => destination_path ? dav_uri_for(user_id, destination_path).to_s : nil
        }
    end

    def raw_mkcol(user_id, path)
        result = raw_webdav_request(user_id, 'MKCOL', path)

        # 201 = created
        # 405 = already exists / method not allowed on existing collection
        result[:ok] = [201, 405].include?(result[:code])

        result
    end

    def raw_propfind(user_id, path, depth: 0)
        result = raw_webdav_request(user_id, 'PROPFIND', path, depth: depth)

        # 207 = Multi-Status
        result[:ok] = result[:code] == 207

        result
    end

    def raw_propfind_move_target(user_id, path)
        request_body = <<~XML
            <?xml version="1.0" encoding="utf-8" ?>
            <d:propfind xmlns:d="DAV:" xmlns:nc="http://nextcloud.org/ns">
              <d:prop>
                <d:resourcetype />
                <d:getetag />
                <nc:mount-type />
                <nc:is-mount-root />
              </d:prop>
            </d:propfind>
        XML

        result = raw_webdav_request(
            user_id,
            'PROPFIND',
            path,
            depth: 1,
            request_body: request_body
        )
        result[:ok] = result[:code] == 207
        return result unless result[:ok]

        begin
            document = REXML::Document.new(result[:body])
            namespaces = {
                'd' => 'DAV:',
                'nc' => 'http://nextcloud.org/ns'
            }
            responses = REXML::XPath.match(document, '//d:response', namespaces)
            response = responses.first

            raise 'PROPFIND returned no DAV response' if response.nil?

            successful_propstat = REXML::XPath.match(response, 'd:propstat', namespaces).find do |propstat|
                status = REXML::XPath.first(propstat, 'd:status', namespaces)&.text.to_s
                status.include?(' 200 ')
            end
            raise 'PROPFIND returned no successful propstat' if successful_propstat.nil?

            prop = REXML::XPath.first(successful_propstat, 'd:prop', namespaces)
            raise 'PROPFIND returned no property set' if prop.nil?

            mount_type_node = REXML::XPath.first(prop, 'nc:mount-type', namespaces)
            mount_root_node = REXML::XPath.first(prop, 'nc:is-mount-root', namespaces)

            result[:response_count] = responses.size
            result[:collection] = !REXML::XPath.first(
                prop,
                'd:resourcetype/d:collection',
                namespaces
            ).nil?
            result[:etag] = REXML::XPath.first(prop, 'd:getetag', namespaces)&.text.to_s
            result[:mount_type] = mount_type_node&.text.to_s
            result[:mount_root] = mount_root_node&.text.to_s == 'true'
            result[:mount_info_available] = !mount_type_node.nil? && !mount_root_node.nil?
        rescue StandardError => e
            result[:ok] = false
            result[:parse_error] = "#{e.class}: #{e.message}"
        end

        result
    end

    def raw_delete_empty_move_target(user_id, path, etag)
        result = raw_webdav_request(
            user_id,
            'DELETE',
            path,
            headers: {'If-Match' => etag}
        )
        result[:ok] = result[:code] == 204
        result
    end

    def raw_move(user_id, source_path, target_path)
        result = raw_webdav_request(user_id, 'MOVE', source_path, destination_path: target_path)

        # 201 = created at destination
        # 204 = moved successfully, no response body
        result[:ok] = [201, 204].include?(result[:code])

        result
    end

    def create_parent_directories_raw!(user_id, target_path, created_sub_paths)
        ok = true
        dir_parts = File.dirname(target_path).split('/')

        dir_parts.each.with_index do |_p, index|
            sub_path = dir_parts[0, index + 1].join('/')
            next if sub_path.empty?

            normalized = normalize_nc_path(sub_path)
            next if created_sub_paths.include?(normalized)

            log "RAW MKCOL/check [#{user_id}]#{sub_path}..."
            result = raw_mkcol(user_id, sub_path)

            debug_log "RAW MKCOL RESULT:"
            debug_log result.to_yaml

            if result[:code] == 201
                count(:parent_dirs_created)
            elsif result[:code] == 405
                count(:parent_dirs_already_present)
            end

            unless result[:ok]
                error "RAW MKCOL failed for [#{user_id}]#{sub_path}", result
                ok = false
            end

            created_sub_paths << normalized
        end

        ok
    end

    def verify_parent_directory_raw!(user_id, target_path)
        parent_path = File.dirname(target_path)
        result = raw_propfind(user_id, parent_path, depth: 0)

        debug_log "RAW PARENT CHECK:"
        debug_log result.to_yaml

        unless result[:ok]
            error "Parent directory does not exist or is not accessible: [#{user_id}]#{parent_path}", result
            return false
        end

        count(:parent_checks_ok)
        true
    end

    def native_share_move_rpc_dir
        '/internal/nextcloud-share-move-rpc'
    end

    def native_share_move!(share, user_id, wanted_target)
        target = DashboardNextcloud.canonical_share_target(wanted_target)

        rpc_dir = native_share_move_rpc_dir
        ready_path = File.join(rpc_dir, 'ready')

        unless File.exist?(ready_path)
            raise "Nextcloud native share move worker is not running. Run this script via src/scripts/share-nc-folders.rb."
        end

        request_id = "#{Process.pid}-#{SecureRandom.hex(8)}"
        request_path = File.join(rpc_dir, 'requests', "#{request_id}.json")
        request_tmp_path = "#{request_path}.tmp"
        response_path = File.join(rpc_dir, 'responses', "#{request_id}.json")

        request = {
            'share_id' => share['id'].to_s,
            'recipient' => user_id,
            'expected_owner' => share['uid_file_owner'] || share['uid_owner'] || NEXTCLOUD_USER,
            'target' => target
        }

        File.write(request_tmp_path, JSON.generate(request))
        File.rename(request_tmp_path, request_path)

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DashboardNextcloud::HTTP_READ_TIMEOUT
        until File.exist?(response_path)
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
                raise "Timed out waiting for Nextcloud native share move worker for share #{share['id']}"
            end
            sleep 0.02
        end

        response = JSON.parse(File.read(response_path))
        unless response['ok']
            raise "#{response['error_class']}: #{response['message']}"
        end

        unless same_nc_path?(response['target'], target)
            raise "Native share move returned unexpected target #{response['target'].inspect}; expected #{target.inspect} for share #{share['id']}"
        end

        response
    ensure
        FileUtils.rm_f(request_tmp_path) if defined?(request_tmp_path) && request_tmp_path
        FileUtils.rm_f(request_path) if defined?(request_path) && request_path
        FileUtils.rm_f(response_path) if defined?(response_path) && response_path
    end

    def share_move_target_free?(user_id, target_path)
        result = raw_propfind_move_target(user_id, target_path)

        return true if result[:code] == 404

        unless result[:ok]
            error "Could not verify that share destination is free for [#{user_id}]#{target_path}", result
            return false
        end

        unless result[:mount_info_available]
            error "Refusing to remove existing destination for [#{user_id}]#{target_path}: Nextcloud did not return mount information", result
            return false
        end

        if result[:mount_root] || !result[:mount_type].to_s.empty?
            error "Refusing to move share for [#{user_id}] to #{target_path}: destination is a mounted filesystem node", {
                :mount_type => result[:mount_type],
                :mount_root => result[:mount_root],
                :source_uri => result[:source_uri]
            }
            return false
        end

        unless result[:collection]
            error "Refusing to move share for [#{user_id}] to #{target_path}: destination is not a directory", result
            return false
        end

        if result[:response_count] != 1
            error "Refusing to move share for [#{user_id}] to #{target_path}: destination directory is not empty", {
                :entries_including_directory => result[:response_count],
                :source_uri => result[:source_uri]
            }
            return false
        end

        if result[:etag].nil? || result[:etag].empty?
            error "Refusing to remove empty destination for [#{user_id}]#{target_path}: Nextcloud returned no ETag", result
            return false
        end

        # This is an ordinary empty directory at the exact place where the
        # received share belongs. Remove it only if its ETag is unchanged since
        # the Depth: 1 check above. That makes a concurrent change fail safely
        # with HTTP 412 instead of deleting newly-added user data.
        log "Removing empty ordinary destination directory [#{user_id}]#{target_path} before native share move..."
        delete_result = raw_delete_empty_move_target(user_id, target_path, result[:etag])

        unless delete_result[:ok]
            error "Could not remove empty destination directory for [#{user_id}]#{target_path}", delete_result
            return false
        end

        count(:empty_move_targets_removed)
        true
    end

    def verify_share_target_after_move(path, user_id, share_id, wanted_target)
        shares_after_move = user_shares_for_path(path, user_id, force: true)
        share_after_move = shares_after_move.find { |x| x['id'].to_s == share_id.to_s }

        if @debug_shares
            STDERR.puts "AFTER NATIVE SHARE MOVE CHECK:"
            if share_after_move
                STDERR.puts "  share id:       #{share_after_move['id']}"
                STDERR.puts "  file_target:    #{share_after_move['file_target'].inspect}"
                STDERR.puts "  decoded target: #{normalize_nc_path(share_after_move['file_target']).inspect}"
                STDERR.puts "  wanted target:  #{normalize_nc_path(wanted_target).inspect}"
            else
                STDERR.puts "  Could not find share after move."
            end
        end

        unless share_after_move
            error "Could not verify share after native share move: share disappeared from OCS result. User: #{user_id}, source: #{path}, share id: #{share_id}"
            return false
        end

        unless same_nc_path?(share_after_move['file_target'], wanted_target)
            error "Native share move returned success, but file_target did not change as expected. User: #{user_id}, source: #{path}, share id: #{share_id}", {
                :current_file_target => share_after_move['file_target'],
                :current_decoded => normalize_nc_path(share_after_move['file_target']),
                :wanted_target => wanted_target,
                :wanted_decoded => normalize_nc_path(wanted_target)
            }
            return false
        end

        true
    end

    def create_user_share(ocs, path, user_id, permissions)
        # Use the OCS endpoint directly so we can explicitly suppress share mails.
        # shareType 0 = internal user share.
        response = ocs.file_sharing.request(:post, 'shares', {
            'path' => path,
            'shareType' => 0,
            'shareWith' => user_id,
            'permissions' => permissions,
            'sendMail' => 'false'
        })

        meta = response.xpath('//meta/*').each_with_object({}) do |node, result|
            result[node.name] = node.text
        end

        unless meta['status'] == 'ok'
            status_code = meta['statuscode'].to_s
            message = meta['message'].to_s
            details = []
            details << "OCS #{status_code}" unless status_code.empty?
            details << message unless message.empty?
            details << 'response contained no OCS status' if details.empty?

            raise "Nextcloud rejected share creation #{path} => [#{user_id}]: #{details.join(': ')}"
        end

        share = {}
        data = response.at_xpath('//data')
        (data&.element_children || []).each do |node|
            next unless node.element_children.empty?

            share[node.name] = node.text
        end

        if share['id'].to_s.empty?
            raise "Nextcloud reported successful share creation #{path} => [#{user_id}], but returned no share id"
        end

        unless share['share_type'].to_i == 0 &&
               share['share_with'] == user_id &&
               same_nc_path?(share['path'], path)
            raise "Nextcloud returned an unexpected share after creating #{path} => [#{user_id}]: #{share.inspect}"
        end

        share
    rescue StandardError
        count(:share_create_errors)
        raise
    end

    def user_shares_for_path(path, user_id, force: false)
        key = [normalize_nc_path(path), user_id]

        unless force
            cached = @present_share_records[key]
            return cached unless cached.nil?
        end

        shares = (@ocs.file_sharing.specific(path.gsub(' ', '%20')) || []).select do |share|
            share['share_type'].to_i == 0 && share['share_with'] == user_id
        end

        @present_share_records[key] = shares
        shares
    end

    def cache_has_share_types?(present_shares)
        present_shares.each_value do |shares_for_user|
            shares_for_user.each_value do |info|
                return false unless info.key?(:share_type)
            end
        end
        true
    end

    def collect_present_shares
        present_shares = {}
        @present_share_records = {}

        (@ocs.file_sharing.all || []).each do |share|
            next if share['share_with'].nil?
            next unless share['share_type'].to_i == 0
            next if share['path'].nil?

            key = [normalize_nc_path(share['path']), share['share_with']]
            (@present_share_records[key] ||= []) << share

            next unless share['path'].index("/#{SHARE_SOURCE_FOLDER}/") == 0

            present_shares[share['share_with']] ||= {}
            present_shares[share['share_with']][share['path']] = {
                :permissions => share['permissions'].to_i,
                :target_path => share['file_target'],
                :share_with => share['share_with_displayname'],
                :id => share['id'],
                :share_type => share['share_type'].to_i
            }
        end

        present_shares
    end

    def present_shares_from_records
        present_shares = {}

        @present_share_records.each_pair do |key, shares|
            path, user_id = key
            next unless path.index("/#{SHARE_SOURCE_FOLDER}/") == 0
            next if shares.empty?

            share = shares.first

            present_shares[user_id] ||= {}
            present_shares[user_id][path] = {
                :permissions => share['permissions'].to_i,
                :target_path => share['file_target'],
                :share_with => share['share_with_displayname'],
                :id => share['id'],
                :share_type => share['share_type'].to_i
            }
        end

        present_shares
    end

    def preferred_share(shares, wanted_target)
        shares.find do |share|
            same_nc_path?(share['file_target'], wanted_target)
        end || shares.min_by { |share| share['id'].to_i }
    end

    def remove_present_share_record!(key, share, duplicate:, failed_share_ids:)
        path, user_id = key
        kind = duplicate ? 'duplicate' : 'stale'

        log "Removing #{kind} share ##{share['id']} #{path} => [#{user_id}]#{share['file_target']}..."

        begin
            @ocs.file_sharing.destroy(share['id'])
            count(duplicate ? :duplicate_shares_removed : :shares_removed)
            @present_share_records[key].delete_if do |record|
                record['id'].to_s == share['id'].to_s
            end
            true
        rescue StandardError => e
            error "Could not remove #{kind} share #{path} for #{user_id}, share id #{share['id']}: #{e.class}: #{e.message}",
                  e.backtrace.first(10).join("\n")
            failed_share_ids << share['id']
            false
        end
    end

    def deduplicate_present_share_records!(path, user_id, wanted_target, failed_share_ids)
        key = [normalize_nc_path(path), user_id]
        shares = @present_share_records[key] || []
        return shares if shares.size <= 1

        keep = preferred_share(shares, wanted_target)
        ok = true

        shares.dup.each do |share|
            next if share['id'].to_s == keep['id'].to_s

            unless remove_present_share_record!(
                key,
                share,
                duplicate: true,
                failed_share_ids: failed_share_ids
            )
                ok = false
            end
        end

        return nil unless ok

        @present_share_records[key] || []
    end

    def reconcile_present_shares_before_ensure!(wanted_shares, wanted_nc_ids, failed_share_ids)
        # Clean up before MOVE. Otherwise a stale share can still occupy the
        # wanted destination and make SabreDAV return 412.
        @present_share_records.keys.sort_by { |path, user_id| [user_id, path] }.each do |key|
            path, user_id = key
            next unless selected_user?(wanted_nc_ids, user_id)
            next unless path.index("/#{SHARE_SOURCE_FOLDER}/") == 0

            wanted_info = (wanted_shares[user_id] || {})[path]

            if wanted_info.nil?
                (@present_share_records[key] || []).dup.each do |share|
                    remove_present_share_record!(
                        key,
                        share,
                        duplicate: false,
                        failed_share_ids: failed_share_ids
                    )
                end
                next
            end

            deduplicate_present_share_records!(
                path,
                user_id,
                wanted_info[:target_path],
                failed_share_ids
            )
        end

        present_shares_from_records
    end

    def resolve_only_user!(only_user)
        return nil if only_user.nil?

        if @@user_info[only_user]
            return @@user_info[only_user][:nc_login]
        end

        if @@user_info.values.any? { |u| u[:nc_login] == only_user }
            return only_user
        end

        raise "Could not resolve --only-user #{only_user.inspect} as email or Nextcloud login"
    end

    def run
        argv = ARGV.dup

        argv.delete('--share-archived')
        argv.delete('--srsly')

        use_cached = !argv.delete('--use-cached').nil?
        if use_cached && SRSLY
            warn '--use-cached is ignored with --srsly so changes are based on a fresh share snapshot.'
            use_cached = false
        end

        @debug_shares = !argv.delete('--debug-shares').nil?
        @verbose = !argv.delete('--verbose').nil? || @debug_shares

        only_user = take_option!(argv, '--only-user')

        @@debug_archive = {}
        if SHARE_ARCHIVED_FILES
            Zip::File.open(DEBUG_ARCHIVE_PATH) do |zip_file|
                zip_file.each do |entry|
                    if entry.file?
                        content = nil
                        entry.get_input_stream { |io| content = io.read }
                        @@debug_archive[File.basename(entry.name).sub('.yaml', '').to_sym] = YAML.load(content)
                    end
                end
            end
        end

        if SHARE_ARCHIVED_FILES
            @@user_info = @@debug_archive[:@@user_info]
            @@users_for_role = @@debug_archive[:@@users_for_role]
            @@klassen_order = @@debug_archive[:@@klassen_order]
            @@lessons_for_klasse = @@debug_archive[:@@lessons_for_klasse]
            @@lessons = @@debug_archive[:@@lessons]
            @@faecher = @@debug_archive[:@@faecher]
            @@shorthands = @@debug_archive[:@@shorthands]
            @@schueler_for_lesson = @@debug_archive[:@@schueler_for_lesson]
            @@lessons_for_shorthand = @@debug_archive[:@@lessons_for_shorthand]
            @@materialamt_for_lesson = @@debug_archive[:@@materialamt_for_lesson]
            @@teachers_for_klasse = @@debug_archive[:@@teachers_for_klasse]
            @@schueler_for_klasse = @@debug_archive[:@@schueler_for_klasse]
        else
            @@user_info = Main.class_variable_get(:@@user_info)
            @@users_for_role = Main.class_variable_get(:@@users_for_role)
            @@klassen_order = Main.class_variable_get(:@@klassen_order)
            @@lessons_for_klasse = Main.class_variable_get(:@@lessons_for_klasse)
            @@lessons = Main.class_variable_get(:@@lessons)
            @@faecher = Main.class_variable_get(:@@faecher)
            @@shorthands = Main.class_variable_get(:@@shorthands)
            @@schueler_for_lesson = Main.class_variable_get(:@@schueler_for_lesson)
            @@lessons_for_shorthand = Main.class_variable_get(:@@lessons_for_shorthand)
            @@materialamt_for_lesson = Main.class_variable_get(:@@materialamt_for_lesson)
            @@teachers_for_klasse = Main.class_variable_get(:@@teachers_for_klasse)
            @@schueler_for_klasse = Main.class_variable_get(:@@schueler_for_klasse)
        end

        unless SRSLY
            warn "Doing nothing unless you specify --srsly."
        end

        schueler_with_dashboard_amt = Set.new()
        $neo4j.neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User {has_dashboard_amt: TRUE}) RETURN u.email;
        END_OF_QUERY
            email = row['u.email']
            schueler_with_dashboard_amt << email
        end

#         @ocs.file_sharing.all.each do |share|
#             STDERR.puts sprintf('[%5s] type=%s %s => [%s]%s',
#                                 share['id'], share['share_type'], share['path'],
#                                 share['share_with'], share['file_target'])
#             STDERR.puts share.to_yaml
#             @ocs.file_sharing.destroy(share['id'])
#         end
#         return

        wanted_shares = {}
        email_for_user_id = {}

        @@shorthands_for_lesson = {}
        @@lessons_for_shorthand.each_pair do |shorthand, item|
            item.each do |lesson_key|
                @@shorthands_for_lesson[lesson_key] ||= Set.new()
                @@shorthands_for_lesson[lesson_key] << shorthand
            end
        end

        latest_lesson_keys = Set.new(@@lessons[:timetables][@@lessons[:timetables].keys.sort.last].keys)
        all_lesson_keys = Set.new()
        all_shorthands_for_lesson = {}

        @@lessons[:timetables].keys.sort.each do |date|
            all_lesson_keys |= Set.new(@@lessons[:timetables][date].keys)
            @@lessons[:timetables][date].each_pair do |lesson_key, lesson_info|
                lesson_info[:stunden].each_pair do |dow, dow_info|
                    dow_info.each_pair do |stunde, stunden_info|
                        stunden_info[:lehrer].each do |shorthand|
                            all_shorthands_for_lesson[lesson_key] ||= Set.new()
                            all_shorthands_for_lesson[lesson_key] << shorthand
                        end
                    end
                end
            end
        end

        all_lesson_keys.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]

            # only handle lessons which have actual Klassen
            next if (Set.new(lesson_info[:klassen]) & Set.new(@@klassen_order)).empty?

            unless ALSO_SHARE_OS_FOLDERS
                next unless (Set.new(lesson_info[:klassen]) & Set.new(['11', '12'])).empty?
            end

            next if lesson_key[0, 8] == 'Testung_'

            folder_name = "#{lesson_key}"
            fach = lesson_info[:fach]
            fach = @@faecher[fach] || fach
            next if fach.empty?

            pretty_folder_name = lesson_info[:pretty_folder_name]
            teachers = Set.new(lesson_info[:lehrer])
            teachers |= all_shorthands_for_lesson[lesson_key] || Set.new()

            teachers.each do |shorthand|
                email = @@shorthands[shorthand]
                next if email.nil?

                user = @@user_info[email]
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email

                wanted_shares[user_id] ||= {}
                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/#{folder_name}"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/#{pretty_folder_name}",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }
            end

            (@@schueler_for_lesson[lesson_key] || []).each do |email|
                user = @@user_info[email]
                name = user[:display_name].unicode_normalize(:nfc)
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email

                wanted_shares[user_id] ||= {}
                pretty_folder_name = "#{fach.gsub('/', '-')}"

                if pretty_folder_name.empty?
                    raise "nope: #{lesson_key}"
                end

                if @@materialamt_for_lesson[lesson_key]
                    permissions = SHARE_READ
                    if @@materialamt_for_lesson[lesson_key].include?(email)
                        permissions = SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE
                    end

                    wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/#{folder_name}/Ausgabeordner-Materialamt"] = {
                        :permissions => permissions,
                        :target_path => "/#{SHARE_TARGET_FOLDER}/#{pretty_folder_name.gsub(' ', '%20')}/Ausgabeordner%20(Dashboard-Amt)",
                        :share_with => user[:display_name].unicode_normalize(:nfc)
                    }
                end

                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/#{folder_name}/Ausgabeordner"] = {
                    :permissions => SHARE_READ,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/#{pretty_folder_name.gsub(' ', '%20')}/Ausgabeordner",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }

                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/#{folder_name}/SuS/#{name}/Einsammelordner"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/#{pretty_folder_name.gsub(' ', '%20')}/Einsammelordner",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }

                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/#{folder_name}/SuS/#{name}/Rückgabeordner"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/#{pretty_folder_name.gsub(' ', '%20')}/Rückgabeordner",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }
            end

            next
        end

        @@klassen_order.each do |klasse|
            next if klasse.to_i > 10

            (@@teachers_for_klasse[klasse] || {}).keys.each do |shorthand|
                email = @@shorthands[shorthand]
                next if email.nil?

                user = @@user_info[email]
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email

                wanted_shares[user_id] ||= {}
                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/Protokolle/#{klasse.gsub('/', '-')}"] = {
                    :permissions => SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/Protokolle #{Main.tr_klasse(klasse).gsub('/', '-')}",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }
            end

            (@@schueler_for_klasse[klasse] || []).each do |email|
                user = @@user_info[email]
                user_id = user[:nc_login]
                email_for_user_id[user_id] = email

                wanted_shares[user_id] ||= {}
                wanted_shares[user_id]["/#{SHARE_SOURCE_FOLDER}/Protokolle/#{klasse.gsub('/', '-')}"] = {
                    :permissions => schueler_with_dashboard_amt.include?(email) ? SHARE_READ | SHARE_UPDATE | SHARE_CREATE | SHARE_DELETE : SHARE_READ,
                    :target_path => "/#{SHARE_TARGET_FOLDER}/Protokolle #{Main.tr_klasse(klasse).gsub('/', '-')}",
                    :share_with => user[:display_name].unicode_normalize(:nfc)
                }
            end
        end

        wanted_shares.keys.each do |user_id|
            src_for_target_path = {}

            wanted_shares[user_id].each_pair do |src, info|
                src_for_target_path[info[:target_path]] ||= Set.new()
                src_for_target_path[info[:target_path]] << src
            end

            src_for_target_path.each_pair do |_target_path, sources|
                if sources.size > 1
                    sources_sorted = sources.to_a.sort
                    sources_sorted[1, sources_sorted.size - 1].each do |src|
                        log "SKIPPING #{src}"
                        count(:duplicate_target_sources_skipped)
                        wanted_shares[user_id].delete(src)
                    end
                end
            end

            target_paths = wanted_shares[user_id].values.map { |x| x[:target_path] }
            if target_paths.sort.uniq.size != wanted_shares[user_id].size
                raise "Ouch! We didn't catch something in the code above."
            end
        end

        wanted_nc_ids = nil
        resolved_only_user = resolve_only_user!(only_user)

        if resolved_only_user
            wanted_nc_ids = Set.new([resolved_only_user])
            log "Filtering to one user: #{resolved_only_user}"
        elsif !argv.empty?
            wanted_nc_ids = Set.new(argv.map { |email| (@@user_info[email] || {})[:nc_login] }.reject { |x| x.nil? })
            log "Filtering to #{wanted_nc_ids.size} users: #{wanted_nc_ids.to_a.sort.to_yaml}"
        end

        selected_wanted_users = wanted_shares.keys.select { |user_id| selected_user?(wanted_nc_ids, user_id) }
        set_count(:wanted_users, selected_wanted_users.size)
        set_count(:wanted_shares, selected_wanted_users.map { |user_id| wanted_shares[user_id].size }.sum)

        log "Got wanted shares for #{wanted_shares.size} users."

        present_shares = {}

        STDERR.puts "Collecting current Nextcloud shares..."
        if use_cached && File.exist?('/internal/debug/present-shares-cache.yaml')
            log "Loading present shares from cache..."
            present_shares = YAML.load(File.read('/internal/debug/present-shares-cache.yaml'))

            unless cache_has_share_types?(present_shares)
                log "Ignoring old present-shares cache because it does not contain :share_type."
                log "Rebuilding present shares from Nextcloud..."
                present_shares = collect_present_shares
            end
        else
            log "Collecting present shares... (hint: specify --use-cached to re-use data in /internal/debug/present-shares-cache.yaml)"
            present_shares = collect_present_shares
        end

        failed_share_ids = Set.new()

        if SRSLY
            STDERR.puts "Removing stale and duplicate shares..."
            log "Removing stale and duplicate shares before ensuring wanted shares..."
            present_shares = reconcile_present_shares_before_ensure!(
                wanted_shares,
                wanted_nc_ids,
                failed_share_ids
            )
        end

        File.open('/internal/debug/present-shares-cache.yaml', 'w') do |f|
            f.write present_shares.to_yaml
        end

        log "Got present shares for #{present_shares.size} users."

        File.open('/internal/debug/present-shares.yaml', 'w') do |f|
            f.write present_shares.to_yaml
        end

        File.open('/internal/debug/wanted-shares.yaml', 'w') do |f|
            f.write wanted_shares.to_yaml
        end

        STDERR.puts "Reconciling shares for #{selected_wanted_users.size} users..."
        selected_wanted_users.sort.each_with_index do |user_id, user_index|
            unless wanted_nc_ids.nil?
                log "Wanted shares for #{user_id}:"
                log wanted_shares[user_id].to_yaml
            end

            STDERR.puts "Processing user #{user_index + 1}/#{selected_wanted_users.size}: #{user_id} (#{wanted_shares[user_id].size} shares)"

            count(:users_processed)

            ocs_user = DashboardNextcloud.as_user(user_id)

            wanted_dirs = Set.new()
            wanted_shares[user_id].values.map { |x| x[:target_path] + '/' }.each do |path|
                parts = path.split('/')
                parts.each.with_index do |_part, index|
                    sub_path = parts[0, index + 1].join('/') + '/'
                    wanted_dirs << normalize_nc_path(sub_path) unless sub_path == '/'
                end
            end

            result = []
            begin
                result = ocs_user.webdav.directory.find("/#{SHARE_TARGET_FOLDER}").contents
            rescue NoMethodError => e
                debug_log "Could not list /#{SHARE_TARGET_FOLDER} for #{user_id}: #{e.class}: #{e.message}"
            rescue StandardError => e
                debug_log "Could not list /#{SHARE_TARGET_FOLDER} for #{user_id}: #{e.class}: #{e.message}"
            end

            (result || []).each do |dir|
                unless dir.href.index("/remote.php/dav/files/#{user_id}") == 0
                    error "Got unexpected dir while cleaning target folders for #{user_id}", {
                        :user_id => user_id,
                        :href => dir.href
                    }
                    next
                end

                next unless dir.resourcetype == 'collection'

                path = dir.href.sub("/remote.php/dav/files/#{user_id}", '')
                path = normalize_nc_path(path)

                if wanted_dirs.include?(path)
                    count(:target_folders_already_wanted)
                else
                    begin
                        dir2 = ocs_user.webdav.directory.find(path.gsub(' ', '%20'))
                        contents_count = (dir2.contents || []).size
                        just_unterricht_shares = true

                        (dir2.contents || []).each do |x|
                            href = x.href
                            unless ['/Ausgabeordner/',
                                    '/Einsammelordner/',
                                    '/R%c3%bcckgabeordner/',
                                    '/Ausgabeordner%20(Dashboard-Amt)/',
                                    '/Auto-Einsammelordner%20(von%20SuS%20an%20mich)/',
                                    'Auto-R%c3%bcckgabeordner%20(von%20mir%20an%20SuS)/',
                                    '/SuS/'].any? { |y| href[href.size - y.size, y.size] == y }
                                just_unterricht_shares = false
                            end
                        end

                        if contents_count == 0 || just_unterricht_shares
                            log "DELETING [#{user_id}]#{path}"
                            if SRSLY
                                ocs_user.webdav.directory.destroy(path.gsub(' ', '%20'))
                                count(:target_folders_deleted)
                            else
                                count(:target_folders_would_delete)
                            end
                        else
                            log "KEEPING [#{user_id}]#{path} because it has #{contents_count} files."
                            count(:target_folders_kept_nonempty)
                        end
                    rescue StandardError => e
                        count(:target_folder_cleanup_errors)
                        error "Could not inspect/delete [#{user_id}]#{path}: #{e.class}: #{e.message}", e.backtrace.first(10).join("\n")
                    end
                end
            end

            created_sub_paths = Set.new()

            wanted_shares[user_id].each_pair do |path, info|
                existing_share_info = (present_shares[user_id] || {})[path]

                unless SRSLY
                    log "Would ensure share: #{path} => #{user_id}"
                    count(:shares_would_ensure)
                    next
                end

                begin
                    created_now = false
                    recreated_from_stale_cache = false

                    created_share = nil

                    unless existing_share_info
                        log "Sharing #{path} to [#{user_id}]..."
                        created_share = create_user_share(@ocs, path, user_id, info[:permissions])
                        count(:shares_created)
                        created_now = true
                    end

                    shares = created_share ? [created_share] : user_shares_for_path(path, user_id)

                    if shares.empty? && existing_share_info
                        log "Existing share info for #{path} to [#{user_id}] looked stale; creating share again..."
                        recreated_share = create_user_share(@ocs, path, user_id, info[:permissions])
                        count(:shares_recreated_from_stale_cache)
                        recreated_from_stale_cache = true
                        shares = [recreated_share]
                    end

                    if shares.size > 1
                        shares = deduplicate_present_share_records!(
                            path,
                            user_id,
                            info[:target_path],
                            failed_share_ids
                        )

                        # If removing one duplicate failed, do not attempt a MOVE
                        # while multiple mounts for the same source remain.
                        next if shares.nil?
                    end

                    if shares.size != 1
                        error "Could not find exactly one user share of #{path} to [#{user_id}]", shares
                        failed_share_ids << existing_share_info[:id] if existing_share_info && existing_share_info[:id]
                        next
                    end

                    share = shares.first

                    if @debug_shares
                        STDERR.puts
                        STDERR.puts "DEBUG SHARE"
                        STDERR.puts "  user:              #{user_id}"
                        STDERR.puts "  source path:       #{path}"
                        STDERR.puts "  share id:          #{share['id']}"
                        STDERR.puts "  share_type:        #{share['share_type']}"
                        STDERR.puts "  current target:    #{share['file_target'].inspect}"
                        STDERR.puts "  wanted target:     #{info[:target_path].inspect}"
                        STDERR.puts "  current decoded:   #{normalize_nc_path(share['file_target']).inspect}"
                        STDERR.puts "  wanted decoded:    #{normalize_nc_path(info[:target_path]).inspect}"
                        STDERR.puts "  current perms:     #{share['permissions']}"
                        STDERR.puts "  wanted perms:      #{info[:permissions]}"
                    end

                    permissions_updated = false
                    moved = false

                    if share['permissions'].to_i != info[:permissions]
                        log "Updating permissions [#{user_id}]#{share['file_target']}..."
                        @ocs.file_sharing.update_permissions(share['id'], info[:permissions])
                        count(:permissions_updated)
                        permissions_updated = true
                    end

                    if !same_nc_path?(share['file_target'], info[:target_path])
                        unless create_parent_directories_raw!(user_id, info[:target_path], created_sub_paths)
                            failed_share_ids << share['id']
                            next
                        end

                        unless verify_parent_directory_raw!(user_id, info[:target_path])
                            failed_share_ids << share['id']
                            next
                        end

                        # When an existing share differs from the wanted target only
                        # by canonical spelling (notably a legacy trailing slash),
                        # the DAV destination is this share's own mount. In that case
                        # it is safe to let Nextcloud rewrite file_target in place
                        # instead of rejecting the destination as already mounted.
                        canonicalization_only = DashboardNextcloud.canonical_share_target(share['file_target']) ==
                                                DashboardNextcloud.canonical_share_target(info[:target_path])

                        unless canonicalization_only || share_move_target_free?(user_id, info[:target_path])
                            failed_share_ids << share['id']
                            next
                        end

                        log "NATIVE SHARE MOVE [#{user_id}]#{share['file_target']} -> #{info[:target_path]}..."
                        begin
                            move_result = native_share_move!(share, user_id, info[:target_path])
                            debug_log "NATIVE SHARE MOVE RESULT:"
                            debug_log move_result.to_yaml
                        rescue StandardError => e
                            error "Native share move failed for [#{user_id}]#{share['file_target']} -> #{info[:target_path]}: #{e.class}: #{e.message}",
                                  e.backtrace.first(10).join("\n")
                            failed_share_ids << share['id']
                            next
                        end

                        unless verify_share_target_after_move(path, user_id, share['id'], info[:target_path])
                            failed_share_ids << share['id']
                            next
                        end

                        count(:shares_moved)
                        moved = true
                    else
                        debug_log "  move needed:       no"
                    end

                    if existing_share_info && !created_now && !recreated_from_stale_cache && !permissions_updated && !moved
                        count(:shares_already_correct)
                    end
                rescue StandardError => e
                    error "Error while processing share #{path} for #{user_id}: #{e.class}: #{e.message}", e.backtrace.first(10).join("\n")
                    failed_share_ids << existing_share_info[:id] if existing_share_info && existing_share_info[:id]
                end
            end
        end

        present_shares.keys.sort.each do |user_id|
            unless wanted_nc_ids.nil?
                next unless wanted_nc_ids.include?(user_id)
            end

            present_shares[user_id].each_pair do |path, info|
                next if (wanted_shares[user_id] || {})[path]

                log "Removing share #{path} for #{user_id}..."
                if SRSLY
                    begin
                        @ocs.file_sharing.destroy(info[:id])
                        count(:shares_removed)
                    rescue StandardError => e
                        error "Could not remove stale share #{path} for #{user_id}, share id #{info[:id]}: #{e.class}: #{e.message}", e.backtrace.first(10).join("\n")
                        failed_share_ids << info[:id]
                    end
                else
                    count(:shares_would_remove)
                end
            end
        end

        unless failed_share_ids.empty?
            error "Failed share IDs", failed_share_ids.to_a.sort.join("\n")
        end

        print_summary(failed_share_ids)

        @errors.empty?
    end
end

begin
    script = Script.new
    ok = script.run
    exit(ok ? 0 : 1)
rescue StandardError => e
    STDERR.puts "ERROR: #{e.class}: #{e.message}"
    STDERR.puts e.backtrace.first(10).join("\n")
    exit(1)
end
