require 'csv'
require 'set'
require 'yaml'
require 'json'
require 'digest/sha2'
require 'nokogiri'
require './credentials.rb'

class String
    # The extended characters map used by removeaccents. The accented characters 
    # are coded here using their numerical equivalent to sidestep encoding issues.
    # These correspond to ISO-8859-1 encoding.
    ACCENTS_MAPPING = {
        'E' => [200,201,202,203],
        'e' => [232,233,234,235],
        'A' => [192,193,194,195,196,197],
        'a' => [224,225,226,227,228,229,230],
        'C' => [199],
        'c' => [231],
        'O' => [210,211,212,213,214,216],
        'o' => [242,243,244,245,246,248],
        'I' => [204,205,206,207],
        'i' => [236,237,238,239],
        'U' => [217,218,219,220],
        'u' => [249,250,251,252],
        'N' => [209],
        'n' => [241],
        'Y' => [221],
        'y' => [253,255],
        'AE' => [306],
        'ae' => [346],
        'OE' => [188],
        'oe' => [189]
    }
    
    
    # Remove the accents from the string. Uses String::ACCENTS_MAPPING as the source map.
    def removeaccents    
        str = String.new(self)
        String::ACCENTS_MAPPING.each {|letter,accents|
        packed = accents.pack('U*')
        rxp = Regexp.new("[#{packed}]", nil)
        str.gsub!(rxp, letter)
        }
        
        str
    end
    
    
    # Convert a string to a format suitable for a URL without ever using escaped characters.
    # It calls strip, removeaccents, downcase (optional) then removes the spaces (optional)
    # and finally removes any characters matching the default regexp (/[^-_A-Za-z0-9]/).
    #
    # Options
    #
    # * :downcase => call downcase on the string (defaults to true)
    # * :convert_spaces => Convert space to underscore (defaults to false)
    # * :regexp => The regexp matching characters that will be converting to an empty string (defaults to /[^-_A-Za-z0-9]/)
    def urlize(options = {})
        options[:downcase] ||= true
        options[:convert_spaces] ||= false
        options[:regexp] ||= /[^-_A-Za-z0-9]/
        
        str = self.strip.removeaccents
        str.downcase! if options[:downcase]
        str.gsub!(/\ /,'-') if options[:convert_spaces]
        str.gsub(options[:regexp], '')
    end

    # This follows the generated ID rules
    def anchorize(options = {})
        options[:downcase] ||= true
        options[:convert_spaces] ||= false
        options[:regexp] ||= /[^-_A-Za-z0-9]/
        
        str = self.strip.removeaccents
        str.downcase! if options[:downcase]
        str.gsub!(/\ /,'_') if options[:convert_spaces]
        str.gsub(options[:regexp], '')
    end
end

class Parser
    
    def initialize
        @@chars = 'BCDFGHJKMNPQRSTVWXYZ23456789'.split('')
        @email_sub = {}
        if File.exists?('/data/schueler/email-sub.txt')
            File.open('/data/schueler/email-sub.txt') do |f|
                f.each_line do |line|
                    parts = line.strip.split(' ').map { |x| x.strip }
                    @email_sub[parts[0]] = parts[1]
                end
            end
        end
        @nc_sub = {}
        if File.exists?('/data/lehrer/nc-sub.txt')
            File.open('/data/lehrer/nc-sub.txt') do |f|
                f.each_line do |line|
                    parts = line.strip.split(' ').map { |x| x.strip }
                    @nc_sub[parts[0]] = parts[1]
                end
            end
        end
        @use_mock_names = false
        if USE_MOCK_NAMES
            @use_mock_names = true
        end
        if @use_mock_names
            STDERR.puts "Using mock names!"
        end
        @mock = {}
        @mock[:nachnamen] = JSON.parse(File.read('mock/nachnamen.json'))
        @mock[:vornamen] = JSON.parse(File.read('mock/vornamen-m.json'))
        @mock[:vornamen] += JSON.parse(File.read('mock/vornamen-w.json'))
    end
    
    def first_letter_dot(s)
        (s && s.length > 0) ? "#{s[0]}." : s
    end
    
    def parse_lehrer(&block)
