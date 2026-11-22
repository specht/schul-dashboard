# Uploading data on /datenpflege (role can_manage_data, admins have it):
# a student export from LUSD is converted (lusd_import.rb), compared with the
# student list valid on the chosen date and – once confirmed – written to the
# data repo as schueler/JJJJ-MM-TT.TXT (data_repo.rb). Afterwards it can be
# committed or rolled back there. Plan: review/2026-11/data-uploads.md.
#
# An upload can be kept as *the draft* (review/2026-11/student-data-review.md):
# it has no effect anywhere, stays until it is replaced, applied or discarded,
# and keeps the choices made on the page (class names, accounts, addresses)
# per student. A new upload is compared with the draft too and takes its
# choices over; the draft before keeps for one comparison.
#
# The comparison runs both lists through the dashboard's own parser, so new,
# lost and renamed accounts are exactly what the dashboard would make of them
# (including the substitution files in /data/schueler).

require './lusd_import.rb'
require './data_repo.rb'

class Main < Sinatra::Base
    DATENPFLEGE_PENDING_DIR = '/internal/datenpflege'
    DATENPFLEGE_MAX_UPLOAD = 5 * 1024 * 1024
    DATENPFLEGE_EXTENSIONS = ['xlsx', 'csv', 'txt']
    DATENPFLEGE_KLASSEN_TR = 'schueler/lusd-klassen.yaml'
    DATENPFLEGE_MANAGED = %r{\Aschueler/(\d{4}-\d{2}-\d{2}\.TXT|lusd-klassen\.yaml|overrides\.yaml)\z}
    DATENPFLEGE_OVERRIDES = 'schueler/overrides.yaml'
    DATENPFLEGE_RUFNAME = /\A[\p{L}\p{M}][\p{L}\p{M}' .\-]{0,39}\z/u
    DATENPFLEGE_DRAFT = 'entwurf.json'

    def require_data_manager!
        require_user_with_role!(:can_manage_data)
    end

    def datenpflege_pending_path(token, ext = 'json')
        assert(token.is_a?(String) && token =~ /\A[0-9a-f]{32}\z/, 'invalid token')
        File.join(DATENPFLEGE_PENDING_DIR, "#{token}.#{ext}")
    end

    def datenpflege_cleanup_pending
        draft = datenpflege_draft || {}
        keep = [draft['token'], draft['previous']].compact
        Dir[File.join(DATENPFLEGE_PENDING_DIR, '*')].each do |path|
            next if File.basename(path) == DATENPFLEGE_DRAFT
            next if keep.include?(File.basename(path).split('.').first)
            File.delete(path) if File.mtime(path) < Time.now - 24 * 60 * 60
        end
    end

    def datenpflege_draft_path
        File.join(DATENPFLEGE_PENDING_DIR, DATENPFLEGE_DRAFT)
    end

    # {'token', 'previous', 'date', 'klassen', 'links', 'emails', 'email', 'saved'}
    # – links and emails keyed by student (datenpflege_student_key); nil
    # when there is none (or its upload is gone)
    def datenpflege_draft
        path = datenpflege_draft_path
        return nil unless File.exist?(path)
        draft = JSON.parse(File.read(path)) rescue nil
        return nil unless draft && File.exist?(datenpflege_pending_path(draft['token']))
        draft['previous'] = nil if draft['previous'] && !File.exist?(datenpflege_pending_path(draft['previous']))
        draft
    end

    def datenpflege_save_draft(draft)
        FileUtils.mkpath(DATENPFLEGE_PENDING_DIR)
        File.write(datenpflege_draft_path, draft.to_json)
    end

    def datenpflege_delete_upload(token)
        return unless token
        ['json', 'TXT'].each do |ext|
            path = datenpflege_pending_path(token, ext)
            File.delete(path) if File.exist?(path)
        end
    end

    # a student of an export, the same in the next export: LUSD's own number
    # when the export has it, else name and birthday
    def self.datenpflege_student_key(st)
        return "lusd:#{st.lusd_id}" unless st.lusd_id.to_s.strip.empty?
        "name:#{st.nachname}|#{st.vorname}|#{st.geburtsdatum}"
    end

    # export row => student key
    def datenpflege_row_keys(pending)
        LusdImport.convert(pending['rows'])[:students].to_h { |st| [st.row, Main.datenpflege_student_key(st)] }
    end

    # the page's choices ({row => value}) and the draft's ({student => value})
    def datenpflege_choices_by_student(pending, by_row)
        keys = datenpflege_row_keys(pending)
        (by_row || {}).each_with_object({}) { |(row, v), h| h[keys[row.to_i]] = v if keys[row.to_i] }
    end

    def datenpflege_choices_by_row(pending, by_student)
        rows = datenpflege_row_keys(pending).invert
        (by_student || {}).each_with_object({}) { |(key, v), h| h[rows[key]] = v if rows[key] }
    end

    # class mapping kept in the data repo (LUSD class => class of the dashboard)
    def datenpflege_saved_klassen
        path = File.join('/data', DATENPFLEGE_KLASSEN_TR)
        return {} unless File.exist?(path)
        data = YAML.load_file(path)
        data.is_a?(Hash) ? data.transform_keys { |k| LusdImport.normalize_klasse(k) }.transform_values(&:to_s) : {}
    rescue StandardError
        {}
    end

    def datenpflege_dashboard_klasse(file_klasse)
        k = Main.fix_parsed_klasse(file_klasse)
        PARSE_KLASSE_TR[k] || k
    end

    def datenpflege_valid_date(s)
        return nil unless s.is_a?(String) && s =~ /\A\d{4}-\d{2}-\d{2}\z/
        Date.parse(s)
    rescue Date::Error
        nil
    end

    def datenpflege_parse_list(path, translate = nil)
        records = []
        Parser.new.parse_schueler(path, all_classes: true, translate_klasse: translate) { |r| records << r }
        records
    end

    def datenpflege_iso_date(ddmmyyyy)
        return nil unless ddmmyyyy.to_s =~ /\A(\d{2})\.(\d{2})\.(\d{4})\z/
        "#{$3}-#{$2}-#{$1}"
    end

    # Who of the export is who in the current list (row => [record, how]):
    # the same name (full, Rufname or first first name with the last name),
    # then the same birthday with the same last or first name, finally the
    # address the dashboard builds from Rufname and last name. Each step only
    # takes a match when exactly one fits.
    def datenpflege_match_old(students, old_records, parser = nil)
        norm = ->(x) { LusdImport.clean(x).downcase }
        first = ->(x) { norm.(x).split(' ').first.to_s }
        loose = ->(x) { remove_accents(LusdImport.clean(x).downcase).gsub(/[^a-z]/, '') }
        loose_first = ->(x) { loose.(LusdImport.clean(x).split(' ').first.to_s) }
        # [how, key of a current record, key of an export row]: LUSD's number,
        # then the same name is the same person; then the address the old
        # rules gave (first import), the name spelled loosely, the birthday,
        # and finally the address built from Rufname and last name
        passes = [
            [:lusd_id, ->(r) { r[:lusd_id] }, ->(st) { st.lusd_id }],
            [:name, ->(r) { [norm.(r[:last_name]), norm.(r[:official_first_name])] },
                    ->(st) { [norm.(st.nachname), norm.(st.vorname)] }],
            [:name, ->(r) { [norm.(r[:last_name]), norm.(r[:first_name])] },
                    ->(st) { [norm.(st.nachname), norm.(st.effective_rufname)] }],
            [:name, ->(r) { [norm.(r[:last_name]), first.(r[:official_first_name])] },
                    ->(st) { [norm.(st.nachname), first.(st.vorname)] }],
        ]
        if parser
            passes << [:alte_regeln, ->(r) { r[:email] }, ->(st) { parser.email_by_old_rules(st.nachname, st.vorname, st.rufname) }]
        end
        passes += [
            [:name, ->(r) { [loose.(r[:last_name]), loose_first.(r[:official_first_name])] },
                    ->(st) { [loose.(st.nachname), loose_first.(st.vorname)] }],
            [:geburtstag, ->(r) { [r[:geburtstag], norm.(r[:last_name])] },
                          ->(st) { [datenpflege_iso_date(st.geburtsdatum), norm.(st.nachname)] }],
            [:geburtstag, ->(r) { [r[:geburtstag], first.(r[:official_first_name])] },
                          ->(st) { [datenpflege_iso_date(st.geburtsdatum), first.(st.vorname)] }],
        ]
        if parser
            passes << [:adresse, ->(r) { r[:email] }, ->(st) { parser.name_to_email(st.effective_rufname, st.nachname, false) }]
        end
        used = {}
        result = {}
        passes.each do |how, old_key, new_key|
            index = Hash.new { |h, k| h[k] = [] }
            old_records.each do |r|
                key = old_key.(r)
                index[key] << r unless key.nil? || (key.is_a?(Array) && key.first.nil?)
            end
            students.each do |st|
                next if result[st.row]
                key = new_key.(st)
                next if key.nil? || (key.is_a?(Array) && key.first.nil?)
                candidates = index.fetch(key, []).reject { |r| used[r[:email]] }
                next unless candidates.size == 1
                result[st.row] = [candidates.first, how]
                used[candidates.first[:email]] = true
            end
        end
        result
    end

    NAME_PARTICLES = %w(von de van der den zu zur du di da la le del ten ter vom)

    # An address for a new student: as the dashboard builds it; when it is
    # too long, leaving out parts of the names (second first names, the
    # second part of double names, von/de …). Returns [address, note].
    def datenpflege_new_email(parser, rufname, nachname, taken)
        build = ->(r, n) { parser.name_to_email(r, n, false) }
        local = ->(e) { e.split('@').first }
        full = build.(rufname, nachname)
        r_first = rufname.split(/[ -]/).first.to_s
        n_parts = nachname.split(/[ -]/).reject { |x| NAME_PARTICLES.include?(x.downcase) }
        tries = [[rufname, nachname], [r_first, nachname], [rufname, n_parts.join(' ')],
                 [r_first, n_parts.join(' ')], [rufname, n_parts.first.to_s], [r_first, n_parts.first.to_s],
                 [r_first, n_parts.last.to_s]]
        email = tries.map { |r, n| build.(r, n) }.find { |e| local.(e).size <= 23 }
        email ||= "#{local.(build.(r_first, n_parts.first.to_s))[0, 23].sub(/[.\-]+\z/, '')}@#{SCHUL_MAIL_DOMAIN}"
        shortened = email != full
        # never the address of someone else (also not of a student who left)
        base = local.(email)
        n = 1
        while taken.include?(email)
            n += 1
            email = "#{base[0, 23 - n.to_s.size - 1]}.#{n}@#{SCHUL_MAIL_DOMAIN}"
        end
        # [address, the full one if shortened, whether the name was taken]
        [email, shortened ? full : nil, n > 1]
    end

    # Converts the pending upload with the class mapping and compares it with
    # the student list valid on date. Returns a hash for the page.
    # links: export row => address of an account in the current list (chosen
    # on the page); emails: export row => address wanted for a new student
    def datenpflege_compare(pending, klassen, date, links = {}, emails = {})
        rows = pending['rows']
        saved = datenpflege_saved_klassen
        old_path = Parser.schueler_path(date)
        old_records = File.exist?(old_path) ? datenpflege_parse_list(old_path) : []

        first = LusdImport.convert(rows, {})
        lusd_klassen = first[:students].map(&:lusd_klasse).uniq.sort_by { |k| LusdImport.klasse_sort_key(k) }
        parser = Parser.new
        matches = datenpflege_match_old(first[:students], old_records, parser)
        old_by_email = old_records.to_h { |r| [r[:email], r] }
        links.each_pair do |row, email|
            next unless old_by_email[email]
            matches.delete_if { |_, (m, _)| m[:email] == email }
            matches[row] = [old_by_email[email], :von_hand]
        end
        # where the students of each LUSD class were so far
        were_in = Hash.new { |h, k| h[k] = Hash.new(0) }
        first[:students].each do |st|
            were_in[st.lusd_klasse][matches[st.row][0][:klasse]] += 1 if matches[st.row]
        end

        mapping = {}
        lusd_klassen.each do |k|
            suggestion = nil
            if (olds = were_in[k]).any?
                best, n = olds.max_by { |_, c| c }
                suggestion = best if n >= olds.values.sum * 0.9 && best != k
            end
            # the same name, or an omega class ("8omega" => "8o")
            guess = Parser.klasse_from_untis(k)
            guess = nil unless KLASSEN_ORDER.include?(guess)
            # a suggestion only fills in a class the dashboard doesn't know
            # otherwise – at the change of school year the students moved on
            target = klassen[k] || saved[k] || guess || suggestion || k
            mapping[k] = { :target => target, :suggestion => suggestion, :dashboard => target, :students => [] }
        end

        result = LusdImport.convert(rows, mapping.transform_values { |m| m[:target] })
        # addresses: whoever is in the dashboard keeps theirs
        taken = Set.new(old_records.map { |r| r[:email] })
        result[:students].each do |st|
            if (old, how = matches[st.row])
                st.email = old[:email]
                st.old_klasse = old[:klasse]
                st.matched_by = how
            end
        end
        wish_errors = []
        result[:students].each do |st|
            next if st.email || !emails[st.row]
            wanted = "#{emails[st.row]}@#{SCHUL_MAIL_DOMAIN}"
            if emails[st.row] !~ /\A[a-z0-9][a-z0-9.\-]{0,22}\z/
                wish_errors << "Zeile #{st.row}: »#{emails[st.row]}« geht nicht als Adresse (Kleinbuchstaben, Ziffern, Punkt und Bindestrich, höchstens 23 Zeichen)"
            elsif taken.include?(wanted)
                wish_errors << "Zeile #{st.row}: »#{emails[st.row]}« ist schon vergeben"
            else
                st.email = wanted
                st.email_custom = true
                taken << wanted
            end
        end
        result[:students].each do |st|
            next if st.email
            st.email, st.email_note, st.email_taken = datenpflege_new_email(parser, st.effective_rufname, st.nachname, taken)
            taken << st.email
        end
        result[:students].each { |st| mapping[st.lusd_klasse][:students] << st if mapping[st.lusd_klasse] }
        mapping.each_value { |m| m[:count] = m[:students].size }
        out = {
            :filename => pending['filename'], :total => result[:students].size,
            :duplicates => result[:duplicates], :skipped => result[:skipped],
            :errors => result[:errors].map { |nr, text| "Zeile #{nr}: #{text}" } + wish_errors,
            :mapping => mapping, :old_path => old_path, :students => result[:students],
            :kept => matches.size,
            :shortened => result[:students].select { |st| st.email_note || st.email_taken },
        }
        return out unless out[:errors].empty?

        tmp = "#{datenpflege_pending_path(pending['token'], 'TXT')}"
        File.write(tmp, LusdImport.ascii_txt(result[:students]), encoding: 'UTF-8')
        begin
            new_records = datenpflege_parse_list(tmp, false)
        rescue Parser::SchuelerLineError => e
            out[:errors] << e.message
            return out
        end
        out.merge!(datenpflege_diff(old_records, new_records))
        out[:new_records] = new_records
        out
    end

    # this upload against the draft (or, for the draft, against the draft
    # before): which LUSD corrections arrived. nil without one.
    def datenpflege_since_draft(pending, c, klassen, date)
        draft = datenpflege_draft
        return nil unless draft && c[:errors].empty?
        other = pending['token'] == draft['token'] ? draft['previous'] : draft['token']
        return nil unless other
        other_pending = (datenpflege_load_pending(other) rescue nil)
        return nil unless other_pending
        oc = datenpflege_compare(other_pending, klassen, date,
                                 datenpflege_choices_by_row(other_pending, draft['links']),
                                 datenpflege_choices_by_row(other_pending, draft['emails']))
        return nil unless oc[:errors].empty?
        datenpflege_diff(oc[:new_records], c[:new_records]).merge(
            :label => pending['token'] == draft['token'] ? 'vorigen Entwurf' : 'Entwurf',
            :filename => other_pending['filename'], :created => other_pending['created'])
    end

    def datenpflege_diff(old_records, new_records)
        old_by = old_records.to_h { |r| [r[:email], r] }
        new_by = new_records.to_h { |r| [r[:email], r] }
        added = new_by.keys - old_by.keys
        removed = old_by.keys - new_by.keys
        # the same person under another address: same birthday and the same
        # last or first name
        moved = []
        removed.dup.each do |email|
            o = old_by[email]
            next unless o[:geburtstag]
            n = added.map { |e| new_by[e] }.find do |r|
                r[:geburtstag] == o[:geburtstag] &&
                    (r[:last_name] == o[:last_name] || r[:official_first_name] == o[:official_first_name])
            end
            next unless n
            moved << [o, n]
            removed.delete(email)
            added.delete(n[:email])
        end
        both = old_by.keys & new_by.keys
        known = ->(r) { KLASSEN_ORDER.include?(r[:klasse]) }
        geb = ->(x) { x ? Date.parse(x).strftime('%d.%m.%Y') : '' }
        birthdays_added = 0
        changed = both.filter_map do |e|
            o, n = old_by[e], new_by[e]
            next unless known.(n) || known.(o)
            changes = []
            changes << ['Klasse', o[:klasse], n[:klasse]] if o[:klasse] != n[:klasse]
            if o[:display_name] != n[:display_name]
                # the first name shown is the Rufname (LUSD's, else the first
                # first name)
                if o[:last_name] == n[:last_name]
                    changes << ['Rufname', o[:first_name], n[:first_name]]
                else
                    changes << ['Name', o[:display_name], n[:display_name]]
                end
            end
            if o[:official_first_name] != n[:official_first_name] && o[:display_name] == n[:display_name]
                changes << ['Vornamen', o[:official_first_name], n[:official_first_name]]
            end
            # ASCII.TXT has no Bildungsgang: the one the dashboard uses now
            old_bg = o[:bildungsgang] || datenpflege_current_bildungsgang(e)
            if n[:bildungsgang] && old_bg != n[:bildungsgang]
                changes << ['Bildungsgang', Main.tr_bildungsgang(old_bg), Main.tr_bildungsgang(n[:bildungsgang])]
            end
            changes << ['Geschlecht', o[:geschlecht], n[:geschlecht]] if o[:geschlecht] != n[:geschlecht]
            if o[:geburtstag].nil? && n[:geburtstag]
                birthdays_added += 1
            elsif o[:geburtstag] && o[:geburtstag] != n[:geburtstag]
                changes << ['Geburtstag', geb.(o[:geburtstag]), geb.(n[:geburtstag])]
            end
            [o, n, changes] unless changes.empty?
        end
        {
            :old_total => old_records.count(&known),
            :new_total => new_records.count(&known),
            :added => added.map { |e| new_by[e] }.select(&known),
            :removed => removed.map { |e| old_by[e] }.select(&known),
            :moved => moved,
            :changed => changed,
            :birthdays_added => birthdays_added,
            :dropped => new_records.reject(&known),
        }
    end

    def datenpflege_current_bildungsgang(email)
        return nil unless Main.class_variable_defined?(:@@user_info)
        (@@user_info[email] || {})[:bildungsgang]
    end

    def datenpflege_name(r)
        dp_h("#{r[:display_name]} (#{r[:klasse]})")
    end

    def dp_h(s)
        CGI.escapeHTML(s.to_s)
    end

    # A change as in a word diff: the old value struck through on red, the
    # new one on green, the words that differ emphasised.
    def datenpflege_word_diff(from, to)
        a = from.to_s.split(/(\s+)/)
        b = to.to_s.split(/(\s+)/)
        pre = 0
        pre += 1 while pre < a.size && pre < b.size && a[pre] == b[pre]
        suf = 0
        suf += 1 while suf < a.size - pre && suf < b.size - pre && a[-1 - suf] == b[-1 - suf]
        mark = lambda do |parts, cls|
            head = parts[0, pre].join
            mid = parts[pre, parts.size - pre - suf].join
            tail = suf > 0 ? parts[-suf..].join : ''
            "<span class='#{cls}'>#{dp_h(head)}#{mid.empty? ? '' : "<mark>#{dp_h(mid)}</mark>"}#{dp_h(tail)}</span>"
        end
        old_html = from.to_s.empty? ? "<span class='dp-old dp-none'>leer</span>" : mark.(a, 'dp-old')
        new_html = to.to_s.empty? ? "<span class='dp-new dp-none'>leer</span>" : mark.(b, 'dp-new')
        "#{old_html} #{new_html}"
    end

    def datenpflege_section(io, cls, title, rows, headers, hint: nil, open: true)
        io.puts "<details class='dp-section #{cls}'#{open && !rows.empty? ? ' open' : ''}>"
        io.puts "<summary>#{title}: <strong class='dp-count'>#{rows.size}</strong></summary>"
        unless rows.empty?
            io.puts "<p class='text-muted dp-hint'>#{hint}</p>" if hint
            io.puts "<div class='dp-scroll'><table class='table table-sm dp-list'><thead><tr>#{headers.map { |x| "<th>#{x}</th>" }.join}</tr></thead><tbody>"
            rows.each { |r| io.puts "<tr>#{r.map { |x| "<td>#{x}</td>" }.join}</tr>" }
            io.puts "</tbody></table></div>"
        end
        io.puts "</details>"
    end

    # The classes of the export and how the dashboard calls them – closed,
    # unless a class would be left out
    def datenpflege_klassen_html(io, c)
        unknown = c[:mapping].values.count { |m| !KLASSEN_ORDER.include?(m[:dashboard]) }
        changed = c[:mapping].count { |k, m| m[:target] != k }
        io.puts "<details class='dp-klassen-box'#{unknown > 0 ? ' open' : ''}>"
        io.puts "<summary>Klassen zuordnen: #{c[:mapping].size} Klassen im Export, #{changed} anders benannt#{unknown > 0 ? ", <span class='text-danger'>#{unknown} gibt es im Dashboard nicht</span>" : ''}</summary>"
        io.puts "<div class='dp-scroll'><table class='table table-sm dp-klassen'><thead><tr><th>Im Export</th><th>Anzahl</th><th>Im Dashboard</th><th></th></tr></thead><tbody>"
        c[:mapping].each_pair do |k, m|
            note = []
            note << "<span class='text-danger'>Gibt es im Dashboard nicht, wird weggelassen</span>" unless KLASSEN_ORDER.include?(m[:dashboard])
            note << "Bisher in #{dp_h(m[:suggestion])}" if m[:suggestion] && m[:suggestion] != m[:target]
            io.puts "<tr><td>#{dp_h(k)}</td><td>#{m[:count]}</td>"
            io.puts "<td><input class='form-control form-control-sm ti_klasse' data-lusd='#{dp_h(k)}' value='#{dp_h(m[:target])}' maxlength='16'></td>"
            io.puts "<td>#{note.join('<br>')}</td></tr>"
        end
        io.puts "</tbody></table></div>"
        io.puts "<p><button class='btn btn-secondary btn-sm' id='bu_recheck'>Mit diesen Klassen neu prüfen</button></p>"
        io.puts "</details>"
    end

    # what changed against the draft: new, gone, changed (own classes, so the
    # sections of the main comparison keep theirs)
    def datenpflege_since_html(io, since)
        return unless since
        order = ->(r) { [LusdImport.klasse_sort_key(r[:klasse].to_s), r[:last_name].to_s, r[:first_name].to_s] }
        when_s = since[:created] ? Time.at(since[:created]).strftime('%d.%m.%Y, %H:%M') : ''
        io.puts "<div class='dp-since'>"
        io.puts "<h5>Seit dem #{since[:label]}</h5>"
        io.puts "<p class='text-muted'>Verglichen mit #{dp_h(since[:filename])}#{when_s.empty? ? '' : ", hochgeladen am #{when_s}"}: was sich in der LUSD seitdem geändert hat.</p>"
        moved = since[:moved].map { |o, n| [o, n, [['Name', o[:display_name], n[:display_name]]]] }
        changed = since[:changed] + moved
        if since[:added].empty? && since[:removed].empty? && changed.empty?
            io.puts "<p class='dp-since-none'>Keine Unterschiede.</p>"
        else
            datenpflege_section(io, 'dp-since-added', 'Neu dazugekommen',
                since[:added].sort_by(&order).map { |r| [dp_h(r[:display_name]), dp_h(r[:klasse])] }, %w(Name Klasse))
            datenpflege_section(io, 'dp-since-removed', 'Nicht mehr dabei',
                since[:removed].sort_by(&order).map { |r| [dp_h(r[:display_name]), dp_h(r[:klasse])] }, %w(Name Klasse))
            datenpflege_section(io, 'dp-since-changed', 'Geändert',
                changed.sort_by { |o, n, _| order.(n) }.map do |o, n, ch|
                    [dp_h(n[:display_name]), dp_h(n[:klasse]),
                     ch.map { |what, from, to| "<span class='dp-what'>#{what}</span> #{datenpflege_word_diff(from, to)}" }.join('<br>')]
                end, %w(Name Klasse Änderung))
        end
        io.puts "</div>"
    end

    def datenpflege_preview_html(c, since = nil)
        StringIO.open do |io|
            io.puts "<p class='dp-summary'>Im Export: <strong>#{c[:total]}</strong> Schüler:innen (#{dp_h(c[:filename])})."
            io.puts " Verglichen mit #{dp_h(File.basename(c[:old_path]))}.</p>"
            notes = []
            notes << "#{c[:duplicates]} doppelte Zeilen zusammengefasst (z. B. eine Zeile je Fremdsprache)" if c[:duplicates].to_i > 0
            notes << "#{c[:skipped]} Zeilen ohne Klasse und Stufe übersprungen (nicht oder nicht mehr an der Schule)" if c[:skipped].to_i > 0
            io.puts "<p class='text-muted dp-notes'>#{notes.join('. ')}.</p>" unless notes.empty?
            unless c[:errors].empty?
                io.puts "<div class='alert alert-danger dp-errors'><strong>#{c[:errors].size == 1 ? 'Ein Fehler' : "#{c[:errors].size} Fehler"} – so kann die Liste nicht übernommen werden:</strong><ul>"
                c[:errors].first(50).each { |e| io.puts "<li>#{dp_h(e)}</li>" }
                io.puts "<li>…</li>" if c[:errors].size > 50
                io.puts "</ul></div>"
                datenpflege_klassen_html(io, c)
                return io.string
            end

            datenpflege_since_html(io, since)
            local = ->(e) { dp_h(e.to_s.sub("@#{SCHUL_MAIL_DOMAIN}", '')) }
            by_email = (c[:students] || []).to_h { |st| [st.email, st] }
            order = ->(r) { [LusdImport.klasse_sort_key(r[:klasse].to_s), r[:last_name].to_s, r[:first_name].to_s] }
            io.puts "<h5>Änderungen gegenüber dem Dashboard</h5>"
            line = "Im Dashboard bisher <strong>#{c[:old_total]}</strong>, danach <strong>#{c[:new_total]}</strong> Schüler:innen; <strong>#{c[:kept]}</strong> behalten ihre Adresse."
            line += " #{c[:birthdays_added]} bekommen den bisher fehlenden Geburtstag." if c[:birthdays_added].to_i > 0
            io.puts "<p>#{line} Adressen ohne @#{dp_h(SCHUL_MAIL_DOMAIN)}.</p>"

            unless c[:moved].empty?
                datenpflege_section(io, 'dp-moved', 'Neue E-Mail-Adresse',
                    c[:moved].map { |o, n| [dp_h(n[:display_name]), dp_h(n[:klasse]), local.(o[:email]), local.(n[:email])] },
                    %w(Name Klasse bisher neu), hint: 'Nicht sicher zugeordnet: diese Konten würden durch neue ersetzt.')
            end
            # a new student: the address (can be changed), or an account of
            # someone no longer in the list it belongs to (same class or a
            # similar name)
            loose = ->(x) { remove_accents(x.to_s.downcase).gsub(/[^a-z]/, '') }
            loose_first = ->(x) { loose.(x.to_s.split(' ').first) }
            datenpflege_section(io, 'dp-added', 'Neu',
                c[:added].sort_by(&order).map do |r|
                    st = by_email[r[:email]]
                    row = st&.row
                    note = [st&.email_note ? "gekürzt, statt #{local.(st.email_note)}" : nil,
                            st&.email_taken ? 'Name schon vergeben, mit Nummer' : nil].compact.join('; ')
                    address = "<input class='form-control form-control-sm ti_email' data-row='#{row}' value='#{local.(r[:email])}' maxlength='23' aria-label='Adresse'>"
                    candidates = c[:removed].select do |o|
                        o[:klasse] == r[:klasse] || loose.(o[:last_name]) == loose.(r[:last_name]) ||
                            loose_first.(o[:official_first_name]) == loose_first.(r[:official_first_name])
                    end.sort_by(&order)
                    link = if candidates.empty?
                        ''
                    else
                        "<select class='form-control form-control-sm ti_link' data-row='#{row}' aria-label='Bestehendes Konto'>" +
                            "<option value=''>neues Konto</option>" +
                            candidates.map { |o| "<option value='#{dp_h(o[:email])}'>#{dp_h(o[:display_name])} (#{dp_h(o[:klasse])})</option>" }.join +
                            "</select>"
                    end
                    [dp_h(r[:display_name]), dp_h(r[:klasse]), address, link, note]
                end, ['Name', 'Klasse', 'Adresse', 'oder bestehendes Konto', 'Hinweis'],
                hint: 'Ist jemand schon im Dashboard, aber unter anderem Namen: das Konto auswählen, dann bleiben Adresse und Daten erhalten.')
            datenpflege_section(io, 'dp-removed', 'Nicht mehr dabei',
                c[:removed].sort_by(&order).map { |r| [dp_h(r[:display_name]), dp_h(r[:klasse]), local.(r[:email])] },
                %w(Name Klasse Adresse))
            datenpflege_section(io, 'dp-changed', 'Geändert',
                c[:changed].sort_by { |o, n, _| order.(n) }.map do |o, n, changes|
                    st = by_email[n[:email]]
                    manual = st&.matched_by == :von_hand ?
                        "Von Hand zugeordnet <button type='button' class='btn btn-link btn-sm p-0 bu_unlink' data-row='#{st.row}'>lösen</button><br>" : ''
                    [dp_h(n[:display_name]), dp_h(n[:klasse]),
                     manual + changes.map { |what, from, to| "<span class='dp-what'>#{what}</span> #{datenpflege_word_diff(from, to)}" }.join('<br>')]
                end, %w(Name Klasse Änderung))
            # where the dashboard keeps its own Rufname or gender: not a
            # change, but visible (closed)
            overridden = (c[:new_records] || []).select { |r| r[:overrides] }.sort_by(&order)
            unless overridden.empty?
                labels = { 'rufname' => 'Rufname', 'geschlecht' => 'Geschlecht' }
                datenpflege_section(io, 'dp-overridden', 'Im Dashboard anders als in der LUSD',
                    overridden.map do |r|
                        [dp_h(r[:display_name]), dp_h(r[:klasse]),
                         r[:overrides].map { |k, (lusd, own)| "<span class='dp-what'>#{labels[k]}</span> LUSD #{dp_h(lusd)}, Dashboard #{dp_h(own)}" }.join('<br>')]
                    end, %w(Name Klasse Unterschied), open: false,
                    hint: 'Festgelegt unter »Rufname und Geschlecht im Dashboard«: kein Unterschied, der übernommen wird.')
            end
            unless c[:dropped].empty?
                datenpflege_section(io, 'dp-dropped', 'Weggelassen (Klasse gibt es im Dashboard nicht)',
                    c[:dropped].sort_by(&order).map { |r| [dp_h(r[:display_name]), dp_h(r[:klasse])] }, %w(Name Klasse))
            end
            datenpflege_klassen_html(io, c)
            io.string
        end
    end

    # the choices on the page: {row => address} – rows as numbers, addresses
    # without the domain for wishes, with it for links
    def datenpflege_choices_param(h, max_value)
        return {} if h.nil?
        assert(h.is_a?(Hash) && h.size <= 2000)
        h.to_h do |k, v|
            assert(k.to_s =~ /\A\d{1,6}\z/ && v.is_a?(String) && v.size <= max_value)
            [k.to_i, v.strip.downcase]
        end
    end

    def datenpflege_respond_preview(pending, klassen, date, links = {}, emails = {})
        c = datenpflege_compare(pending, klassen, date, links, emails)
        since = datenpflege_since_draft(pending, c, klassen, date)
        draft = datenpflege_draft
        respond(:ok => true, :token => pending['token'], :html => datenpflege_preview_html(c, since),
                :can_apply => c[:errors].empty?,
                :existing => Parser.schueler_files.keys,
                :date => date.strftime('%Y-%m-%d'),
                # the choices in force (a new upload takes the draft's over)
                :links => links, :emails => emails,
                :is_draft => !draft.nil? && draft['token'] == pending['token'],
                :has_draft => !draft.nil?)
    end

    post '/api/datenpflege/schueler/upload' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:filename, :content, :date],
                                  :max_body_length => DATENPFLEGE_MAX_UPLOAD * 4 / 3 + 4096,
                                  :max_value_lengths => { :content => DATENPFLEGE_MAX_UPLOAD * 4 / 3 + 16 })
        date = datenpflege_valid_date(data[:date])
        assert(date, 'invalid date')
        ext = data[:filename].split('.').last.to_s.downcase
        unless DATENPFLEGE_EXTENSIONS.include?(ext)
            respond(:ok => false, :message => 'Bitte eine Excel-Datei (.xlsx) oder CSV-Datei hochladen. Eine ältere .xls-Datei in Excel als .xlsx speichern.')
            return
        end
        FileUtils.mkpath(DATENPFLEGE_PENDING_DIR)
        datenpflege_cleanup_pending
        token = SecureRandom.hex(16)
        tmp = datenpflege_pending_path(token, ext)
        begin
            File.binwrite(tmp, Base64.strict_decode64(data[:content]))
            rows = LusdImport.read_rows(tmp)
            # stops here if the columns can't be found
            LusdImport.convert(rows)
        rescue LusdImport::Error => e
            respond(:ok => false, :message => e.message)
            return
        rescue ArgumentError, CSV::MalformedCSVError, REXML::ParseException, Zlib::Error
            respond(:ok => false, :message => 'Die Datei konnte nicht gelesen werden.')
            return
        ensure
            File.delete(tmp) if File.exist?(tmp)
        end
        pending = { 'token' => token, 'filename' => File.basename(data[:filename]), 'rows' => rows,
                    'email' => @session_user[:email], 'created' => Time.now.to_i }
        File.write(datenpflege_pending_path(token), pending.to_json)
        # with a draft: its class names, accounts and addresses
        draft = datenpflege_draft
        if draft
            datenpflege_respond_preview(pending, draft['klassen'] || {}, date,
                                        datenpflege_choices_by_row(pending, draft['links']),
                                        datenpflege_choices_by_row(pending, draft['emails']))
        else
            datenpflege_respond_preview(pending, {}, date)
        end
    end

    def datenpflege_load_pending(token)
        path = datenpflege_pending_path(token)
        assert(File.exist?(path), 'upload expired')
        JSON.parse(File.read(path))
    end

    def datenpflege_klassen_param(klassen)
        assert(klassen.is_a?(Hash) && klassen.size <= 200)
        klassen.to_h do |k, v|
            assert(k.is_a?(String) && v.is_a?(String) && k.size <= 16 && v.size <= 16)
            [LusdImport.normalize_klasse(k), LusdImport.clean(v)]
        end
    end

    post '/api/datenpflege/schueler/preview' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token, :date, :klassen], :optional_keys => [:links, :emails],
                                  :types => { :klassen => Hash, :links => Hash, :emails => Hash }, :max_body_length => 262144)
        date = datenpflege_valid_date(data[:date])
        assert(date, 'invalid date')
        pending = datenpflege_load_pending(data[:token])
        klassen = datenpflege_klassen_param(data[:klassen])
        links = datenpflege_choices_param(data[:links], 100)
        emails = datenpflege_choices_param(data[:emails], 23)
        draft = datenpflege_draft
        if draft && draft['token'] == pending['token']
            datenpflege_save_draft(draft.merge('date' => date.strftime('%Y-%m-%d'), 'klassen' => klassen,
                'links' => datenpflege_choices_by_student(pending, links),
                'emails' => datenpflege_choices_by_student(pending, emails)))
        end
        datenpflege_respond_preview(pending, klassen, date, links, emails)
    end

    # keep this upload as the draft (replaces the one before, which stays
    # for one comparison)
    post '/api/datenpflege/schueler/keep' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token, :date, :klassen], :optional_keys => [:links, :emails],
                                  :types => { :klassen => Hash, :links => Hash, :emails => Hash }, :max_body_length => 262144)
        date = datenpflege_valid_date(data[:date])
        assert(date, 'invalid date')
        pending = datenpflege_load_pending(data[:token])
        klassen = datenpflege_klassen_param(data[:klassen])
        links = datenpflege_choices_param(data[:links], 100)
        emails = datenpflege_choices_param(data[:emails], 23)
        old = datenpflege_draft
        previous = old ? old['previous'] : nil
        if old && old['token'] != pending['token']
            datenpflege_delete_upload(old['previous']) unless old['previous'] == pending['token']
            previous = old['token']
        end
        datenpflege_save_draft('token' => pending['token'], 'previous' => previous,
            'date' => date.strftime('%Y-%m-%d'), 'klassen' => klassen,
            'links' => datenpflege_choices_by_student(pending, links),
            'emails' => datenpflege_choices_by_student(pending, emails),
            'email' => @session_user[:email], 'saved' => Time.now.to_i)
        datenpflege_respond_preview(pending, klassen, date, links, emails)
    end

    # the draft again, with its choices
    post '/api/datenpflege/schueler/draft' do
        require_data_manager!
        draft = datenpflege_draft
        unless draft
            respond(:ok => false, :message => 'Es gibt keinen Entwurf.')
            return
        end
        pending = datenpflege_load_pending(draft['token'])
        date = datenpflege_valid_date(draft['date']) || Date.today
        datenpflege_respond_preview(pending, draft['klassen'] || {}, date,
                                    datenpflege_choices_by_row(pending, draft['links']),
                                    datenpflege_choices_by_row(pending, draft['emails']))
    end

    post '/api/datenpflege/schueler/discard' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token])
        draft = datenpflege_draft
        if draft && draft['token'] == data[:token]
            # the draft goes, with the one before it
            datenpflege_delete_upload(draft['previous'])
            File.delete(datenpflege_draft_path) if File.exist?(datenpflege_draft_path)
        end
        datenpflege_delete_upload(data[:token])
        respond(:ok => true)
    end

    post '/api/datenpflege/schueler/apply' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token, :date, :klassen, :replace], :optional_keys => [:links, :emails],
                                  :types => { :klassen => Hash, :replace => Object, :links => Hash, :emails => Hash },
                                  :max_body_length => 262144)
        date = datenpflege_valid_date(data[:date])
        assert(date, 'invalid date')
        unless DataRepo.writable?
            respond(:ok => false, :message => 'Das Datenverzeichnis ist hier nicht beschreibbar (DATA_REPO_WRITABLE in env.rb).')
            return
        end
        pending = datenpflege_load_pending(data[:token])
        klassen = datenpflege_klassen_param(data[:klassen])
        c = datenpflege_compare(pending, klassen, date, datenpflege_choices_param(data[:links], 100),
                                datenpflege_choices_param(data[:emails], 23))
        unless c[:errors].empty?
            respond(:ok => false, :message => 'Die Liste hat noch Fehler.')
            return
        end
        rel = "schueler/#{date.strftime('%Y-%m-%d')}.TXT"
        if File.exist?(File.join(DataRepo.root, rel)) && data[:replace] != true
            respond(:ok => false, :message => "Für den #{date.strftime('%d.%m.%Y')} gibt es schon eine Liste.")
            return
        end
        DataRepo.write(DataRepo.root, rel, LusdImport.ascii_txt(c[:students]))
        tr = datenpflege_saved_klassen.merge(c[:mapping].to_h { |k, m| [k, m[:target]] }).reject { |k, v| k == v }
        DataRepo.write(DataRepo.root, DATENPFLEGE_KLASSEN_TR, tr.sort.to_h.to_yaml) unless tr.empty?
        # applied: the draft (if it was this one) is done
        draft = datenpflege_draft
        if draft && draft['token'] == data[:token]
            datenpflege_delete_upload(draft['previous'])
            File.delete(datenpflege_draft_path) if File.exist?(datenpflege_draft_path)
        end
        datenpflege_delete_upload(data[:token])
        DataVersion.bump!(DataVersion::PATH, "#{rel} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    def datenpflege_uncommitted
        return {} unless DataRepo.writable?
        DataRepo.uncommitted(DataRepo.root, ['schueler']).select { |rel, _| rel =~ DATENPFLEGE_MANAGED }
    end

    post '/api/datenpflege/commit' do
        require_data_manager!
        changes = datenpflege_uncommitted
        if changes.empty?
            respond(:ok => false, :message => 'Es gibt nichts zu committen.')
            return
        end
        names = changes.keys.map { |rel| File.basename(rel) }.join(', ')
        message = "Schüler:innen: #{names} (über das Dashboard, #{@session_user[:display_name]})"
        result = DataRepo.commit(DataRepo.root, changes.keys, message)
        respond(:ok => true, :commit => result[:commit], :pushed => result[:pushed],
                :push => DataRepo.push?, :push_error => result[:push_error])
    end

    post '/api/datenpflege/rollback' do
        require_data_manager!
        changes = datenpflege_uncommitted
        if changes.empty?
            respond(:ok => false, :message => 'Es gibt nichts zurückzunehmen.')
            return
        end
        DataRepo.rollback(DataRepo.root, changes.keys)
        DataVersion.bump!(DataVersion::PATH, "rollback by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    def print_datenpflege
        require_data_manager!
        StringIO.open do |io|
            current = Parser.schueler_path
            today = Date.today.strftime('%Y-%m-%d')
            count = @@user_info.values.count { |u| !u[:teacher] }
            io.puts "<p class='dp-current'>Im Dashboard: <strong>#{count}</strong> Schüler:innen aus <strong>#{dp_h(File.basename(current))}</strong>, gelesen am <span id='data_loaded_at'>#{@@data_loaded_at.strftime('%d.%m.%Y, %H:%M:%S')}</span>.</p>"
            unless DataRepo.writable?
                io.puts "<div class='alert alert-warning'>Das Datenverzeichnis ist hier nicht beschreibbar: Hochladen und Vergleichen geht, Übernehmen nicht (DATA_REPO_WRITABLE in env.rb).</div>"
            end
            draft = datenpflege_draft
            if draft
                pending = (datenpflege_load_pending(draft['token']) rescue nil)
                if pending
                    by = (@@user_info[draft['email']] || {})[:display_name] || draft['email']
                    io.puts "<div class='dp-draft' data-token='#{dp_h(draft['token'])}'>"
                    io.puts "<h5>Entwurf</h5>"
                    io.puts "<p>#{dp_h(pending['filename'])}, hochgeladen am #{Time.at(pending['created'].to_i).strftime('%d.%m.%Y, %H:%M')}, als Entwurf behalten von #{dp_h(by)}. Er gilt noch nirgends; ein neuer Export wird mit ihm verglichen.</p>"
                    io.puts "<p><button class='btn btn-secondary' id='bu_open_draft'>Entwurf öffnen</button></p>"
                    io.puts "</div>"
                end
            end
            changes = datenpflege_uncommitted
            unless changes.empty?
                io.puts "<div class='dp-uncommitted'>"
                io.puts "<h5>Noch nicht committet</h5><ul>"
                changes.each_pair { |rel, state| io.puts "<li>#{dp_h(rel)} (#{dp_h(state)})</li>" }
                io.puts "</ul>"
                io.puts "<p class='text-muted'>#{DataRepo.push? ? 'Committen schreibt die Änderung ins Daten-Repository und pusht sie.' : 'Committen schreibt die Änderung ins Daten-Repository (ohne Push).'} Zurücknehmen stellt den letzten Stand wieder her.</p>"
                io.puts "<p><button class='btn btn-secondary' id='bu_rollback'>Zurücknehmen</button> <button class='btn btn-success' id='bu_commit'>Committen</button></p>"
                io.puts "</div>"
            end
            files = Parser.schueler_files
            unless files.empty?
                io.puts "<h5>Listen</h5><div class='dp-scroll'><table class='table table-sm dp-files'><thead><tr><th>Gültig ab</th><th>Stand</th><th>Zeilen</th><th>Hochgeladen</th></tr></thead><tbody>"
                files.keys.sort.reverse.each do |date|
                    path = files[date]
                    state = date > today ? 'geplant' : (path == current ? 'aktuell' : 'abgelöst')
                    lines = File.read(path).lines.count { |l| !l.strip.empty? && l.strip[0] != '#' }
                    rel = "schueler/#{date}.TXT"
                    upload = if changes[rel]
                        'noch nicht committet'
                    elsif DataRepo.writable? && (entry = DataRepo.log(DataRepo.root, rel, 1).first)
                        "#{dp_h(Time.parse(entry[:date]).strftime('%d.%m.%Y, %H:%M'))}, #{dp_h(entry[:subject])}"
                    else
                        ''
                    end
                    io.puts "<tr class='dp-file-#{state}'><td>#{Date.parse(date).strftime('%d.%m.%Y')}</td><td>#{state}</td><td>#{lines}</td><td>#{upload}</td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.string
        end
    end

    # ---------- Rufname and gender the dashboard uses instead of LUSD's
    # (Parser.schueler_overrides) ----------

    # set (rufname and/or geschlecht) or, with both empty, remove
    post '/api/datenpflege/override' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email, :rufname, :geschlecht],
                                  :max_value_lengths => { :email => 128, :rufname => 40, :geschlecht => 1 })
        email = data[:email].strip.downcase
        info = @@user_info[email]
        assert(info && !info[:teacher] && info[:klasse], 'not a student')
        rufname = data[:rufname].strip
        geschlecht = data[:geschlecht].strip
        assert(rufname.empty? || rufname =~ DATENPFLEGE_RUFNAME, 'invalid rufname')
        assert(geschlecht.empty? || Parser::OVERRIDE_GENDERS.include?(geschlecht), 'invalid geschlecht')
        unless DataRepo.writable?
            respond(:ok => false, :message => 'Das Datenverzeichnis ist hier nicht beschreibbar (DATA_REPO_WRITABLE in env.rb).')
            return
        end
        overrides = Parser.schueler_overrides(File.join(DataRepo.root, DATENPFLEGE_OVERRIDES))
        if rufname.empty? && geschlecht.empty?
            overrides.delete(email)
        else
            entry = { 'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
            entry['rufname'] = rufname unless rufname.empty?
            entry['geschlecht'] = geschlecht unless geschlecht.empty?
            overrides[email] = entry
        end
        content = "# Rufname und Geschlecht im Dashboard statt der LUSD-Werte (nicht auf Zeugnissen),\n" +
                  "# gesetzt auf /datenpflege. Die Adresse bleibt.\n" + overrides.sort.to_h.to_yaml
        DataRepo.write(DataRepo.root, DATENPFLEGE_OVERRIDES, content)
        DataVersion.bump!(DataVersion::PATH, "#{DATENPFLEGE_OVERRIDES} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    def print_schueler_overrides
        require_data_manager!
        overrides = Parser.schueler_overrides
        students = @@user_info.select { |_, u| !u[:teacher] && u[:klasse] }.map do |email, u|
            o = overrides[email] || {}
            { :email => email, :label => "#{u[:official_first_name]} #{u[:last_name]} (#{u[:klasse]})",
              :rufname => o['rufname'].to_s, :geschlecht => o['geschlecht'].to_s }
        end.sort_by { |x| x[:label] }
        StringIO.open do |io|
            io.puts "<div class='dp-overrides'>"
            io.puts "<h5>Rufname und Geschlecht im Dashboard</h5>"
            io.puts "<p class='text-muted'>Für Schüler:innen, die in der LUSD noch mit altem Namen oder Geschlecht stehen. Gilt überall im Dashboard, nicht auf Zeugnissen; jeder neue LUSD-Export behält es. Die E-Mail-Adresse bleibt.</p>"
            unless overrides.empty?
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-override-list'><thead><tr><th>Name laut LUSD</th><th>Klasse</th><th>Rufname</th><th>Geschlecht</th><th>Gesetzt</th><th></th></tr></thead><tbody>"
                overrides.sort_by { |email, _| (@@user_info[email] || {})[:last_name].to_s }.each do |email, o|
                    u = @@user_info[email] || {}
                    by = (@@user_info[o['by']] || {})[:display_name] || o['by']
                    io.puts "<tr data-email='#{dp_h(email)}'><td>#{dp_h("#{u[:official_first_name]} #{u[:last_name]}".strip.empty? ? email : "#{u[:official_first_name]} #{u[:last_name]}")}</td><td>#{dp_h(u[:klasse])}</td>"
                    gender = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }[o['geschlecht']] || '–'
                    at = (Date.parse(o['at'].to_s).strftime('%d.%m.%Y') rescue o['at'].to_s)
                    io.puts "<td>#{dp_h(o['rufname'] || '–')}</td><td>#{dp_h(gender)}</td>"
                    io.puts "<td>#{dp_h(at)}, #{dp_h(by)}</td>"
                    io.puts "<td class='dp-row-actions'><button type='button' class='btn btn-secondary btn-sm bu_override_edit' data-email='#{dp_h(email)}'>Ändern</button> <button type='button' class='btn btn-secondary btn-sm bu_override_remove' data-email='#{dp_h(email)}'>Entfernen</button></td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<div class='dp-override-form'>"
            io.puts "<div class='dp-of-student'><label for='ti_override_student'>Schüler:in</label><input class='form-control' id='ti_override_student' list='dp_override_students' placeholder='Name oder Klasse' autocomplete='off'></div>"
            io.puts "<div class='dp-of-rufname'><label for='ti_override_rufname'>Rufname im Dashboard</label><input class='form-control' id='ti_override_rufname' maxlength='40' placeholder='wie in der LUSD'></div>"
            io.puts "<div class='dp-of-geschlecht'><label for='ti_override_geschlecht'>Geschlecht im Dashboard</label><select class='form-control' id='ti_override_geschlecht'><option value=''>wie in der LUSD</option><option value='m'>männlich</option><option value='w'>weiblich</option><option value='d'>divers</option></select></div>"
            io.puts "<div class='dp-of-save'><button type='button' class='btn btn-secondary' id='bu_override_save' disabled>Festlegen</button></div>"
            io.puts "</div>"
            io.puts "<datalist id='dp_override_students'>#{students.map { |x| "<option value='#{dp_h(x[:label])}'></option>" }.join}</datalist>"
            io.puts "<script type='application/json' id='dp_override_data'>#{students.to_json.gsub('</', '<\/')}</script>"
            io.puts "</div>"
            io.string
        end
    end

    # ---------- reports from students: a wrong name, an address that no
    # longer fits the name ----------
    # Names come from LUSD and are corrected there; an address stays as it
    # is unless the student asks for one that fits the name (moving the
    # account is a later step – for now the requests are collected).
    NAME_REPORT_KINDS = ['name', 'adresse']

    # the address that would fit the name now (nil if it already does)
    def name_report_fitting_email(email)
        info = @@user_info[email]
        return nil unless info
        parser = Parser.new
        plain = parser.name_to_email(info[:first_name], info[:last_name], false)
        return nil if email == plain || email.sub(/\.\d+@/, '@') == plain
        taken = Set.new(@@user_info.keys)
        datenpflege_new_email(parser, info[:first_name], info[:last_name], taken).first
    end

    def name_reports_open(email = nil)
        neo4j_query(<<~END_OF_QUERY, :email => email).map { |x| x['r'].merge(:email => x['email']) }
            MATCH (r:NameReport)-[:BELONGS_TO]->(u:User)
            WHERE r.done_ts IS NULL AND ($email IS NULL OR u.email = $email)
            RETURN r, u.email AS email
            ORDER BY r.ts;
        END_OF_QUERY
    end

    post '/api/name_report' do
        assert(schueler_logged_in?)
        data = parse_request_data(:required_keys => [:kind], :optional_keys => [:note],
                                  :max_body_length => 4096, :max_value_lengths => { :note => 1000 })
        assert(NAME_REPORT_KINDS.include?(data[:kind]))
        note = (data[:note] || '').strip
        assert(data[:kind] != 'name' || !note.empty?, 'empty report')
        email = @session_user[:email]
        proposed = data[:kind] == 'adresse' ? name_report_fitting_email(email) : nil
        assert(data[:kind] != 'adresse' || proposed, 'address fits')
        # one open report per kind: a second one replaces the text
        neo4j_query(<<~END_OF_QUERY, :email => email, :kind => data[:kind], :note => note, :proposed => proposed, :ts => Time.now.to_i, :id => RandomTag.generate(12))
            MATCH (u:User {email: $email})
            OPTIONAL MATCH (old:NameReport {kind: $kind})-[:BELONGS_TO]->(u) WHERE old.done_ts IS NULL
            DETACH DELETE old
            WITH u
            CREATE (r:NameReport {id: $id, kind: $kind, note: $note, proposed: $proposed, ts: $ts})-[:BELONGS_TO]->(u);
        END_OF_QUERY
        respond(:ok => true)
    end

    post '/api/name_report/done' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:id])
        neo4j_query(<<~END_OF_QUERY, :id => data[:id], :ts => Time.now.to_i, :by => @session_user[:email])
            MATCH (r:NameReport {id: $id})
            SET r.done_ts = $ts, r.done_by = $by;
        END_OF_QUERY
        respond(:ok => true)
    end

    # the box in the profile (students only): report a wrong name; where the
    # address no longer fits, a pointer to /passwoerter (the mailbox page)
    def print_name_report_box
        return '' unless schueler_logged_in?
        email = @session_user[:email]
        sent = name_reports_open(email).find { |x| x[:kind] == 'name' }
        StringIO.open do |io|
            io.puts "<div class='name-report' id='name_report'>"
            if name_report_fitting_email(email)
                io.puts "<p class='nr-mismatch'>Deine Adresse passt nicht mehr ganz zu deinem Namen. Du kannst sie behalten oder unter <a href='/passwoerter'>Passwörter</a> eine passende beantragen.</p>"
            end
            io.puts "<details class='nr-details'><summary>Stimmt etwas mit deinem Namen nicht?</summary>"
            io.puts "<p class='text-muted'>Schreib, was falsch ist und wie es richtig ist. Wir korrigieren es in der Schulverwaltung, danach stimmt es auch hier.</p>"
            io.puts "<textarea class='form-control' id='ti_name_report' rows='3' maxlength='1000'></textarea>"
            io.puts "<p style='margin-top: 0.5em;'><button type='button' class='btn btn-secondary btn-sm' id='bu_send_name_report'>Melden</button></p>"
            io.puts "</details>"
            io.puts "<p class='text-muted nr-sent'>Gemeldet am #{Time.at(sent[:ts]).strftime('%d.%m.%Y')}, wird bearbeitet.</p>" if sent
            io.puts "</div>"
            io.puts <<~END_OF_SCRIPT
                <script>
                document.addEventListener('DOMContentLoaded', function () {
                    $('#bu_send_name_report').on('click', function (e) {
                        let note = $('#ti_name_report').val().trim();
                        if (note.length === 0) { $('#ti_name_report').focus(); return; }
                        $(e.currentTarget).prop('disabled', true);
                        api_call('/api/name_report', { kind: 'name', note: note }, function (data) { if (data.success) location.reload(); });
                    });
                });
                </script>
            END_OF_SCRIPT
            io.string
        end
    end

    # on /passwoerter (students): an address that fits the name, on request
    def print_mail_address_request_section
        return '' unless schueler_logged_in?
        email = @session_user[:email]
        fitting = name_report_fitting_email(email)
        return '' unless fitting
        sent = name_reports_open(email).find { |x| x[:kind] == 'adresse' }
        StringIO.open do |io|
            io.puts "<h3 style='margin-top: 30px;'>Deine E-Mail-Adresse</h3>"
            io.puts "<p>Deine Adresse <strong>#{dp_h(email)}</strong> passt nicht mehr ganz zu deinem Namen, weil er sich geändert hat. Du kannst sie behalten – oder eine neue beantragen: <strong>#{dp_h(fitting)}</strong>.</p>"
            if sent
                io.puts "<p class='text-muted'>Beantragt am #{Time.at(sent[:ts]).strftime('%d.%m.%Y')}, wird bearbeitet.</p>"
            else
                io.puts "<p><button type='button' class='btn btn-secondary' id='bu_request_email'>Neue Adresse beantragen</button></p>"
                io.puts <<~END_OF_SCRIPT
                    <script>
                    document.addEventListener('DOMContentLoaded', function () {
                        $('#bu_request_email').on('click', function (e) {
                            $(e.currentTarget).prop('disabled', true);
                            api_call('/api/name_report', { kind: 'adresse' }, function (data) { if (data.success) location.reload(); });
                        });
                    });
                    </script>
                END_OF_SCRIPT
            end
            io.string
        end
    end

    # on /postfaecher (admins): the open requests for a new address – only
    # collected for now; moving an account comes later
    def print_mail_address_requests
        requests = name_reports_open.select { |r| r[:kind] == 'adresse' }
        return '' if requests.empty?
        StringIO.open do |io|
            io.puts "<h3 style='margin-top: 30px;'>Neue Adresse gewünscht</h3>"
            io.puts "<p class='text-muted'>Name oder Rufname haben sich geändert, die Adresse ist geblieben. Das Umziehen des Kontos kommt später; bis dahin von Hand erledigen und abhaken.</p>"
            io.puts "<div style='overflow-x: auto;'><table class='table table-sm' style='width: auto;'><thead><tr><th>Datum</th><th>Name</th><th>Klasse</th><th>bisher</th><th>gewünscht</th><th></th></tr></thead><tbody>"
            requests.each do |r|
                info = @@user_info[r[:email]] || {}
                io.puts "<tr><td>#{Time.at(r[:ts]).strftime('%d.%m.%Y')}</td><td>#{dp_h(info[:display_name] || r[:email])}</td><td>#{dp_h(info[:klasse])}</td>"
                io.puts "<td>#{dp_h(r[:email])}</td><td>#{dp_h(r[:proposed])}</td>"
                io.puts "<td><button type='button' class='btn btn-secondary btn-sm bu_report_done' data-id='#{dp_h(r[:id])}'>Erledigt</button></td></tr>"
            end
            io.puts "</tbody></table></div>"
            io.puts "<script>document.addEventListener('DOMContentLoaded', function () { $(document).on('click', '.bu_report_done', function (e) { let b = $(e.currentTarget); b.prop('disabled', true); api_call('/api/name_report/done', { id: b.data('id') }, function (data) { if (data.success) b.closest('tr').remove(); else b.prop('disabled', false); }); }); });</script>"
            io.string
        end
    end

    # on /datenpflege: the open reports
    def print_name_reports
        reports = name_reports_open.select { |r| r[:kind] == 'name' }
        return '' if reports.empty?
        StringIO.open do |io|
            io.puts "<h5>Meldungen von Schüler:innen</h5>"
            io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-reports'><thead><tr><th>Datum</th><th>Name</th><th>Klasse</th><th>Adresse</th><th>Meldung</th><th></th></tr></thead><tbody>"
            reports.each do |r|
                info = @@user_info[r[:email]] || {}
                text = dp_h(r[:note])
                io.puts "<tr><td>#{Time.at(r[:ts]).strftime('%d.%m.%Y')}</td><td>#{dp_h(info[:display_name] || r[:email])}</td><td>#{dp_h(info[:klasse])}</td>"
                io.puts "<td>#{dp_h(r[:email].to_s.sub("@#{SCHUL_MAIL_DOMAIN}", ''))}</td><td style='white-space: normal;'>#{text}</td>"
                io.puts "<td class='dp-row-actions'><button type='button' class='btn btn-secondary btn-sm bu_override_edit' data-email='#{dp_h(r[:email])}'>Im Dashboard festlegen</button> <button type='button' class='btn btn-secondary btn-sm bu_report_done' data-id='#{dp_h(r[:id])}'>Erledigt</button></td></tr>"
            end
            io.puts "</tbody></table></div>"
            io.string
        end
    end

end
