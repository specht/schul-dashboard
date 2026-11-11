# Resetting school mailboxes to their original password – the one on the
# E-Mail-Brief (Main.gen_password_for_email), on the page /passwoerter (which
# also has the Nextcloud self-service). Every reset is a case the admin
# decides; a separate bot changes the passwords in the mail provider's control
# panel and reports back, or the admin does it by hand and marks the case
# (plan: review/2026-11/mail-password-reset.md).
#
#   (:MailPasswordCase {id, ts, source, requested_by, reply_to, note, mailboxes,
#                       state, ts_decided, decided_by, ts_done, message,
#                       ts_reply, reply_sent_to})
#       -[:FOR]->(:MailPasswordResetMailbox {mailbox})   one per mailbox
#   source: 'dashboard' (requested on the page) | 'mail' (the admin entered a
#           request that came in by mail; reply_to is the address to answer)
#   state:  'open' (waits for the admin) -> 'approved' -> 'done' | 'failed'
#           'open' -> 'rejected', 'failed' -> 'approved' (retry) | 'cancelled'
#   ts_closed: a done case from a mail that was answered some other way
#   ts…:    Unix time with fractions, so cases within the same second stay in
#           order
#   (:MailPasswordResetBot {key: 'bot', last_seen})   last request of the bot
#
# Who may request which mailbox: students their own, Klassenleitung the
# students' and parents' (eltern.…) mailboxes of their classes, the admin all
# of them. Nothing is reset before the admin approved the case.
# After a done case the admin can answer the requester by mail, with the
# E-Mail-Brief attached.

