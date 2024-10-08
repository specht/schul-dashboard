#!/usr/bin/env ruby

require 'date'
require 'json'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'sinatra/base'
require 'yaml'

require './credentials.template.rb'
warn_level = $VERBOSE
$VERBOSE = nil
require './credentials.rb'
require '/data/config.rb'
$VERBOSE = warn_level

CONFIG = YAML::load_file('/data/config.yaml')

TIMETABLE_JSON_KEYS = {
    # 6 => [:klasse, :stunde, :fach, :raum, :lehrer, :text],
    # 6 => [:stunde, :klasse, :lehrer, :raum, :fach, :text],
    # 7 => [:vnr, :stunde, :klasse, :lehrer, :raum, :fach, :text],
    # assert(headings == 'Klasse(n) / Stunde / Fach / Raum / (Lehrer) / Art / Text / Unterschrift / Statistik / Schülergruppe / (Lehrv.) / Lehrv.')
    12 => [:klasse, :stunde, :fach, :raum, :lehrer, :art, :text, :unterschrift, :statistik, :schuelergruppe, :lehrv, :lehrv2],
    # assert(headings == 'Vtr-Nr. / Stunde / Fach / Klasse(n) / Raum / (Lehrer) / Art / Text / Unterschrift / Statistik / Schülergruppe / (Lehrv.) / Lehrv.')
    13 => [:vnr, :stunde, :fach, :klasse, :raum, :lehrer, :art, :text, :unterschrift, :statistik, :schuelergruppe, :lehrv, :lehrv2]
}

def assert(condition, message = 'assertion failed', suppress_backtrace = false, delay = nil)
    unless condition
        STDERR.puts message
        e = StandardError.new(message)
        e.set_backtrace([]) if suppress_backtrace
        sleep delay unless delay.nil?
        raise e
    end
end

def parse_html_datum(s)
    parts = s.split('.')
    d = parts[0].to_i
    m = parts[1].to_i
    _ = CONFIG[:first_school_day][0, 4].to_i
    (_ .. (_ + 1)).each do |y|
        ds = sprintf('%04d-%02d-%02d', y, m, d)
        if ds >= CONFIG[:first_school_day] && ds <= CONFIG[:last_day]
            return ds
        end
    end
    return nil
    # raise 'nope'
end

def strip_past_tables(dom)
    dom.css('td').each do |td|
        if (td.text || '').strip == 'Vertretungen sind nicht freigegeben'
            n = td.parent.parent
            deleted_table = false
            while n != nil
                p = n.previous
                n.remove()
                if n && n.name == 'table'
                    if deleted_table
                        break
                    else
                        deleted_table = true
                    end
                end
                n = p
            end
        end
    end
    dom
end

def handle_vplan_html_file(contents, removed_days)
    dom = Nokogiri::HTML.parse(contents)
    dom = strip_past_tables(dom)
    return if dom.at_css('h2').nil?
    return if dom.at_css('#vertretung').nil?
    heading = dom.at_css('h2').text
    heading.gsub!('8?', '8o')
    heading.gsub!('9?', '9o')
    heading.gsub!('10?', '10o')
    heading.gsub!('J11', '11')
    heading.gsub!('J12', '12')
    klasse = heading.split(' ').first
    if KLASSEN_ORDER.include?(klasse)
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
                if tr.size == 12
                    # Klassenvertretungsplan:
                    headings = tr.map { |x| x.text }.join(' / ')
                    # assert(headings == 'Klasse(n) / Stunde / Fach / Raum / (Lehrer) / Text')
                    # assert(headings == 'Stunde / Klasse(n) / (Lehrer) / (Raum) / (Fach) / Text')
                    assert(headings == 'Klasse(n) / Stunde / Fach / Raum / (Lehrer) / Art / Text / Unterschrift / Statistik / Schülergruppe / (Lehrv.) / Lehrv.')
                elsif tr.size == 13
                    # Lehrervertretungsplan: Vtr-Nr.	Stunde	Klasse(n)	(Lehrer)	(Raum)	(Fach)	Text
                    headings = tr.map { |x| x.text }.join(' / ')
                    # assert(headings == 'Vtr-Nr. / Stunde / Klasse(n) / (Lehrer) / (Raum) / (Fach) / Text')
                    assert(headings == 'Vtr-Nr. / Stunde / Fach / Klasse(n) / Raum / (Lehrer) / Art / Text / Unterschrift / Statistik / Schülergruppe / (Lehrv.) / Lehrv.')
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
                elsif (cells.size == 12 || cells.size == 13) && table_mode == :vplan
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
                next if datum.nil?
                datum_list << datum
                unless removed_days.include?(datum)
                    Dir["/vplan/#{datum}/*.json"].each do |path|
                        FileUtils::rm_f(path)
                    end
                    removed_days << datum
                end
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

