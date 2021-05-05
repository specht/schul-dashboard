require 'base64'
require 'cgi'
require 'csv'
require 'curb'
require 'date'
require 'digest/sha1'
require 'htmlentities'
require 'i18n'
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
require 'zip'

require './credentials.template.rb'
warn_level = $VERBOSE
$VERBOSE = nil
require './credentials.rb'
$VERBOSE = warn_level

require './background-renderer.rb'
require './include/admin.rb'
require './include/color.rb'
require './include/comment.rb'
require './include/directory.rb'
require './include/event.rb'
require './include/ext_user.rb'
require './include/file.rb'
require './include/homework.rb'
require './include/ical.rb'
require './include/image.rb'
require './include/jitsi.rb'
require './include/lesson.rb'
require './include/login.rb'
require './include/message.rb'
require './include/otp.rb'
require './include/poll.rb'
require './include/stats.rb'
require './include/tests.rb'
require './include/theme.rb'
require './include/user.rb'
require './include/vote.rb'
require './include/vplan.rb'
require './include/website_events.rb'
require './parser.rb'

def remove_accents(s)
    I18n.transliterate(s.gsub('ä', 'ae').gsub('ö', 'oe').gsub('ü', 'ue').gsub('Ä', 'Ae').gsub('Ö', 'Oe').gsub('Ü', 'Ue').gsub('ß', 'ss').gsub('ė', 'e'))
end

def debug(message, index = 0)
    index = 0
    begin
        while index < caller_locations.size - 1 && ['transaction', 'neo4j_query', 'neo4j_query_expect_one'].include?(caller_locations[index].base_label)
            index += 1
        end
    rescue
        index = 0
    end
    l = caller_locations[index]
    ls = ''
    begin
        ls = "#{l.path.sub('/app/', '')}:#{l.lineno} @ #{l.base_label}"
    rescue
        ls = "#{l[0].sub('/app/', '')}:#{l[1]}"
    end
    STDERR.puts "#{DateTime.now.strftime('%H:%M:%S')} [#{ls}] #{message}"
end

def debug_error(message)
    l = caller_locations.first
    ls = ''
    begin
        ls = "#{l.path.sub('/app/', '')}:#{l.lineno} @ #{l.base_label}"
    rescue
        ls = "#{l[0].sub('/app/', '')}:#{l[1]}"
    end
    STDERR.puts "#{DateTime.now.strftime('%H:%M:%S')} [ERROR] [#{ls}] #{message}"
end

USER_AGENT_PARSER = UserAgentParser::Parser.new
WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']
HOMEWORK_FEEDBACK_STATES = ['good', 'hmmm', 'lost']
HOMEWORK_FEEDBACK_EMOJIS = {'good' => '🙂', 
                            'hmmm' => '🤔',
                            'lost' => '😕'}

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
        item = nil
        if @tx.empty?
            item = @neo4j.begin_transaction
#             STDERR.puts "Starting transaction ##{item['commit'].split("/")[-2]}."
            @transaction_size = 0
        end
        @tx << item
        begin
            result = yield
            item = @tx.pop
            unless item.nil?
#                 STDERR.puts "Committing transaction ##{item['commit'].split("/")[-2]} with #{@transaction_size} queries."
                @neo4j.commit_transaction(item)
            end
            result
        rescue
            item = @tx.pop
            unless item.nil?
                begin
                    debug("Rolling back transaction ##{item['commit'].split("/")[-2]} with #{@transaction_size} queries.")
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
    
    def wait_for_neo4j
        delay = 1
        10.times do
            begin
                neo4j_query("MATCH (n) RETURN n LIMIT 1;")
                break
            rescue
                STDERR.puts $!
                STDERR.puts "Retrying after #{delay} seconds..."
                sleep delay
                delay += 1
            end
        end
    end

    def neo4j_query(query_str, options = {})