#         STDERR.puts "Parsing lehrer..."
        path = '/data/lehrer/lehrer.csv'
        unless File.exists?(path)
            STDERR.puts "...skipping because #{path} does not exist"
            return
        end
        srand(1)
        CSV.foreach(path, :headers => true) do |line|
            line = Hash[line]
            email = line['E-Mail-Adresse'].strip
            shorthand = (line['Kürzel'] || '').strip
            next if shorthand.empty?
            first_name = (line['Vorname'] || '').strip
            last_name = (line['Nachname'] || '').strip
            geschlecht = line['Geschlecht']
            
            if @use_mock_names
                if EXCLUDE_FROM_MOCKIFICATION.include?(email)
                    first_name = @mock[:vornamen].sample
                    last_name = @mock[:nachnamen].sample
                    @mock_shorthand ||= {}
                    @mock_shorthand[shorthand] = last_name[0, 3]
                    shorthand = @mock_shorthand[shorthand]
                else
                    @mock_shorthand ||= {}
                    @mock_shorthand[shorthand] = shorthand
                end
            end
            
            titel = (line['Titel'] || '').strip
            display_name = last_name.dup
            if display_name.include?(',')
                display_name = display_name.split(',').map { |x| x.strip }
                display_name = "#{display_name[1]} #{display_name[0]}"
            end
            display_last_name = display_name.dup
            display_last_name = "#{titel} #{display_last_name}".strip
            if geschlecht == 'm'
                display_last_name = "Herr #{display_last_name}".strip
            elsif geschlecht == 'w'
                display_last_name = "Frau #{display_last_name}".strip
            end
            display_last_name = 'NN' if display_last_name.empty?
            display_name = "#{first_name} #{display_name}".strip
            display_name = "#{titel} #{display_name}".strip
            display_name = 'NN' if display_name.empty?
            
            record = {:email => email,
                      :shorthand => shorthand,
                      :first_name => first_name,
                      :last_name => last_name,
                      :titel => titel,
                      :display_name => display_name,
                      :display_last_name => display_last_name,
                      :display_name_official => display_last_name,
                      :display_last_name_dativ => display_last_name.sub('Herr ', 'Herrn '),
                      :can_log_in => (line['Deaktiviert'] || '').empty?,
                      :nc_login => @nc_sub[email] || shorthand.gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue'),
                      :initial_nc_password => gen_password_for_nc(email)
                      }
            yield record
        end
    end
    
    def parse_klassenleiter(&block)
