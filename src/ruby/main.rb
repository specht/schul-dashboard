require 'base64'
require 'cgi'
require 'csv'
require 'curb'
require 'date'
require 'digest/sha1'
require 'htmlentities'
require 'json'
require 'jwt'
require 'kramdown'
require 'mail'
require 'neography'
require 'net/http'
require 'net/imap'
require 'nextcloud'
require 'nokogiri'
require 'open3'
require 'prawn/qrcode'
require 'prawn/measurement_extensions'
require 'prawn-styled-text'
require 'rotp'
require 'rqrcode'
require 'set'
require 'sinatra/base'
require 'sinatra/cookies'
require 'time'
require 'timeout'
require 'user_agent_parser'
require 'write_xlsx'
require 'yaml'

require './background-renderer.rb'
require './credentials.rb'
require './include/event.rb'
require './include/user.rb'
require './parser.rb'

USER_AGENT_PARSER = UserAgentParser::Parser.new
WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']

HOURS_FOR_KLASSE = {}

Neography.configure do |config|
    config.protocol             = "http"
    config.server               = "neo4j"
    config.port                 = 7474
    config.directory            = ""  # prefix this path with '/'
    config.cypher_path          = "/cypher"
    config.gremlin_path         = "/ext/GremlinPlugin/graphdb/execute_script"
    config.log_file             = "/dev/shm/neography.log"
    config.log_enabled          = false
    config.slow_log_threshold   = 0    # time in ms for query logging
    config.max_threads          = 20
    config.authentication       = nil  # 'basic' or 'digest'
    config.username             = nil
    config.password             = nil
    config.parser               = MultiJsonParser
    config.http_send_timeout    = 1200
    config.http_receive_timeout = 1200
    config.persistent           = true
end

module QtsNeo4j

    class CypherError < StandardError
        def initialize(code, message)
            @code = code
            @message = message
        end
        
        def to_s
            "Cypher Error\n#{@code}\n#{@message}"
        end
    end

    def transaction(&block)
        @neo4j ||= Neography::Rest.new
        @tx ||= []
        @tx << (@tx.empty? ? @neo4j.begin_transaction : nil)
        begin
            result = yield
            item = @tx.pop
            unless item.nil?
                @neo4j.commit_transaction(item)
            end
            result
        rescue
            item = @tx.pop
            unless item.nil?
                begin
                    @neo4j.rollback_transaction(item)
                rescue
                end
            end
            raise
        end
    end

    class ResultRow
        def initialize(v)
            @v = Hash[v.map { |k, v| [k.to_sym, v] }]
        end

        def props
            @v
        end
    end

    def neo4j_query(query_str, options = {})
        transaction do
            temp_result = @neo4j.in_transaction(@tx.first, [query_str, options])
            if temp_result['errors'] && !temp_result['errors'].empty?
                STDERR.puts "This:"
                STDERR.puts temp_result.to_yaml
                raise CypherError.new(temp_result['errors'].first['code'], temp_result['errors'].first['message'])
            end
            result = []
            temp_result['results'].first['data'].each_with_index do |row, row_index|
                result << {}
                temp_result['results'].first['columns'].each_with_index do |key, key_index|
                    if row['row'][key_index].is_a? Hash
                        result.last[key] = ResultRow.new(row['row'][key_index])
                    else
                        result.last[key] = row['row'][key_index]
                    end
                end
            end
            result
        end
    end

    def neo4j_query_expect_one(query_str, options = {})
        transaction do
            result = neo4j_query(query_str, options).to_a
            raise "Expected one result but got #{result.size}" unless result.size == 1
            result.first
        end
    end
end

class Neo4jGlobal
    include QtsNeo4j
end

$neo4j = Neo4jGlobal.new

class RandomTag
    BASE_31_ALPHABET = '0123456789bcdfghjklmnpqrstvwxyz'
    def self.to_base31(i)
        result = ''
        while i > 0
            result += BASE_31_ALPHABET[i % 31]
            i /= 31
        end
        result
    end

    def self.generate(length = 12)
        self.to_base31(SecureRandom.hex(length).to_i(16))[0, length]
    end
end    

def mail_html_to_plain_text(s)
    s.gsub('<p>', "\n\n").gsub(/<br\s*\/?>/, "\n").gsub(/<\/?[^>]*>/, '').strip
end

def deliver_mail(&block)
    mail = Mail.new do
        charset = 'UTF-8'
        message = self.instance_eval(&block)
        html_part do
            content_type 'text/html; charset=UTF-8'
            body message
        end
        
        text_part do
            content_type 'text/plain; charset=UTF-8'
            body mail_html_to_plain_text(message)
        end
    end
    mail.deliver!
end

def parse_markdown(s)
    s ||= ''
    Kramdown::Document.new(s, :smart_quotes => %w{sbquo lsquo bdquo ldquo}).to_html.strip
end

def join_with_sep(list, a, b)
    [list[0, list.size - 1].join(a), list.last].join(b)
end

class SetupDatabase
    include QtsNeo4j
    
    def setup(main)
        delay = 1
        10.times do
            begin
                neo4j_query("MATCH (n) RETURN n LIMIT 1;")
                break unless ENV['DASHBOARD_SERVICE'] == 'ruby'
                transaction do
                    STDERR.puts "Removing all constraints and indexes..."
                    indexes = []
                    neo4j_query("CALL db.constraints").each do |constraint|
                        query = "DROP #{constraint['description']}"
                        neo4j_query(query)
                    end
                    neo4j_query("CALL db.indexes").each do |index|
                        query = "DROP #{index['description']}"
                        neo4j_query(query)
                    end
                    
                    STDERR.puts "Setting up constraints and indexes..."
                    neo4j_query("CREATE CONSTRAINT ON (n:User) ASSERT n.email IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Session) ASSERT n.sid IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Lesson) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:WebsiteEvent) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:TextComment) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:AudioComment) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Message) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Event) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Poll) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:PollRun) ASSERT n.key IS UNIQUE")
                    neo4j_query("CREATE INDEX ON :LoginCode(code)")
                    neo4j_query("CREATE INDEX ON :NextcloudLoginCode(code)")
                    neo4j_query("CREATE INDEX ON :LessonInfo(offset)")
                    neo4j_query("CREATE INDEX ON :TextComment(offset)")
                    neo4j_query("CREATE INDEX ON :AudioComment(offset)")
                    neo4j_query("CREATE INDEX ON :ExternalUser(entered_by)")
                    neo4j_query("CREATE INDEX ON :ExternalUser(email)")
                    neo4j_query("CREATE INDEX ON :PredefinedExternalUser(email)")
                    neo4j_query("CREATE INDEX ON :News(date)")
                    neo4j_query("CREATE INDEX ON :PollRun(start_date)")
                    neo4j_query("CREATE INDEX ON :PollRun(end_date)")
                end
                transaction do
                    main.class_variable_get(:@@user_info).keys.each do |email|
                        neo4j_query(<<~END_OF_QUERY, :email => email)
                            MERGE (u:User {email: {email}})
                        END_OF_QUERY
                    end
                end
                transaction do
                    neo4j_query(<<~END_OF_QUERY, :email => "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: {email}})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "kurs.tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: {email}})
                    END_OF_QUERY
                end
                transaction do
                    main.class_variable_get(:@@predefined_external_users)[:recipients].each_pair do |k, v|
                        next if v[:entries]
                        neo4j_query(<<~END_OF_QUERY, :email => k, :name => v[:label])
                            MERGE (n:PredefinedExternalUser {email: {email}, name: {name}})
                        END_OF_QUERY
                    end
                end
                STDERR.puts "Setup finished."
                break
            rescue
                STDERR.puts $!
                STDERR.puts "Retrying setup after #{delay} seconds..."
                sleep delay
                delay += 1
            end
        end
    end
end

class Main < Sinatra::Base
    include QtsNeo4j
    helpers Sinatra::Cookies

    configure do
        set :show_exceptions, false
    end

    def self.iterate_school_days(options = {}, &block)
        day = Date.parse(@@config[:first_day])
        last_day = Date.parse(@@config[:last_day])
        while day <= last_day do
            ds = day.to_s
            off_day = @@off_days.include?(ds)
            unless off_day
                yield ds, day.wday - 1
            end
            day += 1
        end
    end
    
    def iterate_school_days(options = {}, &block)
        self.class.iterate_school_days(options, &block)
    end

    def self.gen_password_for_email(email)
        chars = 'BCDFGHJKMNPQRSTVWXYZ23456789'.split('')
        sha2 = Digest::SHA256.new()
        sha2 << EMAIL_PASSWORD_SALT
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
                c = chars.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
            password += '-'
            4.times do 
                c = chars.sample.dup
                c.downcase! if [0, 1].sample == 1
                password += c
            end
        end
        password
    end
    
    def tr_klasse(klasse)
        KLASSEN_TR[klasse] || klasse
    end
    
    def self.tr_klasse(klasse)
        KLASSEN_TR[klasse] || klasse
    end
    
    def self.collect_data
        @@user_info = {}
        @@shorthands = {}
        @@schueler_for_klasse = {}
        @@faecher = {}
        @@ferien_feiertage = []
        @@lehrer_order = []
        @@klassen_order = []
                           
        @@index_for_klasse = {}
        @@predefined_external_users = {}
        
        parser = Parser.new()
        parser.parse_faecher do |fach, bezeichnung|
            @@faecher[fach] = bezeichnung
        end
        @@off_days = Set.new()
        parser.parse_ferien_feiertage do |t0, t1, title|
            @@ferien_feiertage << {:from => t0, :to => t1, :title => title}
            day = Date.parse(t0)
            last = Date.parse(t1)
            while day <= last
                @@off_days << day.to_s
                day += 1
            end
        end
        begin
            @@config = YAML::load_file('/data/config.yaml')
        rescue
            @@config = {
                :first_day => '2020-06-25',
                :first_school_day => '2020-08-10',
                :last_day => '2021-08-06'
            }
            STDERR.puts "Can't read /data/config.yaml, using a few default values:"
            STDERR.puts @@config.to_yaml
        end
        parser.parse_lehrer do |record|
            next unless record[:can_log_in]
            @@user_info[record[:email]] = {
                :teacher => true,
                :shorthand => record[:shorthand],
                :first_name => record[:first_name],
                :last_name => record[:last_name],
                :titel => record[:titel],
                :display_name => record[:display_name],
                :display_last_name => record[:display_last_name],
                :email => record[:email],
                :can_log_in => record[:can_log_in],
                :nc_login => record[:nc_login],
                :initial_nc_password => record[:initial_nc_password]
            }
            @@shorthands[record[:shorthand]] = record[:email]
            @@lehrer_order << record[:email]
        end
        ADMIN_USERS.each do |email|
            @@user_info[email][:admin] = true
        end
        (CAN_SEE_ALL_TIMETABLES_USERS + ADMIN_USERS).each do |email|
            @@user_info[email][:can_see_all_timetables] = true
        end
        (CAN_UPLOAD_VPLAN_USERS + ADMIN_USERS).each do |email|
            @@user_info[email][:can_upload_vplan] = true
        end
        (CAN_UPLOAD_FILES_USERS + ADMIN_USERS).each do |email|
            @@user_info[email][:can_upload_files] = true
        end
        (CAN_MANAGE_NEWS_USERS + ADMIN_USERS).each do |email|
            @@user_info[email][:can_manage_news] = true
        end

        @@klassenleiter = {}
        parser.parse_klassenleiter do |record|
            @@klassenleiter[record[:klasse]] = record[:klassenleiter]
        end
        
        @@lehrer_order.sort!() do |a, b|
            la = @@user_info[a][:shorthand].downcase 
            lb = @@user_info[b][:shorthand].downcase 
            la = 'zzz' + la if la[0] == '_'
            lb = 'zzz' + lb if lb[0] == '_'
            la <=> lb
        end
        @@klassen_order = KLASSEN_ORDER
        @@klassen_order.each.with_index { |k, i| @@index_for_klasse[k] = i }
        @@klassen_id = {}
        @@klassen_order.each do |klasse|
            @@klassen_id[klasse] = Digest::SHA2.hexdigest(KLASSEN_ID_SALT + klasse).to_i(16).to_s(36)[0, 16]
        end
                     
        self.fix_stundenzeiten()
                           
        parser.parse_schueler do |record|
            @@user_info[record[:email]] = {
                :teacher => false,
                :first_name => record[:first_name],
                :display_first_name => record[:display_first_name],
                :display_last_name => record[:display_last_name],
                :last_name => record[:last_name],
                :display_name => record[:display_name],
                :email => record[:email],
                :id => record[:id],
                :klasse => record[:klasse],
                :geschlecht => record[:geschlecht],
                :nc_login => record[:email].split('@').first.sub(/\.\d+$/, ''),
                :initial_nc_password => record[:initial_nc_password]
            }
            @@schueler_for_klasse[record[:klasse]] ||= []
            @@schueler_for_klasse[record[:klasse]] << record[:email]
        end
        @@user_info.keys.each do |email|
            @@user_info[email][:id] = Digest::SHA2.hexdigest(USER_ID_SALT + email).to_i(16).to_s(36)[0, 16]
        end
        
        # add Eltern
        @@predefined_external_users = {:groups => [], :recipients => {}}
        @@klassen_order.each do |klasse|
            next unless @@schueler_for_klasse.include?(klasse)
            @@predefined_external_users[:groups] << "/eltern/#{klasse}"
            @@predefined_external_users[:recipients]["/eltern/#{klasse}"] = {
                :label => "Eltern der Klasse #{self.tr_klasse(klasse)}",
                :entries => @@schueler_for_klasse[klasse].map { |x| 'eltern.' + @@user_info[x][:email] }
            }
            @@schueler_for_klasse[klasse].each do |x| 
                eltern_email = 'eltern.' + @@user_info[x][:email]
                @@predefined_external_users[:recipients][eltern_email] = {
                    :label => "Eltern von #{@@user_info[x][:display_name]}"
                }
            end
        end

        @@lessons, @@vertretungen, @@vplan_timestamp = parser.parse_timetable(@@config)
        merged_lesson_keys = {}
        @@lessons[:lesson_keys].keys.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            next if (Set.new(lesson_info[:klassen]) & Set.new(@@klassen_order)).empty?
            temp = "#{lesson_info[:fach]}/#{lesson_info[:klassen].sort.join(',')}/#{lesson_info[:lehrer].sort.join(',')}"
            merged_lesson_keys[temp] ||= []
            merged_lesson_keys[temp] << lesson_key
        end
        merged_lesson_keys.keys.each do |temp|
            merged_lesson_keys[temp].sort!
        end
        lesson_key_tr = {}
        # merge lesson_keys
        merged_lesson_keys.each_pair do |temp, lesson_keys|
            next if lesson_keys.size == 1
            klassen = Set.new()
            lesson_keys.each do |lesson_key|
                klassen |= Set.new(@@lessons[:lesson_keys][lesson_key][:klassen])
            end
            lesson_keys.each.with_index do |lesson_key, i|
                if i > 0
                    lesson_key_tr[lesson_key] = lesson_keys.first
                end
            end
        end
        lesson_key_tr = self.fix_lesson_key_tr(lesson_key_tr)

        # patch lesson_keys in @@lessons and @@vertretungen
        @@lessons, @@vertretungen = parser.parse_timetable(@@config, lesson_key_tr)
        # patch @@faecher
        @@lessons[:lesson_keys].each_pair do |lesson_key, info|
            unless @@faecher[lesson_key]
                x = lesson_key.split('~').first.split('-').first
                @@faecher[info[:fach]] = @@faecher[x] if @@faecher[x]
            end
        end
        today = Time.now.strftime('%Y-%m-%d')
        today = @@config[:first_school_day] if today < @@config[:first_school_day]
        today = @@config[:last_day] if today > @@config[:last_day]
        today = @@lessons[:start_date_for_date][today]
        timetable_today = @@lessons[:timetables][today]
#         File.open('/gen/timetable.csv', 'w') do |fout|
#             @@lessons[:lesson_keys].keys.sort.group_by do |a|
#                 a.split('~').first.split('-').first
#             end.each do |common_prefix, lesson_keys|
#                 counts = Set.new()
#                 lehrer = Set.new()
#                 lesson_keys.each do |lesson_key|
#                     lesson_info = @@lessons[:lesson_keys][lesson_key]
#                     count = 0
#                     ((timetable_today[lesson_key] || {})[:stunden] || {}).keys.each do |dow|
#                         count += timetable_today[lesson_key][:stunden][dow].size
#                     end
#                     counts << count || 0
#                     lesson_info[:lehrer].each do |shorthand|
#                         next if shorthand.nil?
#                         next if @@shorthands[shorthand].nil?
#                         lehrer << (@@user_info[@@shorthands[shorthand]] || {})[:display_last_name] || shorthand
#                     end
#                 end
#                 fout.puts "#{common_prefix},#{counts.to_a.sort.join('/')},#{lehrer.to_a.sort.join('/')}"
#             end
#         end
        pretty_folder_names_for_teacher = {}
        @@lessons[:lesson_keys].keys.each do |lesson_key|
            @@lessons[:lesson_keys][lesson_key][:id] = Digest::SHA2.hexdigest(LESSON_ID_SALT + lesson_key).to_i(16).to_s(36)[0, 16]
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            fach = lesson_info[:fach]
            fach = @@faecher[fach] || fach
            pretty_folder_name = "#{fach.gsub('/', '-')} (#{lesson_info[:klassen].sort.join(', ')})"
            lesson_info[:lehrer].each do |shorthand|
                pretty_folder_names_for_teacher[shorthand] ||= {}
                pretty_folder_names_for_teacher[shorthand][pretty_folder_name] ||= Set.new()
                pretty_folder_names_for_teacher[shorthand][pretty_folder_name] << lesson_key
            end
            @@lessons[:lesson_keys][lesson_key][:pretty_folder_name] = pretty_folder_name
        end
        @@lessons[:lesson_keys].keys.each do |lesson_key|
            lesson_info = @@lessons[:lesson_keys][lesson_key]
            pretty_folder_name = lesson_info[:pretty_folder_name]
            more_than_one = false
            lesson_info[:lehrer].each do |shorthand|
                if ((pretty_folder_names_for_teacher[shorthand] || {})[pretty_folder_name] || Set.new()).size > 1
                    (pretty_folder_names_for_teacher[shorthand] || {})[pretty_folder_name].sort.each.with_index do |lesson_key, _|
                        @@lessons[:lesson_keys][lesson_key][:pretty_folder_name] = pretty_folder_name.dup.insert(pretty_folder_name.rindex('('), ('A'.ord + _).chr + ' ')
                    end
                    pretty_folder_names_for_teacher[shorthand].delete(pretty_folder_name)
                end
            end
        end
        @@lessons_for_klasse = {}
        @@lessons[:lesson_keys].each_pair do |lesson_key, lesson|
            lesson[:klassen].each do |klasse|
                @@lessons_for_klasse[klasse] ||= []
                @@lessons_for_klasse[klasse] << lesson_key
            end
        end
        @@lessons_for_shorthand = {}
        @@lessons[:lesson_keys].each_pair do |lesson_key, lesson|
            lesson[:lehrer].each do |lehrer|
                @@lessons_for_shorthand[lehrer] ||= []
                @@lessons_for_shorthand[lehrer] << lesson_key
            end
        end
        
        @@klassen_for_shorthand = {}
        @@teachers_for_klasse = {}
        
        self.fix_lessons_for_shorthand()

        @@lessons_for_shorthand.keys.each do |shorthand|
            @@lessons_for_shorthand[shorthand].sort! do |_a, _b|
                a = @@lessons[:lesson_keys][_a]
                b = @@lessons[:lesson_keys][_b]
                (a[:fach] == b[:fach]) ?
                (((a[:klassen] || []).map { |x| @@klassen_order.index(x) || -1}.min || 0) <=> ((b[:klassen] || []).map { |x| @@klassen_order.index(x) || -1 }.min || 0)) :
                (a[:fach] <=> b[:fach])
            end
        end
        @@lessons[:lesson_keys].each_pair do |lesson_key, lesson|
            lesson[:klassen].each do |klasse|
                if @@klassen_order.include?(klasse)
                    lesson[:lehrer].each do |lehrer|
                        @@klassen_for_shorthand[lehrer] ||= Set.new()
                        @@klassen_for_shorthand[lehrer] << klasse
                    end
                end
            end
        end
        @@klassen_for_shorthand.keys.each do |shorthand|
            @@klassen_for_shorthand[shorthand] = @@klassen_for_shorthand[shorthand].to_a.sort do |a, b|
                @@klassen_order.index(a) <=> @@klassen_order.index(b)
            end
        end
        unless @@lessons[:start_dates].empty?
            @@lessons[:timetables][@@lessons[:start_dates].last].each_pair do |lesson_key, lesson_info|
                lesson = @@lessons[:lesson_keys][lesson_key]
                lesson[:klassen].each do |klasse|
                    @@teachers_for_klasse[klasse] ||= {}
                    lesson[:lehrer].each do |lehrer|
                        @@teachers_for_klasse[klasse][lehrer] ||= {}
                        @@teachers_for_klasse[klasse][lehrer][lesson[:fach]] ||= 0
                        lesson_info[:stunden].each_pair do |dow, stunden|
                            stunden.each_pair do |i, stunde|
                                @@teachers_for_klasse[klasse][lehrer][lesson[:fach]] += stunde[:count]
                            end
                        end
                    end
                end
            end
        end
        
        last_start_date = nil
        @@lessons[:start_dates].each do |start_date|
            if last_start_date
                added_lesson_keys = Set.new(@@lessons[:timetables][start_date].keys) - Set.new(@@lessons[:timetables][last_start_date].keys)
                removed_lesson_keys = Set.new(@@lessons[:timetables][last_start_date].keys) - Set.new(@@lessons[:timetables][start_date].keys)
                (added_lesson_keys + removed_lesson_keys).to_a.sort.each do |lesson_key|
                end
            end
            last_start_date = start_date
        end
        
        kurse_for_schueler, schueler_for_kurs = parser.parse_kurswahl(@@user_info.reject { |x, y| y[:teacher] }, @@lessons, lesson_key_tr)
        
        @@lessons_for_user = {}
        @@schueler_for_lesson = {}
        @@user_info.each_pair do |email, user|
            lessons = (user[:teacher] ? @@lessons_for_shorthand[user[:shorthand]] : @@lessons_for_klasse[user[:klasse]]).dup
            if kurse_for_schueler.include?(email)
                lessons = kurse_for_schueler[email].to_a
            end
            lessons ||= []
            unless user[:teacher]
                lessons.reject! do |lesson_key|
                    lesson = @@lessons[:lesson_keys][lesson_key]
                    (lesson[:fach] == 'SpoM' && user[:geschlecht] != 'w') ||
                    (lesson[:fach] == 'SpoJ' && user[:geschlecht] != 'm')
                end
            end
            @@lessons_for_user[email] = Set.new(lessons)
            unless user[:teacher]
                lessons.each do |lesson_key|
                    @@schueler_for_lesson[lesson_key] ||= []
                    @@schueler_for_lesson[lesson_key] << email
                end
            end
        end
        @@schueler_for_lesson.each_pair do |lesson_key, emails|
            emails.sort! do |a, b|
                @@user_info[a][:display_name] <=> @@user_info[b][:display_name]
            end
        end
        @@pausenaufsichten = parser.parse_pausenaufsichten()
    end    
    
    def self.compile_files(key, mimetype, paths)
        @@compiled_files[key] ||= {:timestamp => nil, :content => nil}
        
        latest_file_timestamp = paths.map do |path|
            File.mtime(File.join('/static', path))
        end.max
        
        if @@compiled_files[key][:timestamp].nil? || @@compiled_files[key][:timestamp] < latest_file_timestamp
            @@compiled_files[key][:content] = StringIO.open do |io|
                paths.each do |path|
                    io.puts File.read(File.join('/static', path))
                end
                io.string
            end
            @@compiled_files[key][:sha1] = Digest::SHA1.hexdigest(@@compiled_files[key][:content])[0, 16]
            @@compiled_files[key][:timestamp] = latest_file_timestamp
        end
    end
    
    def self.compile_js()
        files = [
            '/include/jquery/jquery-3.4.1.min.js',
            '/include/jquery-ui/jquery-ui.min.js',
            '/include/popper.js/popper.min.js',
            '/include/bootstrap/bootstrap.min.js',
            '/include/fullcalendar/main.min.js',
            '/include/fullcalendar/de.js',
            '/include/pako/pako_inflate.min.js',
            '/include/bootstrap4-toggle/bootstrap4-toggle.min.js',
            '/include/summernote/summernote-bs4.min.js',
            '/include/summernote/summernote-de-DE.min.js',
            '/include/clipboard/clipboard.min.js',
            '/include/moment/moment-with-locales.min.js',
            '/include/dropzone/dropzone.min.js',
            '/include/chart.js/Chart.min.js',
            '/code.js',
        ]
        
        self.compile_files(:js, 'application/javascript', files)
        FileUtils::rm_rf('/gen/js/')
        FileUtils::mkpath('/gen/js/')
        File.open("/gen/js/compiled-#{@@compiled_files[:js][:sha1]}.js", 'w') do |f|
            f.print(@@compiled_files[:js][:content])
        end
    end
    
    def self.compile_css()
        files = [
            '/include/bootstrap/bootstrap.min.css',
            '/include/summernote/summernote-bs4.min.css',
            '/include/fork-awesome/fork-awesome.min.css',
            '/include/fullcalendar/main.min.css',
            '/include/bootstrap4-toggle/bootstrap4-toggle.min.css',
            '/include/dropzone/dropzone.min.css',
            '/include/chart.js/Chart.min.css',
            '/styles.css'
        ]
        
        self.compile_files(:css, 'text/css', files)
        FileUtils::rm_rf('/gen/css/')
        FileUtils::mkpath('/gen/css/')
        File.open("/gen/css/compiled-#{@@compiled_files[:css][:sha1]}.css", 'w') do |f|
            f.print(@@compiled_files[:css][:content])
        end
    end
    
    configure do
        @@compiled_files = {}
        self.collect_data()
        setup = SetupDatabase.new()
        setup.setup(self)
        @@color_scheme_colors = COLOR_SCHEME_COLORS
        @@standard_color_scheme = STANDARD_COLOR_SCHEME
        @@color_scheme_colors.map! do |s|
            ['#' + s[0][1, 6], '#' + s[0][7, 6], '#' + s[0][13, 6], s[1], s[0][0], s[2]]
        end
        @@renderer = BackgroundRenderer.new
        if ENV['DASHBOARD_SERVICE'] == 'ruby'
            @@color_scheme_colors.each do |palette|
                @@renderer.render(palette)
            end
            self.compile_js()
            self.compile_css()
        end
        STDERR.puts "Server is up and running!"
    end
    
    def assert(condition, message = 'assertion failed', suppress_backtrace = false)
        unless condition
            e = StandardError.new(message)
            e.set_backtrace([]) if suppress_backtrace
            raise e
        end
    end

    def assert_with_delay(condition, message = 'assertion failed', suppress_backtrace = false)
        unless condition
            e = StandardError.new(message)
            e.set_backtrace([]) if suppress_backtrace
            sleep 3.0
            raise e
        end
    end

    def test_request_parameter(data, key, options)
        type = ((options[:types] || {})[key]) || String
        assert(data[key.to_s].is_a?(type), "#{key.to_s} is a #{type}")
        if type == String
            assert(data[key.to_s].size <= (options[:max_value_lengths][key] || options[:max_string_length]), 'too_much_data')
        end
    end
    
    def parse_request_data(options = {})
        options[:max_body_length] ||= 512
        options[:max_string_length] ||= 512
        options[:required_keys] ||= []
        options[:optional_keys] ||= []
        options[:max_value_lengths] ||= {}
        data_str = request.body.read(options[:max_body_length]).to_s