#         debug(query_str, 1) if DEVELOPMENT
        transaction do
            temp_result = nil
            5.times do
                begin
                    temp_result = @neo4j.in_transaction(@tx.first, [query_str, options])
                    break
                rescue Excon::Error::Socket
                    STDERR.puts "ATTENTION: Retrying query:"
                    STDERR.puts query_str
                    STDERR.puts options.to_json
                    sleep 1.0
                end
            end
            if temp_result.nil?
                STDERR.puts "ATTENTION: Giving up on query after 5 tries."
                raise 'neo4j_oopsie'
            end
                
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
            @transaction_size += 1
            result
        end
    end

    def neo4j_query_expect_one(query_str, options = {})
        transaction do
            result = neo4j_query(query_str, options).to_a
            unless result.size == 1
                debug '-' * 40
                debug query_str
                debug options.to_json
                debug '-' * 40
                raise "Expected one result but got #{result.size}" 
            end
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
    if DEVELOPMENT
        debug "Not sending mail to because we're in development: #{mail.subject} => #{mail.to.join(' / ')}"
    else
        mail.deliver!
    end
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
                    duplicate_peu = neo4j_query(<<~END_OF_QUERY)
                        MATCH (n:PredefinedExternalUser)
                        WITH n.email AS email, COLLECT(n) AS nodes
                        WHERE SIZE(nodes) > 1
                        RETURN nodes;
                    END_OF_QUERY
                    duplicate_peu.each do |entry|
                        debug entry.to_yaml
                        entry['nodes'].select do |node|
                            node['name'] != main.class_variable_get(:@@predefined_external_users)[:recipients][node['email']][:label]
                        end.each do |node|
                            debug "DELETING PEU #{node['name']}"
                            neo4j_query(<<~END_OF_QUERY, {:name => node['name'], :email => node['email']})
                                MATCH (n:PredefinedExternalUser {name: {name}, email: {email}})
                                DETACH DELETE n;
                            END_OF_QUERY
                        end
                    end
                end
                transaction do
                    debug "Removing all constraints and indexes..."
                    indexes = []
#                     neo4j_query("CALL db.constraints").each do |constraint|
#                         query = "DROP #{constraint['description']}"
#                         neo4j_query(query)
#                     end
#                     neo4j_query("CALL db.indexes").each do |index|
#                         query = "DROP #{index['description']}"
#                         neo4j_query(query)
#                     end
                    
                    debug "Setting up constraints and indexes..."
                    neo4j_query("CREATE CONSTRAINT ON (n:LoginCode) ASSERT n.tag IS UNIQUE")
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
                    neo4j_query("CREATE CONSTRAINT ON (n:PresenceToken) ASSERT n.token IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Tablet) ASSERT n.id IS UNIQUE")