#         STDERR.puts "Parsing klassenleiter..."
        path = '/data/klassenleiter/klassenleiter.txt'
        unless File.exists?(path)
            STDERR.puts "...skipping because #{path} does not exist"
            return
        end
        File.open(path) do |f|
            f.each_line do |line|
                parts = line.split(',').map { |x| x.strip }
                if parts.size == 3 
                    yield :klasse => parts[0], :klassenleiter => [parts[1], parts[2]]
                end
            end
        end
    end
    
    def name_to_email(vorname, nachname)
        if nachname.include?(',')
            _ = nachname.split(',').map { |x| x.strip }
            nachname = "#{_[1]} #{_[0]}"
        end
        email = "#{vorname} #{nachname}@#{SCHUL_MAIL_DOMAIN}"
        email.downcase!
        email.gsub!(' ', '.')
        email.gsub!('ä', 'ae')
        email.gsub!('ö', 'oe')
        email.gsub!('ü', 'ue')
        email.gsub!('ß', 'ss')
        email.gsub!('ė', 'e')
        email = email.removeaccents
        @email_sub[email] || email
    end

    def name_to_display_name(vorname, nachname)
        if nachname.include?(',')
            _ = nachname.split(',').map { |x| x.strip }
            nachname = "#{_[1]} #{_[0]}"
        end
        "#{vorname} #{nachname}".strip
    end

    def gen_password(email, salt)
        sha2 = Digest::SHA256.new()
        sha2 << salt
        sha2 << email
        srand(sha2.hexdigest.to_i(16))
        password = ''
        while true do
            if password =~ /[a-z]/ &&
            password =~ /[A-Z]/ &&
            password =~ /[0-9]/ &&
            password.include?('-')
                break
            end
            password = ''
            8.times do 
                c = @@chars.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
            password += '-'
            4.times do 
                c = @@chars.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
        end
        password
    end
    
    def gen_password_for_email(email)
        gen_password(email, EMAIL_PASSWORD_SALT)
    end
    
    def gen_password_for_nc(email)
        gen_password(email, NEXTCLOUD_PASSWORD_SALT)
    end
    
    def handle_schueler_line(line)
        line = line.encode('utf-8')
        parts = line.split("\t")
        nachname = parts[0].strip.gsub(/\s+/, ' ')
        vorname = parts[1].strip.gsub(/\s+/, ' ')
        if @use_mock_names
            while true do
                vorname = @mock[:vornamen].sample
                nachname = @mock[:nachnamen].sample
                break if "#{vorname}.#{nachname}".size <= 20
            end
        end
        klasse = parts[2].strip.gsub(/\s+/, ' ')
        # fix Klasse in WinSchule export
        klasse = Main::fix_parsed_klasse(klasse)
        geschlecht = parts[3].strip
        rufname = vorname.split(' ').first
        unless (parts[4] || '').strip.empty?
            rufname = parts[4].strip
        end
        unless ['m', 'w'].include?(geschlecht)
            STDERR.puts "#{vorname} #{nachname}: #{geschlecht}"
            STDERR.puts "Fehler: Geschlecht nicht korrekt angegeben."
            exit(1)
        end
        email = name_to_email(rufname, nachname)
        if email.sub('@' + SCHUL_MAIL_DOMAIN, '').size > 23
            STDERR.puts email
            STDERR.puts "Fehler: E-Mail-Adresse ist zu lang: #{email}"
            exit(1)
        end

        record = {:first_name => rufname,
                  :last_name => nachname,
                  :email => email,
                  :initial_password => gen_password_for_email(email),
                  :initial_nc_password => gen_password_for_nc(email),
                  :klasse => klasse,
                  :display_name => name_to_display_name(rufname, nachname),
                  :display_first_name => name_to_display_name(rufname, ''),
                  :display_last_name => name_to_display_name('', nachname),
                  :display_name_official => name_to_display_name(rufname, nachname),
                  :geschlecht => geschlecht,
                  :can_log_in => true
                  }
        record
    end

    def parse_schueler(&block)
#         STDERR.puts "Parsing schueler..."
        # create reproducible passwords while parsing SuS
        path = '/data/schueler/ASCII.TXT'
        unless File.exists?(path)
            STDERR.puts "...skipping because #{path} does not exist"
            return
        end
        srand(1)
        File.open(path, 'r:utf-8') do |f|
            f.each_line do |line|
                next if line.strip[0] == '#' || line.strip.empty?
                yield handle_schueler_line(line)
            end
        end
        srand()
    end
    
    def parse_faecher
#         STDERR.puts "Parsing faecher..."
        if File.exists?('/data/faecher/faecher.csv')
            CSV.foreach('/data/faecher/faecher.csv', :headers => true) do |line|
                line = Hash[line]
                next unless line['Fach']
                fach = line['Fach'].strip
                bezeichnung = line['Bezeichnung']
                if bezeichnung
                    bezeichnung.strip! 
                    yield fach, bezeichnung
                end
            end
        end
    end
    
    def parse_ferien_feiertage
#         STDERR.puts "Parsing ferien/feiertage..."
        if File.exists?('/data/ferien_feiertage/ferien_feiertage.csv')
            CSV.foreach('/data/ferien_feiertage/ferien_feiertage.csv', :headers => true) do |line|
                line = Hash[line]
                t0 = line['Beginn']
                t1 = line['Ende'] || t0
                title = line['Titel'].strip
                yield t0, t1, title
            end
        end
    end
    
    def notify_if_different(a, b)
        if a != b
            STDERR.puts "UNEXPECTED DIFFERENCE: #{a} <=> #{b}"
        end
    end
    
    def parse_timetable(config, lesson_key_tr = {})
        sub_keys_for_unr_fach = {}
        lesson_keys_for_unr = {}
        info_for_lesson_key = {}
        all_lessons = {:timetables => {}, :start_dates => [], :lesson_keys => {}}
        Dir['/data/stundenplan/*.TXT'].sort.each do |path|
            timetable_start_date = File.basename(path).sub('.TXT', '')
            next if timetable_start_date < config[:first_school_day]
            all_lessons[:start_dates] << timetable_start_date
            lessons = {}
            # timetables used to be ISO-8859-1 before 2020-10-26, UTF-8 after that
            enc = timetable_start_date < '2020-10-26' ? 'iso-8859-1' : 'utf-8'
            File.open(path, 'r:' + enc) do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
