#!/usr/bin/env ruby
require './main.rb'
require 'cgi'
require 'json'
require 'net/http'
require 'nokogiri'
require 'set'
require 'thread'
require 'uri'

class Script
    DAV_NAMESPACES = {
        'd' => 'DAV:',
        'oc' => 'http://owncloud.org/ns'
    }.freeze

    DEFAULT_JOBS = 8

    class WebdavSession
        def initialize
            @base_uri = URI(NEXTCLOUD_URL_FROM_RUBY_CONTAINER)
            connect
        end

        def request(request)
            @http.request(request)
        rescue EOFError, IOError, Errno::ECONNRESET, Errno::EPIPE
            reconnect
            @http.request(request)
        end

        def close
            @http.finish if @http&.started?
        rescue IOError
            nil
        end

        private

        def connect
            @http = Net::HTTP.new(@base_uri.host, @base_uri.port)
            @http.use_ssl = @base_uri.scheme == 'https'
            @http.read_timeout = DashboardNextcloud::HTTP_READ_TIMEOUT
            @http.start
        end

        def reconnect
            close
            connect
        end
    end

    def initialize
        @admin = DashboardNextcloud.admin
        @user_info = Main.class_variable_get(:@@user_info)
        @users_for_role = Main.class_variable_get(:@@users_for_role)

        @json_path = nil
        @only_user = nil
        @only_klasse = nil
        @show_all_users = false
        @root_only = false
        @jobs = DEFAULT_JOBS
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

    def parse_options!
        argv = ARGV.dup

        @json_path = take_option!(argv, '--json')
        @only_user = take_option!(argv, '--only-user')
        @only_klasse = take_option!(argv, '--klasse')
        jobs = take_option!(argv, '--jobs')
        @jobs = Integer(jobs, 10) unless jobs.nil?
        @show_all_users = !argv.delete('--all-users').nil?
        @root_only = !argv.delete('--root-only').nil?

        raise '--jobs must be at least 1' if @jobs < 1

        unless argv.empty?
            raise "Unknown arguments: #{argv.join(' ')}"
        end
    end

    def normalize_path(path)
        decoded = CGI.unescape(path.to_s).unicode_normalize(:nfc)
        decoded = "/#{decoded}" unless decoded.start_with?('/')
        decoded = decoded.sub(%r{/+\z}, '') unless decoded == '/'
        decoded.empty? ? '/' : decoded
    end

    def human_size(bytes)
        return '-' if bytes.nil?

        value = bytes.to_f
        units = %w[B KiB MiB GiB TiB]
        unit = units.shift

        while value >= 1024 && !units.empty?
            value /= 1024.0
            unit = units.shift
        end

        if unit == 'B'
            "#{value.to_i} #{unit}"
        elsif value >= 100
            format('%.0f %s', value, unit)
        elsif value >= 10
            format('%.1f %s', value, unit)
        else
            format('%.2f %s', value, unit)
        end
    end

    def raw_propfind(session, user_id, path, depth: 1)
        uri = DashboardNextcloud.dav_uri(user_id, path)

        body = <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
              <d:prop>
                <d:displayname/>
                <d:resourcetype/>
                <d:getcontentlength/>
                <d:getlastmodified/>
                <d:getetag/>
                <oc:size/>
                <oc:permissions/>
                <oc:fileid/>
              </d:prop>
            </d:propfind>
        XML

        request = Net::HTTPGenericRequest.new('PROPFIND', true, true, uri.request_uri)
        request.basic_auth user_id, NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL
        request['Depth'] = depth.to_s
        request['Content-Type'] = 'application/xml; charset=utf-8'
        request.body = body

        response = session.request(request)

        unless response.code.to_i == 207
            raise "PROPFIND #{path.inspect} for #{user_id} failed: HTTP #{response.code} #{response.message}"
        end

        response.body
    end

    def prop_text(prop, xpath)
        prop.at_xpath(xpath, DAV_NAMESPACES)&.text
    end

    def response_path(user_id, href)
        uri = URI.parse(href)
        href_path = uri.path
        root_path = DashboardNextcloud.dav_uri(user_id, '/').path

        unless href_path.start_with?(root_path)
            raise "Unexpected WebDAV href for #{user_id}: #{href.inspect}"
        end

        relative = href_path[root_path.length..] || ''
        normalize_path("/#{relative}")
    end

    def parse_propfind(user_id, xml)
        doc = Nokogiri::XML(xml)

        doc.xpath('//d:response', DAV_NAMESPACES).filter_map do |response|
            href = response.at_xpath('./d:href', DAV_NAMESPACES)&.text
            next if href.nil?

            prop = response.at_xpath('./d:propstat[d:status[contains(., " 200 ")]]/d:prop', DAV_NAMESPACES)
            next if prop.nil?

            path = response_path(user_id, href)
            directory = !prop.at_xpath('./d:resourcetype/d:collection', DAV_NAMESPACES).nil?

            size_text = prop_text(prop, './oc:size')
            size_text = prop_text(prop, './d:getcontentlength') if size_text.nil? || size_text.empty?

            {
                path: path,
                name: path == '/' ? '/' : File.basename(path),
                type: directory ? 'directory' : 'file',
                size: size_text.to_s.empty? ? nil : size_text.to_i,
                last_modified: prop_text(prop, './d:getlastmodified'),
                etag: prop_text(prop, './d:getetag'),
                permissions: prop_text(prop, './oc:permissions'),
                fileid: prop_text(prop, './oc:fileid')
            }
        end
    end

    def list_directory(session, user_id, path)
        wanted = normalize_path(path)

        parse_propfind(user_id, raw_propfind(session, user_id, wanted, depth: 1)).reject do |entry|
            entry[:path] == wanted
        end.sort_by do |entry|
            [entry[:type] == 'file' ? 1 : 0, entry[:name].downcase]
        end
    end

    def share_mounts
        result = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = [] } }

        (@admin.file_sharing.all || []).each do |share|
            next unless share['share_type'].to_i == 0

            user_id = share['share_with']
            target = share['file_target']
            next if user_id.nil? || target.nil?

            result[user_id][normalize_path(target)] << {
                id: share['id'].to_s,
                source: normalize_path(share['path']),
                permissions: share['permissions'].to_i
            }
        end

        result
    end

    def selected_users
        emails =
            if @show_all_users
                @user_info.keys
            else
                (@users_for_role[:schueler] || Set.new).to_a
            end

        if @only_klasse
            emails = emails.select do |email|
                info = @user_info[email] || {}
                info[:klasse].to_s == @only_klasse
            end
        end

        if @only_user
            emails = emails.select do |email|
                info = @user_info[email] || {}
                email == @only_user || info[:nc_login].to_s == @only_user
            end
        end

        emails.sort_by do |email|
            info = @user_info[email] || {}
            [info[:klasse].to_s, info[:display_name].to_s, email]
        end
    end

    def share_marker(entry, mounts)
        shares = mounts[entry[:path]]
        return nil if shares.nil? || shares.empty?

        if entry[:path].split('/').reject(&:empty?).size == 1 && entry[:path] != '/Unterricht'
            'ROOT SHARE'
        else
            'SHARE'
        end
    end

    def decorated_entry(entry, mounts)
        result = entry.dup
        shares = mounts[entry[:path]] || []
        result[:shares] = shares
        result[:warning] = share_marker(entry, mounts)
        result
    end

    def scan_tree(session, user_id, path, mounts, seen_fileids = Set.new)
        entries = list_directory(session, user_id, path)

        entries.map do |entry|
            item = decorated_entry(entry, mounts)

            if entry[:type] == 'directory'
                if entry[:fileid] && seen_fileids.include?(entry[:fileid])
                    item[:cycle] = true
                else
                    next_seen = seen_fileids.dup
                    next_seen << entry[:fileid] unless entry[:fileid].nil?
                    begin
                        item[:children] = scan_tree(session, user_id, entry[:path], mounts, next_seen)
                    rescue StandardError => e
                        item[:children_error] = "#{e.class}: #{e.message}"
                    end
                end
            end

            item
        end
    end

    def print_entry(entry, indent: 0)
        marker =
            case entry[:warning]
            when 'ROOT SHARE'
                '  <<< ROOT SHARE'
            when 'SHARE'
                '  [share]'
            else
                ''
            end

        suffix = entry[:type] == 'directory' ? '/' : ''
        puts "#{'  ' * indent}#{entry[:name]}#{suffix.ljust(2)} #{human_size(entry[:size]).rjust(10)}#{marker}"

        (entry[:shares] || []).each do |share|
            puts "#{'  ' * (indent + 1)}share ##{share[:id]} from #{share[:source]}"
        end

        if entry[:cycle]
            puts "#{'  ' * (indent + 1)}[already visited]"
        elsif entry[:children_error]
            puts "#{'  ' * (indent + 1)}[ERROR: #{entry[:children_error]}]"
        else
            (entry[:children] || []).each do |child|
                print_entry(child, indent: indent + 1)
            end
        end
    end

    def scan_user(session, email, mounts_by_user)
        info = @user_info.fetch(email)
        user_id = info[:nc_login]
        mounts = mounts_by_user[user_id]

        root_entries = list_directory(session, user_id, '/').map do |entry|
            decorated_entry(entry, mounts)
        end

        unterricht_entry = root_entries.find { |entry| entry[:path] == '/Unterricht' }

        unterricht_tree =
            if !@root_only && unterricht_entry && unterricht_entry[:type] == 'directory'
                scan_tree(session, user_id, '/Unterricht', mounts)
            else
                []
            end

        root_share_warnings = root_entries.select { |entry| entry[:warning] == 'ROOT SHARE' }

        {
            email: email,
            nc_login: user_id,
            display_name: info[:display_name],
            klasse: info[:klasse],
            root_share_warnings: root_share_warnings.map { |entry| entry[:path] },
            root: root_entries,
            unterricht: unterricht_tree
        }
    end

    def print_user(result)
        puts
        puts '=' * 80
        puts "#{result[:display_name]}  [#{result[:nc_login]}]  #{result[:klasse]}"
        puts result[:email]
        puts

        if result[:error]
            puts "ERROR: #{result[:error]}"
            return
        end

        root_share_warnings = result[:root_share_warnings] || []
        root_entries = result[:root] || []
        unterricht_entry = root_entries.find { |entry| entry[:path] == '/Unterricht' }

        if root_share_warnings.empty?
            puts 'Top level:'
        else
            puts "Top level:  WARNING: #{root_share_warnings.size} shared folder(s) mounted outside /Unterricht"
        end

        root_entries.each do |entry|
            print_entry(entry)
        end

        puts
        if unterricht_entry.nil?
            puts 'Unterricht/: MISSING'
        elsif unterricht_entry[:type] != 'directory'
            puts 'Unterricht/: NOT A DIRECTORY'
        elsif @root_only
            puts 'Unterricht/ tree: skipped (--root-only)'
        else
            puts 'Unterricht/ tree:'
            (result[:unterricht] || []).each do |entry|
                print_entry(entry, indent: 1)
            end
        end
    end

    def scan_users(emails, mounts_by_user)
        results = Array.new(emails.size)
        queue = Queue.new
        emails.each_with_index { |email, index| queue << [index, email] }

        worker_count = [@jobs, emails.size].min
        worker_count.times { queue << :stop }

        progress_mutex = Mutex.new
        completed = 0

        sessions = Array.new(worker_count) { WebdavSession.new }

        workers = sessions.map do |session|
            Thread.new do
                loop do
                    item = queue.pop
                    break if item == :stop

                    index, email = item
                    result =
                        begin
                            scan_user(session, email, mounts_by_user)
                        rescue StandardError => e
                            info = @user_info[email] || {}
                            {
                                email: email,
                                nc_login: info[:nc_login],
                                display_name: info[:display_name],
                                klasse: info[:klasse],
                                error: "#{e.class}: #{e.message}"
                            }
                        end

                    results[index] = result

                    progress_mutex.synchronize do
                        completed += 1
                        if result[:error]
                            STDERR.puts "[#{completed}/#{emails.size}] ERROR #{email}: #{result[:error]}"
                        else
                            STDERR.puts "[#{completed}/#{emails.size}] #{email}"
                        end
                    end
                end
            end
        end

        workers.each(&:join)
        results
    ensure
        (sessions || []).each(&:close)
    end

    def run
        parse_options!

        emails = selected_users
        if emails.empty?
            raise 'No matching users.'
        end

        STDERR.puts "Read-only Nextcloud scan of #{emails.size} user(s), #{@jobs} worker(s)."
        STDERR.puts 'No files, folders or shares will be changed.'
        STDERR.puts 'Scanning top level only.' if @root_only

        mounts_by_user = share_mounts
        results = scan_users(emails, mounts_by_user)

        results.each do |result|
            print_user(result)
        end

        if @json_path
            File.write(@json_path, JSON.pretty_generate(results))
            STDERR.puts "Wrote #{@json_path}"
        end

        problem_users = results.select do |result|
            !result[:error].nil? || !(result[:root_share_warnings] || []).empty?
        end

        STDERR.puts
        STDERR.puts "Summary: #{results.size} scanned, #{problem_users.size} with errors or root-level shares."

        problem_users.each do |result|
            details =
                if result[:error]
                    result[:error]
                else
                    result[:root_share_warnings].join(', ')
                end
            STDERR.puts "  #{result[:nc_login]}: #{details}"
        end
    end
end

Script.new.run