#                     neo4j_query("CREATE CONSTRAINT ON (n:PredefinedExternalUser) ASSERT n.email IS UNIQUE")
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
                    neo4j_query("CREATE INDEX ON :Booking(datum)")
                    neo4j_query("CREATE INDEX ON :Booking(confirmed)")
                    neo4j_query("CREATE INDEX ON :Booking(updated)")
                    neo4j_query("CREATE INDEX ON :Test(klasse)")
                    neo4j_query("CREATE INDEX ON :Test(fach)")
                    neo4j_query("CREATE INDEX ON :Test(datum)")
                end
                transaction do
                    main.class_variable_get(:@@user_info).keys.each do |email|
                        neo4j_query(<<~END_OF_QUERY, :email => email)
                            MERGE (u:User {email: {email}})
                        END_OF_QUERY
                    end
                end
                transaction do
                    main.class_variable_get(:@@tablets).keys.each do |id|
                        neo4j_query(<<~END_OF_QUERY, :id => id)
                            MERGE (u:Tablet {id: {id}})
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
                    neo4j_query(<<~END_OF_QUERY, :email => "tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: {email}})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "klassenraum@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: {email}})
                    END_OF_QUERY
                end
                transaction do
                    present_users = neo4j_query(<<~END_OF_QUERY).map { |x| x['u.email'] }
                        MATCH (u:User)
                        RETURN u.email;
                    END_OF_QUERY
                    wanted_users = Set.new(main.class_variable_get(:@@user_info).keys)
                    wanted_users << "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
                    wanted_users << "kurs.tablet@#{SCHUL_MAIL_DOMAIN}"
                    wanted_users << "tablet@#{SCHUL_MAIL_DOMAIN}"
                    wanted_users << "klassenraum@#{SCHUL_MAIL_DOMAIN}"
                    users_to_be_deleted = Set.new(present_users) - wanted_users
                    unless users_to_be_deleted.empty?
                        debug "Deleting users (not really):"
                        debug users_to_be_deleted.to_a.sort.to_yaml
                    end
                end
                transaction do
                    main.class_variable_get(:@@predefined_external_users)[:recipients].each_pair do |k, v|
                        next if v[:entries]
                        neo4j_query(<<~END_OF_QUERY, :email => k, :name => v[:label])
                            MERGE (n:PredefinedExternalUser {email: {email}, name: {name}})
                        END_OF_QUERY
                    end
                end
                # purge sessions which have not been used within the past 7 days
                purged_session_count = neo4j_query_expect_one(<<~END_OF_QUERY, {:today => (Date.today - 7).strftime('%Y-%m-%d')})['count']
                    MATCH (s:Session)-[:BELONGS_TO]->(u:User)
                    WHERE s.last_access IS NULL OR s.last_access < {today}
                    AND NOT ((u.email = 'lehrer.tablet@#{SCHUL_MAIL_DOMAIN}') OR (u.email = 'kurs.tablet@#{SCHUL_MAIL_DOMAIN}') OR (u.email = 'tablet@#{SCHUL_MAIL_DOMAIN}'))
                    DETACH DELETE s
                    RETURN COUNT(s) as count;
                END_OF_QUERY
                debug "Purged #{purged_session_count} stale sessions..."
                purged_login_code_count = neo4j_query_expect_one(<<~END_OF_QUERY, :now => Time.now.to_i)['count']
                    MATCH (l:LoginCode)
                    WHERE l.valid_to <= {now}
                    DETACH DELETE l
                    RETURN COUNT(l) as count;
                END_OF_QUERY
                debug "Purged #{purged_login_code_count} stale login codes..."
                debug "Setup finished."
                break
            rescue
                debug $!
                debug "Retrying setup after #{delay} seconds..."
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

    def self.gen_ventry_flags(ventry)
        ventry_flags = 0
        ventry_flags <<= 1
        ventry_flags += (ventry[:unr] != 0) ? 1 : 0
        ventry_flags <<= 1
        ventry_flags += (ventry[:fach_alt].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:fach_neu].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:lehrer_alt].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:lehrer_neu].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:klassen_alt].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:klassen_neu].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:raum_alt].nil?) ? 0 : 1
        ventry_flags <<= 1
        ventry_flags += (ventry[:raum_neu].nil?) ? 0 : 1
        ventry_flags
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
        @@tablets = {}
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
        @@tage_infos = []
        parser.parse_tage_infos do |t0, t1, title|
            @@tage_infos << {:from => t0, :to => t1, :title => title}
        end
        begin
            @@config = YAML::load_file('/data/config.yaml')
        rescue
            @@config = {
                :first_day => '2020-06-25',
                :first_school_day => '2020-08-10',
                :last_day => '2021-08-06'
            }
            debug "Can't read /data/config.yaml, using a few default values:"
            debug @@config.to_yaml
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
                :display_name_official => record[:display_name_official],
                :display_last_name => record[:display_last_name],
                :email => record[:email],
                :can_log_in => record[:can_log_in],
                :nc_login => record[:nc_login],
                :initial_nc_password => record[:initial_nc_password]
            }
            @@shorthands[record[:shorthand]] = record[:email]
            @@lehrer_order << record[:email]
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
                :display_name_official => record[:display_name_official],
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
        
        @@tablets_for_school_streaming = Set.new()
        @@tablets_which_are_lehrer_tablets = Set.new()
        parser.parse_tablets do |record|
            if @@tablets.include?(record[:id])
                raise "Ooops: already got this tablet called #{record[:id]}"
            end
            @@tablets[record[:id]] = record
            bg_color = TABLET_COLORS[record[:color]] || TABLET_DEFAULT_COLOR
            rgb = @@renderer.hex_to_rgb(bg_color).map { |x| x / 255.0 }
            gray = rgb[0] * 0.299 + rgb[1] * 0.587 + rgb[2] * 0.114
            @@tablets[record[:id]][:bg_color] = bg_color
            @@tablets[record[:id]][:fg_color] = gray < 0.5 ? '#ffffff' : '#000000'
            if record[:status].index('Klassenstreaming') == 0
                @@tablets[record[:id]][:klassen_stream] = record[:status].sub('Klassenstreaming', '').strip
            end
            if record[:school_streaming]
                @@tablets_for_school_streaming << record[:id]
            end
            if record[:lehrer_modus]
                @@tablets_which_are_lehrer_tablets << record[:id]
            end
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
        SV_USERS.each do |email|
            @@user_info[email][:sv] = true
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
        wahlpflicht_sus_for_lesson_key = parser.parse_wahlpflichtkurswahl(@@user_info.reject { |x, y| y[:teacher] }, @@lessons, lesson_key_tr)
        
        @@lessons_for_user = {}
        @@schueler_for_lesson = {}
        @@schueler_offset_in_lesson = {}
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
            unless user[:teacher]
                lessons.each do |lesson_key|
                    if wahlpflicht_sus_for_lesson_key.include?(lesson_key)
                        next unless wahlpflicht_sus_for_lesson_key[lesson_key].include?(email)
                    end
                    @@schueler_for_lesson[lesson_key] ||= []
                    @@schueler_for_lesson[lesson_key] << email
                    @@lessons_for_user[email] ||= Set.new()
                    @@lessons_for_user[email] << lesson_key
                end
            end
        end
        @@schueler_for_lesson.each_pair do |lesson_key, emails|
            @@schueler_offset_in_lesson[lesson_key] ||= {}
            emails.sort! do |a, b|
                @@user_info[a][:display_name] <=> @@user_info[b][:display_name]
            end
            emails.each.with_index do |email, i|
                @@schueler_offset_in_lesson[lesson_key][email] = i
            end
        end
        @@pausenaufsichten = parser.parse_pausenaufsichten()
        
        @@mailing_lists = {}
        @@klassen_order.each do |klasse|
            next unless @@schueler_for_klasse.include?(klasse)
            @@mailing_lists["klasse.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "SuS der Klasse #{klasse}",
                :recipients => @@schueler_for_klasse[klasse]
            }
            @@mailing_lists["eltern.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "Eltern der Klasse #{klasse}",
                :recipients => @@schueler_for_klasse[klasse].map do |email|
                    "eltern.#{email}"
                end
            }
            @@mailing_lists["lehrer.#{klasse}@#{SCHUL_MAIL_DOMAIN}"] = {
                :label => "Lehrer der Klasse #{klasse}",
                :recipients => ((@@teachers_for_klasse[klasse] || {}).keys.sort).map do |shorthand|
                    email = @@shorthands[shorthand]
                end.reject do |email|
                    email.nil?
                end
            }
        end
        @@mailing_lists["lehrer@#{SCHUL_MAIL_DOMAIN}"] = {
            :label => "Gesamtes Kollegium",
            :recipients => @@user_info.keys.select do |email|
                @@user_info[email][:teacher] && @@user_info[email][:can_log_in]
            end
        }
        @@mailing_lists["sus@#{SCHUL_MAIL_DOMAIN}"] = {
            :label => "Alle Schülerinnen und Schüler",
            :recipients => @@user_info.keys.select do |email|
                !@@user_info[email][:teacher]
            end
        }
        @@mailing_lists["eltern@#{SCHUL_MAIL_DOMAIN}"] = {
            :label => "Alle Eltern",
            :recipients => @@user_info.keys.select do |email|
                !@@user_info[email][:teacher]
            end.map do |email|
                "eltern.#{email}"
            end
        }
        if DEVELOPMENT
            VERTEILER_TEST_EMAILS.each do |email|
                @@mailing_lists[email] = {
                    :label => "Dev-Verteiler #{email}",
                    :recipients => VERTEILER_DEVELOPMENT_EMAILS
                }
            end
        end
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
        @@renderer = BackgroundRenderer.new
        self.collect_data() unless defined?(SKIP_COLLECT_DATA) && SKIP_COLLECT_DATA
        if ENV['DASHBOARD_SERVICE'] == 'ruby' && File.basename($0) == 'thin'
            @@compiled_files = {}
            setup = SetupDatabase.new()
            setup.setup(self)
            @@color_scheme_colors = COLOR_SCHEME_COLORS
            @@standard_color_scheme = STANDARD_COLOR_SCHEME
            @@color_scheme_colors.map! do |s|
                ['#' + s[0][1, 6], '#' + s[0][7, 6], '#' + s[0][13, 6], s[1], s[0][0], s[2]]
            end
            @@color_scheme_colors.each do |palette|
                @@renderer.render(palette)
            end
            self.compile_js()
            self.compile_css()
        end
        if ['thin', 'rackup'].include?(File.basename($0))
            debug('Server is up and running!')
        end
    end
    
    def assert(condition, message = 'assertion failed', suppress_backtrace = false)
        unless condition
            debug_error message
            e = StandardError.new(message)
            e.set_backtrace([]) if suppress_backtrace
            raise e
        end
    end

    def assert_with_delay(condition, message = 'assertion failed', suppress_backtrace = false)
        unless condition
            debug_error message
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
#         debug data_str
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
            debug "Request was:"
            debug data_str
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
#             debug "SID: [#{sid}]"
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
                            if email == "tablet@#{SCHUL_MAIL_DOMAIN}"
                                if @@tablets_which_are_lehrer_tablets.include?(session[:tablet_id])
                                    email = "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
                                else
                                    @session_user = {
                                        :email => email,
                                        :is_tablet => true,
                                        :tablet_type => :specific,
                                        :tablet_id => session[:tablet_id],
                                        :color_scheme => 'la2c6e80d60aea2c6e80',
                                        :can_see_all_timetables => false,
                                        :teacher => false,
                                        :id => @@klassen_id[@@tablets[session[:tablet_id]][:klassen_stream]]
                                    }
                                end
                            end
                            if email == "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}"
                                @session_user = {
                                    :email => email,
                                    :is_tablet => true,
                                    :tablet_id => session[:tablet_id],
                                    :tablet_type => :teacher,
                                    :color_scheme => 'lfcbf499e0001eeba30',
                                    :can_see_all_timetables => true,
                                    :teacher => true
                                }
                            elsif email == "kurs.tablet@#{SCHUL_MAIL_DOMAIN}"
                                @session_user = {
                                    :email => email,
                                    :is_tablet => true,
                                    :tablet_id => session[:tablet_id],
                                    :tablet_type => :kurs,
                                    :color_scheme => 'la86fd07638a15a2b7a',
                                    :can_see_all_timetables => false,
                                    :teacher => false,
                                    :shorthands => session[:shorthands] || []
                                }
                            elsif email == "klassenraum@#{SCHUL_MAIL_DOMAIN}"
                                @session_user = {
                                    :email => email,
                                    :is_tablet => true,
                                    :tablet_id => session[:tablet_id],
                                    :tablet_type => :klassenraum,
                                    :color_scheme => 'l7146749f6976cc8b79',
                                    :can_see_all_timetables => false,
                                    :teacher => false
                                }
                            elsif email != "tablet@#{SCHUL_MAIL_DOMAIN}"
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
    
    def nav_items(primary_color, now, new_messages_count)
        if tablet_logged_in?
            tablet_id = @session_user[:tablet_id]
            tablet = @@tablets[tablet_id] || {}
            tablet_id_span = "<span class='tablet-id-indicator' style='background-color: #{tablet[:bg_color]}; color: #{tablet[:fg_color]}'>#{tablet_id}</span>"
            if teacher_tablet_logged_in?
                return "<div style='margin-right: 15px;'><b>Lehrer-Tablet-Modus</b>#{tablet_id_span}</div>" 
            elsif kurs_tablet_logged_in?
                return "<div style='margin-right: 15px;'><b>Kurs-Tablet-Modus</b>#{tablet_id_span}</div>" 
            elsif klassenraum_logged_in?
                return "<div style='margin-right: 15px;'><b>Klassenraum-Modus</b>#{tablet_id_span}</div>" 
            elsif tablet_logged_in?
                description = ''
                if tablet[:klassen_stream]
                    description = " (Klassenstreaming #{tablet[:klassen_stream]})"
                end
                return "<div style='margin-right: 15px;'><b>Tablet-Modus</b>#{description}#{tablet_id_span}</div>" 
            end
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
                        temp = [tr_klasse(@session_user[:klasse])]
                        if @session_user[:group2]
                            temp << @session_user[:group2]
                        end
                        display_name += " (#{temp.join('/')})"
                    end
                    io.puts "<div class='icon nav_avatar'>#{user_icon(@session_user[:email], 'avatar-md')}</div><span class='menu-user-name'>#{display_name}</span>"
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
                    if teacher_or_sv_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                        if teacher_logged_in?
                            io.puts "<a class='dropdown-item nav-icon' href='/events'><div class='icon'><i class='fa fa-calendar-check-o'></i></div><span class='label'>Termine</span></a>"
                            io.puts "<a class='dropdown-item nav-icon' href='/tests'><div class='icon'><i class='fa fa-file-text-o'></i></div><span class='label'>Klassenarbeiten</span></a>"
                        end
                        io.puts "<a class='dropdown-item nav-icon' href='/polls'><div class='icon'><i class='fa fa-bar-chart'></i></div><span class='label'>Umfragen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/prepare_vote'><div class='icon'><i class='fa fa-group'></i></div><span class='label'>Abstimmungen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/mailing_lists'><div class='icon'><i class='fa fa-envelope'></i></div><span class='label'>E-Mail-Verteiler</span></a>"
                    end
                    if @session_user[:can_upload_vplan]
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_vplan'><div class='icon'><i class='fa fa-upload'></i></div><span class='label'>Vertretungsplan hochladen</span></a>"
                    end
                    if admin_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/admin'><div class='icon'><i class='fa fa-wrench'></i></div><span class='label'>Administration</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/show_all_login_codes'><div class='icon'><i class='fa fa-key-modern'></i></div><span class='label'>Live-Anmeldungen</span></a>"
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
        io.puts "<div class='input-group'><input type='text' class='form-control' readonly value='#{email}' /><div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' title='E-Mail-Adresse in die Zwischenablage kopieren' data-clipboard-text='#{email}'><i class='fa fa-clipboard'></i></button></div></div>"
    end
    
    def print_lehrerzimmer_panel()
        require_user!
        return '' unless teacher_logged_in?
        return '' if teacher_tablet_logged_in?
        StringIO.open do |io|
            io.puts "<div class='hint lehrerzimmer-panel'>"
            io.puts "<div style='padding-top: 7px;'>Momentan im Jitsi-Lehrerzimmer:&nbsp;"
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
    
    def print_timetable_chooser()
        if can_see_all_timetables_logged_in?
            StringIO.open do |io|
                io.puts "<div style='margin-bottom: 15px;'>"
                unless teacher_tablet_logged_in?
                    @@klassen_order.each do |klasse|
                        id = @@klassen_id[klasse]
                        io.puts "<a data-klasse='#{klasse}' data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
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
        elsif klassenraum_logged_in?
            StringIO.open do |io|
                io.puts "<div style='margin-bottom: 15px;'>"
                @@klassen_order.each do |klasse|
                    id = @@klassen_id[klasse]
                    io.puts "<a data-klasse='#{klasse}' data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
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
                    io.puts "<a data-klasse='#{klasse}' data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
                end
                id = @session_user[:id]
                io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable' + window.location.hash;\" class='btn btn-sm ttc'>#{@session_user[:shorthand]}</a>"
                io.puts "</div>"
                io.string
            end
        end
    end
    
    def print_test_klassen_chooser(active = nil)
        StringIO.open do |io|
            io.puts "<div style='margin-bottom: 15px;'>"
            klassen_for_session_user.each do |klasse|
                next if ['11', '12'].include?(klasse)
                io.puts "<a data-klasse='#{klasse}' class='btn btn-sm ttc #{klasse == active ? 'active': ''}'>#{tr_klasse(klasse)}</a>"
            end
            io.puts "</div>"
            io.string
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
        fixed_timetable_data = nil
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
            unless can_see_all_timetables_logged_in? || (@@teachers_for_klasse[klasse] || {}).include?(@session_user[:shorthand])
                redirect "#{WEB_ROOT}/", 302
            end
        elsif path == 'show_login_codes'
            redirect "#{WEB_ROOT}/", 302 unless @session_user
            parts = request.env['REQUEST_PATH'].split('/')
            klasse = parts[2]
