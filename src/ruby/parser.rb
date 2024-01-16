require 'csv'
require 'set'
require 'yaml'
require 'json'
require 'digest/sha2'
require 'nokogiri'
require './credentials.rb'
require '/data/config.rb'

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
        if File.exist?('/data/schueler/email-sub.txt')
            File.open('/data/schueler/email-sub.txt') do |f|
                f.each_line do |line|
                    parts = line.strip.split(' ').map { |x| x.strip }
                    @email_sub[parts[0]] = parts[1]
                end
            end
        end
        @nc_sub = {}
        if File.exist?('/data/lehrer/nc-sub.txt')
            File.open('/data/lehrer/nc-sub.txt') do |f|
                f.each_line do |line|
                    parts = line.strip.split(' ').map { |x| x.strip }
                    @nc_sub[parts[0]] = parts[1]
                end
            end
        end
        @first_name_sub = {}
        if File.exist?('/data/schueler/first-name-sub.txt')
            File.open('/data/schueler/first-name-sub.txt') do |f|
                f.each_line do |line|
                    space_index = line.index(' ')
                    email = line[0, space_index]
                    first_name = line[space_index, line.size].strip
                    @first_name_sub[email] = first_name
                end
            end
        end
        @last_name_sub = {}
        if File.exist?('/data/schueler/last-name-sub.txt')
            File.open('/data/schueler/last-name-sub.txt') do |f|
                f.each_line do |line|
                    space_index = line.index(' ')
                    email = line[0, space_index]
                    last_name = line[space_index, line.size].strip
                    @last_name_sub[email] = last_name
                end
            end
        end
        @use_mock_names = false
        if USE_MOCK_NAMES
            @use_mock_names = true
        end
        if @use_mock_names
            debug "Using mock names!"
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
#         debug "Parsing lehrer..."
        path = '/data/lehrer/lehrer.csv'
        unless File.exist?(path)
            debug "...skipping because #{path} does not exist"
            return
        end
        srand(12)
        CSV.foreach(path, :headers => true) do |line|
            line = Hash[line]
            email = line['E-Mail-Adresse'].strip
            shorthand = (line['Kürzel'] || '').strip
            next if shorthand.empty?
            first_name = (line['Vorname'] || '').strip
            last_name = (line['Nachname'] || '').strip
            geschlecht = line['Geschlecht']
            force_display_name = line['Anzeigename']
            
            if @use_mock_names
                unless EXCLUDE_FROM_MOCKIFICATION.include?(email)
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
            if force_display_name
                display_name = force_display_name
                display_last_name = force_display_name
            end

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
                      :matrix_login => "@#{email.split('@').first}:#{MATRIX_DOMAIN_SHORT}",
                      :initial_nc_password => gen_password_for_nc(email)
                      }
            yield record
        end
    end
    
    def parse_klassenleiter(&block)
