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
    DATENPFLEGE_MANAGED = %r{\Aschueler/(\d{4}-\d{2}-\d{2}\.TXT|lusd-klassen\.yaml|overrides\.yaml|zusaetzlich\.yaml|abgaenge\.yaml|im-ausland\.yaml|klassen-von-hand\.yaml)\z}
    DATENPFLEGE_OVERRIDES = 'schueler/overrides.yaml'
    # students added by hand and gone ones (Parser.schueler_extras)
    DATENPFLEGE_ADDED = 'schueler/zusaetzlich.yaml'
    DATENPFLEGE_GONE = 'schueler/abgaenge.yaml'
    # a student whose LUSD class the dashboard doesn't know, in a class
    # chosen by hand (person key => {klasse, name, by, at})
    DATENPFLEGE_KLASSE_HAND = 'schueler/klassen-von-hand.yaml'
    DATENPFLEGE_ABROAD = 'schueler/im-ausland.yaml'
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

    # a student of an export, the same in the next export: name and birthday
    # (LUSD's own number changes from one export to the next)
    def self.datenpflege_student_key(st)
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

    def datenpflege_parse_list(path, translate = nil, keep_gone: false, extras: Parser.schueler_extras, lenient: false)
        records = []
        Parser.new.parse_schueler(path, all_classes: true, translate_klasse: translate, keep_gone: keep_gone, extras: extras, lenient: lenient) { |r| records << r }
        records
    end

    # a student of an export as the same person (name and birthday)
    def datenpflege_person_key(st)
        Parser.manual_person_key(st.nachname, st.vorname, datenpflege_iso_date(st.geburtsdatum)).join('|')
    end

    def datenpflege_klassen_von_hand(dir = Parser::SCHUELER_DIR)
        Parser.read_yaml_hash(File.join(dir, File.basename(DATENPFLEGE_KLASSE_HAND)))
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
        # [how, key of a current record, key of an export row]: the same name
        # is the same person (never LUSD's number: it changes between
        # exports); then the address the old
        # rules gave (first import), the name spelled loosely, the birthday,
        # and finally the address built from Rufname and last name
        passes = [
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
        # (the particle in front, as in the address)
        nachname = Nachname.anzeige(nachname)
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
        extras = Parser.schueler_extras
        # the gone ones too: an export that still lists them gets their
        # address (and the list read with the extras leaves them out again)
        all_old = File.exist?(old_path) ? datenpflege_parse_list(old_path, keep_gone: true, extras: extras) : []
        old_records = all_old.reject { |r| r[:gone] }

        first = LusdImport.convert(rows, {})
        lusd_klassen = first[:students].map(&:lusd_klasse).uniq.sort_by { |k| LusdImport.klasse_sort_key(k) }
        parser = Parser.new
        matches = datenpflege_match_old(first[:students], all_old, parser)
        old_by_email = all_old.to_h { |r| [r[:email], r] }
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
        # a class the dashboard doesn't know: the one chosen by hand
        hand = datenpflege_klassen_von_hand
        result[:students].each do |st|
            next if KLASSEN_ORDER.include?(st.klasse)
            e = hand[datenpflege_person_key(st)]
            next unless e && KLASSEN_ORDER.include?(e['klasse'])
            st.klasse = e['klasse']
            st.klasse_hand = true
        end
        # addresses: whoever is in the dashboard keeps theirs
        taken = Set.new(all_old.map { |r| r[:email] }) + extras[:added].keys + extras[:gone].keys
        result[:students].each do |st|
            if (old, how = matches[st.row])
                st.email = old[:email]
                st.old_klasse = old[:klasse]
                st.matched_by = how
            end
        end
        # someone marked gone who has no account (new in LUSD): the address
        # of the entry, so it keeps them out
        gone_people = extras[:gone].each_with_object({}) do |(email, e), h|
            h[Parser.manual_person_key(e['nachname'], e['vornamen'], e['geburtstag']).join('|')] = email if e['nachname'] && e['geburtstag']
        end
        result[:students].each do |st|
            next if st.email
            st.email = gone_people[datenpflege_person_key(st)]
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
            :columns => LusdImport.column_report(rows),
            :filename => pending['filename'], :total => result[:students].size,
            :duplicates => result[:duplicates], :skipped => result[:skipped],
            :errors => result[:errors].map { |nr, text| "Zeile #{nr}: #{text}" } + wish_errors,
            :mapping => mapping, :old_path => old_path, :students => result[:students],
            :kept => matches.size,
            :shortened => result[:students].select { |st| st.email_note || st.email_taken },
            # still in LUSD, gone in the dashboard; added by hand, now in LUSD
            :gone_listed => result[:students].select { |st| extras[:gone].include?(st.email) },
            :manual_listed => result[:students].select { |st| extras[:added].include?(st.email) },
            :manual_waiting => extras[:added].size,
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

    # A change as in a word diff, inline: what stays once and plain, what
    # goes struck through on red, what comes on green – a second first name
    # added is just that name in green. Words and their separators (spaces,
    # hyphens) are compared; with nothing but separators in common the whole
    # value is replaced.
    def datenpflege_word_diff(from, to)
        from, to = from.to_s, to.to_s
        # spaces at the edges of a change stay outside the mark
        wrap = lambda do |x, tag, cls|
            core = x.strip
            core.empty? ? dp_h(x) : "#{dp_h(x[/\A\s*/])}<#{tag} class='#{cls}'>#{dp_h(core)}</#{tag}>#{dp_h(x[/\s*\z/])}"
        end
        old_html = ->(x) { x.empty? ? '' : wrap.(x, 'del', 'dp-old') }
        new_html = ->(x) { x.empty? ? '' : wrap.(x, 'ins', 'dp-new') }
        return "<span class='dp-old dp-none'>leer</span> #{new_html.(to)}" if from.empty?
        return "#{old_html.(from)} <span class='dp-new dp-none'>leer</span>" if to.empty?
        a = from.scan(/[^\s\-]+|[\s\-]+/)
        b = to.scan(/[^\s\-]+|[\s\-]+/)
        # longest common subsequence of the tokens
        len = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
        (a.size - 1).downto(0) do |i|
            (b.size - 1).downto(0) do |j|
                len[i][j] = a[i] == b[j] ? len[i + 1][j + 1] + 1 : [len[i + 1][j], len[i][j + 1]].max
            end
        end
        ops = []
        i = j = 0
        while i < a.size || j < b.size
            if i < a.size && j < b.size && a[i] == b[j]
                ops << [:same, a[i]]; i += 1; j += 1
            elsif j < b.size && (i == a.size || len[i][j + 1] >= len[i + 1][j])
                ops << [:add, b[j]]; j += 1
            else
                ops << [:del, a[i]]; i += 1
            end
        end
        unless ops.any? { |op, t| op == :same && t =~ /[^\s\-]/ }
            return "#{old_html.(from)}#{new_html.(to)}"
        end
        html = +''
        gone, added = +'', +''
        flush = lambda do
            html << old_html.(gone) << new_html.(added)
            gone, added = +'', +''
        end
        ops.each do |op, t|
            case op
            when :same then flush.(); html << dp_h(t)
            when :del then gone << t
            when :add then added << t
            end
        end
        flush.()
        html
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

    # which columns the export has and which are missing (and what for)
    def datenpflege_columns_html(io, columns)
        return unless columns
        missing = columns.reject { |x| x[:found] }
        io.puts "<details class='dp-columns'#{missing.any? { |x| x[:required] } ? ' open' : ''}>"
        io.puts "<summary>Spalten im Export: #{columns.size - missing.size} von #{columns.size}#{missing.empty? ? '' : ", es fehlen: #{dp_h(missing.map { |x| x[:label] }.join(', '))}"}</summary>"
        io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-column-list'><thead><tr><th>Spalte</th><th>Im Export als</th><th>Wofür</th></tr></thead><tbody>"
        columns.each do |x|
            state = x[:found] ? "<i class='fa fa-check text-success' aria-hidden='true'></i> #{dp_h(x[:found])}" :
                (x[:required] ? "<span class='text-danger'>fehlt (nötig)</span>" : "<span class='text-muted'>fehlt</span>")
            io.puts "<tr class='#{x[:found] ? 'dp-col-found' : 'dp-col-missing'}' data-field='#{x[:field]}'><td>#{dp_h(x[:label])}</td><td>#{state}</td><td class='text-muted' style='white-space: normal;'>#{dp_h(x[:purpose])}</td></tr>"
        end
        io.puts "</tbody></table></div></details>"
    end

    # What the Klassenleitungen said about the draft's new and leaving
    # students (include/schuelerliste.rb), only while the draft itself is
    # compared – that is what they checked: key => {:state, :text, :by}.
    # :here (a new one is here), :gone (a new one isn't, or a leaving one
    # goes), :note (a leaving one: their correction)
    def datenpflege_teacher_answers(pending)
        draft = datenpflege_draft
        return {} unless draft && pending && draft['token'] == pending['token']
        view = schuelerliste_view
        return {} if view.nil? || view[:errors]
        entries = {}
        view.each_value do |v|
            next unless v.is_a?(Hash) && v[:students]
            (v[:students] + v[:leaving]).each { |e| entries[e[:key]] = e }
        end
        answers = {}
        neo4j_query("MATCH (c:StudentCheck) RETURN c;").each do |x|
            c = x['c']
            entry = entries[c[:student]]
            next unless entry
            check = c.to_h.merge(:fields => (JSON.parse(c[:fields] || '{}') rescue {}))
            next unless schuelerliste_check_valid?(check, entry)
            leaving = entry.include?(:to) && !entry.include?(:geschlecht)
            answer = if check[:gone]
                { :state => :gone, :text => check[:gone_since] ? "nicht mehr an der Schule seit #{(Date.parse(check[:gone_since]).strftime('%d.%m.%Y') rescue check[:gone_since])}" : 'nicht mehr an der Schule' }
            elsif check[:status] == 'ok'
                { :state => leaving ? :gone : :here }
            elsif leaving
                { :state => :note, :text => check[:text].to_s }
            else
                { :state => :here }
            end
            answer[:by] = (@@user_info[check[:by]] || {})[:display_name] || check[:by]
            answers[c[:student]] = answer
        end
        answers
    end

    def datenpflege_teacher_note(a)
        return '' unless a && a[:text] && !a[:text].empty?
        "<span class='dp-teacher-note'>Klassenleitung (#{dp_h(a[:by])}): #{dp_h(a[:text])}</span>"
    end

    def datenpflege_preview_html(c, since = nil, answers = {})
        StringIO.open do |io|
            io.puts "<p class='dp-summary'>Im Export: <strong>#{c[:total]}</strong> Schüler:innen (#{dp_h(c[:filename])})."
            io.puts " Verglichen mit #{dp_h(File.basename(c[:old_path]))}.</p>"
            notes = []
            notes << "#{c[:duplicates]} doppelte Zeilen zusammengefasst (z. B. eine Zeile je Fremdsprache)" if c[:duplicates].to_i > 0
            notes << "#{c[:skipped]} Zeilen ohne Klasse und Stufe übersprungen (nicht oder nicht mehr an der Schule)" if c[:skipped].to_i > 0
            io.puts "<p class='text-muted dp-notes'>#{notes.join('. ')}.</p>" unless notes.empty?
            datenpflege_columns_html(io, c[:columns])
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
            # the Klassenleitung said who is here (or gone): their answers
            # shorten the lists, a contradiction stands in the row
            answer_for = ->(r) do
                st = by_email[r[:email]]
                answers[st ? (st.matched_by ? st.email : Main.datenpflege_student_key(st)) : r[:email]]
            end
            added_ok, added_open = c[:added].sort_by(&order).partition { |r| (answer_for.(r) || {})[:state] == :here }
            added_row = lambda do |r|
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
                    note = [note, st&.klasse_hand ? "Klasse von Hand (LUSD: #{dp_h(st.lusd_klasse)})" : nil].reject { |x| x.to_s.empty? }.join('; ')
                    note = [note, datenpflege_teacher_note(answer_for.(r))].reject { |x| x.to_s.empty? }.join('<br>')
                    gone = row ? "<button type='button' class='btn btn-secondary btn-sm bu_row_gone' data-row='#{row}' data-email='#{dp_h(r[:email])}'>Nicht mehr da</button>" : ''
                    [dp_h(r[:display_name]), dp_h(r[:klasse]), address, link, note, gone]
            end
            added_headers = ['Name', 'Klasse', 'Adresse', 'oder bestehendes Konto', 'Hinweis', '']
            datenpflege_section(io, 'dp-added', 'Neu', added_open.map(&added_row), added_headers,
                hint: 'Ist jemand schon im Dashboard, aber unter anderem Namen: das Konto auswählen, dann bleiben Adresse und Daten erhalten. Steht jemand in der LUSD, ist aber nicht (mehr) an der Schule: »Nicht mehr da«.' +
                      (added_ok.empty? ? '' : " Von der Klassenleitung bestätigte stehen darunter."))
            unless added_ok.empty?
                datenpflege_section(io, 'dp-added-ok', 'Neu, von der Klassenleitung bestätigt', added_ok.map(&added_row), added_headers, open: false)
            end
            removed_ok, removed_open = c[:removed].sort_by(&order).partition { |r| (answers[r[:email]] || {})[:state] == :gone }
            removed_row = lambda do |r|
                    [dp_h(r[:display_name]), dp_h(r[:klasse]), local.(r[:email]), datenpflege_teacher_note(answers[r[:email]]),
                     "<button type='button' class='btn btn-secondary btn-sm bu_row_keep' data-email='#{dp_h(r[:email])}'>Ist doch da</button> " +
                     "<button type='button' class='btn btn-secondary btn-sm bu_row_gone_now' data-email='#{dp_h(r[:email])}' data-name='#{dp_h(r[:display_name])}'>Nicht mehr da</button>"]
            end
            removed_headers = ['Name', 'Klasse', 'Adresse', 'Klassenleitung', '']
            datenpflege_section(io, 'dp-removed', 'Nicht mehr dabei', removed_open.map(&removed_row), removed_headers,
                hint: 'Fehlt jemand in der LUSD, ist aber noch da: »Ist doch da« behält sie:ihn von Hand, bis die LUSD sie:ihn wieder führt. »Nicht mehr da« meldet sofort im Dashboard ab, ohne auf die Übernahme zu warten.' +
                      (removed_ok.empty? ? '' : ' Die Klassenleitung hat bestätigt, dass die darunter gehen: nichts zu tun, sie gehen mit der Übernahme.'))
            unless removed_ok.empty?
                datenpflege_section(io, 'dp-removed-ok', 'Nicht mehr dabei, von der Klassenleitung bestätigt', removed_ok.map(&removed_row), removed_headers, open: false)
            end
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
            hand_rows = (c[:students] || []).select(&:klasse_hand).map do |st|
                [dp_h("#{st.vorname} #{Nachname.anzeige(st.nachname)}"), dp_h(st.klasse),
                 "Klasse von Hand statt #{dp_h(st.lusd_klasse)} aus der LUSD <button type='button' class='btn btn-link btn-sm p-0 bu_row_klasse_remove' data-key='#{dp_h(datenpflege_person_key(st))}'>lösen</button>"]
            end
            manual_rows = hand_rows + (c[:gone_listed] || []).map { |st| [dp_h("#{st.vorname} #{Nachname.anzeige(st.nachname)}"), dp_h(st.klasse), 'als abgegangen vermerkt: bleibt draußen, bis die LUSD sie:ihn nicht mehr führt'] } +
                          (c[:manual_listed] || []).map { |st| [dp_h("#{st.vorname} #{Nachname.anzeige(st.nachname)}"), dp_h(st.klasse), 'von Hand eingetragen, jetzt in der LUSD: der Eintrag endet, sobald diese Liste gilt'] }
            unless manual_rows.empty?
                datenpflege_section(io, 'dp-manual', 'Von Hand geführt', manual_rows, %w(Name Klasse Stand), open: !hand_rows.empty?,
                    hint: 'Festgelegt unter »Noch nicht in der LUSD« und »Nicht mehr an der Schule«: kein Unterschied, der übernommen wird.')
            end
            unless c[:dropped].empty?
                datenpflege_section(io, 'dp-dropped', 'Weggelassen (Klasse gibt es im Dashboard nicht)',
                    c[:dropped].sort_by(&order).map do |r|
                        row = by_email[r[:email]]&.row
                        actions = row ? "<select class='form-control form-control-sm ti_row_klasse' data-row='#{row}' aria-label='Ist da, in Klasse'>" +
                                        "<option value=''>ist da, in Klasse …</option>" + KLASSEN_ORDER.map { |k| "<option value='#{dp_h(k)}'>#{dp_h(tr_klasse(k))}</option>" }.join +
                                        "</select> <button type='button' class='btn btn-secondary btn-sm bu_row_gone' data-row='#{row}' data-email='#{dp_h(r[:email])}'>Nicht mehr da</button>" : ''
                        [dp_h(r[:display_name]), dp_h(r[:klasse]), actions]
                    end, ['Name', 'Klasse', ''],
                    hint: 'Ist jemand doch da: die Klasse wählen (gilt für jeden Export, bis die LUSD eine bekannte Klasse liefert). Sonst »Nicht mehr da«.')
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
        respond(:ok => true, :token => pending['token'], :html => datenpflege_preview_html(c, since, datenpflege_teacher_answers(pending)),
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
        rows = nil
        begin
            File.binwrite(tmp, Base64.strict_decode64(data[:content]))
            rows = LusdImport.read_rows(tmp)
            # stops here if the columns can't be found
            LusdImport.convert(rows)
        rescue LusdImport::Error => e
            # which columns are there and which are missing
            columns_html = rows ? StringIO.open { |io| datenpflege_columns_html(io, LusdImport.column_report(rows)); io.string } : nil
            respond(:ok => false, :message => e.message, :columns_html => columns_html)
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
        # gone meanwhile (applied, discarded, expired): said, not a server error
        unless File.exist?(datenpflege_pending_path(data[:token]))
            respond(:ok => false, :message => 'Dieser Upload ist nicht mehr da (übernommen, verworfen oder abgelaufen). Bitte die Datei noch einmal hochladen.')
            return
        end
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
            'email' => @session_user[:email], 'saved' => Time.now.to_i,
            # replaced by a new export: still released (or not) as before
            'released' => old ? old['released'] == true : false)
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
        datenpflege_extras_cleanup!
        datenpflege_commit!([rel, DATENPFLEGE_KLASSEN_TR, DATENPFLEGE_ADDED, DATENPFLEGE_GONE, DATENPFLEGE_KLASSE_HAND])
        # applied: the draft (if it was this one) is done, and with it the
        # teachers' check (personal data)
        draft = datenpflege_draft
        if draft && draft['token'] == data[:token]
            datenpflege_delete_upload(draft['previous'])
            File.delete(datenpflege_draft_path) if File.exist?(datenpflege_draft_path)
            schuelerliste_reset!
        end
        datenpflege_delete_upload(data[:token])
        DataVersion.bump!(DataVersion::PATH, "#{rel} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    def datenpflege_uncommitted
        return {} unless DataRepo.writable?
        DataRepo.uncommitted(DataRepo.root, ['schueler']).select { |rel, _| rel =~ DATENPFLEGE_MANAGED }
    end

    DATENPFLEGE_PUSH_ERROR = 'push-error.txt'

    # A change in the data repo is committed and pushed at once (decided
    # 2026-11-22): nothing waits for a step that can be forgotten. A failed
    # push is kept for the page (»Erneut schieben«); the commit stays.
    def datenpflege_commit!(rels)
        rels = DataRepo.uncommitted(DataRepo.root, rels).keys
        return nil if rels.empty?
        names = rels.map { |rel| File.basename(rel) }.join(', ')
        result = DataRepo.commit(DataRepo.root, rels, "Schüler:innen: #{names} (über das Dashboard, #{@session_user[:display_name]})")
        datenpflege_note_push(result[:push_error])
        result
    end

    def datenpflege_note_push(error)
        path = File.join(DATENPFLEGE_PENDING_DIR, DATENPFLEGE_PUSH_ERROR)
        if error
            FileUtils.mkpath(DATENPFLEGE_PENDING_DIR)
            File.write(path, error.to_s[0, 500])
        elsif File.exist?(path)
            File.delete(path)
        end
    end

    post '/api/datenpflege/push' do
        require_data_manager!
        begin
            DataRepo.push(DataRepo.root)
            datenpflege_note_push(nil)
            respond(:ok => true)
        rescue DataRepo::Error => e
            datenpflege_note_push(e.message)
            respond(:ok => false, :message => 'Das Schieben hat nicht geklappt.')
        end
    end

    # a list for a day still to come can be withdrawn (committed and pushed)
    post '/api/datenpflege/schueler/delete_list' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:date])
        date = datenpflege_valid_date(data[:date])
        assert(date && date > Date.today, 'only a list still to come')
        rel = "schueler/#{date.strftime('%Y-%m-%d')}.TXT"
        path = File.join(DataRepo.root, rel)
        assert(DataRepo.writable? && File.exist?(path), 'no such list')
        File.delete(path)
        datenpflege_extras_cleanup!
        datenpflege_commit!([rel, DATENPFLEGE_ADDED, DATENPFLEGE_GONE, DATENPFLEGE_KLASSE_HAND])
        respond(:ok => true, :reload => false)
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
                    io.puts "<p><button class='btn btn-secondary' id='bu_open_draft'>Entwurf öffnen</button> <a class='btn btn-secondary' href='/schuelerliste'>Wie die Klassenleitungen ihn sehen</a></p>"
                    io.puts "</div>"
                end
            end
            error_path = File.join(DATENPFLEGE_PENDING_DIR, DATENPFLEGE_PUSH_ERROR)
            unpushed = DataRepo.writable? && DataRepo.push? ? DataRepo.unpushed(DataRepo.root).to_i : 0
            if unpushed > 0 || File.exist?(error_path)
                io.puts "<div class='alert alert-warning dp-unpushed'>"
                io.puts "<p><strong>Noch nicht geschoben:</strong> #{unpushed == 1 ? 'eine Änderung ist' : "#{unpushed} Änderungen sind"} im Daten-Repository auf dem Server committet, aber nicht geschoben.</p>"
                io.puts "<p class='text-muted'>#{dp_h(File.read(error_path))}</p>" if File.exist?(error_path)
                io.puts "<p><button class='btn btn-secondary' id='bu_push'>Erneut schieben</button></p></div>"
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
                io.puts "<h5>Listen</h5><div class='dp-scroll'><table class='table table-sm dp-files'><thead><tr><th>Gültig ab</th><th>Stand</th><th>Zeilen</th><th>Hochgeladen</th><th></th></tr></thead><tbody>"
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
                    remove = state == 'geplant' && DataRepo.writable? ? "<button type='button' class='btn btn-secondary btn-sm bu_delete_list' data-date='#{dp_h(date)}'>Löschen</button>" : ''
                    io.puts "<tr class='dp-file-#{state}'><td>#{Date.parse(date).strftime('%d.%m.%Y')}</td><td>#{state}</td><td>#{lines}</td><td>#{upload}</td><td class='dp-row-actions'>#{remove}</td></tr>"
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
        datenpflege_commit!([DATENPFLEGE_OVERRIDES])
        DataVersion.bump!(DataVersion::PATH, "#{DATENPFLEGE_OVERRIDES} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    def print_schueler_overrides
        require_data_manager!
        overrides = Parser.schueler_overrides
        students = @@user_info.select { |_, u| !u[:teacher] && u[:klasse] }.map do |email, u|
            o = overrides[email] || {}
            { :email => email, :label => "#{u[:official_first_name]} #{Nachname.anzeige(u[:last_name])} (#{u[:klasse]})",
              :rufname => o['rufname'].to_s, :geschlecht => o['geschlecht'].to_s }
        end.sort_by { |x| x[:label] }
        StringIO.open do |io|
            io.puts "<div class='dp-overrides'>"
            io.puts "<h5>Rufname und Geschlecht im Dashboard</h5>"
            io.puts "<p class='text-muted'>Für Schüler:innen, die mit einem anderen Namen oder Geschlecht angesprochen werden möchten, als (noch) amtlich in der LUSD steht – etwa während einer Transition. Gilt überall im Dashboard, nicht auf Zeugnissen und nicht in der Schulverwaltung; jeder neue LUSD-Export behält es. Die E-Mail-Adresse bleibt.</p>"
            unless overrides.empty?
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-override-list'><thead><tr><th>Name laut LUSD</th><th>Klasse</th><th>Rufname</th><th>Geschlecht</th><th>Gesetzt</th><th></th></tr></thead><tbody>"
                overrides.sort_by { |email, _| (@@user_info[email] || {})[:last_name].to_s }.each do |email, o|
                    u = @@user_info[email] || {}
                    by = (@@user_info[o['by']] || {})[:display_name] || o['by']
                    official = "#{u[:official_first_name]} #{Nachname.anzeige(u[:last_name])}".strip
                    io.puts "<tr data-email='#{dp_h(email)}'><td>#{dp_h(official.empty? ? email : official)}</td><td>#{dp_h(u[:klasse])}</td>"
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

    # ---------- students not yet in LUSD, and students gone although LUSD
    # still lists them (Parser.schueler_extras) ----------

    DATENPFLEGE_NAME = /\A[\p{L}\p{M}][\p{L}\p{M}' .\-]{0,59}\z/u
    DATENPFLEGE_EXTRAS_HEADER = {
        DATENPFLEGE_ADDED => "# Schüler:innen, die das Dashboard schon führt, die LUSD aber noch nicht\n" +
                             "# (gesetzt auf /datenpflege). Endet von selbst, sobald eine Liste sie enthält.\n",
        DATENPFLEGE_GONE => "# Schüler:innen, die nicht mehr an der Schule sind, auch wenn die LUSD sie noch\n" +
                            "# führt (gesetzt auf /datenpflege). Endet von selbst, sobald keine Liste sie mehr enthält.\n",
        DATENPFLEGE_ABROAD => "# Schüler:innen, die eine Zeit im Ausland sind (gesetzt auf /datenpflege): Konto bleibt,\n" +
                              "# keine Klasse, Kurse, Verteiler, Zeugnisse bis zum Tag der Rückkehr ('zurueck').\n",
    }

    def datenpflege_extras_in_repo
        Parser.schueler_extras(File.join(DataRepo.root, 'schueler'))
    end

    def datenpflege_write_extras(rel, entries)
        DataRepo.write(DataRepo.root, rel, DATENPFLEGE_EXTRAS_HEADER[rel] + entries.sort.to_h.to_yaml)
    end

    # An entry ends once no list that holds now or later needs it: one added
    # by hand when every such list has the student (the address an import
    # took over, or the same name and birthday), a gone one when none still
    # lists them. Lists for a day still to come count – until then the
    # entry still works on today's list.
    def datenpflege_extras_cleanup!(token = nil)
        dir = File.join(DataRepo.root, 'schueler')
        extras = Parser.schueler_extras(dir)
        return if extras[:added].empty? && extras[:gone].empty?
        today = Date.today.strftime('%Y-%m-%d')
        paths = ([Parser.schueler_path(Date.today, dir)] + Parser.schueler_files(dir).select { |d, _| d > today }.values).uniq
        # the draft (and the upload a decision was made on) count like a list
        # still to come: a decision made in its comparison must not end at once
        draft = datenpflege_draft
        [draft && draft['token'], token].compact.uniq.each do |t|
            next unless t =~ /\A[a-z0-9]+\z/
            path = datenpflege_pending_path(t, 'TXT')
            paths << path if File.exist?(path)
        end
        lists = paths.select { |path| File.exist?(path) }.map do |path|
            # only who is listed: a line the comparison asks a decision for
            # (an address too long) doesn't stop it
            records = datenpflege_parse_list(path, nil, extras: Parser::NO_EXTRAS, lenient: true)
            [Set.new(records.map { |r| r[:email] }),
             Set.new(records.map { |r| Parser.manual_person_key(r[:last_name], r[:official_first_name], r[:geburtstag]) })]
        end
        added = extras[:added].select do |email, e|
            key = Parser.manual_person_key(e['nachname'], e['vornamen'], e['geburtstag'])
            lists.empty? || lists.any? { |emails, people| !emails.include?(email) && !people.include?(key) }
        end
        gone = extras[:gone].select { |email, _| lists.any? { |emails, _| emails.include?(email) } }
        datenpflege_write_extras(DATENPFLEGE_ADDED, added) if added.size != extras[:added].size
        datenpflege_write_extras(DATENPFLEGE_GONE, gone) if gone.size != extras[:gone].size
        datenpflege_abroad_cleanup!
    end

    # abroad: an entry whose return date has passed ends
    def datenpflege_abroad_cleanup!
        dir = File.join(DataRepo.root, 'schueler')
        all = Parser.schueler_abroad(dir)
        now = Parser.abroad_now(Date.today, dir)
        datenpflege_write_extras(DATENPFLEGE_ABROAD, now) if now.size != all.size
    end

    # the students (address and class) today's list gives with the entries
    # by hand as they are now – what the services would load
    def datenpflege_students_now
        dir = File.join(DataRepo.root, 'schueler')
        students = Set.new
        abroad = Parser.abroad_now(Date.today, dir)
        Parser.new.parse_schueler(Parser.schueler_path(Date.today, dir), extras: Parser.schueler_extras(dir), lenient: true) do |r|
            students << [r[:email], r[:klasse]] if KLASSEN_ORDER.include?(r[:klasse]) && !abroad.include?(r[:email])
        end
        students
    end

    # The services read the data again (about half a minute) only when the
    # students they have change: a decision about someone who is only in the
    # draft (new, a class by hand) or kept as already there changes nothing
    # in the dashboard yet – the comparison shows it at once.
    def datenpflege_extras_changed!(rel, token = nil)
        datenpflege_extras_cleanup!(token)
        datenpflege_commit!([DATENPFLEGE_ADDED, DATENPFLEGE_GONE, DATENPFLEGE_KLASSE_HAND, DATENPFLEGE_ABROAD])
        loaded = Main.class_variable_defined?(:@@loaded_students) ? @@loaded_students : nil
        if loaded && datenpflege_students_now == loaded
            respond(:ok => true, :reload => false, :dashboard_changed => false)
            return
        end
        DataVersion.bump!(DataVersion::PATH, "#{rel} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?, :dashboard_changed => true)
    end

    def datenpflege_require_writable!
        return true if DataRepo.writable?
        respond(:ok => false, :message => 'Das Datenverzeichnis ist hier nicht beschreibbar (DATA_REPO_WRITABLE in env.rb).')
        false
    end

    # a student not (yet) in LUSD: gets an address at once and counts like
    # everyone else until a list has them
    post '/api/datenpflege/manual/add' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:nachname, :vornamen, :klasse, :geschlecht, :geburtstag],
                                  :optional_keys => [:rufname, :bildungsgang, :notiz],
                                  :max_value_lengths => { :nachname => 60, :vornamen => 60, :rufname => 40, :klasse => 16,
                                                          :geschlecht => 1, :geburtstag => 10, :bildungsgang => 16, :notiz => 200 })
        nachname = data[:nachname].strip.gsub(/\s+/, ' ')
        vornamen = data[:vornamen].strip.gsub(/\s+/, ' ')
        rufname = data[:rufname].to_s.strip.gsub(/\s+/, ' ')
        assert(nachname =~ DATENPFLEGE_NAME && vornamen =~ DATENPFLEGE_NAME, 'invalid name')
        assert(rufname.empty? || rufname =~ DATENPFLEGE_RUFNAME, 'invalid rufname')
        assert(KLASSEN_ORDER.include?(data[:klasse]), 'invalid klasse')
        assert(Parser::OVERRIDE_GENDERS.include?(data[:geschlecht]), 'invalid geschlecht')
        geburtstag = datenpflege_valid_date(data[:geburtstag])
        assert(geburtstag && geburtstag < Date.today, 'invalid geburtstag')
        bildungsgang = data[:bildungsgang].to_s.strip
        assert(bildungsgang.empty? || Parser::BILDUNGSGAENGE.include?(bildungsgang), 'invalid bildungsgang')
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        current = datenpflege_parse_list(Parser.schueler_path, nil, keep_gone: true, extras: extras)
        key = Parser.manual_person_key(nachname, vornamen, geburtstag.strftime('%Y-%m-%d'))
        twin = current.find { |r| Parser.manual_person_key(r[:last_name], r[:official_first_name], r[:geburtstag]) == key }
        if twin
            respond(:ok => false, :message => twin[:gone] ? 'Diese Person ist als »nicht mehr an der Schule« vermerkt – dort zurücknehmen.' :
                                                            (twin[:manual] ? 'Diese Person ist schon von Hand eingetragen.' : 'Diese Person steht schon in der Liste.'))
            return
        end
        taken = Set.new(@@user_info.keys) + current.map { |r| r[:email] } + extras[:added].keys + extras[:gone].keys
        email, _, _ = datenpflege_new_email(Parser.new, LusdImport.effective_rufname(vornamen, rufname.empty? ? nil : rufname), nachname, taken)
        # the particle behind the name, as the lists keep it (nachname.rb)
        entry = { 'nachname' => Nachname.intern(nachname), 'vornamen' => vornamen, 'klasse' => data[:klasse], 'geschlecht' => data[:geschlecht],
                  'geburtstag' => geburtstag.strftime('%Y-%m-%d'), 'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        entry['rufname'] = rufname unless rufname.empty?
        entry['bildungsgang'] = bildungsgang unless bildungsgang.empty?
        entry['notiz'] = data[:notiz].strip unless data[:notiz].to_s.strip.empty?
        datenpflege_write_extras(DATENPFLEGE_ADDED, extras[:added].merge(email => entry))
        datenpflege_extras_changed!(DATENPFLEGE_ADDED)
    end

    post '/api/datenpflege/manual/remove' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :max_value_lengths => { :email => 128 })
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        assert(extras[:added].include?(data[:email]), 'no such entry')
        datenpflege_write_extras(DATENPFLEGE_ADDED, extras[:added].reject { |email, _| email == data[:email] })
        datenpflege_extras_changed!(DATENPFLEGE_ADDED)
    end

    # gone as far as the dashboard is concerned, at once; one added by hand
    # simply loses the entry
    post '/api/datenpflege/gone/add' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :optional_keys => [:seit, :notiz],
                                  :max_value_lengths => { :email => 128, :seit => 10, :notiz => 200 })
        email = data[:email].strip.downcase
        info = @@user_info[email]
        assert(info && !info[:teacher] && info[:klasse], 'not a student')
        seit = data[:seit].to_s.empty? ? nil : datenpflege_valid_date(data[:seit])
        assert(data[:seit].to_s.empty? || seit, 'invalid date')
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        if extras[:added].include?(email)
            datenpflege_write_extras(DATENPFLEGE_ADDED, extras[:added].reject { |e, _| e == email })
            datenpflege_extras_changed!(DATENPFLEGE_ADDED)
            return
        end
        entry = { 'name' => "#{info[:official_first_name]} #{info[:last_name]}", 'klasse' => info[:klasse],
                  'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        entry['seit'] = seit.strftime('%Y-%m-%d') if seit
        entry['notiz'] = data[:notiz].strip unless data[:notiz].to_s.strip.empty?
        datenpflege_write_extras(DATENPFLEGE_GONE, extras[:gone].merge(email => entry))
        datenpflege_extras_changed!(DATENPFLEGE_GONE)
    end

    post '/api/datenpflege/gone/remove' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :max_value_lengths => { :email => 128 })
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        assert(extras[:gone].include?(data[:email]), 'no such entry')
        datenpflege_write_extras(DATENPFLEGE_GONE, extras[:gone].reject { |email, _| email == data[:email] })
        datenpflege_extras_changed!(DATENPFLEGE_GONE)
    end

    # abroad for a while: the account stays, out of classes, courses, lists
    # and report cards until the return date (the first day back), then back
    # by itself
    post '/api/datenpflege/abroad/add' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :optional_keys => [:zurueck, :notiz],
                                  :max_value_lengths => { :email => 128, :zurueck => 10, :notiz => 200 })
        email = data[:email].strip.downcase
        info = @@user_info[email]
        assert(info && !info[:teacher] && info[:klasse], 'not a student')
        zurueck = data[:zurueck].to_s.empty? ? nil : datenpflege_valid_date(data[:zurueck])
        assert(data[:zurueck].to_s.empty? || (zurueck && zurueck > Date.today), 'invalid date')
        return unless datenpflege_require_writable!
        abroad = Parser.schueler_abroad(File.join(DataRepo.root, 'schueler'))
        entry = { 'name' => "#{info[:official_first_name]} #{info[:last_name]}", 'klasse' => info[:klasse],
                  'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        entry['zurueck'] = zurueck.strftime('%Y-%m-%d') if zurueck
        entry['notiz'] = data[:notiz].strip unless data[:notiz].to_s.strip.empty?
        datenpflege_write_extras(DATENPFLEGE_ABROAD, abroad.merge(email => entry))
        datenpflege_extras_changed!(DATENPFLEGE_ABROAD)
    end

    post '/api/datenpflege/abroad/remove' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :max_value_lengths => { :email => 128 })
        return unless datenpflege_require_writable!
        abroad = Parser.schueler_abroad(File.join(DataRepo.root, 'schueler'))
        assert(abroad.include?(data[:email]), 'no such entry')
        datenpflege_write_extras(DATENPFLEGE_ABROAD, abroad.reject { |email, _| email == data[:email] })
        datenpflege_extras_changed!(DATENPFLEGE_ABROAD)
    end

    # ---------- decisions in the comparison (Neu, Nicht mehr dabei,
    # Weggelassen) ----------

    # a student of an upload by export row
    def datenpflege_upload_student(token, row)
        pending = datenpflege_load_pending(token)
        st = LusdImport.convert(pending['rows'], {})[:students].find { |x| x.row == row.to_i }
        assert(st, 'no such row')
        st
    end

    # »nicht mehr da« for someone the export lists (new, or in a class the
    # dashboard doesn't know): kept out by name and birthday, under the
    # address the comparison gave them; someone with an account like
    # »Nicht mehr an der Schule«
    post '/api/datenpflege/row/gone' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token, :row, :email], :max_value_lengths => { :token => 32, :row => 8, :email => 128 })
        st = datenpflege_upload_student(data[:token], data[:row])
        email = data[:email].strip.downcase
        assert(email =~ /\A[a-z0-9][a-z0-9.\-]{0,40}@#{Regexp.escape(SCHUL_MAIL_DOMAIN)}\z/, 'invalid address')
        geburtstag = datenpflege_iso_date(st.geburtsdatum)
        assert(geburtstag, 'no birthday')
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        info = @@user_info[email]
        if info
            assert(!info[:teacher], 'not a student')
            if extras[:added].include?(email)
                datenpflege_write_extras(DATENPFLEGE_ADDED, extras[:added].reject { |e, _| e == email })
                datenpflege_extras_changed!(DATENPFLEGE_ADDED, data[:token])
                return
            end
        end
        entry = { 'name' => "#{st.vorname} #{st.nachname}", 'nachname' => st.nachname, 'vornamen' => st.vorname,
                  'geburtstag' => geburtstag, 'klasse' => (info || {})[:klasse] || st.lusd_klasse.to_s,
                  'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        datenpflege_write_extras(DATENPFLEGE_GONE, extras[:gone].merge(email => entry))
        datenpflege_extras_changed!(DATENPFLEGE_GONE, data[:token])
    end

    # »ist doch da« for someone the export no longer lists: kept by hand,
    # with the address and data the dashboard has now
    post '/api/datenpflege/row/keep' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:email], :optional_keys => [:token],
                                  :max_value_lengths => { :email => 128, :token => 32 })
        email = data[:email].strip.downcase
        info = @@user_info[email]
        assert(info && !info[:teacher] && info[:klasse], 'not a student')
        return unless datenpflege_require_writable!
        extras = datenpflege_extras_in_repo
        if extras[:gone].include?(email)
            respond(:ok => false, :message => 'Diese Person ist als »nicht mehr an der Schule« vermerkt – dort zurücknehmen.')
            return
        end
        r = datenpflege_parse_list(Parser.schueler_path, nil, extras: extras).find { |x| x[:email] == email }
        assert(r, 'not in the list')
        entry = { 'nachname' => r[:last_name], 'vornamen' => r[:official_first_name], 'klasse' => r[:klasse],
                  'geschlecht' => r[:geschlecht], 'geburtstag' => r[:geburtstag],
                  'notiz' => 'steht nicht mehr in der LUSD, ist aber noch da',
                  'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        entry['rufname'] = r[:first_name] if r[:first_name].to_s != r[:official_first_name].to_s.split(/[ -]/).first
        entry['bildungsgang'] = r[:bildungsgang].to_s if r[:bildungsgang]
        datenpflege_write_extras(DATENPFLEGE_ADDED, extras[:added].merge(email => entry.compact))
        datenpflege_extras_changed!(DATENPFLEGE_ADDED, data[:token])
    end

    # »ist da, in Klasse …« for someone in a class the dashboard doesn't
    # know (kept for every export until removed)
    post '/api/datenpflege/row/klasse' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:token, :row, :klasse], :max_value_lengths => { :token => 32, :row => 8, :klasse => 16 })
        assert(KLASSEN_ORDER.include?(data[:klasse]), 'invalid klasse')
        st = datenpflege_upload_student(data[:token], data[:row])
        assert(datenpflege_iso_date(st.geburtsdatum), 'no birthday')
        return unless datenpflege_require_writable!
        hand = datenpflege_klassen_von_hand(File.join(DataRepo.root, 'schueler'))
        hand[datenpflege_person_key(st)] = { 'klasse' => data[:klasse], 'name' => "#{st.vorname} #{st.nachname}",
                                             'lusd' => st.lusd_klasse.to_s, 'by' => @session_user[:email], 'at' => Date.today.strftime('%Y-%m-%d') }
        datenpflege_write_klassen_von_hand(hand)
        respond(:ok => true)
    end

    post '/api/datenpflege/row/klasse/remove' do
        require_data_manager!
        data = parse_request_data(:required_keys => [:key], :max_value_lengths => { :key => 200 })
        return unless datenpflege_require_writable!
        hand = datenpflege_klassen_von_hand(File.join(DataRepo.root, 'schueler'))
        assert(hand.include?(data[:key]), 'no such entry')
        hand.delete(data[:key])
        datenpflege_write_klassen_von_hand(hand)
        respond(:ok => true)
    end

    def datenpflege_write_klassen_von_hand(hand)
        DataRepo.write(DataRepo.root, DATENPFLEGE_KLASSE_HAND,
                       "# Schüler:innen, deren Klasse aus der LUSD das Dashboard nicht kennt, in einer von Hand\n" +
                       "# gewählten Klasse (gesetzt auf /datenpflege; Nachname|erster Vorname|Geburtstag).\n" + hand.sort.to_h.to_yaml)
        datenpflege_commit!([DATENPFLEGE_KLASSE_HAND])
    end

    def print_schueler_extras
        require_data_manager!
        extras = Parser.schueler_extras
        genders = { 'm' => 'männlich', 'w' => 'weiblich', 'd' => 'divers' }
        when_by = lambda do |e|
            at = (Date.parse(e['at'].to_s).strftime('%d.%m.%Y') rescue e['at'].to_s)
            "#{dp_h(at)}, #{dp_h((@@user_info[e['by']] || {})[:display_name] || e['by'])}"
        end
        local = ->(e) { dp_h(e.to_s.sub("@#{SCHUL_MAIL_DOMAIN}", '')) }
        StringIO.open do |io|
            io.puts "<div class='dp-manual-added'>"
            io.puts "<h5>Noch nicht in der LUSD</h5>"
            io.puts "<p class='text-muted'>Für Schüler:innen, die schon hier sind, aber noch nicht in unserer LUSD stehen (etwa weil die alte Schule sie noch nicht abgegeben hat). Sie bekommen sofort eine Adresse und zählen im Dashboard wie alle anderen. Sobald ein LUSD-Export sie enthält, übernimmt er die Adresse, und der Eintrag endet von selbst.</p>"
            unless extras[:added].empty?
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-manual-list'><thead><tr><th>Name</th><th>Klasse</th><th>Adresse</th><th>Notiz</th><th>Eingetragen</th><th></th></tr></thead><tbody>"
                extras[:added].sort_by { |_, e| [LusdImport.klasse_sort_key(e['klasse'].to_s), e['nachname'].to_s] }.each do |email, e|
                    name = [e['rufname'].to_s.empty? ? e['vornamen'] : "#{e['vornamen']} (#{e['rufname']})", Nachname.anzeige(e['nachname'])].join(' ')
                    io.puts "<tr data-email='#{dp_h(email)}'><td>#{dp_h(name)}</td><td>#{dp_h(e['klasse'])}</td><td>#{local.(email)}</td><td style='white-space: normal;'>#{dp_h(e['notiz'])}</td><td>#{when_by.(e)}</td>"
                    io.puts "<td class='dp-row-actions'><button type='button' class='btn btn-secondary btn-sm bu_manual_remove' data-email='#{dp_h(email)}' data-name='#{dp_h(name)}'>Entfernen</button></td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<div class='dp-manual-form'>"
            io.puts "<div class='dp-mf-wide'><label for='ti_manual_nachname'>Nachname</label><input class='form-control' id='ti_manual_nachname' maxlength='60' autocomplete='off'></div>"
            io.puts "<div class='dp-mf-wide'><label for='ti_manual_vornamen'>Vornamen</label><input class='form-control' id='ti_manual_vornamen' maxlength='60' autocomplete='off' placeholder='alle, wie im Ausweis'></div>"
            io.puts "<div class='dp-mf-mid'><label for='ti_manual_rufname'>Rufname</label><input class='form-control' id='ti_manual_rufname' maxlength='40' autocomplete='off' placeholder='der erste Vorname'></div>"
            io.puts "<div class='dp-mf-small'><label for='ti_manual_klasse'>Klasse</label><select class='form-control' id='ti_manual_klasse'><option value=''></option>#{KLASSEN_ORDER.map { |k| "<option value='#{dp_h(k)}'>#{dp_h(tr_klasse(k))}</option>" }.join}</select></div>"
            io.puts "<div class='dp-mf-small'><label for='ti_manual_geschlecht'>Geschlecht</label><select class='form-control' id='ti_manual_geschlecht'><option value=''></option>#{genders.map { |k, v| "<option value='#{k}'>#{v}</option>" }.join}</select></div>"
            io.puts "<div class='dp-mf-mid'><label for='ti_manual_geburtstag'>Geburtstag</label><input type='date' class='form-control' id='ti_manual_geburtstag'></div>"
            bgs = { 'altsprachlich' => 'altsprachlich', 'sesb' => 'SESB', 'regulaer_la' => 'regulär, Latein', 'regulaer_frz' => 'regulär, Französisch', 'regulaer' => 'regulär' }
            io.puts "<div class='dp-mf-mid'><label for='ti_manual_bildungsgang'>Bildungsgang</label><select class='form-control' id='ti_manual_bildungsgang'><option value=''>unbekannt</option>#{bgs.map { |k, v| "<option value='#{k}'>#{v}</option>" }.join}</select></div>"
            io.puts "<div class='dp-mf-wide'><label for='ti_manual_notiz'>Notiz</label><input class='form-control' id='ti_manual_notiz' maxlength='200' autocomplete='off' placeholder='z. B. woher, seit wann'></div>"
            io.puts "<div class='dp-mf-save'><button type='button' class='btn btn-secondary' id='bu_manual_add' disabled>Eintragen</button></div>"
            io.puts "</div></div>"

            gone_students = @@user_info.select { |email, u| !u[:teacher] && u[:klasse] && !extras[:gone].include?(email) }.map do |email, u|
                { :email => email, :label => "#{u[:official_first_name]} #{u[:last_name]} (#{u[:klasse]})" }
            end.sort_by { |x| x[:label] }
            io.puts "<div class='dp-manual-gone'>"
            io.puts "<h5>Nicht mehr an der Schule</h5>"
            io.puts "<p class='text-muted'>Für Schüler:innen, die gegangen sind, aber noch in der LUSD stehen. Für das Dashboard sind sie sofort weg (keine Anmeldung, nicht mehr in Klassen, Kursen und Verteilern), und jeder neue Export lässt sie weg. Sobald die LUSD sie nicht mehr führt, endet der Eintrag von selbst.</p>"
            unless extras[:gone].empty?
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-gone-list'><thead><tr><th>Name</th><th>Klasse</th><th>Seit</th><th>Notiz</th><th>Vermerkt</th><th></th></tr></thead><tbody>"
                extras[:gone].sort_by { |_, e| [LusdImport.klasse_sort_key(e['klasse'].to_s), e['name'].to_s] }.each do |email, e|
                    seit = (Date.parse(e['seit'].to_s).strftime('%d.%m.%Y') rescue '–')
                    io.puts "<tr data-email='#{dp_h(email)}'><td>#{dp_h(e['name'] || email)}</td><td>#{dp_h(e['klasse'])}</td><td>#{dp_h(seit)}</td><td style='white-space: normal;'>#{dp_h(e['notiz'])}</td><td>#{when_by.(e)}</td>"
                    io.puts "<td class='dp-row-actions'><button type='button' class='btn btn-secondary btn-sm bu_gone_remove' data-email='#{dp_h(email)}' data-name='#{dp_h(e['name'] || email)}'>Zurücknehmen</button></td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<div class='dp-manual-form'>"
            io.puts "<div class='dp-mf-wide'><label for='ti_gone_student'>Schüler:in</label><input class='form-control' id='ti_gone_student' list='dp_gone_students' placeholder='Name oder Klasse' autocomplete='off'></div>"
            io.puts "<div class='dp-mf-mid'><label for='ti_gone_seit'>Seit</label><input type='date' class='form-control' id='ti_gone_seit'></div>"
            io.puts "<div class='dp-mf-wide'><label for='ti_gone_notiz'>Notiz</label><input class='form-control' id='ti_gone_notiz' maxlength='200' autocomplete='off' placeholder='z. B. wohin'></div>"
            io.puts "<div class='dp-mf-save'><button type='button' class='btn btn-secondary' id='bu_gone_add' disabled>Vermerken</button></div>"
            io.puts "</div>"
            io.puts "<datalist id='dp_gone_students'>#{gone_students.map { |x| "<option value='#{dp_h(x[:label])}'></option>" }.join}</datalist>"
            io.puts "<script type='application/json' id='dp_gone_data'>#{gone_students.to_json.gsub('</', '<\/')}</script>"
            io.puts "</div>"

            abroad = Parser.schueler_abroad
            abroad_students = @@user_info.select { |email, u| !u[:teacher] && u[:klasse] && !abroad.include?(email) && !extras[:gone].include?(email) }.map do |email, u|
                { :email => email, :label => "#{u[:official_first_name]} #{u[:last_name]} (#{u[:klasse]})" }
            end.sort_by { |x| x[:label] }
            io.puts "<div class='dp-manual-abroad'>"
            io.puts "<h5>Im Ausland</h5>"
            io.puts "<p class='text-muted'>Für Schüler:innen, die eine Zeit im Ausland sind und danach zurückkommen; die LUSD führt sie weiter in ihrer Klasse. Ihr Konto, ihre Adresse und die Nextcloud bleiben, aber bis zur Rückkehr stehen sie in keiner Klasse, keinem Kurs, keinem Verteiler und auf keinem Zeugnis. Ab dem Tag der Rückkehr sind sie von selbst wieder dabei.</p>"
            unless abroad.empty?
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-abroad-list'><thead><tr><th>Name</th><th>Klasse</th><th>Zurück ab</th><th>Notiz</th><th>Vermerkt</th><th></th></tr></thead><tbody>"
                abroad.sort_by { |_, e| [LusdImport.klasse_sort_key(e['klasse'].to_s), e['name'].to_s] }.each do |email, e|
                    back = (Date.parse(e['zurueck'].to_s).strftime('%d.%m.%Y') rescue 'offen')
                    io.puts "<tr data-email='#{dp_h(email)}'><td>#{dp_h(e['name'] || email)}</td><td>#{dp_h(e['klasse'])}</td><td>#{dp_h(back)}</td><td style='white-space: normal;'>#{dp_h(e['notiz'])}</td><td>#{when_by.(e)}</td>"
                    io.puts "<td class='dp-row-actions'><button type='button' class='btn btn-secondary btn-sm bu_abroad_remove' data-email='#{dp_h(email)}' data-name='#{dp_h(e['name'] || email)}'>Wieder da</button></td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.puts "<div class='dp-manual-form'>"
            io.puts "<div class='dp-mf-wide'><label for='ti_abroad_student'>Schüler:in</label><input class='form-control' id='ti_abroad_student' list='dp_abroad_students' placeholder='Name oder Klasse' autocomplete='off'></div>"
            io.puts "<div class='dp-mf-mid'><label for='ti_abroad_zurueck'>Zurück ab</label><input type='date' class='form-control' id='ti_abroad_zurueck'></div>"
            io.puts "<div class='dp-mf-wide'><label for='ti_abroad_notiz'>Notiz</label><input class='form-control' id='ti_abroad_notiz' maxlength='200' autocomplete='off' placeholder='z. B. wo, Austauschprogramm'></div>"
            io.puts "<div class='dp-mf-save'><button type='button' class='btn btn-secondary' id='bu_abroad_add' disabled>Vermerken</button></div>"
            io.puts "</div>"
            io.puts "<datalist id='dp_abroad_students'>#{abroad_students.map { |x| "<option value='#{dp_h(x[:label])}'></option>" }.join}</datalist>"
            io.puts "<script type='application/json' id='dp_abroad_data'>#{abroad_students.to_json.gsub('</', '<\/')}</script>"
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


    # before an upload: the columns the LUSD query should have
    def print_datenpflege_columns_hint
        need = LusdImport::COLUMNS.select { |x| x[2] }.map { |x| x[1] }
        want = LusdImport::COLUMNS.reject { |x| x[2] }.map { |x| x[1] }
        "<p class='text-muted dp-columns-hint'>Spalten im Export: #{dp_h(need.join(', '))} (nötig); #{dp_h(want.join(', '))} (empfohlen). Nach dem Hochladen steht da, welche gefunden wurden.</p>"
    end
end