#             STDERR.puts @@teachers_for_klasse[klasse].to_yaml
            unless can_see_all_timetables_logged_in? || (@@teachers_for_klasse[klasse] || {}).include?(@session_user[:shorthand])
                redirect "#{WEB_ROOT}/", 302
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
        elsif path == 'livestream'
            jwt = request.params['jwt']
            response.set_cookie('AuthToken', 
                                :value => jwt,
                                :domain => JWT_DOMAIN_STREAM,
                                :path => '/',
                                :httponly => true,
                                :secure => DEVELOPMENT ? false : true)
            redirect "#{STREAM_SITE_URL}?jwt=#{jwt}", 302
        elsif path == 'tests'
            parts = request.env['REQUEST_PATH'].split('/')
            klasse = (parts[2] || '').strip
            if klasse.empty?
                klasse = klassen_for_session_user.first
            end
        elsif path == 'index'
            if @session_user
                path = 'timetable' 
            else
                path = 'login'
            end
        end
        if path == 'timetable'
            redirect "#{WEB_ROOT}/", 302 unless @session_user
            if teacher_logged_in? || tablet_logged_in?
                parts = request.env['REQUEST_PATH'].split('/')
                timetable_id = parts[2]
                if tablet_logged_in?
                    tablet_id = @session_user[:tablet_id]
                    tablet_info = @@tablets[tablet_id] || {}
                    if tablet_info[:school_streaming]
                        today = DateTime.now.strftime('%Y-%m-%d')
                        results = neo4j_query(<<~END_OF_QUERY, {:tablet_id => tablet_id, :today => today})
                            MATCH (t:Tablet {id: {tablet_id}})<-[:WHICH]-(b:Booking {datum: {today}, confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
                            RETURN b, i, l
                        END_OF_QUERY
                        fixed_timetable_data = {:events => []}
                        results.each do |item|
                            booking = item['b'].props
                            lesson = item['l'].props
                            lesson_key = lesson[:key]
                            lesson_info = item['i'].props
                            lesson_data = @@lessons[:lesson_keys][lesson_key]
                            event = {
                                :lesson => true,
                                :lesson_key => lesson_key,
                                :lesson_offset => lesson_info[:offset],
                                :datum => booking[:datum],
                                :start => "#{booking[:datum]}T#{booking[:start_time]}",
                                :end => "#{booking[:datum]}T#{booking[:end_time]}",
                                :label => "<b>#{@@faecher[lesson_data[:fach]] || lesson_data[:fach]}</b> (#{lesson_data[:klassen].join(', ')})",
                                :data => {:lesson_jitsi => true}
                            }
                            fixed_timetable_data[:events] << event
                        end
                    end
                end
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
            unless teacher_or_sv_logged_in?
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
                            debug "Error while evaluating:"
                            debug code
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
end