#         STDERR.puts data_str
        @latest_request_body = data_str.dup
        begin
            assert(data_str.is_a? String)
            assert(data_str.size < options[:max_body_length], 'too_much_data')
            data = JSON::parse(data_str)
            @latest_request_body_parsed = data.dup
            result = {}
            options[:required_keys].each do |key|
                assert(data.include?(key.to_s))
                test_request_parameter(data, key, options)
                result[key.to_sym] = data[key.to_s]
            end
            options[:optional_keys].each do |key|
                if data.include?(key.to_s)
                    test_request_parameter(data, key, options)
                    result[key.to_sym] = data[key.to_s]
                end
            end
            result
        rescue
            STDERR.puts "Request was:"
            STDERR.puts data_str
            raise
        end
    end
    
    def session_user_has_streaming_button?
        return false unless PROVIDE_CLASS_STREAM
        return false unless user_logged_in?
        return false if @session_user[:teacher]
        return false if class_stream_link_for_session_user.nil?
        return false unless @session_user[:homeschooling]
        return true
    end
    
    def class_stream_link_for_session_user
        require_user!
        if PROVIDE_CLASS_STREAM && (!@session_user[:teacher]) && (!['11', '12'].include?(@session_user[:klasse]))
            "/jitsi/Klassenstreaming#{@session_user[:klasse]}"
        else
            nil
        end
    end
    
    def hsv_to_rgb(c)
        h, s, v = c[0].to_f / 360, c[1].to_f / 100, c[2].to_f / 100
        h_i = (h * 6).to_i
        f = h * 6 - h_i
        p = v * (1 - s)
        q = v * (1 - f * s)
        t = v * (1 - (1 - f) * s)
        r, g, b = v, t, p if h_i == 0
        r, g, b = q, v, p if h_i == 1
        r, g, b = p, v, t if h_i == 2
        r, g, b = p, q, v if h_i == 3
        r, g, b = t, p, v if h_i == 4
        r, g, b = v, p, q if h_i == 5
        [(r * 255).to_i, (g * 255).to_i, (b * 255).to_i]
    end


    # http://ntlk.net/2011/11/21/convert-rgb-to-hsb-hsv-in-ruby/
    def rgb_to_hsv(c)
        r = c[0] / 255.0
        g = c[1] / 255.0
        b = c[2] / 255.0
        max = [r, g, b].max
        min = [r, g, b].min
        delta = max - min
        v = max * 100

        if (max != 0.0)
            s = delta / max *100
        else
            s = 0.0
        end

        if (s == 0.0)
            h = 0.0
        else
            if (r == max)
                h = (g - b) / delta
            elsif (g == max)
                h = 2 + (b - r) / delta
            elsif (b == max)
                h = 4 + (r - g) / delta
            end

            h *= 60.0

            if (h < 0)
                h += 360.0
            end
        end
        [h, s, v]
    end

    def hex_to_rgb(c)
        r = c[1, 2].downcase.to_i(16)
        g = c[3, 2].downcase.to_i(16)
        b = c[5, 2].downcase.to_i(16)
        [r, g, b]
    end

    def mix(a, b, t)
        t1 = 1.0 - t
        return [a[0] * t1 + b[0] * t,
                a[1] * t1 + b[1] * t,
                a[2] * t1 + b[2] * t]
    end

    def rgb_to_hex(c)
        sprintf('#%02x%02x%02x', c[0].to_i, c[1].to_i, c[2].to_i)
    end
    
    def desaturate(c)
        hsv = rgb_to_hsv(hex_to_rgb(c))
        hsv[1] *= 0.7
        hsv[2] *= 0.9
        rgb_to_hex(hsv_to_rgb(hsv))
    end

    def shift_hue(c, f = 60)
        hsv = rgb_to_hsv(hex_to_rgb(c))
        hsv[0] = (hsv[0] + f) % 360.0
        rgb_to_hex(hsv_to_rgb(hsv))
    end

    def darken(c, f = 0.2)
        hsv = rgb_to_hsv(hex_to_rgb(c))
        hsv[2] *= f
        rgb_to_hex(hsv_to_rgb(hsv))
    end
    
    def get_login_stats
        login_seen = {}
        LOGIN_STATS_D.each do |d|
            login_counts = neo4j_query(<<~END_OF_QUERY, :today => (Date.today - d).to_s)
                MATCH (u:User) WHERE EXISTS(u.last_access) AND u.last_access >= {today}
                RETURN u.email;
            END_OF_QUERY
            login_counts.map { |x| x['u.email'] }.each do |email|
                login_seen[email] ||= {}
                login_seen[email][d] = true
            end
        end
        login_stats = {}
        @@klassen_order.each do |klasse|
            login_stats[klasse] = {:total => @@schueler_for_klasse[klasse].size, :count => {}}
        end
        teacher_count = 0
        sus_count = 0
        @@user_info.each_pair do |email, user|
            if user[:teacher]
                teacher_count += 1 
            else
                sus_count += 1 
            end
        end
        login_stats[:lehrer] = {:total => teacher_count, :count => {}}
        login_stats[:sus] = {:total => sus_count, :count => {}}
        login_seen.each_pair do |email, seen|
            user = @@user_info[email]
            next if user.nil?
            seen.keys.each do |d|
                if user[:teacher]
                    login_stats[:lehrer][:count][d] ||= 0
                    login_stats[:lehrer][:count][d] += 1
                else
                    login_stats[:sus][:count][d] ||= 0
                    login_stats[:sus][:count][d] += 1
                    login_stats[user[:klasse]][:count][d] ||= 0
                    login_stats[user[:klasse]][:count][d] += 1
                end
            end
        end
        login_stats
    end

    before '*' do
        if DEVELOPMENT
            self.class.compile_js()
            self.class.compile_css()
        end
        
        @latest_request_body = nil
        @latest_request_body_parsed = nil
        # before any API request, determine currently logged in user via the provided session ID
        @session_user = nil
        if request.cookies.include?('sid')
            sid = request.cookies['sid']
#             STDERR.puts "SID: [#{sid}]"
            if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
                first_sid = sid.split(',').first
                if first_sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => first_sid, :today => Date.today.to_s).to_a
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                        SET u.last_access = {today}
                        SET s.last_access = {today}
                        RETURN s, u;
                    END_OF_QUERY
                    if results.size == 1
                        session = results.first['s'].props
                        session_expiry = session[:expires]
                        if DateTime.parse(session_expiry) > DateTime.now
                            email = results.first['u'].props[:email]
                            if email == "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
                                @session_user = {
                                    :email => email,
                                    :teacher_tablet => true,
                                    :color_scheme => 'lfcbf499e0001eeba30',
                                    :can_see_all_timetables => true,
                                    :teacher => true
                                }
                            elsif email == "kurs.tablet@#{SCHUL_MAIL_DOMAIN}"
                                @session_user = {
                                    :email => email,
                                    :kurs_tablet => true,
                                    :color_scheme => 'la86fd07638a15a2b7a',
                                    :can_see_all_timetables => false,
                                    :teacher => false,
                                    :shorthands => session[:shorthands] || []
                                }
                            else
                                @session_user = @@user_info[email].dup
                                if @session_user
                                    @session_user[:font] = results.first['u'].props[:font]
                                    @session_user[:color_scheme] = results.first['u'].props[:color_scheme]
                                    @session_user[:ical_token] = results.first['u'].props[:ical_token]
                                    @session_user[:otp_token] = results.first['u'].props[:otp_token]
                                    @session_user[:homeschooling] = results.first['u'].props[:homeschooling]
                                    @session_user[:group2] = results.first['u'].props[:group2] || 'A'
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    after '/api/*' do
        if @respond_content
            response.body = @respond_content
            response.headers['Content-Type'] = @respond_mimetype
            if @respond_filename
                response.headers['Content-Disposition'] = "attachment; filename=\"#{@respond_filename}\""
            end
        else
            @respond_hash ||= {}
            response.body = @respond_hash.to_json
        end
    end
    
    def respond(hash = {})
        @respond_hash = hash
    end
    
    def respond_raw_with_mimetype(content, mimetype)
        @respond_content = content
        @respond_mimetype = mimetype
    end
    
    def respond_raw_with_mimetype_and_filename(content, mimetype, filename)
        @respond_content = content
        @respond_mimetype = mimetype
        @respond_filename = filename
    end
    
    def htmlentities(s)
        @html_entities_coder ||= HTMLEntities.new
        @html_entities_coder.encode(s)
    end
    
    post '/api/reset_nc_password' do
        require_user!
        ocs = Nextcloud.ocs(url: NEXTCLOUD_URL, 
                            username: NEXTCLOUD_USER, 
                            password: NEXTCLOUD_PASSWORD)
        ocs.user.update(@session_user[:nc_login], 'password', @session_user[:initial_nc_password])
        respond(:ok => 'yay')
    end
    
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
    
    post '/api/upload_image' do
        require_user_who_can_upload_files!
        slug = params['slug']
        slug.strip!
        assert(slug =~ /^[a-zA-Z0-9\-_]+$/)
        assert(!slug.include?('.'))
        assert(slug.size > 0)
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        path = "/raw/uploads/images/#{slug}.#{filename.split('.').last}"
        File.open(path, 'w') do |f|
            f.write(blob)
        end
        trigger_update_images()
        respond(:uploaded => 'yeah')
    end    
    
    post '/api/delete_image' do
        require_user_who_can_upload_files!
        data = parse_request_data(:required_keys => [:slug])
        slug = data[:slug]
        slug.strip!
        assert(slug =~ /^[a-zA-Z0-9\-_]+$/)
        assert(!slug.include?('.'))
        assert(slug.size > 0)
        Dir["/raw/uploads/images/#{slug}.*"].each do |path|
            STDERR.puts "Deleting #{path}"
            FileUtils::rm_f(path)
            local_slug = File.basename(path).split('.').first
            (GEN_IMAGE_WIDTHS.reverse + [:p]).each do |width|
                Dir["/gen/i/#{local_slug}-#{width}.*"].each do |sub_path|
                    STDERR.puts "Deleting #{sub_path}"
                    FileUtils::rm_f(sub_path)
                end
            end
        end
        respond(:deleted => 'yeah')
    end    
    
    post '/api/get_all_images' do
        require_user_who_can_upload_files!
        images = []
        Dir['/raw/uploads/images/*'].each do |path|
            images << {
                :slug => File.basename(path).split('.').first,
                :size => File.size(path),
                :timestamp => File.mtime(path)
            }
        end
        images.sort! { |a, b| b[:timestamp] <=> a[:timestamp] }
        respond(:images => images)
    end    
    
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
    
    post '/api/parse_markdown' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:markdown],
                                  :max_body_length => 64 * 1024,
                                  :max_string_length => 64 * 1024)
        respond(:html => Kramdown::Document.new(data[:markdown]).to_html)
    end
    
    post '/api/get_news' do
        require_user_who_can_manage_news!
        results = neo4j_query(<<~END_OF_QUERY).map { |x| x['n'].props }
            MATCH (n:News)
            RETURN n
            ORDER BY n.date DESC;
        END_OF_QUERY
        respond(:news => results)
    end
    
    def delete_audio_comment(tag)
        require_teacher!
        if tag && tag.class == String && tag =~ /^[0-9a-zA-Z]+$/
            dir = tag[0, 2]
            filename = tag[2, tag.size - 2]
            path = "/raw/uploads/audio_comment/#{dir}/#{filename}.ogg"
            STDERR.puts "DELETING #{path}"
            FileUtils::rm_f(path)
        end
    end
    
    def trigger_update(which)
        begin
            http = Net::HTTP.new('timetable', 8080)
            response = http.request(Net::HTTP::Get.new("/api/update/#{which}"))
        rescue StandardError => e
            STDERR.puts e
        end
    end
    
    def trigger_update_images()
        begin
            http = Net::HTTP.new('image_bot', 8080)
            response = http.request(Net::HTTP::Get.new("/api/update_all"))
        rescue StandardError => e
            STDERR.puts e
        end
    end
    
    def trigger_send_invites()
        begin
            http = Net::HTTP.new('invitation_bot', 8080)
            response = http.request(Net::HTTP::Get.new("/api/send_invites"))
        rescue StandardError => e
            STDERR.puts e
        end
    end
    
    post '/api/upload_audio_comment' do
        require_teacher!
        lesson_key = params['lesson_key']
        schueler = params['schueler']
        lesson_offset = params['lesson_offset'].to_i
        duration = params['duration'].to_i
        entry = params['file']
        blob = entry['tempfile'].read
        tag = RandomTag.to_base31(('f' + Digest::SHA1.hexdigest(blob)).to_i(16))[0, 16]
        id = RandomTag.generate(12)
        FileUtils.mkpath("/raw/uploads/audio_comment/#{tag[0, 2]}")
        target_path = "/raw/uploads/audio_comment/#{tag[0, 2]}/#{tag[2, tag.size - 2]}.ogg"
        FileUtils::mv(entry['tempfile'].path, target_path)
        FileUtils::chmod('a+r', target_path)
        old_tag = nil
        transaction do 
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :key => lesson_key, :offset => lesson_offset, :schueler => schueler, :audio_comment_tag => tag, :duration => duration, :timestamp => timestamp, :id => id)
                MATCH (u:User {email: {schueler}})
                MERGE (l:Lesson {key: {key}})
                MERGE (u)<-[ruc:TO]-(c:AudioComment {offset: {offset}})-[:BELONGS_TO]->(l)
                WITH ruc, u, c, c.tag as old_tag
                SET c.id = {id}
                SET c.tag = {audio_comment_tag}
                SET c.duration = {duration}
                SET c.updated = {timestamp}
                REMOVE ruc.seen
                WITH c, old_tag
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                WITH c, old_tag
                MATCH (su:User {email: {session_email}})
                MERGE (c)-[:FROM]->(su)
                RETURN old_tag
            END_OF_QUERY
            old_tag = (results.first || {})['old_tag']
        end
        # also delete ogg file on disk
        delete_audio_comment(old_tag)
        trigger_update("#{lesson_key}/wait")
        respond(:tag => tag)
    end
    
    post '/api/delete_audio_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        old_tag = nil
        transaction do 
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :timestamp => timestamp)
                MATCH (:User {email: {schueler}})<-[:TO]-(c:AudioComment {offset: {offset}})-[:BELONGS_TO]->(:Lesson {key: {key}})
                WITH c, c.tag AS old_tag
                SET c = {offset: c.offset, updated: {timestamp}}
                WITH c, old_tag
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                RETURN old_tag
            END_OF_QUERY
            old_tag = results.first['old_tag']
        end
        # also delete ogg file on disk
        delete_audio_comment(old_tag)
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
    
    post '/api/publish_text_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset, :comment],
                                  :max_body_length => 4096,
                                  :max_string_length => 4096,
                                  :types => {:lesson_offset => Integer})
        id = RandomTag.generate(12)
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :text_comment => data[:comment], :timestamp => timestamp, :id => id)
                MATCH (u:User {email: {schueler}})
                MERGE (l:Lesson {key: {key}})
                MERGE (u)<-[ruc:TO]-(c:TextComment {offset: {offset}})-[:BELONGS_TO]->(l)
                SET c.comment = {text_comment}
                SET c.created = {timestamp}
                SET c.updated = {timestamp}
                SET c.id = {id}
                REMOVE ruc.seen
                WITH c
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
                WITH c
                MATCH (su:User {email: {session_email}})
                MERGE (c)-[:FROM]->(su);
            END_OF_QUERY
        end
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
    
    post '/api/delete_text_comment' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :schueler, :lesson_offset],
                                  :types => {:lesson_offset => Integer})
        transaction do 
            timestamp = Time.now.to_i
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :schueler => data[:schueler], :timestamp => timestamp)
                MATCH (u:User {email: {schueler}})<-[:TO]-(c:TextComment {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {key}})
                SET c = {offset: c.offset, updated: {timestamp}}
                WITH c
                OPTIONAL MATCH (c)-[r:FROM]->(:User)
                DELETE r
            END_OF_QUERY
        end
        trigger_update("#{data[:lesson_key]}/wait")
        respond(:ok => true)
    end
    
    post '/api/create_vote' do
        require_teacher!
        data = parse_request_data(:required_keys => [:title, :date, :count],
                                  :types => {:count => Integer})
        possible_codes = (0..9999).to_a
        Dir['/internal/vote/*.json'].each do |path|
            code = File.basename(path).gsub('.json', '').to_i
            possible_codes.delete(code)
        end
        code = possible_codes.sample
        if code.nil?
            respond(:error => 'nope')
            return
        end

        vote_data = {
            :token => RandomTag.generate(24),
            :title => data[:title],
            :date => data[:date],
            :count => data[:count]
        }
        File.open(sprintf('/internal/vote/%04d.json', code), 'w') { |f| f.write(vote_data.to_json) }
        neo4j_query(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (u:User {email: {email}})
            CREATE (v:Vote {code: {code}})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        respond(:ok => true)
    end
    
    post '/api/get_votes' do
        require_teacher!
        codes = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['v.code'] }
            MATCH (v:Vote)-[:BELONGS_TO]->(:User {email: {email}})
            RETURN v.code;
        END_OF_QUERY
        results = codes.map do |code|
            begin
                vote_data = {}
                STDERR.puts "/api/get_votes: #{code}"
                File.open(sprintf("/internal/vote/%04d.json", code)) do |f|
                    vote_data = JSON.parse(f.read)
                end
                vote_data[:code] = code
                vote_data
            rescue 
                STDERR.puts "Unable to read #{sprintf('/internal/vote/%04d.json', code)}"
                nil
            end
        end.reject { |x| x.nil? }
        results = results.sort do |a, b|
            a['date'] <=> b['date']
        end
        respond(:votes => results)
    end
    
    post '/api/delete_vote' do
        require_teacher!
        data = parse_request_data(:required_keys => [:code],
                                  :types => {:code => Integer})
        code = data[:code]
        neo4j_query_expect_one(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (v:Vote {code: {code}})-[:BELONGS_TO]->(u:User {email: {email}})
            DETACH DELETE v
            RETURN u.email;
        END_OF_QUERY
        STDERR.puts "Deleting #{code}..."
        FileUtils::rm_f(sprintf('/internal/vote/%04d.json', code));
        FileUtils::rm_f(sprintf('/internal/vote/%04d.pdf', code));
        respond(:ok => true)
    end
    
    def vote_codes_from_token(vote_code, token, _count)
        count = ((_count + 20) / 4).to_i * 4
        vote_code = sprintf('%04d', vote_code)
        codes = []
        i = 0
        while codes.size < count do
            v = "#{token}#{i}"
            code = Digest::SHA1.hexdigest(v).to_i(16).to_s(10)[0, 8]
            code.insert(1, vote_code[0])
            code.insert(4, vote_code[1])
            code.insert(7, vote_code[2])
            code.insert(10, vote_code[3])
            codes << code unless codes.include?(code)
            i += 1
        end
        codes
    end

    get '/api/get_vote_pdf/*' do
        require_teacher!
        code = request.path.sub('/api/get_vote_pdf/', '').to_i
        neo4j_query_expect_one(<<~END_OF_QUERY, :code => code, :email => @session_user[:email])
            MATCH (v:Vote {code: {code}})-[:BELONGS_TO]->(u:User {email: {email}})
            RETURN v;
        END_OF_QUERY
        vote = nil
        File.open(sprintf('/internal/vote/%04d.json', code)) do |f|
            vote = JSON.parse(f.read)
        end
        codes = vote_codes_from_token(code, vote['token'], vote['count'])
        STDOUT.puts "Rendering PDF with #{codes.size} codes..."
        pdf = nil
        pdf_path = sprintf('/internal/vote/%04d.pdf', code)
        unless File.exists?(pdf_path)
            Prawn::Document::new(:page_size => 'A4', :page_layout => :landscape, :margin => [0, 0, 0, 0]) do
                y = 0
                x = 0
                
                codes.each.with_index do |code, _|
                    bounding_box([x * 14.85.cm + 1.cm, 180.mm - y * 10.5.cm + 10.5.cm], width: 12.85.cm, height: 8.5.cm) do
                        stroke { rectangle [0, 0], 12.85.cm, 8.5.cm }
                        bounding_box([5.mm, -5.mm], width: 11.85.cm) do
                            font_size 10
                            
                            text "<b>Code für Online-Abstimmung #{SCHUL_NAME_AN_DATIV} #{SCHUL_NAME}</b>", inline_format: true
                            move_down 2.mm
                            text "<em>#{vote['title']} (#{vote['date'][8, 2].to_i}.#{vote['date'][5, 2].to_i}.#{vote['date'][0, 4]})</em>", inline_format: true
                            move_down 4.mm
                            if _ == 0
                                text "<b>MODERATOREN-CODE: #{code.split('').each_slice(3).to_a.map { |x| x.join('') }.join(' ')}</b>", inline_format: true
                                move_down 4.mm
                                text "Dieser Code ist <b>nicht</b> mit einem Stimmrecht verknüpft.", inline_format: true
                            else
                                text "Auf diesem Blatt finden Sie einen Code, mit dem Sie an\nOnline-Abstimmungen teilnehmen können. Ihre Stimme\nist anonym, weil Sie den Zettel selbst gewählt haben und\nsomit der Code nicht Ihrer Person zuzuordnen ist."
                                move_down 4.mm
                                text 'Um an der Abstimmung teilzunehmen, öffnen Sie bitte die folgende Webseite:'
                                move_down 4.mm
                                text "<b>#{VOTING_WEBSITE_URL}</b>", inline_format: true
                                move_down 4.mm
                                text "Geben Sie dort den Code <b>#{code.split('').each_slice(3).to_a.map { |x| x.join('') }.join(' ')}</b> ein. Oder scannen Sie den QR-Code, um automatisch angemeldet zu werden.", inline_format: true
                                move_down 4.mm
                                text "Bei Fragen zum Verfahren wenden Sie sich bitte an: #{WEBSITE_MAINTAINER_EMAIL}.", inline_format: true
                            end
                        end
                        bounding_box([98.mm, -2.mm], width: 2.cm) do
                            print_qr_code("#{VOTING_WEBSITE_URL}/?#{code}", :dot => 2, :stroke => false)
                        end
                        
                    end
                    x += 1
                    if x >= 2
                        y += 1
                        if y >= 2
                            y = 0
                            start_new_page if _ < codes.size - 1
                        end
                        x = 0
                    end
                end
                pdf = render()
            end
            File.open(pdf_path, 'w') do |f|
                f.write(pdf)
            end
        end
#         respond_raw_with_mimetype_and_filename(pdf, 'application/pdf', "Codes #{vote['title']} #{vote['date']}.pdf")
        respond_raw_with_mimetype(File.read(pdf_path), 'application/pdf')
    end
    
    post '/api/send_message' do
        require_teacher!
        data = parse_request_data(:required_keys => [:recipients, :message],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:message => 1024 * 1024})
        id = RandomTag.generate(12)
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        FileUtils::mkpath(File.dirname(path))
        Zlib::GzipWriter.open(path) do |f|
            f.print data[:message]
        end
        timestamp = Time.now.to_i
        message = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :recipients => data[:recipients])['m'].props
            MATCH (a:User {email: {session_email}})
            CREATE (m:Message {id: {id}})
            SET m.created = {timestamp}
            SET m.updated = {timestamp}
            CREATE (m)-[:FROM]->(a)
            WITH m
            MATCH (u:User)
            WHERE u.email IN {recipients}
            CREATE (m)-[:TO]->(u)
            RETURN DISTINCT m;
        END_OF_QUERY
        t = Time.at(message[:created])
        message = {
            :date => t.strftime('%Y-%m-%d'),
            :dow => t.wday,
            :mid => message[:id],
            :recipients => data[:recipients]
        }
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :message => message)
    end
    
    post '/api/update_message' do
        require_teacher!
        data = parse_request_data(:required_keys => [:mid, :recipients, :message],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024,
                                  :max_value_lengths => {:message => 1024 * 1024})
        id = data[:mid]
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        FileUtils::mkpath(File.dirname(path))
        Zlib::GzipWriter.open(path) do |f|
            f.print data[:message]
        end
        timestamp = Time.now.to_i
        message = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :recipients => data[:recipients])['m'].props
            MATCH (m:Message {id: {id}})-[:FROM]->(a:User {email: {session_email}})
            SET m.updated = {timestamp}
            WITH DISTINCT m
            MATCH (m)-[r:TO]->(u:User)
            DELETE r
            WITH DISTINCT m
            MATCH (u:User)
            WHERE u.email IN {recipients}
            CREATE (m)-[:TO]->(u)
            RETURN DISTINCT m;
        END_OF_QUERY
        t = Time.at(message[:created])
        message = {
            :date => t.strftime('%Y-%m-%d'),
            :dow => t.wday,
            :mid => message[:id],
            :recipients => data[:recipients]
        }
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :message => message, :mid => data[:mid])
    end
    
    post '/api/delete_message' do
        require_teacher!
        data = parse_request_data(:required_keys => [:mid])
        id = data[:mid]
        path = "/gen/m/#{id[0, 2]}/#{id[2, id.length - 2]}.html.gz"
        # also delete message on file system
        FileUtils::rm_f(path)
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:FROM]-(m:Message {id: {id}})
                SET m.updated = {timestamp}
                SET m.deleted = true
                WITH m
                OPTIONAL MATCH (m)-[rt:TO]->(r:User)
                SET rt.updated = {timestamp}
                SET rt.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        trigger_update("all_messages")
        respond(:ok => true, :mid => data[:mid])
    end
    
    post '/api/mark_as_read' do
        require_user!
        data = parse_request_data(:required_keys => [:ids],
                                  :types => {:ids => Array})
        transaction do 
            results = neo4j_query(<<~END_OF_QUERY, :ids => data[:ids], :email => @session_user[:email])
                MATCH (c)-[ruc:TO]->(:User {email: {email}})
                WHERE (c:TextComment OR c:AudioComment OR c:Message) AND c.id IN {ids}
                SET ruc.seen = true
            END_OF_QUERY
        end
        respond(:new_unread_ids => get_unread_messages(Time.now.to_i - MESSAGE_DELAY))
    end
    
    def get_poll_run(prid, external_code = nil)