class Main < Sinatra::Base
    MAIL_PASSWORD_RESET_MAX_PER_DAY = 3
    MAIL_PASSWORD_RESET_BOT_STALE_AFTER = 15 * 60
    MAIL_PASSWORD_RESET_SHOW_DAYS = 30
    MAIL_PASSWORD_CASE_ACTIVE = %w(open approved)
    MAIL_PASSWORD_CASE_MAX_MAILBOXES = 10

    # the student a mailbox belongs to (their own or their parents' mailbox)
    def mail_password_reset_student(mailbox)
        email = mailbox.to_s.sub(/\Aeltern\./, '')
        return nil unless @@user_info[email] && user_has_role(email, :schueler)
        email
    end

    def mail_password_reset_allowed?(mailbox)
        student = mail_password_reset_student(mailbox)
        return false unless student
        return true if admin_logged_in?
        return true if klassenleiter_for_klasse_logged_in?(@@user_info[student][:klasse])
        # students: their own mailbox, not their parents' one
        mailbox == student && schueler_logged_in? && @session_user[:email] == student
    end

    def mail_password_reset_label(mailbox)
        student = mail_password_reset_student(mailbox)
        return mailbox unless student
        info = @@user_info[student]
        label = "#{info[:display_name]} (#{tr_klasse(info[:klasse])})"
        mailbox == student ? label : "Eltern von #{label}"
    end

    # classes whose students the logged in teacher may request resets for
    def mail_password_reset_klassen
        return [] unless teacher_logged_in?
        @@klassen_order.select { |klasse| klassenleiter_for_klasse_logged_in?(klasse) }
    end

    def may_use_mail_password_reset?
        user_logged_in? && (schueler_logged_in? || admin_logged_in? || !mail_password_reset_klassen.empty?)
    end

    def may_use_password_page?
        user_logged_in? && (user_with_role_logged_in?(:can_use_nextcloud) || may_use_mail_password_reset?)
    end

    def this_is_a_page_for_passwords
        redirect "#{WEB_ROOT}/", 303 unless may_use_password_page?
    end

    # Nextcloud: login data and resetting the own password to the initial
    # one – no questions asked (POST /api/reset_nc_password, main.rb)
    def print_nextcloud_password_section
        return '' unless user_with_role_logged_in?(:can_use_nextcloud)
        nc_login = CGI.escapeHTML(@session_user[:nc_login].to_s)
        password = CGI.escapeHTML(@session_user[:initial_nc_password].to_s)
        url = CGI.escapeHTML(NEXTCLOUD_URL)
        login_url = CGI.escapeHTML("#{NEXTCLOUD_URL}/index.php/login?user=#{CGI.escape(@session_user[:nc_login].to_s)}")
        <<~END_OF_HTML
            <h3>Nextcloud</h3>
            <p>Mit diesen Zugangsdaten meldest du dich in der Nextcloud an:</p>
            <table class='table nc-login-table'><tbody>
            <tr><th>Adresse:</th><td>
                <div class='input-group'>
                    <input type='text' class='form-control' value='#{url}' readonly />
                    <div class='input-group-append'><a class='btn btn-secondary' target='_blank' href='#{login_url}'><i class='fa fa-external-link'></i><span class='d-none d-sm-inline'>&nbsp;&nbsp;Öffnen…</span></a></div>
                </div>
            </td></tr>
            <tr><th>Login:</th><td>
                <div class='input-group'>
                    <input id='ti_nc_login' type='text' class='form-control' value='#{nc_login}' readonly />
                    <div class='input-group-append'><button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' data-clipboard-target='#ti_nc_login'><i class='fa fa-clipboard'></i><span class='d-none d-sm-inline'>&nbsp;&nbsp;Kopieren</span></button></div>
                </div>
            </td></tr>
            <tr><th>Initialpasswort:</th><td>
                <div class='input-group'>
                    <input id='ti_initial_nc_password' type='password' class='form-control' value='#{password}' readonly />
                    <div class='input-group-append'>
                        <button class='btn bu-show-password btn-secondary' style='border-right: 2px solid #444;'><i class='fa fa-eye'></i><span class='d-none d-sm-inline'>&nbsp;&nbsp;Anzeigen</span></button>
                        <button class='btn btn-secondary btn-clipboard' data-clipboard-action='copy' data-clipboard-text='#{password}'><i class='fa fa-clipboard'></i><span class='d-none d-sm-inline'>&nbsp;&nbsp;Kopieren</span></button>
                    </div>
                </div>
            </td></tr>
            </tbody></table>
            <p>Du kannst dein Nextcloud-Passwort jederzeit in der Nextcloud ändern. Falls du ein selbst gewähltes Passwort vergessen hast, kannst du es hier sofort wieder auf dein Initialpasswort zurücksetzen:</p>
            <div class='nc-actions' style='text-align: center;'>
                <a href='#{login_url}' target='_blank' class='btn btn-success'><i class='fa fa-sign-in'></i>&nbsp;&nbsp;Zur Nextcloud-Anmeldung…</a>
                <button class='btn btn-outline-secondary bu-reset-nc-password'><i class='fa fa-key'></i>&nbsp;&nbsp;Nextcloud-Passwort zurücksetzen</button>
            </div>
            <div id='nc_reset_result' style='margin-top: 1em;'></div>
        END_OF_HTML
    end

    # one table row per mailbox the user may request; status, password and
    # button are filled in by the page script from /api/mail_password_reset_status
    def print_mail_password_reset_row(io, mailbox, label)
        io.puts "<tr class='mail-reset-row' data-mailbox='#{CGI.escapeHTML(mailbox)}'>"
        io.puts "<td>#{CGI.escapeHTML(label)}<br /><small class='text-muted'>#{CGI.escapeHTML(mailbox)}</small></td>"
        io.puts "<td class='mail-reset-state'></td>"
        io.puts "<td class='mail-reset-action' style='text-align: right;'><button class='btn btn-sm btn-outline-secondary bu_request_mail_reset' data-mailbox='#{CGI.escapeHTML(mailbox)}' data-label='#{CGI.escapeHTML(label)}'><i class='fa fa-key'></i>&nbsp;&nbsp;Zurücksetzen beantragen</button></td>"
        io.puts "</tr>"
    end

    # Klassenleitung: one row per student, a column each for the student's
    # and the parents' mailbox (status below the button)
    def print_mail_password_reset_student(io, student)
        info = @@user_info[student]
        io.puts "<tr class='mail-reset-student' data-student='#{CGI.escapeHTML(student)}'>"
        io.puts "<td class='mail-reset-name'>#{CGI.escapeHTML(info[:display_name])}</td>"
        [[student, 'Postfach', info[:display_name]], ["eltern.#{student}", 'Eltern-Postfach', "Eltern von #{info[:display_name]}"]].each do |mailbox, title, label|
            io.puts "<td class='mail-reset-row mail-reset-sub' data-mailbox='#{CGI.escapeHTML(mailbox)}' data-title='#{title}'>"
            io.puts "<button class='btn btn-sm btn-outline-secondary bu_request_mail_reset' data-mailbox='#{CGI.escapeHTML(mailbox)}' data-label='#{CGI.escapeHTML(label)}' title='#{CGI.escapeHTML(mailbox)}'><i class='fa fa-key'></i>&nbsp;&nbsp;Zurücksetzen…</button>"
            io.puts "<div class='mail-reset-state'></div>"
            io.puts "</td>"
        end
        io.puts "</tr>"
    end

    def print_mail_password_reset_page
        return '' unless may_use_mail_password_reset?
        StringIO.open do |io|
            io.puts "<h3 style='margin-top: 1.5em;'>E-Mail-Postfach</h3>"
            if schueler_logged_in?
                email = @session_user[:email]
                io.puts "<p>Wenn du das Passwort für dein schulisches E-Mail-Postfach vergessen hast, kannst du hier beantragen, dass es auf dein ursprüngliches Passwort zurückgesetzt wird – das aus deinem E-Mail-Brief. Die Administration prüft jede Anfrage; danach geht es meistens schnell. Deine Eltern bekommen anschließend eine kurze Nachricht an ihre E-Mail-Adresse.</p>"
                io.puts "<div class='table-responsive'><table class='table'><tbody>"
                print_mail_password_reset_row(io, email, @session_user[:display_name])
                io.puts "</tbody></table></div>"
                io.puts "<p class='text-muted mail-reset-parents-hint'><i class='fa fa-info-circle'></i>&nbsp;&nbsp;Haben deine Eltern das Passwort für ihr Postfach <b>eltern.#{CGI.escapeHTML(email)}</b> vergessen? Dann sag bitte deiner Klassenleitung Bescheid – sie kann es zurücksetzen lassen. Deine Eltern können auch eine E-Mail an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} (#{CGI.escapeHTML(WEBSITE_MAINTAINER_EMAIL)}) schreiben.</p>"
            end
            mail_password_reset_klassen.each do |klasse|
                io.puts "<h4>Klasse #{CGI.escapeHTML(tr_klasse(klasse))}</h4>"
                if klasse == mail_password_reset_klassen.first
                    io.puts "<p>Hier kannst du beantragen, dass das Postfach einer Schülerin / eines Schülers oder das Eltern-Postfach auf das ursprüngliche Passwort aus dem E-Mail-Brief zurückgesetzt wird. Die Administration prüft jede Anfrage; sobald es erledigt ist, kannst du das Passwort hier anzeigen.</p>"
                    io.puts "<p class='alert alert-info mail-reset-forward-hint'>Bekommst du eine E-Mail mit der Bitte, ein Passwort zurückzusetzen, leite sie bitte an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} (#{CGI.escapeHTML(WEBSITE_MAINTAINER_EMAIL)}) weiter.</p>"
                end
                io.puts "<div class='table-responsive'><table class='table table-sm mail-reset-klasse'>"
                io.puts "<thead><tr><th>Schüler:in</th><th>Postfach</th><th>Eltern-Postfach</th></tr></thead><tbody>"
                (@@schueler_for_klasse[klasse] || []).each do |student|
                    print_mail_password_reset_student(io, student)
                end
                io.puts "</tbody></table></div>"
            end
            if admin_logged_in?
                io.puts "<h4 style='margin-top: 1em;'>Anfragen</h4>"
                io.puts "<div class='card' style='margin-bottom: 1.5em;'><div class='card-body'>"
                io.puts "<h5 class='card-title'>Neue Anfrage (z. B. per E-Mail)</h5>"
                io.puts "<div class='form-group'><label for='ti_mail_case_mailbox'>Postfächer</label>"
                io.puts "<div class='input-group'>"
                io.puts "<input id='ti_mail_case_mailbox' class='form-control' list='li_mail_reset_mailboxes' placeholder='E-Mail-Adresse (auch eltern.…)' autocomplete='off' />"
                io.puts "<div class='input-group-append'><button id='bu_add_mail_case_mailbox' class='btn btn-outline-secondary'><i class='fa fa-plus'></i>&nbsp;&nbsp;Hinzufügen</button></div>"
                io.puts "</div><div id='mail_case_mailboxes' style='margin-top: 0.5em;'></div></div>"
                io.puts "<div class='form-group'><label for='ti_mail_case_reply_to'>Antwort an</label>"
                io.puts "<input id='ti_mail_case_reply_to' type='email' class='form-control' placeholder='Absender der E-Mail' autocomplete='off' /></div>"
                io.puts "<div class='form-group'><label for='ti_mail_case_note'>Notiz</label>"
                io.puts "<input id='ti_mail_case_note' class='form-control' maxlength='500' autocomplete='off' /></div>"
                io.puts "<button id='bu_create_mail_case' class='btn btn-primary'><i class='fa fa-plus'></i>&nbsp;&nbsp;Zur Liste hinzufügen</button>"
                io.puts "</div></div>"
                io.puts "<datalist id='li_mail_reset_mailboxes'>"
                @@klassen_order.each do |klasse|
                    (@@schueler_for_klasse[klasse] || []).each do |student|
                        io.puts "<option value='#{CGI.escapeHTML(student)}'>#{CGI.escapeHTML(mail_password_reset_label(student))}</option>"
                        io.puts "<option value='eltern.#{CGI.escapeHTML(student)}'>#{CGI.escapeHTML(mail_password_reset_label('eltern.' + student))}</option>"
                    end
                end
                io.puts "</datalist>"
                io.puts "<h5>Offene Anfragen (<span id='mail_cases_open_count'>0</span>)</h5>"
                io.puts "<p id='mail_reset_bot_state' class='text-muted'></p>"
                io.puts "<div class='table-responsive'><table class='table table-sm mail-cases' id='mail_cases_open'>"
                io.puts "<thead><tr><th>Postfächer</th><th>Anfrage</th><th>Nächster Schritt</th></tr></thead><tbody></tbody></table></div>"
                io.puts "<details style='margin-top: 1em;'><summary>Abgeschlossen (letzte #{MAIL_PASSWORD_RESET_SHOW_DAYS} Tage): <span id='mail_cases_closed_count'>0</span></summary>"
                io.puts "<div class='table-responsive'><table class='table table-sm mail-cases' id='mail_cases_closed'>"
                io.puts "<thead><tr><th>Postfächer</th><th>Anfrage</th><th>Ergebnis</th></tr></thead><tbody></tbody></table></div></details>"
            end
            io.string
        end
    end

    def mail_password_reset_bot_last_seen
        row = neo4j_query("MATCH (b:MailPasswordResetBot {key: 'bot'}) RETURN b.last_seen AS last_seen;").first
        row ? row['last_seen'] : nil
    end

    def notify_admin_about_mail_password_reset(subject_text, lines)
        deliver_mail do
            to WEBSITE_MAINTAINER_EMAIL
            from SMTP_FROM
            subject subject_text
            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                lines.each { |line| io.puts "<p>#{line}</p>" }
                io.puts "<p><a href='#{WEB_ROOT}/passwoerter'>#{WEB_ROOT}/passwoerter</a></p>"
                io.string
            end
        end
    end

    def notify_parents_about_mail_password_reset(mailbox, ts)
        info = @@user_info[mailbox]
        parents = "eltern.#{mailbox}"
        when_text = Time.at(ts).strftime('%d.%m.%Y um %H:%M Uhr')
        deliver_mail do
            to parents
            from SMTP_FROM
            subject 'Passwort des schulischen E-Mail-Postfachs Ihres Kindes zurückgesetzt'
            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                io.puts "<p>Das Passwort des schulischen E-Mail-Postfachs #{CGI.escapeHTML(mailbox)} (#{CGI.escapeHTML(info[:display_name])}) wurde am #{when_text} auf das ursprüngliche Passwort zurückgesetzt. Angefordert wurde das über das Dashboard-Konto Ihres Kindes.</p>"
                io.puts "<p>Falls Ihr Kind das nicht selbst angefordert hat, wenden Sie sich bitte an #{WEBSITE_MAINTAINER_NAME_AKKUSATIV} (#{WEBSITE_MAINTAINER_EMAIL}).</p>"
                io.puts "<p>Viele Grüße,<br />#{WEBSITE_MAINTAINER_NAME}</p>"
                io.string
            end
        end
    end

    def mail_password_case(id)
        row = neo4j_query("MATCH (c:MailPasswordCase {id: $id}) RETURN c;", :id => id).first
        row ? row['c'] : nil
    end

    # Creates a case unless one of the mailboxes has an active case or (with
    # a limit) was reset too often today. Returns 'requested', 'pending' or
    # 'limit'.
    def create_mail_password_case!(mailboxes, attrs, daily_limit)
        now = Time.now.to_f
        result = nil
        transaction do
            # one lock node per mailbox, so parallel requests are counted one after the other
            counts = neo4j_query_expect_one(<<~END_OF_QUERY, :mailboxes => mailboxes, :active => MAIL_PASSWORD_CASE_ACTIVE, :since => now - 24 * 3600)
                UNWIND $mailboxes AS mailbox
                MERGE (m:MailPasswordResetMailbox {mailbox: mailbox})
                SET m._lock = true REMOVE m._lock
                WITH m
                OPTIONAL MATCH (c:MailPasswordCase)-[:FOR]->(m)
                WITH m.mailbox AS mailbox,
                     count(CASE WHEN c.state IN $active THEN 1 END) AS active,
                     count(CASE WHEN c.ts >= $since AND c.source = 'dashboard' THEN 1 END) AS recent
                RETURN sum(active) AS active, max(recent) AS recent;
            END_OF_QUERY
            if counts['active'] > 0
                result = 'pending'
            elsif daily_limit && counts['recent'] >= MAIL_PASSWORD_RESET_MAX_PER_DAY
                result = 'limit'
            else
                props = attrs.merge(:id => RandomTag.generate(16), :ts => now, :mailboxes => mailboxes)
                neo4j_query(<<~END_OF_QUERY, :props => props, :mailboxes => mailboxes)
                    CREATE (c:MailPasswordCase)
                    SET c = $props
                    WITH c
                    UNWIND $mailboxes AS mailbox
                    MATCH (m:MailPasswordResetMailbox {mailbox: mailbox})
                    CREATE (c)-[:FOR]->(m);
                END_OF_QUERY
                result = 'requested'
            end
        end
        result
    end

    # approved -> done / failed; returns the case or nil if it wasn't approved
    def finish_mail_password_case!(id, ok, message, notify_admin_on_failure)
        ts = Time.now.to_f
        row = neo4j_query(<<~END_OF_QUERY, :id => id, :state => ok ? 'done' : 'failed', :ts => ts, :message => message).first
            MATCH (c:MailPasswordCase {id: $id, state: 'approved'})
            SET c.state = $state, c.ts_done = $ts, c.message = $message
            RETURN c;
        END_OF_QUERY
        return nil unless row
        c = row['c']
        if ok
            # a student's own request: the parents get to know about it
            if c[:source] == 'dashboard' && c[:mailboxes] == [c[:requested_by]]
                notify_parents_about_mail_password_reset(c[:requested_by], ts)
            end
        elsif notify_admin_on_failure
            notify_admin_about_mail_password_reset('Dashboard: E-Mail-Passwort konnte nicht zurückgesetzt werden', [
                "Das Passwort für #{CGI.escapeHTML(c[:mailboxes].join(', '))} konnte nicht zurückgesetzt werden.",
                "Meldung: #{CGI.escapeHTML(message.to_s)}",
            ])
        end
        c
    end

    def normalize_mailbox(mailbox)
        mailbox.to_s.strip.downcase
    end

    post '/api/request_mail_password_reset' do
        require_user!
        data = parse_request_data(:required_keys => [:mailbox], :max_value_lengths => {:mailbox => 256})
        mailbox = normalize_mailbox(data[:mailbox])
        assert(mail_password_reset_allowed?(mailbox), 'mail password reset not allowed')
        # requested for someone else (Klassenleitung): the admin answers them
        # with the E-Mail-Brief to pass on
        own = mailbox == @session_user[:email]
        result = create_mail_password_case!([mailbox], {
            :source => 'dashboard', :requested_by => @session_user[:email], :state => 'open',
            :reply_to => (own || admin_logged_in?) ? nil : @session_user[:email],
        }, !admin_logged_in?)
        if result == 'requested'
            notify_admin_about_mail_password_reset('Dashboard: E-Mail-Passwort zurücksetzen – bitte freigeben', [
                "#{CGI.escapeHTML(@session_user[:display_name])} möchte das Passwort für #{CGI.escapeHTML(mailbox)} (#{CGI.escapeHTML(mail_password_reset_label(mailbox))}) zurücksetzen lassen.",
            ])
        end
        respond(:result => result)
    end

    # a request that came in by mail, entered by the admin: lands in the list
    # as an open case like a click on the page
    post '/api/create_mail_password_case' do
        require_admin!
        data = parse_request_data(:required_keys => [:mailboxes], :optional_keys => [:reply_to, :note],
                                  :types => {:mailboxes => Array},
                                  :max_value_lengths => {:reply_to => 256, :note => 500})
        mailboxes = data[:mailboxes].map { |x| normalize_mailbox(x) }.reject(&:empty?).uniq
        assert(!mailboxes.empty? && mailboxes.size <= MAIL_PASSWORD_CASE_MAX_MAILBOXES, 'invalid mailboxes')
        mailboxes.each do |mailbox|
            assert(mailbox.size <= 256 && mail_password_reset_allowed?(mailbox), "unknown mailbox #{mailbox}")
        end
        reply_to = (data[:reply_to] || '').strip
        assert(reply_to.empty? || reply_to =~ /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, 'invalid reply address')
        result = create_mail_password_case!(mailboxes, {
            :source => 'mail', :requested_by => @session_user[:email],
            :reply_to => reply_to.empty? ? nil : reply_to, :note => (data[:note] || '').strip,
            :state => 'open',
        }, false)
        respond(:result => result)
    end

    # The admin's steps on a case: action => [state it must be in, new state]
    #   approve  open     -> approved   (the bot or the admin resets it now)
    #   reject   open     -> rejected
    #   done     approved -> done       (reset by hand in the control panel)
    #   failed   approved -> failed
    #   retry    failed   -> approved
    #   cancel   failed   -> cancelled
    #   close    done     -> done       (came by mail, answered some other way)
    MAIL_PASSWORD_CASE_ACTIONS = {
        'approve' => %w(open approved),
        'reject' => %w(open rejected),
        'done' => %w(approved done),
        'failed' => %w(approved failed),
        'retry' => %w(failed approved),
        'cancel' => %w(failed cancelled),
        'close' => %w(done done),
    }

    post '/api/update_mail_password_case' do
        require_admin!
        data = parse_request_data(:required_keys => [:id, :action],
                                  :max_value_lengths => {:id => 64, :action => 16})
        from, to = MAIL_PASSWORD_CASE_ACTIONS[data[:action]]
        assert(from, 'unknown action')
        if %w(done failed).include?(data[:action])
            c = finish_mail_password_case!(data[:id], data[:action] == 'done', 'von Hand', false)
            respond(:result => c ? 'ok' : 'wrong_state')
        else
            extra = case data[:action]
                when 'approve', 'reject' then 'c.ts_decided = $ts, c.decided_by = $by'
                when 'close' then 'c.ts_closed = $ts'
                else 'c.ts_updated = $ts'
            end
            row = neo4j_query(<<~END_OF_QUERY, :id => data[:id], :from => from, :to => to, :ts => Time.now.to_f, :by => @session_user[:email]).first
                MATCH (c:MailPasswordCase {id: $id, state: $from})
                SET c.state = $to, #{extra}
                RETURN c.id AS id;
            END_OF_QUERY
            respond(:result => row ? 'ok' : 'wrong_state')
        end
    end

    # Cases the logged in user may see, newest first. The admin sees
    # everything; others only the mailboxes they may request, without who
    # asked, notes and reply addresses, and passwords only for mailboxes
    # whose latest case is done.
    post '/api/mail_password_reset_status' do
        require_user!
        rows = neo4j_query(<<~END_OF_QUERY, :since => Time.now.to_f - MAIL_PASSWORD_RESET_SHOW_DAYS * 24 * 3600, :active => MAIL_PASSWORD_CASE_ACTIVE).map { |x| x['c'] }
            MATCH (c:MailPasswordCase)
            WHERE c.ts >= $since OR c.state IN $active OR c.state = 'failed'
               OR (c.state = 'done' AND (c.source = 'mail' OR c.reply_to IS NOT NULL) AND c.ts_reply IS NULL AND c.ts_closed IS NULL)
            RETURN c ORDER BY c.ts DESC;
        END_OF_QUERY
        admin = admin_logged_in?
        seen = Set.new
        cases = []
        rows.each do |c|
            mailboxes = c[:mailboxes].select { |mailbox| mail_password_reset_allowed?(mailbox) }
            next if mailboxes.empty?
            entry = {
                :id => c[:id],
                :state => c[:state],
                :ts => c[:ts],
                :ts_done => c[:ts_done],
                :mailboxes => mailboxes.map do |mailbox|
                    latest = !seen.include?(mailbox)
                    seen << mailbox
                    item = {:mailbox => mailbox, :label => mail_password_reset_label(mailbox), :latest => latest}
                    item[:password] = Main.gen_password_for_email(mailbox) if c[:state] == 'done' && (latest || admin)
                    item
                end,
            }
            if admin
                requester = @@user_info[c[:requested_by]] || {}
                entry.merge!(
                    :source => c[:source],
                    :requested_by => requester[:display_name] || c[:requested_by],
                    :reply_to => c[:reply_to],
                    :note => c[:note],
                    :message => c[:message],
                    :ts_decided => c[:ts_decided],
                    :ts_reply => c[:ts_reply],
                    :reply_sent_to => c[:reply_sent_to],
                    :ts_closed => c[:ts_closed],
                )
            end
            cases << entry
        end
        result = {:cases => cases}
        if admin
            result[:bot_last_seen] = mail_password_reset_bot_last_seen
            result[:bot_active] = !result[:bot_last_seen].nil? && Time.now.to_i - result[:bot_last_seen] < MAIL_PASSWORD_RESET_BOT_STALE_AFTER
        end
        respond(result)
    end

    # ---- answering the requester, with the E-Mail-Brief attached ----

    def mail_password_case_students(c)
        c[:mailboxes].map { |mailbox| mail_password_reset_student(mailbox) }.compact.uniq
    end

    # "das Postfach von Anna Muster", "das Eltern-Postfach von …", both
    def mail_password_case_phrase(c)
        mail_password_case_students(c).map do |student|
            kinds = []
            kinds << 'das Postfach' if c[:mailboxes].include?(student)
            kinds << 'das Eltern-Postfach' if c[:mailboxes].include?("eltern.#{student}")
            "#{kinds.join(' und ')} von #{@@user_info[student][:display_name]}"
        end.join(' sowie ')
    end

    def mail_password_case_reply_draft(c)
        sender = [@session_user[:first_name], @session_user[:last_name]].map(&:to_s).reject(&:empty?).join(' ')
        body = if c[:source] == 'dashboard'
            # the Klassenleitung asked: they pass the letter on
            "Hallo,\n\nich habe das Passwort für #{mail_password_case_phrase(c)} zurückgesetzt. Im Anhang findest du den E-Mail-Brief mit den Zugangsdaten – bitte gib ihn weiter.\n\nViele Grüße\n#{sender}\n"
        else
            "Sehr geehrte Frau / Herr …,\n\nich habe das Passwort für #{mail_password_case_phrase(c)} zurückgesetzt und sende Ihnen die Zugangsdaten im Anhang.\n\nViele Grüße\n#{sender}\n"
        end
        {
            :to => c[:reply_to] || '',
            :subject => 'Passwort für das schulische E-Mail-Postfach zurückgesetzt',
            :body => body,
            :attachment => "E-Mail-Brief (#{mail_password_case_students(c).map { |x| @@user_info[x][:display_name] }.join(', ')})",
        }
    end

    post '/api/mail_password_case_reply_draft' do
        require_admin!
        data = parse_request_data(:required_keys => [:id], :max_value_lengths => {:id => 64})
        c = mail_password_case(data[:id])
        assert(c && c[:state] == 'done', 'case not done')
        respond(mail_password_case_reply_draft(c))
    end

    post '/api/send_mail_password_case_reply' do
        require_admin!
        data = parse_request_data(:required_keys => [:id, :to, :subject, :body],
                                  :max_value_lengths => {:id => 64, :to => 256, :subject => 200, :body => 10000})
        c = mail_password_case(data[:id])
        assert(c && c[:state] == 'done', 'case not done')
        recipient = data[:to].strip
        assert(recipient =~ /\A[^@\s,;<>]+@[^@\s,;<>]+\.[^@\s,;<>]+\z/, 'invalid recipient')
        students = mail_password_case_students(c)
        assert(!students.empty?)
        pdf = Main.print_email_letters(students)
        filename = students.size == 1 ? "E-Mail-Brief #{@@user_info[students.first][:display_name]}.pdf" : 'E-Mail-Briefe.pdf'
        admin_email = @session_user[:email]
        subject_text = data[:subject].strip
        body_text = data[:body]
        deliver_mail(body_text) do
            to recipient
            from SMTP_FROM
            reply_to admin_email
            bcc admin_email
            subject subject_text
            add_file :content_type => 'application/pdf', :content => pdf, :filename => filename
        end
        neo4j_query(<<~END_OF_QUERY, :id => c[:id], :ts => Time.now.to_f, :to => recipient)
            MATCH (c:MailPasswordCase {id: $id})
            SET c.ts_reply = $ts, c.reply_sent_to = $to;
        END_OF_QUERY
        respond(:result => 'sent')
    end

    # ---- interface for the bot (Authorization: Bearer <token>) ----

    def require_mail_password_reset_bot!
        # off unless credentials.rb defines a long enough token
        token = defined?(MAIL_PASSWORD_RESET_BOT_TOKEN) ? MAIL_PASSWORD_RESET_BOT_TOKEN : nil
        halt 404 unless token.is_a?(String) && token.size >= 32
        given = request.env['HTTP_AUTHORIZATION'].to_s.sub(/\ABearer /, '')
        halt 401 unless Rack::Utils.secure_compare(given, token)
    end

    # approved cases only: nothing is reset without the admin's decision
    get '/api/mail_password_reset_bot/pending' do
        require_mail_password_reset_bot!
        neo4j_query("MERGE (b:MailPasswordResetBot {key: 'bot'}) SET b.last_seen = $ts;", :ts => Time.now.to_i)
        rows = neo4j_query("MATCH (c:MailPasswordCase {state: 'approved'}) RETURN c.id AS id, c.mailboxes AS mailboxes ORDER BY c.ts;")
        respond(:cases => rows.map do |row|
            {:id => row['id'], :mailboxes => row['mailboxes'].map { |mailbox| {:mailbox => mailbox, :password => Main.gen_password_for_email(mailbox)} }}
        end)
    end

    post '/api/mail_password_reset_bot/result' do
        require_mail_password_reset_bot!
        data = parse_request_data(:required_keys => [:id, :ok], :optional_keys => [:message],
                                  :types => {:ok => Object},
                                  :max_value_lengths => {:id => 64, :message => 500})
        assert([true, false].include?(data[:ok]))
        c = finish_mail_password_case!(data[:id], data[:ok], data[:message], true)
        respond(:result => c ? 'ok' : 'not_approved')
    end
end
