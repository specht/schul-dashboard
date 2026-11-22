# The teachers check the new student list before the switch
# (review/2026-11/student-data-review.md, step 3): on /schuelerliste a
# Klassenleitung (5–10) sees the class as it is in the draft (/datenpflege),
# changes against today marked, marks every student as right or enters a
# correction, adds missing students and confirms the list. Corrections are
# made in LUSD by the Datenpflege; nothing here changes the dashboard.
#
#   (:StudentCheck {review, student, status, fields, text, gone, gone_since,
#                   dashboard_only, by, at})      status: ok | correction
#   (:StudentMissing {id, review, name, note, by, at})
#   (:StudentReview {review, confirmed_at, confirmed_by, draft})
#
# review: "klasse:5a"; student: the address for students who have one, the
# key of the export otherwise (datenpflege_student_key). Personal data:
# deleted after the switch.

class Main < Sinatra::Base
    SCHUELERLISTE_FIELDS = %w(rufname nachname vornamen geschlecht geburtstag klasse bildungsgang)
    SCHUELERLISTE_FIELD_LABELS = {
        'rufname' => 'Rufname', 'nachname' => 'Nachname', 'vornamen' => 'Vornamen',
        'geschlecht' => 'Geschlecht', 'geburtstag' => 'Geburtstag', 'klasse' => 'Klasse',
        'bildungsgang' => 'Bildungsgang',
    }
    # only these can be kept in the dashboard alone (overrides)
    SCHUELERLISTE_DASHBOARD_ONLY = %w(rufname geschlecht)

    # classes checked by Klassenleitungen (11 and 12: tutors, later)
    def schuelerliste_klassen_all
        KLASSEN_ORDER.reject { |k| ['11', '12'].include?(k.to_s) }
    end

    # Klassenleitungen see the draft only once the Datenpflege released it
    # (»Für Klassenleitungen freigeben«, or the first mail): before that the
    # export can be tried and fixed without anybody starting to check it
    def schuelerliste_released?
        draft = datenpflege_draft
        !!(draft && draft['released'])
    end

    # the classes this person may check
    def schuelerliste_klassen_for_user
        return schuelerliste_klassen_all if user_with_role_logged_in?(:can_manage_data)
        return [] unless teacher_logged_in? && schuelerliste_released?
        shorthand = @session_user[:shorthand]
        schuelerliste_klassen_all.select { |k| (@@klassenleiter[k] || []).include?(shorthand) }
    end

    def this_is_a_page_for_schuelerliste
        unless teacher_logged_in? || user_with_role_logged_in?(:can_manage_data)
            redirect "#{WEB_ROOT}/", 303
        end
        nil
    end

    # The draft as the classes will see it: klasse => {:students, :leaving},
    # or {:errors} / nil without a draft. Kept until the draft or the
    # overrides change.
    def schuelerliste_view
        draft = datenpflege_draft
        return nil unless draft
        stamp = [draft['token'], (File.mtime(datenpflege_draft_path).to_f rescue 0),
                 (File.mtime(Parser::OVERRIDES_PATH).to_f rescue 0), Parser.schueler_path]
        @@schuelerliste_view ||= nil
        return @@schuelerliste_view[:view] if @@schuelerliste_view && @@schuelerliste_view[:stamp] == stamp
        pending = datenpflege_load_pending(draft['token'])
        date = datenpflege_valid_date(draft['date']) || Date.today
        c = datenpflege_compare(pending, draft['klassen'] || {}, date,
                                datenpflege_choices_by_row(pending, draft['links']),
                                datenpflege_choices_by_row(pending, draft['emails']))
        view = if c[:errors].empty?
            schuelerliste_build_view(c, datenpflege_parse_list(c[:old_path]))
        else
            { :errors => c[:errors] }
        end
        view[:draft] = draft['token']
        @@schuelerliste_view = { :stamp => stamp, :view => view }
        view
    end

    def schuelerliste_build_view(c, old_records)
        old_by = old_records.to_h { |r| [r[:email], r] }
        new_by = c[:new_records].to_h { |r| [r[:email], r] }
        key_for = {}
        (c[:students] || []).each do |st|
            key_for[st.email] = st.matched_by ? st.email : Main.datenpflege_student_key(st)
        end
        changes = {}
        c[:changed].each { |_, n, ch| changes[n[:email]] = ch.reject { |what, _, _| what == 'Klasse' } }
        moved = c[:moved].to_h { |o, n| [n[:email], o[:email]] }
        moved_away = moved.values.to_set
        view = Hash.new { |h, k| h[k] = { :students => [], :leaving => [] } }
        c[:new_records].each do |r|
            next unless schuelerliste_klassen_all.include?(r[:klasse])
            old = old_by[r[:email]] || old_by[moved[r[:email]]]
            view[r[:klasse]][:students] << {
                :key => key_for[r[:email]] || r[:email],
                :name => r[:display_name], :first_name => r[:first_name], :last_name => r[:last_name],
                :official_first_name => r[:official_first_name], :geschlecht => r[:geschlecht],
                :geburtstag => r[:geburtstag], :bildungsgang => r[:bildungsgang], :klasse => r[:klasse],
                :new => old.nil?, :from => (old && old[:klasse] != r[:klasse]) ? old[:klasse] : nil,
                :new_address => moved.include?(r[:email]),
                :changes => changes[r[:email]] || [],
            }
        end
        old_records.each do |o|
            next unless schuelerliste_klassen_all.include?(o[:klasse])
            n = new_by[o[:email]]
            next if n && n[:klasse] == o[:klasse]
            next if moved_away.include?(o[:email]) && new_by.values.any? { |x| moved[x[:email]] == o[:email] && x[:klasse] == o[:klasse] }
            to = n ? n[:klasse] : (moved_away.include?(o[:email]) ? new_by[moved.key(o[:email])]&.dig(:klasse) : nil)
            view[o[:klasse]][:leaving] << { :key => o[:email], :name => o[:display_name], :to => to }
        end
        view.each_value do |v|
            v[:students].sort_by! { |s| [s[:last_name].to_s, s[:first_name].to_s] }
            v[:leaving].sort_by! { |s| s[:name].to_s }
        end
        # a plain hash: looking up a class without students adds nothing
        {}.merge(view)
    end

    def schuelerliste_review_key(klasse)
        "klasse:#{klasse}"
    end

    # what a row shows: a check is only valid while this stays the same (a
    # new draft that changes the row asks again)
    def schuelerliste_values(entry)
        if entry.include?(:to) && !entry.include?(:geschlecht)
            { 'to' => entry[:to] }
        else
            { 'rufname' => entry[:first_name], 'nachname' => entry[:last_name], 'vornamen' => entry[:official_first_name],
              'geschlecht' => entry[:geschlecht], 'geburtstag' => entry[:geburtstag], 'klasse' => entry[:klasse],
              'bildungsgang' => entry[:bildungsgang] }
        end
    end

    def schuelerliste_entries(view, klasse)
        v = view[klasse] || { :students => [], :leaving => [] }
        (v[:students] + v[:leaving]).to_h { |e| [e[:key], e] }
    end

    def schuelerliste_check_valid?(check, entry)
        check && entry && check[:seen] == schuelerliste_values(entry).to_json
    end

    # klasse => keys of the students and the leaving ones (what may be checked)
    def schuelerliste_keys(view, klasse)
        v = view[klasse] || { :students => [], :leaving => [] }
        (v[:students] + v[:leaving]).map { |s| s[:key] }.to_set
    end

    def schuelerliste_state(klasse)
        review = schuelerliste_review_key(klasse)
        checks = neo4j_query("MATCH (c:StudentCheck {review: $review}) RETURN c;", :review => review).map { |x| x['c'] }
        missing = neo4j_query("MATCH (m:StudentMissing {review: $review}) RETURN m ORDER BY m.at;", :review => review).map { |x| x['m'] }
        confirmed = neo4j_query("MATCH (r:StudentReview {review: $review}) RETURN r;", :review => review).map { |x| x['r'] }.first
        {
            :checks => checks.to_h { |c| [c[:student], c.to_h.merge(:fields => (JSON.parse(c[:fields] || '{}') rescue {}))] },
            :missing => missing,
            :confirmed => confirmed && confirmed[:confirmed_at] ? confirmed : nil,
        }
    end

    def schuelerliste_assert_klasse(klasse)
        assert(klasse.is_a?(String) && schuelerliste_klassen_for_user.include?(klasse), 'not your class')
    end

    post '/api/schuelerliste/check' do
        require_teacher_or_data_manager_for_schuelerliste!
        data = parse_request_data(:required_keys => [:klasse, :student, :status],
                                  :optional_keys => [:fields, :text, :gone, :gone_since, :dashboard_only],
                                  :types => { :fields => Hash, :gone => Object, :dashboard_only => Array },
                                  :max_value_lengths => { :text => 1000, :student => 200, :gone_since => 10 },
                                  :max_body_length => 16384)
        klasse = data[:klasse]
        schuelerliste_assert_klasse(klasse)
        view = schuelerliste_view
        assert(view && !view[:errors], 'no draft')
        assert(schuelerliste_keys(view, klasse).include?(data[:student]), 'not in this class')
        assert(['ok', 'correction', 'open'].include?(data[:status]))
        review = schuelerliste_review_key(klasse)
        if data[:status] == 'open'
            neo4j_query("MATCH (c:StudentCheck {review: $review, student: $student}) DELETE c;", :review => review, :student => data[:student])
        else
            fields = {}
            if data[:status] == 'correction'
                (data[:fields] || {}).each do |k, v|
                    k = k.to_s
                    next unless SCHUELERLISTE_FIELDS.include?(k) && v.is_a?(String)
                    v = v.strip
                    fields[k] = v[0, 100] unless v.empty?
                end
                assert(fields['geschlecht'].nil? || Parser::OVERRIDE_GENDERS.include?(fields['geschlecht']))
                assert(fields['geburtstag'].nil? || datenpflege_valid_date(fields['geburtstag']))
                assert(fields['klasse'].nil? || KLASSEN_ORDER.include?(fields['klasse']))
            end
            gone = data[:status] == 'correction' && data[:gone] == true
            gone_since = gone && datenpflege_valid_date(data[:gone_since].to_s) ? data[:gone_since] : nil
            dashboard_only = ((data[:dashboard_only] || []).map(&:to_s) & SCHUELERLISTE_DASHBOARD_ONLY) & fields.keys
            text = (data[:text] || '').strip
            assert(data[:status] == 'ok' || !fields.empty? || gone || !text.empty?, 'empty correction')
            seen = schuelerliste_values(schuelerliste_entries(view, klasse)[data[:student]]).to_json
            values = { :review => review, :student => data[:student], :status => data[:status],
                       :fields => fields.to_json, :text => text, :gone => gone, :gone_since => gone_since,
                       :dashboard_only => dashboard_only, :by => @session_user[:email], :at => Time.now.to_i,
                       :seen => seen }
            neo4j_query(<<~END_OF_QUERY, values)
                MERGE (c:StudentCheck {review: $review, student: $student})
                SET c.status = $status, c.fields = $fields, c.text = $text, c.gone = $gone,
                    c.gone_since = $gone_since, c.dashboard_only = $dashboard_only, c.by = $by, c.at = $at,
                    c.seen = $seen, c.done = false;
            END_OF_QUERY
        end
        # a change reopens a confirmed list
        neo4j_query("MATCH (r:StudentReview {review: $review}) DELETE r;", :review => review)
        respond(:ok => true)
    end

    post '/api/schuelerliste/missing' do
        require_teacher_or_data_manager_for_schuelerliste!
        data = parse_request_data(:required_keys => [:klasse, :name], :optional_keys => [:note],
                                  :max_value_lengths => { :name => 100, :note => 1000 })
        schuelerliste_assert_klasse(data[:klasse])
        name = data[:name].strip
        assert(!name.empty?, 'no name')
        review = schuelerliste_review_key(data[:klasse])
        values = { :id => RandomTag.generate(12), :review => review, :name => name,
                   :note => (data[:note] || '').strip, :by => @session_user[:email], :at => Time.now.to_i }
        neo4j_query(<<~END_OF_QUERY, values)
            CREATE (:StudentMissing {id: $id, review: $review, name: $name, note: $note, by: $by, at: $at});
        END_OF_QUERY
        neo4j_query("MATCH (r:StudentReview {review: $review}) DELETE r;", :review => review)
        respond(:ok => true)
    end

    post '/api/schuelerliste/missing/delete' do
        require_teacher_or_data_manager_for_schuelerliste!
        data = parse_request_data(:required_keys => [:klasse, :id])
        schuelerliste_assert_klasse(data[:klasse])
        review = schuelerliste_review_key(data[:klasse])
        neo4j_query("MATCH (m:StudentMissing {id: $id, review: $review}) DELETE m;", :id => data[:id], :review => review)
        neo4j_query("MATCH (r:StudentReview {review: $review}) DELETE r;", :review => review)
        respond(:ok => true)
    end

    post '/api/schuelerliste/confirm' do
        require_teacher_or_data_manager_for_schuelerliste!
        data = parse_request_data(:required_keys => [:klasse, :confirmed], :types => { :confirmed => Object })
        klasse = data[:klasse]
        schuelerliste_assert_klasse(klasse)
        review = schuelerliste_review_key(klasse)
        if data[:confirmed] == true
            view = schuelerliste_view
            assert(view && !view[:errors], 'no draft')
            checks = schuelerliste_state(klasse)[:checks]
            open = schuelerliste_entries(view, klasse).reject { |key, e| schuelerliste_check_valid?(checks[key], e) }
            unless open.empty?
                respond(:ok => false, :message => "Es sind noch #{open.size} Zeilen nicht geprüft.")
                return
            end
            neo4j_query(<<~END_OF_QUERY, :review => review, :by => @session_user[:email], :at => Time.now.to_i, :draft => view[:draft])
                MERGE (r:StudentReview {review: $review})
                SET r.confirmed_at = $at, r.confirmed_by = $by, r.draft = $draft;
            END_OF_QUERY
        else
            neo4j_query("MATCH (r:StudentReview {review: $review}) DELETE r;", :review => review)
        end
        respond(:ok => true)
    end

    # everything about the check goes (after the switch; personal data)
    def schuelerliste_reset!
        neo4j_query("MATCH (n) WHERE n:StudentCheck OR n:StudentMissing OR n:StudentReview OR n:StudentReviewSeen OR n:StudentReviewNotice DETACH DELETE n;")
    end

    post '/api/schuelerliste/reset' do
        require_data_manager!
        schuelerliste_reset!
        respond(:ok => true)
    end

    # ---------- the Datenpflege's view on /datenpflege ----------

    # the classes of the draft that are checked, with their Klassenleitungen
    def schuelerliste_klassen_in(view)
        schuelerliste_klassen_all.select { |k| view[k] && !(view[k][:students].empty? && view[k][:leaving].empty?) }
    end

    def schuelerliste_teachers(klasse)
        (@@klassenleiter[klasse] || []).filter_map { |sh| @@shorthands[sh] }
    end

    # klasse => {:total, :checked, :corrections, :confirmed, :opened, :notified}
    def schuelerliste_overview(view)
        seen = neo4j_query("MATCH (s:StudentReviewSeen) RETURN s;").map { |x| x['s'] }.to_h { |x| [x[:review], x] }
        notices = neo4j_query("MATCH (n:StudentReviewNotice) RETURN n;").map { |x| x['n'] }.to_h { |x| [x[:review], x] }
        schuelerliste_klassen_in(view).to_h do |klasse|
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            checked = entries.count { |key, e| schuelerliste_check_valid?(state[:checks][key], e) }
            review = schuelerliste_review_key(klasse)
            [klasse, {
                :total => entries.size, :checked => checked,
                :corrections => state[:checks].values.count { |c| c[:status] == 'correction' } + state[:missing].size,
                :confirmed => state[:confirmed] && checked == entries.size ? state[:confirmed] : nil,
                :opened => seen[review], :notified => notices[review],
            }]
        end
    end

    # a correction that arrived: the draft now has the proposed values (in
    # LUSD, or as an override for »nur im Dashboard«), a student marked as
    # gone is no longer in the list, a missing one is there
    def schuelerliste_arrived?(view, klasse, check)
        all = view.values.select { |v| v.is_a?(Hash) && v[:students] }.flat_map { |v| v[:students] }
        entry = all.find { |e| e[:key] == check[:student] }
        if check[:gone]
            return entry.nil?
        end
        return false if check[:fields].empty?
        return false unless entry
        values = schuelerliste_values(entry)
        overrides = Parser.schueler_overrides[check[:student]] || {}
        check[:fields].all? do |field, value|
            if (check[:dashboard_only] || []).include?(field)
                overrides[field].to_s == value
            else
                values[field].to_s == value
            end
        end
    end

    def schuelerliste_missing_arrived?(view, klasse, missing)
        words = remove_accents(missing[:name].to_s.downcase).split(/[\s,]+/).reject(&:empty?)
        return false if words.empty?
        (view[klasse] || { :students => [] })[:students].any? do |e|
            name = remove_accents("#{e[:name]} #{e[:official_first_name]} #{e[:last_name]}".downcase)
            words.all? { |w| name.include?(w) }
        end
    end

    post '/api/schuelerliste/done' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:review, :done], :optional_keys => [:student, :missing],
                                  :types => { :done => Object }, :max_value_lengths => { :review => 64, :student => 200, :missing => 64 })
        assert([true, false].include?(data[:done]))
        if data[:missing]
            neo4j_query("MATCH (m:StudentMissing {review: $review, id: $id}) SET m.done = $done;", :review => data[:review], :id => data[:missing], :done => data[:done])
        else
            neo4j_query("MATCH (c:StudentCheck {review: $review, student: $student}) SET c.done = $done;", :review => data[:review], :student => data[:student].to_s, :done => data[:done])
        end
        respond(:ok => true)
    end

    def schuelerliste_set_released(flag)
        draft = datenpflege_draft
        assert(draft, 'no draft')
        datenpflege_save_draft(draft.merge('released' => flag))
    end

    post '/api/schuelerliste/release' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:released], :types => { :released => Object })
        assert([true, false].include?(data[:released]))
        schuelerliste_set_released(data[:released])
        respond(:ok => true)
    end

    # a mail to the Klassenleitungen of the classes not confirmed yet (one per
    # person, with all their classes)
    post '/api/schuelerliste/notify' do
        require_data_manager!
        data = parse_request_data(:optional_keys => [:deadline], :max_value_lengths => { :deadline => 10 })
        deadline = datenpflege_valid_date(data[:deadline].to_s)
        view = schuelerliste_view
        assert(view && !view[:errors], 'no draft')
        # the mail releases the draft for the Klassenleitungen
        schuelerliste_set_released(true)
        overview = schuelerliste_overview(view)
        open = overview.reject { |_, o| o[:confirmed] }.keys
        by_teacher = Hash.new { |h, k| h[k] = [] }
        open.each { |klasse| schuelerliste_teachers(klasse).each { |email| by_teacher[email] << klasse } }
        sender = @session_user[:display_name] || @session_user[:email]
        by_teacher.each_pair do |email, klassen|
            teacher = @@user_info[email] || {}
            links = klassen.map { |k| "Klasse #{tr_klasse(k)}: #{WEB_ROOT}/schuelerliste?klasse=#{CGI.escape(k)}" }
            body = <<~END_OF_TEXT
                Hallo #{teacher[:first_name] || teacher[:display_name]},

                wir bereiten eine neue Schülerliste aus der Schulverwaltung (LUSD) vor. Bevor sie ins Dashboard kommt, prüf bitte, ob für #{klassen.size == 1 ? 'deine Klasse' : 'deine Klassen'} alles stimmt: Namen, Geschlecht, Geburtstag, Bildungsgang, wer neu dazukommt und wer geht.

                #{links.join("
