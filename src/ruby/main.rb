require 'base64'
require 'cgi'
require 'csv'
require 'curb'
require 'date'
require 'digest/sha1'
require 'faye/websocket'
require 'htmlentities'
require 'i18n'
require 'json'
require 'jwt'
require 'kramdown'
require 'mail'
require './neo4j.rb'
require 'net/http'
require 'net/imap'
require 'nextcloud'
require 'nokogiri'
require 'open3'
require 'prawn/qrcode'
require 'prawn/measurement_extensions'
require 'prawn-styled-text'
require 'pry'
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
require '/data/config.rb'
$VERBOSE = warn_level
DASHBOARD_SERVICE = ENV['DASHBOARD_SERVICE']

BIB_JWT_TTL = 60
BIB_JWT_TTL_EXTRA = 20

require './background-renderer.rb'
require './include/admin.rb'
require './include/bib_login.rb'
require './include/color.rb'
require './include/color-schemes.rb'
require './include/comment.rb'
require './include/cypher.rb'
require './include/directory.rb'
require './include/event.rb'
require './include/ext_user.rb'
require './include/file.rb'
require './include/gev.rb'
require './include/groups.rb'
require './include/hack.rb'
require './include/homework.rb'
require './include/ical.rb'
require './include/image.rb'
require './include/jitsi.rb'
require './include/lehrbuchverein.rb'
require './include/lesson.rb'
require './include/login.rb'
require './include/matrix.rb'
require './include/message.rb'
require './include/monitor.rb'
require './include/otp.rb'
require './include/poll.rb'
require './include/salzh.rb'
require './include/stats.rb'
require './include/tablet_set.rb'
require './include/tests.rb'
require './include/test_events.rb'
require './include/theme.rb'
require './include/user.rb'
require './include/vote.rb'
require './include/website.rb'
require './parser.rb'

Faye::WebSocket.load_adapter('thin')

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
    # STDERR.puts caller_locations.to_yaml
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

def fix_h_to_hh(s)
    return nil if s.nil?
    if s =~ /^\d:\d\d$/
        '0' + s
    else
        s
    end
end

USER_AGENT_PARSER = UserAgentParser::Parser.new
WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']
HOMEWORK_FEEDBACK_STATES = ['good', 'hmmm', 'lost']
HOMEWORK_FEEDBACK_EMOJIS = {'good' => '🙂',
                            'hmmm' => '🤔',
                            'lost' => '😕'}

HOURS_FOR_KLASSE = {}

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

def deliver_mail(plain_text = nil, &block)
    mail = Mail.new do
        charset = 'UTF-8'
        message = self.instance_eval(&block)
        if plain_text.nil?
            html_part do
                content_type 'text/html; charset=UTF-8'
                body message
            end

            text_part do
                content_type 'text/plain; charset=UTF-8'
                body mail_html_to_plain_text(message)
            end
        else
            text_part do
                content_type 'text/plain; charset=UTF-8'
                body plain_text
            end
        end
    end
    if DEVELOPMENT
        if DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST.include?(mail.to.first)
            debug "Sending mail to #{mail.to.join(' / ')} because first recipient is included in DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST..."
            mail.deliver!
        else
            debug "Not sending mail to because we're in development: #{mail.subject} => #{mail.to.join(' / ')}"
            debug mail.to_s
        end
    else
        mail.deliver!
    end
end

def parse_markdown(s)
    s ||= ''
    s.gsub!(/\w\*in/) { |x| x.sub('*', '\\*') }
    Kramdown::Document.new(s, :smart_quotes => %w{sbquo lsquo bdquo ldquo}).to_html.strip
end

def join_with_sep(list, a, b)
    list.size == 1 ? list.first : [list[0, list.size - 1].join(a), list.last].join(b)
end