#         external_code = nil if user_logged_in?
        result = {}
        if external_code
            rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                MATCH (ou)-[rt2:IS_PARTICIPANT]->(pr2:PollRun {id: {prid}})-[:RUNS]->(p2:Poll)-[:ORGANIZED_BY]->(au2:User)
                WHERE COALESCE(rt2.deleted, false) = false
                RETURN u, pr, p, au.email, COUNT(ou) AS total_participants;
            END_OF_QUERY
            invitation = rows.select do |row|
                row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                external_code == row_code
            end.first
            assert(!(invitation.nil?))
            result = invitation
        else
            require_user!
            result = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
                MATCH (u:User {email: {email}})-[:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WITH pr, p, au
                MATCH (ou)-[rt2:IS_PARTICIPANT]->(pr2:PollRun {id: {prid}})-[:RUNS]->(p2:Poll)-[:ORGANIZED_BY]->(au2:User)
                WHERE COALESCE(rt2.deleted, false) = false
                RETURN pr, p, au.email, COUNT(ou) AS total_participants
            END_OF_QUERY
        end
        poll = result['p'].props
        poll.delete(:items)
        poll_run = result['pr'].props
        poll_run[:items] = JSON.parse(poll_run[:items])
        return poll, poll_run, result['au.email'], result['total_participants']
    end
    
    post '/api/get_poll_run' do
        data = parse_request_data(:required_keys => [:prid], :optional_keys => [:external_code])
        prid = data[:prid]
        external_code = data[:external_code]
        poll, poll_run, organizer_email, total_participants = get_poll_run(prid, external_code)

        stored_response = nil
        if user_logged_in?
            results = neo4j_query(<<~END_OF_QUERY, {:prid => poll_run[:id], :email => @session_user[:email]}).map { |x| x['prs.response'] }
                MATCH (u:User {email: {email}})<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr:PollRun {id: {prid}})
                RETURN prs.response
                LIMIT 1;
            END_OF_QUERY
            unless results.empty?
                stored_response = JSON.parse(results.first)
            end
        else
            rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User)
                WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                WITH u, pr
                MATCH (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                RETURN prs.response, u, pr;
            END_OF_QUERY
            STDERR.puts rows.to_yaml
            results = rows.select do |row|
                row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                external_code == row_code
            end
            unless results.empty?
                stored_response = JSON.parse(results.first['prs.response'])
            end
        end
        stored_response ||= {}
        respond(:poll => poll, :poll_run => poll_run, :stored_response => stored_response,
                :organizer => (@@user_info[organizer_email] || {})[:display_last_name],
                :total_participants => total_participants)
    end
    
    post '/api/stop_poll_run' do
        require_user!
        data = parse_request_data(:required_keys => [:prid])
        now_date = Date.today.strftime('%Y-%m-%d')
        now_time = (Time.now - 60).strftime('%H:%M')
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => data[:prid], :email => @session_user[:email], :now_date => now_date, :now_time => now_time})
            MATCH (pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(u:User {email: {email}})
            SET pr.end_date = {now_date}
            SET pr.end_time = {now_time}
            RETURN pr
        END_OF_QUERY
        poll_run = result['pr'].props
        poll_run[:items] = JSON.parse(poll_run[:items])
        respond(:prid => data[:prid], :end_date => now_date, :end_time => now_time)
    end
    
    post '/api/submit_poll_run' do
        data = parse_request_data(:required_keys => [:prid, :response],
                                  :optional_keys => [:external_code],
                                  :max_body_length => 64 * 1024,
                                  :max_string_length => 64 * 1024)
        prid = data[:prid]
        external_code = data[:external_code]
        poll, poll_run = get_poll_run(prid, external_code)
        now_s = DateTime.now.strftime('%Y-%m-%dT%H:%M:%S')
        good = true
        if now_s < "#{poll_run[:start_date]}T#{poll_run[:start_time]}:00"
            good = false
            respond(:error => 'Diese Umfrage ist noch nicht geöffnet.')
        elsif now_s > "#{poll_run[:end_date]}T#{poll_run[:end_time]}:00"
            good = false
            respond(:error => 'Diese Umfrage ist nicht mehr geöffnet.')
        end
        if good
            if external_code.nil?
                neo4j_query(<<~END_OF_QUERY, {:prid => prid, :response => data[:response], :email => @session_user[:email]})
                    MATCH (u:User {email: {email}})
                    MATCH (pr:PollRun {id: {prid}})
                    MERGE (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    SET prs.response = {response};
                END_OF_QUERY
            else
                rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
                    MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)
                    WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(p.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                    RETURN id(u), pr, u;
                END_OF_QUERY
                results = rows.select do |row|
                    row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                    external_code == row_code
                end
                neo4j_query(<<~END_OF_QUERY, {:prid => prid, :response => data[:response], :node_id => results.first['id(u)']})
                    MATCH (u)
                    WHERE id(u) = {node_id}
                    WITH u
                    MATCH (pr:PollRun {id: {prid}})
                    MERGE (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    SET prs.response = {response};
                END_OF_QUERY
            end
            respond(:submitted => true)
        end
    end
    
    def get_poll_run_results(prid)
        require_teacher!
        temp = neo4j_query_expect_one(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
            MATCH (pu)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE COALESCE(p.deleted, false) = false 
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(rt.deleted, false) = false
            RETURN au.email, pr, p, COUNT(pu) AS participant_count;
        END_OF_QUERY
        participants = neo4j_query(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]})
            MATCH (pu)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE COALESCE(p.deleted, false) = false 
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(rt.deleted, false) = false
            RETURN labels(pu), pu.email, pu.name
        END_OF_QUERY
        participants = Hash[participants.map do |x|
            [x['pu.email'], x['pu.name'] || (@@user_info[x['pu.email']] || {})[:display_name] || 'NN']
        end]
        poll = temp['p'].props
        poll_run = temp['pr'].props
        poll[:organizer] = (@@user_info[temp['au.email']] || {})[:display_last_name]
        poll_run[:items] = JSON.parse(poll_run[:items])
        poll_run[:participant_count] = temp['participant_count']
        poll_run[:participants] = participants
        responses = neo4j_query(<<~END_OF_QUERY, {:prid => prid, :email => @session_user[:email]}).map { |x| {:response => JSON.parse(x['prs.response']), :email => x['u.email']} }
            MATCH (u)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(au:User {email: {email}})
            WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser)
            RETURN u.email, prs.response;
        END_OF_QUERY
        responses.sort! { |a, b| participants[a] <=> participants[b] }
        return poll, poll_run, responses
    end
    
    def poll_run_results_to_html(poll, poll_run, responses, target = :web)
        StringIO.open do |io|
            io.puts "<h3>Umfrage: #{poll[:title]}</h3>"
            io.puts "<p>Diese #{poll_run[:anonymous] ? 'anonyme' : 'personengebundene'} Umfrage wurde von #{poll[:organizer].sub('Herr ', 'Herrn ')} mit #{poll_run[:participant_count]} Teilnehmern am #{Date.parse(poll_run[:start_date]).strftime('%d.%m.%Y')} durchgeführt.</p>"
            io.puts "<div class='alert alert-info'>"
            io.puts "Von #{poll_run[:participant_count]} Teilnehmern haben #{responses.size} die Umfrage beantwortet (#{(responses.size * 100 / poll_run[:participant_count]).to_i}%)."
            unless poll_run[:anonymous]
                missing_responses_from = (Set.new(poll_run[:participants].keys) - Set.new(responses.map { |x| x[:email]})).map { |x| poll_run[:participants][x] }.sort
                io.puts "Es fehlen Antworten von: <em>#{missing_responses_from.join(', ')}</em>."
            end
            io.puts "</div>"
            poll_run[:items].each_with_index do |item, item_index|
                item = item.transform_keys(&:to_sym)
                if item[:type] == 'paragraph'
                    io.puts "<p><strong>#{item[:title]}</strong></p>" unless (item[:title] || '').strip.empty?
                    io.puts "<p>#{item[:text]}</p>" unless (item[:text] || '').strip.empty?
                elsif item[:type] == 'radio' || item[:type] == 'checkbox'
                    io.puts "<p>"
                    io.puts "<strong>#{item[:title]}</strong>"
                    if item[:type] == 'checkbox'
                        io.puts " <em>(Mehrfachnennungen möglich)</em>"
                    end
                    io.puts "</p>"
                    histogram = {}
                    participants_for_answer = {}
                    (0...item[:answers].size).each { |x| histogram[x] = 0 }
                    responses.each do |entry|
                        response = entry[:response]
                        if item[:type] == 'radio'
                            value = response[item_index.to_s]
                            unless value.nil?
                                histogram[value] += 1
                                participants_for_answer[value] ||= []
                                participants_for_answer[value] << entry[:email]
                            end
                        else
                            (response[item_index.to_s] || []).each do |value|
                                histogram[value] += 1
                                participants_for_answer[value] ||= []
                                participants_for_answer[value] << entry[:email]
                            end
                        end
                    end
                    sum = histogram.values.sum
                    sum = 1 if sum == 0
                    io.puts "<table class='table'>"
                    io.puts "<tbody>"
                    (0...item[:answers].size).each do |answer_index| 
                        v = histogram[answer_index]
                        io.puts "<tr class='pb-0'><td>#{item[:answers][answer_index]}</td><td style='text-align: right;'>#{v == 0 ? '&ndash;' : v}</td></tr>"
                        io.puts "<tr class='noborder pdf-space-below'><td colspan='2'>"
                        io.puts "<div class='progress'>"
                        io.puts "<div class='progress-bar progress-bar-striped bg-info' role='progressbar' style='width: #{(v * 100.0 / sum).round}%' aria-valuenow='50' aria-valuemin='0' aria-valuemax='100'><span>#{(v * 100.0 / sum).round}%</span></div>"
                        io.puts "</div>"
                        unless poll_run[:anonymous]
                            if participants_for_answer[answer_index]
                                io.puts "<em>#{(participants_for_answer[answer_index] || []).map { |x| poll_run[:participants][x]}.join(', ')}</em>"
                            else
                                io.puts "<em>&ndash;</em>"
                            end
                        end
                        io.puts "</td></tr>"
                    end
                    io.puts "</tbody>"
                    io.puts "</table>"
                elsif item[:type] == 'textarea'
                    io.puts "<p>"
                    io.puts "<strong>#{item[:title]}</strong>"
                    io.puts "</p>"
                    first_response = true
                    responses.each do |entry|
                        response = entry[:response][item_index.to_s].strip
                        unless response.empty?
                            io.puts "<hr />" unless first_response
                            if poll_run[:anonymous]
                                io.puts "<p>#{response}</p>"
                            else
                                io.puts "<p><em>#{poll_run[:participants][entry[:email]]}</em>: #{response}</p>"
                            end
                            first_response = false
                        end
                    end
                    
                end
            end
            unless poll_run[:anonymous]
                responses.each do |entry|
                    io.puts "<div class='page-break'></div>"
                    io.puts "<h3>Einzelauswertung: #{poll_run[:participants][entry[:email]]}</h3>"
                    poll_run[:items].each_with_index do |item, item_index|
                        item = item.transform_keys(&:to_sym)
                        if item[:type] == 'paragraph'
                            io.puts "<p><strong>#{item[:title]}</strong></p>" unless (item[:title] || '').strip.empty?
                            io.puts "<p>#{item[:text]}</p>" unless (item[:text] || '').strip.empty?
                        elsif item[:type] == 'radio'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts "</p>"
                            answer = entry[:response][item_index.to_s]
                            unless answer.nil?
                                io.puts "<p>#{item[:answers][answer]}</p>"
                            end
                        elsif item[:type] == 'radio' || item[:type] == 'checkbox'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts " <em>(Mehrfachnennungen möglich)</em>"
                            io.puts "</p>"
                            unless entry[:response][item_index.to_s].nil?
                                io.puts "<p>"
                                io.puts entry[:response][item_index.to_s].map { |answer| item[:answers][answer]}.join(', ')
                                io.puts "</p>"
                            end
                        elsif item[:type] == 'textarea'
                            io.puts "<p>"
                            io.puts "<strong>#{item[:title]}</strong>"
                            io.puts "</p>"
                            response = entry[:response][item_index.to_s].strip
                            io.puts "<p>#{response}</p>" unless response.empty?
                        end
                    end
                end
            end
            io.string
        end
    end
    
    post '/api/get_poll_run_results' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid])
        poll, poll_run, responses = get_poll_run_results(data[:prid])
        html = poll_run_results_to_html(poll, poll_run, responses)
        respond(:html => html, :title => poll[:title], :prid => data[:prid])
    end
    
    get '/api/poll_run_results_pdf/*' do
        require_teacher!
        prid = request.path.sub('/api/poll_run_results_pdf/', '')
        poll, poll_run, responses = get_poll_run_results(prid)
        html = poll_run_results_to_html(poll, poll_run, responses, :pdf)
        css = StringIO.open do |io|
            io.puts "<style>"
            io.puts "body { font-size: 12pt; line-height: 120%; }"
            io.puts "table { width: 100%; }"
            io.puts ".progress { width: 100%; background-color: #ccc; }"
            io.puts ".progress-bar { position: relative; background-color: #888; text-align: right; overflow: hidden; }"
            io.puts ".progress-bar span { margin-right: 0.5em; }"
            io.puts ".pdf-space-above td {padding-top: 0.2em; }"
            io.puts ".pdf-space-below td {padding-bottom: 0.2em; }"
            io.puts ".page-break { page-break-after: always; border-top: none; margin-bottom: 0; }"
            io.puts "</style>"
            io.string
        end
        c = Curl.post('http://weasyprint:5001/pdf', {:data => css + html}.to_json)
        pdf = c.body_str
