class Main < Sinatra::Base

    MONITOR_MESSAGE_PATH = '/vplan/message.json'

    def get_monitor_messages()
        data = {}
        if File.exist?(MONITOR_MESSAGE_PATH)
            data = JSON.parse(File.read(MONITOR_MESSAGE_PATH))
        end
        result = {
            :messages => [],
            :images => []
        }
        [:messages, :images].each do |key|
            (data[key.to_s] || '').split("\n").each do |line|
                line.strip!
                result[key] << line unless line.empty?
            end
        end
        result
    end

    def self.force_reload_monitors
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'force_reload'}.to_json)
        end
    end

    post '/api/force_reload_monitors' do
        require_user_who_can_manage_monitors!
        self.class.force_reload_monitors()
    end

    def update_monitors_message
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'update_monitor_messages', :data => get_monitor_messages}.to_json)
        end
    end

    def update_monitors_vplan
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            monitor_data = {:klassen => {}, :timestamp => ''}
            monitor_data_path = '/vplan/monitor/monitor.json'
            if File.exist?(monitor_data_path)
                monitor_data = JSON.parse(File.read(monitor_data_path))
            end
            ws.send({:command => 'update_vplan', :data => monitor_data}.to_json)
        end
    end

    def update_monitors
        update_monitors_message()
        update_monitors_vplan()
    end

    # Signalisiert den Monitoren nur, DASS sich Buchungen geändert haben - die Daten
    # selbst werden bewusst nicht über diesen Kanal verschickt, da /ws_monitor ohne
    # Anmeldung erreichbar ist. Der Buchungen-Monitor lädt daraufhin neu und bekommt
    # die Daten serverseitig gerendert, also erst nach der Rechteprüfung.
    def update_monitors_bookings
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            ws = info[:ws]
            ws.send({:command => 'update_bookings'}.to_json)
        end
    end

    post '/api/update_monitor_messages' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:messages, :images],
            :max_body_length => 64 * 1024,
            :max_string_length => 64 * 1024)
        File.open(MONITOR_MESSAGE_PATH, 'w') do |f|
            d = {:messages => data[:messages], :images => data[:images]}
            f.print d.to_json
        end
        update_monitors_message()
    end

    post '/api/get_monitor_messages_raw' do
        require_user_who_can_manage_monitors!
        data = {'messages': '', 'images': ''}
        if File.exist?(MONITOR_MESSAGE_PATH)
            data = JSON.parse(File.read(MONITOR_MESSAGE_PATH))
        end
        respond(:data => data)
    end

    get '/api/update_monitors' do
        update_monitors()
    end

    get '/ws_monitor' do
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)

            ws.on(:open) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:monitor] ||= {}
                @@ws_clients[:monitor][client_id] = {:ws => ws}
                STDERR.puts "Got #{@@ws_clients[:monitor].size} connected monitors."
                ws.send({command: 'update_time', time: Time.now.to_i }.to_json)
                update_monitors()
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                data = nil
                begin
                    data = JSON.parse(msg.data)
                rescue
                end
                if data
                    STDERR.puts data.to_yaml
                end
            end

            ws.on(:close) do |event|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                @@ws_clients[:monitor] ||= {}
                @@ws_clients[:monitor].delete(client_id)
                STDERR.puts "Got #{@@ws_clients[:monitor].size} connected monitors."
            end

            ws.rack_response
        end
    end

    def get_monitor_zeugniskonferenzen
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (m:MonitorZeugniskonferenz)
            RETURN m.key, COALESCE(m.value, FALSE) AS value;
        END_OF_QUERY
        result = {}
        rows.each do |row|
            result[row['m.key']] = row['value']
        end
        result['flur'] ||= false
        result['lz'] ||= false
        result['sek'] ||= false
        result['silentium'] ||= false
        result
    end

    post '/api/get_monitor_zeugniskonferenzen' do
        respond(:result => get_monitor_zeugniskonferenzen())
    end

    post '/api/toggle_monitor_zeugniskonferenzen' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:key])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:key => data[:key]})
            MERGE (m:MonitorZeugniskonferenz {key: $key})
            SET m.value = NOT COALESCE(m.value, FALSE)
            RETURN COALESCE(m.value, FALSE) AS result;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond(:result => result['result'])
    end

    def running_zeugniskonferenzen
        sha1_and_t0_list = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i}).map { |x| [x['m.sha1'], x['m.t0']] }
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            RETURN m.sha1, m.t0;
        END_OF_QUERY
        sha1_list = Set.new(sha1_and_t0_list.map { |x| x[0] })
        t0_for_sha1 = {}
        sha1_and_t0_list.each do |entry|
            t0_for_sha1[entry[0]] = entry[1]
        end
        result = {}
        today = Date.today.strftime('%Y-%m-%d')
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            sha1 = Digest::SHA1.hexdigest([today, entry].to_json)[0, 16]
            if sha1_list.include?(sha1)
                result[entry[0]] = t0_for_sha1[sha1]
            end
        end
        result
    end

    def finished_zeugniskonferenzen
        sha1_list = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i}).map { |x| x['m.sha1'] }
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NOT NULL
            RETURN m.sha1;
        END_OF_QUERY
        sha1_list = Set.new(sha1_list)
        result = []
        today = Date.today.strftime('%Y-%m-%d')
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            sha1 = Digest::SHA1.hexdigest([today, entry].to_json)[0, 16]
            if sha1_list.include?(sha1)
                result << entry[0]
            end
        end
        result
    end

    post '/api/start_zeugniskonferenz' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:start_time])
        start_time = data[:start_time]
        today = Date.today.strftime('%Y-%m-%d')
        found_entry = nil
        (ZEUGNISKONFERENZEN[today] || []).each do |entry|
            if entry[0] == start_time
                found_entry = entry
                break
            end
        end
        result = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i})
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            SET m.t1 = $t1;
        END_OF_QUERY
        if found_entry
            sha1 = Digest::SHA1.hexdigest([today, found_entry].to_json)[0, 16]
            result = neo4j_query_expect_one(<<~END_OF_QUERY, {:sha1 => sha1, :t0 => Time.now.to_i})
                MERGE (m:MonitorZeugniskonferenzState {sha1: $sha1})
                SET m.t0 = $t0
                REMOVE m.t1
                RETURN m;
            END_OF_QUERY
            self.class.force_reload_monitors()
            klasse = found_entry[1]
            if @@zeugnisliste_for_klasse[klasse]
                lehrer_for_fach = @@zeugnisliste_for_klasse[klasse][:lehrer_for_fach]
                lehrer_set = Set.new()
                if lehrer_for_fach
                    lehrer_for_fach.each_pair do |fach, lehrer_list|
                        lehrer_list.each do |shorthand|
                            lehrer_set << @@shorthands[shorthand]
                        end
                    end
                end
                lehrer_set.each do |email|
                    begin
                        telephone_number = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => email})['telephone_number']
                            MATCH (u:User {email: $email})
                            RETURN u.telephone_number AS telephone_number;
                        END_OF_QUERY
                        if telephone_number
                            begin
                                send_sms(telephone_number.deobfuscate(SMS_PHONE_NUMBER_PASSPHRASE), "Die Zensurenkonferenz der Klasse #{klasse} beginnt jetzt.", email: email, purpose: 'conference')
                            rescue
                                STDERR.puts "Failed to send SMS to #{telephone_number}"
                            end
                        end
                    rescue
                        STDERR.puts "Failed to send SMS to #{email}"
                    end
                end
            end
        end
        respond()
    end

    post '/api/stop_zeugniskonferenz' do
        require_user_who_can_manage_monitors!
        today = Date.today.strftime('%Y-%m-%d')

        result = neo4j_query(<<~END_OF_QUERY, {:t1 => Time.now.to_i})
            MATCH (m:MonitorZeugniskonferenzState)
            WHERE m.t1 IS NULL
            SET m.t1 = $t1;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond()
    end
    # ---- Wetter- und Festeffekte (monitor_effekte.rb, static/monitor_effekte.js) ----

    MONITOR_WETTER_ABRUF_ALLE = 10 * 60
    @@monitor_wetter = {:versucht => 0, :geholt => 0, :daten => nil, :laeuft => false}
    @@monitor_wetter_mutex = Mutex.new

    # Liefert die zuletzt geholten Warnungen des DWD. Sind sie älter als zehn
    # Minuten, holt ein Hintergrund-Thread neue – keine Anfrage wartet auf den
    # DWD, und ist er nicht erreichbar, bleibt es einfach bei den alten Daten.
    def monitor_wetter_daten
        return nil unless MONITOR_DWD_WARNCELL
        @@monitor_wetter_mutex.synchronize do
            jetzt = Time.now.to_i
            if !@@monitor_wetter[:laeuft] && jetzt - @@monitor_wetter[:versucht] > MONITOR_WETTER_ABRUF_ALLE
                @@monitor_wetter[:laeuft] = true
                @@monitor_wetter[:versucht] = jetzt
                Thread.new do
                    daten = nil
                    begin
                        c = Curl::Easy.new(MonitorEffekte::DWD_WARNINGS_URL)
                        c.connect_timeout = 10
                        c.timeout = 30
                        c.follow_location = false
                        c.perform
                        daten = MonitorEffekte.parse_dwd(c.body_str) if c.response_code == 200
                        STDERR.puts "DWD-Warnungen: Antwort #{c.response_code}" unless daten
                    rescue StandardError => e
                        STDERR.puts "DWD-Warnungen nicht abrufbar: #{e.class}"
                    ensure
                        @@monitor_wetter_mutex.synchronize do
                            if daten
                                @@monitor_wetter[:daten] = daten
                                @@monitor_wetter[:geholt] = Time.now.to_i
                            end
                            @@monitor_wetter[:laeuft] = false
                        end
                    end
                end
            end
            if jetzt - @@monitor_wetter[:geholt] > MonitorEffekte::HOECHSTALTER
                nil
            else
                @@monitor_wetter[:daten]
            end
        end
    end

    def monitor_effekte_an?
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (m:MonitorEinstellung {key: 'effekte_aus'})
            RETURN COALESCE(m.value, FALSE) AS aus;
        END_OF_QUERY
        !(rows.first && rows.first['aus'])
    end

    # Je Effekt: an/aus und ab welcher Warnstufe (MonitorEffekte::REGELN_STANDARD)
    # Schultermine für die Monitore (Adventskonzert, Forschertag …), je ein Tag
    def monitor_schultermine
        neo4j_query(<<~END_OF_QUERY).map { |r| {:id => r['id'], :datum => r['datum'], :bis => r['bis'] || '', :motiv => r['motiv'], :titel => r['titel'] || ''} }
            MATCH (t:MonitorSchultermin)
            RETURN t.id AS id, t.datum AS datum, t.bis AS bis, t.motiv AS motiv, t.titel AS titel
            ORDER BY t.datum;
        END_OF_QUERY
    end

    post '/api/add_monitor_schultermin' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:datum, :motiv], :optional_keys => [:titel, :bis], :max_string_length => 80)
        datum = Date.parse(data[:datum]) rescue nil
        assert(!datum.nil?)
        bis = data[:bis].to_s.strip.empty? ? nil : (Date.parse(data[:bis]) rescue nil)
        assert(data[:bis].to_s.strip.empty? || (!bis.nil? && bis >= datum && bis - datum <= 14))
        assert(MonitorEffekte::SCHULTERMIN_MOTIVE.include?(data[:motiv]))
        neo4j_query(<<~END_OF_QUERY, :id => RandomTag.generate(12), :datum => datum.to_s, :bis => bis ? bis.to_s : '', :motiv => data[:motiv], :titel => (data[:titel] || '').strip)
            CREATE (t:MonitorSchultermin {id: $id, datum: $datum, bis: $bis, motiv: $motiv, titel: $titel});
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/delete_monitor_schultermin' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:id], :max_string_length => 32)
        neo4j_query(<<~END_OF_QUERY, :id => data[:id])
            MATCH (t:MonitorSchultermin {id: $id})
            DETACH DELETE t;
        END_OF_QUERY
        respond(:ok => true)
    end

    def monitor_effekt_regeln
        rows = neo4j_query(<<~END_OF_QUERY)
            MATCH (m:MonitorEffektRegel)
            RETURN m.effekt AS effekt, m.an AS an, m.ab AS ab;
        END_OF_QUERY
        gespeichert = {}
        rows.each do |row|
            g = {}
            g[:an] = row['an'] unless row['an'].nil?
            g[:ab] = row['ab'] unless row['ab'].nil?
            gespeichert[row['effekt']] = g
        end
        MonitorEffekte.regeln(gespeichert)
    end

    # Monitore, die über einen geheimen Monitor-Link laufen (MONITOR_*_DEEP_LINK),
    # haben keine Sitzung – sie schicken den Link als Ausweis mit.
    def monitor_deep_link?(link)
        return false unless link.is_a?(String) && link.size >= 8
        [MONITOR_DEEP_LINK, MONITOR_LZ_DEEP_LINK, MONITOR_SILENTIUM_DEEP_LINK].any? do |l|
            l.is_a?(String) && l.size == link.size && Rack::Utils.secure_compare(l, link)
        end
    end

    # Fragen die Flur-Monitore alle zehn Minuten ab. Antwort:
    # an: Effekte eingeschaltet (Monitore verwalten)
    # wetter: {effekt, staerke, titel, bis} oder null
    # fest: {fest, nah} oder null
    # bereit: false, solange noch keine Daten vom DWD da sind
    # Für die Verwaltung zusätzlich: warnungen (alle aktuellen und kommenden
    # Warnungen des DWD fürs Warngebiet, mit Texten), abgerufen (Zeitpunkt in ms)
    get '/api/monitor_effekte' do
        verwaltung = false
        unless monitor_deep_link?(params['link'])
            require_monitor_or_user_who_can_manage_monitors!
            verwaltung = user_who_can_manage_monitors_logged_in?
        end
        daten = monitor_wetter_daten()
        regeln = monitor_effekt_regeln()
        # Wetter und Fest zugleich: Einzeltage (Valentinstag, Fasching, letzter Schultag)
        # gehen vor, bei Advent und Ostern hat das Wetter Vorrang
        termine = monitor_schultermine()
        heute = MonitorEffekte.schultermin(Date.today, termine) || MonitorEffekte.fest(Date.today, @@ferien_feiertage, Time.now)
        wetter, fest, ruht = MonitorEffekte.vorrang(MonitorEffekte.wetter(daten, MONITOR_DWD_WARNCELL, Time.now, regeln), heute)
        antwort = {:an => monitor_effekte_an?,
                   :wetter => wetter,
                   :fest => fest,
                   :ruht => ruht,
                   :bereit => !daten.nil? || !MONITOR_DWD_WARNCELL,
                   :vorschau => @@monitor_effekte_vorschau}
        if verwaltung
            antwort[:warnungen] = MonitorEffekte.warnungen(daten, MONITOR_DWD_WARNCELL, Time.now, regeln)
            antwort[:regeln] = regeln
            antwort[:schultermine] = termine.select { |t| (t[:bis].to_s.empty? ? t[:datum] : t[:bis]) >= Date.today.to_s }
            antwort[:schultermin_motive] = MonitorEffekte::SCHULTERMIN_MOTIVE
            antwort[:phaenomene] = MonitorEffekte::PHAENOMENE
            antwort[:phaenomene_ohne_effekt] = MonitorEffekte::PHAENOMENE_OHNE_EFFEKT
            antwort[:abgerufen] = daten ? @@monitor_wetter[:geholt] * 1000 : nil
            antwort[:dwd_aus] = !MONITOR_DWD_WARNCELL
        end
        respond(antwort)
    end

    # Schalter auf „Monitore verwalten“: an = 'ja' oder 'nein'. Die Monitore laden
    # danach neu, damit laufende Effekte sofort verschwinden.
    post '/api/set_monitor_effekte' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:an], :max_string_length => 4)
        assert(%w(ja nein).include?(data[:an]))
        result = neo4j_query_expect_one(<<~END_OF_QUERY, {:aus => data[:an] == 'nein'})
            MERGE (m:MonitorEinstellung {key: 'effekte_aus'})
            SET m.value = $aus
            RETURN m.value AS aus;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond(:an => !result['aus'])
    end

    # Vorschau auf „Monitore verwalten“: Fenster im Folgen-Modus (/monitor…?effekt=folgen)
    # zeigen den gewählten Effekt; die echten Monitore reagieren nicht darauf.
    @@monitor_effekte_vorschau = ''
    MONITOR_VORSCHAU_NAMEN = (MonitorEffekte::EFFEKTE + MonitorEffekte::FESTE + %w(zeus rundgang)).freeze

    post '/api/monitor_effekte_vorschau' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:effekt], :max_string_length => 16)
        assert(data[:effekt] == '' || MONITOR_VORSCHAU_NAMEN.include?(data[:effekt]))
        @@monitor_effekte_vorschau = data[:effekt]
        (@@ws_clients[:monitor] || {}).each_pair do |client_id, info|
            info[:ws].send({:command => 'monitor_effekte_vorschau', :effekt => @@monitor_effekte_vorschau}.to_json)
        end
        respond(:effekt => @@monitor_effekte_vorschau)
    end

    # Ein Wetter-Effekt an/aus und ab welcher Stufe (Tabelle auf „Monitore verwalten“)
    post '/api/set_monitor_effekt_regel' do
        require_user_who_can_manage_monitors!
        data = parse_request_data(:required_keys => [:effekt, :an, :ab], :types => {:ab => Integer},
                                  :max_string_length => 16)
        effekt = data[:effekt]
        assert(MonitorEffekte::EFFEKTE.include?(effekt))
        assert(%w(ja nein).include?(data[:an]))
        erlaubt = effekt == 'hitze' ? MonitorEffekte::STUFEN_HITZE : MonitorEffekte::STUFEN_WAEHLBAR
        assert(erlaubt.include?(data[:ab]))
        neo4j_query(<<~END_OF_QUERY, {:effekt => effekt, :an => data[:an] == 'ja', :ab => data[:ab]})
            MERGE (m:MonitorEffektRegel {effekt: $effekt})
            SET m.an = $an, m.ab = $ab;
        END_OF_QUERY
        self.class.force_reload_monitors()
        respond(:regeln => monitor_effekt_regeln())
    end
end