")}

                Für jede Schülerin und jeden Schüler genügt »Stimmt« oder eine kurze Korrektur, zum Schluss »Liste bestätigen«.#{deadline ? " Bitte bis #{deadline.strftime('%d.%m.%Y')}." : ''}

                Viele Grüße
                #{sender}
            END_OF_TEXT
            subject_text = 'Bitte prüf die neue Schülerliste deiner Klasse'
            reply = @session_user[:email]
            deliver_mail(body) do
                to email
                from SMTP_FROM
                reply_to reply
                subject subject_text
            end
        end
        open.each do |klasse|
            next if schuelerliste_teachers(klasse).empty?
            neo4j_query(<<~END_OF_QUERY, :review => schuelerliste_review_key(klasse), :at => Time.now.to_i)
                MERGE (n:StudentReviewNotice {review: $review})
                SET n.at = $at, n.count = coalesce(n.count, 0) + 1;
            END_OF_QUERY
        end
        respond(:ok => true, :sent => by_teacher.size, :without => open.count { |k| schuelerliste_teachers(k).empty? })
    end

    def print_schuelerliste_overview
        view = schuelerliste_view
        return '' if view.nil? || view[:errors]
        overview = schuelerliste_overview(view)
        return '' if overview.empty?
        fmt = ->(ts) { ts ? Time.at(ts).strftime('%d.%m.%Y') : '' }
        StringIO.open do |io|
            io.puts "<div class='dp-review'>"
            io.puts "<h5>Prüfung durch die Klassenleitungen</h5>"
            confirmed = overview.count { |_, o| o[:confirmed] }
            if schuelerliste_released?
                io.puts "<p class='dp-release'><strong>Für die Klassenleitungen freigegeben:</strong> sie sehen ihre Klasse, wie sie im Entwurf steht, unter <a href='/schuelerliste'>/schuelerliste</a> und im Menü. #{confirmed} von #{overview.size} Klassen bestätigt. <button type='button' class='btn btn-secondary btn-sm' id='bu_sl_release' data-released='false'>Freigabe zurücknehmen</button></p>"
            else
                io.puts "<p class='dp-release'><strong>Noch nicht freigegeben:</strong> nur die Datenpflege sieht den Entwurf (<a href='/schuelerliste'>so sehen ihn die Klassenleitungen</a>). Freigegeben wird er mit der ersten Mail oder hier. <button type='button' class='btn btn-secondary btn-sm' id='bu_sl_release' data-released='true'>Für Klassenleitungen freigeben</button></p>"
            end
            io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-review-list'><thead><tr><th>Klasse</th><th>Klassenleitung</th><th>Geprüft</th><th>Korrekturen</th><th>Stand</th><th>Benachrichtigt</th></tr></thead><tbody>"
            overview.each_pair do |klasse, o|
                names = schuelerliste_teachers(klasse).map { |e| (@@user_info[e] || {})[:display_last_name] || e }
                status = if o[:confirmed] then "bestätigt am #{fmt.(o[:confirmed][:confirmed_at])}"
                         elsif o[:opened] then "geöffnet am #{fmt.(o[:opened][:last_at])}"
                         else 'noch nicht geöffnet' end
                io.puts "<tr data-klasse='#{sl_h(klasse)}'><td><a href='/schuelerliste?klasse=#{CGI.escape(klasse)}'>#{sl_h(tr_klasse(klasse))}</a></td>"
                io.puts "<td>#{names.empty? ? "<span class='text-danger'>keine</span>" : sl_h(names.join(', '))}</td>"
                io.puts "<td>#{o[:checked]} von #{o[:total]}</td><td>#{o[:corrections]}</td><td class='dp-review-status'>#{sl_h(status)}</td>"
                io.puts "<td>#{o[:notified] ? "#{fmt.(o[:notified][:at])}#{o[:notified][:count].to_i > 1 ? " (#{o[:notified][:count]}×)" : ''}" : ''}</td></tr>"
            end
            io.puts "</tbody></table></div>"
            open = overview.reject { |_, o| o[:confirmed] }.size
            if open > 0
                io.puts "<div class='dp-notify'><label for='ti_sl_deadline'>Bitte bis (optional)</label> <input type='date' class='form-control' id='ti_sl_deadline'> <button type='button' class='btn btn-secondary' id='bu_sl_notify' data-count='#{open}'>Klassenleitungen benachrichtigen</button></div>"
                io.puts "<p class='text-muted'>Schickt eine Mail mit dem Link an die Klassenleitung#{open == 1 ? ' der Klasse, die' : "en der #{open} Klassen, die"} noch nicht bestätigt #{open == 1 ? 'hat' : 'haben'} – noch einmal gedrückt, ist es eine Erinnerung.</p>"
            end
            schuelerliste_corrections_html(io, view)
            io.puts "</div>"
            io.string
        end
    end

    def schuelerliste_corrections_html(io, view)
        rows = []
        schuelerliste_klassen_in(view).each do |klasse|
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            state[:checks].each_value do |c|
                next unless c[:status] == 'correction'
                entry = entries[c[:student]]
                arrived = schuelerliste_arrived?(view, klasse, c)
                rows << { :klasse => klasse, :review => c[:review], :student => c[:student], :name => entry ? entry[:name] : c[:student],
                          :what => schuelerliste_correction_text(c), :by => c[:by], :at => c[:at],
                          :arrived => arrived, :done => c[:done] == true,
                          :override => (c[:dashboard_only] || []).any? && c[:student].to_s.include?('@') && !arrived ? c : nil }
            end
            state[:missing].each do |m|
                rows << { :klasse => klasse, :review => m[:review], :missing => m[:id], :name => m[:name],
                          :what => "fehlt#{m[:note].to_s.empty? ? '' : ": #{sl_h(m[:note])}"}", :by => m[:by], :at => m[:at],
                          :arrived => schuelerliste_missing_arrived?(view, klasse, m), :done => m[:done] == true }
            end
        end
        return if rows.empty?
        open = rows.count { |r| !r[:arrived] && !r[:done] }
        io.puts "<h6 class='dp-corrections-title'>Korrekturen: #{open} offen von #{rows.size}</h6>"
        io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-corrections'><thead><tr><th>Klasse</th><th>Schüler:in</th><th>Korrektur</th><th>Von</th><th>Stand</th><th></th></tr></thead><tbody>"
        rows.sort_by { |r| [(r[:arrived] || r[:done]) ? 1 : 0, LusdImport.klasse_sort_key(r[:klasse].to_s), r[:name].to_s] }.each do |r|
            by = (@@user_info[r[:by]] || {})[:display_last_name] || r[:by]
            state = r[:arrived] ? 'angekommen' : (r[:done] ? 'erledigt' : 'offen')
            attrs = "data-review='#{sl_h(r[:review])}' #{r[:missing] ? "data-missing='#{sl_h(r[:missing])}'" : "data-student='#{sl_h(r[:student])}'"}"
            actions = []
            if r[:override]
                f = r[:override][:fields]
                actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_take_override' data-email='#{sl_h(r[:student])}' data-rufname='#{sl_h(f['rufname'])}' data-geschlecht='#{sl_h(f['geschlecht'])}'>Im Dashboard festlegen</button>"
            end
            unless r[:arrived]
                actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_done' #{attrs} data-done='#{r[:done] ? 'false' : 'true'}'>#{r[:done] ? 'Wieder offen' : 'Erledigt'}</button>"
            end
            io.puts "<tr class='dp-correction dp-correction-#{state}'><td>#{sl_h(tr_klasse(r[:klasse]))}</td><td>#{sl_h(r[:name])}</td><td style='white-space: normal;'>#{r[:what]}</td>"
            io.puts "<td>#{sl_h(by)}</td><td>#{state}</td><td class='dp-row-actions'>#{actions.join(' ')}</td></tr>"
        end
        io.puts "</tbody></table></div>"
    end

    def schuelerliste_correction_text(check)
        parts = check[:fields].map { |k, v| "#{SCHUELERLISTE_FIELD_LABELS[k]}: #{sl_h(k == 'geburtstag' ? sl_date(v) : v)}#{(check[:dashboard_only] || []).include?(k) ? ' (nur im Dashboard)' : ''}" }
        parts << "nicht mehr an der Schule#{check[:gone_since] ? " seit #{sl_date(check[:gone_since])}" : ''}" if check[:gone]
        parts << sl_h(check[:text]) unless check[:text].to_s.empty?
        parts.join('; ')
    end

    def require_teacher_or_data_manager_for_schuelerliste!
        assert(teacher_logged_in? || user_with_role_logged_in?(:can_manage_data))
    end

    def sl_h(s)
        CGI.escapeHTML(s.to_s)
    end

    def sl_date(iso)
        iso ? (Date.parse(iso).strftime('%d.%m.%Y') rescue iso) : ''
    end

    def print_schuelerliste(klasse_param)
        klassen = schuelerliste_klassen_for_user
        StringIO.open do |io|
            unless user_with_role_logged_in?(:can_manage_data) || schuelerliste_released?
                io.puts "<p class='sl-none'>Gerade gibt es keine neue Schülerliste zu prüfen.</p>"
                return io.string
            end
            if klassen.empty?
                io.puts "<p>Hier prüfen Klassenleitungen die neue Schülerliste ihrer Klasse. Du hast keine Klasse, die du prüfen kannst.</p>"
                return io.string
            end
            view = schuelerliste_view
            if view.nil?
                io.puts "<p class='sl-none'>Gerade gibt es keine neue Schülerliste zu prüfen.</p>"
                return io.string
            end
            if view[:errors]
                io.puts "<p class='sl-none'>Die neue Schülerliste wird gerade noch vorbereitet. Bitte schau später noch einmal.</p>"
                return io.string
            end
            klasse = klassen.include?(klasse_param) ? klasse_param : klassen.first
            if klassen.size > 1
                io.puts "<div class='sl-klassen'><label for='sl_klasse'>Klasse</label> <select class='form-control' id='sl_klasse'>"
                klassen.each { |k| io.puts "<option value='#{sl_h(k)}'#{k == klasse ? ' selected' : ''}>#{sl_h(tr_klasse(k))}</option>" }
                io.puts "</select></div>"
            end
            v = view[klasse] || { :students => [], :leaving => [] }
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            keys = entries.keys.to_set
            valid = ->(key) { schuelerliste_check_valid?(state[:checks][key], entries[key]) }
            done = keys.count { |k| valid.(k) }
            # the overview on /datenpflege: opened by the Klassenleitung
            if (@@klassenleiter[klasse] || []).include?(@session_user[:shorthand])
                neo4j_query(<<~END_OF_QUERY, :review => schuelerliste_review_key(klasse), :at => Time.now.to_i)
                    MERGE (s:StudentReviewSeen {review: $review})
                    ON CREATE SET s.first_at = $at
                    SET s.last_at = $at;
                END_OF_QUERY
            end
            io.puts "<div class='sl-class' data-klasse='#{sl_h(klasse)}'>"
            io.puts "<h3>Klasse #{sl_h(tr_klasse(klasse))}</h3>"
            io.puts "<p class='sl-intro'>So steht deine Klasse in der neuen Liste aus der Schulverwaltung (LUSD). Bitte prüfe jede Zeile: »Stimmt«, wenn alles richtig ist, sonst »Korrigieren«. Fehlt jemand, trag es unten ein. Zum Schluss »Liste bestätigen«. Im Dashboard ändert sich erst etwas, wenn die Liste übernommen wird.</p>"
            io.puts "<p class='sl-progress'><strong>#{done}</strong> von <strong>#{keys.size}</strong> geprüft</p>"
            io.puts "<p class='sl-legend'><span class='sl-badge sl-badge-added'>+ neu</span> kommt dazu <span class='sl-badge sl-badge-removed'>− geht</span> verlässt die Klasse <span class='dp-old'>bisher</span> <span class='dp-new'>neu</span> geändert</p>"
            io.puts "<div class='sl-scroll'><table class='table sl-table'><thead><tr><th>Name</th><th>Geschlecht</th><th>Geburtstag</th><th>Bildungsgang</th><th></th></tr></thead><tbody>"
            gender = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }
            v[:students].each do |s|
                # the changes against today in their column, like a diff: the
                # old value struck through on red, the new one on green
                ch = s[:changes].to_h { |what, from, to| [what, [from, to]] }
                diff = ->(from, to) { datenpflege_word_diff(from, to) }
                name_html = if ch['Name'] then diff.(*ch['Name'])
                            elsif ch['Rufname'] then diff.("#{ch['Rufname'][0]} #{s[:last_name]}", s[:name])
                            else sl_h(s[:name]) end
                official = if ch['Vornamen'] then "<div class='sl-official'>Vornamen: #{diff.(*ch['Vornamen'])}</div>"
                           elsif s[:official_first_name] != s[:first_name] then "<div class='sl-official'>Vornamen: #{sl_h(s[:official_first_name])}</div>"
                           else '' end
                badges = []
                badges << "<span class='sl-badge sl-badge-added'>+ neu</span>" if s[:new] && !s[:new_address]
                badges << "<span class='sl-badge sl-badge-added'>+ aus #{sl_h(tr_klasse(s[:from]))}</span>" if s[:from]
                badges << "<span class='sl-badge'>neue Adresse</span>" if s[:new_address]
                g = ->(x) { gender[x] || x }
                gender_html = ch['Geschlecht'] ? diff.(g.(ch['Geschlecht'][0]), g.(ch['Geschlecht'][1])) : sl_h(g.(s[:geschlecht]))
                birthday_html = ch['Geburtstag'] ? diff.(*ch['Geburtstag']) : sl_h(sl_date(s[:geburtstag]))
                bildungsgang_html = ch['Bildungsgang'] ? diff.(*ch['Bildungsgang']) : sl_h(Main.tr_bildungsgang(s[:bildungsgang]))
                row_class = (s[:new] || s[:from]) ? 'sl-row-added' : (ch.empty? ? '' : 'sl-row-changed')
                io.puts "<tr class='sl-row #{row_class}' data-student='#{sl_h(s[:key])}' data-values='#{sl_h({ 'rufname' => s[:first_name], 'nachname' => s[:last_name], 'vornamen' => s[:official_first_name], 'geschlecht' => s[:geschlecht], 'geburtstag' => s[:geburtstag], 'klasse' => s[:klasse], 'bildungsgang' => s[:bildungsgang] }.to_json)}'>"
                io.puts "<td><div class='sl-name'>#{name_html}</div>#{official}#{badges.empty? ? '' : "<div class='sl-badges'>#{badges.join(' ')}</div>"}</td>"
                io.puts "<td>#{gender_html}</td><td>#{birthday_html}</td><td>#{bildungsgang_html}</td>"
                io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]], valid.(s[:key]))}</td></tr>"
            end
            io.puts "</tbody></table></div>"
            unless v[:leaving].empty?
                io.puts "<h4>Verlässt die Klasse</h4>"
                io.puts "<div class='sl-scroll'><table class='table sl-table sl-leaving'><tbody>"
                v[:leaving].each do |s|
                    where = s[:to] ? "− wechselt in die #{sl_h(tr_klasse(s[:to]))}" : '− steht nicht mehr in der Liste'
                    io.puts "<tr class='sl-row sl-row-removed' data-student='#{sl_h(s[:key])}' data-leaving='1' data-values='{}'><td><div class='sl-name'><span class='dp-old'>#{sl_h(s[:name])}</span></div><div class='sl-badges'><span class='sl-badge sl-badge-removed'>#{where}</span></div></td>"
                    io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]], valid.(s[:key]))}</td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<h4>Fehlt jemand?</h4>"
            unless state[:missing].empty?
                io.puts "<ul class='sl-missing'>"
                state[:missing].each do |m|
                    io.puts "<li><span><strong>#{sl_h(m[:name])}</strong>#{m[:note].to_s.empty? ? '' : " – #{sl_h(m[:note])}"}</span> <button type='button' class='btn btn-link btn-sm bu_sl_missing_delete' data-id='#{sl_h(m[:id])}'>Entfernen</button></li>"
                end
                io.puts "</ul>"
            end
            io.puts "<div class='sl-missing-form'><input class='form-control' id='ti_sl_missing_name' maxlength='100' placeholder='Vor- und Nachname'><input class='form-control' id='ti_sl_missing_note' maxlength='1000' placeholder='Hinweis (optional)'><button type='button' class='btn btn-secondary' id='bu_sl_missing'>Eintragen</button></div>"
            io.puts "<div class='sl-confirm'>"
            if state[:confirmed] && done < keys.size
                io.puts "<p class='sl-changed'>Seit deiner Bestätigung hat sich die Liste geändert. Bitte prüf die markierten Zeilen noch einmal und bestätige dann erneut.</p>"
            end
            if state[:confirmed] && done == keys.size
                by = (@@user_info[state[:confirmed][:confirmed_by]] || {})[:display_name] || state[:confirmed][:confirmed_by]
                io.puts "<p class='sl-confirmed'><i class='fa fa-check'></i> Bestätigt am #{Time.at(state[:confirmed][:confirmed_at]).strftime('%d.%m.%Y')} von #{sl_h(by)}.</p>"
                io.puts "<button type='button' class='btn btn-secondary' id='bu_sl_unconfirm'>Ändern</button>"
            else
                open = keys.size - done
                io.puts "<p class='text-muted'>#{open > 0 ? "Noch #{open} #{open == 1 ? 'Zeile' : 'Zeilen'} zu prüfen." : 'Alles geprüft.'}</p>"
                io.puts "<button type='button' class='btn btn-success' id='bu_sl_confirm'#{open > 0 ? ' disabled' : ''}>Liste bestätigen</button>"
            end
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    def schuelerliste_status_html(check, valid = true)
        if check.nil? || !valid
            changed = check ? "<div class='sl-changed-row'>geändert seit deiner Prüfung</div>" : ''
            "#{changed}<button type='button' class='btn btn-secondary btn-sm bu_sl_ok'>Stimmt</button> <button type='button' class='btn btn-secondary btn-sm bu_sl_correct'>Korrigieren…</button>"
        elsif check[:status] == 'ok'
            "<span class='sl-done'><i class='fa fa-check'></i> stimmt</span> <button type='button' class='btn btn-link btn-sm bu_sl_reopen'>Ändern</button>"
        else
            "<span class='sl-corrected'>Korrektur: #{schuelerliste_correction_text(check)}</span> <button type='button' class='btn btn-link btn-sm bu_sl_correct' data-check='#{sl_h({ 'fields' => check[:fields], 'text' => check[:text], 'gone' => check[:gone], 'gone_since' => check[:gone_since], 'dashboard_only' => check[:dashboard_only] || [] }.to_json)}'>Ändern</button>"
        end
    end
end