#         respond_raw_with_mimetype_and_filename(pdf, 'application/pdf', "Umfrageergebnisse #{poll[:title]}.pdf")
        respond_raw_with_mimetype(pdf, 'application/pdf')
    end
    
    def sanitize_poll_items(items)
        items.map do |item|
            if item['type'] == 'radio' || item['type'] == 'checkbox'
                item['answers'].reject! { |x| x.strip.empty? }
            end
            item
        end
    end

    post '/api/save_poll' do
        require_teacher!
        data = parse_request_data(:required_keys => [:title, :items],
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = RandomTag.generate(12)
        data[:items] = sanitize_poll_items(JSON.parse(data[:items])).to_json
        timestamp = Time.now.to_i
        poll = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :items => data[:items])['p'].props
            MATCH (a:User {email: {session_email}})
            CREATE (p:Poll {id: {id}, title: {title}, items: {items}})
            SET p.created = {timestamp}
            SET p.updated = {timestamp}
            CREATE (p)-[:ORGANIZED_BY]->(a)
            RETURN p;
        END_OF_QUERY
        poll = {
            :pid => poll[:id], 
            :poll => poll
        }
        respond(:ok => true, :poll => poll, :items => data[:items])
    end

    post '/api/update_poll' do
        require_teacher!
        data = parse_request_data(:required_keys => [:pid, :title, :items],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        id = data[:pid]
        STDERR.puts "Updating poll #{id}"
        data[:items] = sanitize_poll_items(JSON.parse(data[:items])).to_json
        timestamp = Time.now.to_i
        poll = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :title => data[:title], :items => data[:items])['p'].props
            MATCH (p:Poll {id: {id}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            SET p.updated = {timestamp}
            SET p.title = {title}
            SET p.items = {items}
            WITH DISTINCT p
            RETURN p;
        END_OF_QUERY
        poll = {
            :pid => poll[:id], 
            :poll => poll
        }
        # update timetable for affected users
        respond(:ok => true, :poll => poll, :pid => poll[:pid], :items => data[:items])
    end
    
    post '/api/delete_poll' do
        require_teacher!
        data = parse_request_data(:required_keys => [:pid])
        id = data[:pid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll {id: {id}})
                SET p.updated = {timestamp}
                SET p.deleted = true
            END_OF_QUERY
        end
        # update all messages (but wait some time)
        respond(:ok => true, :pid => data[:pid])
    end
    
    post '/api/save_poll_run' do
        require_teacher!
        data = parse_request_data(:required_keys => [:pid, :anonymous,
                                                     :start_date, :start_time,
                                                     :end_date, :end_time, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024)
        id = RandomTag.generate(12)
        timestamp = Time.now.to_i
        assert(['true', 'false'].include?(data[:anonymous]))
        poll_run = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :pid => data[:pid], :anonymous => (data[:anonymous] == 'true'), :start_date => data[:start_date], :start_time => data[:start_time], :end_date => data[:end_date], :end_time => data[:end_time])['pr'].props
            MATCH (p:Poll {id: {pid}})-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            CREATE (pr:PollRun {id: {id}, anonymous: {anonymous}, start_date: {start_date}, start_time: {start_time}, end_date: {end_date}, end_time: {end_time}})
            SET pr.created = {timestamp}
            SET pr.updated = {timestamp}
            SET pr.items = p.items
            CREATE (pr)-[:RUNS]->(p)
            RETURN pr;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:User)
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
        # link external users (predefined)
#         STDERR.puts data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) }.to_yaml
        temp = neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
            CREATE (u)-[:IS_PARTICIPANT]->(pr);
        END_OF_QUERY
#         STDERR.puts temp.to_yaml
        poll_run = {
            :prid => poll_run[:id], 
            :info => poll_run,
            :recipients => data[:recipients],
        }
#         trigger_update("_poll_run_#{poll_run[:prid]}")
        respond(:ok => true, :poll_run => poll_run)
    end
    
    post '/api/update_poll_run' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid, :anonymous, :start_date, :start_time,
                                                     :end_date, :end_time, :recipients],
                                  :types => {:recipients => Array},
                                  :max_body_length => 1024 * 1024)

        id = data[:prid]
        STDERR.puts "Updating poll run #{id}"
        timestamp = Time.now.to_i
        assert(['true', 'false'].include?(data[:anonymous]))
        poll_run = neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id, :anonymous => (data[:anonymous] == 'true'), :start_date => data[:start_date], :start_time => data[:start_time], :end_date => data[:end_date], :end_time => data[:end_time], :recipients => data[:recipients])['pr'].props
            MATCH (pr:PollRun {id: {id}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(a:User {email: {session_email}})
            WHERE pr.anonymous = {anonymous}
            SET pr.updated = {timestamp}
            SET pr.start_date = {start_date}
            SET pr.start_time = {start_time}
            SET pr.end_date = {end_date}
            SET pr.end_time = {end_time}
            WITH DISTINCT pr
            OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(pr)
            SET r.deleted = true
            WITH DISTINCT pr
            RETURN pr;
        END_OF_QUERY
        # link regular users
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@user_info.include?(x)} )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:User)
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users from address book
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].reject {|x| @@user_info.include?(x)}, :session_email => @session_user[:email] )
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:ExternalUser {entered_by: {session_email}})
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        # link external users (predefined)
        neo4j_query(<<~END_OF_QUERY, :prid => id, :recipients => data[:recipients].select {|x| @@predefined_external_users[:recipients].include?(x) })
            MATCH (pr:PollRun {id: {prid}})
            WITH DISTINCT pr
            MATCH (u:PredefinedExternalUser)
            WHERE u.email IN {recipients}
            MERGE (u)-[r:IS_PARTICIPANT]->(pr)
            REMOVE r.deleted
        END_OF_QUERY
        poll_run = {
            :prid => poll_run[:id], 
            :info => poll_run,
            :recipients => data[:recipients],
        }
        # update timetable for affected users
