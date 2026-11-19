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
        # test persons an admin chose (/design_feedback), whatever the stage
        return true if user_logged_in? && (@session_user || {})[:ui_preview_granted]
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
        return ui_preview_account? if user_logged_in?
        ui_preview_public_page? && UI_PREVIEW_COOKIE_VALUES.include?(ui_preview_cookie)
    end

    # the account's own setting (logged in)
    def ui_preview_account?
        ui_preview_allowed? && !!(@session_user || {})[:ui_preview]
    end

    # Logged out (the login and code pages) there is no account to ask, so
    # the browser remembers the look: whoever switches the preview on gets a
    # long-lived cookie with nothing in it but "light" or "dark" – no session
    # data, no name, never written into a page. Switching it off (or logging
    # in with an account without the preview) removes it again. It is purely
    # cosmetic: someone who sets it by hand only sees the public pages below
    # in the new look (whose styles are public files anyway); switching the
    # preview on for an account still needs ui_preview_allowed?, and logging
    # in works exactly the same in both looks.
    UI_PREVIEW_COOKIE = 'ui_preview'
    UI_PREVIEW_COOKIE_VALUES = %w(light dark)
    # the pages someone sees logged out that have a design in the preview
    # ('' and 'index' are the login page when nobody is logged in)
    UI_PREVIEW_PUBLIC_PAGES = %w(index login c login_otp otp)

    def ui_preview_public_page?
        # library devices have a login page of their own
        return false if @session_device
        page = ((request.path rescue '') || '').split('/')[1].to_s
        UI_PREVIEW_PUBLIC_PAGES.include?(page.empty? ? 'index' : page)
    end

    # dark mode: the account's setting, logged out the remembered look
    def ui_dark?
        return !!@session_user[:dark] if user_logged_in?
        ui_preview? && ui_preview_cookie == 'dark'
    end

    def ui_preview_cookie
        (request.cookies[UI_PREVIEW_COOKIE] rescue nil)
    end

    def set_ui_preview_cookie(look)
        if look
            response.set_cookie(UI_PREVIEW_COOKIE,
                                :value => look,
                                :expires => Time.new + COOKIE_EXPIRY_TIME,
                                :path => '/',
                                :httponly => true,
                                :same_site => :lax,
                                :secure => DEVELOPMENT ? false : true)
        else
            response.delete_cookie(UI_PREVIEW_COOKIE, :path => '/')
        end
    end

    # on every page while logged in: the cookie follows the account (the
    # preview switched on for someone else, on another device, light / dark)
    def sync_ui_preview_cookie
        return unless user_logged_in?
        look = ui_preview_account? ? (@session_user[:dark] ? 'dark' : 'light') : nil
        set_ui_preview_cookie(look) if look != ui_preview_cookie
    end

    # body classes of the new design; pv-public: logged out (no navigation)
    def design_preview_body_class
        return '' unless ui_preview?
        # the font pair (UI_FONTS, preview.css); logged out the default
        user_logged_in? ? " ui-preview pv-font-#{ui_font}" : ' ui-preview pv-public'
    end

    # the login pages logged out (no navigation): the school's name and icon
    # at the top of the card, a way back to the start
    def design_preview_public_brand
        return '' unless ui_preview? && !user_logged_in?
        "<a class='pv-login-brand' href='/'><img src='/#{ui_dark? ? DARK_SCHUL_ICON : SCHUL_ICON}' alt=''><span>#{CGI.escapeHTML(SCHUL_NAME)}</span></a>"
    end

    # a page's own part of the new design (src/static/preview/<name>.js), for
    # pages that need no data of their own for it (Klassenmemory): only in the
    # new design, '' otherwise, so that the page stays byte for byte as it was
    def design_preview_page_script(name)
        return '' unless ui_preview?
        assert(name =~ /\A[a-z0-9_]+\z/)
        "\n<script src='#{preview_asset("/preview/#{name}.js")}'></script>"
    end

    # code fields (c.html): in the new design a text field with the numeric
    # keyboard (a number field shows spin arrows and
    # changes on scrolling) that phones can fill from an SMS or mail
    def design_preview_code_input_type
        return 'type="number"' unless ui_preview?
        'type="text" inputmode="numeric" autocomplete="one-time-code" spellcheck="false"'
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
    def design_preview_backdrop_css(color_scheme, dark)
        code = (dark ? 'd' : 'l') + color_scheme.to_s[1..].to_s
        jpg = "/gen/bg/bg-#{code}.jpg"
        url = File.exist?(jpg) ? jpg : "/gen/bg/bg-#{code[0, code.size - 1]}0.svg"
        [code, "body.ui-preview { background-image: url(#{url}); background-color: #{dark ? '#0e131a' : '#f3f5f8'}; }"]
    end

    def design_preview_backdrop(color_scheme, dark)
        code, css = design_preview_backdrop_css(color_scheme, dark)
        [code, "<style id='design_backdrop'>#{css}</style>\n"]
    end

    # The colours for a scheme and Farbigkeit, for the profile to show a change
    # at once (without loading the page again)
    get '/api/design_tokens' do
        require_user!
        scheme = params['scheme'].to_s.downcase
        assert(scheme =~ /\A[ld][0-9a-f]{18}[0-9]?\z/)
        vivid = params['vivid'].nil? ? ui_vividness : (params['vivid'].to_i.clamp(0, 100) / 100.0)
        dark = !!(@session_user || {})[:dark]
        backdrop, backdrop_css = design_preview_backdrop_css(scheme, dark)
        respond(:tokens => DesignTokens.css(DesignTokens.effective_scheme(scheme), dark, backdrop, vivid),
                :backdrop => backdrop_css, :theme_color => '#' + backdrop[1, 6])
    end

    def design_preview_head(color_scheme)
        sync_ui_preview_cookie
        return '' unless ui_preview?
        dark = ui_dark?
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
        "<style id='design_tokens'>#{DesignTokens.css(DesignTokens.effective_scheme(color_scheme), dark, backdrop, ui_vividness)}</style>\n" +
            "<link href='#{preview_asset('/include/fonts-v2/fonts.css')}' rel='stylesheet' />\n" +
            "<link href='#{preview_asset('/preview.css')}' rel='stylesheet' />\n" +
            # one stylesheet per area of the new design (messages, polls, login …)
            Dir[File.join('/static', 'preview', '*.css')].sort.map { |f| "<link href='#{preview_asset('/preview/' + File.basename(f))}' rel='stylesheet' />\n" }.join +
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
        # the look for the login pages of this browser (see UI_PREVIEW_COOKIE)
        set_ui_preview_cookie(on ? (@session_user[:dark] ? 'dark' : 'light') : nil)
        respond(:ok => true)
    end

    # Admins give the new design to single persons for testing (or take it
    # back): allowed for them from now on and switched on at once; taking it
    # back switches it off. They can still switch it off themselves.
    post '/api/set_ui_preview_tester' do
        require_admin!
        data = parse_request_data(:required_keys => [:email, :mode], :max_body_length => 1024,
                                  :max_value_lengths => {:email => 256})
        assert(%w(on off).include?(data[:mode]))
        email = data[:email].strip.downcase
        assert(@@user_info.include?(email))
        on = data[:mode] == 'on'
        neo4j_query(<<~END_OF_QUERY, :email => email, :on => on, :ts => Time.now.to_i)
            MATCH (u:User {email: $email})
            SET u.ui_preview_granted = $on
            SET u.ui_preview = $on
            SET u.ui_preview_ts = $ts
            SET u.ui_preview_tried = COALESCE(u.ui_preview_tried, false) OR $on;
        END_OF_QUERY
        respond(:ok => true)
    end

    def ui_preview_testers
        require_admin!
        neo4j_query(<<~END_OF_QUERY).map { |row| {:email => row['email'], :on => !!row['on']} }.select { |x| @@user_info.include?(x[:email]) }
            MATCH (u:User)
            WHERE u.ui_preview_granted = true
            RETURN u.email AS email, u.ui_preview AS on;
        END_OF_QUERY
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
    # feedback button and dialog in the template (preview only); the
    # dashboard addresses everyone with "du"
    def design_feedback_html
        return '' unless ui_preview? && user_logged_in?
        placeholder = 'Was gefällt dir, was fehlt, was klappt nicht?'
        contact = 'Du darfst mich dazu ansprechen.'
        thanks = 'Danke für deine Rückmeldung!'
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
            # test persons: the new design for single persons, whatever the stage
            testers = ui_preview_testers.sort_by { |x| (@@user_info[x[:email]][:display_name] || '').downcase }
            io.puts "<h3 class='mt-4'>Testpersonen</h3>"
            io.puts "<p class='text-muted'>Diese Personen bekommen das neue Design zum Testen, auch wenn es sonst nur für Admins freigeschaltet ist. Hinzufügen schaltet es für sie gleich ein, Entfernen schaltet es aus; selbst abschalten können sie es im Profil.</p>"
            if testers.empty?
                io.puts "<p class='text-muted' id='pv_testers_empty'>Noch keine Testpersonen.</p>"
            else
                io.puts "<ul class='list-unstyled pv-testers' id='pv_testers'>"
                testers.each do |x|
                    info = @@user_info[x[:email]]
                    extra = info[:teacher] ? 'Lehrkraft' : (info[:klasse] ? "Klasse #{tr_klasse(info[:klasse])}" : '')
                    state = x[:on] ? 'eingeschaltet' : 'selbst abgeschaltet'
                    io.puts "<li class='d-flex align-items-center' style='gap: 12px; padding: 6px 0; border-bottom: 1px solid rgba(128,128,128,0.2);' data-email='#{CGI.escapeHTML(x[:email])}'>" +
                            "<span style='flex: 1;'><b>#{CGI.escapeHTML(info[:display_name].to_s)}</b> <span class='text-muted'>#{CGI.escapeHTML(extra)}, #{state}</span></span>" +
                            "<button type='button' class='btn btn-sm btn-outline-secondary bu-remove-tester' data-email='#{CGI.escapeHTML(x[:email])}'>Entfernen</button></li>"
                end
                io.puts "</ul>"
            end
            io.puts "<div class='d-flex flex-wrap align-items-center' style='gap: 8px; margin: 10px 0 28px;'>"
            io.puts "<input type='text' class='form-control' id='ti_preview_tester' list='dl_preview_tester' placeholder='Name oder E-Mail-Adresse' autocomplete='off' style='max-width: 26rem;'>"
            io.puts "<button type='button' class='btn btn-secondary' id='bu_add_tester' disabled>Hinzufügen</button>"
            io.puts "</div>"
            io.puts "<datalist id='dl_preview_tester'>"
            @@user_info.keys.sort_by { |e| (@@user_info[e][:display_name] || e).downcase }.each do |e|
                info = @@user_info[e]
                extra = info[:teacher] ? 'Lehrkraft' : (info[:klasse] ? "Klasse #{tr_klasse(info[:klasse])}" : '')
                io.puts "<option value='#{CGI.escapeHTML(e)}'>#{CGI.escapeHTML(info[:display_name].to_s)}#{extra.empty? ? '' : ', ' + CGI.escapeHTML(extra)}</option>"
            end
            io.puts "</datalist>"
            io.puts "<h3>Nutzung und Feedback</h3>"
            io.puts "<p class='design-feedback-counts'><b>#{data[:active]}</b> nutzen das neue Design gerade, <b>#{data[:left]}</b> haben es ausprobiert und wieder abgeschaltet.</p>"
            if data[:entries].empty?
                io.puts "<p class='text-muted'>Noch kein Feedback.</p>"
            else
                by_role = data[:entries].group_by { |e| e[:role] }.map { |r, es| "#{CGI.escapeHTML(r.to_s)}: #{es.size}" }.join(', ')
                io.puts "<p class='text-muted'>#{data[:entries].size} Rückmeldungen, #{by_role}</p>"
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
        # as in the mockups: teachers Heute, Woche, Nachrichten, Unterricht, Mehr,
        # students Heute, Woche, Aufgaben, Nachrichten, Mehr; the profile is
        # the picture in the day's header (and in "Mehr"), the search an icon there
        tabs = []
        unless external_user_logged_in?
            tabs << ['/', 'Heute', 'fa-calendar', start_page_todo_count]
            tabs << ['/#woche', 'Woche', 'fa-th', nil]
        end
        tabs << ['/#aufgaben', 'Aufgaben', 'fa-check-square-o', nil] if schueler_logged_in?
        tabs << ['/messages', 'Nachrichten', 'fa-comment-o', new_messages_count] if user_with_role_logged_in?(:can_receive_messages)
        tabs << ['#kurse', 'Unterricht', 'fa-book', nil] if teacher_logged_in?
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
                        // "Unterricht": the Kursbuch of one's courses and the class lists as a sheet
                        $('#bu_pv_courses').on('click', function () {
                            if (document.querySelector('.pv-link-sheet')) { window.pv_close_plan_menu(true); return; }
                            let groups = window.pv_menu_links('navbarDropdownKlassen');
                            window.pv_open_link_sheet('Unterricht', [
                                ['Mein Unterricht', window.pv_menu_links('navbarDropdownKurse')],
                                ['Meine Lerngruppen', groups.filter(function (g) { return g[3]; })],
                                ['Weitere Lerngruppen', groups.filter(function (g) { return !g[3]; }), {folded: true}],
                            ]);
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
                            veil.prop('hidden', true).removeClass('pv-veil-out');
                            document.body.classList.remove('pv-sheet-open');
                            $('#bu_pv_more').attr('aria-expanded', 'false');
                        };
                        let close_menu = function () {
                            menu[0].classList.add('pv-closing');
                            // the veil fades with the sheet instead of vanishing at the end
                            veil.addClass('pv-veil-out');
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
    # "Farbigkeit" (profile, new design): 0 calm … 100 colourful (default)
    def ui_vividness
        v = (@session_user || {})[:ui_vividness]
        v.nil? ? 1.0 : (v.to_i.clamp(0, 100) / 100.0)
    end

    post '/api/set_ui_vividness' do
        require_user!
        data = parse_request_data(:required_keys => [:value], :types => {:value => Integer}, :max_body_length => 64)
        value = data[:value].to_i
        assert(value >= 0 && value <= 100)
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :value => value)
            MATCH (u:User {email: $email})
            SET u.ui_vividness = $value;
        END_OF_QUERY
        respond(:ok => true)
    end

    # "Schrift" (profile, new design): five pairs of fonts for headings and
    # text, all with accents and Greek (preview.css, include/fonts-v2). The
    # first is the default; the old design keeps its own choice (u.font).
    UI_FONTS = [
        ['klar', 'Klar', 'Bricolage Grotesque und Atkinson Hyperlegible'],
        ['sachlich', 'Sachlich', 'Inter Tight und Inter'],
        ['buch', 'Buch', 'Literata'],
        ['freundlich', 'Freundlich', 'M PLUS Rounded und Manrope'],
        ['feder', 'Feder', 'Alegreya und Alegreya Sans'],
    ]
    UI_FONT_KEYS = UI_FONTS.map(&:first)

    def ui_font
        f = (@session_user || {})[:ui_font]
        UI_FONT_KEYS.include?(f) ? f : UI_FONT_KEYS.first
    end

    post '/api/set_ui_font' do
        require_user!
        data = parse_request_data(:required_keys => [:font], :max_body_length => 64,
                                  :max_value_lengths => {:font => 16})
        assert(UI_FONT_KEYS.include?(data[:font]))
        neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :font => data[:font])
            MATCH (u:User {email: $email})
            SET u.ui_font = $font;
        END_OF_QUERY
        respond(:ok => true)
    end

    # one tile per pair, each in its own fonts: a heading and a line with accents
    # and Greek; switching applies at once (profil.html, preview.js)
    def design_preview_font_picker_html
        return '' unless ui_preview?
        current = ui_font
        tiles = UI_FONTS.map do |key, name, fonts|
            active = key == current
            "<button type='button' class='pv-font-tile' data-font='#{key}' role='radio' aria-checked='#{active}'>" +
                "<span class='pv-font-head'><span class='pv-font-name'>#{name}</span><i class='ti ti-check' aria-hidden='true'></i></span>" +
                "<span class='pv-font-sample' lang='de'>Größe, café, <span lang='el'>Ελληνικά, Αθήνα</span></span>" +
                "<span class='pv-font-families'>#{fonts}</span>" +
            "</button>"
        end.join
        <<~END_OF_HTML
            <div class='pv-fonts'>
                <div class='pv-fonts-label' id='pv_fonts_label'>Schrift</div>
                <div class='pv-font-tiles' role='radiogroup' aria-labelledby='pv_fonts_label'>#{tiles}</div>
            </div>
        END_OF_HTML
    end

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
                    io.puts "<span class='pal-tuned'>angepasst <i class='ti ti-chevron-right' aria-hidden='true'></i> " + [1, 7, 13].map { |i| "<i style='background: ##{effective[i, 6]}'></i>" }.join + "</span>"
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
    # colours to pick for one's own scheme: the Cling palette, as in the
    # Hackschule sprite editor (http://clingeverything.com/color-palette),
    # without black and white (weak as scheme colours): 42, six rows of seven
    # on phones
    CLING_COLOURS = [
        ['#ffe617', 'Narzisse'], ['#fad31c', 'Sonnengelb'], ['#fdb717', 'Senf'],
        ['#faaa21', 'Zirkusorange'], ['#f1753f', 'Kürbis'], ['#ed5724', 'Mandarine'],
        ['#ef4538', 'Lachs'], ['#ea2830', 'Kaki'], ['#bc2326', 'Rubin'],
        ['#8c0c03', 'Scharlach'], ['#e5185d', 'Pink'], ['#f384ae', 'Rosa'],
        ['#fac6d2', 'Zartrosa'], ['#b296c7', 'Flieder'], ['#7b67ae', 'Lavendel'],
        ['#5f3577', 'Violett'], ['#c1d18a', 'Seladon'], ['#799155', 'Olive'],
        ['#80bc42', 'Bambus'], ['#4aa03f', 'Gras'], ['#16884a', 'Kleegrün'],
        ['#003f2e', 'Wald'], ['#c3def1', 'Wolke'], ['#55beed', 'Traumblau'],
        ['#31a8e0', 'Golf'], ['#238acc', 'Azur'], ['#0d60ae', 'Himmel'],
        ['#143b86', 'Indigo'], ['#001b4a', 'Marine'], ['#7dcdc2', 'Meerschaum'],
        ['#00a8a8', 'Blaugrün'], ['#12959f', 'Pfau'], ['#094e54', 'Tiefsee'],
        ['#381e11', 'Schokolade'], ['#c05c20', 'Terrakotta'], ['#bf9b6b', 'Kamel'],
        ['#e9d4a7', 'Leinen'], ['#e7e6e1', 'Stein'], ['#cfd0d2', 'Rauch'],
        ['#8a8b8f', 'Stahl'], ['#778590', 'Schiefer'], ['#474d4d', 'Anthrazit'],
    ]

    # light colours get a dark check mark, dark ones a white one
    def cling_light?(hex)
        r, g, b = hex[1, 6].scan(/../).map { |x| x.to_i(16) / 255.0 }
        0.299 * r + 0.587 * g + 0.114 * b > 0.6
    end

    def design_preview_scheme_picker_html
        return '' unless ui_preview?
        code = (@session_user || {})[:color_scheme] || @@standard_color_scheme
        note = ''
        unless DesignTokens.curated?(code)
            name = (@@color_scheme_info[code[0, 19]] || @@color_scheme_info['l' + code[1, 18]] || [])[0]
            key, cname, _ = DesignTokens.closest_curated(code)
            # kept as one's own scheme of three colours (adjustable below)
            mine = name ? "Dein eigenes Farbschema »#{CGI.escapeHTML(name)}«" : 'Dein eigenes Farbschema'
            note = "<p class='pv-scheme-note'>#{mine} besteht aus drei Farben, du kannst sie unten anpassen. Ähnlich in der Auswahl: <b>#{CGI.escapeHTML(cname)}</b>.</p>"
        end
        colours = [1, 7, 13].map { |i| '#' + code[i, 6].to_s }
        <<~END_OF_HTML
            #{note}
            <div class='pv-vividness'>
                <label for='ti_ui_vividness'>Farbigkeit der Fächer und Menüs</label>
                <div class='pv-vividness-row'>
                    <span>ruhig</span>
                    <input type='range' id='ti_ui_vividness' min='0' max='100' step='25' value='#{(ui_vividness * 100).round}' aria-describedby='pv_vividness_hint'>
                    <span>bunt</span>
                </div>
                <div class='pv-vivid-sample' aria-hidden='true'>
                    #{[%w(de De), %w(en En), %w(la La), %w(ma Ma), %w(bio Bio), %w(ge Ge), %w(ku Ku), %w(sp Sp)].map { |k, l| "<span style='background: var(--subj-#{k}); color: var(--subj-#{k}-ink)'>#{l}</span>" }.join}
                </div>
                <p class='text-muted' id='pv_vividness_hint'>Wie weit sich die Farben der Fächer über das Farbspektrum verteilen. Lesbar bleibt es in jeder Stufe.</p>
            </div>
            <div class='pv-scheme-own'>
                <div class='pv-scheme-own-head'>
                    <h3>Eigenes Farbschema</h3>
                    <p class='text-muted'>Drei Farben: links, Mitte (Hauptfarbe), rechts. Wähle eine aus und tippe eine Farbe an oder stelle sie mit den Reglern ein; die Pfeile tauschen zwei. Das neue Design macht daraus Akzent- und Fächerfarben, die gut lesbar bleiben.</p>
                </div>
                <div class='pv-scheme-inputs' role='radiogroup' aria-label='Welche Farbe du änderst'>
                    <button type='button' class='pv-scheme-slot' data-slot='left' role='radio' aria-checked='false'><span class='pv-scheme-chip' style='background: #{colours[0]}'></span><span class='pv-scheme-slot-name'>Links</span></button>
                    <button type='button' class='pv-scheme-swap' data-a='left' data-b='main' aria-label='Links und Mitte tauschen'><i class='ti ti-arrows-exchange'></i></button>
                    <button type='button' class='pv-scheme-slot' data-slot='main' role='radio' aria-checked='true'><span class='pv-scheme-chip' style='background: #{colours[1]}'></span><span class='pv-scheme-slot-name'>Mitte</span></button>
                    <button type='button' class='pv-scheme-swap' data-a='main' data-b='right' aria-label='Mitte und rechts tauschen'><i class='ti ti-arrows-exchange'></i></button>
                    <button type='button' class='pv-scheme-slot' data-slot='right' role='radio' aria-checked='false'><span class='pv-scheme-chip' style='background: #{colours[2]}'></span><span class='pv-scheme-slot-name'>Rechts</span></button>
                </div>
                <input type='hidden' id='ti_scheme_left' value='#{colours[0]}'>
                <input type='hidden' id='ti_scheme_main' value='#{colours[1]}'>
                <input type='hidden' id='ti_scheme_right' value='#{colours[2]}'>
                <div class='pv-scheme-strip' aria-hidden='true'></div>
                <div class='pv-cling' role='group' aria-label='Farben zur Auswahl'>
                    #{CLING_COLOURS.map { |hex, name| "<button type='button' class='pv-cling-colour#{cling_light?(hex) ? ' pv-cling-light' : ''}' data-hex='#{hex}' style='--sw: #{hex}; background: #{hex}' title='#{name}' aria-label='#{name}' aria-pressed='false'><i class='ti ti-check' aria-hidden='true'></i></button>" }.join}
                </div>
                <div class='pv-hsl'>
                    <label for='ti_hsl_h'>Farbton</label>
                    <input type='range' id='ti_hsl_h' class='pv-hsl-h' min='0' max='359' step='1'>
                    <label for='ti_hsl_s'>Sättigung</label>
                    <input type='range' id='ti_hsl_s' class='pv-hsl-s' min='0' max='100' step='1'>
                    <label for='ti_hsl_l'>Helligkeit</label>
                    <input type='range' id='ti_hsl_l' class='pv-hsl-l' min='0' max='100' step='1'>
                    <label for='ti_scheme_hex'>Farbcode</label>
                    <input type='text' id='ti_scheme_hex' class='form-control pv-hsl-hex' maxlength='7' spellcheck='false' autocomplete='off' inputmode='text'>
                </div>
                <div class='pv-scheme-actions'>
                    <button type='button' class='btn btn-outline-secondary' id='bu_reverse_own_scheme'><i class='fa fa-retweet'></i>&nbsp;&nbsp;Umdrehen</button>
                    <button type='button' class='btn btn-primary' id='bu_apply_own_scheme'>Übernehmen</button>
                </div>
            </div>
        END_OF_HTML
    end
end
