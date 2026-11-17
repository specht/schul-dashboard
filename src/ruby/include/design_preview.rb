# Neues Design (Vorschau): everyone can opt in on the profile page; the
# template then loads the new design's tokens and styles (design_tokens.rb,
# /preview.css). People who try it can leave feedback – with the page, the
# device, light/dark, the colour scheme and the role, but without a name unless
# they agree to be contacted. Admins see it on /design_feedback.
class Main < Sinatra::Base
    DESIGN_FEEDBACK_MAX_LENGTH = 2000
    # who may switch the preview on – widened stage by stage (see
    # review/2026-11/redesign.md): :admins, then :teachers, then :all.
    # Development instances: everyone, so that every role's pages can be
    # checked in the new design (still opt-in per account; the test stack
    # runs in production mode).
    UI_PREVIEW_FOR = DEVELOPMENT ? :all : :admins

    def ui_preview_allowed?
        case UI_PREVIEW_FOR
        when :admins then admin_logged_in?
        when :teachers then admin_logged_in? || teacher_logged_in?
        else user_logged_in?
        end
    end

    def ui_preview?
        # monitors keep their own layout, also when an admin views them
        # (manage_monitor embeds them with the admin's session)
        return false if ((request.path rescue '') || '').start_with?('/monitor')
        ui_preview_allowed? && !!(@session_user || {})[:ui_preview]
    end

    # the role a feedback entry is filed under
    def design_feedback_role
        return 'Lehrkraft' if teacher_logged_in?
        return 'Schüler:in' if schueler_logged_in?
        return 'Elternvertretung' if gev_logged_in?
        'andere'
    end

    # <style> with the tokens and the preview styles, only for those who opted in
    # static files (served by nginx) with their modification time, so that
    # browsers fetch them again after every change instead of keeping an old copy
    def preview_asset(path)
        "#{path}?v=#{File.mtime(File.join('/static', path)).to_i}"
    rescue StandardError
        path
    end

    # In the new design the backdrop follows light / dark mode (one switch
    # instead of "Hintergrund" and "Helligkeit"): the light or dark variant
    # of the scheme's backdrop, the ground below it to match.
    def design_preview_backdrop(color_scheme, dark)
        code = (dark ? 'd' : 'l') + color_scheme.to_s[1..].to_s
        jpg = "/gen/bg/bg-#{code}.jpg"
        url = File.exist?(jpg) ? jpg : "/gen/bg/bg-#{code[0, code.size - 1]}0.svg"
        [code, "<style id='design_backdrop'>body.ui-preview { background-image: url(#{url}); background-color: #{dark ? '#0e131a' : '#f3f5f8'}; }</style>\n"]
    end

    def design_preview_head(color_scheme)
        return '' unless ui_preview?
        dark = !!(@session_user || {})[:dark]
        backdrop, backdrop_css = design_preview_backdrop(color_scheme, dark)
        # the page reaches behind the island / status bar (safe areas in
        # preview.css); in a browser tab the browser's own bar stays, on the
        # home screen the backdrop shows behind the status bar
        status_colour = '#' + backdrop.to_s[1, 6]
        "<meta name='viewport' content='width=device-width, initial-scale=1, viewport-fit=cover'>\n" +
        "<meta name='apple-mobile-web-app-capable' content='yes'>\n" +
        "<meta name='apple-mobile-web-app-status-bar-style' content='black-translucent'>\n" +
        "<script>(function () { var m = document.querySelector('meta[name=viewport]'); if (m) m.setAttribute('content', 'width=device-width, initial-scale=1, viewport-fit=cover'); var t = document.querySelector('meta[name=theme-color]'); if (t) t.setAttribute('content', '#{status_colour}'); })();</script>\n" +
        backdrop_css +
        "<style id='design_tokens'>#{DesignTokens.css(DesignTokens.effective_scheme(color_scheme), dark, backdrop)}</style>\n" +
            "<link href='#{preview_asset('/include/fonts-v2/fonts.css')}' rel='stylesheet' />\n" +
            "<link href='#{preview_asset('/preview.css')}' rel='stylesheet' />\n" +
            "<script src='#{preview_asset('/preview.js')}'></script>\n" +
            # Tabler icons instead of Fork Awesome (include/tabler/fa-to-tabler.js)
            "<link href='#{preview_asset('/include/tabler/tabler-icons.css')}' rel='stylesheet' />\n" +
            "<script src='#{preview_asset('/include/tabler/fa-to-tabler.js')}'></script>"
    end

    post '/api/set_ui_preview' do
        require_user!
        data = parse_request_data(:required_keys => [:mode], :optional_keys => [:reason],
                                  :max_body_length => 4096, :max_value_lengths => {:reason => DESIGN_FEEDBACK_MAX_LENGTH})
        assert(%w(on off).include?(data[:mode]))
        on = data[:mode] == 'on'
        # switching off is always allowed, switching on only for the current stage
        assert(ui_preview_allowed?) if on
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :on => on, :ts => Time.now.to_i)
            MATCH (u:User {email: $email})
            SET u.ui_preview = $on
            SET u.ui_preview_ts = $ts
            SET u.ui_preview_tried = COALESCE(u.ui_preview_tried, false) OR $on;
        END_OF_QUERY
        # switching back: one optional question, filed like other feedback
        reason = (data[:reason] || '').strip
        store_design_feedback('opt_out', reason, nil, nil, false) if !on && !reason.empty?
        respond(:ok => true)
    end

    post '/api/design_feedback' do
        require_user!
        assert(ui_preview?)
        data = parse_request_data(:required_keys => [:text, :page, :device], :optional_keys => [:contact],
                                  :max_body_length => 4096,
                                  :max_value_lengths => {:text => DESIGN_FEEDBACK_MAX_LENGTH, :page => 200})
        assert(%w(phone desktop).include?(data[:device]))
        assert(%w(yes no).include?(data[:contact] || 'no'))
        text = data[:text].strip
        assert(!text.empty?)
        store_design_feedback('feedback', text, data[:page], data[:device], data[:contact] == 'yes')
        respond(:ok => true)
    end

    def store_design_feedback(kind, text, page, device, contact)
        props = {
            :id => RandomTag.generate(12), :ts => Time.now.to_i, :kind => kind, :text => text,
            :page => (page || '').sub(/\?.*/, ''), :device => device || '', :role => design_feedback_role,
            :dark => !!(@session_user || {})[:dark], :scheme => ((@session_user || {})[:color_scheme] || '')[0, 19],
            :contact => contact ? @session_user[:email] : '',
        }
        neo4j_query(<<~END_OF_QUERY, :props => props)
            CREATE (f:DesignFeedback)
            SET f = $props;
        END_OF_QUERY
    end

    # for /design_feedback (admins): numbers and all entries, newest first
    def design_feedback_page_data
        require_admin!
        counts = neo4j_query_expect_one(<<~END_OF_QUERY)
            MATCH (u:User)
            RETURN sum(CASE WHEN u.ui_preview = true THEN 1 ELSE 0 END) AS active,
                   sum(CASE WHEN u.ui_preview_tried = true AND COALESCE(u.ui_preview, false) = false THEN 1 ELSE 0 END) AS left;
        END_OF_QUERY
        entries = neo4j_query(<<~END_OF_QUERY).map { |row| row['f'] }
            MATCH (f:DesignFeedback)
            RETURN f ORDER BY f.ts DESC;
        END_OF_QUERY
        {:active => counts['active'], :left => counts['left'], :entries => entries}
    end
