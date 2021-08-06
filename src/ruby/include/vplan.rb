TIMETABLE_JSON_KEYS = {
    6 => [:klasse, :stunde, :fach, :raum, :lehrer, :text],
    7 => [:vnr, :stunde, :klasse, :lehrer, :raum, :fach, :text],
}

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

    def handle_zip_entry(contents)
        require_user_who_can_upload_vplan!

        dom = Nokogiri::HTML.parse(contents)
        return if dom.at_css('h2').nil?
        return if dom.at_css('#vertretung').nil?
        heading = dom.at_css('h2').text
        heading.gsub!('8?', '8o')
        heading.gsub!('9?', '9o')
        heading.gsub!('J11', '11')
        heading.gsub!('J12', '12')
        klasse = heading.split(' ').first
        if @@index_for_klasse[klasse]
            heading = klasse
        end
        datum_list = Set.new()
        datum = nil
        result = {}
        dom.at_css('#vertretung').children.each do |child|
            if child.name == 'table' && datum
                table_mode = nil
                classes = child.attribute('class').to_s.split(' ')
                # STDERR.puts "[#{heading}] [#{datum}] [#{classes.join(' ')}]"
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
                    row.search('s').each do |n| 
                        n.content = "__STRIKE_BEGIN__#{n.content}__STRIKE_END__"
                    end
                    row.search('br').each do |n| 
                        n.content = "__LINE_BREAK__"
                    end
                    row.search('td/*').each do |n| 
                        n.replace(n.content) unless n.name == 's'
                    end

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
                        result[datum] ||= {}
                        day_message = cells.first.text.gsub('__LINE_BREAK__', "\n").strip
                        sha1 = Digest::SHA1.hexdigest(day_message.to_json)[0, 8]
                        path = "/vplan/#{datum}/entries/#{sha1}.json"
                        FileUtils.mkpath(File.dirname(path))
                        File.open(path, 'w') { |f| f.write(day_message.to_json) }
                        result[datum][:day_messages] ||= []
                        result[datum][:day_messages] << sha1
                    elsif (cells.size == 6 || cells.size == 7) && table_mode == :vplan
                        # Klassenvertretungsplan: Klasse(n)	Stunde	Fach	Raum	(Lehrer)	Text
                        # Lehrervertretungsplan: Vtr-Nr.	Stunde	Klasse(n)	(Lehrer)	(Raum)	(Fach)	Text
                        result[datum] ||= {}
                        result[datum][:entries] ||= []
                        entry = {}
                        cells.each.with_index do |x, index|
                            key = TIMETABLE_JSON_KEYS[cells.size][index]
                            text = x.content || ''
                            # replace &nbsp; with normal space and strip
                            text.gsub!(/[[:space:]]+/, ' ')
                            text.strip!
                            entry_del = nil
                            entry_add = nil
                            if text.include?('__STRIKE_BEGIN__')
                                text.gsub!('__STRIKE_BEGIN__', '')
                                parts = text.split('__STRIKE_END__')
                                entry_del = (parts[0] || '').strip
                                entry_add = (parts[1] || '').strip
                            else
                                entry_add = (text || '').strip
                            end
                            entry_add = nil if entry_add && entry_add.empty?
                            entry_del = nil if entry_del && entry_del.empty?
                            entry_add = entry_add[1, entry_add.size - 1] if entry_add && entry_add[0] == '?'
                            entry[key] = [entry_del, entry_add]
                        end
                        fixed_entry = [entry[:stunde][1], entry[:klasse], entry[:lehrer], entry[:fach], entry[:raum], entry[:text][1]]
                        sha1 = Digest::SHA1.hexdigest(fixed_entry.to_json)[0, 8]
                        path = "/vplan/#{datum}/entries/#{sha1}.json"
                        FileUtils.mkpath(File.dirname(path))
                        File.open(path, 'w') { |f| f.write(fixed_entry.to_json) }
                        result[datum][:entries] << sha1
                    end
                    # STDERR.print " #{cells.size}"
                end
                # STDERR.puts
                # STDERR.puts '-' * 40
            else
                b = nil
                b = child.text if child.name == 'b'
                child.css('b').each { |c2| b = c2.text }
                if b
                    datum = parse_html_datum(b) 
                    datum_list << datum
                end
            end
        end
        result.each_pair do |datum, info|
            path = "/vplan/#{datum}/#{heading.gsub('/', '-')}.json"
            FileUtils.mkpath(File.dirname(path))
            File.open(path, 'w') { |f| f.write(result[datum].to_json) }
        end
        return datum_list
    end

    post '/api/upload_vplan_html_zip' do
        require_user_who_can_upload_vplan!
        entry = params['data']
        blob = entry['tempfile']
        datum_list = Set.new()
        Zip::File.open(blob) do |zip_file|
            zip_file.each do |entry|
                zip_contents = entry.get_input_stream.read
                temp = handle_zip_entry(zip_contents)
                if temp
                    datum_list |= temp
                end
            end
        end
        datum_list.each do |datum|
            File.open("/vplan/#{datum}.json", 'w') do |fout|
                data = {:entries => {}, :entry_ref => {}, :timetables => {}}
                Dir["/vplan/#{datum}/entries/*.json"].each do |path|
                    sha1 = File.basename(path).sub('.json', '')
                    data[:entries][sha1] = JSON.parse(File.read(path))
                end
                Dir["/vplan/#{datum}/*.json"].each do |path|
                    id = File.basename(path).sub('.json', '')
                    entry = JSON.parse(File.read(path))
                    unless entry.empty?
                        data[:timetables][id] = entry
                        (entry['entries'] || []).each do |e|
                            data[:entry_ref][e] ||= []
                            data[:entry_ref][e] << id
                        end
                    end
                end
                fout.write(data.to_json)
            end
        end
        trigger_update('all')
        respond(:yay => 'sure')
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
