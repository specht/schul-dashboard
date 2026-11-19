# Terminfinder (/terminfinder, new design only): teachers pick people and
# see when all of them are free in a week. Only lessons count – personal
# appointments (Termine) stay private, by decision. The answer contains busy
# times only (date, from, to), never what someone has, where or with whom.
# Read from the public week files the timetable writes (/gen/w/<public_id>),
# which teachers can already open in the timetable for everyone.
class Main < Sinatra::Base
    TERMINFINDER_MAX_PEOPLE = 150

    # second line of a page that only exists in the new design: everyone
    # else goes to the start page
    def this_page_is_only_in_the_new_design
        redirect "#{WEB_ROOT}/", 303 unless ui_preview?
        ''
    end

    # busy times of one person in one week (ISO week 'YYYY-WW'), nil if the
    # timetable has no file for them (no timetable, or outside the school year)
    def terminfinder_busy_times(email, week)
        info = @@user_info[email]
        return nil if info.nil? || info[:public_id].nil?
        path = "/gen/w/#{info[:public_id]}/#{week}.json.gz"
        return nil unless File.exist?(path)
        events = Zlib::GzipReader.open(path) { |f| JSON.parse(f.read) }['events'] || []
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
end