#                     parts = line.split(",").map do |x| 
                    parts = line.split("\t").map do |x| 
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    unr = parts[0].to_i
                    klasse = parts[1]
                    klasse = '8o' if klasse == '8?'
                    klasse = '8o' if klasse == '8ω'
#                     next if timetable_start_date < '2020-08-19' && ['11', '12'].include?(klasse)
                    lehrer = parts[2]
                    if @use_mock_names
                        lehrer = @mock_shorthand[lehrer]
                        next if lehrer.nil?
                    end
                    fach = parts[3].gsub('/', '-')
#                     STDERR.puts fach
#                     fach = fach.split('-').first
#                     next if (!fach.nil?) && fach[fach.size - 1] =~ /\d/
                    raum = parts[4]
                    dow = parts[5].to_i - 1
                    stunde = parts[6].to_i
                    fach_unr_key = "#{fach}~#{unr}"
                    lessons[fach_unr_key] ||= {}
                    lessons[fach_unr_key]["#{dow}/#{stunde}"] ||= {}
                    lessons[fach_unr_key]["#{dow}/#{stunde}"][raum] ||= {
                        :lehrer => Set.new(),
                        :klassen => Set.new()
                    }
                    lessons[fach_unr_key]["#{dow}/#{stunde}"][raum][:lehrer] << lehrer
                    lessons[fach_unr_key]["#{dow}/#{stunde}"][raum][:klassen] << klasse
                end
            end
            fixed_lessons = {}
            lessons.each_pair do |unr_fach, stunden|
                stunden.each_pair do |tag_stunde, info|
                    info.each_pair do |raum, stunden_info|
                        sub_key_klassen = stunden_info[:klassen].to_a.sort
                        sub_key = "#{stunden_info[:lehrer].to_a.sort.join('/')}~#{sub_key_klassen.join('/')}"
                        sub_keys_for_unr_fach[unr_fach] ||= {}
                        letter = sub_keys_for_unr_fach[unr_fach].keys.select do |x|
                            klassen = (x.split('~')[1] || '').split('/')
                            klassen == sub_key_klassen
                        end.map { |x| sub_keys_for_unr_fach[unr_fach][x] }.first
                        
                        letter ||= ('a'.ord + sub_keys_for_unr_fach[unr_fach].size).chr
                        sub_keys_for_unr_fach[unr_fach][sub_key] ||= letter
                    end
                end
            end
            lessons.each_pair do |unr_fach, stunden|
                stunden.each_pair do |tag_stunde, info|
                    info.each_pair do |raum, stunden_info|
                        sub_key = "#{stunden_info[:lehrer].to_a.sort.join('/')}~#{stunden_info[:klassen].to_a.sort.join('/')}"
                        lesson_key = "#{unr_fach}#{sub_keys_for_unr_fach[unr_fach][sub_key]}"
                        lesson_key = lesson_key_tr[lesson_key] || lesson_key
                        lesson_keys_for_unr[unr_fach.split('~')[1].to_i] ||= Set.new()
                        lesson_keys_for_unr[unr_fach.split('~')[1].to_i] << lesson_key
                        info_for_lesson_key[lesson_key] ||= {:lehrer => Set.new(),
                                                             :klassen => Set.new()}
                        info_for_lesson_key[lesson_key][:lehrer] |= stunden_info[:lehrer]
                        info_for_lesson_key[lesson_key][:klassen] |= stunden_info[:klassen]
                        fixed_lessons[lesson_key] ||= {
                            :stunden => {}
                        }
                        all_lessons[:lesson_keys][lesson_key] ||= {
                            :unr => Set.new(),
                            :fach => unr_fach.split('~').first,
                            :lehrer => Set.new(),
                            :klassen => Set.new()
                        }
                        
                        all_lessons[:lesson_keys][lesson_key][:unr] << unr_fach.split('~')[1].to_i
                        all_lessons[:lesson_keys][lesson_key][:lehrer] |= info_for_lesson_key[lesson_key][:lehrer]
                        all_lessons[:lesson_keys][lesson_key][:klassen] |= info_for_lesson_key[lesson_key][:klassen]

                        tag, stunde = *(tag_stunde.split('/').map { |x| x.to_i })
                        start_time = nil
                        end_time = nil
                        klasse = info_for_lesson_key[lesson_key][:klassen].to_a.sort.first
                        fixed_lessons[lesson_key][:stunden][tag] ||= {}
                        fixed_lessons[lesson_key][:stunden][tag][stunde] = {
                            :tag => tag,
                            :raum => raum,
                            :stunde => stunde,
                            :lehrer => stunden_info[:lehrer],
                            :klassen => stunden_info[:klassen],
                            :count => 1,
                            :pausen => []
                        }
                    end
                end
            end
            lessons = fixed_lessons
            all_lessons[:timetables][timetable_start_date] = lessons
        end
        all_lessons[:lesson_keys].keys.each do |lesson_key|
            all_lessons[:lesson_keys][lesson_key][:klassen] = all_lessons[:lesson_keys][lesson_key][:klassen].to_a.sort
            all_lessons[:lesson_keys][lesson_key][:lehrer] = all_lessons[:lesson_keys][lesson_key][:lehrer].to_a.sort
        end
        all_lessons[:lesson_keys_for_unr] = lesson_keys_for_unr
        all_lessons[:start_date_for_date] = {}
        d = Date.parse(config[:first_day])
        end_date = Date.parse(config[:last_day])
        index = 0
        unless all_lessons[:start_dates].empty?
            while d <= end_date do
                ds = d.strftime('%Y-%m-%d')
                while ds >= (all_lessons[:start_dates][index + 1] || '') && (index < all_lessons[:start_dates].size - 1)
                    index += 1
                end
                if ds >= all_lessons[:start_dates][index]
                    all_lessons[:start_date_for_date][ds] = all_lessons[:start_dates][index]
                end
                d += 1
            end
        end
        entries = []
        vplan_path = Dir['/vplan/*.txt'].sort.last
        if vplan_path
            STDERR.puts "Loading vplan from #{vplan_path}..."
            File.open(vplan_path, 'r:' + VPLAN_ENCODING) do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    parts = line.split("\t").map do |x| 
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    vertretungs_arten = {
                        'T' => 'verlegt',
                        'F' => 'verlegt von',
                        'W' => 'Tausch',
                        'S' => 'Betreuung',
                        'A' => 'Sondereinsatz',
                        'C' => 'Entfall',
                        'L' => 'Freisetzung',
                        'P' => 'Teil-Vertretung',
                        'R' => 'Raumvertretung',
                        'B' => 'Pausenaufsichtsvertretung',
                        '~' => 'Lehrertausch',
                        'E' => 'Klausur'
                    }
                    art = Set.new()
                    bits = {0 => 'Entfall',
                            1 => 'Betreuung',
                            2 => 'Sondereinsatz',
                            3 => 'Wegverlegung',
                            4 => 'Freisetzung',
                            5 => 'Plus als Vertreter',
                            6 => 'Teilvertretung',
                            7 => 'Hinverlegung',
                            16 => 'Raumvertretung',
                            17 => 'Pausenaufsichtsvertretung',
                            18 => 'Stunde ist unterrichtsfrei',
                            20 => 'Kennzeichen nicht drucken',
                            21 => 'Kennzeichen neu'}
                    flags = parts[17].to_i
                    bit = 0
                    while flags > 0
                        if (flags & 1) == 1
                            art << (bits[bit] || "unbekanntes Bit #{bit}")
                        end
                        bit += 1
                        flags >>= 1
                    end
                    datum = "#{parts[1][0, 4]}-#{parts[1][4, 2]}-#{parts[1][6, 2]}"
                    if @use_mock_names
                        if parts[5] && !parts[5].empty?
                            parts[5] = @mock_shorthand[parts[5]]
                            next if parts[5].nil?
                        end
                        if parts[6] && !parts[6].empty?
                            parts[6] = @mock_shorthand[parts[6]]
                            next if parts[6].nil?
                        end
                    end
                    entry = {
                        :vnr => parts[0].to_i,
                        :datum => datum,
                        :stunde => parts[2].to_i,
    #                     :absenz_nr => parts[3].to_i,
                        # referenziert Stundenplan
                        :unr => parts[4].to_i,
                        :lehrer_alt => parts[5],
                        :lehrer_neu => parts[6],
                        :fach_alt => parts[7].gsub('/', '-'),
    #                     :fach_alt_stkz => parts[8],
                        :fach_neu => parts[9].gsub('/', '-'),
    #                     :fach_neu_stkz => parts[10],
                        :raum_alt => parts[11].gsub('~', '/'),
                        :raum_neu => parts[12].gsub('~', '/'),
    #                     :stkz => parts[13],
                        :klassen_alt => Set.new(parts[14].split('~')).to_a.map { |x| x == '8?' ? '8o': x }.sort,
                        :grund => parts[15],
                        :vertretungs_text => parts[16],
                        :art => art,
                        :klassen_neu => Set.new(parts[18].split('~')).to_a.map { |x| x == '8?' ? '8o': x }.sort,
                        :vertretungs_art => vertretungs_arten[parts[19]] || parts[19],
    #                     :record_date => parts[20],
    #                     :unknown => parts[21]
                    }

                    entry.keys.each do |k|
                        if (entry[k].is_a?(String) || entry[k].is_a?(Array)) && entry[k].empty?
                            entry.delete(k)
                        end
                    end
                    unless entry[:art].include?('Kennzeichen nicht drucken')
                        entries << entry
                    end
                end
            end
        end
        vertretungen = {}
        entries.each do |entry|
            vertretungen[entry[:datum]] ||= []
            vertretungen[entry[:datum]] << entry
        end
        return all_lessons, vertretungen, File.basename(vplan_path || '').sub('.txt', '')
    end
    
    def parse_pausenaufsichten()
        all_pausenaufsichten = {:aufsichten => {}, :start_dates => []}
        Dir['/data/pausenaufsichten/*.TXT'].sort.each do |path|
            start_date = File.basename(path).sub('.TXT', '')
            all_pausenaufsichten[:start_dates] << start_date
            all_pausenaufsichten[:aufsichten][start_date] = {}
            File.open(path, File.basename(path) >= '2020-10-26.TXT' ? 'r:utf-8' : 'r:iso-8859-1') do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    parts = line.split("\t").map do |x| 
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    where = parts[0]
                    shorthand = parts[1]
                    dow = parts[2].to_i - 1
                    stunde = parts[3].to_i
                    minutes = parts[4].to_i
                    all_pausenaufsichten[:aufsichten][start_date][shorthand] ||= {}
                    all_pausenaufsichten[:aufsichten][start_date][shorthand][dow] ||= {}
                    h = AUFSICHT_ZEIT[stunde].split(':')[0].to_i
                    m = AUFSICHT_ZEIT[stunde].split(':')[1].to_i
                    t1 = h * 60 + m
                    t0 = t1 - minutes
                    all_pausenaufsichten[:aufsichten][start_date][shorthand][dow][stunde] ||= {
                        :where => where,
                        :minutes => minutes,
                        :start_time => sprintf('%02d:%02d', (t0 / 60).to_i, t0 % 60),
                        :end_time => sprintf('%02d:%02d', (t1 / 60).to_i, t1 % 60)
                    }
                end
            end
        end
        return all_pausenaufsichten
    end
    
    def parse_kurswahl(user_info, lessons, lesson_key_tr)
