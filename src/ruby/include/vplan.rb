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

    def parse_html_datum(s)
        parts = s.split('.')
        d = parts[0].to_i
        m = parts[1].to_i
        _ = @@config[:first_school_day][0, 4].to_i
        (_ .. (_ + 1)).each do |y|
            ds = sprintf('%04d-%02d-%02d', y, m, d)
            if ds >= @@config[:first_school_day] && ds <= @@config[:last_day]
                return ds
            end
        end
        raise 'nope'
    end

    post '/api/upload_vplan_html' do
        require_user_who_can_upload_vplan!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile']
        mtime = blob.mtime
        contents = blob.read
        # contents = contents.force_encoding('iso-8859-1').encode('utf-8')
        # STDERR.puts "#{filename} #{contents.encoding} #{mtime}"

        dom = Nokogiri::HTML.parse(contents)
        return if dom.at_css('h2').nil?
        return if dom.at_css('#vertretung').nil?
        heading = dom.at_css('h2').text
        datum = nil
        dom.at_css('#vertretung').children.each do |child|
            if child.name == 'table' && datum
                table_mode = nil
                result = {
                    :filename => filename,
                    :heading => heading,
                    :datum => datum
                }
                classes = child.attribute('class').to_s.split(' ')
                # STDERR.puts "[#{filename}] [#{heading}] [#{datum}] "
                if classes.include?('subst')
                    # STDERR.print "(Vertretungsplan)"
                    table_mode = :vplan
                else
                    if child.css('tr').first.text == 'Nachrichten zum Tag'
                        # STDERR.print "(Nachrichten zum Tag)"
                        table_mode = :day_message
                    else
                        # STDERR.puts "classes: #{classes.to_json}"
                        # STDERR.puts child.to_s
                        raise 'unexpected table'
                    end
                end
                assert(!table_mode.nil?)
                # STDERR.puts child.to_s
                child.css('tr').each do |row|
                    tr = row.css('th')
                    if tr.size == 6
                        # Klassenvertretungsplan: 
                        headings = tr.map { |x| x.text }.join(' / ')
                        assert(headings == 'Klasse(n) / Stunde / Fach / Raum / (Lehrer) / Text')
                    elsif tr.size == 7
                        # Lehrervertretungsplan: Vtr-Nr.	Stunde	Klasse(n)	(Lehrer)	(Raum)	(Fach)	Text
                        headings = tr.map { |x| x.text }.join(' / ')
                        assert(headings == 'Vtr-Nr. / Stunde / Klasse(n) / (Lehrer) / (Raum) / (Fach) / Text')
                    end
                    cells = row.css('td')
                    if cells.size == 1 && table_mode == :day_message
                        result[:day_message] = cells.first.text
                    elsif cells.size == 6 && table_mode == :vplan
                        result[:entries] ||= []
                        result[:entries] << cells.map { |x| x.text }
                        # Klassenvertretungsplan: Klasse(n)	Stunde	Fach	Raum	(Lehrer)	Text
                    elsif cells.size == 7 && table_mode == :vplan
                        result[:entries] ||= []
                        result[:entries] << cells.map { |x| x.text }
                        # Lehrervertretungsplan: Vtr-Nr.	Stunde	Klasse(n)	(Lehrer)	(Raum)	(Fach)	Text
                    end
                    # STDERR.print " #{cells.size}"
                end
                # STDERR.puts
                # STDERR.puts '-' * 40
                path = "/vplan/#{result[:datum]}/#{result[:heading].gsub('/', '-')}.yaml"
                FileUtils.mkpath(File.dirname(path))
                File.open(path, 'w') { |f| f.write(result.to_yaml) }
            else
                b = nil
                b = child.text if child.name == 'b'
                child.css('b').each { |c2| b = c2.text }
                datum = parse_html_datum(b) if b
            end
        end
        # head = dom.css('.mon_head').to_s 
        # m = head.match(/Stand: (\d+\.\d+\.\d+)\s+(\d+:\d+)/)
        # d = m[1]
        # t = m[2]
        # valid_from = d.split('.').map { |x| x.to_i }.reverse.map.with_index { |x, i| sprintf("%0#{i == 0 ? 4 : 2}d", x) }.join('-')
        # valid_from += "T#{t}:00"
        # STDERR.puts valid_from

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
        respond(:uploaded => 'yeah')
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
