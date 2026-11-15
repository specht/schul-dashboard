class Main < Sinatra::Base
    # What the search in the navigation bar finds: only things every teacher
    # may open anyway (class and course lists, timetables). Built from memory,
    # no database query. The pages of the person's own menu are added in the
    # browser (code.js, quick search).
    def quick_search_index
        require_teacher!
        items = []
        led_klassen = {}
        @@klassen_order.each do |klasse|
            (@@klassenleiter[klasse] || []).each do |shorthand|
                led_klassen[shorthand] ||= []
                led_klassen[shorthand] << tr_klasse(klasse)
            end
        end

        @@klassen_order.each do |klasse|
            sus = @@schueler_for_klasse[klasse] || []
            sub = ["#{sus.size} Schüler:innen"]
            klassenleiter = @@klassenleiter[klasse] || []
            sub << "Klassenleitung #{klassenleiter.join(', ')}" unless klassenleiter.empty?
            item = {
                :kind => 'klasse',
                :label => "Klasse #{tr_klasse(klasse)}",
                :sub => sub.join(' · '),
                :terms => "Klasse #{tr_klasse(klasse)} #{klasse}",
                :href => "/directory/#{CGI.escape(klasse)}",
            }
            if @@klassen_id[klasse]
                item[:actions] = [['Stundenplan', "/timetable/#{@@klassen_id[klasse]}"]]
            end
            items << item
        end

        @@lehrer_order.each do |email|
            user = @@user_info[email]
            next unless user
            sub = [user[:shorthand]]
            sub << "Klassenleitung #{led_klassen[user[:shorthand]].join(', ')}" if led_klassen[user[:shorthand]]
            items << {
                :kind => 'lehrer',
                :label => user[:display_name],
                :sub => sub.join(' · '),
                :terms => [user[:first_name], user[:last_name], user[:display_name]].join(' '),
                :shorthand => user[:shorthand],
                :href => "/timetable/#{user[:id]}",
            }
        end

        @@klassen_order.each do |klasse|
            (@@schueler_for_klasse[klasse] || []).each do |email|
                user = @@user_info[email]
                next unless user
                items << {
                    :kind => 'schueler',
                    :label => user[:display_name],
                    :sub => "Klasse #{tr_klasse(klasse)}",
                    :terms => [user[:first_name], user[:last_name], user[:display_name]].join(' '),
                    :href => "/directory/#{CGI.escape(klasse)}#quick=#{user[:id]}",
                    :actions => [['Stundenplan', "/timetable/#{user[:id]}"]],
                }
            end
        end

        # courses with their own list (upper school, electives)
        @@kurse_for_lehrer.values.flatten.uniq.each do |lesson_key|
            info = @@lessons[:lesson_keys][lesson_key]
            next unless info
            fach = @@faecher[info[:fach]] || info[:fach]
            sub = ['Kurs']
            sub << info[:lehrer].join(', ') unless (info[:lehrer] || []).empty?
            sub << "#{(@@schueler_for_lesson[lesson_key] || []).size} Schüler:innen"
            items << {
                :kind => 'kurs',
                :label => info[:pretty_folder_name],
                :sub => sub.join(' · '),
                :terms => [info[:pretty_folder_name], fach, (info[:lehrer] || []).join(' ')].join(' '),
                :href => "/directory/#{CGI.escape(lesson_key)}",
            }
        end
        items
    end

    get '/api/quick_search_index' do
        require_teacher!
        response.headers['Cache-Control'] = 'no-store'
        respond_raw_with_mimetype({:items => quick_search_index}.to_json, 'application/json')
    end
end