#         STDERR.puts "Parsing kurswahl..."
        kurse_for_schueler = {}
        schueler_for_kurs = {}
        name_tr = {}
        path = '/data/kurswahl/kurswahl-tr.txt'
        if File.exists?('/data/kurswahl/kurswahl-tr.txt')
            File.open(path, 'r:utf-8') do |f|
                f.each_line do |line|
                    parts = line.split(/\s+/)
                    name_tr[parts[0]] = parts[1]
                end
            end
        end
        unassigned_names = Set.new()
        if File.exists?('/data/kurswahl/kurswahl.TXT')
            File.open('/data/kurswahl/kurswahl.TXT', 'r:utf-8') do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    next if line.strip.empty?
                    parts = line.split("\t").map do |x| 
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    name = parts[0]
                    fach = parts[2].gsub('/', '-')
                    email = nil
                    if name_tr.include?(name)
                        email = name_tr[name]
                    else
                        emails = user_info.select do |email, user_info|
                            last_name = user_info[:last_name]
                            first_name = user_info[:first_name]
                            ['11', '12'].include?(user_info[:klasse]) && ("#{last_name}#{first_name[0, name.size - last_name.size]}" == name)
                        end.keys
                        if emails.size == 1
                            email = emails.to_a.first
                        else
                            unassigned_names << name
                        end
                    end
                    lesson_keys = lessons[:lesson_keys].keys.select do |lesson_key|
                        lessons[:lesson_keys][lesson_key][:fach] == fach
                    end
                    if lesson_keys.size != 1
                        STDERR.puts line
                        STDERR.puts "#{fach}: #{lesson_keys.to_json}"
                    end
                    unless email
                        STDERR.puts "Kurswahl: Can't assign #{name}!"
                    end
                    if email && lesson_keys.size == 1
                        lesson_key = lesson_keys.to_a.first
                        kurse_for_schueler[email] ||= Set.new()
                        kurse_for_schueler[email] << lesson_key
                        schueler_for_kurs[lesson_key] ||= Set.new()
                        schueler_for_kurs[lesson_key] << email
                    end
                end
            end
        end
        unless unassigned_names.empty?
            STDERR.puts "Kurswahl: Can't assign these names!"
            STDERR.puts unassigned_names.to_a.sort.to_yaml
        end
        return kurse_for_schueler, schueler_for_kurs
    end

    def parse_wahlpflichtkurswahl(user_info, lessons)