class SetupDatabase
    include QtsNeo4j

    CONSTRAINTS_LIST = [
        'LoginCode/tag',
        'User/email',
        'Session/sid',
        'DeviceToken/token',
        'DeviceLoginToken/token',
        'Lesson/key',
        'WebsiteEvent/key',
        'TestEvent/key',
        'TextComment/key',
        'AudioComment/key',
        'Message/key',
        'NewsEntry/timestamp',
        'Event/key',
        'Poll/key',
        'PollRun/key',
        'PresenceToken/token',
        'Tablet/id',
        'TabletSet/id',
        'PublicEventPerson/tag',
        'MatrixAccessToken/access_token',
        'KnownEmailAddress/email',
        'SelfTestDay/datum'
    ]

    INDEX_LIST = [
        'LoginCode/code',
        'NextcloudLoginCode/code',
        'LessonInfo/offset',
        'TextComment/offset',
        'AudioComment/offset',
        'ExternalUser/entered_by',
        'ExternalUser/email',
        'PredefinedExternalUser/email',
        'News/date',
        'PollRun/start_date',
        'PollRun/end_date',
        'Booking/datum',
        'Booking/confirmed',
        'Booking/updated',
        'Test/klasse',
        'Test/fach',
        'Test/datum',
        'User/ev'
    ]

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
                        entry['nodes'].select do |node|
                            STDERR.puts node.to_yaml
                            node[:name] != (main.class_variable_get(:@@predefined_external_users)[:recipients][node[:email]] || {})[:label]
                        end.each do |node|
                            debug "DELETING PEU #{node[:name]}"
                            neo4j_query(<<~END_OF_QUERY, {:name => node[:name], :email => node[:email]})
                                MATCH (n:PredefinedExternalUser {name: $name, email: $email})
                                DETACH DELETE n;
                            END_OF_QUERY
                        end
                    end
                end
                wanted_constraints = Set.new()
                wanted_indexes = Set.new()
                STDERR.puts "Setting up constraints and indexes..."
                CONSTRAINTS_LIST.each do |constraint|
                    constraint_name = constraint.gsub('/', '_')
                    wanted_constraints << constraint_name
                    label = constraint.split('/').first
                    property = constraint.split('/').last
                    query = "CREATE CONSTRAINT #{constraint_name} IF NOT EXISTS FOR (n:#{label}) REQUIRE n.#{property} IS UNIQUE"
                    STDERR.puts query
                    neo4j_query(query)
                end
                INDEX_LIST.each do |index|
                    index_name = index.gsub('/', '_')
                    wanted_indexes << index_name
                    label = index.split('/').first
                    property = index.split('/').last
                    query = "CREATE INDEX #{index_name} IF NOT EXISTS FOR (n:#{label}) ON (n.#{property})"
                    STDERR.puts query
                    neo4j_query(query)
                end
                neo4j_query("SHOW ALL CONSTRAINTS").each do |row|
                    next if wanted_constraints.include?(row['name'])
                    query = "DROP CONSTRAINT #{row['name']}"
                    STDERR.puts query
                    neo4j_query(query)
                end
                neo4j_query("SHOW ALL INDEXES").each do |row|
                    next if wanted_indexes.include?(row['name']) || wanted_constraints.include?(row['name'])
                    query = "DROP INDEX #{row['name']}"
                    STDERR.puts query
                    neo4j_query(query)
                end
                transaction do
                    main.class_variable_get(:@@user_info).keys.each do |email|
                        neo4j_query(<<~END_OF_QUERY, :email => email)
                            MERGE (u:User {email: $email})
                        END_OF_QUERY
                    end
                end
                transaction do
                    main.class_variable_get(:@@tablets).keys.each do |id|
                        neo4j_query(<<~END_OF_QUERY, :id => id)
                            MERGE (u:Tablet {id: $id})
                        END_OF_QUERY
                    end
                end
                transaction do
                    # create tablet sets
                    main.class_variable_get(:@@tablet_sets).keys.each do |id|
                        neo4j_query(<<~END_OF_QUERY, :id => id)
                            MERGE (t:TabletSet {id: $id})
                        END_OF_QUERY
                    end
                    # remove tablet sets which are no more present,
                    # this automatically invalidates all tablet set bookings
                    neo4j_query(<<~END_OF_QUERY, :tablet_sets => main.class_variable_get(:@@tablet_sets).keys)
                        MATCH (t:TabletSet)
                        WHERE NOT (t.id IN $tablet_sets)
                        DETACH DELETE t;
                    END_OF_QUERY
                end
                transaction do
                    neo4j_query(<<~END_OF_QUERY, :email => "lehrer.tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "kurs.tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "tablet@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "klassenraum@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "monitor@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "monitor-sek@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
                    END_OF_QUERY
                    neo4j_query(<<~END_OF_QUERY, :email => "monitor-lz@#{SCHUL_MAIL_DOMAIN}")
                        MERGE (u:User {email: $email})
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
                    wanted_users << "monitor@#{SCHUL_MAIL_DOMAIN}"
                    wanted_users << "monitor-sek@#{SCHUL_MAIL_DOMAIN}"
                    wanted_users << "monitor-lz@#{SCHUL_MAIL_DOMAIN}"
                    users_to_be_deleted = Set.new(present_users) - wanted_users
                    unless users_to_be_deleted.empty?
                        debug "Deleting #{users_to_be_deleted.size} users (not really)"
                        # debug users_to_be_deleted.to_a.sort.to_yaml
                    end
                end
                transaction do
                    main.class_variable_get(:@@predefined_external_users)[:recipients].each_pair do |k, v|
                        next if v[:entries]
                        neo4j_query(<<~END_OF_QUERY, :email => k, :name => v[:label])
                            MERGE (n:PredefinedExternalUser {email: $email, name: $name})
                        END_OF_QUERY
                    end
                end
                # purge sessions which have not been used within the past 7 days
                purged_session_count = neo4j_query_expect_one(<<~END_OF_QUERY, {:today => (Date.today - 7).strftime('%Y-%m-%d')})['count']
                    MATCH (s:Session)-[:BELONGS_TO]->(u:User)
                    WHERE s.last_access IS NULL OR s.last_access < $today
                    AND NOT ((u.email = 'lehrer.tablet@#{SCHUL_MAIL_DOMAIN}') OR (u.email = 'kurs.tablet@#{SCHUL_MAIL_DOMAIN}') OR (u.email = 'tablet@#{SCHUL_MAIL_DOMAIN}'))
                    DETACH DELETE s
                    RETURN COUNT(s) as count;
                END_OF_QUERY
                debug "Purged #{purged_session_count} stale sessions..."
                purged_login_code_count = neo4j_query_expect_one(<<~END_OF_QUERY, :now => Time.now.to_i)['count']
                    MATCH (l:LoginCode)
                    WHERE l.valid_to <= $now
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
                yield ds, (day.wday + 6) % 7
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
        @@email_for_matrix_login = {}
        @@shorthands = {}
        @@shorthand_order = []
        @@schueler_for_klasse = {}
        @@faecher = {}
        @@ferien_feiertage = []
        @@tablets = {}
        @@tablet_sets = {}
        @@lehrer_order = []
        @@klassen_order = []
        @@current_email_addresses = []
        @@antikenfahrt_recipients = {}
        @@antikenfahrt_mailing_lists = {}
        @@birthday_entries = {}
        @@server_etag = RandomTag.generate(24)

        @@index_for_klasse = {}
        @@predefined_external_users = {}
        @@bib_summoned_books = {}
        @@bib_summoned_books_last_ts = 0

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
                :display_last_name_dativ => record[:display_last_name_dativ],
                :email => record[:email],
                :can_log_in => record[:can_log_in],
                :nc_login => record[:nc_login],
                :matrix_login => record[:matrix_login],
                :initial_nc_password => record[:initial_nc_password]
            }
            matrix_login = record[:matrix_login]
            raise "oops: duplicate matrix / nc login: #{matrix_login}" if @@email_for_matrix_login.include?(matrix_login)
            @@email_for_matrix_login[matrix_login] = record[:email]
            @@shorthands[record[:shorthand]] = record[:email]
            @@lehrer_order << record[:email]
        end
        @@klassenleiter = {}
        parser.parse_klassenleiter do |record|
            @@klassenleiter[record[:klasse]] = record[:klassenleiter]
        end
        @@shorthand_order = @@shorthands.keys.sort do |a, b|
            a.downcase <=> b.downcase
        end

        @@lehrer_order.sort!() do |a, b|
            la = @@user_info[a][:shorthand].downcase
            lb = @@user_info[b][:shorthand].downcase
            la = 'zzz' + la if la[0] == '_'
            lb = 'zzz' + lb if lb[0] == '_'
            la <=> lb
        end
        @@klassen_order = KLASSEN_ORDER
        @@klassen_index = {}
        KLASSEN_ORDER.each_with_index do |klasse, i|
            @@klassen_index[klasse] = i
        end
        @@klassen_order.each.with_index { |k, i| @@index_for_klasse[k] = i }
        @@klassen_id = {}
        @@klassen_order.each do |klasse|
            @@klassen_id[klasse] = Digest::SHA2.hexdigest(KLASSEN_ID_SALT + klasse).to_i(16).to_s(36)[0, 16]
        end

        self.fix_stundenzeiten()

        disable_jitsi_for_email = Set.new()
        if File.exists?('/data/schueler/disable-jitsi.txt')
            File.open('/data/schueler/disable-jitsi.txt') do |f|
                f.each_line do |line|
                    line.strip!
                    next if line.empty?
                    disable_jitsi_for_email << line
                end
            end
        end

        parser.parse_schueler do |record|
            matrix_login = "@#{record[:email].split('@').first.sub(/\.\d+$/, '')}:#{MATRIX_DOMAIN_SHORT}"
            unless KLASSEN_ORDER.include?(record[:klasse])
                raise "Klasse #{record[:klasse]} is included in KLASSEN_ORDER"
            end
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
                :matrix_login => matrix_login,
                :initial_nc_password => record[:initial_nc_password],
                :biber_password => Main.gen_password_for_email(record[:email] + 'biber')[0, 4].downcase,
                :jitsi_disabled => disable_jitsi_for_email.include?(record[:email]),
                :geburtstag => record[:geburtstag]
            }
            raise "oops: duplicate matrix / nc login: #{matrix_login}" if @@email_for_matrix_login.include?(matrix_login)
            @@email_for_matrix_login[matrix_login] = record[:email]
            @@schueler_for_klasse[record[:klasse]] ||= []
            @@schueler_for_klasse[record[:klasse]] << record[:email]
            birthday = record[:geburtstag]
            if birthday
                birthday_md = birthday[5, 5]
                @@birthday_entries[birthday_md] ||= []
                @@birthday_entries[birthday_md] << record[:email]
            end
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

        @@tablet_sets = parser.parse_tablet_sets || {}

        ADMIN_USERS.each do |email|
            @@user_info[email][:admin] = true
        end
        (CAN_SEE_ALL_TIMETABLES_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_see_all_timetables] = true
        end
        (CAN_MANAGE_SALZH_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_manage_salzh] = true
        end
        (CAN_UPLOAD_VPLAN_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_upload_vplan] = true
        end
        (CAN_UPLOAD_FILES_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_upload_files] = true
        end
        (CAN_MANAGE_NEWS_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_manage_news] = true
        end
        (CAN_MANAGE_MONITORS_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_manage_monitors] = true
        end
        (CAN_MANAGE_TABLETS_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_manage_tablets] = true
        end
        (CAN_MANAGE_ANTIKENFAHRT_USERS + ADMIN_USERS).each do |email|
            next unless @@user_info[email]
            @@user_info[email][:can_manage_antikenfahrt] = true
        end
        SV_USERS.each do |email|
            next unless @@user_info[email]
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

        lesson_key_tr = {}
        lesson_key_tr = self.fix_lesson_key_tr(lesson_key_tr)
        # if DASHBOARD_SERVICE == 'ruby'
        #     debug lesson_key_tr.to_yaml
        # end

        @@lessons, @@vertretungen, @@vplan_timestamp, @@day_messages, @@lesson_key_back_tr, @@original_lesson_key_for_lesson_key = parser.parse_timetable(@@config, lesson_key_tr)
        @@current_lesson_key_order = []
        @@current_lesson_key_info = {}
        if DASHBOARD_SERVICE == 'ruby'
            @@lessons[:lesson_keys].keys.sort do |a, b|
                afach = (a.split('_').first || '').downcase
                bfach = (b.split('_').first || '').downcase
                astufe = a.split('_')[1].to_i
                bstufe = b.split('_')[1].to_i
                afach == bfach ? ((astufe == bstufe) ? (a <=> b) : (astufe <=> bstufe)) : (afach <=> bfach)
            end.each do |lesson_key|
                lesson = @@lessons[:lesson_keys][lesson_key]
                stunden = Set.new()
                ((@@lessons[:timetables][@@lessons[:timetables].keys.sort.last][lesson_key] || {})[:stunden] || {}).each_pair do |dow, h|
                    h.each_pair do |stunde, info|
                        stunden << sprintf('%d/%02d', info[:tag], info[:stunde])
                    end
                end
                unless stunden.empty?
                    @@current_lesson_key_order << lesson_key
                    @@current_lesson_key_info[lesson_key] = {}
                    @@current_lesson_key_info[lesson_key][:stunden] = stunden.to_a.sort
                end
            end
        end

        # patch lesson_keys in @@lessons and @@vertretungen
        @@lessons, @@vertretungen = parser.parse_timetable(@@config, lesson_key_tr)
        # patch @@faecher
        @@lessons[:lesson_keys].each_pair do |lesson_key, info|
            # STDERR.puts "[#{lesson_key}]"
            unless @@faecher[lesson_key]
                x = lesson_key.split('_').first.split('-').first
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
            pretty_folder_name = "#{fach.gsub('/', '-')} (#{lesson_info[:klassen].sort.map { |x| tr_klasse(x) }.join(', ')})"
            lesson_info[:lehrer].each do |shorthand|
                pretty_folder_names_for_teacher[shorthand] ||= {}
                pretty_folder_names_for_teacher[shorthand][pretty_folder_name] ||= Set.new()
                pretty_folder_names_for_teacher[shorthand][pretty_folder_name] << lesson_key
            end
            @@lessons[:lesson_keys][lesson_key][:pretty_folder_name] = pretty_folder_name
        end
        # if we have 2x Chemie GK (11) for one teacher, differentiate with A and B
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
                a = @@lessons[:lesson_keys][_a] || {}
                b = @@lessons[:lesson_keys][_b] || {}
                (a[:fach] == b[:fach]) ?
                (((a[:klassen] || []).map { |x| @@klassen_order.index(x) || -1}.min || 0) <=> ((b[:klassen] || []).map { |x| @@klassen_order.index(x) || -1 }.min || 0)) :
                (a[:fach] <=> b[:fach])
            end
        end
        @@lessons[:lesson_keys].each_pair do |lesson_key, lesson|
            next if lesson_key[0, 8] == 'Testung_'
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
                next if lesson[:fach] == 'Testung'
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

        kurse_for_schueler, schueler_for_kurs = parser.parse_kurswahl(@@user_info.reject { |x, y| y[:teacher] }, @@lessons, lesson_key_tr, @@original_lesson_key_for_lesson_key)
        wahlpflicht_sus_for_lesson_key = parser.parse_wahlpflichtkurswahl(@@user_info.reject { |x, y| y[:teacher] }, @@lessons, lesson_key_tr, @@schueler_for_klasse)

        @@materialamt_for_lesson = {}
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY)
            MATCH (u:User)-[r:HAS_AMT {amt: 'material'}]->(l:Lesson)
            RETURN u.email, l.key;
        END_OF_QUERY
        rows.each do |row|
            @@materialamt_for_lesson[row['l.key']] ||= Set.new()
            @@materialamt_for_lesson[row['l.key']] << row['u.email']
        end

        @@lessons_for_user = {}
        @@schueler_for_lesson = {}
        @@schueler_offset_in_lesson = {}
        @@user_info.each_pair do |email, user|
            lessons = (user[:teacher] ? @@lessons_for_shorthand[user[:shorthand]] : @@lessons_for_klasse[user[:klasse]]).dup
            unless user[:teacher]
                if ['11', '12'].include?(user[:klasse])
                    lessons = (kurse_for_schueler[email] || Set.new()).to_a
                end
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

        @@schueler_for_teacher = {}
        @@lessons_for_shorthand.each_pair do |shorthand, lesson_keys|
            @@schueler_for_teacher[shorthand] ||= Set.new()
            lesson_keys.each do |lesson_key|
                (@@schueler_for_lesson[lesson_key] || []).each do |email|
                    @@schueler_for_teacher[shorthand] << email
                end
            end
        end

        @@pausenaufsichten = parser.parse_pausenaufsichten(@@config)

        @@mailing_lists = {}
        self.update_antikenfahrt_groups()
        self.update_mailing_lists()
        @@current_email_addresses = parser.parse_current_email_addresses()

        @@holiday_dates = Set.new()
        @@ferien_feiertage.each do |entry|
            temp0 = Date.parse(entry[:from])
            temp1 = Date.parse(entry[:to])
            while temp0 <= temp1
                @@holiday_dates << temp0.strftime('%Y-%m-%d')
                temp0 += 1
            end
        end

        @@room_ids = {}
        ROOM_ORDER.each do |room|
            @@room_ids[room] = Digest::SHA2.hexdigest(KLASSEN_ID_SALT + room).to_i(16).to_s(36)[0, 16]
        end
        @@rooms_for_shorthand = {}
        room_order_set = Set.new(ROOM_ORDER)
        undeclared_rooms = Set.new()
        timetable_today.each_pair do |lesson_key, info|
            info[:stunden].each_pair do |wday, day_info|
                day_info.each_pair do |stunde, lesson_info|
                    lesson_info[:lehrer].each do |shorthand|
                        (lesson_info[:raum] || '').split('/').each do |room|
                            unless (room || '').strip.empty?
                                if room_order_set.include?(room)
                                    @@rooms_for_shorthand[shorthand] ||= Set.new()
                                    @@rooms_for_shorthand[shorthand] << room
                                else
                                    undeclared_rooms << room
                                end
                            end
                        end
                    end
                end
            end
        end
        unless undeclared_rooms.empty?
            debug("Undeclared rooms: #{undeclared_rooms.to_a.sort.join(' ')}")
        end

        if ENV['DASHBOARD_SERVICE'] == 'ruby'
            FileUtils.rm_rf('/internal/debug/')
            FileUtils.mkpath('/internal/debug/')
            Main.class_variables.each do |x|
                File.open(File.join('/internal/debug', "#{x.to_s}.yaml"), 'w') do |f|
                    f.write Main.class_variable_get(x).to_yaml
                end
            end
            File::open('/internal/debug/emails.txt', 'w') do |f|
                @@user_info.keys.sort.each do |email|
                    f.puts "#{email}"
                end
            end
        end
    end

    def self.update_mailing_lists()
        self.update_antikenfahrt_groups()
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
            if klasse.to_i > 0
                if @@klassenleiter[klasse]
                    @@mailing_lists["team.#{klasse.to_i}@#{SCHUL_MAIL_DOMAIN}"] ||= {
                        :label => "Klassenleiterteam der Klassenstufe #{klasse.to_i}",
                        :recipients => []
                    }
                    @@klassenleiter[klasse].each do |shorthand|
                        if @@shorthands[shorthand]
                            @@mailing_lists["team.#{klasse.to_i}@#{SCHUL_MAIL_DOMAIN}"][:recipients] << @@shorthands[shorthand]
                        end
                    end
                end
            end
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
        temp = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| { :email => x['u.email'] } }
            MATCH (u:User {ev: true})
            RETURN u.email;
        END_OF_QUERY
        @@mailing_lists["ev@#{SCHUL_MAIL_DOMAIN}"] = {
            :label => "Alle Elternvertreter:innen",
            :recipients => temp.map { |x| 'eltern.' + x[:email] }
        }
        @@antikenfahrt_mailing_lists.each_pair do |k, v|
            @@mailing_lists[k] = v
        end
        if DEVELOPMENT
            VERTEILER_TEST_EMAILS.each do |email|
                @@mailing_lists[email] = {
                    :label => "Dev-Verteiler #{email}",
                    :recipients => VERTEILER_DEVELOPMENT_EMAILS
                }
            end
        end
        File.open('/internal/mailing_lists.yaml.tmp', 'w') do |f|
            f.puts @@mailing_lists.to_yaml
        end
        FileUtils::mv('/internal/mailing_lists.yaml.tmp', '/internal/mailing_lists.yaml', force: true)
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

    def self.refresh_bib_data()
        begin
            now = Time.now.to_i
            return if now - @@bib_summoned_books_last_ts < 60 * 60
            @@bib_summoned_books_last_ts = now
            @@bib_summoned_books = {}
            debug "Refreshing bib data..."
            url = "#{BIB_HOST}/api/get_summoned_books"
            res = Curl.get(url) do |http|
                payload = {:exp => Time.now.to_i + 60, :email => 'timetable'}
                http.headers['X-JWT'] = JWT.encode(payload, JWT_APPKEY_BIB, "HS256")
            end
            raise 'oops' if res.response_code != 200
            @@bib_summoned_books = JSON.parse(res.body)
            # debug @@bib_summoned_books.to_yaml
        rescue StandardError => e
            debug e
        end
    end

    def self.compile_js()
        files = [
            '/include/jquery/jquery-3.6.1.min.js',
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
            '/include/jszip/dist/jszip.min.js',
            '/include/flowbite/flowbite.js',
            '/code.js',
            '/include/zxing.min.js',
            '/barcode-widget.js',
            '/sound.js',
            '/include/howler.core.min.js',
            '/sortable-table.js',
            '/include/print.min.js',
            '/include/odometer.min.js',
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
            '/include/flowbite/flowbite.min.css',
            '/include/bootstrap/bootstrap.min.css',
            '/include/summernote/summernote-bs4.min.css',
            '/include/fork-awesome/fork-awesome.min.css',
            '/include/fullcalendar/main.min.css',
            '/include/bootstrap4-toggle/bootstrap4-toggle.min.css',
            '/include/dropzone/dropzone.min.css',
            '/include/chart.js/Chart.min.css',
            '/styles.css',
            '/cling.css',
            '/include/print.min.css',
            '/include/odometer-theme-default.css',
        ]

        self.compile_files(:css, 'text/css', files)
        FileUtils::rm_rf('/gen/css/')
        FileUtils::mkpath('/gen/css/')
        File.open("/gen/css/compiled-#{@@compiled_files[:css][:sha1]}.css", 'w') do |f|
            f.print(@@compiled_files[:css][:content])
        end
    end

    configure do
        setup = SetupDatabase.new()
        setup.wait_for_neo4j()
        @@renderer = BackgroundRenderer.new
        self.collect_data() unless defined?(SKIP_COLLECT_DATA) && SKIP_COLLECT_DATA
        @@ws_clients = {}
        @@color_scheme_info = {}
        if ENV['DASHBOARD_SERVICE'] == 'ruby' && (File.basename($0) == 'thin' || File.basename($0) == 'pry.rb')
            @@compiled_files = {}
            setup.setup(self)
            COLOR_SCHEME_COLORS.each do |entry|
                @@color_scheme_info[entry[0]] = [entry[1], entry[2]]
            end
            @@color_scheme_colors = COLOR_SCHEME_COLORS
            @@standard_color_scheme = STANDARD_COLOR_SCHEME
            @@color_scheme_colors.map! do |s|
                ['#' + s[0][1, 6], '#' + s[0][7, 6], '#' + s[0][13, 6], s[1], s[0][0], s[2]]
            end
            COLOR_SCHEME_COLORS.each do |palette|
                @@renderer.render(palette)
            end
            rows = $neo4j.neo4j_query(<<~END_OF_QUERY).map { |x| x['u.color_scheme'] }
                MATCH (u:User)
                WHERE u.color_scheme IS NOT NULL
                RETURN u.color_scheme;
            END_OF_QUERY
            missing_color_schemes = Set.new(rows.map { |x| x[1, 18]} )
            missing_color_schemes = missing_color_schemes.map do |x|
                ["##{x[0, 6]}", "##{x[6, 6]}", "##{x[12, 6]}"]
            end
            missing_color_schemes = missing_color_schemes.to_a.sort
            missing_color_schemes.each do |palette|
                @@renderer.render(palette)
            end

            begin
                http = Net::HTTP.new('image_bot', 8080)
                response = http.request(Net::HTTP::Get.new("/api/update_all"))
            rescue StandardError => e
                STDERR.puts e
            end

            self.refresh_bib_data()

            self.compile_js()
            self.compile_css()
            self.determine_lehrmittelverein_state_for_all()
            # STDERR.puts @@color_scheme_info.to_yaml
        end
        if ['thin', 'rackup'].include?(File.basename($0))
            debug('Server is up and running!')
        end
        if ENV['DASHBOARD_SERVICE'] == 'ruby' && File.basename($0) == 'pry.rb'
            binding.pry
        end
    end

    def assert(condition, message = 'assertion failed', suppress_backtrace = false, delay = nil)
        unless condition
            debug_error message
            e = StandardError.new(message)
            e.set_backtrace([]) if suppress_backtrace
            sleep delay unless delay.nil?
            raise e
        end
    end

    def assert_with_delay(condition, message = 'assertion failed', suppress_backtrace = false)
        assert(condition, message, suppress_backtrace, 3.0)
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
        if @session_user
            unless ['/api/send_message', '/api/update_message', '/api/submit_poll_run'].include?(request.path)
                begin
                    ip_short = request.ip.to_s.split('.').map { |x| sprintf('%02x', x.to_i) }.join('')
                    STDERR.puts sprintf("%s [%s] [%s] %s %s", DateTime.now.strftime('%Y-%m-%d %H:%M:%S'), ip_short, @session_user[:nc_login], request.path, data_str)
                rescue
                end
            end
        end
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
        if DEVELOPMENT && request.path[0, 5] != '/api/'
            self.class.compile_js()
            self.class.compile_css()
        end

        @latest_request_body = nil
        @latest_request_body_parsed = nil

        self.class.refresh_bib_data()

        @session_device = nil
        @session_device_token = nil
        if request.cookies.include?('device_token')
            token = request.cookies['device_token']
            if (token.is_a? String) && (token =~ /^[0-9A-Za-z,]+$/)
                results = neo4j_query(<<~END_OF_QUERY, :token => token, :today => Date.today.to_s).to_a
                    MATCH (s:DeviceToken {token: $token})
                    SET s.last_access = $today
                    RETURN s;
                END_OF_QUERY
                if results.size == 1
                    @session_device = results.first['s'][:device]
                    @session_device_token = token
                end
            end
        end

        # before any API request, determine currently logged in user via the provided session ID
        @session_user = nil
        if request.cookies.include?('sid')
            sid = request.cookies['sid']
