# Importing an external calendar (iCal feed) into one person's timetable.
#
# Only for people with the role :can_import_ical (roles.rb). They store the
# address of their feed on the profile page (include/ical_import.rb); the
# timetable service fetches it every ICAL_IMPORT_INTERVAL seconds and right
# after it was saved (timetable-repl.rb), keeps the parsed appointments in
# ICAL_IMPORT_DIR and puts them into that person's private week files only
# (timetable.rb, event_type 'agenda'). Never into the public week files
# (colleagues, Terminfinder), never into the dashboard's own iCal export – so
# nothing that came from a feed goes out again (no loops with tools that read
# the week files or the export).
#
# Fetched through Main.fetch_public_uri (http(s) only, no internal addresses,
# no redirects); ICAL_IMPORT_TEST_HOSTS (test stack only) lets the fake
# Nextcloud serve a feed.

require 'digest'
require 'json'
require 'tzinfo'   # comes with activesupport (Gemfile.lock)

module IcalImport
    DIR = '/internal/ical_import'
    MAX_BYTES = 2 * 1024 * 1024
    MAX_EVENTS = 3000
    # appointments from this many days ago on (the rest until the end of the
    # school year)
    DAYS_BACK = 28
    BERLIN = TZInfo::Timezone.get('Europe/Berlin')

    # ---------- parsing ----------

    # [{uid, title, location, description, start, end, all_day, tentative}],
    # plus counts of what was left out; nil if the text is no calendar
    def self.parse(text, from_date, to_date)
        text = text.to_s.dup.force_encoding('UTF-8')
        text = text.encode('UTF-8', 'binary', :invalid => :replace, :undef => :replace) unless text.valid_encoding?
        return nil unless text =~ /BEGIN:VCALENDAR/i
        lines = text.gsub(/\r\n?/, "\n").gsub(/\n[ \t]/, '').split("\n")
        calname = nil
        events = []
        skipped = {:recurring => 0, :cancelled => 0}
        current = nil
        depth = 0
        lines.each do |line|
            name, params, value = parse_line(line)
            next if name.nil?
            if name == 'BEGIN'
                if value.upcase == 'VEVENT' && current.nil?
                    current = {}
                    depth = 0
                elsif current
                    depth += 1   # VALARM and the like inside an event
                end
                next
            end
            if name == 'END'
                if current && depth > 0
                    depth -= 1
                elsif current && value.upcase == 'VEVENT'
                    e = build_event(current, from_date, to_date, skipped)
                    events.concat(e) if e
                    current = nil
                end
                next
            end
            if current.nil?
                calname ||= unescape(value).strip if name == 'X-WR-CALNAME'
                next
            end
            next if depth > 0
            current[name] ||= [params, value]
        end
        events.sort_by! { |e| [e[:start], e[:end], e[:title]] }
        {:calname => (calname || '')[0, 60], :events => events.first(MAX_EVENTS), :skipped => skipped}
    end

    def self.parse_line(line)
        return nil if line.strip.empty?
        # the name and its parameters end at the first ':' outside quotes
        quoted = false
        cut = nil
        line.each_char.with_index do |c, i|
            quoted = !quoted if c == '"'
            if c == ':' && !quoted
                cut = i
                break
            end
        end
        return nil if cut.nil?
        head = line[0, cut]
        value = line[cut + 1..-1] || ''
        parts = head.split(';')
        name = parts.shift.to_s.upcase.strip
        params = {}
        parts.each do |p|
            k, v = p.split('=', 2)
            params[k.to_s.upcase.strip] = v.to_s.delete('"').strip
        end
        [name, params, value]
    end

    def self.unescape(s)
        s.to_s.gsub(/\\([nN,;\\])/) { |m| m[1] =~ /[nN]/ ? "\n" : m[1] }
    end

    # Time or Date (all-day) of DTSTART / DTEND, in Berlin time
    def self.parse_time(entry)
        return nil if entry.nil?
        params, value = entry
        value = value.to_s.strip
        if params['VALUE'].to_s.upcase == 'DATE' || value =~ /\A\d{8}\z/
            return (Date.strptime(value[0, 8], '%Y%m%d') rescue nil)
        end
        m = value.match(/\A(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?\z/)
        return nil if m.nil?
        y, mo, d, h, mi, s = m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, (m[6] || 0).to_i
        if m[7]
            utc = (Time.utc(y, mo, d, h, mi, s) rescue nil)
            return utc && BERLIN.to_local(utc)
        end
        zone = BERLIN
        if params['TZID'] && !params['TZID'].empty?
            zone = (TZInfo::Timezone.get(params['TZID'].sub(%r{\A/}, '')) rescue BERLIN)
        end
        local = (zone.local_time(y, mo, d, h, mi, s) rescue nil)
        return nil if local.nil?
        zone == BERLIN ? local : BERLIN.to_local(local.utc)
    end

    def self.parse_duration(value)
        m = value.to_s.strip.match(/\A([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?\z/)
        return nil if m.nil?
        seconds = m[2].to_i * 7 * 86400 + m[3].to_i * 86400 + m[4].to_i * 3600 + m[5].to_i * 60 + m[6].to_i
        m[1] == '-' ? -seconds : seconds
    end

    def self.text(current, name, max)
        unescape((current[name] || [nil, ''])[1]).strip[0, max]
    end

    def self.build_event(current, from_date, to_date, skipped)
        if current['RRULE'] || current['RDATE']
            # series are not expanded (yet): counted, so the profile can say so
            skipped[:recurring] += 1
            return nil
        end
        status = (current['STATUS'] || [nil, ''])[1].to_s.strip.upcase
        if status == 'CANCELLED'
            skipped[:cancelled] += 1
            return nil
        end
        start = parse_time(current['DTSTART'])
        return nil if start.nil?
        stop = parse_time(current['DTEND'])
        if stop.nil? && current['DURATION']
            seconds = parse_duration(current['DURATION'][1])
            if seconds
                stop = start.is_a?(Date) && !start.is_a?(DateTime) ? start + (seconds / 86400) : start + seconds
            end
        end
        all_day = start.is_a?(Date) && !start.is_a?(DateTime)
        if all_day
            stop = start + 1 unless stop.is_a?(Date) && stop > start
            return nil if stop <= from_date || start > to_date
            s, e = start.strftime('%Y-%m-%d'), stop.strftime('%Y-%m-%d')
        else
            stop = start if stop.nil? || stop.is_a?(Date) && !stop.is_a?(DateTime) || stop < start
            return nil if stop.to_date < from_date || start.to_date > to_date
            s, e = start.strftime('%Y-%m-%dT%H:%M'), stop.strftime('%Y-%m-%dT%H:%M')
        end
        title = text(current, 'SUMMARY', 200)
        title = 'Termin' if title.empty?
        [{
            :uid => text(current, 'UID', 200),
            :title => title,
            :location => text(current, 'LOCATION', 200),
            :description => text(current, 'DESCRIPTION', 4000),
            :start => s,
            :end => e,
            :all_day => all_day,
            :tentative => status == 'TENTATIVE',
        }]
    end

    # ---------- the cache (one file per person) ----------

    def self.path_for(email)
        File.join(DIR, Digest::SHA256.hexdigest("ical-import:#{email}")[0, 24] + '.json')
    end

    def self.read(email)
        path = path_for(email)
        return nil unless File.exist?(path)
        JSON.parse(File.read(path), :symbolize_names => true) rescue nil
    end

    # writes the parsed feed; true if the appointments changed
    def self.write(email, parsed, host)
        old = read(email)
        items = parsed[:events]
        digest = Digest::SHA256.hexdigest([items, parsed[:calname]].to_json)
        FileUtils.mkpath(DIR)
        data = {:digest => digest, :calname => parsed[:calname], :host => host,
                :fetched => Time.now.to_i, :events => items}
        temp = path_for(email) + '.tmp'
        File.write(temp, data.to_json)
        FileUtils.mv(temp, path_for(email))
        old.nil? || old[:digest] != digest
    end

    def self.remove(email)
        path = path_for(email)
        return false unless File.exist?(path)
        FileUtils.rm_f(path)
        true
    end

    # ---------- fetching ----------

    def self.test_hosts
        defined?(ICAL_IMPORT_TEST_HOSTS) ? ICAL_IMPORT_TEST_HOSTS : []
    end

    # [status, body]; raises with a short German reason
    def self.fetch(url)
        uri = (URI.parse(url.to_s) rescue nil)
        raise 'Die Adresse ist keine http(s)-Adresse.' unless uri.is_a?(URI::HTTP) && !uri.hostname.to_s.empty?
        if test_hosts.include?(uri.hostname)
            # test stack only: the fake Nextcloud serves the feed
            c = Curl::Easy.new(uri.to_s)
            c.follow_location = false
            c.timeout = 20
            c.perform
            return [c.response_code, c.body_str.to_s]
        end
        begin
            Main.fetch_public_uri(uri.to_s, MAX_BYTES + 1)
        rescue StandardError => e
            case e.message
            when 'unknown host' then raise 'Den Server gibt es nicht.'
            when 'address not allowed' then raise 'Diese Adresse ist nicht erlaubt.'
            else raise 'Der Server war nicht erreichbar.'
            end
        end
    end

    # The people whose feeds to fetch: a stored address and the role.
    def self.subscriptions(only_email = nil)
        rows = $neo4j.neo4j_query(<<~END_OF_QUERY, {:email => only_email})
            MATCH (u:User)
            WHERE u.ical_import_url IS NOT NULL AND ($email IS NULL OR u.email = $email)
            RETURN u.email, u.ical_import_url;
        END_OF_QUERY
        rows.map { |r| [r['u.email'], r['u.ical_import_url']] }.select do |email, url|
            Main.user_has_role(email, :can_import_ical)
        end
    end

    # Fetches the feeds (all, or one person's) and stores the result and its
    # state on the person. Returns the emails whose appointments changed (their
    # week files need writing).
    def self.refresh(only_email = nil, from_date = Date.today - DAYS_BACK, to_date = nil)
        to_date ||= (Date.parse(Main.class_variable_get(:@@config)[:last_day]) rescue Date.today + 365)
        changed = []
        subs = subscriptions(only_email)
        # gone: no address any more, or no role – the appointments go too
        if only_email && subs.empty?
            changed << only_email if remove(only_email)
        end
        subs.each do |email, url|
            begin
                status, body = fetch(url)
                raise "Der Server antwortet mit #{status}." unless status == 200
                raise 'Der Kalender ist größer als 2 MB.' if body.bytesize > MAX_BYTES
                parsed = parse(body, from_date, to_date)
                raise 'Unter der Adresse liegt kein Kalender (iCal).' if parsed.nil?
                host = (URI.parse(url).hostname rescue '')
                changed << email if write(email, parsed, host)
                $neo4j.neo4j_query(<<~END_OF_QUERY, {:email => email, :ts => Time.now.to_i, :count => parsed[:events].size, :recurring => parsed[:skipped][:recurring]})
                    MATCH (u:User {email: $email})
                    SET u.ical_import_ok_at = $ts, u.ical_import_count = $count, u.ical_import_recurring = $recurring
                    REMOVE u.ical_import_error, u.ical_import_error_at;
                END_OF_QUERY
            rescue StandardError => e
                reason = e.message.to_s
                reason = 'Der Kalender ließ sich nicht lesen.' unless reason =~ /\A[A-ZÄÖÜ].*\.\z/
                $neo4j.neo4j_query(<<~END_OF_QUERY, {:email => email, :ts => Time.now.to_i, :reason => reason[0, 200]})
                    MATCH (u:User {email: $email})
                    SET u.ical_import_error = $reason, u.ical_import_error_at = $ts;
                END_OF_QUERY
            end
        end
        changed
    end

    # ---------- into the week files ----------

    # the person's appointments by ISO week ('2026-47'), as week file events;
    # all-day ones in every week they touch
    def self.events_by_week(email)
        data = read(email)
        return {} if data.nil?
        label = data[:calname].to_s.strip
        label = 'Kalender' if label.empty?
        result = {}
        (data[:events] || []).each do |item|
            weeks = []
            if item[:all_day]
                d = Date.parse(item[:start])
                last = Date.parse(item[:end]) - 1
                while d <= last
                    weeks << d.strftime('%G-%V')
                    d += 7
                end
                weeks << last.strftime('%G-%V')
            else
                weeks << Date.parse(item[:start][0, 10]).strftime('%G-%V')
            end
            event = week_event(item, label)
            weeks.uniq.each { |yw| (result[yw] ||= []) << event }
        end
        result
    end

    # Text from the feed goes into fields the timetable inserts as HTML
    # (event_title, description, organized_by, label): escaped. `title` stays
    # text (the places that write it as text).
    def self.week_event(item, label)
        h = lambda { |s| CGI.escapeHTML(s.to_s) }
        title = item[:title].to_s
        title += ' (vorläufig)' if item[:tentative]
        description = [item[:location].to_s.empty? ? nil : "Ort: #{item[:location]}", item[:description]].compact.reject(&:empty?).join("\n\n")
        id = 'ical-' + Digest::SHA256.hexdigest("#{item[:uid]}/#{item[:start]}")[0, 16]
        event = {
            :lesson => false,
            :event_type => 'agenda',
            :source => 'ical',
            :uid => item[:uid],
            :tentative => item[:tentative] ? true : false,
            :title => title,
            :classNames => ['pv-ical'],
            :start => item[:start],
            :end => item[:end],
            :datum => item[:start][0, 10],
        }
        if item[:all_day]
            event[:allDay] = true
            event[:label] = h.call(title)
        else
            event.merge!({
                :is_event => true,
                :eid => id,
                :event_title => h.call(title),
                :description => h.call(description).gsub("\n", '<br />'),
                :organized_by => h.call(label),
                # the place (»Gymnasium X« of »Gymnasium X, Straße 1«), as text
                :room_name => item[:location].to_s.split(',').first.to_s.strip[0, 40],
                :start_time => item[:start][11, 5],
                :end_time => item[:end][11, 5],
                :jitsi => false,
            })
        end
        event
    end
end
