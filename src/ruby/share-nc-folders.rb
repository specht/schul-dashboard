#!/usr/bin/env ruby
require './main.rb'
require './parser.rb'
require 'set'
require 'zlib'
require 'fileutils'
require 'nextcloud'
require 'cgi'
require 'yaml'
require 'zip'
require 'uri'
require 'net/http'

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

HTTP_READ_TIMEOUT = 60 * 10

# This is a really ugly way to monkey patch an increased HTTP read timeout into the dachinat/nextcloud gem.
# We still use the gem for OCS share handling, but not for the fragile WebDAV MKCOL/MOVE calls.

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

            raw ? response.body : Nokogiri::XML.parse(response.body)
        end
    end
end

class Script
    def initialize
        @ocs = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                             username: NEXTCLOUD_USER,
                             password: NEXTCLOUD_PASSWORD)

        @verbose = false
        @debug_shares = false
        @errors = []
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
        CGI.unescape(path.to_s).unicode_normalize(:nfc)
    end

    def same_nc_path?(a, b)
        normalize_nc_path(a) == normalize_nc_path(b)
    end

    def dav_escape_segment(segment)
        CGI.escape(CGI.unescape(segment.to_s).unicode_normalize(:nfc)).gsub('+', '%20')
    end

    def dav_escape_path(path)
        decoded = normalize_nc_path(path)
        decoded = "/#{decoded}" unless decoded.start_with?('/')

        decoded.split('/').map { |part| dav_escape_segment(part) }.join('/')
    end

    def dav_uri_for(user_id, path)
        base = URI(NEXTCLOUD_URL_FROM_RUBY_CONTAINER)
        base_path = base.path.to_s.sub(/\/+\z/, '')

        uri = base.dup
        uri.query = nil
        uri.fragment = nil
        uri.path = "#{base_path}/remote.php/dav/files/#{dav_escape_segment(user_id)}#{dav_escape_path(path)}"

        uri
    end

    def raw_webdav_request(user_id, method, path, destination_path: nil, depth: nil)
        uri = dav_uri_for(user_id, path)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
            http.read_timeout = HTTP_READ_TIMEOUT

            req = Net::HTTPGenericRequest.new(method.to_s.upcase, false, true, uri.request_uri)
            req.basic_auth user_id, NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL
            req['Depth'] = depth.to_s unless depth.nil?

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

        dir_parts.each.with_index do |p, index|
            sub_path = dir_parts[0, index + 1].join('/')
            next if sub_path.empty?

            normalized = normalize_nc_path(sub_path)
            next if created_sub_paths.include?(normalized)

            log "RAW MKCOL/check [#{user_id}]#{sub_path}..."
            result = raw_mkcol(user_id, sub_path)

            debug_log "RAW MKCOL RESULT:"
            debug_log result.to_yaml

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

        true
    end

    def verify_share_target_after_move(path, user_id, share_id, wanted_target)
        shares_after_move = user_shares_for_path(path, user_id)
        share_after_move = shares_after_move.find { |x| x['id'].to_s == share_id.to_s }

        if @debug_shares
            STDERR.puts "AFTER MOVE CHECK:"
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
            error "Could not verify share after MOVE: share disappeared from OCS result. User: #{user_id}, source: #{path}, share id: #{share_id}"
            return false
        end

        unless same_nc_path?(share_after_move['file_target'], wanted_target)
            error "MOVE returned success, but file_target did not change as expected. User: #{user_id}, source: #{path}, share id: #{share_id}", {
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
        ocs.request(:post, '/ocs/v2.php/apps/files_sharing/api/v1/shares', {
            'path' => path,
            'shareType' => 0,
            'shareWith' => user_id,
            'permissions' => permissions,
            'sendMail' => 'false'
        })
    end

    def user_shares_for_path(path, user_id)
        (@ocs.file_sharing.specific(path.gsub(' ', '%20')) || []).select do |share|
            share['share_type'].to_i == 0 && share['share_with'] == user_id
        end
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

        (@ocs.file_sharing.all || []).each do |share|
            next if share['share_with'].nil?
            next unless share['share_type'].to_i == 0
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

            src_for_target_path.each_pair do |target_path, sources|
                if sources.size > 1
                    sources_sorted = sources.to_a.sort
                    sources_sorted[1, sources_sorted.size - 1].each do |src|
                        log "SKIPPING #{src}"
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

        log "Got wanted shares for #{wanted_shares.size} users."

        present_shares = {}

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

        failed_share_ids = Set.new()

        wanted_shares.keys.sort.each do |user_id|
            unless wanted_nc_ids.nil?
                next unless wanted_nc_ids.include?(user_id)
                log "Wanted shares for #{user_id}:"
                log wanted_shares[user_id].to_yaml
            end

            ocs_user = Nextcloud.ocs(url: NEXTCLOUD_URL_FROM_RUBY_CONTAINER,
                                     username: user_id,
                                     password: NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL)

            wanted_dirs = Set.new()
            wanted_shares[user_id].values.map { |x| x[:target_path] + '/' }.each do |path|
                parts = path.split('/')
                parts.each.with_index do |part, index|
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
                    return false
                end

                next unless dir.resourcetype == 'collection'

                path = dir.href.sub("/remote.php/dav/files/#{user_id}", '')
                path = normalize_nc_path(path)

                if wanted_dirs.include?(path)
                    # ok
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
                            end
                        else
                            log "KEEPING [#{user_id}]#{path} because it has #{contents_count} files."
                        end
                    rescue StandardError => e
                        error "Could not inspect/delete [#{user_id}]#{path}: #{e.class}: #{e.message}", e.backtrace.first(10).join("\n")
                    end
                end
            end

            created_sub_paths = Set.new()

            wanted_shares[user_id].each_pair do |path, info|
                existing_share_info = (present_shares[user_id] || {})[path]

                unless SRSLY
                    log "Would ensure share: #{path} => #{user_id}"
                    next
                end

                begin
                    unless existing_share_info
                        log "Sharing #{path} to [#{user_id}]..."
                        create_user_share(@ocs, path, user_id, info[:permissions])
                    end

                    shares = user_shares_for_path(path, user_id)

                    if shares.empty? && existing_share_info
                        log "Existing share info for #{path} to [#{user_id}] looked stale; creating share again..."
                        create_user_share(@ocs, path, user_id, info[:permissions])
                        shares = user_shares_for_path(path, user_id)
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

                    if share['permissions'].to_i != info[:permissions]
                        log "Updating permissions [#{user_id}]#{share['file_target']}..."
                        @ocs.file_sharing.update_permissions(share['id'], info[:permissions])
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

                        log "RAW MOVE [#{user_id}]#{share['file_target']} -> #{info[:target_path]}..."
                        move_result = raw_move(user_id, share['file_target'], info[:target_path])

                        debug_log "RAW MOVE RESULT:"
                        debug_log move_result.to_yaml

                        unless move_result[:ok]
                            error "RAW MOVE failed for [#{user_id}]#{share['file_target']} -> #{info[:target_path]}", move_result
                            failed_share_ids << share['id']
                            next
                        end

                        unless verify_share_target_after_move(path, user_id, share['id'], info[:target_path])
                            failed_share_ids << share['id']
                            next
                        end
                    else
                        debug_log "  move needed:       no"
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
                    rescue StandardError => e
                        error "Could not remove stale share #{path} for #{user_id}, share id #{info[:id]}: #{e.class}: #{e.message}", e.backtrace.first(10).join("\n")
                        failed_share_ids << info[:id]
                    end
                end
            end
        end

        unless failed_share_ids.empty?
            error "Failed share IDs", failed_share_ids.to_a.sort.join("\n")
        end

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