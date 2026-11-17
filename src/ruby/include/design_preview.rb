# Neues Design (Vorschau): everyone can opt in on the profile page; the
# template then loads the new design's tokens and styles (design_tokens.rb,
# /preview.css). People who try it can leave feedback – with the page, the
# device, light/dark, the colour scheme and the role, but without a name unless
# they agree to be contacted. Admins see it on /design_feedback.
class Main < Sinatra::Base
    DESIGN_FEEDBACK_MAX_LENGTH = 2000
    # who may switch the preview on – widened stage by stage (see
    # review/2026-11/redesign.md): :admins, then :teachers, then :all
    UI_PREVIEW_FOR = :admins

    def ui_preview_allowed?
        case UI_PREVIEW_FOR
        when :admins then admin_logged_in?
        when :teachers then admin_logged_in? || teacher_logged_in?
        else user_logged_in?
        end
    end

    def ui_preview?
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
    def design_preview_head(color_scheme)
        return '' unless ui_preview?
        dark = !!(@session_user || {})[:dark]
        "<style id='design_tokens'>#{DesignTokens.css(color_scheme, dark)}</style>\n" +
            "<link href='/preview.css' rel='stylesheet' />\n" +
            # Tabler icons instead of Fork Awesome (include/tabler/fa-to-tabler.js)
            "<link href='/include/tabler/tabler-icons.css' rel='stylesheet' />\n" +
            "<script src='/include/tabler/fa-to-tabler.js'></script>"
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
                    $('#bu_design_feedback').on('click', function () {
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
        tabs = []
        tabs << ['/', 'Heute', 'fa-calendar', nil] unless external_user_logged_in?
        tabs << ['/messages', 'Nachrichten', 'fa-comment-o', new_messages_count] if user_with_role_logged_in?(:can_receive_messages)
        tabs << ['#search', 'Suchen', 'fa-search', nil] if teacher_logged_in?
        tabs << ['/profil', 'Profil', 'fa-user-o', nil]
        StringIO.open do |io|
            io.puts "<nav class='pv-tabbar' aria-label='Hauptbereiche'>"
            tabs.each do |href, label, icon, badge|
                badge_html = (badge.to_i > 0) ? "<span class='pv-badge'>#{badge.to_i}</span>" : ''
                if href == '#search'
                    io.puts "<button type='button' class='pv-tab' id='bu_pv_search'><i class='fa #{icon}'></i>#{label}</button>"
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
                        document.querySelectorAll('.navbar .nav-link[href], .navbar .dropdown-item[href], .pv-tab[href]').forEach(function (a) {
                            let target = (a.getAttribute('href') || '').replace(/\\/$/, '') || '/';
                            if (target === here) a.classList.add('pv-active');
                        });
                        $('#bu_pv_more').on('click', function (e) {
                            let open = !$('#navbarTogglerDemo02').hasClass('show');
                            $('#navbarTogglerDemo02').collapse(open ? 'show' : 'hide');
                            e.currentTarget.setAttribute('aria-expanded', open ? 'true' : 'false');
                        });
                        $('#bu_pv_search').on('click', function () { $('#bu_quick_search').trigger('click'); });
                    });
                </script>
            END_OF_HTML
            io.string
        end
    end
end
