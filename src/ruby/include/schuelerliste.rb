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

    # the classes this person may check
    def schuelerliste_klassen_for_user
        return schuelerliste_klassen_all if user_with_role_logged_in?(:can_manage_data)
        return [] unless teacher_logged_in?
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
            values = { :review => review, :student => data[:student], :status => data[:status],
                       :fields => fields.to_json, :text => text, :gone => gone, :gone_since => gone_since,
                       :dashboard_only => dashboard_only, :by => @session_user[:email], :at => Time.now.to_i }
            neo4j_query(<<~END_OF_QUERY, values)
                MERGE (c:StudentCheck {review: $review, student: $student})
                SET c.status = $status, c.fields = $fields, c.text = $text, c.gone = $gone,
                    c.gone_since = $gone_since, c.dashboard_only = $dashboard_only, c.by = $by, c.at = $at;
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
            open = schuelerliste_keys(view, klasse) - schuelerliste_state(klasse)[:checks].keys
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
    post '/api/schuelerliste/reset' do
        require_data_manager!
        neo4j_query("MATCH (n) WHERE n:StudentCheck OR n:StudentMissing OR n:StudentReview DETACH DELETE n;")
        respond(:ok => true)
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
            keys = schuelerliste_keys(view, klasse)
            done = (keys & state[:checks].keys.to_set).size
            io.puts "<div class='sl-class' data-klasse='#{sl_h(klasse)}'>"
            io.puts "<h3>Klasse #{sl_h(tr_klasse(klasse))}</h3>"
            io.puts "<p class='sl-intro'>So steht deine Klasse in der neuen Liste aus der Schulverwaltung (LUSD). Bitte prüfe jede Zeile: »Stimmt«, wenn alles richtig ist, sonst »Korrigieren«. Fehlt jemand, trag es unten ein. Zum Schluss »Liste bestätigen«. Im Dashboard ändert sich erst etwas, wenn die Liste übernommen wird.</p>"
            io.puts "<p class='sl-progress'><strong>#{done}</strong> von <strong>#{keys.size}</strong> geprüft</p>"
            io.puts "<div class='sl-scroll'><table class='table sl-table'><thead><tr><th>Name</th><th>Geschlecht</th><th>Geburtstag</th><th>Bildungsgang</th><th></th></tr></thead><tbody>"
            gender = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }
            v[:students].each do |s|
                notes = []
                notes << 'neu' if s[:new] && !s[:new_address]
                notes << "kommt aus #{sl_h(tr_klasse(s[:from]))}" if s[:from]
                notes << 'bekommt eine neue Adresse' if s[:new_address]
                s[:changes].each do |what, from, to|
                    notes << "#{sl_h(what)}: bisher #{sl_h(from.to_s.empty? ? 'leer' : from)}"
                end
                official = s[:official_first_name] != s[:first_name] ? "<div class='sl-official'>Vornamen: #{sl_h(s[:official_first_name])}</div>" : ''
                io.puts "<tr class='sl-row' data-student='#{sl_h(s[:key])}' data-values='#{sl_h({ 'rufname' => s[:first_name], 'nachname' => s[:last_name], 'vornamen' => s[:official_first_name], 'geschlecht' => s[:geschlecht], 'geburtstag' => s[:geburtstag], 'klasse' => s[:klasse], 'bildungsgang' => s[:bildungsgang] }.to_json)}'>"
                io.puts "<td><div class='sl-name'>#{sl_h(s[:name])}</div>#{official}#{notes.empty? ? '' : "<div class='sl-notes'>#{notes.join(', ')}</div>"}</td>"
                io.puts "<td>#{sl_h(gender[s[:geschlecht]] || s[:geschlecht])}</td><td>#{sl_h(sl_date(s[:geburtstag]))}</td><td>#{sl_h(Main.tr_bildungsgang(s[:bildungsgang]))}</td>"
                io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]])}</td></tr>"
            end
            io.puts "</tbody></table></div>"
            unless v[:leaving].empty?
                io.puts "<h4>Verlässt die Klasse</h4>"
                io.puts "<div class='sl-scroll'><table class='table sl-table sl-leaving'><tbody>"
                v[:leaving].each do |s|
                    where = s[:to] ? "wechselt in die #{sl_h(tr_klasse(s[:to]))}" : 'steht nicht mehr in der Liste'
                    io.puts "<tr class='sl-row' data-student='#{sl_h(s[:key])}' data-leaving='1' data-values='{}'><td><div class='sl-name'>#{sl_h(s[:name])}</div><div class='sl-notes'>#{where}</div></td>"
                    io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]])}</td></tr>"
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
            if state[:confirmed]
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

    def schuelerliste_status_html(check)
        if check.nil?
            "<button type='button' class='btn btn-secondary btn-sm bu_sl_ok'>Stimmt</button> <button type='button' class='btn btn-secondary btn-sm bu_sl_correct'>Korrigieren…</button>"
        elsif check[:status] == 'ok'
            "<span class='sl-done'><i class='fa fa-check'></i> stimmt</span> <button type='button' class='btn btn-link btn-sm bu_sl_reopen'>Ändern</button>"
        else
            parts = check[:fields].map { |k, v| "#{SCHUELERLISTE_FIELD_LABELS[k]}: #{sl_h(k == 'geburtstag' ? sl_date(v) : v)}#{(check[:dashboard_only] || []).include?(k) ? ' (nur im Dashboard)' : ''}" }
            parts << "nicht mehr an der Schule#{check[:gone_since] ? " seit #{sl_date(check[:gone_since])}" : ''}" if check[:gone]
            parts << sl_h(check[:text]) unless check[:text].to_s.empty?
            "<span class='sl-corrected'>Korrektur: #{parts.join('; ')}</span> <button type='button' class='btn btn-link btn-sm bu_sl_correct' data-check='#{sl_h({ 'fields' => check[:fields], 'text' => check[:text], 'gone' => check[:gone], 'gone_since' => check[:gone_since], 'dashboard_only' => check[:dashboard_only] || [] }.to_json)}'>Ändern</button>"
        end
    end
end
