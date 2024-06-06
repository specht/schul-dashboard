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

    post '/api/upload_file_via_uri' do
        require_user_who_can_upload_files!
        data = parse_request_data(:required_keys => [:uri])
        uri = data[:uri]
        STDERR.puts uri
        if uri.include?(NEXTCLOUD_URL)
            c = Curl::Easy.new(uri)
            c.perform
            if c.status == '200'
                dom = Nokogiri::HTML.parse(c.body_str)
                uri2 = nil
                begin
                    uri2 = dom.css('#downloadURL').first.get_attribute('value')
                rescue
                    uri2 = dom.css('#previewURL').first.get_attribute('value')
                end
                assert(!(uri2.nil?))
                filename = dom.css('#filename').first.get_attribute('value')
                STDERR.puts uri2
                STDERR.puts filename
                c2 = Curl::Easy.new(uri2)
                c2.perform
                if c2.status == '200'
                    respond(:filename => filename, :body => Base64::strict_encode64(c2.body_str), :size => c2.body_str.size)
                    return
                end
            end
        else
            filename = CGI.unescape(File.basename(URI.parse(uri).path))
            c = Curl::Easy.new(uri)
            c.perform
            if c.status == '200'
                respond(:filename => filename, :body => Base64::strict_encode64(c.body_str), :size => c.body_str.size)
                return
            end
        end
        raise 'nope'
    end
end