#         STDERR.puts "Parsing wahlpflichtkurswahl..."
        schueler_for_lesson_key = {}
        unassigned_names = Set.new()
        begin
            if File.exists?('/data/kurswahl/wahlpflicht.yaml')
                wahlpflicht = YAML.load(File.read('/data/kurswahl/wahlpflicht.yaml'))
                wahlpflicht.each_pair do |lesson_key, sus|
                    unless lessons[:lesson_keys].include?(lesson_key)
                        STDERR.puts "NOTICE -- Wahlpflicht: Skipping #{lesson_key} because it's unknown."
                        next
                    end
                    sus.each do |name|
                        email = nil
                        emails = user_info.select do |email, user_info|
                            last_name = user_info[:last_name]
                            first_name = user_info[:first_name]
                            "#{first_name} #{last_name}" == name || email.sub("@#{SCHUL_MAIL_DOMAIN}", '') == name
                        end.keys
                        if emails.size == 1
                            email = emails.to_a.first
                        else
                            unassigned_names << name
                        end
                        unless email
                            STDERR.puts "Wahlpflichtkurswahl: Can't assign #{name}!"
                        end
                        if email
                            schueler_for_lesson_key[lesson_key] ||= Set.new()
                            schueler_for_lesson_key[lesson_key] << email
                        end
                    end
                end
            end
        rescue
            STDERR.puts '-' * 50
            STDERR.puts "ATTENTION: Error parsing wahlpflicht.yaml, skipping..."
            STDERR.puts '-' * 50
        end
        unless unassigned_names.empty?
            STDERR.puts "Kurswahl: Can't assign these names!"
            STDERR.puts unassigned_names.to_a.sort.to_yaml
        end
        STDERR.puts "Wahlpflichtkurswahl: got SuS for #{schueler_for_lesson_key.size} lesson keys."
        return schueler_for_lesson_key
    end
end

