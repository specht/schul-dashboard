class Main < Sinatra::Base
    post '/api/upload_vplan' do
        require_user_who_can_upload_vplan!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        path = "/vplan/#{DateTime.now.strftime('%Y-%m-%dT%H-%M-%S')}.txt.tmp"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        found_error = false
        File.open(path, 'r:' + VPLAN_ENCODING) do |f|
            f.each_line do |line|
                next if line.strip.empty?
                line = line.encode('utf-8')
                parts = line.split("\t")
                if parts.size != 22
                    found_error = true
                    break
                end
            end
        end
        
        if found_error
            FileUtils::rm(path)
            respond(:error => true, :error_message => 'Falsches Dateiformat!')
            return
        end
        FileUtils.mv(path, path.sub('.txt.tmp', '.txt'))
        trigger_update('all')
        respond(:uploaded => 'yeah')
    end

    post '/api/upload_vplan_html' do
        require_user_who_can_upload_vplan!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile']
        mtime = blob.mtime
        contents = blob.read
        contents = contents.force_encoding('iso-8859-1').encode('utf-8')
        STDERR.puts contents.encoding
        STDERR.puts mtime

        dom = Nokogiri::HTML.parse(contents)
        head = dom.css('.mon_head').to_s 
        m = head.match(/Stand: (\d+\.\d+\.\d+)\s+(\d+:\d+)/)
        d = m[1]
        t = m[2]
        valid_from = d.split('.').map { |x| x.to_i }.reverse.map.with_index { |x, i| sprintf("%0#{i == 0 ? 4 : 2}d", x) }.join('-')
        valid_from += "T#{t}:00"
        STDERR.puts valid_from

        # path = "/vplan/#{DateTime.now.strftime('%Y-%m-%dT%H-%M-%S')}.txt.tmp"
        # File.open(path, 'w') do |f|
        #     f.write(blob)
        # end
        # found_error = false
        # File.open(path, 'r:' + VPLAN_ENCODING) do |f|
        #     f.each_line do |line|
        #         next if line.strip.empty?
        #         line = line.encode('utf-8')
        #         parts = line.split("\t")
        #         if parts.size != 22
        #             found_error = true
        #             break
        #         end
        #     end
        # end
        
        # if found_error
        #     FileUtils::rm(path)
        #     respond(:error => true, :error_message => 'Falsches Dateiformat!')
        #     return
        # end
        # FileUtils.mv(path, path.sub('.txt.tmp', '.txt'))
        # trigger_update('all')
        # respond(:uploaded => 'yeah')
    end
    
    post '/api/delete_vplan' do
        require_user_who_can_upload_vplan!
        
        data = parse_request_data(:required_keys => [:timestamp])
        timestamp = data[:timestamp].gsub(':', '-')
        
        assert(timestamp =~ /^[0-9]{4}\-[0-9]{2}\-[0-9]{2}T[0-9]{2}\-[0-9]{2}\-[0-9]{2}$/)
        
        path = "/vplan/#{timestamp}.txt"
        if File::exists?(path)
            latest_vplan = Dir['/vplan/*.txt'].sort.last
            FileUtils::rm(path)
            if latest_vplan 
                if File.basename(latest_vplan).sub('.txt', '') == timestamp
                    trigger_update('all')
                end
            end
        end

        respond(:deleted => 'yeah')
    end
    
    post '/api/get_vplan_list' do
        require_user_who_can_upload_vplan!
        entries = []
        Dir['/vplan/*.txt'].sort.reverse.each do |path|
            contents = nil
            File.open(path, 'r:iso-8859-1') do |f|
                contents = f.read
            end
            timestamp = File.basename(path).split('.').first.split('T')
            timestamp[1].gsub!('-', ':')
            timestamp = timestamp.join('T')
            entries << {
                :timestamp => timestamp,
                :size => File::size(path),
                :lines => contents.split("\n").size
            }
        end
        respond(:entries => entries)
    end
end
