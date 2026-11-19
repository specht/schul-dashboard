class Main < Sinatra::Base
    post '/api/upload_file' do
        require_user_who_can_upload_files!
        filename = params['filename']
        assert(!filename.include?('/'))
        assert(filename.size > 0)
        entry = params['file']
        blob = entry['tempfile'].read
        path = "/raw/uploads/files/#{filename}"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        respond(:uploaded => 'yeah')
    end

    post '/api/delete_file' do
        require_user_who_can_upload_files!
        data = parse_request_data(:required_keys => [:filename])
        filename = data[:filename]
        assert(!filename.include?('/'))
        assert(filename.size > 0)
        FileUtils::rm_f("/raw/uploads/files/#{filename}")
        respond(:deleted => 'yeah')
    end

    post '/api/get_all_files' do
        require_user_who_can_upload_files!
        files = []
        Dir['/raw/uploads/files/*'].each do |path|
            files << {
                :name => File.basename(path),
                :size => File.size(path),
                :timestamp => File.mtime(path)
            }
        end
        files.sort! { |a, b| a[:name].downcase <=> b[:name].downcase }
        respond(:files => files)
    end

    # Address ranges the server never fetches from on behalf of a user: the
    # Docker network with the database and the bots, loopback, link-local
    # (cloud metadata) and other non-public ranges.
    BLOCKED_FETCH_RANGES = %w(
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
        172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/3
        ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
    ).map { |x| IPAddr.new(x) }
    MAX_FETCHED_FILE_SIZE = 32 * 1024 * 1024

    # Fetches a public http(s) address without following redirects and
    # returns [HTTP status, body]. The host is resolved once, every address
    # is checked, and curl connects to exactly the checked address. A class
    # method, so that the timetable service can use it too (ical_import.rb).
    def fetch_public_uri(uri_string)
        Main.fetch_public_uri(uri_string)
    end

    def self.fetch_public_uri(uri_string, max_size = MAX_FETCHED_FILE_SIZE)
        uri = URI.parse(uri_string.to_s) rescue nil
        assert(uri.is_a?(URI::HTTP) && !uri.hostname.to_s.empty?, 'invalid uri')
        addresses = (Addrinfo.getaddrinfo(uri.hostname, uri.port, nil, :STREAM) rescue []).map do |a|
            IPAddr.new(a.ip_address.sub(/%.*\z/, '')).native
        end.uniq
        assert(!addresses.empty?, 'unknown host')
        addresses.each do |ip|
            assert(BLOCKED_FETCH_RANGES.none? { |range| range.include?(ip) }, 'address not allowed')
        end
        address = addresses.find(&:ipv4?) || addresses.first
        c = Curl::Easy.new(uri.to_s)
        c.resolve = ["#{uri.hostname}:#{uri.port}:#{address.ipv6? ? "[#{address}]" : address}"]
        c.follow_location = false
        c.connect_timeout = 10
        c.timeout = 60
        body = String.new
        c.on_body do |chunk|
            body << chunk
            # a different count aborts the transfer
            body.bytesize > max_size ? 0 : chunk.bytesize
        end
        c.perform
        [c.response_code, body]
    end

    post '/api/upload_file_via_uri' do
        require_user_who_can_upload_files!
        data = parse_request_data(:required_keys => [:uri])
        uri = URI.parse(data[:uri]) rescue nil
        assert(uri.is_a?(URI::HTTP), 'invalid uri')
        nextcloud_host = (URI.parse(NEXTCLOUD_URL).hostname rescue nil)
        if nextcloud_host && uri.hostname == nextcloud_host
            # a Nextcloud share page: the file itself is linked on the page
            status, body = fetch_public_uri(uri.to_s)
            if status == 200
                dom = Nokogiri::HTML.parse(body)
                link = dom.css('#downloadURL').first || dom.css('#previewURL').first
                name = dom.css('#filename').first
                assert(!link.nil? && !name.nil?)
                status, body = fetch_public_uri(link.get_attribute('value'))
                if status == 200
                    respond(:filename => name.get_attribute('value'), :body => Base64::strict_encode64(body), :size => body.size)
                    return
                end
            end
        else
            filename = CGI.unescape(File.basename(uri.path.to_s))
            status, body = fetch_public_uri(uri.to_s)
            if status == 200
                respond(:filename => filename, :body => Base64::strict_encode64(body), :size => body.size)
                return
            end
        end
        raise 'nope'
    end
end