#         trigger_update("_poll_run_#{poll_run[:prid]}")
        respond(:ok => true, :poll_run => poll_run)
    end
    
    post '/api/delete_poll_run' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid])
        id = data[:prid]
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :timestamp => timestamp, :id => id)
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})
                SET pr.updated = {timestamp}
                SET pr.deleted = true
            END_OF_QUERY
        end
        respond(:ok => true, :prid => data[:prid])
    end
    
    post '/api/get_external_invitations_for_poll_run' do
        require_teacher!
        data = parse_request_data(:optional_keys => [:prid])
        id = data[:prid]
        invitations = {}
        invitation_requested = {}
        unless (id || '').empty?
            data = {:session_email => @session_user[:email], :id => id}
            temp = neo4j_query(<<~END_OF_QUERY, data).map { |x| {:email => x['r.email'], :invitations => x['invitations'] || [], :invitation_requested => x['invitation_requested'] } }
                MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})<-[rt:IS_PARTICIPANT]-(r)
                WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND COALESCE(rt.deleted, false) = false
                RETURN r.email, COALESCE(rt.invitations, []) AS invitations, COALESCE(rt.invitation_requested, false) AS invitation_requested;
            END_OF_QUERY
            temp.each do |entry|
                invitations[entry[:email]] = entry[:invitations].map do |x|
                    Time.at(x).strftime('%d.%m.%Y %H:%M:%S')
                end
                invitation_requested[entry[:email]] = entry[:invitation_requested]
            end
        end
        respond(:invitations => invitations, :invitation_requested => invitation_requested)
    end
    
    def self.invite_external_user_for_poll_run(prid, email, session_user_email)
        STDERR.puts "Sending invitation mail for poll run #{prid} to #{email}"
        timestamp = Time.now.to_i
        data = {}
        data[:prid] = prid
        data[:email] = email
        data[:timestamp] = timestamp
        poll_run = nil
        temp = $neo4j.neo4j_query_expect_one(<<~END_OF_QUERY, data)
            MATCH (u:User)<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {prid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(pr.deleted, false) = false AND COALESCE(p.deleted, false) = false
            RETURN pr, p, u.email;
        END_OF_QUERY
        poll_run = temp['pr'].props
        poll = temp['p'].props
        session_user = @@user_info[temp['u.email']][:display_last_name]
        code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + data[:prid] + data[:email]).to_i(16).to_s(36)[0, 8]
        deliver_mail do
            to data[:email]
            bcc SMTP_FROM
            from SMTP_FROM
            reply_to "#{@@user_info[session_user_email][:display_name]} <#{session_user_email}>"
            
            subject "Einladung zur Umfrage: #{poll[:title]}"

            StringIO.open do |io|
                io.puts "<p>Sie haben eine Einladung zu einer Umfrage erhalten.</p>"
                io.puts "<p>"
                io.puts "Eingeladen von: #{session_user}<br />"
                io.puts "Titel: #{poll[:title]}<br />"
                io.puts "Datum und Uhrzeit: #{Time.parse(poll_run[:start_date]).strftime('%d.%m.%Y')}, #{poll_run[:start_time]} &ndash; #{Time.parse(poll_run[:end_date]).strftime('%d.%m.%Y')}, #{poll_run[:end_time]}<br />"
                link = WEB_ROOT + "/p/#{data[:prid]}/#{code}"
                io.puts "</p>"
                io.puts "<p>Link zur Umfrage:<br /><a href='#{link}'>#{link}</a></p>"
                io.puts "<p>Bitte geben Sie den Link nicht weiter. Er ist personalisiert und nur im angegebenen Zeitraum gültig.</p>"
                io.string
            end
        end
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, data)
            MATCH (pr:PollRun {id: {prid}})<-[rt:IS_PARTICIPANT]-(r)
            WHERE (r:ExternalUser OR r:PredefinedExternalUser) AND (r.email = {email}) AND COALESCE(rt.deleted, false) = false AND COALESCE(pr.deleted, false) = false
            SET rt.invitations = COALESCE(rt.invitations, []) + [{timestamp}]
            REMOVE rt.invitation_requested
        END_OF_QUERY
    end
    
    post '/api/invite_external_user_for_poll_run' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid, :email])
        self.class.invite_external_user_for_poll_run(data[:prid], data[:email], @session_user[:email])
        respond({})
    end
    
    post '/api/get_website_events' do
        require_user_who_can_manage_news!
        ts_now = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'].props }
            MATCH (e:WebsiteEvent)
            WHERE e.date < {today}
            DELETE e;
        END_OF_QUERY
        results = neo4j_query(<<~END_OF_QUERY, :today => ts_now).map { |x| x['e'].props }
            MATCH (e:WebsiteEvent)
            RETURN e
            ORDER BY e.date, e.title;
        END_OF_QUERY
        respond(:events => results)
    end
    
    post '/api/delete_website_event' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (e:WebsiteEvent {id: {id}})
            DELETE e;
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/create_website_event' do
        require_user_who_can_manage_news!
        id = RandomTag.generate()
        ts_now = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :id => id, :date => ts_now)
            CREATE (e:WebsiteEvent)
            SET e.id = {id}
            SET e.date = {date}
            SET e.title = '';
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_date' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :date])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :date => data[:date])
            MATCH (e:WebsiteEvent {id: {id}})
            SET e.date = {date};
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    post '/api/change_website_event_title' do
        require_user_who_can_manage_news!
        data = parse_request_data(:required_keys => [:id, :title])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :title => data[:title])
            MATCH (e:WebsiteEvent {id: {id}})
            SET e.title = {title};
        END_OF_QUERY
        respond(:result => 'yay')
    end
    
    get '/e/:eid/:code' do
        eid = params[:eid]
        code = params[:code]
        redirect "#{WEB_ROOT}/jitsi/event/#{eid}/#{code}", 302
    end
    
    get '/p/:prid/:code' do
        prid = params[:prid]
        code = params[:code]
        redirect "#{WEB_ROOT}/poll/#{prid}/#{code}", 302
    end
    
    def external_users_for_session_user
        result = {:groups => [], :recipients => {}, :order => []}
        # add pre-defined external users
        @@predefined_external_users[:groups].each do |x|
            result[:groups] << x
        end
        @@predefined_external_users[:recipients].each_pair do |k, v|
            result[:recipients][k] = v
        end
        
        # add external users from user's address book
        ext_users = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email]).map { |x| x['e'].props }
            MATCH (u:User {email: {session_email}})-[:ENTERED_EXT_USER]->(e:ExternalUser)
            RETURN e
            ORDER BY e.name
        END_OF_QUERY
        ext_users.each do |entry|
            result[:recipients][entry[:email]] = {:label => entry[:name]}
            result[:order] << entry[:email]
        end

        result
    end
    
    post '/api/add_external_users' do
        require_teacher!
        data = parse_request_data(:required_keys => [:text],
                                  :max_body_length => 1024 * 4,
                                  :max_string_length => 1024 * 4,
                                  :max_value_lengths => {:text => 1024 * 4})
        raw_addresses = Mail::AddressList.new(data[:text].gsub("\n", ','))
        raw_addresses.addresses.each do |a|  
            email = (a.address || '').strip
            display_name = (a.display_name || '').strip
            if email.size > 0 && display_name.size > 0
                neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :email => email, :name => display_name)
                    MATCH (u:User {email: {session_email}})
                    MERGE (u)-[:ENTERED_EXT_USER]->(e:ExternalUser {email: {email}, entered_by: {session_email}})
                    SET e.name = {name}
                END_OF_QUERY
            end
        end
        respond(:ext_users => external_users_for_session_user)
    end
    
    post '/api/delete_external_user' do
        require_teacher!
        data = parse_request_data(:required_keys => [:email])
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :email => data[:email])
            MATCH (u:User {email: {session_email}})-[:ENTERED_EXT_USER]->(e:ExternalUser {email: {email}})
            DETACH DELETE e;
        END_OF_QUERY
        respond(:ext_users => external_users_for_session_user)
    end
    
    post '/api/impersonate' do
        require_admin!
        data = parse_request_data(:required_keys => [:email])
        session_id = create_session(data[:email])
        purge_missing_sessions(session_id)
        respond(:ok => 'yeah')
    end
    
    def delete_session_user_ical_link()
        require_user!
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| x['u.ical_token'] }
            MATCH (u:User {email: {email}})
            WHERE EXISTS(u.ical_token)
            RETURN u.ical_token;
        END_OF_QUERY
        result.each do |token|
            path = "/gen/ical/#{token}.ics"
            STDERR.puts path
            if File.exists?(path)
                FileUtils.rm(path)
            end
        end
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: {email}})
            REMOVE u.ical_token;
        END_OF_QUERY
    end
    
    post '/api/regenerate_ical_link' do
        require_user!
        delete_session_user_ical_link()
        token = RandomTag.generate(32)
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :token => token)
            MATCH (u:User {email: {email}})
            SET u.ical_token = {token};
        END_OF_QUERY
        trigger_update("_#{@session_user[:email]}")
        respond(:token => token)
    end
    
    post '/api/delete_ical_link' do
        require_user!
        delete_session_user_ical_link()
        respond(:ok => 'yeah')
    end
    
    def delete_session_user_otp_token()
        require_user!
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
            MATCH (u:User {email: {email}})
            REMOVE u.otp_token;
        END_OF_QUERY
    end
    
    post '/api/regenerate_otp_token' do
        require_user!
        delete_session_user_otp_token()
        token = ROTP::Base32.random()
        result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :token => token)
            MATCH (u:User {email: {email}})
            SET u.otp_token = {token};
        END_OF_QUERY
        @session_user[:otp_token] = token
        respond(:qr_code => session_user_otp_qr_code())
    end
    
    post '/api/delete_otp_token' do
        require_user!
        delete_session_user_otp_token()
        respond(:ok => 'yeah')
    end
    
    def session_user_otp_qr_code()
        require_user!
        otp_token = @session_user[:otp_token]
        return nil if otp_token.nil?
        totp = ROTP::TOTP.new(otp_token, issuer: "Dashboard")
        uri = totp.provisioning_uri(@session_user[:email]) 
        qrcode = RQRCode::QRCode.new(uri, 7)
        svg = qrcode.as_svg(offset: 0, color: '000', shape_rendering: 'crispEdges',
                            module_size: 4, standalone: true)    
        svg.gsub("\n", '')
    end
    
    def logout()
        sid = request.cookies['sid']
        if sid =~ /^[0-9A-Za-z,]+$/
            current_sid = sid.split(',').first
            if current_sid =~ /^[0-9A-Za-z]+$/
                result = neo4j_query(<<~END_OF_QUERY, :sid => current_sid)
                    MATCH (s:Session {sid: {sid}})
                    DETACH DELETE s;
                END_OF_QUERY
            end
        end
        purge_missing_sessions()
    end

    post '/api/logout' do
        logout()
        respond(:ok => 'yeah')
    end
    
    post '/api/switch_current_session' do
        data = parse_request_data(:required_keys => [:sid_index],
                                  :types => {:sid_index => Integer})
        sid = request.cookies['sid']
        if sid =~ /^[0-9A-Za-z,]+$/
            sids = sid.split(',')
            if data[:sid_index] < sids.size
                purge_missing_sessions(sids[data[:sid_index]])
            end
        end
        respond(:ok => 'yeah')
    end
    
    post '/api/login' do
        data = parse_request_data(:required_keys => [:email])
        data[:email] = data[:email].strip.downcase
        unless @@user_info.include?(data[:email]) && @@user_info[data[:email]][:can_log_in]
            sleep 3.0
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]), "Login requested for invalid email: #{data[:email]}", true)
        srand(Digest::SHA2.hexdigest(LOGIN_CODE_SALT).to_i + (Time.now.to_f * 1000000).to_i)
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        STDERR.puts "!!!!! #{data[:email]} => #{random_code} !!!!!"
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        # was causing problems with a user... maybe? huh...
#         neo4j_query(<<~END_OF_QUERY, :email => data[:email])
#             MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: {email}})
#             DETACH DELETE l;
#         END_OF_QUERY
        result = neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :code => random_code, :valid_to => valid_to.to_i)
            MATCH (n:User {email: {email}})
            CREATE (l:LoginCode {tag: {tag}, code: {code}, valid_to: {valid_to}})-[:BELONGS_TO]->(n)
            RETURN n, l;
        END_OF_QUERY
        begin
            deliver_mail do
                to data[:email]
                bcc SMTP_FROM
                from SMTP_FROM
                
                subject "Dein Anmeldecode lautet #{random_code}"

                StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>Dein Anmeldecode lautet:</p>"
                    io.puts "<p style='font-size: 200%;'>#{random_code}</p>"
                    io.puts "<p>Der Code ist für zehn Minuten gültig. Nachdem du eingeloggt bist, bleibst du für ein ganzes Jahr eingeloggt.</p>"
    #                 link = "#{WEB_ROOT}/c/#{tag}/#{random_code}"
    #                 io.puts "<p><a href='#{link}'>#{link}</a></p>"
                    io.puts "<p>Falls du diese E-Mail nicht angefordert hast, hat jemand versucht, sich mit deiner E-Mail-Adresse auf <a href='https://#{WEBSITE_HOST}/'>https://#{WEBSITE_HOST}/</a> anzumelden. In diesem Fall musst du nichts weiter tun (es sei denn, du befürchtest, dass jemand anderes Zugriff auf dein E-Mail-Konto hat – dann solltest du dein E-Mail-Passwort ändern).</p>"
                    io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                    io.string
                end
            end
        rescue StandardError => e
            if DEVELOPMENT
                STDERR.puts "Cannot send e-mail in DEVELOPMENT mode, continuing anyway:"
                STDERR.puts e
            else
                raise e
            end
        end
        respond(:tag => tag)
    end
    
    post '/api/login_otp' do
        data = parse_request_data(:required_keys => [:email])
        data[:email] = data[:email].strip.downcase
        unless @@user_info.include?(data[:email]) && @@user_info[data[:email]][:can_log_in]
            respond(:error => 'no_invitation_found')
        end
        assert(@@user_info.include?(data[:email]))
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: {email}})
            DETACH DELETE l;
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :valid_to => valid_to.to_i)
            MATCH (n:User {email: {email}})
            CREATE (l:LoginCode {tag: {tag}, otp: true, valid_to: {valid_to}})-[:BELONGS_TO]->(n)
            RETURN n;
        END_OF_QUERY
        respond(:tag => tag)
    end
    
    def create_session(email)
        sid = RandomTag::generate(24)
        assert(sid =~ /^[0-9A-Za-z]+$/)
        data = {:sid => sid,
                :expires => (DateTime.now() + 365).to_s}
        begin
            ua = USER_AGENT_PARSER.parse(request.env['HTTP_USER_AGENT'])
            usa = "#{ua.family} #{ua.version.segments.first} (#{ua.os.family}"
            usa += " / #{ua.device.family}" if ua.device.family.downcase != 'other'
            usa += ')'
            data[:user_agent] = usa
        rescue
        end
        
        all_sessions().each do |session|
            other_sid = session[:sid]
            result = neo4j_query(<<~END_OF_QUERY, :email => email, :other_sid => other_sid).map { |x| x['sid'] }
                MATCH (s:Session {sid: {other_sid}})-[:BELONGS_TO]->(u:User {email: {email}})
                DETACH DELETE s;
            END_OF_QUERY
        end
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :data => data)
            MATCH (u:User {email: {email}})
            CREATE (s:Session {data})-[:BELONGS_TO]->(u)
            RETURN s; 
        END_OF_QUERY
        sid
    end
    
    post '/api/confirm_login' do
        data = parse_request_data(:required_keys => [:tag, :code])
        data[:code] = data[:code].gsub(/[^0-9]/, '')
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:LoginCode {tag: {tag}})-[:BELONGS_TO]->(u:User)
            RETURN l, u;
        END_OF_QUERY
        user = result['u'].props
        login_code = result['l'].props
        if login_code[:otp]
            otp_token = user[:otp_token]
            assert(!otp_token.nil?)
            totp = ROTP::TOTP.new(otp_token, issuer: "Dashboard")
            assert_with_delay(totp.verify(data[:code], drift_behind: 15, drift_ahead: 15), "Wrong OTP code entered for #{user[:email]}: #{data[:code]}", true)
        else
            assert_with_delay(data[:code] == login_code[:code], "Wrong e-mail code entered for #{user[:email]}: #{data[:code]}", true)
        end
        if Time.at(login_code[:valid_to]) < Time.now
            respond({:error => 'code_expired'})
        end
        assert(Time.at(login_code[:valid_to]) >= Time.now)
        session_id = create_session(user[:email])
        result = neo4j_query(<<~END_OF_QUERY, :tag => data[:tag], :code => data[:code])
            MATCH (l:LoginCode {tag: {tag}, code: {code}})
            DETACH DELETE l;
        END_OF_QUERY
        purge_missing_sessions(session_id)
        respond(:ok => 'yeah')
    end
    
    post '/api/login_as_teacher_tablet' do
        require_admin!
        logout()
        session_id = create_session("lehrer.tablet@#{SCHUL_MAIL_DOMAIN}")
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yay')
    end
    
    post '/api/login_as_kurs_tablet' do
        require_admin!
        data = parse_request_data(:required_keys => [:shorthands],
                                  :max_body_length => 1024,
                                  :types => {:shorthands => Array})
        logout()
        session_id = create_session("kurs.tablet@#{SCHUL_MAIL_DOMAIN}")
        neo4j_query(<<~END_OF_QUERY, :sid => session_id, :shorthands => data[:shorthands])
            MATCH (s:Session {sid: {sid}})
            SET s.shorthands = {shorthands};
        END_OF_QUERY
        purge_missing_sessions(session_id, true)
        respond(:ok => 'yeah')
    end
    
    def css_for_font(font)
        if font == 'Alegreya'
            {'font-family' => 'AlegreyaSans', 'letter-spacing' => 'unset'}
        elsif font == 'Billy'
            {'font-family' => 'Billy', 'letter-spacing' => 'unset'}
        elsif font == 'Riffic'
            {'font-family' => 'Riffic', 'letter-spacing' => '0.05em'}
        else
            {'font-family' => 'Roboto', 'letter-spacing' => 'unset'}
        end
    end
    
    post '/api/set_font' do
        require_user!
        data = parse_request_data(:required_keys => [:font])
        assert(AVAILABLE_FONTS.include?(data[:font]))
        results = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :font => data[:font])
            MATCH (u:User {email: {email}})
            SET u.font = {font};
        END_OF_QUERY
        respond(:ok => true, :css => css_for_font(data[:font]))
    end
    
    post '/api/set_color_scheme' do
        require_user!
        data = parse_request_data(:required_keys => [:scheme])
        assert('ld'.include?(data[:scheme][0]))
        assert(data[:scheme][1, 18] =~ /^[0-9a-f]{18}[0-6]?$/)
        results = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :scheme => data[:scheme])
            MATCH (u:User {email: {email}})
            SET u.color_scheme = {scheme};
        END_OF_QUERY
        @@renderer.render(["##{data[:scheme][1, 6]}", "##{data[:scheme][7, 6]}", "##{data[:scheme][13, 6]}", '(no title)'], @session_user[:email])
        respond(:ok => true, :primary_color_darker => darken("##{data[:scheme][7, 6]}", 0.8))
    end
    
    post '/api/save_lesson_data' do
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offsets, :data],
                                  :max_body_length => 65536,
                                  :types => {:lesson_offsets => Array, :data => Hash})
        transaction do 
            timestamp = Time.now.to_i
            data[:lesson_offsets].each do |lesson_offset|
                results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => lesson_offset, :data => data[:data], :timestamp => timestamp)
                    MERGE (l:Lesson {key: {key}})
                    MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                    SET i += {data}
                    SET i.updated = {timestamp};
                END_OF_QUERY
            end
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end
    
    post '/api/force_jitsi_for_lesson' do
        require_teacher_tablet!
        data = parse_request_data(:required_keys => [:lesson_key, :lesson_offset],
                                  :max_body_length => 1024,
                                  :types => {:lesson_offset => Integer})
        transaction do 
            timestamp = Time.now.to_i
            neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:lesson_offset], :data => {:lesson_jitsi => true}, :timestamp => timestamp)
                MERGE (l:Lesson {key: {key}})
                MERGE (i:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l)
                SET i += {data}
                SET i.updated = {timestamp};
            END_OF_QUERY
        end
        trigger_update(data[:lesson_key])
        respond(:ok => true)
    end
    
    def get_lesson_data(lesson_key)
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| x['i'].props }
            MATCH (i:LessonInfo)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            RETURN i
            ORDER BY i.offset;
        END_OF_QUERY
        results = {}
        rows.each do |row|
            results[row[:offset]] ||= {}
            results[row[:offset]][:info] = row.reject do |k, v|
                [:offset, :updated].include?(k)
            end
        end
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'].props, :user => x['u'].props, :text_comment_from => x['tcf.email'] } }
            MATCH (u:User)<-[:TO]-(c:TextComment)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            MATCH (c)-[:FROM]->(tcf:User)
            RETURN c, u, tcf.email
            ORDER BY c.offset;
        END_OF_QUERY
        rows.each do |row|
            results[row[:comment][:offset]] ||= {}
            results[row[:comment][:offset]][:comments] ||= {}
            results[row[:comment][:offset]][:comments][row[:user][:email]] ||= {}
            if row[:comment][:comment]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:text_comment] = row[:comment][:comment]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:text_comment_from] = row[:text_comment_from] 
            end
        end
        rows = neo4j_query(<<~END_OF_QUERY, :key => lesson_key).map { |x| {:comment => x['c'].props, :user => x['u'].props, :audio_comment_from => x['acf.email'] } }
            MATCH (u:User)<-[:TO]-(c:AudioComment)-[:BELONGS_TO]->(l:Lesson {key: {key}})
            MATCH (c)-[:FROM]->(acf:User)
            RETURN c, u, acf.email
            ORDER BY c.offset;
        END_OF_QUERY
        rows.each do |row|
            results[row[:comment][:offset]] ||= {}
            results[row[:comment][:offset]][:comments] ||= {}
            results[row[:comment][:offset]][:comments][row[:user][:email]] ||= {}
            if row[:comment][:tag]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:audio_comment_tag] = row[:comment][:tag]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:duration] = row[:comment][:duration]
                results[row[:comment][:offset]][:comments][row[:user][:email]][:audio_comment_from] = row[:audio_comment_from] 
            end
        end
        results
    end
    
    post '/api/get_lesson_data' do
        data = parse_request_data(:required_keys => [:lesson_key])
        results = get_lesson_data(data[:lesson_key])
        respond(:results => results)
    end
    
    post '/api/insert_lesson' do 
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offset, :shift],
                                  :types => {:offset => Integer, :shift => Integer})
        timestamp = Time.now.to_i
        results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => data[:offset], :shift => data[:shift], :timestamp => timestamp)
            MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: {key}}) 
            WHERE n.offset >= {offset}
            SET n.offset = n.offset + {shift}
            SET n.updated = {timestamp};
        END_OF_QUERY
        trigger_update(data[:lesson_key])
        respond(:ok => 'yeah')
    end
    
    post '/api/delete_lessons' do 
        require_teacher!
        data = parse_request_data(:required_keys => [:lesson_key, :offsets],
                                  :types => {:offsets => Array},
                                  :max_body_length => 65536)
        data[:offsets].each do |offset|
            raise 'no a number' unless offset.is_a?(Integer)
        end
        STDERR.puts data.to_yaml
        data[:offsets].sort!
        cumulative_offset = 0
        timestamp = Time.now.to_i
        data[:offsets].each do |offset|
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => offset - cumulative_offset, :timestamp => timestamp)
                MATCH (n:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(:Lesson {key: {key}}) 
                DETACH DELETE n;
            END_OF_QUERY
            results = neo4j_query(<<~END_OF_QUERY, :key => data[:lesson_key], :offset => offset - cumulative_offset, :timestamp => timestamp)
                MATCH (n:LessonInfo)-[:BELONGS_TO]->(:Lesson {key: {key}}) 
                WHERE n.offset > {offset}
                SET n.offset = n.offset - 1
                SET n.updated = {timestamp};
            END_OF_QUERY
            cumulative_offset += 1
        end
        trigger_update(data[:lesson_key])
        respond(:ok => 'yeah')
    end
    
    def user_icon(email, c = nil)
        "<div style='background-image: url(#{NEXTCLOUD_URL}/index.php/avatar/#{@@user_info[email][:nc_login]}/128), url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mO88h8AAq0B1REmZuEAAAAASUVORK5CYII=);;' class='#{c}'></div>"
    end
    
    def nav_items(primary_color, now, new_messages_count)
        if teacher_tablet_logged_in?
            return "<div style='margin-right: 15px;'><b>Lehrer-Tablet-Modus</b></div>" 
        elsif kurs_tablet_logged_in?
            return "<div style='margin-right: 15px;'><b>Kurs-Tablet-Modus</b></div>" 
        end
        StringIO.open do |io|
            new_messages_count_s = nil
            nav_items = []
            if user_logged_in?
                nav_items << ['/', 'Stundenplan', 'fa fa-calendar']
                if teacher_logged_in?
                    nav_items << :kurse
                    nav_items << :directory
                end
                if teacher_logged_in?
                    nav_items << ['/events', 'Termine', 'fa fa-calendar-check-o']
                end
                if user_who_can_upload_files_logged_in? || user_who_can_manage_news_logged_in?
                    nav_items << :website
                end
                nav_items << :messages
                nav_items << :profile
                new_messages_count_s = new_messages_count.to_s
                new_messages_count_s = '99+' if new_messages_count > 99
                if new_messages_count > 0
                    io.puts "<a href='/messages' class='new-messages-indicator-mini'><i class='fa fa-comment' style='color: #{primary_color};'></i><span>#{new_messages_count_s}</span></a>"
                end
            else
                nav_items << ['/hilfe', 'Hilfe', 'fa fa-question-circle']
                nav_items << ['/', 'Anmelden', 'fa fa-sign-in']
            end
            return nil if nav_items.empty?
            io.puts "<button class='navbar-toggler' type='button' data-toggle='collapse' data-target='#navbarTogglerDemo02' aria-controls='navbarTogglerDemo02' aria-expanded='false' aria-label='Toggle navigation'>"
            io.puts "<span class='navbar-toggler-icon'></span>"
            io.puts "</button>"
            io.puts "<div class='collapse navbar-collapse my-0 flex-grow-0' id='navbarTogglerDemo02'>"
            io.puts "<ul class='navbar-nav mr-auto'>"
            nav_items.each do |x|
                if x == :profile
                    io.puts "<li class='nav-item dropdown'>"
                    io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                    display_name = htmlentities(@session_user[:display_name])
                    if @session_user[:klasse]
                        if @session_user[:klasse][0, 2] == '10'
                            display_name += " (#{tr_klasse(@session_user[:klasse])}/#{@session_user[:group2]})"
                        else
                            display_name += " (#{tr_klasse(@session_user[:klasse])})"
                        end
                    end
                    io.puts "<div class='icon'>#{user_icon(@session_user[:email], 'avatar-md')}</div><span class='menu-user-name'>#{display_name}</span>"
#                     
                    io.puts "</a>"
                    io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown'>"
                    io.puts "<a class='dropdown-item nav-icon' href='/profil'><div class='icon'>#{user_icon(@session_user[:email], 'avatar-sm')}</div><span class='label'>Profil</span></a>"
                    sessions = all_sessions()
                    if sessions.size > 1
                        io.puts "<div class='dropdown-divider'></div>"
                        sessions[1, sessions.size - 1].each.with_index do |entry, _|
                            display_name = htmlentities(entry[:user][:display_name])
                            if entry[:user][:klasse]
                                display_name += " (#{tr_klasse(entry[:user][:klasse])})"
                            end
                            io.puts "<a class='dropdown-item nav-icon switch-session' data-sidindex='#{_ + 1}' href='#'><div class='icon'>#{user_icon(entry[:user][:email], 'avatar-sm')}</div><span class='label'>#{display_name}</span></a>"
                        end
                    end
                    io.puts "<a class='dropdown-item nav-icon' href='/login'><div class='icon'><i class='fa fa-sign-in'></i></div><span class='label'>Zusätzliche Anmeldung…</span></a>"
                    io.puts "<a class='dropdown-item nav-icon' href='/login_nc'><div class='icon'><i class='fa fa-nextcloud'></i></div><span class='label'>In Nextcloud anmelden…</span></a>"
                    if @session_user[:teacher]
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/polls'><div class='icon'><i class='fa fa-bar-chart'></i></div><span class='label'>Umfragen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/prepare_vote'><div class='icon'><i class='fa fa-group'></i></div><span class='label'>Abstimmungen</span></a>"
                    end
                    if @session_user[:can_upload_vplan]
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_vplan'><div class='icon'><i class='fa fa-upload'></i></div><span class='label'>Vertretungsplan hochladen</span></a>"
                    end
                    if admin_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/admin'><div class='icon'><i class='fa fa-wrench'></i></div><span class='label'>Administration</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/stats'><div class='icon'><i class='fa fa-bar-chart'></i></div><span class='label'>Statistiken</span></a>"
                    end
                    io.puts "<div class='dropdown-divider'></div>"
                    io.puts "<a class='dropdown-item nav-icon' href='/hilfe'><div class='icon'><i class='fa fa-question-circle'></i></div><span class='label'>Hilfe</span></a>"
                    io.puts "<div class='dropdown-divider'></div>"
                    io.puts "<a class='dropdown-item nav-icon' href='#' onclick='perform_logout();'><div class='icon'><i class='fa fa-sign-out'></i></div><span class='label'>Abmelden</span></a>"
                    io.puts "</div>"
                    io.puts "</li>"
                elsif x == :kurse
                    unless (@@lessons_for_shorthand[@session_user[:shorthand]] || []).empty?
                        io.puts "<li class='nav-item dropdown'>"
                        io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                        io.puts "<div class='icon'><i class='fa fa-address-book'></i></div>Kurse"
                        io.puts "</a>"
                        io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown'>"
                        (@@lessons_for_shorthand[@session_user[:shorthand]] || []).each do |lesson_key|
                            lesson_info = @@lessons[:lesson_keys][lesson_key]
                            fach = lesson_info[:fach]
                            fach = @@faecher[fach] if @@faecher[fach]
                            io.puts "<a class='dropdown-item nav-icon' href='/lessons/#{CGI.escape(lesson_key)}'><div class='icon'><i class='fa fa-address-book'></i></div><span class='label'>#{fach} (#{lesson_info[:klassen].map { |x| tr_klasse(x) }.join(', ')})</span></a>"
                        end
                        io.puts "</div>"
                        io.puts "</li>"
                    end
                elsif x == :directory
                    klassen = @@klassen_for_shorthand[@session_user[:shorthand]] || []
                    unless klassen.empty?
                        io.puts "<li class='nav-item dropdown'>"
                        io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                        io.puts "<div class='icon'><i class='fa fa-address-book'></i></div>Klassen"
                        io.puts "</a>"
                        io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown' style='max-height: 500px; overflow-y: auto;'>"
                        if can_see_all_timetables_logged_in?
                            klassen = @@klassen_order
                        end
                        klassen.each do |klasse|
                            io.puts "<a class='dropdown-item nav-icon' href='/directory/#{klasse}'><div class='icon'><i class='fa fa-address-book'></i></div><span class='label'>Klasse #{tr_klasse(klasse)}</span></a>"
                        end
                        io.puts "</div>"
                        io.puts "</li>"
                    end
                elsif x == :website
                    io.puts "<li class='nav-item dropdown'>"
                    io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                    io.puts "<div class='icon'><i class='fa fa-home'></i></div>Website"
                    io.puts "</a>"
                    io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown' style='max-height: 500px; overflow-y: auto;'>"
                    if user_who_can_manage_news_logged_in?
#                         io.puts "<a class='dropdown-item nav-icon' href='/manage_news'><div class='icon'><i class='fa fa-newspaper-o'></i></div><span class='label'>News verwalten</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/manage_calendar'><div class='icon'><i class='fa fa-calendar'></i></div><span class='label'>Termine verwalten</span></a>"
                    end
                    if user_who_can_manage_news_logged_in? && user_who_can_upload_files_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                    end
                    if user_who_can_upload_files_logged_in?
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_images'><div class='icon'><i class='fa fa-photo'></i></div><span class='label'>Bilder hochladen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_files'><div class='icon'><i class='fa fa-file-pdf-o'></i></div><span class='label'>Dateien hochladen</span></a>"
                    end
                    io.puts "</div>"
                    io.puts "</li>"
                elsif x == :messages
                    io.puts "<li class='nav-item text-nowrap'>"
                    if new_messages_count > 0
                        io.puts "<a class='nav-link nav-icon' href='/messages'><div class='icon'><i class='fa fa-comment'></i></div>Nachrichten<span class='new-messages-indicator' style='background-color: #{primary_color}'><span>#{new_messages_count_s}</span></span></a>"
                    else
                        io.puts "<a class='nav-link nav-icon' href='/messages'><div class='icon'><i class='fa fa-comment'></i></div>Nachrichten</a>"
                    end
                    io.puts "</li>"
                else
                    io.puts "<li class='nav-item text-nowrap'>"
                    io.puts "<a class='nav-link nav-icon' href='#{x[0]}' #{x[3]}><div class='icon'><i class='#{x[2]}'></i></div>#{x[1]}</a>"
                    io.puts "</li>"
                end
            end
            io.puts "</ul>"
            io.puts "</div>"
            io.string
        end
    end
    
    def get_gradients()
        results = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User) 
            WITH COALESCE(u.color_scheme, '#{@@standard_color_scheme}') AS scheme
            RETURN  scheme, count(scheme) AS count ORDER BY count DESC, scheme DESC;
        END_OF_QUERY
        histogram = {}
        results.each do |entry|
            entry['scheme'] ||= @@standard_color_scheme
            histogram[entry['scheme'][1, 18]] ||= 0
            histogram[entry['scheme'][1, 18]] += entry['count']
        end
        histogram_style = {}
        results.each do |entry|
            entry['scheme'] ||= @@standard_color_scheme
            style = (entry['scheme'][19] || '0').to_i
            histogram_style[style] ||= 0
            histogram_style[style] += entry['count']
        end
        color_schemes = @@color_scheme_colors.map do |x|
            paint_colors = x[0, 3].map do |c|
                rgb_to_hex(mix(hex_to_rgb(c), [255, 255, 255], 0.3))
            end
            [x[1], x[0, 3], paint_colors, x[3], x[4], x[5], histogram[x[0, 3].join('').gsub('#', '')]]
        end
        {:color_schemes => color_schemes,
         :style_histogram => histogram_style}
    end
    
    def bytes_to_str(ai_Size)
        if ai_Size < 1024
            return "#{ai_Size} B"
        elsif ai_Size < 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0)} kB"
        elsif ai_Size < 1024 * 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0)} MB"
        elsif ai_Size < 1024 * 1024 * 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0)} GB"
        end
        return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0 / 1024.0)} TB"
    end
    
    def print_email_field(io, email)
        io.puts "<div class='input-group'><input type='text' class='form-control' readonly value='#{email}' /><div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' data-clipboard-text='#{email}'><i class='fa fa-clipboard'></i></button><a href='mailto:#{email}' class='btn btn-primary' /><i class='fa fa-envelope'></i></a></div></div>"
    end
    
    def mail_addresses_table(klasse)
        require_teacher!
        all_homeschooling_users = get_all_homeschooling_users()
        StringIO.open do |io|
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-12'>"
            io.puts "<h3>Klasse #{tr_klasse(klasse)}</h3>"
            io.puts "<table class='klassen_table table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Nr.</th>"
            io.puts "<th style='width: 64px;'></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "<th style='width: 140px;'>Homeschooling</th>"
            io.puts "<th style='width: 100px;'>Gruppe A/B</th>"
            io.puts "<th style='width: 180px;'>Letzter Zugriff</th>"
            io.puts "<th>Eltern-E-Mail-Adresse</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            results = neo4j_query(<<~END_OF_QUERY, :email_addresses => @@schueler_for_klasse[klasse])
                MATCH (u:User)
                WHERE u.email IN {email_addresses}
                RETURN u.email, u.last_access, COALESCE(u.group2, 'A') AS group2;
            END_OF_QUERY
            last_access = {}
            group2_for_email = {}
            results.each do |x|
                last_access[x['u.email']] = x['u.last_access']
                group2_for_email[x['u.email']] = x['group2']
            end
            
            (@@schueler_for_klasse[klasse] || []).sort do |a, b|
                (@@user_info[a][:last_name] == @@user_info[b][:last_name]) ?
                (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
                (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
            end.each.with_index do |email, _|
                record = @@user_info[email]
                io.puts "<tr class='user_row'>"
                io.puts "<td>#{_ + 1}.</td>"
                io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                io.puts "<td>#{record[:last_name]}</td>"
                io.puts "<td>#{record[:first_name]}</td>"
                io.puts "<td>"
                print_email_field(io, record[:email])
                io.puts "</td>"
                homeschooling_button_disabled = (@@klassenleiter[klasse] || []).include?(@session_user[:shorthand]) ? '' : 'disabled'
                if all_homeschooling_users.include?(email)
                    io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-info btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-home'></i>&nbsp;&nbsp;zu Hause</button></td>"
                else
                    io.puts "<td><button #{homeschooling_button_disabled} class='btn btn-secondary btn-xs btn-toggle-homeschooling' data-email='#{email}'><i class='fa fa-building'></i>&nbsp;&nbsp;Präsenz</button></td>"
                end
                io.puts "<td><div class='group2-button group2-#{group2_for_email[email]}' data-email='#{email}'>#{group2_for_email[email]}</div></td>"
                la_label = 'noch nie angemeldet'
                today = Date.today.to_s
                if last_access[email]
                    days = (Date.today - Date.parse(last_access[email])).to_i
                    if days == 0
                        la_label = 'heute'
                    elsif days == 1
                        la_label = 'gestern'
                    elsif days == 2
                        la_label = 'vorgestern'
                    elsif days == 3
                        la_label = 'vor 3 Tagen'
                    elsif days == 4
                        la_label = 'vor 4 Tagen'
                    elsif days == 5
                        la_label = 'vor 5 Tagen'
                    elsif days == 6
                        la_label = 'vor 6 Tagen'
                    elsif days < 14
                        la_label = 'vor 1 Woche'
                    elsif days < 21
                        la_label = 'vor 2 Wochen'
                    elsif days < 28
                        la_label = 'vor 3 Woche'
                    elsif days < 35
                        la_label = 'vor 4 Woche'
                    else
                        la_label = 'vor mehreren Wochen'
                    end
                end
                io.puts "<td>#{la_label}</td>"
                io.puts "<td>"
                print_email_field(io, "eltern.#{record[:email]}")
                io.puts "</td>"
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td><b>E-Mail an die Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "<td></td>"
            io.puts "<td></td>"
            io.puts "<td colspan='2'><b>E-Mail an alle Eltern der Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "</tr>"
            io.puts "<tr class='user_row'>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td>"
            print_email_field(io, "klasse.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "<td></td>"
            io.puts "<td></td>"
            io.puts "<td colspan='2'>"
            print_email_field(io, "eltern.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "</tr>"
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<hr style='margin: 3em 0;'/>"
            io.puts "<h3>Schülerlisten Klasse #{tr_klasse(klasse)}</h3>"
#             io.puts "<div style='text-align: center;'>"
            io.puts "<a href='/api/directory_xlsx/#{klasse}' class='btn btn-primary'><i class='fa fa-file-excel-o'></i>&nbsp;&nbsp;Excel-Tabelle herunterladen</a>"
            io.puts "<a href='/api/directory_timetex_pdf/#{klasse}' class='btn btn-primary'><i class='fa fa-file-pdf-o'></i>&nbsp;&nbsp;Timetex-PDF herunterladen</a>"
#             io.puts "</div>"
            io.puts "<hr style='margin: 3em 0;'/>"
            io.puts "<h3>Lehrer der Klasse #{tr_klasse(klasse)}</h3>"
            io.puts "<table class='table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Kürzel</th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Fächer (Wochenstunden)</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            old_is_klassenleiter = true
            @@teachers_for_klasse[klasse].keys.sort do |a, b|
                name_comp = begin
                    @@user_info[@@shorthands[a]][:last_name] <=> @@user_info[@@shorthands[b]][:last_name]
                rescue
                    a <=> b
                end

                a_kli = (@@klassenleiter[klasse] || []).index(a)
                b_kli = (@@klassenleiter[klasse] || []).index(b)
                
                if a_kli.nil?
                    if b_kli.nil?
                        name_comp
                    else
                        1
                    end
                else
                    if b_kli.nil?
                        -1
                    else
                        a_kli <=> b_kli
                    end
                end
            end.each do |shorthand|
                lehrer = @@user_info[@@shorthands[shorthand]] || {}
                is_klassenleiter = (@@klassenleiter[klasse] || []).include?(shorthand)
                
                if old_is_klassenleiter && !is_klassenleiter
                    io.puts "<tr class='sep user_row'>"
                else
                    io.puts "<tr class='user_row'>"
                end
                old_is_klassenleiter = is_klassenleiter
                io.puts "<td>#{shorthand}#{is_klassenleiter ? ' (KL)' : ''}</td>"
#                 io.puts "<td>#{((lehrer[:titel] || '') + ' ' + (lehrer[:last_name] || shorthand)).strip}</td>"
                io.puts "<td>#{lehrer[:display_name] || ''}</td>"
                hours = @@teachers_for_klasse[klasse][shorthand].keys.sort do |a, b|
                    @@teachers_for_klasse[klasse][shorthand][b] <=> @@teachers_for_klasse[klasse][shorthand][a]
                end.map do |x|
                    fach = x.gsub('.', '')
                    fach = @@faecher[fach] if @@faecher[fach]
                    "#{fach} (#{@@teachers_for_klasse[klasse][shorthand][x]})"
                end.join(', ')
                io.puts "<td>#{hours}</td>"
                if lehrer.empty?
                    io.puts "<td></td>"
                else
                    io.puts "<td>"
                    print_email_field(io, lehrer[:email])
                    io.puts "</td>"
                end
                io.puts "</tr>"
            end
            io.puts "<tr>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td><b>E-Mail an alle Lehrer/innen der Klasse #{tr_klasse(klasse)}</b></td>"
            io.puts "</tr>"
            io.puts "<tr class='user_row'>"
            io.puts "<td colspan='3'></td>"
            io.puts "<td>"
            print_email_field(io, "lehrer.#{klasse}@#{SCHUL_MAIL_DOMAIN}")
            io.puts "</td>"
            io.puts "</tr>"
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
    end
    
    def get_all_homeschooling_users
        temp = neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User {homeschooling: true})
            RETURN u.email
        END_OF_QUERY
        all_homeschooling_users = Set.new()
        temp.each do |user|
            all_homeschooling_users << user['u.email']
        end
        all_homeschooling_users
    end
    
    def get_homeschooling_for_user(email)
        neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})['homeschooling']
            MATCH (u:User {email: {email}})
            RETURN COALESCE(u.homeschooling, false) AS homeschooling
        END_OF_QUERY
    end
    
    def print_admin_dashboard()
        require_admin!
        temp = neo4j_query(<<~END_OF_QUERY).map { |x| {:session => x['s'].props, :email => x['u.email'] } }
            MATCH (s:Session)-[:BELONGS_TO]->(u:User)
            RETURN s, u.email
        END_OF_QUERY
        all_sessions = {}
        temp.each do |s|
            all_sessions[s[:email]] ||= []
            all_sessions[s[:email]] << s[:session]
        end
        all_homeschooling_users = get_all_homeschooling_users()
        StringIO.open do |io|
            io.puts "<a class='btn btn-secondary' href='#teachers'>Lehrerinnen und Lehrer</a>"
            io.puts "<a class='btn btn-secondary' href='#sus'>Schülerinnen und Schüler</a>"
            io.puts "<a class='btn btn-secondary' href='#tablets'>Tablets</a>"
            io.puts "<hr />"
            io.puts "<h3 id='teachers'>Lehrerinnen und Lehrer</h3>"
            io.puts "<table class='table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th></th>"
            io.puts "<th>Kürzel</th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "<th>Stundenplan</th>"
            io.puts "<th>Anmelden</th>"
            io.puts "<th>Sessions</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            @@lehrer_order.each do |email|
                io.puts "<tr>"
                user = @@user_info[email]
                io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                io.puts "<td>#{user[:shorthand]}</td>"
                io.puts "<td>#{user[:last_name]}</td>"
                io.puts "<td>#{user[:first_name]}</td>"
                if USE_MOCK_NAMES
                    io.puts "<td>#{user[:first_name].downcase}.#{user[:last_name].downcase}@#{SCHUL_MAIL_DOMAIN}</td>"
                else
                    io.puts "<td>#{user[:email]}</td>"
                end
                io.puts "<td><a class='btn btn-xs btn-secondary' href='/timetable/#{user[:id]}'><i class='fa fa-calendar'></i>&nbsp;&nbsp;Stundenplan</a></td>"
                io.puts "<td><button class='btn btn-warning btn-xs btn-impersonate' data-impersonate-email='#{user[:email]}'><i class='fa fa-id-badge'></i>&nbsp;&nbsp;Anmelden</button></td>"
                if all_sessions.include?(email)
                    io.puts "<td><button class='btn-sessions btn btn-xs btn-secondary' data-sessions-id='#{@@user_info[email][:id]}'>#{all_sessions[email].size} Session#{all_sessions[email].size == 1 ? '' : 's'}</button></td>"
                else
                    io.puts "<td></td>"
                end
                io.puts "</tr>"
                (all_sessions[email] || []).each do |s|
                    scrambled_sid = Digest::SHA2.hexdigest(SESSION_SCRAMBLER + s[:sid]).to_i(16).to_s(36)[0, 16]
                    io.puts "<tr class='session-row sessions-#{@@user_info[email][:id]}' style='display: none;'>"
                    io.puts "<td colspan='4'></td>"
                    io.puts "<td colspan='2'>"
                    io.puts "#{s[:user_agent] || '(unbekanntes Gerät)'}"
                    io.puts "</td>"
                    io.puts "<td>"
                    io.puts "<button class='btn btn-xs btn-danger btn-purge-session' data-email='#{email}' data-scrambled-sid='#{scrambled_sid}'>Abmelden</button>"
                    io.puts "</td>"
                    io.puts "</tr>"
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<h3 id='sus'>Schülerinnen und Schüler</h3>"
            io.puts "<table class='table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th></th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Vorname</th>"
            io.puts "<th>E-Mail-Adresse</th>"
            io.puts "<th>Stundenplan</th>"
            io.puts "<th>Anmelden</th>"
            io.puts "<th>Homeschooling</th>"
            io.puts "<th>Sessions</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            @@klassen_order.each do |klasse|
                io.puts "<tr>"
                io.puts "<th colspan='8'>Klasse #{klasse}</th>"
                io.puts "</tr>"
                (@@schueler_for_klasse[klasse] || []).each do |email|
                    io.puts "<tr>"
                    user = @@user_info[email]
                    io.puts "<td>#{user_icon(email, 'avatar-md')}</td>"
                    io.puts "<td>#{user[:last_name]}</td>"
                    io.puts "<td>#{user[:first_name]}</td>"
                    io.puts "<td>#{user[:email]}</td>"
                    io.puts "<td><a class='btn btn-xs btn-secondary' href='/timetable/#{user[:id]}'><i class='fa fa-calendar'></i>&nbsp;&nbsp;Stundenplan</a></td>"
                    io.puts "<td><button class='btn btn-warning btn-xs btn-impersonate' data-impersonate-email='#{user[:email]}'><i class='fa fa-id-badge'></i>&nbsp;&nbsp;Anmelden</button></td>"
                    if all_homeschooling_users.include?(email)
                        io.puts "<td><button class='btn btn-info btn-xs btn-toggle-homeschooling' data-email='#{user[:email]}'><i class='fa fa-home'></i>&nbsp;&nbsp;zu Hause</button></td>"
                    else
                        io.puts "<td><button class='btn btn-secondary btn-xs btn-toggle-homeschooling' data-email='#{user[:email]}'><i class='fa fa-building'></i>&nbsp;&nbsp;Präsenz</button></td>"
                    end
                    if all_sessions.include?(email)
                        io.puts "<td><button class='btn-sessions btn btn-xs btn-secondary' data-sessions-id='#{@@user_info[email][:id]}'>#{all_sessions[email].size} Session#{all_sessions[email].size == 1 ? '' : 's'}</button></td>"
                    else
                        io.puts "<td></td>"
                    end
                    io.puts "</tr>"
                    (all_sessions[email] || []).each do |s|
                        scrambled_sid = Digest::SHA2.hexdigest(SESSION_SCRAMBLER + s[:sid]).to_i(16).to_s(36)[0, 16]
                        io.puts "<tr class='session-row sessions-#{@@user_info[email][:id]}' style='display: none;'>"
                        io.puts "<td colspan='3'></td>"
                        io.puts "<td colspan='2'>"
                        io.puts "#{s[:user_agent] || '(unbekanntes Gerät)'}"
                        io.puts "</td>"
                        io.puts "<td>"
                        io.puts "<button class='btn btn-xs btn-danger btn-purge-session' data-email='#{email}' data-scrambled-sid='#{scrambled_sid}'>Abmelden</button>"
                        io.puts "</td>"
                        io.puts "</tr>"
                    end
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<h3 id='tablets'>Tablets</h3>"
            io.puts "<hr />"
            io.puts "<button class='btn btn-success bu_login_teacher_tablet'><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Lehrer-Tablet-Modus aktivieren</button>"
            io.puts "<hr />"
            @@shorthands.keys.sort.each do |shorthand|
                io.puts "<button class='btn-teacher-for-kurs-tablet-login btn btn-xs btn-outline-secondary' data-shorthand='#{shorthand}'>#{shorthand}</button>"
            end
            io.puts "<br /><br >"
            io.puts "<button class='btn btn-success bu_login_kurs_tablet' disabled><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Kurs-Tablet-Modus aktivieren</button>"
            io.puts "<hr />"
            io.puts "<table class='table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Typ</th>"
            io.puts "<th>Gerät</th>"
            io.puts "<th>Abmelden</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            get_sessions_for_user("lehrer.tablet@#{SCHUL_MAIL_DOMAIN}").each do |session|
                io.puts "<tr>"
                io.puts "<td>Lehrer-Tablet</td>"
                io.puts "<td>#{session[:user_agent]}</td>"
                io.puts "<td><button class='btn btn-xs btn-danger btn-purge-session' data-email='lehrer.tablet@#{SCHUL_MAIL_DOMAIN}' data-scrambled-sid='#{session[:scrambled_sid]}'>Abmelden</button></td>"
                io.puts "</tr>"
            end
            get_sessions_for_user("kurs.tablet@#{SCHUL_MAIL_DOMAIN}").each do |session|
                io.puts "<tr>"
                io.puts "<td>Kurs-Tablet (#{(session[:shorthands] || []).sort.join(', ')})</td>"
                io.puts "<td>#{session[:user_agent]}</td>"
                io.puts "<td><button class='btn btn-xs btn-danger btn-purge-session' data-email='kurs.tablet@#{SCHUL_MAIL_DOMAIN}' data-scrambled-sid='#{session[:scrambled_sid]}'>Abmelden</button></td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<hr />"
            
            io.puts "<table class='table table-condensed table-striped narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Lesson Key</th>"
            io.puts "<th>Fach</th>"
            io.puts "<th>Lehrer</th>"
            io.puts "<th>Klassen</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            @@lessons[:lesson_keys].keys.sort do |a, b|
                a.downcase <=> b.downcase
            end.each do |lesson_key|
                io.puts "<tr>"
                io.puts "<td>#{lesson_key}</td>"
                io.puts "<td>#{@@faecher[@@lessons[:lesson_keys][lesson_key][:fach]]}</td>"
                io.puts "<td>#{@@lessons[:lesson_keys][lesson_key][:lehrer].join(', ')}</td>"
                io.puts "<td>#{@@lessons[:lesson_keys][lesson_key][:klassen].join(', ')}</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    def current_jitsi_rooms()
        @@current_jitsi_rooms ||= nil
        @@current_jitsi_rooms_timestamp ||= Time.now
        if @@current_jitsi_rooms.nil? || Time.now > @@current_jitsi_rooms_timestamp + 10
            begin
                @@current_jitsi_rooms = JSON.parse(File.read("/internal/jitsi/room.json"))
                @@current_jitsi_rooms_timestamp = Time.now
            rescue
                @@current_jitsi_rooms = nil
            end
        end
        return @@current_jitsi_rooms
    end
    
    def print_lehrerzimmer_panel()
        require_user!
        return '' unless teacher_logged_in?
        return '' if teacher_tablet_logged_in?
        StringIO.open do |io|
            io.puts "<div class='hint lehrerzimmer-panel'>"
            io.puts "<div style='padding-top: 7px;'>Momentan im Jitsi-Lehrerzimmer:&nbsp;"
#             <span class='btn btn-xs ttc'>Sp</span>
            rooms = current_jitsi_rooms()
            nobody_here = true
            if rooms
                rooms.each do |room|
                    if room['roomName'] == 'lehrerzimmer'
                        room['participants'].sort do |a, b|
                            a['displayName'].downcase.sub('herr', '').sub('frau', '').sub('dr.', '').strip <=> b['displayName'].downcase.sub('herr', '').sub('frau', '').sub('dr.', '').strip
                        end.each do |participant|
                            email = participant['email']
                            if @@user_info[email] && @@user_info[email][:teacher]
                                io.puts "<span class='btn btn-xs ttc'>#{@@user_info[email][:shorthand]}</span>"
                                nobody_here = false
                            end
                        end
                    end
                end
            end
            if nobody_here
                io.puts "<em>niemand</em>"
            end
            io.puts "</div>"
            io.puts "<hr />"
            io.puts "<a href='/jitsi/Lehrerzimmer' target='_blank' style='white-space: nowrap;' class='float-right btn btn-success'><i class='fa fa-microphone'></i>&nbsp;&nbsp;Lehrerzimmer&nbsp;<i class='fa fa-angle-double-right'></i></a>"
            io.puts "<div style='clear: both;'></div>"
            io.puts "</div>"
            io.string
        end
    end
    
    def print_current_polls()
        require_user!
        today = Date.today.strftime('%Y-%m-%d')
        now = Time.now.strftime('%Y-%m-%dT%H:%M:%S')
        email = @session_user[:email]
        entries = neo4j_query(<<~END_OF_QUERY, :email => email, :today => today).map { |x| {:poll_run => x['pr'].props, :poll_title => x['p.title'], :organizer => x['a.email'] } }
            MATCH (u:User {email: {email}})-[rt:IS_PARTICIPANT]->(pr:PollRun)-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(a:User)
            WHERE COALESCE(rt.deleted, false) = false
            AND COALESCE(pr.deleted, false) = false
            AND COALESCE(p.deleted, false) = false
            AND {today} >= pr.start_date
            AND   {today} <= pr.end_date
            RETURN pr, p.title, a.email
            ORDER BY pr.end_date, pr.end_time;
        END_OF_QUERY
        entries.select! do |entry|
            pr = entry[:poll_run]
            now >= "#{pr[:start_date]}T#{pr[:start_time]}:00" && now <= "#{pr[:end_date]}T#{pr[:end_time]}:00"
        end
        return '' if entries.empty?
        StringIO.open do |io|
            entries.each.with_index do |entry, _|
                io.puts "<div class='hint'>"
                poll_title = entry[:poll_title]
                poll_run = entry[:poll_run]
                organizer = entry[:organizer]
                io.puts "<div style='float: left; width: 36px; height: 36px; margin-right: 15px; position: relative; top: 5px; left: 4px;'>"
                io.puts user_icon(organizer, 'avatar-fill')
                io.puts "</div>"
                io.puts "<div>#{@@user_info[organizer][:display_last_name]} hat #{teacher_logged_in? ? 'Sie' : 'dich'} zu einer Umfrage eingeladen: <strong>#{poll_title}</strong>. #{teacher_logged_in? ? 'Sie können' : 'Du kannst'} bis zum #{Date.parse(poll_run[:end_date]).strftime('%d.%m.%Y')} um #{poll_run[:end_time]} Uhr teilnehmen (die Umfrage <span class='moment-countdown' data-target-timestamp='#{poll_run[:end_date]}T#{poll_run[:end_time]}:00' data-before-label='läuft noch' data-after-label='ist vorbei'></span>).</div>"
                io.puts "<hr />"
                io.puts "<button style='white-space: nowrap;' class='float-right btn btn-success bu-launch-poll' data-poll-run-id='#{poll_run[:id]}'>Zur Umfrage&nbsp;<i class='fa fa-angle-double-right'></i></button>"
                io.puts "<div style='clear: both;'></div>"
                io.puts "</div>"
            end
            io.string
        end
    end
    
    def html_to_rgb(x)
        [x[1, 2].to_i(16), x[3, 2].to_i(16), x[5, 2].to_i(16)]
    end
    
    def rgb_to_html(x)
        sprintf('#%02x%02x%02x', x[0], x[1], x[2])
    end
    
    def get_gradient(colors, t)
        i = (t * (colors.size - 1)).to_i
        i = colors.size - 2 if i == colors.size - 1
        f = (t * (colors.size - 1)) - i
        f1 = 1.0 - f
        a = html_to_rgb(colors[i])
        b = html_to_rgb(colors[i + 1])
        rgb_to_html([a[0] * f1 + b[0] * f, a[1] * f1 + b[1] * f, a[2] * f1 + b[2] * f])
    end
    
    def print_stats()
        require_admin!
        login_stats = get_login_stats()
        StringIO.open do |io|
            io.puts "<table class='table table-narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Gruppe</th>"
            io.puts "<th>jemals</th>"
            io.puts "<th>letzte 4 Wochen</th>"
            io.puts "<th>letzte Woche</th>"
            io.puts "<th>heute</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            ([:sus, :lehrer] + @@klassen_order).each do |key|
                label = nil
                if key == :sus
                    label = 'Schülerinnen und Schüler'
                elsif key == :lehrer
                    label = 'Lehrerinnen und Lehrer'
                else
                    label = "Klasse #{tr_klasse(key)}" 
                end
                io.puts "<tr>"
                io.puts "<td>#{label}</td>"
                LOGIN_STATS_D.reverse.each do |d|
                    io.puts "<td>"
                    data = login_stats[key]
                    percent = ((data[:count][d] || 0) * 100 / data[:total]).to_i
                    bgcol = get_gradient(['#cc0000', '#f4951b', '#ffe617', '#80bc42'], percent / 100.0)
                    io.puts "<span style='background-color: #{bgcol}; padding: 4px 8px; margin: 0; border-radius: 3px;'>#{percent}%</span>"
                    io.puts "</td>"
                end
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    def get_sessions_for_user(email)
        require_user!
        sessions = neo4j_query(<<~END_OF_QUERY, :email => email).map { |x| x['s'].props }
            MATCH (s:Session)-[:BELONGS_TO]->(u:User {email: {email}})
            RETURN s
            ORDER BY s.expires;
        END_OF_QUERY
        sessions.map do |s|
            s[:scrambled_sid] = Digest::SHA2.hexdigest(SESSION_SCRAMBLER + s[:sid]).to_i(16).to_s(36)[0, 16]
            s
        end
    end
    
    def get_current_user_sessions()
        require_user!
        get_sessions_for_user(@session_user[:email])
    end
    
    def print_sessions()
        require_user!
        StringIO.open do |io|
            io.puts "<table class='table table-condensed table-striped table-narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Gültig bis</th>"
            io.puts "<th>Gerät</th>"
            io.puts "<th>Abmelden</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            sessions = get_current_user_sessions()
            
            sessions.each do |s|
                io.puts "<tr>"
                d = Time.parse(s[:expires]).strftime('%d.%m.%Y');
                io.puts "<td>#{d}</td>"
                io.puts "<td style='text-overflow: ellipsis;'>#{s[:user_agent] || 'unbekanntes Gerät'}</td>"
                io.puts "<td><button class='btn btn-danger btn-xs btn-purge-session' data-purge-session='#{s[:scrambled_sid]}'><i class='fa fa-sign-out'></i>&nbsp;&nbsp;Gerät abmelden</button></td>"
                io.puts "</tr>"
            end
            if sessions.size > 1
                io.puts "<tr>"
                io.puts "<td></td>"
                io.puts "<td></td>"
                io.puts "<td><button class='btn btn-danger btn-xs btn-purge-session' data-purge-session='_all'><i class='fa fa-sign-out'></i>&nbsp;&nbsp;Alle Geräte abmelden</button></td>"            
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    post '/api/purge_session' do
        require_user!
        data = parse_request_data(:required_keys => [:scrambled_sid])
        if data[:scrambled_sid] == '_all'
            neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                MATCH (s:Session)-[:BELONGS_TO]->(:User {email: {email}})
                DETACH DELETE s;
            END_OF_QUERY
        else
            sessions = get_current_user_sessions().select { |x| x[:scrambled_sid] == data[:scrambled_sid] }
            sessions.each do |s|
                neo4j_query(<<~END_OF_QUERY, :sid => s[:sid])
                    MATCH (s:Session {sid: {sid}})
                    DETACH DELETE s;
                END_OF_QUERY
            end
        end
        respond(:ok => true)
    end
    
    post '/api/purge_session_for_user' do
        require_admin!
        data = parse_request_data(:required_keys => [:scrambled_sid, :email])
        sessions = get_sessions_for_user(data[:email]).select { |x| x[:scrambled_sid] == data[:scrambled_sid] }
        sessions.each do |s|
            neo4j_query(<<~END_OF_QUERY, :sid => s[:sid])
                MATCH (s:Session {sid: {sid}})
                DETACH DELETE s;
            END_OF_QUERY
        end
        respond(:ok => true)
    end
    
    post '/api/toggle_homeschooling' do
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        unless admin_logged_in?
            klasse = @@user_info[email][:klasse]
            assert(@@klassenleiter[klasse].include?(@session_user[:shorthand]))
        end
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])
            MATCH (u:User {email: {email}})
            SET u.homeschooling = NOT COALESCE(u.homeschooling, FALSE)
            RETURN u.homeschooling;
        END_OF_QUERY
        respond(:ok => true, :homeschooling => result['u.homeschooling'])
    end
    
    def print_timetable_chooser()
        if can_see_all_timetables_logged_in?
            StringIO.open do |io|
                io.puts "<div style='margin-bottom: 15px;'>"
                unless teacher_tablet_logged_in?
                    @@klassen_order.each do |klasse|
                        id = @@klassen_id[klasse]
                        io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
                    end
                    io.puts '<hr />'
                end
                @@lehrer_order.each do |email|
                    id = @@user_info[email][:id]
                    next unless @@user_info[email][:can_log_in]
                    io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{@@user_info[email][:shorthand]}</a>"
                end
                io.puts "</div>"
                io.string
            end
        elsif kurs_tablet_logged_in?
            StringIO.open do |io|
                io.puts "<div style='margin-bottom: 15px;'>"
                @@lehrer_order.each do |email|
                    next unless @session_user[:shorthands].include?(@@user_info[email][:shorthand])
                    id = @@user_info[email][:id]
                    next unless @@user_info[email][:can_log_in]
                    io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{@@user_info[email][:shorthand]}</a>"
                end
                io.puts "</div>"
                io.string
            end
        elsif teacher_logged_in?
            StringIO.open do |io|
                io.puts "<div style='margin-bottom: 15px;'>"
                @@klassen_order.each do |klasse|
                    next unless (@@klassen_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(klasse)
                    id = @@klassen_id[klasse]
                    io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
                end
                id = @session_user[:id]
                io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable' + window.location.hash;\" class='btn btn-sm ttc'>#{@session_user[:shorthand]}</a>"
                io.puts "</div>"
                io.string
            end
        end
    end
    
    def may_edit_lessons?(lesson_key)
        teacher_logged_in? && @@lessons_for_shorthand[@session_user[:shorthand]].include?(lesson_key)
    end

    get '/nc_auth' do
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        if @auth.provided? && @auth.basic? && @auth.credentials 
            begin
                password = @auth.credentials[1]
                assert(!(NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL.nil?))
                assert(password == NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL, "Caught failed NextCloud login with user [#{@auth.credentials[0]}] and password [#{password}]!")
                status 200
            rescue StandardError => e
                STDERR.puts e
                throw(:halt, [401, "Not authorized\n"])
            end
        else
            response['WWW-Authenticate'] = %(Basic realm="Restricted Area")
            throw(:halt, [401, "Not authorized\n"])
        end
    end
    
    def get_unread_messages(now)
        require_user!
        # don't show messages which are not at least 5 minutes old
        rows = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :now => now).map { |x| x['c.id'] }
            MATCH (c)-[ruc:TO]->(u:User {email: {email}}) 
            WHERE ((c:TextComment AND EXISTS(c.comment)) OR 
                    (c:AudioComment AND EXISTS(c.tag)) OR
                    (c:Message AND EXISTS(c.id))) AND
                    c.updated < {now} AND COALESCE(ruc.seen, false) = false
            RETURN c.id
        END_OF_QUERY
        rows
    end
    
    def iterate_directory(which, &block)
        (@@schueler_for_klasse[which] || []).sort do |a, b|
            (@@user_info[a][:last_name] == @@user_info[b][:last_name]) ?
            (@@user_info[a][:first_name] <=> @@user_info[b][:first_name]) :
            (@@user_info[a][:last_name] <=> @@user_info[b][:last_name])
        end.each.with_index do |email, i|
            yield email, i
        end
    end
    
    get '/api/directory_timetex_pdf/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_timetex_pdf/', '')
        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, 
                                :margin => 0) do
            font('/app/fonts/RobotoCondensed-Regular.ttf') do
                font_size 12
                main.iterate_directory(klasse) do |email, i|
                    user = @@user_info[email]
                    y = 297.mm - 20.mm - 20.7.pt * i
                    draw_text "#{user[:last_name]}, #{user[:first_name]}", :at => [30.mm, y + 6.pt]
                    line_width 0.2.mm
                    stroke { line [30.mm, y + 20.7.pt], [77.mm, y + 20.7.pt] } if i == 0
                    stroke { line [30.mm, y], [77.mm, y] }
                end
            end
        end
        respond_raw_with_mimetype_and_filename(doc.render, 'application/pdf', "Klasse #{klasse}.pdf")
    end

    get '/api/print_offline_users' do
        require_admin!
        emails = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
            MATCH (u:User) WHERE NOT EXISTS(u.last_access)
            RETURN u.email;
        END_OF_QUERY
        never_seen_users = Set.new(emails)
        emails = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
            MATCH (u:User) WHERE EXISTS(u.last_access)
            RETURN u.email;
        END_OF_QUERY
        seen_users = Set.new(emails)
        
        main = self
        doc = Prawn::Document.new(:page_size => 'A4', :page_layout => :portrait, 
                                  :margin => 2.cm) do
            @@klassen_order.each_with_index do |klasse, i|
                font_size 12
                if ['11', '12'].include?(klasse)
                    font_size 10
                end
                start_new_page if i > 0
                text "<b>Klasse #{klasse}</b>\n\n", inline_format: true
                unless ['11', '12'].include?(klasse)
                    text "Klassenleitung: #{(@@klassenleiter[klasse] || ['-']).join(', ')}\n\n"
                end
                seen_count = (Set.new(@@schueler_for_klasse[klasse]) & seen_users).size
                text "Bisher mindestens einmal am Dashboard angemeldet haben sich <b>#{seen_count}</b> von <b>#{@@schueler_for_klasse[klasse].size}</b> SuS.\n\n", inline_format: true
                text "Folgende SuS haben sich bisher <b>noch nicht</b> am Dashboard angemeldet und können deshalb auch bisher nicht auf die NextCloud zugreifen:\n\n", inline_format: true
                @@schueler_for_klasse[klasse].each do |email|
                    next unless never_seen_users.include?(email)
                    user = @@user_info[email]
                    text "#{user[:display_name]}\n"
                end
                text "\n\nBitte erinnern Sie die SuS daran, schnellstmöglich ihr E-Mail-Postfach einzurichten, sich am Dashboard anzumelden und sich bei der NextCloud anzumelden. ", inline_format: true
                text "Wer seinen E-Mail-Zettel verloren hat, schreibt bitte eine E-Mail an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} – <b>#{WEBSITE_MAINTAINER_EMAIL}</b> – dort bekommt jeder die Zugangsdaten zur Not noch einmal als PDF.\n\n", inline_format: true
                text "Zuerst muss das E-Mail-Postfach eingerichtet werden. Den Zugangscode für das Dashboard bekommt man per E-Mail und die Zugangsdaten für die NextCloud finden sich im Dashboard im Menü ganz rechts: <em>In Nextcloud anmelden…</em>\n\n", inline_format: true
                text "Bei Fällen, in denen ein E-Mail-Postfach abgelehnt wird, suchen Sie bitte das Gespräch und erfragen Sie die Gründe für diese Entscheidung. Es lassen sich für dieses Problem fast immer Lösungen im gegenseitigen Einvernehmen finden und deshalb bitte ich Sie, auch in diesen Fällen einen Kontakt zu #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} herzustellen."
            end
        end
        STDERR.puts "Noch nie angemeldete Lehrer:"
        @@lehrer_order.each do |email|
            next unless never_seen_users.include?(email)
            user = @@user_info[email]
            STDERR.puts user[:display_name]
        end
        respond_raw_with_mimetype(doc.render, 'application/pdf')
    end

    get '/api/directory_xlsx/*' do
        require_teacher!
        klasse = request.path.sub('/api/directory_xlsx/', '')
        file = Tempfile.new('foo')
        result = nil
        begin
            workbook = WriteXLSX.new(file.path)
            sheet = workbook.add_worksheet
            format_header = workbook.add_format({:bold => true})
            sheet.write(0, 0, 'Nachname', format_header)
            sheet.write(0, 1, 'Vorname', format_header)
            sheet.write(0, 2, 'Klasse', format_header)
            sheet.write(0, 3, 'Gruppe', format_header)
            sheet.write(0, 4, 'E-Mail', format_header)
            sheet.write(0, 5, 'E-Mail der Eltern', format_header)
            sheet.set_column(0, 1, 16)
            sheet.set_column(4, 5, 48)
            iterate_directory(klasse) do |email, i|
                user = @@user_info[email]
                group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
                    MATCH (u:User {email: {email}})
                    RETURN COALESCE(u.group2, 'A') AS group2;
                END_OF_QUERY
                sheet.write(i + 1, 0, user[:last_name])
                sheet.write(i + 1, 1, user[:first_name])
                sheet.write(i + 1, 2, user[:klasse])
                sheet.write(i + 1, 3, group2)
                sheet.write(i + 1, 4, user[:email])
                sheet.write(i + 1, 5, 'eltern.' + user[:email])
            end
            workbook.close
            result = File.read(file.path)
        ensure
            file.close
            file.unlink
        end
        respond_raw_with_mimetype_and_filename(result, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', "Klasse #{klasse}.xlsx")
    end
    
    get '/api/jitsi_terms' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Nutzungshinweise-Meet.pdf'), 'application/pdf', "Nutzungshinweise-Meet.pdf")
    end
        
    get '/api/jitsi_dse' do
        respond_raw_with_mimetype_and_filename(File.read('/data/legal/Datenschutzerklärung-Meet.pdf'), 'application/pdf', "Datenschutzerklärung-Meet.pdf")
    end
    
    def gen_jwt_for_room(room = '', eid = nil, user = nil)
        payload = {
            :context => { :user => {}},
            :aud => JWT_APPAUD,
            :iss => JWT_APPISS,
            :sub => JWT_SUB,
            :room => room,
            :exp => DateTime.parse("#{Time.now.strftime('%Y-%m-%d')} 00:00:00").to_time.to_i + 24 * 60 * 60,
            :moderator => teacher_logged_in?
        }
        if user
            payload[:context][:user][:name] = user
        end
        if user_logged_in?
            use_user = @session_user
            if teacher_tablet_logged_in?
                use_user = @@user_info[@@shorthands[user]]
            elsif kurs_tablet_logged_in?
                use_user = {:display_name => 'Kursraum'}
            end
            payload[:context][:user][:name] = use_user[:teacher] ? use_user[:display_last_name] : use_user[:display_name]
            payload[:context][:user][:email] = use_user[:email]
            payload[:context][:user][:avatar] = "#{NEXTCLOUD_URL}/index.php/avatar/#{use_user[:nc_login]}/128"
            if eid
                organizer_email = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :session_email => use_user[:email])['ou.email']
                    MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                    WHERE COALESCE(e.deleted, false) = false
                    RETURN ou.email;
                END_OF_QUERY
                payload[:moderator] = admin_logged_in? || (organizer_email == use_user[:email])
            end
        end
        assert(!(payload[:context][:user][:name].nil?))
        assert(payload[:context][:user][:name].strip.size > 0)
        assert(room.strip.size > 0)

        token = JWT.encode payload, JWT_APPKEY, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        token
    end
    
    def room_name_for_event(title, eid)
        "#{title} (#{eid[0, 8]})"
    end
    
    post '/api/send_missing_event_invitations' do
        require_teacher!
        data = parse_request_data(:required_keys => [:eid])
        id = data[:eid]
        STDERR.puts "Sending missing invitations for event #{id}"
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
            MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(e:Event {id: {id}})<-[rt:IS_PARTICIPANT]-(u)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND SIZE(COALESCE(rt.invitations, [])) = 0
            SET rt.invitation_requested = true;
        END_OF_QUERY
        trigger_send_invites()
        respond(:ok => true)
    end
    
    post '/api/send_missing_poll_run_invitations' do
        require_teacher!
        data = parse_request_data(:required_keys => [:prid])
        id = data[:prid]
        STDERR.puts "Sending missing invitations for poll run #{id}"
        neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :id => id)
            MATCH (a:User {email: {session_email}})<-[:ORGANIZED_BY]-(p:Poll)<-[:RUNS]-(pr:PollRun {id: {id}})<-[rt:IS_PARTICIPANT]-(u)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND SIZE(COALESCE(rt.invitations, [])) = 0
            SET rt.invitation_requested = true;
        END_OF_QUERY
        trigger_send_invites()
        respond(:ok => true)
    end
    
    post '/api/toggle_group2_for_user' do
        require_teacher!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email)['group2']
            MATCH (u:User {email: {email}})
            RETURN COALESCE(u.group2, 'A') AS group2;
        END_OF_QUERY
        if group2 == 'A'
            group2 = 'B'
        else
            group2 = 'A'
        end
        group2 = neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :group2 => group2)['group2']
            MATCH (u:User {email: {email}})
            SET u.group2 = {group2}
            RETURN u.group2 AS group2;
        END_OF_QUERY
        respond(:group2 => group2)
    end
    
    post '/api/get_homework_feedback' do
        require_user!
        data = parse_request_data(:required_keys => [:entries],
                                  :types => {:entries => Array})
        results = {}
        data[:entries].each do |entry|
            parts = entry.split('/')
            lesson_key = parts[0]
            offset = parts[1].to_i
            hf = neo4j_query(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => lesson_key, :offset => offset).map { |x| x['hf'].props }
                MATCH (u:User {email: {session_email}})<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
                RETURN hf;
            END_OF_QUERY
            results[entry] = {}
            hf.each do |x|
                results[entry] = x
            end
        end
        respond(:homework_feedback => results)
    end
    
    post '/api/mark_homework_done' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})
         neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => data[:lesson_key], :offset => data[:offset])
            MATCH (u:User {email: {session_email}}), (li:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
            WITH u, li
            MERGE (u)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li)
            SET hf.done = true
            RETURN hf;
        END_OF_QUERY
        respond(:yeah => 'sure')
    end
    
    post '/api/mark_homework_undone' do
        require_user!
        data = parse_request_data(:required_keys => [:lesson_key, :offset],
                                  :types => {:offset => Integer})
         neo4j_query_expect_one(<<~END_OF_QUERY, :session_email => @session_user[:email], :lesson_key => data[:lesson_key], :offset => data[:offset])
            MATCH (u:User {email: {session_email}}), (li:LessonInfo {offset: {offset}})-[:BELONGS_TO]->(l:Lesson {key: {lesson_key}})
            WITH u, li
            MERGE (u)<-[:FROM]-(hf:HomeworkFeedback)-[:FOR]->(li)
            SET hf.done = false
            RETURN hf;
        END_OF_QUERY
        respond(:yeah => 'sure')
    end
    
    def gen_jitsi_data(path)
        ua = USER_AGENT_PARSER.parse(request.env['HTTP_USER_AGENT'])
        browser_icon = 'fa-microphone'
        browser_name = 'Browser'
        ['edge', 'firefox', 'chrome', 'safari', 'opera'].each do |x|
            if ua.family.downcase.include?(x)
                browser_icon = x
                browser_name = x.capitalize
            end
        end
        os_family = ua.os.family.downcase.gsub(/\s+/, '').strip
        result = {:html => "<p class='alert alert-danger'>Der Videochat konnte nicht gefunden werden.</p>"}
        room_name = nil
        can_enter_room = false
        eid = nil
        ext_name = nil
        begin
            if path == 'Lehrerzimmer'
                if teacher_logged_in?
                    room_name = 'Lehrerzimmer'
                    can_enter_room = true
                    result[:html] = ''
                    result[:html] += "<div class='alert alert-warning'><strong>Hinweis:</strong> Wenn Sie das Lehrerzimmer betreten, wird allen Kolleginnen und Kollegen über dem Stundenplan angezeigt, dass Sie momentan im Lehrerzimmer sind. Das Lehrerzimmer steht nicht nur Lehrkräften, sondern auch unseren Kolleg*innen aus dem Otium und dem Sekretariat zur Verfügung. Für Schülerinnen und Schüler ist der Zutritt nicht möglich.</div>"
                end
            elsif path[0, 6] == 'event/'
                result[:html] = ''
                # it's an event!
                parts = path.split('/')
                eid = parts[1]
                code = parts[2]
                invitation = nil
                organizer_email = nil
                event = nil
                data = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid)
                    MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                    WHERE COALESCE(e.deleted, false) = false
                    RETURN e, ou.email;
                END_OF_QUERY
                organizer_email = data['ou.email']
                event = data['e'].props
                room_name = room_name_for_event(event[:title], eid)
                
                if code
                    # EVENT - EXTERNAL USER WITH CODE
                    rows = neo4j_query(<<~END_OF_QUERY, :eid => eid)
                        MATCH (u)-[rt:IS_PARTICIPANT]->(e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                        WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(e.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                        RETURN e, ou.email, u;
                    END_OF_QUERY
                    invitation = rows.select do |row|
                        row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['e'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
                        code == row_code
                    end.first
                    ext_name = invitation['u'].props[:name]
                else
                    # EVENT - INTERNAL USER
                    require_user!
                    begin
                        # EVENT - INTERNAL USER IS ORGANIZER
                        invitation = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :email => @session_user[:email])
                            MATCH (e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User {email: {email}})
                            WHERE COALESCE(e.deleted, false) = false
                            RETURN e, ou.email;
                        END_OF_QUERY
                    rescue
                        # EVENT - INTERNAL USER IS INVITED
                        invitation = neo4j_query_expect_one(<<~END_OF_QUERY, :eid => eid, :email => @session_user[:email])
                            MATCH (u:User {email: {email}})-[rt:IS_PARTICIPANT]->(e:Event {id: {eid}})-[:ORGANIZED_BY]->(ou:User)
                            WHERE COALESCE(e.deleted, false) = false AND COALESCE(rt.deleted, false) = false
                            RETURN e, ou.email, u;
                        END_OF_QUERY
                    end
                end
                assert(invitation != nil)

                now = Time.now
                event_start = Time.parse("#{event[:date]}T#{event[:start_time]}")
                event_end = Time.parse("#{event[:date]}T#{event[:end_time]}")
                result[:html] += "<b class='key'>Termin:</b>#{event[:title]}<br />\n"
                result[:html] += "<b class='key'>Eingeladen von:</b>#{(@@user_info[organizer_email] || {})[:display_name]}<br />\n"
                event_date = Date.parse(event[:date])
                result[:html] += "<b class='key'>Datum:</b>#{WEEKDAYS[event_date.wday]}, #{event_date.strftime('%d.%m.%Y')}<br />\n"
                result[:html] += "<b class='key'>Zeit:</b>#{event[:start_time]} &ndash; #{event[:end_time]} Uhr<br />\n"
                if now < event_start - JITSI_EVENT_PRE_ENTRY_TOLERANCE * 60
                    result[:html] += "<div class='alert alert-warning'>Sie können den Raum erst #{JITSI_EVENT_PRE_ENTRY_TOLERANCE} Minuten vor Beginn betreten. Bitte laden Sie die Seite dann neu, um in den Raum zu gelangen.</div>"
                    # room can't yet be entered (too early)
                elsif now > event_end + JITSI_EVENT_POST_ENTRY_TOLERANCE * 60
                    # room can't be entered anymore (too late)
                    result[:html] += "<div class='alert alert-danger'>Der Termin liegt in der Vergangenheit. Sie können den Videochat deshalb nicht mehr betreten.</div>"
                else
                    can_enter_room = true
                end
                result[:html] += "<hr />"
            else
                # it's a lesson, only allow between 07:00 and 18:00
                require_user!
                can_enter_room = true
                room_name = path
                if room_name.index('Klassenstream') == 0
                    if (!@session_user[:teacher]) && (!get_homeschooling_for_user(@session_user[:email])) && room_name.index('Klassenstream') == 0
                        result[:html] += "<div class='alert alert-danger'>Du bist momentan nicht für den Klassenstream freigeschaltet. Deine Klassenleiterin oder dein Klassenleiter kann dich dafür freischalten.</div>"
                        can_enter_room = false
                    end
                    if can_enter_room
                        now_s = Time.now.strftime('%H:%M')
                        if now_s < '07:00' || now_s > '18:00'
                            result[:html] += "<div class='alert alert-warning'>Der #{PROVIDE_CLASS_STREAM ? 'Klassenstream' : 'Stream'} ist nur von 07:00 bis 18:00 Uhr geöffnet.</div>"
                            can_enter_room = false
                        end
                    end
                else
                    if teacher_tablet_logged_in?
                        ext_name = path.split('@')[1]
                        ext_name = URI.decode_www_form(ext_name).first.first
                        path = path.split('@')[0]
                    end
                    if kurs_tablet_logged_in?
                        ext_name = 'Kursraum'
                        path = path.split('@')[0]
                    end
                    result[:html] = ''
                    lesson_key = path.sub('lesson/', '')
                    p_ymd = Date.today.strftime('%Y-%m-%d')
                    p_yw = Date.today.strftime('%Y-%V')
                    assert(user_logged_in?)
                    timetable_path = "/gen/w/#{@session_user[:id]}/#{p_yw}.json.gz"
                    timetable = nil
                    Zlib::GzipReader.open(timetable_path) do |f|
                        timetable = JSON.parse(f.read)
                    end
                    assert(!(timetable.nil?))
                    timetable = timetable['events'].select do |entry|
                        entry['lesson'] && entry['lesson_key'] == lesson_key && entry['datum'] == p_ymd && (entry['data'] || {})['lesson_jitsi']
                    end.sort { |a, b| a['start'] <=> b['start'] }
                    now_time = Time.now
                    old_timetable_size = timetable.size
                    timetable = timetable.reject do |entry|
                        t = Time.parse("#{entry['end']}:00") + JITSI_LESSON_POST_ENTRY_TOLERANCE * 60
                        now_time > t
                    end
                    if timetable.empty?
                        if old_timetable_size > 0
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht mehr geöffnet.</div>"
                        else
                            result[:html] += "<div class='alert alert-warning'>Dieser Jitsi-Raum ist heute nicht geöffnet.</div>"
                        end
                        can_enter_room = false
                    else
                        t = Time.parse("#{timetable.first['start']}:00") - JITSI_LESSON_PRE_ENTRY_TOLERANCE * 60
                        room_name = timetable.first['label_lehrer_lang'].gsub(/<[^>]+>/, '') + ' ' + timetable.first['klassen'].first.map { |x| tr_klasse(x) }.join(', ')
                        if now_time >= t
                            can_enter_room = true
                        else
                            timediff = ((t - now_time).to_f / 60.0).ceil
                            tds = "#{timediff} Minute#{timediff == 1 ? '' : 'n'}"
                            tds = "#{timediff / 60} Stunde#{timediff / 60 == 1 ? '' : 'n'} und #{timediff % 60} Minute#{(timediff % 60) == 1 ? '' : 'n'}" if timediff > 60
                            if timediff == 1
                                tds = 'einer Minute'
                            elsif timediff == 2
                                tds = 'zwei Minuten'
                            elsif timediff == 3
                                tds = 'drei Minuten'
                            elsif timediff == 4
                                tds = 'vier Minuten'
                            elsif timediff == 5
                                tds = 'fünf Minuten'
                            end
                            result[:html] += "<div class='alert alert-warning'>Der Jitsi-Raum <strong>»#{room_name}«</strong> ist erst ab #{t.strftime('%H:%M')} Uhr geöffnet. Du kannst ihn in #{tds} betreten.</div>"
                            can_enter_room = false
                        end
                    end
                    room_name = CGI.unescape(room_name)
                end
            end
            if can_enter_room
                # room can be entered now
                if ext_name
                    temp_name = ext_name.dup
                    if teacher_tablet_logged_in?
                        temp_name = @@user_info[@@shorthands[ext_name]][:display_last_name]
                    end
                    result[:html] += "<p>Sie können dem Videochat jetzt als <b>#{temp_name}</b> beitreten.</p>\n"
                end
                result[:html] += "<div class='alert alert-secondary'>\n"
                result[:html] += "<p>Ich habe die <a href='/api/jitsi_terms'>Nutzerordnung</a> und die <a href='/api/jitsi_dse'>Datenschutzerklärung</a> zur Kenntnis genommen und willige ein.</p>\n"
                room_name = CGI.escape(room_name.gsub(/[\:\?#\[\]@!$&\\'()*+,;=><\/"]/, '')).gsub('+', '%20')
                jwt = gen_jwt_for_room(room_name, eid, ext_name)
                result[:html] += "<div class='go_div'>\n"
                # edge firefox chrome safari opera internet-explorer
                if os_family == 'ios' || os_family == 'macosx'
                    result[:html] += "<a class='btn btn-success' href='org.jitsi.meet://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-apple'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet betreten (iPhone und iPad)</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://apps.apple.com/de/app/jitsi-meet/id1165103905' target='_blank'>App Store</a>.</em></p>"
                    unless browser_icon == 'safari'
                        result[:html] += "<a class='btn btn-outline-secondary' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                    end
                    if browser_icon == 'safari'
                        result[:html] += "<p style='font-size: 90%;'><em>Falls Sie einen Mac verwenden: Leider funktioniert Jitsi Meet nicht mit Safari. Verwenden Sie bitte einen anderen Web-Browser wie <a href='https://www.google.com/intl/de_de/chrome/' target='_blank'>Google Chrome</a> oder <a href='https://www.mozilla.org/de/firefox/new/' target='_blank'>Firefox</a>.</em></p>"
                    end
                elsif os_family == 'android'
                    result[:html] += "<a class='btn btn-success' href='intent://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}#Intent;scheme=org.jitsi.meet;package=org.jitsi.meet;end'><i class='fa fa-microphone'></i>&nbsp;&nbsp;Jitsi-Raum mit Jitsi Meet für Android betreten</a>"
                    result[:html] += "<p style='font-size: 90%;'><em>Installieren Sie bitte die Jitsi Meet-App aus dem <a href='https://play.google.com/store/apps/details?id=org.jitsi.meet' target='_blank'>Google Play Store</a> oder via <a href='https://f-droid.org/en/packages/org.jitsi.meet/' target='_blank' style=''>F&#8209;Droid</a>.</em></p>"
                    result[:html] += "<a class='btn btn-outline-secondary' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                else
                    result[:html] += "<a class='btn btn-success' target='_blank' href='https://#{JITSI_HOST}/#{room_name}?jwt=#{jwt}'><i class='fa fa-#{browser_icon}'></i>&nbsp;&nbsp;Jitsi-Raum mit #{browser_name} betreten</a>"
                end
                result[:html] += "</div>\n"
                result[:html] += "</div>\n"
            end
        rescue StandardError => e
            STDERR.puts "gen_jitsi_data failed for path [#{path}]"
            STDERR.puts e
            STDERR.puts e.backtrace
            result = {:html => "<p class='alert alert-danger'>Der Videochat konnte nicht gefunden werden.</p>"}
        end
        result
    end
    
    def gen_poll_data(path)
        result = {}
        result[:html] = ''
        parts = path.sub('/poll/', '').split('/')
        prid = parts[0]
        code = parts[1]
        assert((prid.is_a? String) && (!code.empty?))
        assert((code.is_a? String) && (!code.empty?))
        rows = neo4j_query(<<~END_OF_QUERY, :prid => prid)
            MATCH (u)-[rt:IS_PARTICIPANT]->(pr:PollRun {id: {prid}})-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(ou:User)
            WHERE (u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(pr.deleted, false) = false AND COALESCE(rt.deleted, false) = false
            RETURN pr, ou.email, u, p;
        END_OF_QUERY
        invitation = rows.select do |row|
            row_code = Digest::SHA2.hexdigest(EXTERNAL_USER_EVENT_SCRAMBLER + row['pr'].props[:id] + row['u'].props[:email]).to_i(16).to_s(36)[0, 8]
            code == row_code
        end.first
        if invitation.nil?
            redirect "#{WEB_ROOT}/poll_not_found", 302
            return
        end
        ext_name = invitation['u'].props[:name]
        poll = invitation['p'].props
        poll_run = invitation['pr'].props
        now = "#{Date.today.strftime('%Y-%m-%d')}T#{Time.now.strftime('%H:%M')}:00"
        start_time = "#{poll_run[:start_date]}T#{poll_run[:start_time]}:00"
        end_time = "#{poll_run[:end_date]}T#{poll_run[:end_time]}:00"
        result[:organizer] = (@@user_info[invitation['ou.email']] || {})[:display_last_name]
        result[:organizer_icon] = user_icon(invitation['ou.email'], 'avatar-fill')
        result[:title] = poll[:title]
        result[:end_date] = poll_run[:end_date]
        result[:end_time] = poll_run[:end_time]
        result[:prid] = prid
        result[:code] = code
        result[:external_user_name] = ext_name
        if now < start_time
            result[:disable_launch_button] = true
            result[:html] += "Die Umfrage öffnet erst am"
            result[:html] += " #{Date.parse(poll_run[:start_date]).strftime('%d.%m.%Y')} um #{poll_run[:start_time]} Uhr (in <span class='moment-countdown' data-target-timestamp='#{poll_run[:start_date]}T#{poll_run[:start_time]}:00' data-before-label='' data-after-label=''></span>)."
        elsif now > end_time
            result[:disable_launch_button] = true
            result[:html] += "Die Umfrage ist bereits beendet."
        else
            result[:disable_launch_button] = false
            result[:html] += "Sie können noch bis zum #{Date.parse(poll_run[:end_date]).strftime('%d.%m.%Y')} um #{poll_run[:end_time]} Uhr teilnehmen (die Umfrage <span class='moment-countdown' data-target-timestamp='#{poll_run[:end_date]}T#{poll_run[:end_time]}:00' data-before-label='läuft noch' data-after-label='ist vorbei'></span>)."
        end
        result
    end
    
    def print_login_ranking()
        stats = get_login_stats()
        klassen_stats = {}
        @@klassen_order.each do |klasse|
            klassen_stats[klasse] = 100 * stats[klasse][:count][LOGIN_STATS_D.last].to_f / stats[klasse][:total]
            if stats[klasse][:count][LOGIN_STATS_D.last] == stats[klasse][:total]
                neo4j_query(<<~END_OF_QUERY, :klasse => klasse, :timestamp => Time.now.to_i)
                    MERGE (n:KlasseKomplett {klasse: {klasse}})
                    ON CREATE SET n.timestamp = {timestamp}
                END_OF_QUERY
            end
        end
        klassen_ranking = neo4j_query(<<~END_OF_QUERY).map { |x| x['n.klasse'] }
            MERGE (n:KlasseKomplett)
            RETURN n.klasse
            ORDER BY n.timestamp ASC;
        END_OF_QUERY
        now = Time.now.to_i
        StringIO.open do |io|
            io.puts "<p style='text-align: center;'>"
            io.puts "<em>Die ersten Klassen sind komplett im Dashboard angemeldet.<br />Herzlichen Glückwunsch an die Klassen #{join_with_sep(klassen_ranking.map { |x| '<b>' + (tr_klasse(x) || '') + '</b>' }, ', ', ' und ')}!</em>"
            io.puts "</p>"
            klassen_stats.keys.sort do |a, b|
                va = sprintf('%020d%020d', 1000 - (klassen_ranking.index(a) || 1000), klassen_stats[a] * 1000)
                vb = sprintf('%020d%020d', 1000 - (klassen_ranking.index(b) || 1000), klassen_stats[b] * 1000)
                vb <=> va
            end.each.with_index do |klasse, index|
                place = "#{index + 1}."
                percent = klassen_stats[klasse]
                bgcol = get_gradient(['#cc0000', '#f4951b', '#ffe617', '#80bc42'], percent / 100.0)
                c = ''
                star_span = ''
                if stats[klasse][:count][LOGIN_STATS_D.last] == stats[klasse][:total]
                    c = 'complete'
                    star_span = "<i class='fa fa-star'></i>"
                else
                    place = ''
                end
                io.puts "<span class='ranking #{c}' style='background-color: #{bgcol};'>#{star_span}<span class='klasse'>#{tr_klasse(klasse)}</span><span class='percent'>#{percent.to_i}%</span>"
                io.puts "<span class='place'>#{place}</span>" unless place.empty?
                io.puts "</span>"
            end
            io.string
        end
    end
    
    get "/api/website_get_teachers/#{WEBSITE_READ_INFO_SECRET}" do
        data = {}
        data[:teachers] = @@user_info.select do |email, info|
            info[:teacher] && !info[:shorthand].empty? && info[:shorthand][0] != '_'
        end.map do |email, info|
            {:name => info[:display_last_name],
             :email => info[:email]}
        end
        respond(data)
    end
    
    get "/api/website_get_events/#{WEBSITE_READ_INFO_SECRET}" do
        data = {}
        results = neo4j_query(<<~END_OF_QUERY).map { |x| x['e'].props }
            MATCH (e:WebsiteEvent)
            RETURN e
            ORDER BY e.date, e.title;
        END_OF_QUERY
        data[:events] = results.map do |x|
            x.select do |k, v|
                [:date, :title, :cancelled].include?(k)
            end
        end
        respond(data)
    end
    
    get '/*' do
        path = request.env['REQUEST_PATH']
        assert(path[0] == '/')
        path = path[1, path.size - 1]
        path = 'index' if path.empty?
        path = path.split('/').first
        brand = SCHUL_NAME
        if path.include?('..') || (path[0] == '/')
            status 404
            return
        end
        
        slug = nil
        task = nil
        sha1 = nil
        cat_slug = nil
        klasse = nil
        show_lesson_key = nil
        lesson_key_id = nil
        lesson_data = nil
        timetable_id = nil
        initial_date = Date.parse([@@config[:first_school_day], Date.today.to_s].max.to_s)
        while [6, 0].include?(initial_date.wday)
        #while [0].include?(initial_date.wday)
           initial_date += 1
        end
        initial_date = initial_date.strftime('%Y-%m-%d')
        latest_vplan_timestamp = ''
        os_family = 'unknown'
        jitsi_data = nil
        poll_data = nil
        
        if (@session_user || {})[:can_upload_vplan]
            latest_vplan_timestamp = File.basename(Dir['/vplan/*.txt'].sort.last || '').sub('.txt', '')
        end
        
        now = Time.now.to_i - MESSAGE_DELAY
        sent_messages = []
        stored_events = []
        stored_polls = []
        stored_poll_runs = []
        show_event = {}
        external_users_for_session_user = []
        if path == 'directory'
            redirect "#{WEB_ROOT}/", 302 unless @session_user
            parts = request.env['REQUEST_PATH'].split('/')
            klasse = parts[2]
#             STDERR.puts @@teachers_for_klasse[klasse].to_yaml
            unless can_see_all_timetables_logged_in?
                unless @@teachers_for_klasse[klasse]
                    redirect "#{WEB_ROOT}/", 302
                end
                unless @@teachers_for_klasse[klasse].include?(@session_user[:shorthand])
                    redirect "#{WEB_ROOT}/", 302
                end
            end
        elsif path == 'lessons'
            redirect "#{WEB_ROOT}/", 302 unless @session_user
            parts = request.env['REQUEST_PATH'].split('/')
            show_lesson_key = CGI::unescape(parts[2])
            lesson_key_id = @@lessons[:lesson_keys][show_lesson_key][:id]
            lesson_data = get_lesson_data(show_lesson_key)
            unless may_edit_lessons?(show_lesson_key)
                redirect "#{WEB_ROOT}/", 302
            end
        elsif path == 'jitsi'
            jitsi_data = gen_jitsi_data(request.path.sub('/jitsi/', ''))
        elsif path == 'poll'
            poll_data = gen_poll_data(request.path.sub('/jitsi/', ''))
        elsif path == 'index'
            if @session_user
                path = 'timetable' 
            else
                path = 'login'
            end
        elsif path == 'timetable'
            redirect "#{WEB_ROOT}/", 302 unless @session_user
            if teacher_logged_in? || tablet_logged_in?
                parts = request.env['REQUEST_PATH'].split('/')
                timetable_id = parts[2]
            end
        elsif path == 'messages'
            unless @session_user
                redirect "#{WEB_ROOT}/", 302 
            else
                neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                    MATCH (c)-[ruc:TO]->(:User {email: {email}})
                    WHERE (c:TextComment OR c:AudioComment OR c:Message)
                    SET ruc.seen = true
                END_OF_QUERY
                sent_messages = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['m'].props, :recipient => x['r.email']} }
                    MATCH (m:Message)-[:FROM]->(u:User {email: {email}})
                    WHERE COALESCE(m.deleted, false) = false
                    WITH m
                    OPTIONAL MATCH (m)-[:TO]->(r:User)
                    RETURN m, r.email
                    ORDER BY m.created DESC, m.id;
                END_OF_QUERY
                temp = {}
                temp_order = []
                sent_messages.each do |x|
                    unless temp[x[:info][:id]]
                        t = Time.at(x[:info][:created])
                        temp[x[:info][:id]] = {
                            :recipients => [],
                            :date => t.strftime('%Y-%m-%d'),
                            :dow => t.wday,
                            :mid => x[:info][:id]
                        }
                        temp_order << x[:info][:id]
                    end
                    temp[x[:info][:id]][:recipients] << x[:recipient]
                end
                sent_messages = temp_order.map { |x| temp[x] }
            end
        elsif path == 'events'
            unless teacher_logged_in?
                redirect "#{WEB_ROOT}/", 302 
            else
                stored_events = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['e'].props, :recipient => x['u.email']} }
                    MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User {email: {email}})
                    WHERE COALESCE(e.deleted, false) = false
                    WITH e
                    OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    RETURN e, u.email
                    ORDER BY e.created DESC, e.id;
                END_OF_QUERY
                external_users_for_session_user = external_users_for_session_user()
                temp = {}
                temp_order = []
                stored_events.each do |x|
                    unless temp[x[:info][:id]]
                        t = Time.parse(x[:info][:date])
                        temp[x[:info][:id]] = {
                            :recipients => [],
                            :eid => x[:info][:id],
                            :info => x[:info],
                            :dow => t.wday
                        }
                        temp_order << x[:info][:id]
                    end
                    temp[x[:info][:id]][:recipients] << x[:recipient]
                end
                stored_events = temp_order.map { |x| temp[x] }
            end
        elsif path == 'polls'
            unless teacher_logged_in?
                redirect "#{WEB_ROOT}/", 302 
            else
                stored_polls = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['p'].props, :recipient => x['u.email']} }
                    MATCH (p:Poll)-[:ORGANIZED_BY]->(ou:User {email: {email}})
                    WHERE COALESCE(p.deleted, false) = false
                    WITH p
                    OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(p)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    RETURN p, u.email
                    ORDER BY p.created DESC, p.id;
                END_OF_QUERY
                external_users_for_session_user = external_users_for_session_user()
                temp = {}
                temp_order = []
                stored_polls.each do |x|
                    unless temp[x[:info][:id]]
                        temp[x[:info][:id]] = {
                            :pid => x[:info][:id],
                            :poll => x[:info],
                            :created => Time.at(x[:info][:created]).strftime('%Y-%m-%d')
                        }
                        temp_order << x[:info][:id]
                    end
                end
                stored_polls = temp_order.map { |x| temp[x] }
                
                stored_poll_runs = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['pr'].props, :recipient => x['user_email'], :pid => x['pid'], :response_count => x['response_count']} }
                    MATCH (pr:PollRun)-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(ou:User {email: {email}})
                    WHERE COALESCE(pr.deleted, false) = false
                    AND COALESCE(p.deleted, false) = false
                    WITH pr, p
                    OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(pr)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    WITH pr, u.email AS user_email, p.id AS pid
                    OPTIONAL MATCH (pu)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    WHERE (pu:User OR pu:ExternalUser OR pu:PredefinedExternalUser) 
                    RETURN pr, user_email, pid, COUNT(prs) as response_count
                    ORDER BY pr.start_date ASC, pr.start_time ASC;
                END_OF_QUERY
                temp = {}
                temp_order = []
                stored_poll_runs.each do |x|
                    unless temp[x[:info][:id]]
                        temp[x[:info][:id]] = {
                            :recipients => [],
                            :prid => x[:info][:id],
                            :pid => x[:pid],
                            :info => x[:info],
                            :response_count => x[:response_count]
                        }
                        temp_order << x[:info][:id]
                    end
                    temp[x[:info][:id]][:recipients] << x[:recipient]
                end
                stored_poll_runs = temp_order.map { |x| temp[x] }
            end
        elsif path == 'login_nc'
            unless @session_user
                redirect "#{WEB_ROOT}/", 302 
            end
        end
        new_messages_count = 0
        unread_message_ids = []
        if user_logged_in?
            timetable_id ||= @session_user[:id]
            unread_message_ids = get_unread_messages(now)
            new_messages_count = unread_message_ids.size
        end
        
        @page_title = ''
        @page_description = ''
        
        font_family = (@session_user || {})[:font]
        color_scheme = (@session_user || {})[:color_scheme]
        font_family = 'Roboto' unless AVAILABLE_FONTS.include?(font_family)
        unless color_scheme =~ /^[ld][0-9a-f]{18}[0-6]?$/
            unless user_logged_in?
                @@default_color_scheme ||= {}
                jd = Date.today.jd
                if @@default_color_scheme[jd].nil?
                    srand(jd)
                    which = @@color_scheme_colors.select do |x|
                        x[4] == 'l'
                    end.sample
                    @@default_color_scheme[jd] = "#{which[4]}#{which[0, 3].join('').gsub('#', '')}#{[0, 1, 2, 3, 5, 6].sample}"
                end
                color_scheme = @@default_color_scheme[jd]
            else
                color_scheme = @@standard_color_scheme
            end
        end
        if color_scheme.size < 20
            color_scheme += '0'
        end
        @@renderer.render(["##{color_scheme[1, 6]}", "##{color_scheme[7, 6]}", "##{color_scheme[13, 6]}"], (@session_user || {})[:email])
        primary_color = '#' + color_scheme[7, 6]
        primary_color_darker = darken(primary_color, 0.8)
        desaturated_color = darken(desaturate(primary_color), 0.9)
        desaturated_color_darker = darken(desaturate(primary_color), 0.3)
        disabled_color = rgb_to_hex(mix(hex_to_rgb(primary_color), [192, 192, 192], 0.7))
        shifted_color = shift_hue(primary_color, 350)
        color_palette = {:primary => primary_color, :disabled => disabled_color, :shifted => desaturated_color}
        
        unless path.include?('/')
            unless path.include?('.') || path[0] == '_'
                original_path = path.dup
                show_offer = {}
                
                path = File::join('/static', path) + '.html'
                if File::exists?(path)
                    content = File::read(path, :encoding => 'utf-8')
                    
                    @original_path = original_path
                    @task_slug = slug
                    if original_path == 'c'
                        parts = request.env['REQUEST_PATH'].split('/')
                        login_tag = parts[2]
                        login_code = parts[3]
                    end
                    
                    template_path = '_template'
                    template_path = "/static/#{template_path}.html"
                    @template ||= {}
                    @template[template_path] ||= File::read(template_path, :encoding => 'utf-8')
                    
                    s = @template[template_path].dup
                    s.sub!('#{CONTENT}', content)
                    s.gsub!('{BRAND}', brand);
                    purge_missing_sessions()
                    page_css = ''
                    if File::exist?(path.sub('.html', '.css'))
                        page_css = "<style>\n#{File::read(path.sub('.html', '.css'))}\n</style>"
                    end
                    s.sub!('#{PAGE_CSS_HERE}', page_css)
                    compiled_js_sha1 = @@compiled_files[:js][:sha1]
                    compiled_css_sha1 = @@compiled_files[:css][:sha1]
                    meta_tags = ''

                    while true
                        index = s.index('#{')
                        break if index.nil?
                        length = 2
                        balance = 1
                        while index + length < s.size && balance > 0
                            c = s[index + length]
                            balance -= 1 if c == '}'
                            balance += 1 if c == '{'
                            length += 1
                        end
                        code = s[index + 2, length - 3]
                        begin
#                             STDERR.puts code
                            s[index, length] = eval(code).to_s || ''
                        rescue
                            STDERR.puts "Error while evaluating:"
                            STDERR.puts code
                            raise
                        end
                    end
                    s.gsub!('<!--PAGE_TITLE-->', @page_title)
                    s.gsub!('<!--PAGE_DESCRIPTION-->', @page_description)
                    s
                else
                    status 404
                end
            else
                status 404
            end
        else
            status 404
        end
    end

    run! if app_file == $0
end
