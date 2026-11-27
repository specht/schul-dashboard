# Terminfinder (/terminfinder, new design only): teachers pick people, classes,
# groups and rooms and see when all of them are free in a week. Only lessons
# count – personal appointments (Termine) stay private, by decision.
#
# Two answers: /api/terminfinder_week has busy times only (date, from, to),
# for up to 150 people; /api/terminfinder_timetables has the lessons of a few
# timetables (people, classes, rooms) to show them side by side – what a
# teacher can already open in the timetable for each of them, nothing more
# (the public week files /gen/w/<public_id>, and the class and room files).
class Main < Sinatra::Base
    TERMINFINDER_MAX_PEOPLE = 150
    TERMINFINDER_MAX_TIMETABLES = 10

    # the week file of a person (email), a class ('/klasse/5a') or a room
    # ('@109') – the same a teacher sees in the timetable; nil if unknown
    def terminfinder_week_path(key, week)
        id = if key.start_with?('@')
            @@room_ids[key[1..]]
        elsif key.start_with?('/klasse/')
            @@klassen_id[key.sub('/klasse/', '')]
        else
            (@@user_info[key] || {})[:public_id]
        end
        return nil if id.nil? || id.to_s.empty?
        path = "/gen/w/#{id}/#{week}.json.gz"
        File.exist?(path) ? path : nil
    end

    def terminfinder_events(key, week)
        path = terminfinder_week_path(key, week)
        return nil if path.nil?
        Zlib::GzipReader.open(path) { |f| JSON.parse(f.read) }['events'] || []
    end

    # an event's label as it is now: what was struck out (substitutions)
    # gone, the rest as plain text
    def terminfinder_text(html)
        html.to_s.gsub(%r{<s>.*?</s>}m, ' ').gsub(/<[^>]*>/, ' ').gsub('&amp;', '&').gsub(/\s+/, ' ').strip
    end

    # second line of a page that only exists in the new design: everyone
    # else goes to the start page
    def this_page_is_only_in_the_new_design
        redirect "#{WEB_ROOT}/", 303 unless ui_preview?
        ''
    end

    # busy times of one person in one week (ISO week 'YYYY-WW'), nil if the
    # timetable has no file for them (no timetable, or outside the school year)
    # (a room's busy times too: '@109')
    def terminfinder_busy_times(email, week)
        events = terminfinder_events(email, week)
        return nil if events.nil?
        busy = {}
        days = {}
        events.each do |e|
            if e['lesson']
                next if e['entfall'] || e['deleted']
                start = e['start'].to_s
                stop = e['end'].to_s
                next unless start =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/ && stop =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
                (busy[start[0, 10]] ||= []) << [start[11, 5], stop[11, 5]]
            elsif e['event_type'] == 'holiday' && e['title']
                # Ferien and Feiertage have no label, the school's other days
                # (Projekttage …) have one
                days[[e['start'], e['end'], e['title']]] = e['label'] ? 'info' : 'holiday'
            end
        end
        busy.each_value do |list|
            list.sort!
            merged = []
            list.each do |a, b|
                if merged.last && a <= merged.last[1]
                    merged.last[1] = b if b > merged.last[1]
                else
                    merged << [a, b]
                end
            end
            list.replace(merged)
        end
        { :busy => busy, :days => days }
    end

    post '/api/terminfinder_week' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:week, :emails],
                                  :types => {:emails => Array},
                                  :max_body_length => 64 * 1024,
                                  :max_value_lengths => {:week => 7})
        assert(data[:week] =~ /\A\d{4}-\d{2}\z/)
        emails = data[:emails]
        assert(emails.all? { |x| x.is_a?(String) && x.size <= 256 })
        emails = emails.uniq
        assert(emails.size <= TERMINFINDER_MAX_PEOPLE, 'too_many_people')
        people = {}
        missing = []
        days = {}
        emails.each do |email|
            result = terminfinder_busy_times(email, data[:week])
            if result.nil?
                missing << email
                next
            end
            people[email] = result[:busy]
            days.merge!(result[:days])
        end
        respond(:week => data[:week], :people => people, :missing => missing,
                :days => days.map { |(from, to, title), kind| {:from => from, :to => to, :title => title, :kind => kind} })
    end

    # the lessons of a few timetables side by side: per key the week's
    # lessons with what the timetable shows of them (label, room), cancelled
    # ones marked; nil for a key without a timetable
    post '/api/terminfinder_timetables' do
        assert(teacher_logged_in?)
        data = parse_request_data(:required_keys => [:week, :keys],
                                  :types => {:keys => Array},
                                  :max_body_length => 8 * 1024,
                                  :max_value_lengths => {:week => 7})
        assert(data[:week] =~ /\A\d{4}-\d{2}\z/)
        keys = data[:keys]
        assert(keys.all? { |x| x.is_a?(String) && x.size <= 256 })
        keys = keys.uniq
        assert(keys.size <= TERMINFINDER_MAX_TIMETABLES, 'too_many_timetables')
        timetables = {}
        keys.each do |key|
            events = terminfinder_events(key, data[:week])
            if events.nil?
                timetables[key] = nil
                next
            end
            lessons = []
            events.each do |e|
                next unless e['lesson'] && !e['deleted']
                start = e['start'].to_s
                stop = e['end'].to_s
                next unless start =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/ && stop =~ /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/
                label = terminfinder_text(e['label_short'] || e['label'])
                room = terminfinder_text(e['raum'].is_a?(Array) ? e['raum'].last : e['raum'])
                changed = [e['label_short'], e['label'], e['raum']].any? { |x| x.to_s.include?('<s>') } || !e['vertretungs_text'].to_s.strip.empty?
                lesson = { :date => start[0, 10], :from => start[11, 5], :to => stop[11, 5], :label => label }
                lesson[:room] = room unless room.empty? || key == "@#{room}"
                lesson[:off] = true if e['entfall']
                lesson[:changed] = true if changed && !e['entfall']
                lesson[:duty] = true if e['pausenaufsicht']
                lessons << lesson
            end
            lessons.sort_by! { |l| [l[:date], l[:from], l[:label]] }
            timetables[key] = lessons
        end
        respond(:week => data[:week], :timetables => timetables)
    end
end
