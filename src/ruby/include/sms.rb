class String
    def obfuscate(key)
        k = Digest::SHA256.digest(key).unpack('C*')
        m = self.bytes
        (0...m.size).each { |i| m[i] ^= k[i % 32] }
        Base64::strict_encode64(m.pack('C*'))
    end

    def deobfuscate(key)
        k = Digest::SHA256.digest(key).bytes
        m = Base64::strict_decode64(self).unpack('C*')
        (0...m.size).each { |i| m[i] ^= k[i % 32] }
        m.pack('C*')
    end
end

# The gateway is pinged on the websocket; one that doesn't answer for a while
# (e.g. its internet connection is gone, while the server still sees an open
# connection) no longer counts as ready, so codes go by email instead.
SMS_GATEWAY_PING_INTERVAL = 20 unless defined?(SMS_GATEWAY_PING_INTERVAL)
SMS_GATEWAY_STALE_AFTER = 60 unless defined?(SMS_GATEWAY_STALE_AFTER)

class Main < Sinatra::Base

    def user_is_eligible_for_sms?
        return false unless user_logged_in?
        return teacher_logged_in? || user_with_role_logged_in?(:praktikum)
    end

    # an authenticated gateway that answered recently
    def self.sms_gateway
        now = Time.now.to_f
        (@@ws_clients[:authenticated_sms] || {}).values.select do |client|
            now - client[:last_seen] < SMS_GATEWAY_STALE_AFTER
        end.max_by { |client| client[:last_seen] }
    end

    def self.sms_gateway_ready?
        !sms_gateway.nil?
    end

    def session_user_telephone_number
        require_user!
        telephone_number = @session_user[:telephone_number]
        return nil if telephone_number.nil?
        return '(redacted)'
    end

    def session_user_telephone_number_good_for_tresor()
        require_user!
        telephone_number = @session_user[:telephone_number]
        return false if telephone_number.nil?
        return @session_user[:telephone_number_changed] < DateTime.now.strftime('%Y-%m-%d')
    end

    # what an SMS was for (SmsSend.purpose, shown on /sms_anmeldung)
    SMS_PURPOSES = {
        'login' => 'Anmeldung',
        'login_2fa' => '2. Faktor',
        'tresor' => 'Tresor',
        'confirm_number' => 'Nummer bestätigen',
        'conference' => 'Zeugniskonferenz',
    }
    # how long the SMS log per person is kept
    SMS_LOG_KEEP_DAYS = 180

    # email: the person the SMS is for; purpose: a key of SMS_PURPOSES.
    # Per person, only when and why is recorded – no number, no text.
    def send_sms(telephone_number, message, email:, purpose:)
        assert(SMS_PURPOSES.include?(purpose))
        data = {:telephone_number => telephone_number, :message => message}
        # no number and no text in the log – the text usually is a login code
        debug "Sending SMS (#{message.size} characters)"
        gateway = Main.sms_gateway
        raise 'SMS gateway not available' if gateway.nil?
        gateway[:ws].send(data.to_json)
        ds = Date.today.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, {:ds => ds})
            MERGE (d:SmsDay {ds: $ds})
            SET d.count = COALESCE(d.count, 0) + 1;
        END_OF_QUERY
        begin
            neo4j_query(<<~END_OF_QUERY, {:email => email, :purpose => purpose, :ts => Time.now.to_i})
                MATCH (u:User {email: $email})
                CREATE (s:SmsSend {ts: $ts, purpose: $purpose})-[:BELONGS_TO]->(u);
            END_OF_QUERY
            sms_log_cleanup()
        rescue StandardError => e
            # the SMS is out – the statistics must not break the login
            STDERR.puts "Unable to record SMS: #{e.class}"
        end
    end

    def sms_log_cleanup
        neo4j_query(<<~END_OF_QUERY, {:ts => Time.now.to_i - SMS_LOG_KEEP_DAYS * 24 * 60 * 60})
            MATCH (s:SmsSend) WHERE s.ts < $ts
            DETACH DELETE s;
        END_OF_QUERY
    end

    # /sms_anmeldung: who still uses SMS codes, to move them to OTP. People
    # without OTP first – they are the ones to talk to.
    def print_sms_usage
        require_admin!
        now = Time.now.to_i
        day = 24 * 60 * 60
        people = {}
        person = lambda { |email| people[email] ||= {:email => email, :phone => false, :otp => false, :prefers_sms => false, :sends => [], :sessions => 0} }
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User) WHERE u.telephone_number IS NOT NULL
            RETURN u.email AS email, u.otp_token IS NOT NULL AS otp, u.preferred_login_method AS preferred;
        END_OF_QUERY
            x = person.call(row['email'])
            x[:phone] = true
            x[:otp] = row['otp']
            x[:prefers_sms] = row['preferred'] == 'sms'
        end
        neo4j_query(<<~END_OF_QUERY, {:ts => now - 90 * day}).each do |row|
            MATCH (s:SmsSend)-[:BELONGS_TO]->(u:User) WHERE s.ts >= $ts
            RETURN u.email AS email, u.otp_token IS NOT NULL AS otp, s.ts AS ts, s.purpose AS purpose;
        END_OF_QUERY
            x = person.call(row['email'])
            x[:otp] = row['otp']
            x[:sends] << [row['ts'], row['purpose']]
        end
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (s:Session)-[:BELONGS_TO]->(u:User) WHERE s.method = 'sms'
            RETURN u.email AS email, count(s) AS sessions;
        END_OF_QUERY
            person.call(row['email'])[:sessions] = row['sessions'] if people[row['email']]
        end
        recorded_since = neo4j_query("MATCH (s:SmsSend) RETURN min(s.ts) AS ts").first['ts']
        totals = {}
        [30, 90].each do |days|
            totals[days] = neo4j_query(<<~END_OF_QUERY, {:ds => (Date.today - days + 1).strftime('%Y-%m-%d')}).first['n'] || 0
                MATCH (d:SmsDay) WHERE d.ds >= $ds RETURN sum(d.count) AS n;
            END_OF_QUERY
        end
        name_for = lambda do |email|
            info = @@user_info[email]
            info ? [info[:display_name], info[:shorthand]] : [email, nil]
        end
        rows = people.values.sort_by do |x|
            [x[:otp] ? 1 : 0, -x[:sends].size, name_for.call(x[:email])[0].to_s.downcase]
        end
        without_otp = people.values.select { |x| x[:phone] && !x[:otp] }

        StringIO.open do |io|
            io.puts "<h3>SMS-Anmeldung</h3>"
            io.puts "<div class='sms-usage-summary'>"
            io.puts "<div><span class='sms-usage-label'>SMS-Gateway</span><span id='sms_gateway_status'>#{Main.sms_gateway_ready? ? '<i class=\'fa fa-check text-success\'></i>&nbsp;online' : '<i class=\'fa fa-times text-danger\'></i>&nbsp;offline – Codes gehen per E-Mail'}</span></div>"
            io.puts "<div><span class='sms-usage-label'>Gesendet</span><span>#{totals[30]} SMS in 30 Tagen, #{totals[90]} in 90 Tagen</span></div>"
            io.puts "<div><span class='sms-usage-label'>Telefonnummer</span><span id='sms_usage_counts'>#{people.values.count { |x| x[:phone] }} Personen, davon <strong>#{without_otp.size} ohne OTP</strong></span></div>"
            since = recorded_since ? "seit #{Time.at(recorded_since).strftime('%d.%m.%Y')}" : 'ab der nächsten SMS'
            io.puts "<div><span class='sms-usage-label'>Pro Person</span><span>aufgezeichnet #{since}: wann und wofür, ohne Nummer und Text; nach #{SMS_LOG_KEEP_DAYS} Tagen gelöscht</span></div>"
            io.puts "</div>"
            unless without_otp.empty?
                addresses = without_otp.map { |x| x[:email] }.sort.join(', ')
                io.puts "<p><button class='btn btn-sm btn-outline-secondary' id='bu_copy_sms_addresses' data-addresses='#{CGI.escapeHTML(addresses)}'><i class='fa fa-clipboard'></i>&nbsp;&nbsp;Adressen ohne OTP kopieren</button></p>"
            end
            io.puts "<div style='max-width: 100%; overflow-x: auto;'>"
            io.puts "<table class='table table-sm narrow sms-usage-table'>"
            io.puts "<tr><th>Name</th><th>OTP</th><th>Anmeldung per SMS</th><th class='text-right'>SMS 30&nbsp;Tage</th><th class='text-right'>SMS 90&nbsp;Tage</th><th>Zuletzt</th><th>Wofür (90 Tage)</th></tr>"
            rows.each do |x|
                name, shorthand = name_for.call(x[:email])
                recent = x[:sends].count { |ts, _| ts >= now - 30 * day }
                last = x[:sends].map(&:first).max
                purposes = x[:sends].group_by(&:last).map { |purpose, list| [list.size, SMS_PURPOSES[purpose] || purpose] }.sort_by { |n, label| [-n, label] }
                login = []
                login << 'bevorzugt' if x[:prefers_sms]
                login << "#{x[:sessions]}&nbsp;#{x[:sessions] == 1 ? 'Sitzung' : 'Sitzungen'}" if x[:sessions] > 0
                login << '<span class=\'text-muted\'>Nummer gelöscht</span>' unless x[:phone]
                io.puts "<tr class='sms-usage-row' data-email='#{CGI.escapeHTML(x[:email])}' data-sms30='#{recent}' data-sms90='#{x[:sends].size}'>"
                io.puts "<td>#{CGI.escapeHTML(name.to_s)}#{shorthand ? " <span class='text-muted'>(#{CGI.escapeHTML(shorthand)})</span>" : ''}</td>"
                io.puts "<td class='sms-usage-otp'>#{x[:otp] ? '<i class=\'fa fa-check text-success\'></i>&nbsp;ja' : '<strong>nein</strong>'}</td>"
                io.puts "<td>#{login.empty? ? '&ndash;' : login.join(', ')}</td>"
                io.puts "<td class='text-right'>#{recent}</td>"
                io.puts "<td class='text-right'>#{x[:sends].size}</td>"
                io.puts "<td>#{last ? Time.at(last).strftime('%d.%m.%Y') : '&ndash;'}</td>"
                io.puts "<td class='sms-usage-purposes'>#{purposes.map { |n, label| "#{n}×&nbsp;#{CGI.escapeHTML(label)}" }.join(', ')}</td>"
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "</div>"
            io.puts "<p class='text-muted'>„Sitzungen“: noch aktive Anmeldungen, die mit einem SMS-Code begonnen haben (auch aus der Zeit vor der Aufzeichnung). Den zweiten Faktor bei der Anmeldung von Lehrkräften zählen nur die SMS-Spalten.</p>"
            io.string
        end
    end

    post '/api/save_telephone_number' do
        require_user!
        data = parse_request_data(:required_keys => [:telephone_number])
        telephone_number = data[:telephone_number].strip
        if telephone_number[0, 2] == '00'
            telephone_number = '+' + telephone_number[2, telephone_number.size - 2]
        end
        number = TelephoneNumber.parse(telephone_number, :de)
        raise 'oopsie daisy' unless number.valid?
        number = number.e164_number()
        tag = RandomTag::generate(8)
        valid_to = Time.now + 600
        random_code = RandomTag::digits(6)
        send_sms(number, "Dein Bestaetigungscode zur Aktivierung der SMS-Anmeldung lautet #{random_code}.", email: @session_user[:email], purpose: 'confirm_number')
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :telephone_number => number.obfuscate(SMS_PHONE_NUMBER_PASSPHRASE), :tag => tag, :code => random_code, :valid_to => valid_to.to_i})
            MATCH (u:User {email: $email})
            CREATE (l:PhoneNumberConfirmation {tag: $tag, code: $code, valid_to: $valid_to, telephone_number: $telephone_number})-[:BELONGS_TO]->(u)
        END_OF_QUERY
        respond(:telephone_number => number, :next => 'confirm', :tag => tag)
    end

    post '/api/confirm_telephone_number' do
        require_user!
        data = parse_request_data(:required_keys => [:tag, :code])
        data[:code] = data[:code].gsub(/[^0-9]/, '')
        begin
            result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:PhoneNumberConfirmation {tag: $tag})-[:BELONGS_TO]->(u:User)
                SET l.tries = COALESCE(l.tries, 0) + 1
                RETURN l, u;
            END_OF_QUERY
        rescue
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        user = result['u']
        sms_code = result['l']
        # the confirmation belongs to the person who is logged in
        assert(user[:email] == @session_user[:email])
        if sms_code[:tries] > MAX_LOGIN_TRIES
            neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
                MATCH (l:PhoneNumberConfirmation {tag: $tag})
                DETACH DELETE l;
            END_OF_QUERY
            respond({:error => 'code_expired'})
            assert_with_delay(false, "Code expired", true)
        end
        assert(sms_code[:tries] <= MAX_LOGIN_TRIES)
        assert_with_delay(data[:code] == sms_code[:code], "Wrong SMS confirmation code entered for #{user[:email]}", true)
        if Time.at(sms_code[:valid_to]) < Time.now
            respond({:error => 'code_expired'})
        end
        assert(Time.at(sms_code[:valid_to]) >= Time.now, 'code expired', true)

        today = DateTime.now.strftime('%Y-%m-%d')
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :telephone_number => sms_code[:telephone_number], :today => today)
            MATCH (u:User {email: $email})
            SET u.telephone_number = $telephone_number
            SET u.telephone_number_changed = $today;
        END_OF_QUERY
        send_sms(sms_code[:telephone_number].deobfuscate(SMS_PHONE_NUMBER_PASSPHRASE), "Die Anmeldung per SMS ist nun aktiviert.", email: @session_user[:email], purpose: 'confirm_number')

        neo4j_query(<<~END_OF_QUERY, :tag => data[:tag])
            MATCH (l:PhoneNumberConfirmation {tag: $tag})
            DETACH DELETE l;
        END_OF_QUERY
        session_user = @session_user.dup
        deliver_mail do
            to session_user[:email]
            bcc SMTP_FROM
            from SMTP_FROM

            subject "Dashboard: SMS-Anmeldung aktiviert"

            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Die SMS-Anmeldung wurde aktiviert.</p>"
                io.puts "<p>Falls Sie diese Aktivierung nicht selbst veranlasst haben, setzen Sie sich bitte dringend mit #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} unter der E-Mail-Adresse <a href='mailto:#{WEBSITE_MAINTAINER_EMAIL}'>#{WEBSITE_MAINTAINER_EMAIL}</a> in Verbindung.</p>"
                io.puts "<p>Die Aktivierung erfolgte am #{DateTime.now.strftime('%d.%m.%Y')} um #{DateTime.now.strftime('%H:%M')} Uhr (Gerät: #{session_user[:user_agent]}, IP: #{session_user[:ip]}).</p>"
                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                io.string
            end
        end
        respond(:ok => 'yeah', :telephone_number => sms_code[:telephone_number].deobfuscate(SMS_PHONE_NUMBER_PASSPHRASE))
    end

    post '/api/delete_telephone_number' do
        require_user!
        had_number = !(@session_user[:telephone_number] || '').empty?
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            REMOVE u.preferred_login_method
            REMOVE u.telephone_number_changed
            REMOVE u.telephone_number;
        END_OF_QUERY
        notify_login_method_change('SMS-Anmeldung deaktiviert', 'Die SMS-Anmeldung wurde deaktiviert und die Telefonnummer gelöscht.') if had_number
        respond(:yay => 'sure')
    end

    get '/ws_sms' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)

            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:sms] ||= {}
                @@ws_clients[:sms][client_id] = {:ws => ws, :authenticated => false}
                @@ws_clients[:authenticated_sms] ||= {}
                STDERR.puts "Got #{@@ws_clients[:sms].size} connected SMS gateways."
                ws.send({command: 'hello', time: Time.now.to_i }.to_json)
                # heartbeat: every client answers a ping with a pong by itself
                @@ws_clients[:sms][client_id][:timer] = EM.add_periodic_timer(SMS_GATEWAY_PING_INTERVAL) do
                    client = @@ws_clients[:authenticated_sms][client_id]
                    next unless client
                    if Time.now.to_f - client[:last_seen] >= SMS_GATEWAY_STALE_AFTER
                        STDERR.puts "SMS gateway did not answer for #{SMS_GATEWAY_STALE_AFTER} seconds, dropping it."
                        @@ws_clients[:authenticated_sms].delete(client_id)
                        ws.close()
                    else
                        ws.ping('') { client[:last_seen] = Time.now.to_f }
                    end
                end
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                data = nil
                begin
                    data = JSON.parse(msg.data)
                rescue
                end
                if data
                    if Rack::Utils.secure_compare(data['hello'].to_s, SMS_GATEWAY_SECRET.to_s)
                        @@ws_clients[:sms][client_id][:authenticated] = true
                        @@ws_clients[:authenticated_sms][client_id] = {:ws => ws, :authenticated => true, :last_seen => Time.now.to_f}
                    else
                        ws.close()
                    end
                end
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:sms] ||= {}
                timer = (@@ws_clients[:sms][client_id] || {})[:timer]
                timer.cancel if timer
                @@ws_clients[:sms].delete(client_id)
                @@ws_clients[:authenticated_sms] ||= {}
                @@ws_clients[:authenticated_sms].delete(client_id)
                STDERR.puts "Got #{@@ws_clients[:sms].size} connected SMS gateways."
            end

            ws.rack_response
        end
    end
end
