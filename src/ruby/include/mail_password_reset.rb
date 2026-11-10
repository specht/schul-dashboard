# Resetting a school mailbox to its original password – the one on the
# E-Mail-Brief (Main.gen_password_for_email). The dashboard collects the
# requests; a separate bot changes the password in the mail provider's
# control panel and reports back (plan: review/2026-11/mail-password-reset.md).
#
#   (:MailPasswordReset {id, mailbox, requested_by, ts, state, ts_done, message})
#       -[:FOR]->(:MailPasswordResetMailbox {mailbox})
#   state: 'pending' -> 'done' | 'failed'
#   ts, ts_done: Unix time with fractions, so requests made within the same
#   second are still in order
#   (:MailPasswordResetBot {key: 'bot', last_seen})   last request of the bot
#
# Who may request which mailbox: students their own, Klassenleitung the
# students of their classes, the admin also the parents' (eltern.…) ones.
# Until the bot has been seen recently, the admin gets a mail for every new
# request and can mark it done by hand on /mail_passwort.

class Main < Sinatra::Base
    MAIL_PASSWORD_RESET_MAX_PER_DAY = 3
    MAIL_PASSWORD_RESET_BOT_STALE_AFTER = 15 * 60
    MAIL_PASSWORD_RESET_SHOW_DAYS = 30

    # the student a mailbox belongs to (their own or their parents' mailbox)
    def mail_password_reset_student(mailbox)
        email = mailbox.sub(/\Aeltern\./, '')
        return nil unless @@user_info[email] && user_has_role(email, :schueler)
        email
    end

    def mail_password_reset_allowed?(mailbox)
        student = mail_password_reset_student(mailbox)
        return false unless student
        return true if admin_logged_in?
        # parents' mailboxes: only the admin
        return false unless mailbox == student
        return true if schueler_logged_in? && @session_user[:email] == student
        klassenleiter_for_klasse_logged_in?(@@user_info[student][:klasse])
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

    def this_is_a_page_for_mail_password_reset
        unless user_logged_in? && (schueler_logged_in? || admin_logged_in? || !mail_password_reset_klassen.empty?)
            redirect "#{WEB_ROOT}/", 303
        end
    end

    # one table row per mailbox the user may reset; status, password and
    # button are filled in by the page script from /api/mail_password_reset_status
    def print_mail_password_reset_row(io, mailbox, label)
        io.puts "<tr class='mail-reset-row' data-mailbox='#{CGI.escapeHTML(mailbox)}'>"
        io.puts "<td>#{CGI.escapeHTML(label)}<br /><small class='text-muted'>#{CGI.escapeHTML(mailbox)}</small></td>"
        io.puts "<td class='mail-reset-state'></td>"
        io.puts "<td class='mail-reset-action' style='text-align: right;'><button class='btn btn-sm btn-outline-danger bu_request_mail_reset' data-mailbox='#{CGI.escapeHTML(mailbox)}' data-label='#{CGI.escapeHTML(label)}'><i class='fa fa-key'></i>&nbsp;&nbsp;Zurücksetzen</button></td>"
        io.puts "</tr>"
    end

    def print_mail_password_reset_page
        StringIO.open do |io|
            if schueler_logged_in?
                email = @session_user[:email]
                io.puts "<h3>Dein E-Mail-Postfach</h3>"
                io.puts "<p>Wenn du das Passwort für dein schulisches E-Mail-Postfach vergessen hast, kannst du es hier auf dein ursprüngliches Passwort zurücksetzen lassen – das aus deinem E-Mail-Brief. Das dauert meistens nur wenige Minuten. Deine Eltern bekommen danach eine kurze Nachricht an ihre E-Mail-Adresse.</p>"
                io.puts "<div class='table-responsive'><table class='table'><tbody>"
                print_mail_password_reset_row(io, email, @session_user[:display_name])
                io.puts "</tbody></table></div>"
            end
            mail_password_reset_klassen.each do |klasse|
                io.puts "<h3>Klasse #{CGI.escapeHTML(tr_klasse(klasse))}</h3>"
                io.puts "<p>Das Passwort wird auf das ursprüngliche Passwort aus dem E-Mail-Brief zurückgesetzt. Sobald es erledigt ist, kannst du es hier anzeigen oder den E-Mail-Brief drucken.</p>" if klasse == mail_password_reset_klassen.first
                io.puts "<div class='table-responsive'><table class='table'><tbody>"
                (@@schueler_for_klasse[klasse] || []).each do |student|
                    print_mail_password_reset_row(io, student, @@user_info[student][:display_name])
                end
                io.puts "</tbody></table></div>"
            end
            if admin_logged_in?
                io.puts "<h3>Administration</h3>"
                io.puts "<p id='mail_reset_bot_state' class='text-muted'></p>"
                io.puts "<div class='input-group' style='max-width: 40em;'>"
                io.puts "<input id='ti_mail_reset_mailbox' class='form-control' list='li_mail_reset_mailboxes' placeholder='E-Mail-Adresse (auch eltern.…)' autocomplete='off' />"
                io.puts "<div class='input-group-append'><button id='bu_request_mail_reset_mailbox' class='btn btn-outline-danger'><i class='fa fa-key'></i>&nbsp;&nbsp;Zurücksetzen</button></div>"
                io.puts "</div>"
                io.puts "<datalist id='li_mail_reset_mailboxes'>"
                @@klassen_order.each do |klasse|
                    (@@schueler_for_klasse[klasse] || []).each do |student|
                        io.puts "<option value='#{CGI.escapeHTML(student)}'>#{CGI.escapeHTML(mail_password_reset_label(student))}</option>"
                        io.puts "<option value='eltern.#{CGI.escapeHTML(student)}'>#{CGI.escapeHTML(mail_password_reset_label('eltern.' + student))}</option>"
                    end
                end
                io.puts "</datalist>"
                io.puts "<div class='table-responsive' style='margin-top: 1em;'><table class='table table-sm' id='mail_reset_requests'>"
                io.puts "<thead><tr><th>Postfach</th><th>Angefordert</th><th>Status</th><th></th></tr></thead><tbody></tbody></table></div>"
            end
            io.string
        end
    end

    def mail_password_reset_bot_last_seen
        row = neo4j_query("MATCH (b:MailPasswordResetBot {key: 'bot'}) RETURN b.last_seen AS last_seen;").first
        row ? row['last_seen'] : nil
    end

    def mail_password_reset_bot_active?
        last_seen = mail_password_reset_bot_last_seen
        !last_seen.nil? && Time.now.to_i - last_seen < MAIL_PASSWORD_RESET_BOT_STALE_AFTER
    end

    def notify_admin_about_mail_password_reset(subject_text, lines)
        deliver_mail do
            to WEBSITE_MAINTAINER_EMAIL
            from SMTP_FROM
            subject subject_text
            StringIO.open do |io|
                io.puts "<p>Hallo!</p>"
                lines.each { |line| io.puts "<p>#{line}</p>" }
                io.puts "<p><a href='#{WEB_ROOT}/mail_passwort'>#{WEB_ROOT}/mail_passwort</a></p>"
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

    # pending -> done / failed; returns the request or nil if it wasn't pending
    def finish_mail_password_reset!(id, ok, message, notify_admin_on_failure)
        ts = Time.now.to_f
        row = neo4j_query(<<~END_OF_QUERY, :id => id, :state => ok ? 'done' : 'failed', :ts => ts, :message => message).first
            MATCH (r:MailPasswordReset {id: $id, state: 'pending'})
            SET r.state = $state, r.ts_done = $ts, r.message = $message
            RETURN r.mailbox AS mailbox, r.requested_by AS requested_by;
        END_OF_QUERY
        return nil unless row
        mailbox = row['mailbox']
        if ok
            # a student's own request: the parents get to know about it
            notify_parents_about_mail_password_reset(mailbox, ts) if row['requested_by'] == mailbox
        elsif notify_admin_on_failure
            notify_admin_about_mail_password_reset('Dashboard: E-Mail-Passwort konnte nicht zurückgesetzt werden', [
                "Das Passwort für #{CGI.escapeHTML(mailbox)} konnte nicht zurückgesetzt werden.",
                "Meldung: #{CGI.escapeHTML(message.to_s)}",
            ])
        end
        row
    end

    post '/api/request_mail_password_reset' do
        require_user!
        data = parse_request_data(:required_keys => [:mailbox], :max_value_lengths => {:mailbox => 256})
        mailbox = data[:mailbox].strip.downcase
        assert(mail_password_reset_allowed?(mailbox), 'mail password reset not allowed')
        now = Time.now.to_f
        result = nil
        transaction do
            # one lock node per mailbox, so parallel requests are counted one after the other
            counts = neo4j_query_expect_one(<<~END_OF_QUERY, :mailbox => mailbox, :since => now - 24 * 3600)
                MERGE (m:MailPasswordResetMailbox {mailbox: $mailbox})
                SET m._lock = true REMOVE m._lock
                WITH m
                OPTIONAL MATCH (r:MailPasswordReset)-[:FOR]->(m)
                RETURN count(CASE WHEN r.state = 'pending' THEN 1 END) AS pending,
                       count(CASE WHEN r.ts >= $since THEN 1 END) AS recent;
            END_OF_QUERY
            if counts['pending'] > 0
                result = 'pending'
            elsif counts['recent'] >= MAIL_PASSWORD_RESET_MAX_PER_DAY
                result = 'limit'
            else
                neo4j_query(<<~END_OF_QUERY, :mailbox => mailbox, :id => RandomTag.generate(16), :requested_by => @session_user[:email], :ts => now)
                    MATCH (m:MailPasswordResetMailbox {mailbox: $mailbox})
                    CREATE (r:MailPasswordReset {id: $id, mailbox: $mailbox, requested_by: $requested_by, ts: $ts, state: 'pending'})-[:FOR]->(m);
                END_OF_QUERY
                result = 'requested'
            end
        end
        if result == 'requested' && !mail_password_reset_bot_active?
            notify_admin_about_mail_password_reset('Dashboard: E-Mail-Passwort zurücksetzen', [
                "#{CGI.escapeHTML(@session_user[:display_name])} möchte das Passwort für #{CGI.escapeHTML(mailbox)} zurücksetzen lassen.",
                "Der Bot war in den letzten #{MAIL_PASSWORD_RESET_BOT_STALE_AFTER / 60} Minuten nicht aktiv – bitte von Hand erledigen und auf der Seite als erledigt markieren.",
            ])
        end
        respond(:result => result)
    end

    # requests the logged in user may see, newest first; the password only
    # for mailboxes whose latest request is done
    post '/api/mail_password_reset_status' do
        require_user!
        rows = neo4j_query(<<~END_OF_QUERY, :since => Time.now.to_i - MAIL_PASSWORD_RESET_SHOW_DAYS * 24 * 3600).map { |x| x['r'] }
            MATCH (r:MailPasswordReset)
            WHERE r.ts >= $since OR r.state = 'pending'
            RETURN r ORDER BY r.ts DESC;
        END_OF_QUERY
        seen = Set.new
        requests = []
        rows.each do |r|
            next unless mail_password_reset_allowed?(r[:mailbox])
            latest = !seen.include?(r[:mailbox])
            seen << r[:mailbox]
            entry = {
                :id => r[:id],
                :mailbox => r[:mailbox],
                :label => mail_password_reset_label(r[:mailbox]),
                :state => r[:state],
                :ts => r[:ts],
                :ts_done => r[:ts_done],
                :latest => latest,
            }
            entry[:password] = Main.gen_password_for_email(r[:mailbox]) if latest && r[:state] == 'done'
            if admin_logged_in?
                entry[:requested_by] = (@@user_info[r[:requested_by]] || {})[:display_name] || r[:requested_by]
                entry[:message] = r[:message]
            end
            requests << entry
        end
        result = {:requests => requests}
        result[:bot_last_seen] = mail_password_reset_bot_last_seen if admin_logged_in?
        respond(result)
    end

    post '/api/set_mail_password_reset_state' do
        require_admin!
        data = parse_request_data(:required_keys => [:id, :state], :optional_keys => [:message],
                                  :max_value_lengths => {:id => 64, :state => 16, :message => 500})
        assert(%w(done failed).include?(data[:state]))
        row = finish_mail_password_reset!(data[:id], data[:state] == 'done', data[:message] || 'von Hand', false)
        respond(:result => row ? 'ok' : 'not_pending')
    end

    # ---- interface for the bot (Authorization: Bearer <token>) ----

    def require_mail_password_reset_bot!
        token = MAIL_PASSWORD_RESET_BOT_TOKEN
        halt 404 unless token.is_a?(String) && token.size >= 32
        given = request.env['HTTP_AUTHORIZATION'].to_s.sub(/\ABearer /, '')
        halt 401 unless Rack::Utils.secure_compare(given, token)
    end

    get '/api/mail_password_reset_bot/pending' do
        require_mail_password_reset_bot!
        neo4j_query("MERGE (b:MailPasswordResetBot {key: 'bot'}) SET b.last_seen = $ts;", :ts => Time.now.to_i)
        rows = neo4j_query("MATCH (r:MailPasswordReset {state: 'pending'}) RETURN r.id AS id, r.mailbox AS mailbox ORDER BY r.ts;")
        respond(:requests => rows.map do |row|
            {:id => row['id'], :mailbox => row['mailbox'], :password => Main.gen_password_for_email(row['mailbox'])}
        end)
    end

    post '/api/mail_password_reset_bot/result' do
        require_mail_password_reset_bot!
        data = parse_request_data(:required_keys => [:id, :ok], :optional_keys => [:message],
                                  :types => {:ok => Object},
                                  :max_value_lengths => {:id => 64, :message => 500})
        assert([true, false].include?(data[:ok]))
        row = finish_mail_password_reset!(data[:id], data[:ok], data[:message], true)
        respond(:result => row ? 'ok' : 'not_pending')
    end
end