#             debug "SID: [#{sid}]"
            if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
                first_sid = sid.split(',').first
                if first_sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => first_sid, :today => Date.today.to_s).to_a
                        MATCH (s:Session {sid: $sid})-[:BELONGS_TO]->(u:User)
                        SET u.last_access = $today
                        SET s.last_access = $today
                        RETURN s, u;
                    END_OF_QUERY
                    if results.size == 1
                        begin
                            session = results.first['s']
                            if session[:tied_to_device_token]
                                assert(session[:tied_to_device_token] == @session_device_token)
                            end
                            session_expiry = session[:expires]
                            if DateTime.parse(session_expiry) > DateTime.now
                                email = results.first['u'][:email]
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
                                elsif email == "monitor@#{SCHUL_MAIL_DOMAIN}"
                                    @session_user = {
                                        :email => email,
                                        :is_monitor => true,
                                        :teacher => false
                                    }
                                elsif email == "monitor-sek@#{SCHUL_MAIL_DOMAIN}"
                                    @session_user = {
                                        :email => email,
                                        :is_monitor => true,
                                        :teacher => false
                                    }
                                elsif email == "monitor-lz@#{SCHUL_MAIL_DOMAIN}"
                                    @session_user = {
                                        :email => email,
                                        :is_monitor => true,
                                        :teacher => false
                                    }
                                elsif email != "tablet@#{SCHUL_MAIL_DOMAIN}"
                                    @session_user = @@user_info[email].dup
                                    if @session_user
                                        @session_user[:font] = results.first['u'][:font]
                                        @session_user[:color_scheme] = results.first['u'][:color_scheme]
                                        @session_user[:ical_token] = results.first['u'][:ical_token]
                                        @session_user[:otp_token] = results.first['u'][:otp_token]
                                        @session_user[:homeschooling] = results.first['u'][:homeschooling]
                                        @session_user[:group2] = results.first['u'][:group2] || 'A'
                                        @session_user[:group_af] = results.first['u'][:group_af] || ''
                                        @session_user[:sus_may_contact_me] = results.first['u'][:sus_may_contact_me] || false
                                        @session_user[:user_agent] = results.first['s'][:user_agent]
                                    end
                                end
                            end
                        rescue
                            # something went wrong, delete the session
                            results = neo4j_query(<<~END_OF_QUERY, :sid => first_sid).to_a
                                MATCH (s:Session {sid: $sid})
                                DETACH DELETE s;
                            END_OF_QUERY
                        end
                    end
                end
            end
        end
    end

    after '*' do
        cleanup_neo4j()
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
        respond(:html => parse_markdown(data[:markdown]))
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

    # returns 0 if before Dec 1
    # returns 1 .. 24 if in range
    # returns 24 if Dec 25 .. 31
    def advents_calendar_date_today()
        date = DateTime.now.to_s[0, 10]
        # if DEVELOPMENT
            # date = '2021-12-24'
        # end
        return 0 if date < '2021-12-01'
        return 0 if date > '2021-12-31'
        day = date[8, 2].to_i
        day = 24 if day > 24
        return day
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
                if @session_user[:tablet_type] == :bib_mobile
                    return ""
                else
                    return "<div style='margin-right: 15px;'><b>Tablet-Modus</b>#{description}#{tablet_id_span}</div>"
                end
            end
        end
        if monitor_logged_in?
            return ''
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
                # if user_who_can_upload_files_logged_in? || user_who_can_manage_news_logged_in?
                #     nav_items << :website
                # end
                # if user_who_can_manage_monitors_logged_in?
                #     nav_items << :monitor
                # end
                nav_items << :messages
                if admin_logged_in? || user_who_can_upload_files_logged_in? || user_who_can_manage_news_logged_in? || user_who_can_manage_monitors_logged_in? || user_who_can_manage_tablets_logged_in?
                    nav_items << :admin
                end
                # nav_items << :advent_calendar #if advents_calendar_date_today > 0
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
            if external_user_logged_in?
                nav_items = []
                if can_manage_bib_payment_logged_in?
                    nav_items << ['/', 'Lehrmittelverein', 'fa fa-book']
                    nav_items << :profile
                end
            end
            return nil if nav_items.empty?
            io.puts "<button class='navbar-toggler' type='button' data-toggle='collapse' data-target='#navbarTogglerDemo02' aria-controls='navbarTogglerDemo02' aria-expanded='false' aria-label='Toggle navigation'>"
            io.puts "<span class='navbar-toggler-icon'></span>"
            io.puts "</button>"
            io.puts "<div class='collapse navbar-collapse my-0 flex-grow-0' id='navbarTogglerDemo02'>"
            io.puts "<ul class='navbar-nav mr-auto'>"
            nav_items.each do |x|
                if x == :admin
                    io.puts "<li class='nav-item dropdown'>"
                    io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                    io.puts "<div class='icon'><i class='fa fa-wrench'></i></div>Administration"
                    io.puts "</a>"
                    io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown'>"
                    printed_something = false
                    if user_who_can_manage_news_logged_in?
                        io.puts "<a class='dropdown-item nav-icon' href='/manage_news'><div class='icon'><i class='fa fa-newspaper-o'></i></div><span class='label'>News verwalten</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/manage_calendar'><div class='icon'><i class='fa fa-calendar'></i></div><span class='label'>Termine verwalten</span></a>"
                        # io.puts "<a class='dropdown-item nav-icon' href='/anmeldungen'><div class='icon'><i class='fa fa-group'></i></div><span class='label'>Anmeldungen einsehen</span></a>"
                        printed_something = true
                    end
                    if user_who_can_upload_files_logged_in?
                        io.puts "<div class='dropdown-divider'></div>" if printed_something
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_images'><div class='icon'><i class='fa fa-photo'></i></div><span class='label'>Bilder hochladen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/upload_files'><div class='icon'><i class='fa fa-file-pdf-o'></i></div><span class='label'>Dateien hochladen</span></a>"
                        printed_something = true
                    end
                    if user_who_can_manage_monitors_logged_in?
                        io.puts "<div class='dropdown-divider'></div>" if printed_something
                        io.puts "<a class='dropdown-item nav-icon' href='/manage_monitor'><div class='icon'><i class='fa fa-tv'></i></div><span class='label'>Monitore verwalten</span></a>"
                        printed_something = true
                    end
                    if admin_logged_in?
                        io.puts "<div class='dropdown-divider'></div>" if printed_something
                        io.puts "<a class='dropdown-item nav-icon' href='/admin'><div class='icon'><i class='fa fa-wrench'></i></div><span class='label'>Administration</span></a>"
                    end
                    if user_who_can_manage_tablets_logged_in?
                        io.puts "<a class='dropdown-item nav-icon' href='/bookings'><div class='icon'><i class='fa fa-tablet'></i></div><span class='label'>Tablets</span></a>"
                    end
                    if admin_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/show_all_login_codes'><div class='icon'><i class='fa fa-key-modern'></i></div><span class='label'>Live-Anmeldungen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/email_accounts'><div class='icon'><i class='fa fa-envelope'></i></div><span class='label'>E-Mail-Postfächer</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/stats'><div class='icon'><i class='fa fa-bar-chart'></i></div><span class='label'>Statistiken</span></a>"
                        printed_something = true
                    end
                    io.puts "</div>"
                    io.puts "</li>"
                elsif x == :advent_calendar
                    unless admin_logged_in?
                        io.puts "<li class='nav-item text-nowrap'>"
                        io.puts "<a class='bu-launch-adventskalender nav-link nav-icon'><div class='icon'><i class='fa fa-snowflake-o'></i></div>Adventskalender</a>"
                        io.puts "</li>"
                    end
                elsif x == :profile
                    io.puts "<li class='nav-item dropdown'>"
                    io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                    display_name = htmlentities(@session_user[:display_name])
                    if @session_user[:klasse]
                        temp = [tr_klasse(@session_user[:klasse])]
                        # if @session_user[:group2]
                        #     temp << @session_user[:group2]
                        # end
                        display_name += " (#{temp.join('/')})"
                    end
                    io.puts "<div class='icon nav_avatar'>#{user_icon(@session_user[:email], 'avatar-md')}</div><span class='menu-user-name'>#{display_name}</span>"
                    io.puts "</a>"
                    io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown'>"
                    unless external_user_logged_in?
                        io.puts "<a class='dropdown-item nav-icon' href='/profil'><div class='icon'>#{user_icon(@session_user[:email], 'avatar-sm')}</div><span class='label'>Profil</span></a>"
                    end
                    sessions = all_sessions()
                    if sessions.size > 1
                        unless external_user_logged_in?
                            io.puts "<div class='dropdown-divider'></div>"
                        end
                        sessions[1, sessions.size - 1].each.with_index do |entry, _|
                            display_name = htmlentities(entry[:user][:display_name])
                            if entry[:user][:klasse]
                                display_name += " (#{tr_klasse(entry[:user][:klasse])})"
                            end
                            io.puts "<a class='dropdown-item nav-icon switch-session' data-sidindex='#{_ + 1}' href='#'><div class='icon'>#{user_icon(entry[:user][:email], 'avatar-sm')}</div><span class='label'>#{display_name}</span></a>"
                        end
                    end
                    io.puts "<a class='dropdown-item nav-icon' href='/login'><div class='icon'><i class='fa fa-sign-in'></i></div><span class='label'>Zusätzliche Anmeldung…</span></a>"
                    unless external_user_logged_in?
                        io.puts "<a class='dropdown-item nav-icon' href='/login_nc'><div class='icon'><i class='fa fa-nextcloud'></i></div><span class='label'>In Nextcloud anmelden…</span></a>"
                        # if can_manage_agr_app_logged_in? || can_manage_bib_members_logged_in? || can_manage_bib_logged_in? || teacher_logged_in?
                            io.puts "<div class='dropdown-divider'></div>"
                            if gev_logged_in?
                                io.puts "<a class='dropdown-item nav-icon' href='/gev'><div class='icon'><i class='fa fa-users'></i></div><span class='label'>Gesamtelternvertretung</span></a>"
                            end
                            if can_manage_agr_app_logged_in?
                                io.puts "<a class='dropdown-item nav-icon' href='/agr_app'><div class='icon'><i class='fa fa-mobile'></i></div><span class='label'>Altgriechisch-App</span></a>"
                            end
                            if can_manage_bib_members_logged_in?
                                io.puts "<a class='dropdown-item nav-icon' href='/lehrbuchverein'><div class='icon'><i class='fa fa-book'></i></div><span class='label'>Lehrmittelverein</span></a>"
                            end
                            # if can_manage_bib_logged_in? || teacher_logged_in?
                                io.puts "<a class='dropdown-item nav-icon' href='/bibliothek'><div class='icon'><i class='fa fa-book'></i></div><span class='label'>Bibliothek</span></a>"
                            # end
                        # end
                        if teacher_or_sv_logged_in?
                            io.puts "<div class='dropdown-divider'></div>"
                            if teacher_or_sv_logged_in?
                                if teacher_logged_in?
                                    if can_manage_salzh_logged_in?
                                        io.puts "<a class='dropdown-item nav-icon' href='/salzh'><div class='icon'><i class='fa fa-home'></i></div><span class='label'>Testungen</span></a>"
                                    end
                                    io.puts "<a class='dropdown-item nav-icon' href='/events'><div class='icon'><i class='fa fa-calendar-check-o'></i></div><span class='label'>Termine</span></a>"
                                    io.puts "<a class='dropdown-item nav-icon' href='/tests'><div class='icon'><i class='fa fa-file-text-o'></i></div><span class='label'>Klassenarbeiten</span></a>"
                                end
                                io.puts "<a class='dropdown-item nav-icon' href='/polls'><div class='icon'><i class='fa fa-bar-chart'></i></div><span class='label'>Umfragen</span></a>"
                                io.puts "<a class='dropdown-item nav-icon' href='/prepare_vote'><div class='icon'><i class='fa fa-hand-paper-o'></i></div><span class='label'>Abstimmungen</span></a>"
                                io.puts "<a class='dropdown-item nav-icon' href='/mailing_lists'><div class='icon'><i class='fa fa-envelope'></i></div><span class='label'>E-Mail-Verteiler</span></a>"
                                io.puts "<a class='dropdown-item nav-icon' href='/groups'><div class='icon'><i class='fa fa-group'></i></div><span class='label'>Gruppen</span></a>"
                            end
                        end
                        # if @session_user[:can_upload_vplan]
                        #     io.puts "<div class='dropdown-divider'></div>"
                        #     io.puts "<a class='dropdown-item nav-icon' href='/upload_vplan_html'><div class='icon'><i class='fa fa-upload'></i></div><span class='label'>Vertretungsplan hochladen</span></a>"
                        # end
                        io.puts "<div class='dropdown-divider'></div>"
                        # if true
                        #     io.puts "<a class='dropdown-item nav-icon' href='/h4ck'><div class='icon'><i class='fa fa-rocket'></i></div><span class='label'>Dashboard Hackers</span></a>"
                        # end
                        # if admin_logged_in?
                        #     io.puts "<a class='bu-launch-adventskalender dropdown-item nav-icon'><div class='icon'><i class='fa fa-snowflake-o'></i></div><span class='label'>Adventskalender</span></a>"
                        # end
                    end
                    io.puts "<a class='dropdown-item nav-icon' href='/hilfe'><div class='icon'><i class='fa fa-question-circle'></i></div><span class='label'>Hilfe</span></a>"
                    io.puts "<div class='dropdown-divider'></div>"
                    io.puts "<a class='dropdown-item nav-icon' href='#' onclick='perform_logout();'><div class='icon'><i class='fa fa-sign-out'></i></div><span class='label'>Abmelden</span></a>"
                    io.puts "</div>"
                    io.puts "</li>"
                elsif x == :kurse
                    unless (@@lessons_for_shorthand[@session_user[:shorthand]] || []).empty? && (@@lessons[:historic_lessons_for_shorthand][@session_user[:shorthand]] || []).empty?
                        io.puts "<li class='nav-item dropdown'>"
                        io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                        io.puts "<div class='icon'><i class='fa fa-address-book'></i></div>Kurse"
                        io.puts "</a>"
                        io.puts "<div class='dropdown-menu' aria-labelledby='navbarDropdown'>"
                        taken_lesson_keys = Set.new()
                        (@@lessons_for_shorthand[@session_user[:shorthand]] || []).each do |lesson_key|
                            lesson_info = @@lessons[:lesson_keys][lesson_key]
                            if lesson_info
                                fach = lesson_info[:fach]
                                fach = @@faecher[fach] if @@faecher[fach]
                                io.puts "<a class='dropdown-item nav-icon' href='/lessons/#{CGI.escape(lesson_key)}'><div class='icon'><i class='fa fa-address-book'></i></div><span class='label'>#{lesson_info[:pretty_folder_name]}</span></a>"
                                taken_lesson_keys << lesson_key
                            end
                        end
                        remaining_lesson_keys = ((@@lessons[:historic_lessons_for_shorthand][@session_user[:shorthand]] || Set.new()) - taken_lesson_keys)
                        unless remaining_lesson_keys.empty?
                            lesson_keys_with_data = neo4j_query(<<~END_OF_QUERY, {:lesson_keys => remaining_lesson_keys}).map { |x| x['l.key'] }
                                MATCH (l:Lesson)
                                WHERE l.key IN $lesson_keys
                                RETURN l.key;
                            END_OF_QUERY
                            remaining_lesson_keys &= Set.new(lesson_keys_with_data)
                            unless remaining_lesson_keys.empty?
                                io.puts "<div class='dropdown-divider'></div>"
                                remaining_lesson_keys.to_a.sort.each do |lesson_key|
                                    lesson_info = @@lessons[:lesson_keys][lesson_key]
                                    if lesson_info
                                        fach = lesson_info[:fach]
                                        fach = @@faecher[fach] if @@faecher[fach]
                                        io.puts "<a class='dropdown-item nav-icon' href='/lessons/#{CGI.escape(lesson_key)}'><div class='icon'><i class='fa fa-address-book'></i></div><span class='label'>#{fach} (#{lesson_info[:klassen].map { |x| tr_klasse(x) }.join(', ')})</span></a>"
                                    end
                                end
                            end
                        end
                        io.puts "</div>"
                        io.puts "</li>"
                    end
                elsif x == :directory
                    klassen = @@klassen_for_shorthand[@session_user[:shorthand]] || []
                    if user_who_can_manage_antikenfahrt_logged_in?
                        klassen << '11'
                        klassen << '12'
                        klassen.uniq!
                    end
                    unless klassen.empty?
                        io.puts "<li class='nav-item dropdown'>"
                        io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                        io.puts "<div class='icon'><i class='fa fa-address-book'></i></div>Klassen"
                        io.puts "</a>"
                        io.puts "<div class='dropdown-menu' aria-labelledby='navbarDropdown'>"
                        if can_see_all_timetables_logged_in?
                            klassen = @@klassen_order
                        end
                        klassen.each do |klasse|
                            io.puts "<a class='dropdown-item nav-icon' href='/directory/#{klasse}'><div class='icon'><i class='fa fa-address-book'></i></div><span class='label'>Klasse #{tr_klasse(klasse)}</span></a>"
                        end
                        io.puts "</div>"
                        io.puts "</li>"
                    end
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
        io.puts "<div class='input-group'><input type='text' class='form-control' readonly value='#{email}' style='min-width: 100px;' /><div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' title='Eintrag in die Zwischenablage kopieren' data-clipboard-text='#{email}'><i class='fa fa-clipboard'></i></button></div></div>"
    end

    def print_password_field(io, password)
        io.puts "<div class='input-group'><input type='password' class='form-control' readonly value='#{password}' style='min-width: 50px;' /><div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' title='Eintrag in die Zwischenablage kopieren' data-clipboard-text='#{password}'><i class='fa fa-clipboard'></i></button></div></div>"
    end

    def print_lehrerzimmer_panel()
        require_user!
        return '' unless teacher_logged_in?
        return '' if teacher_tablet_logged_in?
        StringIO.open do |io|
            io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
            io.puts "<div class='hint lehrerzimmer-panel'>"
            io.puts "<div class='hide-sm'>"
            io.puts "<div style='padding-top: 7px;'>Momentan im Jitsi-Lehrerzimmer:&nbsp;"
            rooms = current_jitsi_rooms()
            nobody_here = true
            users = []
            if rooms
                rooms.each do |room|
                    if room['roomName'] == 'lehrerzimmer'
                        room['participants'].sort do |a, b|
                            a['displayName'].downcase.sub('herr', '').sub('frau', '').sub('dr.', '').strip <=> b['displayName'].downcase.sub('herr', '').sub('frau', '').sub('dr.', '').strip
                        end.each do |participant|
                            email = participant['email']
                            users << email
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
            io.puts "</div>"
            io.puts "<div class='hide-non-sm'>"
            users.each do |email|
                if @@user_info[email] && @@user_info[email][:teacher]