end

class Main < Sinatra::Base
    # feedback button and dialog in the template (preview only); teachers are
    # addressed with "Sie", everyone else with "du"
    def design_feedback_html
        return '' unless ui_preview?
        sie = teacher_logged_in?
        placeholder = sie ? 'Was gefällt Ihnen, was fehlt, was klappt nicht?' : 'Was gefällt dir, was fehlt, was klappt nicht?'
        contact = sie ? 'Sie dürfen mich dazu ansprechen.' : 'Ihr dürft mich dazu ansprechen.'
        thanks = sie ? 'Danke für Ihre Rückmeldung!' : 'Danke für deine Rückmeldung!'
        <<~END_OF_HTML
            <button type="button" class="btn btn-sm btn-secondary design-feedback-button" id="bu_design_feedback"><i class="fa fa-comment-o"></i>&nbsp;&nbsp;Feedback zum neuen Design</button>
            <div class="modal" id="designFeedbackModal" tabindex="-1" role="dialog" aria-labelledby="designFeedbackTitle">
                <div class="modal-dialog" role="document">
                    <div class="modal-content">
                        <div class="modal-header"><h5 class="modal-title" id="designFeedbackTitle">Feedback zum neuen Design</h5></div>
                        <div class="modal-body">
                            <textarea class="form-control" id="ti_design_feedback" rows="4" maxlength="#{DESIGN_FEEDBACK_MAX_LENGTH}" placeholder="#{placeholder}"></textarea>
                            <div class="form-check mt-2">
                                <input class="form-check-input" type="checkbox" id="ti_design_feedback_contact">
                                <label class="form-check-label" for="ti_design_feedback_contact">#{contact}</label>
                            </div>
                            <p class="design-feedback-note">Gespeichert werden die Seite, Handy oder Desktop, hell oder dunkel, das Farbschema und die Rolle – der Name nur, wenn das Häkchen gesetzt ist.</p>
                            <p class="design-feedback-thanks" style="display: none;">#{thanks}</p>
                            <div class="api_messages" style="display: none;"></div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Schließen</button>
                            <button type="button" class="btn btn-primary" id="bu_send_design_feedback">Senden</button>
                        </div>
                    </div>
                </div>
            </div>
            <script>
                window.addEventListener('load', function () {
                    let modal = $('#designFeedbackModal');
                    // the floating button (hidden for now, preview.css) or the link in the profile
                    $('#bu_design_feedback, .bu-open-design-feedback').on('click', function () {
                        modal.find('.design-feedback-thanks').hide();
                        modal.find('textarea, .form-check, .design-feedback-note, #bu_send_design_feedback').show();
                        modal.modal('show');
                    });
                    modal.on('shown.bs.modal', function () { $('#ti_design_feedback').focus(); });
                    $('#bu_send_design_feedback').on('click', function () {
                        let text = $('#ti_design_feedback').val().trim();
                        if (text.length === 0) { $('#ti_design_feedback').focus(); return; }
                        api_call('/api/design_feedback', {
                            text: text,
                            page: location.pathname,
                            device: window.matchMedia('(max-width: 767px)').matches ? 'phone' : 'desktop',
                            contact: $('#ti_design_feedback_contact').is(':checked') ? 'yes' : 'no',
                        }, function (data) {
                            if (data.success) {
                                $('#ti_design_feedback').val('');
                                $('#ti_design_feedback_contact').prop('checked', false);
                                modal.find('textarea, .form-check, .design-feedback-note, #bu_send_design_feedback').hide();
                                modal.find('.design-feedback-thanks').show();
                            }
                        });
                    });
                });
            </script>
        END_OF_HTML
    end

    # /design_feedback: numbers and entries for admins
    def print_design_feedback
        data = design_feedback_page_data
        kinds = {'feedback' => 'Feedback', 'opt_out' => 'Zurück zum alten Design'}
        StringIO.open do |io|
            io.puts "<p class='design-feedback-counts'><b>#{data[:active]}</b> nutzen das neue Design gerade, <b>#{data[:left]}</b> haben es ausprobiert und wieder abgeschaltet.</p>"
            if data[:entries].empty?
                io.puts "<p class='text-muted'>Noch kein Feedback.</p>"
            else
                by_role = data[:entries].group_by { |e| e[:role] }.map { |r, es| "#{CGI.escapeHTML(r.to_s)}: #{es.size}" }.join(' · ')
                io.puts "<p class='text-muted'>#{data[:entries].size} Rückmeldungen · #{by_role}</p>"
                io.puts "<div class='table-responsive'><table class='table table-sm design-feedback-table'>"
                io.puts "<thead><tr><th>Wann</th><th>Art</th><th>Rolle</th><th>Seite</th><th>Gerät</th><th>Text</th><th>Ansprechen</th></tr></thead><tbody>"
                data[:entries].each do |e|
                    device = [e[:device] == 'phone' ? 'Handy' : (e[:device] == 'desktop' ? 'Desktop' : ''), e[:dark] ? 'dunkel' : 'hell'].reject(&:empty?).join(', ')
                    io.puts "<tr><td>#{Time.at(e[:ts].to_i).strftime('%d.%m.%Y %H:%M')}</td><td>#{kinds[e[:kind]] || ''}</td>" +
                            "<td>#{CGI.escapeHTML(e[:role].to_s)}</td><td>#{CGI.escapeHTML(e[:page].to_s)}</td><td>#{device}</td>" +
                            "<td style='white-space: pre-line;'>#{CGI.escapeHTML(e[:text].to_s)}</td><td>#{CGI.escapeHTML(e[:contact].to_s)}</td></tr>"
                end
                io.puts "</tbody></table></div>"
            end
            io.string
        end
    end
