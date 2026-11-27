# Datenpflege, the timetable (/datenpflege_stundenplan, role
# can_manage_timetable – the students' data has its own page and role): the Untis
# export – an HTML export of the teacher and class timetables as a ZIP – is
# uploaded with the day it applies from and compared with the timetable
# valid until then, read by the same parser the services use (lessons per
# class, break duties, names the dashboard doesn't know). Applied, it goes
# into the data repository as stundenplan/<day>.zip, is committed, and the
# services read the data again. A plan for a day still to come can be
# deleted before it applies.
class Main < Sinatra::Base
    STUNDENPLAN_DIR = 'stundenplan'
    STUNDENPLAN_MAX_UPLOAD = 5 * 1024 * 1024

    def stundenplan_pending_path(token)
        assert(token.is_a?(String) && token =~ /\A[0-9a-f]{32}\z/, 'invalid token')
        File.join(DATENPFLEGE_PENDING_DIR, "stundenplan-#{token}.zip")
    end

    def stundenplan_dir
        File.join(DataRepo.root, STUNDENPLAN_DIR)
    end

    # the timetable sources by day ('YYYY-MM-DD' => path), as the services
    # read them (Parser#timetable_sources: ZIPs and the older TXT files)
    def stundenplan_sources
        Parser.new.timetable_sources('/data/stundenplan')
    end

    # the rows of the timetable valid until day: every source before it in
    # order, each read with the one before as reference (parse_timetable)
    def stundenplan_rows_until(day)
        parser = Parser.new
        rows = []
        stundenplan_sources.each_pair do |d, path|
            break if d >= day
            rows = path.end_with?('.zip') ? parser.untis_zip_timetable_rows(path, rows) : parser.read_txt_rows(path)
        end
        rows
    end

    def stundenplan_aufsichten_until(day)
        parser = Parser.new
        rows = []
        parser.timetable_sources('/data/pausenaufsichten').each_pair do |d, path|
            break if d >= day
            rows = if path.end_with?('.zip')
                parser.read_untis_zip(path)[:pausenaufsichten]
            else
                parser.read_txt_rows(path, File.basename(path) >= '2020-10-26.TXT' ? 'r:utf-8' : 'r:iso-8859-1')
            end
        end
        # (a row that doesn't split into its four columns doesn't count)
        rows.map { |r| r[0, 4].map(&:to_s) }.reject { |r| r.size < 4 || r.any?(&:empty?) }
    end

    # Two timetables compared slot by slot: {klasse => [{:dow, :stunde,
    # :before => [[lehrer, fach, raum]], :after => …}]} for every slot that
    # differs, and counts. Rows as the parser gives them: [unr, klasse,
    # lehrer, fach, raum, dow, stunde] (the Unterrichtsnummer doesn't count).
    def self.stundenplan_diff(before_rows, after_rows)
        slots = lambda do |rows|
            result = Hash.new { |h, k| h[k] = Set.new }
            rows.each do |r|
                next if r[3].to_s.strip.empty?
                result[[Parser.timetable_klasse(r[1].to_s), r[5].to_i, r[6].to_i]] << [r[2].to_s, r[3].to_s, r[4].to_s]
            end
            result
        end
        before = slots.(before_rows)
        after = slots.(after_rows)
        klassen = {}
        counts = { :added => 0, :removed => 0, :changed => 0 }
        lehrer = Set.new
        (before.keys | after.keys).sort_by { |k, dow, stunde| [k, dow, stunde] }.each do |klasse, dow, stunde|
            b = before.fetch([klasse, dow, stunde], Set.new)
            a = after.fetch([klasse, dow, stunde], Set.new)
            next if a == b
            gone = (b - a).to_a.sort
            came = (a - b).to_a.sort
            if gone.empty? then counts[:added] += 1
            elsif came.empty? then counts[:removed] += 1
            else counts[:changed] += 1 end
            (gone + came).each { |x| lehrer << x[0] }
            (klassen[klasse] ||= []) << { :dow => dow, :stunde => stunde, :before => gone, :after => came }
        end
        counts.merge(:klassen => klassen, :lehrer => lehrer.to_a.sort)
    end

    # break duties: [where, lehrer, dow, stunde], what is new and what goes
    def self.stundenplan_aufsichten_diff(before, after)
        b = Set.new(before)
        a = Set.new(after)
        order = ->(x) { [x[2].to_i, x[3].to_i, x[0], x[1]] }
        { :added => (a - b).to_a.sort_by(&order), :removed => (b - a).to_a.sort_by(&order) }
    end

    # what the dashboard doesn't know: teachers' shorthands, classes
    def stundenplan_unknown(rows)
        lehrer = rows.map { |r| r[2].to_s }.reject { |x| x.empty? || x == '?' }.uniq
        klassen = rows.map { |r| Parser.timetable_klasse(r[1].to_s) }.reject(&:empty?).uniq
        { :lehrer => (lehrer - @@shorthands.keys).sort, :klassen => (klassen - KLASSEN_ORDER).sort }
    end

    DOW_NAMES = %w(Mo Di Mi Do Fr Sa So)

    def stundenplan_preview_html(token, day)
        path = stundenplan_pending_path(token)
        parser = Parser.new
        before_rows = stundenplan_rows_until(day)
        after_rows = parser.untis_zip_timetable_rows(path, before_rows)
        h = ->(x) { CGI.escapeHTML(x.to_s) }
        StringIO.open do |io|
            if after_rows.empty?
                io.puts "<div class='alert alert-warning'>Im ZIP fand sich kein Stundenplan: Erwartet wird der HTML-Export der Lehrer- und Klassenpläne aus Untis.</div>"
                return [io.string, false]
            end
            diff = Main.stundenplan_diff(before_rows, after_rows)
            aufsichten = Main.stundenplan_aufsichten_diff(stundenplan_aufsichten_until(day), parser.read_untis_zip(path)[:pausenaufsichten].map { |r| r[0, 4].map(&:to_s) })
            unknown = stundenplan_unknown(after_rows)
            stunden = after_rows.map { |r| [Parser.timetable_klasse(r[1].to_s), r[5], r[6]] }.uniq.size
            klassen_n = after_rows.map { |r| Parser.timetable_klasse(r[1].to_s) }.uniq.size
            lehrer_n = after_rows.map { |r| r[2] }.uniq.size
            io.puts "<p class='dp-sp-summary'>Im Export: <strong>#{klassen_n}</strong> Klassen und Kurse, <strong>#{lehrer_n}</strong> Lehrkräfte, <strong>#{stunden}</strong> belegte Stunden.</p>"
            changes = diff[:added] + diff[:removed] + diff[:changed]
            if changes == 0 && aufsichten[:added].empty? && aufsichten[:removed].empty?
                io.puts "<p class='dp-sp-same'>Gegenüber dem bisherigen Stundenplan ändert sich nichts.</p>"
            else
                io.puts "<p class='dp-sp-changes'>Gegenüber dem bisherigen Stundenplan: <strong>#{diff[:changed]}</strong> geändert, <strong>#{diff[:added]}</strong> neu, <strong>#{diff[:removed]}</strong> entfallen – in #{diff[:klassen].size} #{diff[:klassen].size == 1 ? 'Klasse' : 'Klassen und Kursen'}, bei #{diff[:lehrer].size} #{diff[:lehrer].size == 1 ? 'Lehrkraft' : 'Lehrkräften'}.</p>"
            end
            unless unknown[:lehrer].empty? && unknown[:klassen].empty?
                io.puts "<div class='alert alert-warning dp-sp-unknown'>Kennt das Dashboard nicht:"
                io.puts " Kürzel #{unknown[:lehrer].map { |x| "<strong>#{h.(x)}</strong>" }.join(', ')}." unless unknown[:lehrer].empty?
                io.puts " Klassen #{unknown[:klassen].map { |x| "<strong>#{h.(x)}</strong>" }.join(', ')}." unless unknown[:klassen].empty?
                io.puts " Ihr Unterricht erscheint bei niemandem.</div>"
            end
            lesson = ->(x) { "#{h.(x[1])} #{h.(x[0])}#{x[2].empty? ? '' : " #{h.(x[2])}"}" }
            diff[:klassen].each_pair do |klasse, slots|
                io.puts "<details class='dp-section dp-sp-klasse' data-klasse='#{h.(klasse)}'>"
                io.puts "<summary>#{h.(tr_klasse(klasse))}: <strong class='dp-count'>#{slots.size}</strong></summary>"
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list dp-sp-list'><thead><tr><th>Stunde</th><th>bisher</th><th>neu</th></tr></thead><tbody>"
                slots.each do |s|
                    io.puts "<tr><td>#{DOW_NAMES[s[:dow] - 1] rescue s[:dow]} #{s[:stunde]}.</td>" +
                            "<td>#{s[:before].empty? ? '–' : s[:before].map { |x| "<span class='dp-old'>#{lesson.(x)}</span>" }.join('<br>')}</td>" +
                            "<td>#{s[:after].empty? ? 'entfällt' : s[:after].map { |x| "<span class='dp-new'>#{lesson.(x)}</span>" }.join('<br>')}</td></tr>"
                end
                io.puts "</tbody></table></div></details>"
            end
            unless aufsichten[:added].empty? && aufsichten[:removed].empty?
                io.puts "<details class='dp-section dp-sp-aufsichten'>"
                io.puts "<summary>Aufsichten: <strong class='dp-count'>#{aufsichten[:added].size + aufsichten[:removed].size}</strong></summary>"
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list'><thead><tr><th>Wann</th><th>Wo</th><th>Wer</th><th></th></tr></thead><tbody>"
                (aufsichten[:removed].map { |x| [x, 'entfällt'] } + aufsichten[:added].map { |x| [x, 'neu'] }).sort_by { |x, _| [x[2].to_i, x[3].to_i, x[0]] }.each do |x, what|
                    io.puts "<tr><td>#{DOW_NAMES[x[2].to_i - 1]} vor der #{h.(x[3])}.</td><td>#{h.(x[0])}</td><td>#{h.(x[1])}</td><td>#{what}</td></tr>"
                end
                io.puts "</tbody></table></div></details>"
            end
            return [io.string, true]
        end
    end

    def stundenplan_respond_preview(token, day)
        html, ok = stundenplan_preview_html(token, day.strftime('%Y-%m-%d'))
        rel = "#{STUNDENPLAN_DIR}/#{day.strftime('%Y-%m-%d')}"
        respond(:ok => true, :token => token, :html => html, :can_apply => ok,
                :replacing => File.exist?(File.join(DataRepo.root, "#{rel}.zip")),
                # a TXT for that day wins over a ZIP (Parser#timetable_sources)
                :txt_wins => File.exist?(File.join(DataRepo.root, "#{rel}.TXT")))
    end

    post '/api/datenpflege/stundenplan/upload' do
        require_timetable_manager!
        data = parse_request_data(:required_keys => [:filename, :content, :date],
                                  :max_body_length => STUNDENPLAN_MAX_UPLOAD * 4 / 3 + 4096,
                                  :max_value_lengths => { :content => STUNDENPLAN_MAX_UPLOAD * 4 / 3 + 16, :filename => 200 })
        day = datenpflege_valid_date(data[:date])
        assert(day, 'invalid date')
        content = Base64.decode64(data[:content])
        unless content.start_with?("PK\x03\x04".b)
            respond(:ok => false, :message => 'Das ist keine ZIP-Datei. Erwartet wird der HTML-Export der Lehrer- und Klassenpläne aus Untis als ZIP.')
            return
        end
        token = SecureRandom.hex(16)
        FileUtils.mkpath(DATENPFLEGE_PENDING_DIR)
        File.binwrite(stundenplan_pending_path(token), content)
        begin
            stundenplan_respond_preview(token, day)
        rescue Zip::Error, StandardError => e
            File.delete(stundenplan_pending_path(token)) rescue nil
            debug "Stundenplan-Upload nicht lesbar: #{e.class}"
            respond(:ok => false, :message => 'Die ZIP-Datei ließ sich nicht lesen.')
        end
    end

    # the same upload for another day
    post '/api/datenpflege/stundenplan/preview' do
        require_timetable_manager!
        data = parse_request_data(:required_keys => [:token, :date])
        day = datenpflege_valid_date(data[:date])
        assert(day, 'invalid date')
        unless File.exist?(stundenplan_pending_path(data[:token]))
            respond(:ok => false, :message => 'Dieser Upload ist nicht mehr da. Bitte die Datei noch einmal hochladen.')
            return
        end
        stundenplan_respond_preview(data[:token], day)
    end

    post '/api/datenpflege/stundenplan/apply' do
        require_timetable_manager!
        data = parse_request_data(:required_keys => [:token, :date], :optional_keys => [:replace],
                                  :types => { :replace => Object })
        day = datenpflege_valid_date(data[:date])
        assert(day, 'invalid date')
        path = stundenplan_pending_path(data[:token])
        unless File.exist?(path)
            respond(:ok => false, :message => 'Dieser Upload ist nicht mehr da. Bitte die Datei noch einmal hochladen.')
            return
        end
        return unless datenpflege_require_writable!
        rel = "#{STUNDENPLAN_DIR}/#{day.strftime('%Y-%m-%d')}"
        if File.exist?(File.join(DataRepo.root, "#{rel}.TXT"))
            respond(:ok => false, :message => "Für den #{day.strftime('%d.%m.%Y')} gibt es eine TXT-Datei, die Vorrang hätte. Bitte einen anderen Tag wählen.")
            return
        end
        if File.exist?(File.join(DataRepo.root, "#{rel}.zip")) && data[:replace] != true
            respond(:ok => false, :message => "Für den #{day.strftime('%d.%m.%Y')} gibt es schon einen Stundenplan. Zum Ersetzen bitte bestätigen.")
            return
        end
        FileUtils.mkpath(stundenplan_dir)
        DataRepo.write_binary(DataRepo.root, "#{rel}.zip", File.binread(path))
        result = DataRepo.commit(DataRepo.root, ["#{rel}.zip"], "Stundenplan: #{File.basename(rel)}.zip (über das Dashboard, #{@session_user[:display_name]})")
        datenpflege_note_push(result[:push_error])
        File.delete(path) rescue nil
        DataVersion.bump!(DataVersion::PATH, "stundenplan #{File.basename(rel)} by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    post '/api/datenpflege/stundenplan/discard' do
        require_timetable_manager!
        data = parse_request_data(:required_keys => [:token])
        path = stundenplan_pending_path(data[:token])
        File.delete(path) if File.exist?(path)
        respond(:ok => true)
    end

    # a plan for a day still to come, before it applies
    post '/api/datenpflege/stundenplan/delete' do
        require_timetable_manager!
        data = parse_request_data(:required_keys => [:date])
        day = datenpflege_valid_date(data[:date])
        assert(day && day > Date.today, 'only a plan still to come')
        return unless datenpflege_require_writable!
        rel = "#{STUNDENPLAN_DIR}/#{day.strftime('%Y-%m-%d')}.zip"
        assert(File.exist?(File.join(DataRepo.root, rel)), 'no such plan')
        File.delete(File.join(DataRepo.root, rel))
        result = DataRepo.commit(DataRepo.root, [rel], "Stundenplan: #{File.basename(rel)} gelöscht (über das Dashboard, #{@session_user[:display_name]})")
        datenpflege_note_push(result[:push_error])
        DataVersion.bump!(DataVersion::PATH, "stundenplan #{File.basename(rel)} deleted by #{@session_user[:email]}")
        respond(:ok => true, :reload => DataVersion.restarts?)
    end

    # /datenpflege_stundenplan: the plan in force, the plans there are, the upload
    def print_stundenplan_datenpflege
        require_timetable_manager!
        today = Date.today.strftime('%Y-%m-%d')
        sources = stundenplan_sources
        current = sources.keys.select { |d| d <= today }.max
        h = ->(x) { CGI.escapeHTML(x.to_s) }
        StringIO.open do |io|
            io.puts "<div class='dp-stundenplan'>"
            in_force = current ? "der Stundenplan aus <strong>#{h.(File.basename(sources[current]))}</strong>" : 'noch kein Stundenplan'
            io.puts "<p class='dp-current'>Im Dashboard: #{in_force}, gelesen am <span id='data_loaded_at'>#{@@data_loaded_at.strftime('%d.%m.%Y, %H:%M:%S')}</span>.</p>"
            unless DataRepo.writable?
                io.puts "<div class='alert alert-warning'>Das Datenverzeichnis ist hier nicht beschreibbar: Hochladen und Vergleichen geht, Übernehmen nicht (DATA_REPO_WRITABLE in env.rb).</div>"
            end
            io.puts print_data_repo_unpushed
            io.puts "<p class='text-muted'>Der HTML-Export der Lehrer- und Klassenpläne aus Untis als ZIP. Hochladen ändert noch nichts: Erst kommt der Vergleich mit dem Stundenplan, der bis zum gewählten Tag gilt – jede geänderte Stunde je Klasse, die Aufsichten und Kürzel, die das Dashboard nicht kennt. Übernommen gilt er ab diesem Tag; einen geplanten kannst du bis dahin wieder löschen.</p>"
            unless sources.empty?
                io.puts "<details class='dp-section dp-sp-plans'><summary>Stundenpläne: <strong class='dp-count'>#{sources.size}</strong></summary>"
                io.puts "<div class='dp-scroll'><table class='table table-sm dp-list'><thead><tr><th>Gilt ab</th><th>Datei</th><th>Stand</th><th></th></tr></thead><tbody>"
                sources.keys.sort.reverse.each do |d|
                    path = sources[d]
                    state = d > today ? 'geplant' : (d == current ? 'gilt jetzt' : 'früher')
                    action = (d > today && path.end_with?('.zip')) ? "<button type='button' class='btn btn-secondary btn-sm bu_sp_delete' data-date='#{h.(d)}'>Löschen</button>" : ''
                    io.puts "<tr data-date='#{h.(d)}'><td>#{h.(Date.parse(d).strftime('%d.%m.%Y'))}</td><td>#{h.(File.basename(path))}</td><td>#{state}</td><td class='dp-row-actions'>#{action}</td></tr>"
                end
                io.puts "</tbody></table></div></details>"
            end
            io.puts "<div class='dp-form'>"
            io.puts "<label class='dp-drop' id='dp_sp_drop' for='ti_sp_file'><input type='file' id='ti_sp_file' accept='.zip' hidden><i class='ti ti-file-zip' aria-hidden='true'></i><span class='dp-drop-text'><strong>Untis-Export (ZIP) hierher ziehen</strong> oder klicken, um ihn auszuwählen</span><span class='dp-drop-file' hidden></span></label>"
            io.puts "<div class='dp-date'><label for='ti_sp_date'>Gilt ab</label><input type='date' class='form-control' id='ti_sp_date' value='#{today}'></div>"
            io.puts "</div>"
            io.puts "<div id='dp_sp_message' class='alert alert-warning' style='margin-top: 1em;' hidden></div>"
            io.puts "<div id='dp_sp_preview' style='margin-top: 1em;'></div>"
            io.puts "<div id='dp_sp_apply' hidden>"
            io.puts "<p id='dp_sp_replace' class='alert alert-warning' hidden><label style='margin: 0;'><input type='checkbox' id='ti_sp_replace'> Für diesen Tag gibt es schon einen Stundenplan. Er wird ersetzt.</label></p>"
            io.puts "<div class='dp-actions'><button class='btn btn-secondary' id='bu_sp_discard'>Verwerfen</button><span class='dp-spacer'></span><button class='btn btn-success' id='bu_sp_apply'>Übernehmen</button></div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end
end
