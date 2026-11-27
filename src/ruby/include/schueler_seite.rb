# A student's page for teachers (/schueler/<id>, the search in the navigation
# bar leads here): what the class list already shows teachers about the
# student, in one place, and the lessons with their teachers and hours.
# Nothing a teacher couldn't see before – the same fields as the class list
# (directory.rb), the lessons as in the student's timetable.
class Main < Sinatra::Base
    def schueler_seite_email(id)
        return nil unless id.is_a?(String) && id =~ /\A[a-z0-9]{1,32}\z/
        @@user_info.each_pair do |email, user|
            return email if user[:id] == id && !user[:teacher] && user[:klasse]
        end
        nil
    end

    # lessons per week of a lesson in the timetable valid today (0 if it has
    # none now)
    def schueler_seite_hours(lesson_key)
        start_date = (@@lessons[:start_date_for_date] || {})[Date.today.strftime('%Y-%m-%d')]
        start_date ||= ((@@lessons[:timetables] || {}).keys.select { |d| d <= Date.today.strftime('%Y-%m-%d') }.max)
        return 0 if start_date.nil?
        lesson = ((@@lessons[:timetables] || {})[start_date] || {})[lesson_key]
        return 0 if lesson.nil?
        (lesson[:stunden] || {}).values.map(&:size).sum
    end

    def schueler_seite_teacher_link(shorthand)
        h = ->(x) { CGI.escapeHTML(x.to_s) }
        teacher = @@user_info[@@shorthands[shorthand]]
        return h.(shorthand) if teacher.nil?
        "<a href='/timetable/#{h.(teacher[:id])}'>#{h.(teacher[:display_name])}</a>"
    end

    def print_schueler_seite
        require_teacher!
        email = schueler_seite_email(request.path.split('/')[2])
        h = ->(x) { CGI.escapeHTML(x.to_s) }
        StringIO.open do |io|
            if email.nil?
                io.puts "<h2>Schüler:in</h2>"
                io.puts "<p>Diese Seite gibt es nicht (mehr). Vielleicht ist die Person nicht mehr an der Schule.</p>"
                next io.string
            end
            user = @@user_info[email]
            klasse = user[:klasse]
            oberstufe = (user[:klassenstufe] || 7) >= 11

            # the head: picture, name, class, the way to the timetable and the list
            io.puts "<div class='sp-head'>"
            io.puts "<div class='sp-avatar'>#{user_icon(email, 'sp-avatar-img')}</div>"
            io.puts "<div class='sp-title'>"
            io.puts "<h2>#{h.(user[:display_name])}</h2>"
            line = ["<a href='/directory/#{h.(CGI.escape(klasse))}#quick=#{h.(user[:id])}'>Klasse #{h.(tr_klasse(klasse))}</a>"]
            leiter = (@@klassenleiter[klasse] || []).map { |s| schueler_seite_teacher_link(s) }
            line << "Klassenleitung #{leiter.join(', ')}" unless leiter.empty?
            io.puts "<p class='sp-sub'>#{line.join(', ')}</p>"
            io.puts "<div class='sp-actions'>"
            io.puts "<a class='btn btn-secondary' id='bu_sp_timetable' href='/timetable/#{h.(user[:id])}'>Stundenplan</a>"
            io.puts "<a class='btn btn-secondary' id='bu_sp_klasse' href='/directory/#{h.(CGI.escape(klasse))}#quick=#{h.(user[:id])}'>Klassenliste</a>"
            io.puts "</div>"
            io.puts "</div>"
            io.puts "</div>"

            # the data: as in the class list
            last_access = (neo4j_query(<<~END_OF_QUERY, :email => email).first || {})['u.last_access']
                MATCH (u:User {email: $email})
                RETURN u.last_access;
            END_OF_QUERY
            facts = []
            facts << ['Geburtsdatum', user[:geburtstag] ? (Date.parse(user[:geburtstag]).strftime('%d.%m.%Y') rescue h.(user[:geburtstag])) : '–']
            facts << ['Geschlecht', h.({ 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }[user[:geschlecht]] || user[:geschlecht] || '–')]
            facts << ['Bildungsgang', h.(tr_bildungsgang(user[:bildungsgang]) || '–')]
            facts << ['Stufe', h.(user[:klassenstufe] || '–')]
            if oberstufe
                lks = directory_lks[email] || []
                facts << ['Leistungskurse', lks.empty? ? '–' : h.(lks.map { |x| x[:name] }.join(', '))]
                tutor = user[:tutor] && @@user_info[user[:tutor]]
                facts << ['Tutor:in', tutor ? schueler_seite_teacher_link(tutor[:shorthand]) : '–']
            end
            facts << ['E-Mail', :email]
            facts << ['E-Mail der Eltern', :eltern]
            facts << ['Letzter Zugriff', h.(directory_last_access_label(last_access))]
            io.puts "<h4>Angaben</h4>"
            io.puts "<dl class='sp-facts'>"
            facts.each do |label, value|
                io.puts "<dt>#{label}</dt><dd>"
                if value == :email
                    print_email_field(io, h.(user[:email]))
                elsif value == :eltern
                    print_email_field(io, h.("eltern.#{user[:email]}"))
                else
                    io.puts value
                end
                io.puts "</dd>"
            end
            io.puts "</dl>"

            # the lessons: subject, teachers, hours per week, the course's list
            rows = (@@lessons_for_user[email] || []).map do |key|
                info = @@lessons[:lesson_keys][key]
                next nil if info.nil?
                fach = info[:fach].to_s
                { :key => key, :info => info, :fach => (@@faecher[fach] || fach).to_s, :hours => schueler_seite_hours(key) }
            end.compact
            # lessons the timetable has now (others ended or start later)
            rows = rows.select { |r| r[:hours] > 0 } if rows.any? { |r| r[:hours] > 0 }
            rows.sort_by! { |r| [r[:fach].downcase, r[:key]] }
            klasse_size = (@@schueler_for_klasse[klasse] || []).size
            io.puts "<h4>Unterricht</h4>"
            if rows.empty?
                io.puts "<p class='sp-none'>Kein Unterricht im Stundenplan.</p>"
            else
                io.puts "<div class='sp-scroll'><table class='table table-sm sp-lessons'>"
                io.puts "<thead><tr><th>Fach</th><th>Lehrkraft</th><th class='sp-num'>Std.</th><th>Lerngruppe</th></tr></thead><tbody>"
                rows.each do |r|
                    info = r[:info]
                    subject = DesignTokens.subject_key(info[:fach])
                    dot = subject ? "<span class='sp-dot' style='background: var(--subj-#{subject}, var(--acc))' aria-hidden='true'></span>" : "<span class='sp-dot' aria-hidden='true'></span>"
                    teachers = (info[:lehrer] || []).map { |s| schueler_seite_teacher_link(s) }
                    members = (@@schueler_for_lesson[r[:key]] || []).size
                    group = if members > 0 && (members != klasse_size || oberstufe)
                        "<a href='/directory/#{h.(CGI.escape(r[:key]))}'>#{h.(info[:pretty_folder_name] || r[:fach])}</a> (#{members})"
                    else
                        "Klasse #{h.(tr_klasse(klasse))}"
                    end
                    io.puts "<tr data-lesson='#{h.(r[:key])}'><td>#{dot}#{h.(r[:fach])}</td><td>#{teachers.empty? ? '–' : teachers.join(', ')}</td><td class='sp-num'>#{r[:hours] > 0 ? r[:hours] : '–'}</td><td>#{group}</td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.string
        end
    end
end