end

class Main < Sinatra::Base
    # Phones in the new design: a tab bar at the bottom with the most used
    # places; "Mehr" opens the full menu (the same nav_items as in the sidebar).
    # Also marks the current page in the menu.
    def design_preview_tabbar_html(new_messages_count)
        return '' unless ui_preview? && user_logged_in?
        # as in the mockups: teachers Heute · Woche · Nachrichten · Kurse · Mehr,
        # students Heute · Woche · Aufgaben · Nachrichten · Mehr; the profile is
        # the picture in the day's header (and in "Mehr"), the search an icon there
        tabs = []
        unless external_user_logged_in?
            tabs << ['/', 'Heute', 'fa-calendar', nil]
            tabs << ['/#woche', 'Woche', 'fa-th', nil]
        end
        tabs << ['/#aufgaben', 'Aufgaben', 'fa-check-square-o', nil] if schueler_logged_in?
        tabs << ['/messages', 'Nachrichten', 'fa-comment-o', new_messages_count] if user_with_role_logged_in?(:can_receive_messages)
        tabs << ['#kurse', 'Kurse', 'fa-book', nil] if teacher_logged_in?
        tabs << ['/profil', 'Profil', 'fa-user-o', nil] unless teacher_logged_in? || schueler_logged_in?
        StringIO.open do |io|
            io.puts "<nav class='pv-tabbar' aria-label='Hauptbereiche'>"
            tabs.each do |href, label, icon, badge|
                badge_html = (badge.to_i > 0) ? "<span class='pv-badge'>#{badge.to_i}</span>" : ''
                if href == '#kurse'
                    io.puts "<button type='button' class='pv-tab' id='bu_pv_courses'><i class='fa #{icon}'></i>#{label}</button>"
                else
                    io.puts "<a class='pv-tab' href='#{href}'>#{badge_html}<i class='fa #{icon}'></i>#{label}</a>"
                end
            end
            io.puts "<button type='button' class='pv-tab' id='bu_pv_more' aria-controls='navbarTogglerDemo02' aria-expanded='false'><i class='fa fa-bars'></i>Mehr</button>"
            io.puts "</nav>"
            io.puts <<~END_OF_HTML
                <script>
                    window.addEventListener('load', function () {
                        // the current page, in the sidebar and the tab bar
                        let here = location.pathname.replace(/\\/$/, '') || '/';
                        document.querySelectorAll('.navbar .nav-link[href], .navbar .dropdown-item[href]').forEach(function (a) {
                            let target = (a.getAttribute('href') || '').replace(/\\/$/, '') || '/';
                            if (target === here) a.classList.add('pv-active');
                        });
                        // tabs: Woche and Aufgaben are parts of the start page (#woche, #aufgaben)
                        let mark_tabs = function () {
                            let hash = here === '/' ? location.hash : '';
                            document.querySelectorAll('.pv-tab[href]').forEach(function (a) {
                                let parts = a.getAttribute('href').split('#');
                                let target = parts[0].replace(/\\/$/, '') || '/';
                                let wanted = parts[1] ? '#' + parts[1] : '';
                                a.classList.toggle('pv-active', target === here && (wanted === hash || (wanted === '' && !/^#(woche|aufgaben)$/.test(hash))));
                            });
                        };
                        mark_tabs();
                        window.addEventListener('hashchange', mark_tabs);
                        // "Kurse": Kursbuch and class lists of one's courses as a sheet
                        $('#bu_pv_courses').on('click', function () {
                            if (document.querySelector('.pv-link-sheet')) { window.pv_close_plan_menu(true); return; }
                            window.pv_open_link_sheet('Kurse', [['Kursbuch', window.pv_menu_links('navbarDropdownKurse')], ['Lerngruppen', window.pv_menu_links('navbarDropdownKlassen')]]);
                        });
                        // "Mehr": the menu as a sheet – slides up over a veil, slides
                        // down again (tap on "Mehr" or the veil, or pull it down, preview.js)
                        let menu = $('#navbarTogglerDemo02');
                        let veil = $('<div class="pv-menu-veil" hidden></div>').appendTo('body');
                        window.pv_menu_hide_now = function () {
                            menu.collapse('hide');
                            menu[0].classList.remove('pv-closing');
                            menu[0].style.transform = '';
                            menu[0].style.transition = '';
                            veil.prop('hidden', true);
                            document.body.classList.remove('pv-sheet-open');
                            $('#bu_pv_more').attr('aria-expanded', 'false');
                        };
                        let close_menu = function () {
                            menu[0].classList.add('pv-closing');
                            setTimeout(window.pv_menu_hide_now, 180);
                        };
                        $('#bu_pv_more').on('click', function (e) {
                            if (menu.hasClass('show')) {
                                close_menu();
                            } else {
                                menu.collapse('show');
                                veil.prop('hidden', false);
                                document.body.classList.add('pv-sheet-open');
                                e.currentTarget.setAttribute('aria-expanded', 'true');
                            }
                        });
                        veil.on('click', close_menu);
                        // the search (teachers): an icon in the day's header and elsewhere
                        // at the top of "Mehr"; a native click – jQuery's trigger() skips it on
                        // links, and the search listens with addEventListener (code.js)
                        $(document).on('click', '.pv-search-button', function () { document.getElementById('bu_quick_search').click(); });
                    });
                </script>
            END_OF_HTML
            io.string
        end
    end
end

class Main < Sinatra::Base
    # Quick switch between the designs, for admins who want it (setting in the
    # profile): a button on every page, in both designs, to check that today's
    # design keeps working while the new one grows.
    def ui_preview_quick?
        admin_logged_in? && ui_preview_allowed? && !!(@session_user || {})[:ui_preview_quick]
    end

    post '/api/set_ui_preview_quick' do
        require_admin!
        data = parse_request_data(:required_keys => [:mode])
        assert(%w(on off).include?(data[:mode]))
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :on => data[:mode] == 'on')
            MATCH (u:User {email: $email})
            SET u.ui_preview_quick = $on;
        END_OF_QUERY
        respond(:ok => true)
    end

    def design_quick_toggle_html
        return '' unless ui_preview_quick?
        on = ui_preview?
        label = on ? 'Zum bisherigen Design wechseln' : 'Zum neuen Design wechseln'
        <<~END_OF_HTML
            <button type="button" class="design-quick-toggle#{on ? ' on' : ''}" id="bu_design_quick_toggle" title="#{label}" aria-label="#{label}"><i class="fa fa-exchange"></i></button>
            <style>
                .design-quick-toggle {
                    position: fixed;
                    right: max(12px, env(safe-area-inset-right, 0px));
                    bottom: calc(36px + env(safe-area-inset-bottom, 0px));
                    z-index: 100002;
                    width: 34px;
                    height: 34px;
                    display: grid;
                    place-items: center;
                    border: 1px solid rgba(0, 0, 0, 0.15);
                    border-radius: 50%;
                    padding: 0;
                    font-size: 15px;
                    opacity: 0.75;
                    background: #fff;
                    color: #131b26;
                    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.2);
                    cursor: pointer;
                }
                body.modal-open .design-quick-toggle {
                    display: none;
                }
                .design-quick-toggle:hover, .design-quick-toggle:focus-visible {
                    opacity: 1;
                }
                body.dark .design-quick-toggle {
                    background: #161d27;
                    color: #e6ebf2;
                    border-color: rgba(255, 255, 255, 0.2);
                }
                @media (max-width: 767px) {
                    .ui-preview .design-quick-toggle {
                        bottom: calc(72px + env(safe-area-inset-bottom, 0px));
                    }
                }
            </style>
            <script>
                window.addEventListener('load', function () {
                    $('#bu_design_quick_toggle').on('click', function (e) {
                        e.currentTarget.disabled = true;
                        api_call('/api/set_ui_preview', {mode: '#{on ? 'off' : 'on'}'}, function (data) {
                            if (data.success) location.reload();
                            else e.currentTarget.disabled = false;
                        });
                    });
                });
            </script>
        END_OF_HTML
    end
    # Marks on /design_palettes: which schemes go into the curated set
    # ('keep' as they are, 'tune' with adjusted colours) and which go ('drop')
    DESIGN_PALETTE_MARKS = %w(keep tune drop)

    post '/api/design_palette_mark' do
        require_admin!
        data = parse_request_data(:required_keys => [:code, :mark], :max_body_length => 256,
                                  :max_value_lengths => {:code => 19, :mark => 8})
        assert(@@color_scheme_info.include?(data[:code]))
        assert((DESIGN_PALETTE_MARKS + ['none']).include?(data[:mark]))
        if data[:mark] == 'none'
            neo4j_query(<<~END_OF_QUERY, :code => data[:code])
                MATCH (p:DesignPaletteMark {code: $code})
                DELETE p;
            END_OF_QUERY
        else
            neo4j_query(<<~END_OF_QUERY, :code => data[:code], :mark => data[:mark], :by => @session_user[:display_name], :ts => Time.now.to_i)
                MERGE (p:DesignPaletteMark {code: $code})
                SET p.mark = $mark, p.by = $by, p.ts = $ts;
            END_OF_QUERY
        end
        respond(:ok => true)
    end

    # Admin page /design_palettes: the new design in every colour scheme, light
    # and dark, sorted by how many accounts use the scheme (counts only), to
    # choose and tune the curated palettes (review/2026-11/redesign.md).
    PALETTE_SAMPLE_SUBJECTS = [['de', 'De'], ['en', 'En'], ['la', 'La'], ['frz', 'Fr'], ['ph', 'Ph'], ['ch', 'Ch'],
                               ['ma', 'Ma'], ['bio', 'Bio'], ['in', 'Inf'], ['ge', 'Ge'], ['ek', 'Ek'], ['pw', 'PW'],
                               ['eth', 'Eth'], ['ku', 'Ku'], ['mu', 'Mu'], ['sp', 'Sp']]

    def design_palettes_html
        require_admin!
        counts = Hash.new(0)
        random = 0
        neo4j_query(<<~END_OF_QUERY).each do |row|
            MATCH (u:User) RETURN u.color_scheme AS s, count(*) AS n
        END_OF_QUERY
            if row['s'].is_a?(String) && row['s'].size >= 19
                counts[row['s'][1, 18]] += row['n']
            else
                random += row['n']
            end
        end
        # COLOR_SCHEME_COLORS is rewritten at startup (main.rb); the codes and
        # names are kept in @@color_scheme_info
        # accounts without a choice of their own have the standard scheme (Sky)
        counts[@@standard_color_scheme[1, 18]] += random
        schemes = @@color_scheme_info.map { |code, info| [code, info[0]] }.sort_by { |code, name| [DesignTokens.curated?(code) ? 0 : 1, -counts[code[1, 18]], name.to_s] }
        names = schemes.to_h
        marks = {}
        neo4j_query(<<~END_OF_QUERY).each { |row| marks[row['code']] = {'mark' => row['mark'], 'by' => row['by'], 'ts' => row['ts']} }
            MATCH (p:DesignPaletteMark)
            RETURN p.code AS code, p.mark AS mark, p.by AS by, p.ts AS ts;
        END_OF_QUERY
        StringIO.open do |io|
            tally = Hash.new(0)
            accounts = Hash.new(0)
            schemes.each do |code, _|
                m = (marks[code] || {})['mark'] || 'none'
                tally[m] += 1
                accounts[m] += counts[code[1, 18]]
            end
            curated_accounts = schemes.select { |code, _| DesignTokens.curated?(code) }.sum { |code, _| counts[code[1, 18]] }
            io.puts "<p class='text-muted'>#{schemes.size} Farbschemata, sortiert nach Nutzung (#{random} Konten ohne eigene Wahl zählen zum Standard Sky). <b>Kuratierte Auswahl: #{DesignTokens::CURATED.size} Schemata, #{curated_accounts} von #{counts.values.sum} Konten.</b> Alle anderen bleiben als eigenes Schema nutzbar; im Profil wird das ähnlichste aus der Auswahl vorgeschlagen.</p>"
            io.puts "<p class='pal-tally'>"
            [['keep', 'Behalten'], ['tune', 'Anpassen'], ['drop', 'Weg'], ['none', 'Offen']].each do |m, label|
                io.puts "<span class='pal-mark-#{m}'>#{label}: <b>#{tally[m]}</b> Schemata, #{accounts[m]} Konten</span>"
            end
            io.puts "</p>"
            shown_rest = false
            io.puts "<h3 class='pal-section'>Kuratierte Auswahl</h3>"
            schemes.each do |code, name|
                curated = DesignTokens.curated?(code)
                if !curated && !shown_rest
                    io.puts "<h3 class='pal-section'>Weitere Schemata (bleiben als eigene nutzbar)</h3>"
                    shown_rest = true
                end
                effective = DesignTokens.effective_scheme(code)
                mark = marks[code] || {}
                io.puts "<div class='pal-row' data-code='#{code}' data-mark='#{mark['mark'] || 'none'}'>"
                io.puts "<div class='pal-head'><b>#{CGI.escapeHTML(name.to_s)}</b>"
                io.puts "<span class='pal-dots'>" + [1, 7, 13].map { |i| "<i style='background: ##{code[i, 6]}'></i>" }.join + "</span>"
                if effective != code
                    io.puts "<span class='pal-tuned'>angepasst → " + [1, 7, 13].map { |i| "<i style='background: ##{effective[i, 6]}'></i>" }.join + "</span>"
                end
                io.puts "<span class='pal-count'>#{counts[code[1, 18]]} Konten</span>"
                io.puts "<span class='pal-marks btn-group btn-group-sm' role='group' aria-label='Auswahl für #{CGI.escapeHTML(name.to_s)}'>"
                [['keep', 'Behalten'], ['tune', 'Anpassen'], ['drop', 'Weg']].each do |m, label|
                    active = mark['mark'] == m
                    io.puts "<button type='button' class='btn btn-outline-secondary bu_palette_mark#{active ? ' active' : ''}' data-mark='#{active ? 'none' : m}' aria-pressed='#{active}'>#{label}</button>"
                end
                io.puts "</span></div>"
                if mark['mark']
                    io.puts "<div class='pal-by'>#{CGI.escapeHTML(mark['by'].to_s)}, #{Time.at(mark['ts'].to_i).strftime('%d.%m.%Y')}</div>"
                end
                unless curated
                    key, cname, _ = DesignTokens.closest_curated(code)
                    io.puts "<div class='pal-target'>ähnlich in der Auswahl: <b>#{CGI.escapeHTML(cname)}</b> " + [0, 6, 12].map { |i| "<i style='background: ##{key[i, 6]}'></i>" }.join + "</div>"
                end
                io.puts "<div class='pal-cards'>"
                [false, true].each do |dark|
                    t = DesignTokens.tokens(effective, dark)
                    vars = t.map { |k, v| "#{k}: #{v}" }.join('; ')
                    surface = '#' + DesignTokens::SURFACE[dark]
                    paper = '#' + DesignTokens::PAPER[dark]
                    ink = '#' + DesignTokens::INK[dark]
                    on_subject = dark ? '#0a1222' : '#ffffff'
                    io.puts "<div class='pal-card' style='#{vars}; --paper: #{paper}; --surface: #{surface}; --ink: #{ink}; --on-subject: #{on_subject}'>"
                    io.puts "<div class='pal-band'><span>#{dark ? 'dunkel' : 'hell'}</span></div>"
                    io.puts "<div class='pal-body'>"
                    io.puts "<div class='pal-actions'><span class='pal-btn'>Speichern</span><span class='pal-chip'>Heute</span><span class='pal-link'>Alle Klassen</span></div>"
                    io.puts "<div class='pal-subjects'>" + PALETTE_SAMPLE_SUBJECTS.map { |k, label| "<span style='background: var(--subj-#{k})'>#{label}</span>" }.join + "</div>"
                    io.puts "<div class='pal-agenda'><div class='pal-when'><b>8:00</b><span>8:45</span></div><div class='pal-lesson' style='--c: var(--subj-ma)'><span class='pal-subj'>Ma</span><div><b>Mathematik (6a)</b><small>111</small></div></div></div>"
                    io.puts "<div class='pal-agenda'><div class='pal-when'><b>8:50</b><span>10:20</span></div><div class='pal-lesson' style='--c: var(--subj-in)'><span class='pal-subj'>Inf</span><div><b>Informatik (11)</b><small>223</small></div></div></div>"
                    io.puts "</div></div>"
                end
                io.puts "</div></div>"
            end
            io.string
        end
    end
    # Profile, new design: the curated set comes first (profil.html filters
    # the swatches), a note when one's own scheme is not in it, and a picker
    # for an own scheme – three colours, the new design keeps them readable.
    def design_preview_scheme_picker_html
        return '' unless ui_preview?
        code = (@session_user || {})[:color_scheme] || @@standard_color_scheme
        note = ''
        unless DesignTokens.curated?(code)
            name = (@@color_scheme_info[code[0, 19]] || @@color_scheme_info['l' + code[1, 18]] || [])[0]
            key, cname, _ = DesignTokens.closest_curated(code)
            mine = name ? "Dein Farbschema »#{CGI.escapeHTML(name)}«" : 'Dein eigenes Farbschema'
            note = "<p class='pv-scheme-note'>#{mine} gehört nicht zur Auswahl des neuen Designs – es bleibt dir erhalten. Ähnlich in der Auswahl: <b>#{CGI.escapeHTML(cname)}</b>.</p>"
        end
        colours = [1, 7, 13].map { |i| '#' + code[i, 6].to_s }
        <<~END_OF_HTML
            #{note}
            <div class='pv-scheme-own'>
                <h3>Eigenes Farbschema</h3>
                <p class='text-muted'>Drei Farben – links, Mitte (Hauptfarbe), rechts. Das neue Design macht daraus Akzent- und Fächerfarben, die gut lesbar bleiben.</p>
                <div class='pv-scheme-inputs'>
                    <label>Links <input type='color' id='ti_scheme_left' value='#{colours[0]}'></label>
                    <label>Mitte <input type='color' id='ti_scheme_main' value='#{colours[1]}'></label>
                    <label>Rechts <input type='color' id='ti_scheme_right' value='#{colours[2]}'></label>
                </div>
                <div class='pv-scheme-strip' aria-hidden='true'></div>
                <button type='button' class='btn btn-primary' id='bu_apply_own_scheme'>Übernehmen</button>
            </div>
        END_OF_HTML
    end
end
