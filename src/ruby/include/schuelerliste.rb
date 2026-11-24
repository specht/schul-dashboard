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
#   (:StudentTutor {student, teacher, by, at})   who is a student's tutor in
#       11/12, marked by the LK teachers on their list; kept after the
#       switch (the dashboard has no other source yet, later for LUSD)
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

    OBERSTUFE = ['11', '12']

    # What is checked, and by whom: classes 5–10 by their Klassenleitungen;
    # in 11 and 12 there is no tutor data yet, so the teachers of a student's
    # Leistungskurse check (one of the two is the tutor) – a list per LK
    # ("lk:<lesson key>"). 11 and 12 themselves hold who is in no LK (new
    # students, for the Datenpflege).
    def schuelerliste_klassen_all
        KLASSEN_ORDER.reject { |k| OBERSTUFE.include?(k.to_s) } + schuelerliste_lk_groups +
            KLASSEN_ORDER.select { |k| OBERSTUFE.include?(k.to_s) }
    end

    # an LK: a course of 11/12 whose subject code is in capitals (EN_11, MA;
    # a GK is en_11), not a Zusatzkurs (ZK)
    def self.schuelerliste_lk_lesson?(info)
        return false unless ((info[:klassen] || []) & OBERSTUFE).any?
        code = (info[:orig_fach] || info[:fach]).to_s.split(/[_\s-]/).first.to_s
        !!(code =~ /\A[A-ZÄÖÜ]{2,}\z/) && code != 'ZK'
    end

    def schuelerliste_lk_groups
        (@@lessons[:lesson_keys] || {}).select { |key, info| Main.schuelerliste_lk_lesson?(info) && !(@@schueler_for_lesson[key] || []).empty? }
            .keys.map { |key| "lk:#{key}" }.sort_by { |g| schuelerliste_short(g) }
    end

    def schuelerliste_lk?(group)
        group.to_s.start_with?('lk:')
    end

    def schuelerliste_lesson(group)
        (@@lessons[:lesson_keys] || {})[group.to_s.sub('lk:', '')] || {}
    end

    # shorthands of who checks a list
    def schuelerliste_teacher_shorthands(group)
        return schuelerliste_lesson(group)[:lehrer] || [] if schuelerliste_lk?(group)
        return [] if OBERSTUFE.include?(group.to_s)
        @@klassenleiter[group] || []
    end

    # "5a", "LK Englisch (11)", "11 ohne LK"
    def schuelerliste_short(group)
        if schuelerliste_lk?(group)
            lesson = schuelerliste_lesson(group)
            "LK #{lesson[:pretty_folder_name] || lesson[:pretty_fach] || group.sub('lk:', '')}"
        elsif OBERSTUFE.include?(group.to_s)
            "#{tr_klasse(group)} ohne LK"
        else
            tr_klasse(group)
        end
    end

    # "Klasse 5a", "LK Englisch (11)", "Jahrgang 11 ohne LK"
    def schuelerliste_label(group)
        return schuelerliste_short(group) if schuelerliste_lk?(group)
        OBERSTUFE.include?(group.to_s) ? "Jahrgang #{schuelerliste_short(group)}" : "Klasse #{tr_klasse(group)}"
    end

    # the lists a teacher checks
    def schuelerliste_klassen_of_teacher(shorthand)
        schuelerliste_klassen_all.select { |g| schuelerliste_teacher_shorthands(g).include?(shorthand) }
    end

    SCHUELERLISTE_LK_NOTE = 'Für 11 und 12 gibt es noch keine Daten, wer Tutor:in ist. Deshalb prüfen die Lehrkräfte der Leistungskurse: Du siehst alle Schüler:innen deines LKs, auch die, deren Tutor:in du nicht bist. Eine der beiden LK-Lehrkräfte ist die Tutorin oder der Tutor; was die andere schon geprüft hat, ist hier auch abgehakt. Bitte hak in der Spalte »Tutor:in« deine Tutand:innen an – dann kennt das Dashboard sie künftig auch.'

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
        schuelerliste_klassen_of_teacher(@session_user[:shorthand])
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
                 (File.mtime(Parser::OVERRIDES_PATH).to_f rescue 0), (File.mtime(Parser::MANUAL_ADDED_PATH).to_f rescue 0),
                 (File.mtime(Parser::MANUAL_GONE_PATH).to_f rescue 0), Parser.schueler_path]
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
            next unless KLASSEN_ORDER.include?(r[:klasse])
            old = old_by[r[:email]] || old_by[moved[r[:email]]]
            # the names field by field, each in its column
            ch = (changes[r[:email]] || []).reject { |what, _, _| ['Name', 'Rufname', 'Vornamen'].include?(what) }
            if old
                [['Vornamen', :official_first_name], ['Rufname', :first_name], ['Nachname', :last_name]].each do |what, field|
                    shown = ->(rec) { field == :last_name ? Nachname.anzeige(rec[field]) : rec[field].to_s }
                    ch << [what, shown.(old), shown.(r)] if old[field].to_s != r[field].to_s
                end
            end
            view[r[:klasse]][:students] << {
                :key => key_for[r[:email]] || r[:email],
                :name => r[:display_name], :first_name => r[:first_name], :last_name => r[:last_name],
                :official_first_name => r[:official_first_name], :geschlecht => r[:geschlecht],
                :geburtstag => r[:geburtstag], :bildungsgang => r[:bildungsgang], :klasse => r[:klasse],
                :new => old.nil?, :from => (old && old[:klasse] != r[:klasse]) ? old[:klasse] : nil,
                :new_address => moved.include?(r[:email]),
                :changes => ch,
            }
        end
        old_records.each do |o|
            next unless KLASSEN_ORDER.include?(o[:klasse])
            n = new_by[o[:email]]
            next if n && n[:klasse] == o[:klasse]
            next if moved_away.include?(o[:email]) && new_by.values.any? { |x| moved[x[:email]] == o[:email] && x[:klasse] == o[:klasse] }
            to = n ? n[:klasse] : (moved_away.include?(o[:email]) ? new_by[moved.key(o[:email])]&.dig(:klasse) : nil)
            view[o[:klasse]][:leaving] << { :key => o[:email], :name => o[:display_name], :to => to }
        end
        # 11 and 12: a list per LK (its students by their address), the
        # rest stays in the year
        in_lk = Set.new
        schuelerliste_lk_groups.each do |g|
            members = Set.new(@@schueler_for_lesson[g.sub('lk:', '')] || [])
            v = { :students => [], :leaving => [] }
            OBERSTUFE.each do |k|
                next unless view.include?(k)
                v[:students] += view[k][:students].select { |s| members.include?(s[:key]) }
                v[:leaving] += view[k][:leaving].select { |s| members.include?(s[:key]) }
            end
            in_lk.merge((v[:students] + v[:leaving]).map { |s| s[:key] })
            view[g] = v unless v[:students].empty? && v[:leaving].empty?
        end
        OBERSTUFE.each do |k|
            next unless view.include?(k)
            view[k][:students].reject! { |s| in_lk.include?(s[:key]) }
            view[k][:leaving].reject! { |s| in_lk.include?(s[:key]) }
        end
        view.each_value do |v|
            v[:students].sort_by! { |s| [s[:last_name].to_s, s[:first_name].to_s] }
            v[:leaving].sort_by! { |s| s[:name].to_s }
        end
        # a plain hash: looking up a class without students adds nothing
        {}.merge(view)
    end

    def schuelerliste_review_key(klasse)
        schuelerliste_lk?(klasse) ? klasse : "klasse:#{klasse}"
    end

    # the checks of a student in 11/12 are shared by the LK lists (either
    # LK teacher may check); confirmations and missing students are per list
    def schuelerliste_check_review(klasse)
        schuelerliste_lk?(klasse) ? 'lk' : schuelerliste_review_key(klasse)
    end

    # what a row shows: a check is only valid while this stays the same (a
    # new draft that changes the row asks again)
    def schuelerliste_values(entry)
        if entry.include?(:to) && !entry.include?(:geschlecht)
            { 'to' => entry[:to] }
        else
            { 'rufname' => entry[:first_name], 'nachname' => Nachname.anzeige(entry[:last_name]), 'vornamen' => entry[:official_first_name],
              'geschlecht' => entry[:geschlecht], 'geburtstag' => entry[:geburtstag], 'klasse' => entry[:klasse],
              'bildungsgang' => entry[:bildungsgang] }
        end
    end

    def schuelerliste_entries(view, klasse)
        v = view[klasse] || { :students => [], :leaving => [] }
        (v[:students] + v[:leaving]).to_h { |e| [e[:key], e] }
    end

    def schuelerliste_check_valid?(check, entry)
        return false unless check && entry
        now = schuelerliste_values(entry)
        check[:seen] == now.to_json || schuelerliste_correction_taken?(check, now)
    end

    # a new export in which LUSD took over a correction exactly: what was
    # asked for has the proposed value, nothing else changed (a field kept
    # in the dashboard alone stays as LUSD had it) – that is no reason to
    # ask again
    def schuelerliste_correction_taken?(check, now)
        return false unless check[:status] == 'correction' && !check[:gone]
        fields = check[:fields] || {}
        lusd = fields.keys - (check[:dashboard_only] || [])
        return false if lusd.empty?
        seen = (JSON.parse(check[:seen].to_s) rescue nil)
        return false unless seen.is_a?(Hash) && seen.keys.sort == now.keys.sort
        now.all? { |k, v| lusd.include?(k) ? v.to_s == fields[k].to_s : v == seen[k] }
    end

    # klasse => keys of the students and the leaving ones (what may be checked)
    def schuelerliste_keys(view, klasse)
        v = view[klasse] || { :students => [], :leaving => [] }
        (v[:students] + v[:leaving]).map { |s| s[:key] }.to_set
    end

    # a row that needs a word of its own: new in the list, leaving it, or
    # changed against the dashboard. A row as the dashboard already has it
    # needs no »Stimmt«: confirming the list covers it (it can still be
    # corrected) – agreeing doesn't make it right, so it stays in the list
    def schuelerliste_needs_check?(entry)
        return true if entry.include?(:to) && !entry.include?(:geschlecht)
        !!(entry[:new] || entry[:from] || entry[:new_address] || !(entry[:changes] || []).empty?)
    end

    # [rows that need a check, the ones of them still open]
    def schuelerliste_progress(entries, checks)
        needed = entries.select { |_, e| schuelerliste_needs_check?(e) }
        [needed.keys, needed.reject { |key, e| schuelerliste_check_valid?(checks[key], e) }.keys]
    end

    def schuelerliste_state(klasse)
        review = schuelerliste_review_key(klasse)
        checks = neo4j_query("MATCH (c:StudentCheck {review: $review}) RETURN c;", :review => schuelerliste_check_review(klasse)).map { |x| x['c'] }
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
        review = schuelerliste_check_review(klasse)
        if data[:status] == 'open'
            neo4j_query("MATCH (c:StudentCheck {review: $review, student: $student}) DELETE c;", :review => review, :student => data[:student])
        else
            fields = {}
            if data[:status] == 'correction'
                (data[:fields] || {}).each do |k, v|
                    k = k.to_s
                    next unless SCHUELERLISTE_FIELDS.include?(k) && v.is_a?(String)
                    v = v.strip
                    # a particle in front, as everywhere it is shown (nachname.rb)
                    v = Nachname.anzeige(Nachname.intern(v)) if k == 'nachname'
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
                    c.seen = $seen, c.done = false, c.wontfix = null;
            END_OF_QUERY
        end
        # a change reopens a confirmed list (in 11/12 every LK list of the student)
        reviews = [schuelerliste_review_key(klasse)]
        if schuelerliste_lk?(klasse)
            reviews += schuelerliste_klassen_in(view).select { |g| schuelerliste_lk?(g) && schuelerliste_keys(view, g).include?(data[:student]) }.map { |g| schuelerliste_review_key(g) }
        end
        neo4j_query("MATCH (r:StudentReview) WHERE r.review IN $reviews DELETE r;", :reviews => reviews.uniq)
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
            _, open = schuelerliste_progress(schuelerliste_entries(view, klasse), checks)
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

    # ---------- tutors in 11/12 (StudentTutor) ----------

    # student address => addresses of the teachers who marked themselves
    def schuelerliste_tutors
        tutors = Hash.new { |h, k| h[k] = [] }
        neo4j_query("MATCH (t:StudentTutor) RETURN t.student AS student, t.teacher AS teacher ORDER BY t.at;").each do |row|
            tutors[row['student']] << row['teacher']
        end
        tutors
    end

    # a teacher of the LK marks (or unmarks) themselves as tutor
    def schuelerliste_tutor_marker?(klasse)
        schuelerliste_lk?(klasse) && teacher_logged_in? && schuelerliste_teacher_shorthands(klasse).include?(@session_user[:shorthand])
    end

    post '/api/schuelerliste/tutor' do
        require_teacher_or_data_manager_for_schuelerliste!
        data = parse_request_data(:required_keys => [:klasse, :student, :tutor], :types => { :tutor => Object },
                                  :max_value_lengths => { :student => 200 })
        assert([true, false].include?(data[:tutor]))
        klasse = data[:klasse]
        schuelerliste_assert_klasse(klasse)
        assert(schuelerliste_tutor_marker?(klasse), 'not a teacher of this LK')
        view = schuelerliste_view
        assert(view && !view[:errors], 'no draft')
        assert(data[:student].include?('@') && (view[klasse] || { :students => [] })[:students].any? { |e| e[:key] == data[:student] }, 'not in this LK')
        if data[:tutor]
            neo4j_query(<<~END_OF_QUERY, :student => data[:student], :teacher => @session_user[:email], :at => Time.now.to_i)
                MERGE (t:StudentTutor {student: $student, teacher: $teacher})
                ON CREATE SET t.by = $teacher, t.at = $at;
            END_OF_QUERY
        else
            neo4j_query("MATCH (t:StudentTutor {student: $student, teacher: $teacher}) DELETE t;", :student => data[:student], :teacher => @session_user[:email])
        end
        respond(:ok => true)
    end

    # the students of 11 and 12 today, with their tutors
    def schuelerliste_tutor_rows
        tutors = schuelerliste_tutors
        OBERSTUFE.flat_map { |k| @@schueler_for_klasse[k] || [] }.filter_map do |email|
            info = @@user_info[email]
            next unless info
            { :email => email, :klasse => info[:klasse], :last_name => info[:last_name].to_s,
              :first_names => (info[:official_first_name] || info[:first_name]).to_s, :name => info[:display_name].to_s,
              :geburtstag => info[:geburtstag], :tutors => tutors[email] }
        end.sort_by { |r| [r[:klasse].to_s, r[:last_name], r[:first_names]] }
    end

    def schuelerliste_teacher_name(email)
        info = @@user_info[email] || {}
        info[:display_last_name] || info[:display_name] || email
    end

    def print_schuelerliste_tutors
        rows = schuelerliste_tutor_rows
        return '' if rows.empty?
        known = rows.count { |r| !r[:tutors].empty? }
        double = rows.count { |r| r[:tutors].size > 1 }
        StringIO.open do |io|
            io.puts "<details class='dp-section dp-tutors'>"
            io.puts "<summary>Tutor:innen in 11 und 12: <strong class='dp-count'>#{known}</strong> von #{rows.size} angegeben#{double > 0 ? ", <span class='text-danger'>#{double} doppelt</span>" : ''}</summary>"
            io.puts "<p class='text-muted dp-hint'>Die Lehrkräfte der Leistungskurse haken auf ihrer Schülerliste ihre Tutand:innen an. Die Angaben bleiben nach der Übernahme der Liste erhalten. <a class='btn btn-secondary btn-sm' id='bu_tutors_csv' href='/api/datenpflege/tutoren.csv'>Als CSV herunterladen</a></p>"
            io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-tutor-list'><thead><tr><th>Jahrgang</th><th>Schüler:in</th><th>Tutor:in</th></tr></thead><tbody>"
            rows.each do |r|
                tutors = r[:tutors].map { |t| sl_h(schuelerliste_teacher_name(t)) }.join(', ')
                tutors = "<span class='text-muted'>noch offen</span>" if r[:tutors].empty?
                tutors += " <span class='text-danger'>(doppelt)</span>" if r[:tutors].size > 1
                io.puts "<tr data-email='#{sl_h(r[:email])}'><td>#{sl_h(tr_klasse(r[:klasse]))}</td><td>#{sl_h(r[:name])}</td><td>#{tutors}</td></tr>"
            end
            io.puts "</tbody></table></div>"
            io.puts "</details>"
            io.string
        end
    end

    # for LUSD: one line per student of 11/12, the tutor (or tutors) by
    # shorthand and name; »;« like the LUSD's own CSV, UTF-8 with BOM (Excel)
    get '/api/datenpflege/tutoren.csv' do
        require_data_manager!
        lines = [%w(Jahrgang Nachname Vornamen Geburtsdatum E-Mail Tutor:in-Kürzel Tutor:in)]
        schuelerliste_tutor_rows.each do |r|
            lines << [r[:klasse], Nachname.anzeige(r[:last_name]), r[:first_names], sl_date(r[:geburtstag]), r[:email],
                      r[:tutors].map { |t| (@@user_info[t] || {})[:shorthand] || '' }.join(', '),
                      r[:tutors].map { |t| schuelerliste_teacher_name(t) }.join(', ')]
        end
        # (no formulas when opened in a spreadsheet)
        cell = ->(x) { x = x.to_s.gsub(/[;\r\n"]/, ' '); x =~ /\A[=+\-@]/ ? "'#{x}" : x }
        csv = lines.map { |l| l.map(&cell).join(';') }.join("\r\n") + "\r\n"
        respond_raw_with_mimetype_and_filename("\uFEFF" + csv, 'text/csv; charset=utf-8', "tutorinnen-#{Date.today.strftime('%Y-%m-%d')}.csv")
    end

    # ---------- the Datenpflege's view on /datenpflege ----------

    # the classes of the draft that are checked, with their Klassenleitungen
    def schuelerliste_klassen_in(view)
        schuelerliste_klassen_all.select { |k| view[k] && !(view[k][:students].empty? && view[k][:leaving].empty?) }
    end

    def schuelerliste_teachers(klasse)
        schuelerliste_teacher_shorthands(klasse).filter_map { |sh| @@shorthands[sh] }
    end

    # klasse => {:total, :checked, :unchanged, :corrections, :confirmed, :opened, :notified}
    # (total and checked: the rows that need a check)
    def schuelerliste_overview(view)
        seen = neo4j_query("MATCH (s:StudentReviewSeen) RETURN s;").map { |x| x['s'] }.to_h { |x| [x[:review], x] }
        notices = neo4j_query("MATCH (n:StudentReviewNotice) RETURN n;").map { |x| x['n'] }.to_h { |x| [x[:review], x] }
        schuelerliste_klassen_in(view).to_h do |klasse|
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            needed, open = schuelerliste_progress(entries, state[:checks])
            review = schuelerliste_review_key(klasse)
            [klasse, {
                :total => needed.size, :checked => needed.size - open.size, :unchanged => entries.size - needed.size,
                :corrections => state[:checks].values.count { |c| c[:status] == 'correction' && (!schuelerliste_lk?(klasse) || entries.include?(c[:student])) } + state[:missing].size,
                :confirmed => state[:confirmed] && open.empty? ? state[:confirmed] : nil,
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
        # 11/12: someone new is in no LK yet – anywhere in the year
        groups = schuelerliste_lk?(klasse) || OBERSTUFE.include?(klasse.to_s) ?
            view.keys.select { |g| schuelerliste_lk?(g) || OBERSTUFE.include?(g.to_s) } : [klasse]
        groups.flat_map { |g| (view[g] || { :students => [] })[:students] }.any? do |e|
            name = remove_accents("#{e[:name]} #{e[:official_first_name]} #{Nachname.anzeige(e[:last_name])}".downcase)
            words.all? { |w| name.include?(w) }
        end
    end

    # the Datenpflege's to-do list: a correction done in LUSD, or one that
    # can't be done (with the reason, which the teacher sees), or open again
    post '/api/schuelerliste/done' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:review, :done], :optional_keys => [:student, :missing, :reason],
                                  :types => { :done => Object },
                                  :max_value_lengths => { :review => 64, :student => 200, :missing => 64, :reason => 300 })
        assert([true, false].include?(data[:done]))
        reason = data[:done] ? data[:reason].to_s.strip : ''
        values = { :review => data[:review], :done => data[:done], :wontfix => reason.empty? ? nil : reason,
                   :by => @session_user[:email], :at => Time.now.to_i }
        set = 'SET n.done = $done, n.wontfix = $wontfix, n.done_by = $by, n.done_at = $at'
        if data[:missing]
            neo4j_query("MATCH (n:StudentMissing {review: $review, id: $id}) #{set};", values.merge(:id => data[:missing]))
        else
            neo4j_query("MATCH (n:StudentCheck {review: $review, student: $student}) #{set};", values.merge(:student => data[:student].to_s))
        end
        respond(:ok => true)
    end

    # the start page's »Zu erledigen« (include/start_todo.rb): for a
    # Klassenleitung, the classes still to check or confirm – nil when there
    # is nothing (not released, all confirmed, no class)
    def start_page_schuelerliste_todo
        return nil unless teacher_logged_in? && schuelerliste_released?
        klassen = schuelerliste_klassen_of_teacher(@session_user[:shorthand])
        return nil if klassen.empty?
        view = schuelerliste_view
        return nil if view.nil? || view[:errors]
        open = klassen.filter_map do |k|
            entries = schuelerliste_entries(view, k)
            next if entries.empty?
            state = schuelerliste_state(k)
            needed, still = schuelerliste_progress(entries, state[:checks])
            next if state[:confirmed] && still.empty?
            { :klasse => k, :label => schuelerliste_label(k), :open => still.size, :total => needed.size }
        end
        return nil if open.empty?
        { :kind => 'schuelerliste', :key => 'schuelerliste', :klassen => open, :deadline => datenpflege_draft['deadline'] }
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
    # who gets a mail: the teachers of the lists not confirmed yet (list =>
    # teachers), and the lists without one
    def schuelerliste_notify_plan(view)
        open = schuelerliste_overview(view).reject { |_, o| o[:confirmed] }.keys
        by_teacher = Hash.new { |h, k| h[k] = [] }
        open.each { |klasse| schuelerliste_teachers(klasse).each { |email| by_teacher[email] << klasse } }
        { :open => open, :by_teacher => by_teacher, :without => open.count { |k| schuelerliste_teachers(k).empty? } }
    end

    # [subject, text] of the mail to one teacher
    # the mail's text as HTML: paragraphs, the addresses as links
    def schuelerliste_mail_html(text)
        text.strip.split(/\n{2,}/).map do |para|
            html = CGI.escapeHTML(para.strip).gsub(%r{https?://[^\s<]+}) { |u| "<a href=\"#{u}\">#{u}</a>" }.gsub("\n", "<br>\n")
            "<p>#{html}</p>"
        end.join("\n")
    end

    def schuelerliste_notify_mail(email, klassen, deadline)
        teacher = @@user_info[email] || {}
        name = teacher[:first_name] || teacher[:display_name]
        greeting = { 'w' => 'Liebe', 'm' => 'Lieber' }[teacher[:geschlecht]] || 'Hallo'
        links = klassen.map { |k| "#{schuelerliste_label(k)}: #{WEB_ROOT}/schuelerliste?klasse=#{CGI.escape(k)}" }
        lks = klassen.count { |k| schuelerliste_lk?(k) }
        classes = klassen.size - lks
        what = [classes > 0 ? (classes == 1 ? 'deine Klasse' : 'deine Klassen') : nil,
                lks > 0 ? (lks == 1 ? 'deinen Leistungskurs' : 'deine Leistungskurse') : nil].compact.join(' und ')
        lk_note = lks > 0 ? "\n#{SCHUELERLISTE_LK_NOTE}\n" : ''
        body = <<~END_OF_TEXT
            #{greeting} #{name},

            wir bereiten eine neue Schülerliste aus der Schulverwaltung (LUSD) vor. Bevor sie ins Dashboard kommt, prüf bitte, ob für #{what} alles stimmt: Namen, Geschlecht, Geburtstag, Bildungsgang, wer neu dazukommt und wer geht.
            #{lk_note}
            #{links.join("\n")}

            Nachname und Vornamen (alle, wie im Ausweis) stehen auf Zeugnissen und anderen amtlichen Dokumenten; mit dem Rufnamen erscheint die Schülerin oder der Schüler im Dashboard, auf Sitzplänen, in der Nextcloud und überall sonst im Schulalltag.

            Was sich gegenüber dem Dashboard geändert hat, ist markiert: dort genügt »Stimmt« oder eine kurze Korrektur. Die übrigen Zeilen bitte einmal durchsehen, zum Schluss »Liste bestätigen«.#{deadline ? " Bitte bis #{deadline.strftime('%d.%m.%Y')}." : ''}

            Falls du Fragen hast, schreib mir bitte.

            Danke und viele Grüße
            Micha
        END_OF_TEXT
        subject = classes > 0 && lks == 0 ? 'Bitte prüf die neue Schülerliste deiner Klasse' :
                  (classes == 0 ? 'Bitte prüf die neue Schülerliste deiner Leistungskurse' : 'Bitte prüf die neue Schülerliste deiner Klasse und Leistungskurse')
        [subject, body]
    end

    # the mails as they would go out, to look at before sending
    post '/api/schuelerliste/notify_preview' do
        require_data_manager!
        data = parse_request_data(:optional_keys => [:deadline], :max_value_lengths => { :deadline => 10 })
        deadline = datenpflege_valid_date(data[:deadline].to_s)
        view = schuelerliste_view
        assert(view && !view[:errors], 'no draft')
        plan = schuelerliste_notify_plan(view)
        mails = plan[:by_teacher].sort_by { |email, _| schuelerliste_teacher_name(email) }.map do |email, klassen|
            subject, body = schuelerliste_notify_mail(email, klassen, deadline)
            { :name => schuelerliste_teacher_name(email), :lists => klassen.map { |k| schuelerliste_short(k) }.join(', '),
              :subject => subject, :body => body }
        end
        respond(:ok => true, :mails => mails, :without => plan[:without])
    end

    post '/api/schuelerliste/notify' do
        require_data_manager!
        data = parse_request_data(:optional_keys => [:deadline], :max_value_lengths => { :deadline => 10 })
        deadline = datenpflege_valid_date(data[:deadline].to_s)
        view = schuelerliste_view
        assert(view && !view[:errors], 'no draft')
        # the mail releases the draft for the Klassenleitungen; its deadline
        # shows in their »Zu erledigen«
        schuelerliste_set_released(true)
        datenpflege_save_draft(datenpflege_draft.merge('deadline' => deadline.strftime('%Y-%m-%d'))) if deadline
        plan = schuelerliste_notify_plan(view)
        reply = @session_user[:email]
        plan[:by_teacher].each_pair do |email, klassen|
            subject_text, plain_text = schuelerliste_notify_mail(email, klassen, deadline)
            html_text = schuelerliste_mail_html(plain_text)
            # the text as written, and as HTML with links to click; answers
            # go to whoever sent it
            mail = Mail.new do
                to email
                from SMTP_FROM
                reply_to reply
                subject subject_text
                html_part do
                    content_type 'text/html; charset=UTF-8'
                    body html_text
                end
                text_part do
                    content_type 'text/plain; charset=UTF-8'
                    body plain_text
                end
            end
            deliver_with_development_guard!(mail)
        end
        plan[:open].each do |klasse|
            next if schuelerliste_teachers(klasse).empty?
            neo4j_query(<<~END_OF_QUERY, :review => schuelerliste_review_key(klasse), :at => Time.now.to_i)
                MERGE (n:StudentReviewNotice {review: $review})
                SET n.at = $at, n.count = coalesce(n.count, 0) + 1;
            END_OF_QUERY
        end
        respond(:ok => true, :sent => plan[:by_teacher].size, :without => plan[:without])
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
            io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-review-list'><thead><tr><th>Klasse / LK</th><th>Prüft</th><th>Geprüft</th><th>Korrekturen</th><th>Stand</th><th>Benachrichtigt</th></tr></thead><tbody>"
            overview.each_pair do |klasse, o|
                names = schuelerliste_teachers(klasse).map { |e| (@@user_info[e] || {})[:display_last_name] || e }
                status = if o[:confirmed] then "bestätigt am #{fmt.(o[:confirmed][:confirmed_at])}"
                         elsif o[:opened] then "geöffnet am #{fmt.(o[:opened][:last_at])}"
                         else 'noch nicht geöffnet' end
                io.puts "<tr data-klasse='#{sl_h(klasse)}'><td><a href='/schuelerliste?klasse=#{CGI.escape(klasse)}'>#{sl_h(schuelerliste_short(klasse))}</a></td>"
                io.puts "<td>#{names.empty? ? "<span class='text-danger'>keine</span>" : sl_h(names.join(', '))}</td>"
                same = o[:unchanged] > 0 ? "#{o[:unchanged]} unverändert" : ''
                checked = o[:total] > 0 ? "#{o[:checked]} von #{o[:total]}#{same.empty? ? '' : ", #{same}"}" : same
                io.puts "<td>#{checked}</td><td>#{o[:corrections]}</td><td class='dp-review-status'>#{sl_h(status)}</td>"
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
        # the checks in 11/12 are shared by the LK lists: each once, with the
        # first LK list that has the student (any, once they are gone)
        lks = schuelerliste_klassen_in(view).select { |g| schuelerliste_lk?(g) }
        lk_of = {}
        lks.each { |g| schuelerliste_keys(view, g).each { |key| lk_of[key] ||= g } }
        schuelerliste_klassen_in(view).each do |klasse|
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            state[:checks].each_value do |c|
                next unless c[:status] == 'correction'
                next if schuelerliste_lk?(klasse) && (lk_of[c[:student]] || lks.first) != klasse
                entry = entries[c[:student]]
                arrived = schuelerliste_arrived?(view, klasse, c)
                rows << { :klasse => klasse, :review => c[:review], :student => c[:student], :name => entry ? entry[:name] : c[:student],
                          :official => entry && entry[:last_name] ? [entry[:official_first_name], Nachname.anzeige(entry[:last_name])].compact.join(' ') : nil,
                          :geburtstag => entry && entry[:geburtstag],
                          :what => schuelerliste_correction_todo_text(c, entry), :by => c[:by], :at => c[:at],
                          :arrived => arrived, :done => c[:done] == true, :wontfix => c[:wontfix],
                          :override => (c[:dashboard_only] || []).any? && c[:student].to_s.include?('@') && !arrived ? c : nil,
                          # gone: at once in the dashboard, without waiting for LUSD
                          :gone_email => c[:gone] && !arrived && !c[:done] && @@user_info[c[:student]] ? c[:student] : nil,
                          :gone_since => c[:gone_since] }
            end
            state[:missing].each do |m|
                rows << { :klasse => klasse, :review => m[:review], :missing => m[:id], :name => m[:name], :note => m[:note],
                          :what => "fehlt#{m[:note].to_s.empty? ? '' : ": #{sl_h(m[:note])}"}", :by => m[:by], :at => m[:at],
                          :arrived => schuelerliste_missing_arrived?(view, klasse, m), :done => m[:done] == true, :wontfix => m[:wontfix] }
            end
        end
        return if rows.empty?
        open = rows.count { |r| !r[:arrived] && !r[:done] }
        io.puts "<h6 class='dp-corrections-title'>Korrekturen: #{open} offen von #{rows.size}</h6>"
        io.puts "<p class='text-muted dp-hint'>Die Liste zum Abarbeiten in der LUSD: »Erledigt«, wenn es dort korrigiert ist, »Geht nicht…« mit dem Grund, wenn nicht – die Lehrkraft sieht beides auf ihrer Liste. Was mit dem nächsten Export ankommt, ist von selbst abgehakt.</p>"
        io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-corrections'><thead><tr><th>Klasse</th><th>Schüler:in</th><th>Korrektur</th><th>Von</th><th>Stand</th><th></th></tr></thead><tbody>"
        rows.sort_by { |r| [(r[:arrived] || r[:done]) ? 1 : 0, LusdImport.klasse_sort_key(r[:klasse].to_s), r[:name].to_s] }.each do |r|
            by = (@@user_info[r[:by]] || {})[:display_last_name] || r[:by]
            state = r[:arrived] ? 'angekommen' : (r[:done] ? (r[:wontfix] ? 'geht nicht' : 'erledigt') : 'offen')
            attrs = "data-review='#{sl_h(r[:review])}' #{r[:missing] ? "data-missing='#{sl_h(r[:missing])}'" : "data-student='#{sl_h(r[:student])}'"}"
            actions = []
            if r[:gone_email]
                actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_take_gone' data-email='#{sl_h(r[:gone_email])}' data-name='#{sl_h(r[:name])}' data-seit='#{sl_h(r[:gone_since])}'>Im Dashboard abmelden</button>"
            end
            if r[:missing] && !r[:arrived] && !r[:done]
                actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_take_missing' data-name='#{sl_h(r[:name])}' data-note='#{sl_h(r[:note])}'>Von Hand eintragen</button>"
            end
            if r[:override]
                f = r[:override][:fields]
                actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_take_override' data-email='#{sl_h(r[:student])}' data-rufname='#{sl_h(f['rufname'])}' data-geschlecht='#{sl_h(f['geschlecht'])}'>Im Dashboard festlegen</button>"
            end
            unless r[:arrived]
                if r[:done]
                    actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_done' #{attrs} data-done='false'>Wieder offen</button>"
                else
                    actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_done' #{attrs} data-done='true'>Erledigt</button>"
                    actions << "<button type='button' class='btn btn-secondary btn-sm bu_sl_wontfix' #{attrs} data-name='#{sl_h(r[:name])}'>Geht nicht…</button>"
                end
            end
            who = sl_h(r[:name])
            who += "<div class='dp-who-official'>#{sl_h(r[:official])}#{r[:geburtstag] ? ", geb. #{sl_h(sl_date(r[:geburtstag]))}" : ''}</div>" if r[:official]
            stand = sl_h(state)
            stand += "<div class='dp-wontfix'>#{sl_h(r[:wontfix])}</div>" if r[:wontfix] && !r[:arrived]
            io.puts "<tr class='dp-correction dp-correction-#{state.tr(' ', '-')}'><td>#{sl_h(schuelerliste_short(r[:klasse]))}</td><td>#{who}</td><td style='white-space: normal;'>#{r[:what]}</td>"
            io.puts "<td>#{sl_h(by)}</td><td style='white-space: normal;'>#{stand}</td><td class='dp-row-actions'>#{actions.join(' ')}</td></tr>"
        end
        io.puts "</tbody></table></div>"
    end

    def schuelerliste_done_html(item)
        if item[:wontfix]
            "<span class='sl-wontfix'>Datenpflege: geht nicht – #{sl_h(item[:wontfix])}</span>"
        else
            "<span class='sl-done-lusd'>Datenpflege: in der LUSD korrigiert</span>"
        end
    end

    # a correction for the to-do list: each field as it is now and as it
    # should be (marked like a diff), »nur im Dashboard« apart
    def schuelerliste_correction_todo_text(check, entry)
        now = entry ? schuelerliste_values(entry) : {}
        show = ->(k, v) { k == 'geschlecht' ? (SCHUELERLISTE_GENDER_LABELS[v] || v.to_s) : (k == 'geburtstag' ? sl_date(v) : (k == 'bildungsgang' ? Main.tr_bildungsgang(v).to_s : v.to_s)) }
        parts = check[:fields].map do |k, v|
            label = "<span class='dp-what'>#{SCHUELERLISTE_FIELD_LABELS[k]}</span>"
            if (check[:dashboard_only] || []).include?(k)
                "#{label} #{sl_h(show.(k, v))} (nur im Dashboard)"
            elsif now.include?(k)
                "#{label} #{datenpflege_word_diff(show.(k, now[k]), show.(k, v))}"
            else
                "#{label} #{sl_h(show.(k, v))}"
            end
        end
        parts << "nicht mehr an der Schule#{check[:gone_since] ? " seit #{sl_date(check[:gone_since])}" : ''}" if check[:gone]
        parts << "<span class='dp-what'>Anmerkung</span> #{sl_h(check[:text])}" unless check[:text].to_s.empty?
        parts.join('<br>')
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
                io.puts "<p>Hier prüfen Klassenleitungen die neue Schülerliste ihrer Klasse, in 11 und 12 die Lehrkräfte der Leistungskurse. Du hast keine Klasse, die du prüfen kannst.</p>"
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
                io.puts "<div class='sl-klassen'><label for='sl_klasse'>#{klassen.any? { |k| schuelerliste_lk?(k) } ? 'Klasse oder LK' : 'Klasse'}</label> <select class='form-control' id='sl_klasse'>"
                klassen.each { |k| io.puts "<option value='#{sl_h(k)}'#{k == klasse ? ' selected' : ''}>#{sl_h(schuelerliste_short(k))}</option>" }
                io.puts "</select></div>"
            end
            v = view[klasse] || { :students => [], :leaving => [] }
            state = schuelerliste_state(klasse)
            entries = schuelerliste_entries(view, klasse)
            keys = entries.keys.to_set
            valid = ->(key) { schuelerliste_check_valid?(state[:checks][key], entries[key]) }
            needed, open_keys = schuelerliste_progress(entries, state[:checks])
            needed = needed.to_set
            done = needed.size - open_keys.size
            unchanged = keys.size - needed.size
            # the overview on /datenpflege: opened by the Klassenleitung
            if schuelerliste_teacher_shorthands(klasse).include?(@session_user[:shorthand])
                neo4j_query(<<~END_OF_QUERY, :review => schuelerliste_review_key(klasse), :at => Time.now.to_i)
                    MERGE (s:StudentReviewSeen {review: $review})
                    ON CREATE SET s.first_at = $at
                    SET s.last_at = $at;
                END_OF_QUERY
            end
            io.puts "<div class='sl-class' data-klasse='#{sl_h(klasse)}'>"
            io.puts "<h3>#{sl_h(schuelerliste_label(klasse))}</h3>"
            if schuelerliste_lk?(klasse)
                io.puts "<p class='sl-intro sl-lk-note'>#{sl_h(SCHUELERLISTE_LK_NOTE)}</p>"
            end
            io.puts "<p class='sl-intro'>So #{schuelerliste_lk?(klasse) ? 'stehen die Schüler:innen deines Leistungskurses' : 'steht deine Klasse'} in der neuen Liste aus der Schulverwaltung (LUSD). Markierte Zeilen (neu, geändert, geht) prüfst du einzeln: »Stimmt«, wenn alles richtig ist, sonst »Korrigieren«. Die übrigen stehen schon so im Dashboard – bitte trotzdem einmal durchsehen und korrigieren, was nicht stimmt. Fehlt jemand, trag es unten ein. Zum Schluss »Liste bestätigen«. Im Dashboard ändert sich erst etwas, wenn die Liste übernommen wird.</p>"
            lk = schuelerliste_lk?(klasse)
            tutors = lk ? schuelerliste_tutors : {}
            marker = schuelerliste_tutor_marker?(klasse)
            with_tutor = lk ? v[:students].count { |e| !tutors[e[:key]].empty? } : 0
            io.puts "<p class='sl-intro sl-names-note'><strong>Nachname</strong> und <strong>Vornamen</strong> (alle, wie im Ausweis) stehen auf Zeugnissen und anderen amtlichen Dokumenten. Mit dem <strong>Rufnamen</strong> erscheint die Schülerin oder der Schüler im Dashboard, auf Sitzplänen, in der Nextcloud und überall sonst im Schulalltag.</p>"
            progress = needed.empty? ? "Keine Änderungen: <strong>#{unchanged}</strong> #{unchanged == 1 ? 'Zeile steht' : 'Zeilen stehen'} schon so im Dashboard" :
                "<strong>#{done}</strong> von <strong>#{needed.size}</strong> markierten Zeilen geprüft#{unchanged > 0 ? ", <span class='sl-unchanged'>#{unchanged} unverändert</span>" : ''}"
            io.puts "<p class='sl-progress'>#{progress}#{lk ? ", <strong class='sl-tutor-count'>#{with_tutor}</strong> mit Tutor:in" : ''}</p>"
            io.puts "<p class='sl-legend'><span class='sl-badge sl-badge-added'>+ neu</span> kommt dazu <span class='sl-badge sl-badge-removed'>− geht</span> verlässt die Klasse <span class='dp-old'>bisher</span> <span class='dp-new'>neu</span> geändert <span class='sl-fix'>neuer Wert</span> Korrektur</p>"
            io.puts "<div class='sl-scroll'><table class='table sl-table'><thead><tr><th class='sl-head'>Name</th><th>Nachname</th><th>Rufname</th><th>Vornamen</th><th>Geschlecht</th><th>Geburtstag</th><th>Bildungsgang</th>#{lk ? '<th>Tutor:in</th>' : ''}<th></th></tr></thead><tbody>"
            gender = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }
            abroad = Parser.abroad_now
            v[:students].each do |s|
                # the changes against today in their column, like a diff: what
                # goes struck through on red, what comes on green
                ch = s[:changes].to_h { |what, from, to| [what, [from, to]] }
                diff = ->(from, to) { datenpflege_word_diff(from, to) }
                cell = ->(what, now) { ch[what] ? diff.(*ch[what]) : sl_h(now) }
                badges = []
                badges << "<span class='sl-badge sl-badge-added'>+ neu</span>" if s[:new] && !s[:new_address]
                badges << "<span class='sl-badge sl-badge-added'>+ aus #{sl_h(tr_klasse(s[:from]))}</span>" if s[:from]
                badges << "<span class='sl-badge'>neue Adresse</span>" if s[:new_address]
                if (away = abroad[s[:key]])
                    back = (Date.parse(away['zurueck'].to_s).strftime('%d.%m.%Y') rescue nil)
                    badges << "<span class='sl-badge sl-badge-abroad'>im Ausland#{back ? ", zurück ab #{back}" : ''}</span>"
                end
                badges_html = badges.empty? ? '' : "<div class='sl-badges'>#{badges.join(' ')}</div>"
                g = ->(x) { gender[x] || x }
                gender_html = ch['Geschlecht'] ? diff.(g.(ch['Geschlecht'][0]), g.(ch['Geschlecht'][1])) : sl_h(g.(s[:geschlecht]))
                birthday_html = ch['Geburtstag'] ? diff.(*ch['Geburtstag']) : sl_h(sl_date(s[:geburtstag]))
                bildungsgang_html = ch['Bildungsgang'] ? diff.(*ch['Bildungsgang']) : sl_h(Main.tr_bildungsgang(s[:bildungsgang]))
                row_class = (s[:new] || s[:from]) ? 'sl-row-added' : (ch.empty? ? '' : 'sl-row-changed')
                io.puts "<tr class='sl-row #{row_class}' data-student='#{sl_h(s[:key])}' data-values='#{sl_h({ 'rufname' => s[:first_name], 'nachname' => Nachname.anzeige(s[:last_name]), 'vornamen' => s[:official_first_name], 'geschlecht' => s[:geschlecht], 'geburtstag' => s[:geburtstag], 'klasse' => s[:klasse], 'bildungsgang' => s[:bildungsgang] }.to_json)}'>"
                # the name as a heading where the row becomes a card (phones)
                io.puts "<td class='sl-head'><div class='sl-name'>#{sl_h(s[:name])}</div>#{badges_html}</td>"
                io.puts "<td class='sl-nachname'>#{cell.('Nachname', Nachname.anzeige(s[:last_name]))}#{badges_html}</td>"
                io.puts "<td class='sl-rufname'>#{cell.('Rufname', s[:first_name])}</td><td class='sl-vornamen'>#{cell.('Vornamen', s[:official_first_name])}</td>"
                io.puts "<td>#{gender_html}</td><td>#{birthday_html}</td><td>#{bildungsgang_html}</td>"
                io.puts "<td class='sl-tutor'>#{schuelerliste_tutor_html(tutors[s[:key]], marker && s[:key].include?('@'))}</td>" if lk
                io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]], valid.(s[:key]), needed.include?(s[:key]))}</td></tr>"
                check = state[:checks][s[:key]]
                taken = !!(check && valid.(s[:key]) && check[:seen] != schuelerliste_values(entries[s[:key]]).to_json)
                io.puts schuelerliste_note_rows(check, valid.(s[:key]), row_class, lk ? SCHUELERLISTE_COLUMNS[0..-2] + [nil, nil] : SCHUELERLISTE_COLUMNS, taken)
            end
            io.puts "</tbody></table></div>"
            unless v[:leaving].empty?
                io.puts "<h4>#{OBERSTUFE.include?(klasse) || schuelerliste_lk?(klasse) ? 'Geht' : 'Verlässt die Klasse'}</h4>"
                io.puts "<div class='sl-scroll'><table class='table sl-table sl-leaving'><tbody>"
                v[:leaving].each do |s|
                    where = s[:to] ? "− wechselt in die #{sl_h(tr_klasse(s[:to]))}" : '− steht nicht mehr in der Liste'
                    io.puts "<tr class='sl-row sl-row-removed' data-student='#{sl_h(s[:key])}' data-leaving='1' data-values='{}'><td><div class='sl-name'><span class='dp-old'>#{sl_h(s[:name])}</span></div><div class='sl-badges'><span class='sl-badge sl-badge-removed'>#{where}</span></div></td>"
                    io.puts "<td class='sl-actions'>#{schuelerliste_status_html(state[:checks][s[:key]], valid.(s[:key]))}</td></tr>"
                    io.puts schuelerliste_note_rows(state[:checks][s[:key]], valid.(s[:key]), 'sl-row-removed', [nil, nil])
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<h4>Fehlt jemand?</h4>"
            unless state[:missing].empty?
                io.puts "<ul class='sl-missing'>"
                state[:missing].each do |m|
                    io.puts "<li><span><strong>#{sl_h(m[:name])}</strong>#{m[:note].to_s.empty? ? '' : " – #{sl_h(m[:note])}"}</span>#{m[:done] ? " #{schuelerliste_done_html(m)}" : ''} <button type='button' class='btn btn-link btn-sm bu_sl_missing_delete' data-id='#{sl_h(m[:id])}'>Entfernen</button></li>"
                end
                io.puts "</ul>"
            end
            io.puts "<div class='sl-missing-form'><input class='form-control' id='ti_sl_missing_name' maxlength='100' placeholder='Vor- und Nachname'><input class='form-control' id='ti_sl_missing_note' maxlength='1000' placeholder='Hinweis (optional)'><button type='button' class='btn btn-secondary' id='bu_sl_missing'>Eintragen</button></div>"
            io.puts "<div class='sl-confirm'>"
            if state[:confirmed] && !open_keys.empty?
                io.puts "<p class='sl-changed'>Seit deiner Bestätigung hat sich die Liste geändert. Bitte prüf die markierten Zeilen noch einmal und bestätige dann erneut.</p>"
            end
            if state[:confirmed] && open_keys.empty?
                by = (@@user_info[state[:confirmed][:confirmed_by]] || {})[:display_name] || state[:confirmed][:confirmed_by]
                io.puts "<p class='sl-confirmed'><i class='fa fa-check'></i> Bestätigt am #{Time.at(state[:confirmed][:confirmed_at]).strftime('%d.%m.%Y')} von #{sl_h(by)}.</p>"
                io.puts "<button type='button' class='btn btn-secondary' id='bu_sl_unconfirm'>Ändern</button>"
            else
                open = open_keys.size
                rest = unchanged > 0 ? " Mit »Liste bestätigen« bestätigst du auch die #{unchanged == 1 ? 'unveränderte Zeile' : "#{unchanged} unveränderten Zeilen"}." : ''
                io.puts "<p class='text-muted'>#{open > 0 ? "Noch #{open} #{open == 1 ? 'markierte Zeile' : 'markierte Zeilen'} zu prüfen." : "#{needed.empty? ? 'Nichts einzeln zu prüfen.' : 'Alles Markierte geprüft.'}#{rest}"}</p>"
                io.puts "<button type='button' class='btn btn-success' id='bu_sl_confirm'#{open > 0 ? ' disabled' : ''}>Liste bestätigen</button>"
            end
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    # the tutor column of an LK list: »ich« to tick for the LK's teachers,
    # who else marked the student
    def schuelerliste_tutor_html(tutors, can_mark)
        me = @session_user[:email]
        others = (tutors - [me]).map { |t| sl_h(schuelerliste_teacher_name(t)) }
        html = +''
        if can_mark
            html << "<label class='sl-tutor-mark'><input type='checkbox' class='ti_sl_tutor'#{tutors.include?(me) ? ' checked' : ''}> <span class='sl-tutor-phone'>Tutor:in: </span>ich</label>"
        end
        html << " <span class='sl-tutor-others'>#{others.join(', ')}</span>" unless others.empty?
        html << "<span class='text-muted'>–</span>" if html.empty?
        html
    end

    # the last column: only the buttons (one line), what was said goes in
    # a row of its own below (schuelerliste_note_row)
    def schuelerliste_status_html(check, valid = true, needed = true)
        if (check.nil? || !valid) && !needed
            # unchanged: covered by confirming the list, only a correction
            "<button type='button' class='btn btn-secondary btn-sm bu_sl_correct'>Korrigieren…</button>"
        elsif check.nil? || !valid
            "<button type='button' class='btn btn-secondary btn-sm bu_sl_ok'>Stimmt</button> <button type='button' class='btn btn-secondary btn-sm bu_sl_correct'>Korrigieren…</button>"
        elsif check[:status] == 'ok'
            "<span class='sl-done'><i class='fa fa-check'></i> stimmt</span>#{schuelerliste_by_other(check)} <button type='button' class='btn btn-link btn-sm bu_sl_reopen'>Ändern</button>"
        else
            "<button type='button' class='btn btn-link btn-sm bu_sl_correct' data-check='#{sl_h({ 'fields' => check[:fields], 'text' => check[:text], 'gone' => check[:gone], 'gone_since' => check[:gone_since], 'dashboard_only' => check[:dashboard_only] || [] }.to_json)}'>Ändern</button> <button type='button' class='btn btn-link btn-sm bu_sl_withdraw'>Zurücknehmen</button>"
        end
    end

    # who checked, when it was someone else (in 11/12 the LK teachers share
    # the checks of a student)
    def schuelerliste_by_other(check)
        return '' if check[:by].nil? || check[:by] == @session_user[:email]
        name = (@@user_info[check[:by]] || {})[:display_last_name] || check[:by]
        " <span class='sl-by'>(#{sl_h(name)})</span>"
    end

    # a correction below its row, each value exactly in its column (the
    # student's row stays as it is); what has no column (Klasse, »nicht mehr
    # an der Schule«, the note) across the columns in a row of its own. Or
    # that the row changed since it was checked.
    # columns: the field of each column, nil for a column without one
    SCHUELERLISTE_COLUMNS = [nil, 'nachname', 'rufname', 'vornamen', 'geschlecht', 'geburtstag', 'bildungsgang', nil]
    SCHUELERLISTE_GENDER_LABELS = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }

    def schuelerliste_note_rows(check, valid, row_class, columns, taken = false)
        tr = ->(cells) { "<tr class='sl-note-row #{row_class}'>#{cells}</tr>" }
        # (the first column of the class table is the name heading on phones)
        span = ->(html) { tr.(columns.size > 2 ? "<td class='sl-head'></td><td colspan='#{columns.size - 1}' data-label=''>#{html}</td>" : "<td colspan='#{columns.size}' data-label=''>#{html}</td>") }
        if check && !valid
            return span.("<span class='sl-changed-row'>geändert seit deiner Prüfung</span>")
        end
        return '' unless check && check[:status] == 'correction'
        fields = check[:fields] || {}
        dashboard_only = check[:dashboard_only] || []
        in_columns = fields.keys & columns.compact
        rows = +''
        unless in_columns.empty?
            cells = columns.each_with_index.map do |field, i|
                if field && fields.include?(field)
                    v = fields[field]
                    v = case field
                        when 'geschlecht' then SCHUELERLISTE_GENDER_LABELS[v] || v
                        when 'geburtstag' then sl_date(v)
                        when 'bildungsgang' then Main.tr_bildungsgang(v)
                        else v
                        end
                    only = dashboard_only.include?(field) ? " <span class='sl-only'>(nur im Dashboard)</span>" : ''
                    "<td class='sl-fix-cell sl-fix-#{field}'><span class='sl-fix'>#{sl_h(v)}</span>#{only}</td>"
                elsif i == columns.size - 1
                    "<td class='sl-fix-label'>#{taken ? 'Korrektur übernommen' : 'Korrektur'}#{schuelerliste_by_other(check)}</td>"
                else
                    "<td#{i == 0 ? " class='sl-head'" : ''}></td>"
                end
            end
            rows << tr.(cells.join)
        end
        rest = check.merge(:fields => fields.reject { |k, _| in_columns.include?(k) })
        unless rest[:fields].empty? && !rest[:gone] && rest[:text].to_s.empty?
            rows << span.("<span class='sl-corrected'>Korrektur#{in_columns.empty? ? schuelerliste_by_other(check) : ''}: #{schuelerliste_correction_text(rest)}</span>")
        end
        # what the Datenpflege did with it
        rows << span.(schuelerliste_done_html(check)) if check[:done] && !taken
        rows
    end

end