#         debug "Parsing klassenleiter..."
        path = '/data/klassenleiter/klassenleiter.txt'
        unless File.exist?(path)
            debug "...skipping because #{path} does not exist"
            return
        end
        File.open(path) do |f|
            f.each_line do |line|
                next if line.strip[0] == '#'
                parts = line.split(',').map { |x| x.strip }
                if parts.size > 1
                    yield :klasse => parts[0], :klassenleiter => parts[1, parts.size - 1]
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
        email = remove_accents(email)
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
        if @force_first_name["#{vorname} #{nachname}"]
            vorname = @force_first_name["#{vorname} #{nachname}"]
        end
        klasse = parts[2].strip.gsub(/\s+/, ' ')
        # fix Klasse in WinSchule export
        klasse = Main::fix_parsed_klasse(klasse)
        geschlecht = parts[3].strip
        rufname = vorname.split(' ').first
        if rufname == 'Ka'
            rufname = vorname
        end
        geburtstag = nil
        if parts[4] =~ /^\d+\.\d+\.\d+$/
            geb_parts = parts[4].split('.').map { |x| x.to_i }
            geburtstag = sprintf('%04d-%02d-%02d', geb_parts[2], geb_parts[1], geb_parts[0])
        end
        unless (parts[5] || '').strip.empty?
            rufname = parts[5].strip
        end
        unless ['m', 'w'].include?(geschlecht)
            debug "#{vorname} #{nachname}: #{geschlecht}"
            debug "Fehler: Geschlecht nicht korrekt angegeben."
            exit(1)
        end
        email = name_to_email(rufname, nachname)
        if @first_name_sub[email]
            vorname = @first_name_sub[email]
        end
        if @last_name_sub[email]
            nachname = @last_name_sub[email]
        end
        name = "#{vorname} #{nachname}"
        if @force_email[name]
            email = @force_email[name]
        end
        if email.sub('@' + SCHUL_MAIL_DOMAIN, '').size > 23
            unless @use_mock_names
                debug "Fehler: E-Mail-Adresse ist zu lang: #{email}"
                exit(1)
            end
        end

        record = {:first_name => rufname,
                  :official_first_name => vorname,
                  :last_name => nachname,
                  :email => email,
                  :geburtstag => geburtstag,
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
#         debug "Parsing schueler..."
        # create reproducible passwords while parsing SuS

        @force_email = {}
        path = '/data/schueler/email-sub-by-name.txt'
        if File.exist?(path)
            File.open(path) do |f|
                f.each_line do |line|
                    line.strip!
                    next if line.empty?
                    parts = line.split(' ')
                    email = parts[0]
                    name = parts[1, parts.size - 1].join(' ')
                    @force_email[name] = email
                end
            end
        end

        @force_first_name = {}
        path = '/data/schueler/first-name-sub-by-name.txt'
        if File.exist?(path)
            File.open(path) do |f|
                f.each_line do |line|
                    line.strip!
                    next if line.empty?
                    parts = line.split('/')
                    @force_first_name[parts[0].strip] = parts[1].strip
                end
            end
        end

        path = '/data/schueler/ASCII.TXT'
        unless File.exist?(path)
            debug "...skipping because #{path} does not exist"
            return
        end
        srand(12)
        File.open(path, 'r:utf-8') do |f|
            f.each_line do |line|
                next if line.strip[0] == '#' || line.strip.empty?
                yield handle_schueler_line(line)
            end
        end
        if DEMO_ACCOUNT_EMAIL
            yield handle_schueler_line("#{DEMO_ACCOUNT_INFO[:last_name]}\t#{DEMO_ACCOUNT_INFO[:first_name]}\t#{DEMO_ACCOUNT_INFO[:klasse]}\t#{DEMO_ACCOUNT_INFO[:geschlecht]}")
        end

        srand()
    end
    
    def parse_faecher
#         debug "Parsing faecher..."
        if File.exist?('/data/faecher/faecher.csv')
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
#         debug "Parsing ferien/feiertage..."
        if File.exist?('/data/ferien_feiertage/ferien_feiertage.csv')
            CSV.foreach('/data/ferien_feiertage/ferien_feiertage.csv', :headers => true) do |line|
                line = Hash[line]
                t0 = line['Beginn']
                t1 = line['Ende'] || t0
                title = line['Titel'].strip
                next if DEVELOPMENT && t0 == '2021-03-08'
                yield t0, t1, title
            end
        end
    end
    
    def parse_tage_infos
#         debug "Parsing ferien/feiertage..."
        if File.exist?('/data/ferien_feiertage/infos.csv')
            CSV.foreach('/data/ferien_feiertage/infos.csv', :headers => true) do |line|
                line = Hash[line]
                t0 = line['Beginn']
                t1 = line['Ende'] || t0
                title = line['Titel'].strip
                next if DEVELOPMENT && t0 == '2021-03-08'
                yield t0, t1, title
            end
        end
    end
    
    def parse_tablets
#         debug "Parsing tablets..."
        if File.exist?('/data/tablets/tablets.csv')
            CSV.foreach('/data/tablets/tablets.csv', :headers => true) do |line|
                line = Hash[line]
                next unless line['Bezeichnung']
                deaktiviert = (line['Deaktiviert'] || '').strip
                next unless deaktiviert.empty?
                id = line['Bezeichnung'].strip
                color = (line['Farbe'] || '').strip
                lagerort = (line['Lagerort'] || '').strip
                status = (line['Aktueller Status'] || '').strip
                school_streaming = (line['Unterrichtseinsatz Streaming aus der Schule'] || '').strip
                lehrer_modus = (line['Lehrer-Modus'] || '').strip
                record = {:id => id, :color => color, 
                          :status => status, :lagerort => lagerort }
                record[:school_streaming] = true unless school_streaming.empty?
                record[:lehrer_modus] = true unless lehrer_modus.empty?
                yield record
            end
        end
    end
    
    def parse_tablet_sets
        #         debug "Parsing tablet sets..."
        path = '/data/tablets/tablet_sets.yaml'
        if File.exist?(path)
            result = YAML::load(File.read(path))
            result.keys.each do |k|
                if result[k][:only_these_rooms]
                    result[k][:only_these_rooms].map! { |x| x.to_s }
                end
                if result[k][:is_tablet_set]
                    result[k][:label] = "#{result[k][:form_factor]} mit #{result[k][:count]} Tablets"
                else
                    result[k][:label] = "#{result[k][:form_factor]} mit einem Gerät"
                end
            end
            return result
        end
        return nil
    end
            
    def notify_if_different(a, b)
        if a != b
            debug "UNEXPECTED DIFFERENCE: #{a} <=> #{b}"
        end
    end
    
    def parse_timetable(config, lesson_key_tr = {})
        historic_lessons_for_shorthand = {}
        sub_keys_for_unr_fach = {}
        lesson_keys_for_unr = {}
        info_for_lesson_key = {}
        day_messages = {}
        all_lessons = {:timetables => {}, :start_dates => [], :lesson_keys => {}}
        current_date = Date.today.strftime('%Y-%m-%d')
        current_timetable_start_date = Dir['/data/stundenplan/*.TXT'].sort.map do |path|
            File.basename(path).sub('.TXT', '')
        end.select do |x|
            current_date >= x
        end.last
        if current_timetable_start_date.nil?
            current_timetable_start_date = Dir['/data/stundenplan/*.TXT'].sort.map do |path|
                File.basename(path).sub('.TXT', '')
            end.first
        end

        unr_tr = {}
        if File.exist?('/data/stundenplan/unr-tr.yaml')
            unr_tr = YAML.load(File.read('/data/stundenplan/unr-tr.yaml'))
        end

        lesson_key_back_tr = {}
        original_lesson_key_for_lesson_key = {}

        Dir['/data/stundenplan/*.TXT'].sort.each do |path|
            timetable_start_date = File.basename(path).sub('.TXT', '')
            next if timetable_start_date < config[:first_school_day]
            all_lessons[:start_dates] << timetable_start_date
            lessons = {}
            use_tr_date = unr_tr.keys.select { |x| x <= timetable_start_date }.first
            use_tr = unr_tr[use_tr_date] || {}
            line_cache = {}
            separator = timetable_start_date < '2023-08-28' ? "\t" : ","
            File.open(path, 'r:utf-8') do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    parts = line.split(separator).map do |x| 
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    klasse = parts[1]
                    klasse = '8o' if klasse == '8?'
                    klasse = '8o' if klasse == '8ω'
                    klasse = '9o' if klasse == '9?'
                    klasse = '9o' if klasse == '9ω'
                    cache_key = parts[2, parts.size - 2].join('/')
                    line_cache[cache_key] ||= Set.new()
                    line_cache[cache_key] << klasse
                end
            end
            File.open(path, 'r:utf-8') do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    parts = line.split(separator).map do |x|
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    unr = parts[0].to_i
                    unr = use_tr[unr] || unr
                    klasse = parts[1]
                    klasse = '8o' if klasse == '8?'
                    klasse = '8o' if klasse == '8ω'
                    klasse = '9o' if klasse == '9?'
                    klasse = '9o' if klasse == '9ω'

                    lehrer = parts[2]
                    if @use_mock_names
                        lehrer = @mock_shorthand[lehrer]
                        next if lehrer.nil?
                    end
                    original_fach = parts[3]
                    next if (parts[3] || '').strip.empty?
                    fach = parts[3].gsub('/', '-')
                    raum = parts[4].split('~').join('/')
                    dow = parts[5].to_i - 1
                    stunde = parts[6].to_i
                    cache_key = parts[2, parts.size - 2].join('/')
                    fach_unr_key = "#{fach}_#{line_cache[cache_key].to_a.sort { |a, b| (a.to_i == b.to_i) ? (a <=> b) : (a.to_i <=> b.to_i)}.join('~')}"
                    fach_unr_key = lesson_key_tr[fach_unr_key] || fach_unr_key
                    if ['Vert', 'Ber', 'FSL'].include?(fach)
                        fach_unr_key = "#{fach}_#{parts[0].to_i}"
                    end
                    lesson_key_back_tr[fach_unr_key] = "#{fach}~#{unr}a"
                    original_lesson_key_for_lesson_key[parts[3]] ||= Set.new()
                    original_lesson_key_for_lesson_key[parts[3]] << fach_unr_key
                    next if fach_unr_key == '_'
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
                        lesson_key = "#{unr_fach}"
                        # lesson_key = "#{unr_fach}~#{sub_keys_for_unr_fach[unr_fach][sub_key]}"
                        lesson_keys_for_unr[unr_fach.split('_')[1].to_i] ||= Set.new()
                        lesson_keys_for_unr[unr_fach.split('_')[1].to_i] << lesson_key
                        info_for_lesson_key[lesson_key] ||= {:lehrer => Set.new(),
                                                             :klassen => Set.new()}
                        # only assign lessons to teachers if it's in the current timetable
                        stunden_info[:lehrer].each do |shorthand|
                            historic_lessons_for_shorthand[shorthand] ||= Set.new()
                            historic_lessons_for_shorthand[shorthand] << lesson_key
                        end
                        if (Date.today.to_s < config[:first_school_day]) || (timetable_start_date == current_timetable_start_date)
                            info_for_lesson_key[lesson_key][:lehrer] |= stunden_info[:lehrer]
                        end
                        info_for_lesson_key[lesson_key][:klassen] |= stunden_info[:klassen]
                        fixed_lessons[lesson_key] ||= {
                            :stunden => {}
                        }
                        all_lessons[:lesson_keys][lesson_key] ||= {
                            :unr => Set.new(),
                            :fach => unr_fach.split('_').first,
                            :lehrer => Set.new(),
                            :klassen => Set.new()
                        }
                        
                        all_lessons[:lesson_keys][lesson_key][:unr] << unr_fach.split('_')[1].to_i
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
        vplan_timestamp = nil

        Dir['/vplan/*.json'].sort.each do |path|
            next unless File.basename(path) =~ /\d{4}\-\d{2}\-\d{2}\.json/
            mtime = File.mtime(path)
            vplan_timestamp ||= mtime
            vplan_timestamp = mtime if mtime > vplan_timestamp
            vplan = JSON.parse(File.read(path))
            datum = File.basename(path).sub('.json', '')
            day_entries_merge_teachers = {}
            vplan['timetables'].each_pair do |target, info|
                next unless info['day_messages']
                info['day_messages'].each do |sha1|
                    message = (vplan['entries'][sha1] || '').strip
                    unless message.empty?
                        p_yw = Date.parse(datum).strftime('%Y-%V')
                        day_messages[p_yw] ||= {}
                        day_messages[p_yw][target] ||= {}
                        day_messages[p_yw][target][datum] ||= []
                        day_messages[p_yw][target][datum] << message
                    end
                end
            end
            vplan['entries'].each_pair do |sha1, jentry|
                # STDERR.puts "#{datum} #{sha1} #{jentry.to_json}"
                before_stunde = false
                stunde_range = []
                # TODO: fix this
                next unless jentry.is_a? Array
                if jentry[0].nil?
                    if DASHBOARD_SERVICE == 'ruby'
                        debug "ATTENTION: #{datum} #{sha1} #{jentry.to_json}"
                    end
                    next
                end
                if jentry[0].include?('-')
                    parts = jentry[0].split('-').map { |x| x.strip.to_i }
                    stunde_range = (parts[0]..parts[1]).to_a
                elsif jentry[0].include?('/')
                    parts = jentry[0].split('/').map { |x| x.strip.to_i }
                    stunde_range = (parts[1]..parts[1]).to_a
                    before_stunde = true
                else
                    stunde_range = (jentry[0].to_i..jentry[0].to_i).to_a
                end
                stunde_range.each do |stunde|
                    # 0: stunde
                    # 1: klasse (old, new)
                    # 2: lehrer (old, new)
                    # 3: fach (old, new)
                    # 4: raum (old, new)
                    # 5: vertretungs_text

                    entry = {
                        # :vnr => parts[0].to_i,
                        :sha1 => sha1,
                        :datum => datum,
                        :stunde => stunde,
                        :klassen_alt => Set.new((jentry[1][0] || '').gsub('~', '/').gsub(',', '/').split('/')).to_a.map { |x| x.strip }.reject { |x| x.empty? }.sort,
                        :klassen_neu => Set.new((jentry[1][1] || '').gsub('~', '/').gsub(',', '/').split('/')).to_a.map { |x| x.strip }.reject { |x| x.empty? }.sort,
                        :lehrer_alt => jentry[2][0].nil? ? [] : [jentry[2][0]],
                        :lehrer_neu => jentry[2][1].nil? ? [] : [jentry[2][1]],
                        :fach_alt => (jentry[3][0] || '').gsub('/', '-'),
                        :fach_neu => (jentry[3][1] || '').gsub('/', '-'),
                        :raum_alt => (jentry[4][0] || '').gsub('~', '/').gsub(',', '/').split('/').map { |x| x.strip }.join('/'),
                        :raum_neu => (jentry[4][1] || '').gsub('~', '/').gsub(',', '/').split('/').map { |x| x.strip }.join('/'),
                        :vertretungs_text => jentry[5],
                    }

                    # TODO: IMPORTANT: This ignores all Testing entries as a temporary fix
                    if entry[:fach_alt] == 'Testung' || entry[:fach_neu] == 'Testung'
                        next
                    end

                    if before_stunde
                        entry[:before_stunde] = true
                    end

                    entry.keys.each do |k|
                        if (entry[k].is_a?(String) || entry[k].is_a?(Array)) && entry[k].empty?
                            entry.delete(k)
                        end
                    end

                    key_parts = [
                        entry[:stunde],
                        (entry[:klassen_alt] || []).join('/'),
                        (entry[:klassen_neu] || []).join('/'),
                        entry[:fach_alt] || '',
                        entry[:fach_neu] || '',
                        entry[:raum_alt] || '',
                        entry[:raum_neu] || '',
                        entry[:vertretungs_text] || ''
                    ]
                    key = key_parts.join('/')
                    day_entries_merge_teachers[key] ||= []
                    day_entries_merge_teachers[key] << entry
                end
            end
            day_entries_merge_teachers.values.each do |_entries|
                # all entries in 'entries' only differ in their teachers, so let's merge them

                # debug_this = false
                # if ENV['DASHBOARD_SERVICE'] == 'timetable' && datum == '2021-05-11' && _entries.size > 1 && (_entries.first[:klassen_neu] || []).include?('8a')
                #     # STDERR.puts _entries.to_yaml
                #     debug_this = true
                # end
                merged_entry = _entries.first.dup
                (1..._entries.size).each do |i|
                    other = _entries[i]
                    [:lehrer_alt, :lehrer_neu].each do |key|
                        if other[key]
                            merged_entry[key] ||= []
                            merged_entry[key] << other[key].first
                        end
                    end
                end
                # if debug_this
                #     STDERR.puts merged_entry.to_yaml
                # end
                entries << merged_entry
            end
        end

        vertretungen = {}
        entries.each do |entry|
            vertretungen[entry[:datum]] ||= []
            vertretungen[entry[:datum]] << entry
        end
        all_lessons[:historic_lessons_for_shorthand] = historic_lessons_for_shorthand
        return all_lessons, vertretungen, vplan_timestamp, day_messages, lesson_key_back_tr, original_lesson_key_for_lesson_key
    end
    
    def parse_pausenaufsichten(config)
        all_pausenaufsichten = {:aufsichten => {}, :start_dates => []}
        Dir['/data/pausenaufsichten/*.TXT'].sort.each do |path|
            start_date = File.basename(path).sub('.TXT', '')
            next if start_date < config[:first_school_day]
            separator = start_date < '2023-08-28' ? "\t" : ","
            all_pausenaufsichten[:start_dates] << start_date
            all_pausenaufsichten[:aufsichten][start_date] = {}
            File.open(path, File.basename(path) >= '2020-10-26.TXT' ? 'r:utf-8' : 'r:iso-8859-1') do |f|
                f.each_line do |line|
                    line = line.encode('utf-8')
                    parts = line.split(separator).map do |x|
                        x = x.strip
                        if x[0] == '"' && x[x.size - 1] == '"'
                            x = x[1, x.size - 2]
                        end
                        x.strip
                    end
                    where = parts[0]
                    shorthand = parts[1]
                    next if (shorthand || '').empty?
                    dow = parts[2].to_i - 1
                    stunde = parts[3].to_i
                    #minutes = parts[4].to_i
                    minutes = AUFSICHT_DAUER[stunde]
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

        all_pausenaufsichten[:start_date_for_date] = {}
        d = Date.parse(config[:first_day])
        end_date = Date.parse(config[:last_day])
        index = 0
        unless all_pausenaufsichten[:start_dates].empty?
            while d <= end_date do
                ds = d.strftime('%Y-%m-%d')
                while ds >= (all_pausenaufsichten[:start_dates][index + 1] || '') && (index < all_pausenaufsichten[:start_dates].size - 1)
                    index += 1
                end
                if ds >= all_pausenaufsichten[:start_dates][index]
                    all_pausenaufsichten[:start_date_for_date][ds] = all_pausenaufsichten[:start_dates][index]
                end
                d += 1
            end
        end

        return all_pausenaufsichten
    end
    
    def parse_kurswahl(user_info, lessons, lesson_key_tr, original_lesson_key_for_lesson_key, shorthands)
        kurse_for_schueler = {}
        schueler_for_kurs = {}
        email_for_name = {}
        user_info.each_pair do |email, info|
            name = "#{info[:last_name].split(', ').reverse.join(' ')}, #{info[:official_first_name]}"
            email_for_name[name] = email
            name = "#{info[:last_name].split(', ').reverse.join(' ')}, #{info[:display_first_name]}"
            email_for_name[name] = email
            name = "#{info[:last_name].split(', ').reverse.join(' ')}, #{info[:first_name]}"
            email_for_name[name] = email
        end
        lesson_keys_for_tag = {}
        lessons[:lesson_keys].keys.each do |lesson_key|
            unless (Set.new(lessons[:lesson_keys][lesson_key][:klassen]) & Set.new(['11', '12'])).empty?
                tag = "#{lessons[:lesson_keys][lesson_key][:lehrer].join(',')}/#{lesson_key.split('_').first}"
                lesson_keys_for_tag[tag] ||= []
                lesson_keys_for_tag[tag] << lesson_key
            end
        end
        kurs_ids_for_tag = {}
        emails_for_kurs_id = {}
        kurs_id_tr = {}
        if File.exist?('/data/kurswahl/kurs_id_tr.yaml')
            kurs_id_tr = YAML.load(File.read('/data/kurswahl/kurs_id_tr.yaml'))
        end
        Dir['/data/kurswahl/csv/2024-01/**/*.csv'].sort.each do |path|
            begin
                File.open(path) do |f|
                    f.each_line do |line|
                        line = line.force_encoding('CP1252')
                        line = line.encode('UTF-8')
                        line.strip!
                        next if line.empty?
                        parts = line.split(';')
                        sus_name = parts[0]
                        shorthand = parts[2]
                        fach = parts[3].split('-').first
                        tag = "#{shorthand}/#{fach}"
                        kurs_id = File.basename(path).split('.').first
                        kurs_ids_for_tag[tag] ||= Set.new()
                        kurs_ids_for_tag[tag] << kurs_id
                        while sus_name.length > 0
                            break if email_for_name.include?(sus_name)
                            name_parts = sus_name.split(' ')
                            sus_name = name_parts[0, name_parts.size - 1].join(' ')
                        end
                        unless shorthands.include?(shorthand)
                            STDERR.puts "Warning: Unknown shorthand »#{shorthand}«"
                            next
                        end
                        unless email_for_name.include?(sus_name)
                            STDERR.puts "Warning: Unknown SuS name »#{sus_name}« in #{File.basename(path)}\n#{line}"
                            next
                        end
                        emails_for_kurs_id[kurs_id] ||= []
                        emails_for_kurs_id[kurs_id] << email_for_name[sus_name]
                    end
                end
            rescue StandardError => e
                if DASHBOARD_SERVICE == 'ruby'
                    STDERR.puts "Error parsing #{path}: #{e}"
                end
            end
        end
        debug_logs = StringIO.open do |io|
            kurs_ids_for_tag.each_pair { |tag, ids| kurs_ids_for_tag[tag] = ids.to_a }
            (Set.new(kurs_ids_for_tag.keys) | Set.new(lesson_keys_for_tag.keys)).to_a.sort.each do |tag|
                if kurs_ids_for_tag[tag] && lesson_keys_for_tag[tag]
                    if kurs_ids_for_tag[tag].size == 1 && lesson_keys_for_tag[tag].size == 1
                        # normal one on one mapping
                        kurs_id_tr[kurs_ids_for_tag[tag].first] = lesson_keys_for_tag[tag].first
                        next
                    end
                    if kurs_ids_for_tag[tag].size == 2 && lesson_keys_for_tag[tag].size == 1
                        if lesson_keys_for_tag[tag].first =~ /11~12$/
                            kursnummern = kurs_ids_for_tag[tag].map { |x| x.match(/(\d+)_/)[1].to_i }.sort
                            if kursnummern[0] < 100 && kursnummern[1] >= 100
                                # ["Gk04_mu","Gk105_mu"] ["mu_11~12"] (jahrgangsuebergreifend)
                                kurs_id_tr[kurs_ids_for_tag[tag].first] = lesson_keys_for_tag[tag].first
                                kurs_id_tr[kurs_ids_for_tag[tag].last] = lesson_keys_for_tag[tag].first
                                next
                            end
                        end
                    end
                end
                io.puts "#{tag}: #{kurs_ids_for_tag[tag].to_json} #{lesson_keys_for_tag[tag].to_json}"
            end
            io.string
        end

        unassigned_kurs_ids = []

        emails_for_kurs_id.each_pair do |kurs_id, emails|
            if kurs_id_tr[kurs_id]
                lesson_key = kurs_id_tr[kurs_id]
                if lessons[:lesson_keys].include?(lesson_key)
                    emails.each do |email|
                        schueler_for_kurs[lesson_key] ||= Set.new()
                        schueler_for_kurs[lesson_key] << email
                        kurse_for_schueler[email] ||= Set.new()
                        kurse_for_schueler[email] << lesson_key
                    end
                else
                    unassigned_kurs_ids << kurs_id
                end
            else
                unassigned_kurs_ids << kurs_id
            end
        end

        if DASHBOARD_SERVICE == 'ruby'
            unless unassigned_kurs_ids.empty?
                STDERR.puts ">>> Warning: Could not assign #{unassigned_kurs_ids.size} of #{emails_for_kurs_id.size} kurs IDs:"
                unassigned_kurs_ids.each do |kurs_id|
                    STDERR.puts "#{kurs_id}"
                end
                STDERR.puts ">>> See here for details:"
                STDERR.puts debug_logs
            end
        end

        return kurse_for_schueler, schueler_for_kurs
    end

    def parse_wahlpflichtkurswahl(user_info, lessons, lesson_key_tr, schueler_for_klasse)
#         debug "Parsing wahlpflichtkurswahl..."
        schueler_for_lesson_key = {}
        unassigned_names = Set.new()
        begin
            if File.exist?('/data/kurswahl/wahlpflicht.yaml')
                wahlpflicht = YAML.load(File.read('/data/kurswahl/wahlpflicht.yaml'))
                wahlpflicht.each_pair do |lesson_key, sus|
                    lesson_key = lesson_key_tr[lesson_key] || lesson_key
                    unless lessons[:lesson_keys].include?(lesson_key)
                        debug "NOTICE -- Wahlpflicht: Skipping #{lesson_key} because it's unknown."
                        next
                    end
                    sus.each do |name|
                        if name[0] == '@'
                            klasse = name.sub('@', '').split('_').first
                            specifier = name.sub('@', '').sub(klasse, '')
                            schueler_for_lesson_key[lesson_key] ||= Set.new()
                            schueler_for_klasse[klasse].each do |email|
                                if specifier == '_sesb'
                                    next unless user_info[email][:sesb]
                                elsif specifier == '_not_sesb'
                                    next if user_info[email][:sesb]
                                else
                                    raise "Unknown specifier in wahlpflicht.yaml: #{specifier}!"
                                end
                                schueler_for_lesson_key[lesson_key] << email
                            end
                        else
                            email = nil
                            emails = user_info.select do |email, user_info|
                                last_name = user_info[:last_name]
                                first_name = user_info[:first_name]
                                official_first_name = user_info[:official_first_name]
                                "#{first_name} #{last_name}" == name ||
                                "#{last_name}, #{first_name}" == name ||
                                "#{last_name}, #{official_first_name}" == name ||
                                email.sub("@#{SCHUL_MAIL_DOMAIN}", '') == name ||
                                email == name
                            end.keys
                            if emails.size == 1
                                email = emails.to_a.first
                            else
                                unassigned_names << name
                            end
                            unless email
                                debug "Wahlpflichtkurswahl: Can't assign #{name}!"
                            end
                            if email
                                schueler_for_lesson_key[lesson_key] ||= Set.new()
                                schueler_for_lesson_key[lesson_key] << email
                            end
                        end
                    end
                end
            end
        rescue
            debug '-' * 50
            debug "ATTENTION: Error parsing wahlpflicht.yaml, skipping..."
            debug '-' * 50
            raise
        end
        unless unassigned_names.empty?
            debug "Kurswahl: Can't assign these names!"
            debug unassigned_names.to_a.sort.to_yaml
        end
        # debug "Wahlpflichtkurswahl: got SuS for #{schueler_for_lesson_key.size} lesson keys."
        return schueler_for_lesson_key
    end

    def parse_sesb(user_info, schueler_for_klasse)
#         debug "Parsing wahlpflichtkurswahl..."
        sesb_sus = Set.new()
        unassigned_names = Set.new()
        begin
            if File.exist?('/data/schueler/sesb.yaml')
                sus = YAML.load(File.read('/data/schueler/sesb.yaml'))
                sus.each do |name|
                    if name[0] == '@'
                        klasse = name.sub('@', '')
                        schueler_for_klasse[klasse].each do |email|
                            sesb_sus << email
                        end
                    else
                        email = nil
                        emails = user_info.select do |email, user_info|
                            last_name = user_info[:last_name]
                            first_name = user_info[:first_name]
                            "#{first_name} #{last_name}" == name || email.sub("@#{SCHUL_MAIL_DOMAIN}", '') == name || email == name
                        end.keys
                        if emails.size == 1
                            email = emails.to_a.first
                        else
                            unassigned_names << name
                        end
                        unless email
                            debug "SESB: Can't assign #{name}!"
                        end
                        if email
                            sesb_sus << email
                        end
                    end
                end
            end
        rescue
            debug '-' * 50
            debug "ATTENTION: Error parsing sesb.yaml, skipping..."
            debug '-' * 50
            raise
        end
        unless unassigned_names.empty?
            debug "SESB: Can't assign these names!"
            debug unassigned_names.to_a.sort.to_yaml
        end
        # debug "Wahlpflichtkurswahl: got SuS for #{schueler_for_lesson_key.size} lesson keys."
        return sesb_sus
    end
        
    def parse_current_email_addresses
        email_addresses = []
        email_accounts_path = '/data/current-email-addresses.csv'
        if File.exist?(email_accounts_path)
            CSV.foreach(email_accounts_path, headers: true, col_sep: ';') do |row|
                email = row.to_h['E-Mail-Adresse']
                email_addresses << email
            end
        end
        return email_addresses
    end
end