#                     io.puts "<span class='btn btn-xs ttc'>#{@@user_info[email][:shorthand]}</span>"
                    io.puts "<div style='margin-right: 5px; display: inline-block; position: relative; top: 5px; background-image: url(#{NEXTCLOUD_URL}/index.php/avatar/#{@@user_info[email][:nc_login]}/128), url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mO88h8AAq0B1REmZuEAAAAASUVORK5CYII=);' class='avatar-md'></div>"
                end
            end
            io.puts "</div>"
            io.puts "<a href='/jitsi/Lehrerzimmer' target='_blank' style='white-space: nowrap;' class='float-right btn btn-success'><i class='fa fa-microphone'></i>&nbsp;&nbsp;Lehrerzimmer&nbsp;<i class='fa fa-angle-double-right'></i></a>"
            io.puts "<div style='clear: both;'></div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    def print_timetable_chooser()
        # if can_see_all_timetables_logged_in?
        #     StringIO.open do |io|
        #         io.puts "<div style='margin-bottom: 15px;'>"
        #         unless teacher_tablet_logged_in?
        #             @@klassen_order.each do |klasse|
        #                 id = @@klassen_id[klasse]
        #                 io.puts "<a data-klasse='#{klasse}' data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{tr_klasse(klasse)}</a>"
        #             end
        #             io.puts '<hr />'
        #         end
        #         @@lehrer_order.each do |email|
        #             id = @@user_info[email][:id]
        #             next unless @@user_info[email][:can_log_in]
        #             io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{@@user_info[email][:shorthand]}</a>"
        #         end
        #         io.puts '<hr />'
        #         ROOM_ORDER.each do |room|
        #             id = room
        #             # next unless @@user_info[email][:can_log_in]
        #             io.puts "<a data-id='#{id}' onclick=\"window.location.href = '/timetable/#{id}' + window.location.hash;\" class='btn btn-sm ttc'>#{room}</a>"
        #         end
        #         io.puts "</div>"
        #         io.string
        #     end
        if kurs_tablet_logged_in?
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
                hidden_something = false
                temp = StringIO.open do |tio|
                    @@lehrer_order.each do |email|
                        next if teacher_tablet_logged_in? && @@user_info[email][:shorthand][0] == '_'
                        id = @@user_info[email][:id]
                        next unless @@user_info[email][:can_log_in]
                        next unless can_see_all_timetables_logged_in? || email == @session_user[:email]
                        hide = (email != @session_user[:email])
                        hide = false if teacher_tablet_logged_in?
                        hidden_something = true if hide
                        style = hide ? 'display: none;' : ''
                        tio.puts "<a data-id='#{id}' onclick=\"load_timetable('#{id}'); window.selected_shorthand = '#{@@user_info[email][:shorthand]}'; \" class='btn btn-sm ttc ttc-teacher' style='#{style}'>#{@@user_info[email][:shorthand]}</a>"
                    end
                    tio.string
                end
                if hidden_something
                    io.puts "<button class='btn btn-xs ttc bu-show-alle-teacher pull-right' style='margin-left: 0.5em; width: unset; padding: 0.25rem 0.5rem; display: inline-block;' onclick=\"$('.ttc-teacher').show(); $('.bu-show-alle-teacher').hide();\">Alle Lehrkräfte</button>"
                end
                io.puts temp
                unless teacher_tablet_logged_in?
                    io.puts '<hr />'

                    hidden_something = false
                    all_hidden = @@klassen_order.all? do |klasse|
                        !((@@klassen_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(klasse))
                    end
                    temp = StringIO.open do |tio|
                        @@klassen_order.each do |klasse|
                            hide = !((@@klassen_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(klasse))
                            hide = false if all_hidden
                            hidden_something = true if hide
                            style = hide ? 'display: none;' : ''
                            id = @@klassen_id[klasse]
                            tio.puts "<a data-klasse='#{klasse}' data-id='#{id}' onclick=\"load_timetable('#{id}');\" class='btn btn-sm ttc ttc-klasse' style='#{style}'>#{tr_klasse(klasse)}</a>"
                        end
                        tio.string
                    end
                    if hidden_something
                        io.puts "<button class='btn btn-xs ttc bu-show-alle-klassen pull-right' style='margin-left: 0.5em; width: unset; padding: 0.25rem 0.5rem; display: inline-block;' onclick=\"$('.ttc-klasse').show(); $('.bu-show-alle-klassen').hide();\">Alle Klassen</button>"
                    end
                    io.puts temp

                    io.puts '<hr />'

                    hidden_something = false
                    all_hidden = ROOM_ORDER.all? do |room|
                        !((@@rooms_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(room))
                    end
                    temp = StringIO.open do |tio|
                        ROOM_ORDER.each do |room|
                            hide = !((@@rooms_for_shorthand[@session_user[:shorthand]] || Set.new()).include?(room))
                            hide = false if all_hidden
                            hidden_something = true if hide
                            style = hide ? 'display: none;' : ''
                            id = @@room_ids[room]
                            tio.puts "<a data-id='#{id}' onclick=\"load_timetable('#{id}');\" class='btn btn-sm ttc ttc-room' style='#{style}'>#{room}</a>"
                        end
                        tio.string
                    end
                    if hidden_something
                        io.puts "<button class='btn btn-xs ttc bu-show-alle-rooms pull-right' style='margin-left: 0.5em; width: unset; padding: 0.25rem 0.5rem; display: inline-block;' onclick=\"$('.ttc-room').show(); $('.bu-show-alle-rooms').hide();\">Alle Räume</button>"
                    end
                    io.puts temp
                end


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
            if user_who_can_manage_news_logged_in?
                io.puts "<hr />"
                io.puts "<a href='/manage_test_calendar' style='width: 9em;' class='btn btn-sm ttc'>Kalender verwalten</a>"
            end
            io.puts "</div>"
            io.string
        end
    end

    def print_semi_public_links()
        require_user!
        # return '' unless teacher_logged_in?
        return '' if teacher_tablet_logged_in?
        StringIO.open do |io|
            io.puts "<h2 style='margin-bottom: 30px; margin-top: 30px;'>Schulinterne Links</h2>"
            io.puts "<div class='table-responsive' style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-condensed table-striped narrow' style='width: unset; min-width: 100%;'>"
            io.puts "<tr><th>Website</th><th>Name</th><th>Passwort</th></tr>"
            SEMI_PUBLIC_LINKS.each do |link|
                next unless link[:condition].call(self)
                io.puts "<tr>"
                io.puts "<td><a href='#{link[:url]}' target='_blank'>#{link[:title]}</a></td>"
                io.puts "<td>"
                print_email_field(io, link[:user])
                io.puts "</td>"
                io.puts "<td>"
                print_password_field(io, link[:password])
                io.puts "</td>"
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"
            io.puts "<hr />"
            io.string
        end
    end

    def may_edit_lessons?(lesson_key)
        teacher_logged_in? && (@@lessons_for_shorthand[@session_user[:shorthand]].include?(lesson_key) || (@@lessons[:historic_lessons_for_shorthand][@session_user[:shorthand]].include?(lesson_key)))
    end

    get '/nc_auth' do
        @auth ||=  Rack::Auth::Basic::Request.new(request.env)
        if @auth.provided? && @auth.basic? && @auth.credentials
            begin
                password = @auth.credentials[1]
                assert(!(NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL.nil?))
                assert(password == NEXTCLOUD_ALL_ACCESS_PASSWORD_BE_CAREFUL, "Caught failed NextCloud login for user [#{@auth.credentials[0]}]")
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

    def pick_random_color_scheme()
        @@default_color_scheme ||= {}
        jd = (Date.today + 1).jd
        return @@default_color_scheme[jd] if @@default_color_scheme[jd]
        srand(DEVELOPMENT ? (Time.now.to_f * 1000).to_i : jd)
        which = nil
        style = nil
        while true do
            which = @@color_scheme_colors.sample
            style = [0].sample
            break unless which[4] == 'd' || which[1] == '#ff0040'
        end
        color_scheme = "#{which[4]}#{which[0, 3].join('').gsub('#', '')}#{style}"
        @@default_color_scheme[jd] = color_scheme unless DEVELOPMENT
        return color_scheme
    end

    def get_open_doors_for_user()
        require_user!
        doors = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email])['doors']
            MATCH (u:User {email: $email})
            RETURN COALESCE(u.advent_calendar_doors, 0) AS doors;
        END_OF_QUERY
        doors
    end

    def advent_calendar_images
        return [] unless File.exists?('advent-calendar-images.txt')
        File.read('advent-calendar-images.txt').split(/\s+/).map { |x| x.strip }.reject { |x| x.empty? }.map do |x|
            unless File.exists?("/gen/ac-#{x}.png")
                system("wget -O /gen/ac-#{x}-dl.png https://pixel.hackschule.de/raw/uploads/#{x}.png")
                system("convert /gen/ac-#{x}-dl.png -scale 1600% /gen/ac-#{x}.png")
            end
            "/gen/ac-#{x}.png"
        end
    end

    def print_advent_calendar_css
        return '' unless user_logged_in?
        permutation = [18,2,7,5,8,23,21,15,10,14,11,20,4,9,17,0,19,3,1,12,6,22,16,13]
        xo = [1,2,3,4,0.5,1.5,2.5,3.5,4.5,0,1,2,3,4,5,0.5,1.5,2.5,3.5,4.5,1,2,3,4]
        yo = [0,0,0,0,1,1,1,1,1,2,2,2,2,2,2,3,3,3,3,3,4,4,4,4]
        images = advent_calendar_images
        StringIO.open do |io|
            (0..23).each do |k|
                i = permutation[k]
                image = images[i]
                image = nil if i > advents_calendar_date_today() - 1
                io.puts ".door.door#{i} {"
                io.puts "    left: #{xo[k] * 17.5 + 0.5}vh;"
                io.puts "    top: #{yo[k] * 17.5 + 0.1}vh;"
                io.puts "    width: 17.5vh;"
                io.puts "    height: 17.5vh;"
                io.puts "}"
                io.puts ".door.door#{i} .flip-card-front {"
                io.puts "    background-image: url(/images/advent-calendar/doors/tiles-#{i}.png);"
                io.puts "    background-size: cover;"
                io.puts "}"
                io.puts ".door.door#{i} .flip-card-back {"
                io.puts "    background-image: url(#{images[i]});"
                io.puts "    background-size: cover;"
                io.puts "}"
            end
            io.puts "@media (orientation: portrait) {"
                (0..23).each do |k|
                    i = permutation[k]
                    io.puts ".door.door#{i} {"
                    io.puts "    left: #{yo[k] * 18.277 + 0.1044}vw;"
                    io.puts "    top: #{xo[k] * 18.277 + 0.5222}vw;"
                    io.puts "    width: 18.277vw;"
                    io.puts "    height: 18.277vw;"
                    io.puts "}"
                end
            io.puts "}"
            io.string
        end
    end

    def print_advent_calendar_doors
        return '' unless user_logged_in?
        doors = get_open_doors_for_user()
        StringIO.open do |io|
            (0..23).each do |i|
                io.puts "<div data-door='#{i}' class='door door#{i} #{((doors >> i) & 1) > 0 ? 'open' : ''}'>"
                io.puts "<div class='flip-card-inner'>"
                io.puts "<div class='flip-card-front'></div>"
                io.puts "<div class='flip-card-back'></div>"
                io.puts "</div>"
                io.puts "</div>"
            end
            io.string
        end
    end

    def print_current_monitor_advent_calendar_images()
        images = advent_calendar_images
        today = advents_calendar_date_today()
        StringIO.open do |io|
            d = advents_calendar_date_today() - 4
            d = 0 if d < 0
            d = 19 if d > 19
            (0..4).each do |x|
                i = d + x
                url = "/images/advent-calendar/doors/tiles-#{i}.png"
                if i <= today - 1
                    url = images[i]
                end
                io.puts "<img src='#{url}' />"
            end
            io.string
        end
    end

    post '/api/toggle_door' do
        require_user!
        data = parse_request_data(:required_keys => [:door], :types => {:door => Integer})
        door = data[:door]
        assert(door >= 0 && door <= 23)
        assert(door <= advents_calendar_date_today - 1)
        # TODO: only open doors that we may open
        doors = get_open_doors_for_user()
        doors ^= (1 << door)
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :doors => doors)
            MATCH (u:User {email: $email})
            SET u.advent_calendar_doors = $doors;
        END_OF_QUERY
        respond(:ok => 'yay')
    end

    def print_adventskalender_sidepanel()
        require_user!
        StringIO.open do |io|
            io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
            io.puts "<div class='hint'>"
            io.puts "<div>Adventskalender</div>"
            io.puts "<hr />"
            io.puts "<button style='white-space: nowrap;' class='float-right btn btn-success bu-launch-adventskalender'>Adventskalender öffnen&nbsp;<i class='fa fa-angle-double-right'></i></button>"
            io.puts "<div style='clear: both;'></div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/get_agr_jwt_token' do
        require_user_who_can_manage_agr_app!
        data = parse_request_data(:required_keys => [:url, :payload], :max_body_length => 0x10000000)
        payload = {
            # :context => JSON.parse(data[:payload]),
            :data_sha1 => Digest::SHA1.hexdigest(data[:payload]),
            :url => data[:url],
            :email => @session_user[:email],
            :display_name => @session_user[:display_name],
            :exp => Time.now.to_i + 60
        }
        token = JWT.encode payload, JWT_APPKEY_AGRAPP, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        respond(:token => token)
    end

    post '/api/get_bib_jwt_token' do
        # require_user_who_can_manage_bib!
        debug "Creating bib token for #{@session_user[:email]}"
        payload = {
            :email => @session_user[:email],
            :display_name => @session_user[:display_name],
            :can_manage_bib => can_manage_bib_logged_in?,
            :can_manage_bib_special_access => can_manage_bib_special_access_logged_in?,
            :teacher => teacher_logged_in?,
            :exp => Time.now.to_i + BIB_JWT_TTL + BIB_JWT_TTL_EXTRA
        }
        token = JWT.encode payload, JWT_APPKEY_BIB, algorithm = 'HS256', header_fields = {:typ => 'JWT'}
        respond(:token => token, :ttl => BIB_JWT_TTL)
    end

    get '/api/get_bib_dump_etag' do
        jwt = request.env["HTTP_X_JWT"]
        decoded_token = JWT.decode(jwt, JWT_APPKEY_BIB, true, { :algorithm => "HS256" }).first
        diff = decoded_token["exp"] - Time.now.to_i
        assert(diff >= 0)
        respond(:etag => @@server_etag)
    end

    get '/api/get_bib_dump' do
        jwt = request.env["HTTP_X_JWT"]
        decoded_token = JWT.decode(jwt, JWT_APPKEY_BIB, true, { :algorithm => "HS256" }).first
        diff = decoded_token["exp"] - Time.now.to_i
        assert(diff >= 0)
        respond(:user_info => @@user_info, :etag => @@server_etag, :lessons => @@lessons)
    end

    get '/api/get_hackschule_users' do
        require_admin!
        # > Klasse 7a
        # + specht@gymnasiumsteglitz.de
        # w Alessandria Klonaris <alessandria.klonaris@mail.gymnasiumsteglitz.de>
        response = StringIO.open do |io|
            @@lessons[:lesson_keys].keys.sort.each do |lesson_key|
                lesson_info = @@lessons[:lesson_keys][lesson_key]
                if (lesson_key.downcase[0, 2] == 'in' || lesson_key.downcase[0, 3] == 'itg') && @@schueler_for_lesson[lesson_key]
                    io.puts "> #{lesson_info[:pretty_folder_name]}"
                    lesson_info[:lehrer].each do |shorthand|
                        io.puts "+ #{@@shorthands[shorthand]}"
                    end
                    @@schueler_for_lesson[lesson_key].each do |email|
                        user = @@user_info[email]
                        io.puts "#{user[:geschlecht]} #{user[:first_name]} <#{email}>"
                    end
                    io.puts
                end
            end
            io.string
        end
        respond_raw_with_mimetype(response, 'text/plain')
    end

    before "/monitor/#{MONITOR_DEEP_LINK}" do
        unless MONITOR_DEEP_LINK.nil?
            @session_user = {
                :email => "monitor@#{SCHUL_MAIL_DOMAIN}",
                :is_monitor => true,
                :teacher => false
            }
        end
    end

    before "/monitor/#{MONITOR_LZ_DEEP_LINK}" do
        unless MONITOR_LZ_DEEP_LINK.nil?
            @session_user = {
                :email => "monitor-lz@#{SCHUL_MAIL_DOMAIN}",
                :is_monitor => true,
                :teacher => false
            }
        end
    end

    get '/p/:tag' do
        redirect "#{WEB_ROOT}/bib_postpone/#{params[:tag]}", 302
    end

    get '/*' do
        # first things first
        # days_left = (Date.parse('2022-07-07') - Date.today).to_i
        # response.headers['X-Tage-Bis-Zu-Den-Sommerferien'] = "#{days_left}"
        d4ys_left = (Date.parse('2022-12-24') - Date.today).to_i
        response.headers['X-Tage-Bis-Weihnachten'] = "#{d4ys_left}"

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
        # if DEVELOPMENT
        #     initial_date = Date.parse('2021-08-30')
        # end
        while [6, 0].include?(initial_date.wday)
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
        stored_groups = []
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
            lesson_data = Main.get_lesson_data(show_lesson_key)
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
        elsif path == 'salzh_protokoll' || path == 'self_tests'
            parts = request.env['REQUEST_PATH'].split('/')
            salzh_protocol_delta = (parts[2] || '').strip
        elsif path == 'index'
            if @session_user
                if @session_device
                    if @session_device == 'bib-mobile'
                        redirect "#{WEB_ROOT}/bib_scan", 302
                        return
                    end
                    redirect "#{WEB_ROOT}/bib_browse", 302
                    return
                else
                    if external_user_logged_in?
                        path = ''
                        if can_manage_bib_payment_logged_in?
                            path = 'lehrbuchverein'
                        end
                    else
                        path = 'timetable'
                    end
                end
            else
                if @session_device
                    path = 'bib_login'
                else
                    path = 'login'
                end
            end
        end
        if user_logged_in? && @session_user[:is_monitor]
            path = 'monitor'
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
                            MATCH (t:Tablet {id: $tablet_id})<-[:WHICH]-(b:Booking {datum: $today, confirmed: true})-[:FOR]->(i:LessonInfo)-[:BELONGS_TO]->(l:Lesson)
                            RETURN b, i, l
                        END_OF_QUERY
                        fixed_timetable_data = {:events => []}
                        results.each do |item|
                            booking = item['b']
                            lesson = item['l']
                            lesson_key = lesson[:key]
                            lesson_info = item['i']
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
                    MATCH (c)-[ruc:TO]->(:User {email: $email})
                    WHERE (c:TextComment OR c:AudioComment OR c:Message)
                    SET ruc.seen = true
                END_OF_QUERY
                sent_messages = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['m'], :recipient => x['r.email']} }
                    MATCH (m:Message)-[:FROM]->(u:User {email: $email})
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
                stored_events = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['e'], :recipient => x['u.email']} }
                    MATCH (e:Event)-[:ORGANIZED_BY]->(ou:User {email: $email})
                    WHERE COALESCE(e.deleted, false) = false
                    WITH e
                    OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(e)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    RETURN e, u.email
                    ORDER BY e.date DESC, e.start_time DESC, e.id;
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
                stored_events = temp_order.map do |x|
                    e = temp[x]
                    e[:info][:start_time] = fix_h_to_hh(e[:info][:start_time])
                    e[:info][:end_time] = fix_h_to_hh(e[:info][:end_time])
                    e
                end
            end
        elsif path == 'groups'
            unless teacher_or_sv_logged_in?
                redirect "#{WEB_ROOT}/", 302
            else
                stored_groups = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['g'], :recipient => x['u.email']} }
                    MATCH (g:Group)-[:DEFINED_BY]->(ou:User {email: $email})
                    WHERE COALESCE(g.deleted, false) = false
                    WITH g
                    OPTIONAL MATCH (u)-[r:IS_PART_OF]->(g)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    RETURN g, u.email
                    ORDER BY g.created DESC, g.id;
                END_OF_QUERY
                external_users_for_session_user = external_users_for_session_user()
                temp = {}
                temp_order = []
                stored_groups.each do |x|
                    unless temp[x[:info][:id]]
                        temp[x[:info][:id]] = {
                            :recipients => [],
                            :gid => x[:info][:id],
                            :info => x[:info]
                        }
                        temp_order << x[:info][:id]
                    end
                    temp[x[:info][:id]][:recipients] << x[:recipient]
                end
                stored_groups = temp_order.map do |x|
                    e = temp[x]
                    e
                end
            end
        elsif path == 'polls'
            unless teacher_or_sv_logged_in?
                redirect "#{WEB_ROOT}/", 302
            else
                stored_polls = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['p'], :recipient => x['u.email']} }
                    MATCH (p:Poll)-[:ORGANIZED_BY]->(ou:User {email: $email})
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

                # Two part query, step one: first, fetch all polls and poll runs, but without the participants
                # (otherwise we'll get lots of redundancy and traffic galore)
                stored_poll_runs = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email]).map { |x| {:info => x['pr'], :pid => x['pid'], :response_count => x['response_count']} }
                    MATCH (pr:PollRun)-[:RUNS]->(p:Poll)-[:ORGANIZED_BY]->(ou:User {email: $email})
                    WHERE COALESCE(pr.deleted, false) = false
                    AND COALESCE(p.deleted, false) = false
                    WITH pr, p
                    OPTIONAL MATCH (pu)<-[:RESPONSE_BY]-(prs:PollResponse)-[:RESPONSE_TO]->(pr)
                    WHERE (pu:User OR pu:ExternalUser OR pu:PredefinedExternalUser)
                    RETURN pr, p.id AS pid, COUNT(prs) as response_count
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
                end

                # Step 2: now fetch participants for every poll run
                participants = neo4j_query(<<~END_OF_QUERY, :poll_run_ids => temp_order).map { |x| {:prid => x['prid'], :user_email => x['user_email']} }
                    MATCH (pr:PollRun)
                    WHERE pr.id IN $poll_run_ids
                    WITH pr
                    OPTIONAL MATCH (u)-[r:IS_PARTICIPANT]->(pr)
                    WHERE (u:User OR u:ExternalUser OR u:PredefinedExternalUser) AND COALESCE(r.deleted, false) = false
                    RETURN pr.id AS prid, u.email AS user_email;
                END_OF_QUERY
                participants.each do |row|
                    temp[row[:prid]][:recipients] << row[:user_email]
                end

                stored_poll_runs = temp_order.map { |x| temp[x] }
            end
        elsif path == 'login_nc'
            unless @session_user
                redirect "#{WEB_ROOT}/", 302
            end
        end

        if external_user_logged_in?
            unless ['lehrbuchverein', 'login', 'hilfe'].include?(path)
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
        font_family = 'Alegreya' if path == 'monitor'
        font_family = 'Alegreya' if %w(bib-mobile bib-station bib-station-with-printer).include?(@session_device)
        color_scheme = (@session_user || {})[:color_scheme]
        font_family = 'Alegreya' unless AVAILABLE_FONTS.include?(font_family)
        unless color_scheme =~ /^[ld][0-9a-f]{18}[0-9]?$/
            unless user_logged_in?
                color_scheme = pick_random_color_scheme()
            else
                color_scheme = @@standard_color_scheme
            end
        end
        if color_scheme.size < 20
            color_scheme += '0'
        end
        if path == 'monitor'
            color_scheme = pick_random_color_scheme()
        end
        rendered_something = @@renderer.render(["##{color_scheme[1, 6]}", "##{color_scheme[7, 6]}", "##{color_scheme[13, 6]}"], (@session_user || {})[:email])
        trigger_update_images() if rendered_something
        color_palette = color_palette_for_color_scheme(color_scheme)

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
                            debug "Error while evaluating for #{(@session_user || {})[:email]}:"
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