def handle_html_batch(bodies)
    datum_list = Set.new()
    removed_days = Set.new()
    STDERR.puts "Handling #{bodies.size} HTML files..."
    bodies.each do |body|
        temp = handle_vplan_html_file(body, removed_days)
        if temp
            datum_list |= temp
        end
    end
    datum_list.each do |datum|
        File.open("/vplan/#{datum}.json", 'w') do |fout|
            data = {:entries => {}, :entry_ref => {}, :timetables => {}}
            Dir["/vplan/#{datum}/*.json"].each do |path|
                temp = JSON.parse(File.read(path))
                (temp['entries'] || []).each do |sha1|
                    data[:entries][sha1] = JSON.parse(File.read("/vplan/#{datum}/entries/#{sha1}.json"))
                end
                (temp['day_messages'] || []).each do |sha1|
                    data[:entries][sha1] = JSON.parse(File.read("/vplan/#{datum}/entries/#{sha1}.json"))
                end
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
    # trigger_update('all')
end

def get_file_from_url(url, &block)
    # STDERR.puts "Getting #{url}..."
    uri = URI.parse(url)
    req = Net::HTTP::Get.new(uri)
    if UNTIS_VERTRETUNGSPLAN_USERNAME && UNTIS_VERTRETUNGSPLAN_PASSWORD
        req.basic_auth UNTIS_VERTRETUNGSPLAN_USERNAME, UNTIS_VERTRETUNGSPLAN_PASSWORD
    end

    res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        response = http.request(req)
        if response.code.to_i == 200
            body = response.body
            body.force_encoding('iso-8859-1')
            body = body.encode('utf-8')
            yield(response.header, body)
        else
            STDERR.puts "WARNING: page not found: #{url}"
            # raise "page not found: #{url}"
        end
    end
end

def head_file_from_url(url, &block)
    uri = URI.parse(url)
    req = Net::HTTP::Head.new(uri)
    if UNTIS_VERTRETUNGSPLAN_USERNAME && UNTIS_VERTRETUNGSPLAN_PASSWORD
        req.basic_auth UNTIS_VERTRETUNGSPLAN_USERNAME, UNTIS_VERTRETUNGSPLAN_PASSWORD
    end

    res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
        response = http.request(req)
        if response.code.to_i == 200
            yield(response.header)
        else
            raise "page not found: #{url}"
        end
    end
end

def perform_refresh
    last_update_timestamp = ''
    last_update_timestamp_path = '/vplan/timestamp.txt'
    if File.exist?(last_update_timestamp_path)
        last_update_timestamp = File.read(last_update_timestamp_path).strip
    end
    last_modified = last_update_timestamp
    head_file_from_url("#{UNTIS_VERTRETUNGSPLAN_BASE_URL}/frames/navbar.htm") do |header|
        last_modified = DateTime.parse(header['last-modified']).strftime('%Y-%m-%d-%H-%M-%S')
    end
    return unless last_modified > last_update_timestamp

    STDERR.puts "Fetching vplan from #{UNTIS_VERTRETUNGSPLAN_BASE_URL}!"

    get_file_from_url("#{UNTIS_VERTRETUNGSPLAN_BASE_URL}/frames/navbar.htm") do |header, body|
        file_count = 0
        bodies = []
        dom = Nokogiri::HTML.parse(body)
        weeks = []
        dom.css('select').each do |element|
            if element.attr('name') == 'week'
                element.css('option').each do |option|
                    weeks << option.attr('value').to_i
                end
            end
        end
        classes = JSON.parse(body.match(/var classes\s*=\s*([^;]+);/)[1])
        teachers = JSON.parse(body.match(/var teachers\s*=\s*([^;]+);/)[1])
        STDERR.puts "Got #{weeks.size} weeks, #{classes.size} classes, #{teachers.size} teachers"
        weeks.each do |week|
            (0...teachers.size).each do |index|
                file_count += 1
                url = "#{UNTIS_VERTRETUNGSPLAN_BASE_URL}/#{sprintf('%02d', week)}/v/#{sprintf('v%05d', index + 1)}.htm"
                STDERR.puts "Fetching #{url}..."
                get_file_from_url(url) do |header, body|
                    bodies << body
                end
            end
            (0...classes.size).each do |index|
                file_count += 1
                url = "#{UNTIS_VERTRETUNGSPLAN_BASE_URL}/#{sprintf('%02d', week)}/w/#{sprintf('w%05d', index + 1)}.htm"
                STDERR.puts "Fetching #{url}..."
                get_file_from_url(url) do |header, body|
                    bodies << body
                end
            end
        end
        STDERR.puts "Fetched #{file_count} HTML files, parsing..."
        handle_html_batch(bodies)
    end
    File.open(last_update_timestamp_path, 'w') { |f| f.puts(last_modified) }
    STDERR.puts "Triggering timetable update..."
    system("curl -s http://timetable:8080/api/update/all")
end

loop do
    perform_refresh
    sleep 60
end
