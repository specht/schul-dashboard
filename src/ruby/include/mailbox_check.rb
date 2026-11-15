# Checking one school mailbox (a student's own or the parents' eltern.…) on
# /postfaecher, when somebody writes that no mail arrives:
#
#   1. the mail provider's address list (mail_account_creation.rb): is there a
#      mailbox, only a forwarding, or nothing?
#   2. an IMAP login with the original password from the E-Mail-Brief; if it
#      works, an overview without content: per folder the number of mails,
#      the arrival time of the newest one and how many came in the last 30
#      days, plus how full the mailbox is. Never subjects, senders or
#      contents (decided 2026-11-15). Read-only: EXAMINE, never SELECT.
#   3. an assessment and a reply draft for the person who asked (the admin
#      may attach the E-Mail-Brief).
#
# Admins only. Every check is logged – who checked which mailbox when, whether
# the login worked and whether / to whom a reply went, not what was found.
# Only admins see the log (on /postfaecher); it is deleted after
# MAILBOX_CHECK_KEEP_DAYS days.
#   (:MailboxCheck {id, ts, mailbox, checked_by, login, ts_reply, reply_sent_to, reply_letter})

class Main < Sinatra::Base
    MAILBOX_CHECK_FOLDER_MAX = 60
    MAILBOX_CHECK_RECENT_DAYS = 30
    MAILBOX_CHECK_TIMEOUT = 30
    MAILBOX_CHECK_QUOTA_WARN = 0.9
    MAILBOX_CHECK_KEEP_DAYS = 90
    MAILBOX_CHECK_LOG_SHOW = 200

    def mailbox_check_cleanup
        neo4j_query("MATCH (c:MailboxCheck) WHERE c.ts < $ts DETACH DELETE c;", :ts => Time.now.to_f - MAILBOX_CHECK_KEEP_DAYS * 24 * 3600)
    end

    # the provider's IMAP server; the test stack points it to its stand-in
    def mailbox_check_imap_config
        defined?(MAILBOX_CHECK_IMAP) ? MAILBOX_CHECK_IMAP : {:host => SCHUL_MAIL_LOGIN_IMAP_HOST, :port => 993, :ssl => true}
    end

    # what the address list says about the mailbox
    def mailbox_check_address_list(mailbox)
        row = neo4j_query("MATCH (l:IonosAddressList {key: 'current'}) RETURN l.ts AS ts, l.addresses AS addresses, l.types AS types;").first
        if row && row['addresses']
            index = row['addresses'].index(mailbox)
            type = index ? (row['types'] || [])[index].to_s : nil
            kind = if index.nil?
                'missing'
            elsif type =~ /weiterleit|forward/i
                'forward'
            else
                'mailbox'
            end
            {:source => 'ionos', :ts => row['ts'], :kind => kind, :type => type}
        else
            present = @@current_email_addresses.any? { |x| x.to_s.downcase == mailbox }
            {:source => 'file', :ts => nil, :kind => present ? 'mailbox' : 'missing', :type => nil}
        end
    end

    # {:login => 'ok' | 'refused' | 'error', :error, :folders, :quota}
    def mailbox_check_imap(mailbox)
        config = mailbox_check_imap_config
        result = {:login => 'error'}
        imap = nil
        begin
            Timeout.timeout(MAILBOX_CHECK_TIMEOUT) do
                imap = Net::IMAP.new(config[:host], :port => config[:port], :ssl => config[:ssl] ? {:verify_mode => OpenSSL::SSL::VERIFY_PEER} : false,
                                     :open_timeout => 10)
                begin
                    imap.login(mailbox, Main.gen_password_for_email(mailbox))
                rescue Net::IMAP::NoResponseError
                    result[:login] = 'refused'
                    next
                end
                result[:login] = 'ok'
                since = Date.today - MAILBOX_CHECK_RECENT_DAYS
                folders = []
                (imap.list('', '*') || []).each do |entry|
                    break if folders.size >= MAILBOX_CHECK_FOLDER_MAX
                    next if entry.attr.include?(:Noselect)
                    folder = {:name => Net::IMAP.decode_utf7(entry.name), :messages => 0, :recent => 0, :newest => nil}
                    folder[:messages] = imap.status(entry.name, ['MESSAGES'])['MESSAGES'].to_i
                    if folder[:messages] > 0
                        imap.examine(entry.name)
                        newest = imap.fetch('*', 'INTERNALDATE')
                        if newest && newest.first
                            date = newest.first.attr['INTERNALDATE']
                            folder[:newest] = (date.is_a?(Time) ? date : Time.parse(date.to_s)).to_i
                        end
                        folder[:recent] = imap.search(['SINCE', since]).size
                    end
                    folders << folder
                end
                # INBOX first, then by name
                result[:folders] = folders.sort_by { |f| [f[:name].upcase == 'INBOX' ? 0 : 1, f[:name].downcase] }
                if imap.capability.include?('QUOTA')
                    begin
                        quota = imap.getquotaroot('INBOX').find { |x| x.is_a?(Net::IMAP::MailboxQuota) }
                        result[:quota] = {:used_kb => quota.usage.to_i, :limit_kb => quota.quota.to_i} if quota && quota.quota.to_i > 0
                    rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
                    end
                end
            end
        rescue Timeout::Error
            result[:error] = 'Zeitüberschreitung'
        rescue StandardError => e
            result[:error] = e.class.name.split('::').last
        ensure
            begin
                imap.logout if imap && !imap.disconnected?
            rescue StandardError
            end
            imap.disconnect if imap && !imap.disconnected? rescue nil
        end
        result
    end

    def mailbox_check_date(ts)
        ts ? Time.at(ts).strftime('%d.%m.%Y') : nil
    end

    # [{:level => 'ok' | 'warn' | 'problem' | 'info', :key, :text}] for the admin
    def mailbox_check_assessment(list, imap)
        items = []
        case list[:kind]
        when 'forward'
            items << {:level => 'problem', :key => 'forward', :text => "Laut Adressliste gibt es für diese Adresse kein Postfach, nur eine Weiterleitung (#{list[:type]}). E-Mails landen dort, wohin sie weitergeleitet werden."}
        when 'missing'
            items << {:level => 'problem', :key => 'missing', :text => 'Laut Adressliste gibt es für diese Adresse kein Postfach. Es kann unten bei „Fehlende Postfächer“ angelegt werden.'}
        end
        if list[:source] == 'ionos' && list[:ts] && Time.now.to_i - list[:ts] > MAIL_ADDRESS_LIST_STALE_AFTER
            items << {:level => 'info', :key => 'list_stale', :text => "Die Adressliste ist vom #{mailbox_check_date(list[:ts])} – sie kann unten neu angefordert werden."}
        end
        case imap[:login]
        when 'refused'
            items << {:level => 'info', :key => 'password_changed', :text => 'Das ursprüngliche Passwort aus dem E-Mail-Brief funktioniert nicht mehr: Es wurde geändert (oder das Postfach gibt es nicht). Ohne das aktuelle Passwort kann das Dashboard nicht hineinsehen. Weiterleitungen und Filterregeln kann nur die Person selbst im Webmail prüfen – oder das Passwort wird zurückgesetzt.'}
        when 'error'
            items << {:level => 'warn', :key => 'imap_error', :text => "Der Mail-Server war nicht erreichbar (#{imap[:error]}). Bitte später noch einmal prüfen."}
        when 'ok'
            folders = imap[:folders] || []
            inbox = folders.find { |f| f[:name].upcase == 'INBOX' }
            others = folders.reject { |f| f.equal?(inbox) || f[:recent] == 0 || f[:name] =~ /trash|papierkorb|gel[öo]scht|deleted|sent|gesendet|draft|entw[üu]rf/i }
            newest = folders.map { |f| f[:newest] }.compact.max
            if inbox && inbox[:recent] > 0
                items << {:level => 'ok', :key => 'mail_arrives', :text => "E-Mails kommen an: #{inbox[:recent]} im Posteingang in den letzten #{MAILBOX_CHECK_RECENT_DAYS} Tagen, die neueste am #{mailbox_check_date(inbox[:newest])}. Wahrscheinlich ruft das E-Mail-Programm sie nicht mehr ab – z. B. Gmail mit „E-Mails von anderen Konten abrufen“ (POP3), das Google einstellt. Abhilfe: per IMAP einrichten oder im Webmail lesen."}
            elsif !others.empty?
                items << {:level => 'warn', :key => 'filter', :text => "Neue E-Mails landen nicht im Posteingang, sondern in #{others.map { |f| "„#{f[:name]}“" }.join(', ')} – vermutlich durch eine Filterregel."}
            else
                items << {:level => 'warn', :key => 'nothing_new', :text => "In den letzten #{MAILBOX_CHECK_RECENT_DAYS} Tagen ist keine neue E-Mail angekommen#{newest ? " (die neueste ist vom #{mailbox_check_date(newest)})" : ''}. Mögliche Ursachen: eine Weiterleitung ohne Kopie oder eine Filterregel im Webmail, oder ein Programm ruft per POP3 ab und löscht dabei auf dem Server."}
            end
            if imap[:quota] && imap[:quota][:used_kb] >= MAILBOX_CHECK_QUOTA_WARN * imap[:quota][:limit_kb]
                items << {:level => 'problem', :key => 'full', :text => "Das Postfach ist fast voll (#{(100.0 * imap[:quota][:used_kb] / imap[:quota][:limit_kb]).round} %). Neue E-Mails werden abgewiesen, sobald es voll ist."}
            end
        end
        items
    end

    # the reply to the person who asked, in their words: students "du",
    # parents "Sie"
    def mailbox_check_reply_draft(mailbox, list, imap, keys)
        student = mailbox.sub(/\Aeltern\./, '')
        parents = mailbox != student
        info = @@user_info[student]
        sender = [@session_user[:first_name], @session_user[:last_name]].map(&:to_s).reject(&:empty?).join(' ')
        help = "#{WEB_ROOT}/hilfe#email-programm"
        webmail = SCHUL_MAIL_LOGIN_URL
        du = !parents
        t = lambda { |du_text, sie_text| du ? du_text : sie_text }
        lines = []
        lines << (du ? "Hallo #{info[:first_name]}," : 'Sehr geehrte Frau / Herr …,')
        lines << ''
        lines << t.call("danke für deine Nachricht. Ich habe dein schulisches Postfach #{mailbox} mit einem automatisierten Verfahren geprüft. Dabei wurde keine E-Mail geöffnet – weder Inhalte noch Betreffzeilen oder Absender, nur die Anzahl der E-Mails und ihr Eingangsdatum.",
                        "vielen Dank für Ihre Nachricht. Ich habe das Eltern-Postfach #{mailbox} mit einem automatisierten Verfahren geprüft. Dabei wurde keine E-Mail geöffnet – weder Inhalte noch Betreffzeilen oder Absender, nur die Anzahl der E-Mails und ihr Eingangsdatum.")
        lines << ''
        if keys.include?('forward')
            lines << t.call('Für deine Adresse ist bei unserem Mail-Anbieter kein Postfach eingerichtet, sondern nur eine Weiterleitung. Ich kümmere mich darum und melde mich wieder.',
                            'Für diese Adresse ist bei unserem Mail-Anbieter kein Postfach eingerichtet, sondern nur eine Weiterleitung. Ich kümmere mich darum und melde mich wieder.')
            lines << ''
        elsif keys.include?('missing')
            lines << t.call('Für deine Adresse gibt es bei unserem Mail-Anbieter zurzeit kein Postfach. Ich lasse es anlegen und melde mich wieder.',
                            'Für diese Adresse gibt es bei unserem Mail-Anbieter zurzeit kein Postfach. Ich lasse es anlegen und melde mich wieder.')
            lines << ''
        end
        if keys.include?('mail_arrives')
            inbox = (imap[:folders] || []).find { |f| f[:name].upcase == 'INBOX' }
            lines << t.call("In deinem Postfach kommen E-Mails an, zuletzt am #{mailbox_check_date(inbox[:newest])}. Sie werden aber offenbar nicht mehr von deinem E-Mail-Programm abgerufen.",
                            "Im Postfach kommen E-Mails an, zuletzt am #{mailbox_check_date(inbox[:newest])}. Sie werden aber offenbar nicht mehr von Ihrem E-Mail-Programm abgerufen.")
            lines << ''
            lines << t.call('Falls du deine Schul-E-Mails bisher in Gmail über „E-Mails von anderen Konten abrufen“ (POP3) bekommen hast: Diese Funktion stellt Google gerade ein. Richte das Postfach stattdessen per IMAP ein, zum Beispiel in der Gmail-App, oder lies deine E-Mails im Webmail:',
                            'Falls Sie die E-Mails bisher in Gmail über „E-Mails von anderen Konten abrufen“ (POP3) bekommen haben: Diese Funktion stellt Google gerade ein. Richten Sie das Postfach stattdessen per IMAP ein, zum Beispiel in der Gmail-App, oder lesen Sie die E-Mails im Webmail:')
            lines << webmail
            lines << ''
        end
        if keys.include?('filter')
            lines << t.call('Neue E-Mails landen bei dir nicht im Posteingang, sondern in einem anderen Ordner – vermutlich durch eine Filterregel. Bitte melde dich im Webmail an und prüfe unter „Einstellungen“ die Filterregeln:',
                            'Neue E-Mails landen nicht im Posteingang, sondern in einem anderen Ordner – vermutlich durch eine Filterregel. Bitte melden Sie sich im Webmail an und prüfen Sie unter „Einstellungen“ die Filterregeln:')
            lines << webmail
            lines << ''
        end
        if keys.include?('nothing_new') || keys.include?('password_changed')
            if keys.include?('password_changed')
                lines << t.call('Da du das Passwort geändert hast, kann ich nicht in dein Postfach hineinsehen.',
                                'Da das Passwort geändert wurde, kann ich nicht in das Postfach hineinsehen.')
            else
                lines << t.call('Seit einiger Zeit sind in deinem Postfach keine neuen E-Mails mehr angekommen.',
                                'Seit einiger Zeit sind im Postfach keine neuen E-Mails mehr angekommen.')
            end
            lines << t.call('Häufige Ursachen sind eine Weiterleitung, die keine Kopie behält, eine Filterregel, oder ein Programm, das die E-Mails per POP3 abruft und dabei vom Server löscht. Bitte melde dich im Webmail an und prüfe unter „Einstellungen“ die Weiterleitungen und Filterregeln:',
                            'Häufige Ursachen sind eine Weiterleitung, die keine Kopie behält, eine Filterregel, oder ein Programm, das die E-Mails per POP3 abruft und dabei vom Server löscht. Bitte melden Sie sich im Webmail an und prüfen Sie unter „Einstellungen“ die Weiterleitungen und Filterregeln:')
            lines << webmail
            lines << ''
            if keys.include?('password_changed')
                lines << t.call('Falls du dein Passwort nicht mehr weißt, kann ich es auf das ursprüngliche Passwort aus deinem E-Mail-Brief zurücksetzen – sag mir einfach Bescheid.',
                                'Falls Sie das Passwort nicht mehr wissen, kann ich es auf das ursprüngliche Passwort aus dem E-Mail-Brief zurücksetzen – geben Sie mir einfach Bescheid.')
                lines << ''
            end
        end
        if keys.include?('full')
            lines << t.call('Außerdem ist dein Postfach fast voll. Wenn es voll ist, werden neue E-Mails abgewiesen. Bitte lösche alte E-Mails (vor allem solche mit großen Anhängen) und leere den Papierkorb.',
                            'Außerdem ist das Postfach fast voll. Wenn es voll ist, werden neue E-Mails abgewiesen. Bitte löschen Sie alte E-Mails (vor allem solche mit großen Anhängen) und leeren Sie den Papierkorb.')
            lines << ''
        end
        lines << t.call('Wie du dein E-Mail-Programm oder die Gmail-App einrichtest (IMAP und SMTP), steht hier:',
                        'Wie Sie ein E-Mail-Programm oder die Gmail-App einrichten (IMAP und SMTP), steht hier:')
        lines << help
        lines << ''
        lines << 'Viele Grüße'
        lines << sender
        {
            :subject => du ? 'Dein schulisches E-Mail-Postfach' : 'Ihr schulisches E-Mail-Postfach',
            :body => lines.join("\n") + "\n",
            :attachment => "E-Mail-Brief (#{info[:display_name]})",
        }
    end

    post '/api/check_mailbox' do
        require_admin!
        data = parse_request_data(:required_keys => [:mailbox], :max_value_lengths => {:mailbox => 256})
        mailbox = data[:mailbox].strip.downcase
        # only students' and parents' mailboxes, never anything else
        assert(['student', 'parents'].include?(mail_account_kind(mailbox)), 'not a student or parents mailbox')
        mailbox_check_cleanup
        list = mailbox_check_address_list(mailbox)
        imap = mailbox_check_imap(mailbox)
        assessment = mailbox_check_assessment(list, imap)
        id = RandomTag.generate(12)
        neo4j_query(<<~END_OF_QUERY, :id => id, :ts => Time.now.to_f, :mailbox => mailbox, :by => @session_user[:email], :login => imap[:login])
            CREATE (:MailboxCheck {id: $id, ts: $ts, mailbox: $mailbox, checked_by: $by, login: $login});
        END_OF_QUERY
        respond(
            :id => id,
            :mailbox => mailbox,
            :label => mail_password_reset_label(mailbox),
            :list => list.merge(:date => mailbox_check_date(list[:ts])),
            :imap => imap.merge(:folders => (imap[:folders] || []).map { |f| f.merge(:newest_date => mailbox_check_date(f[:newest])) }),
            :assessment => assessment,
            :draft => mailbox_check_reply_draft(mailbox, list, imap, assessment.map { |x| x[:key] }),
        )
    end

    # the log for the admins: who checked which mailbox when, nothing found
    post '/api/mailbox_check_log' do
        require_admin!
        mailbox_check_cleanup
        rows = neo4j_query("MATCH (c:MailboxCheck) RETURN c ORDER BY c.ts DESC LIMIT $limit;", :limit => MAILBOX_CHECK_LOG_SHOW).map { |x| x['c'] }
        entries = rows.map do |c|
            {
                :ts => c[:ts],
                :mailbox => c[:mailbox],
                :label => mail_password_reset_label(c[:mailbox]),
                :checked_by => (@@user_info[c[:checked_by]] || {})[:display_name] || c[:checked_by],
                :login => c[:login],
                :ts_reply => c[:ts_reply],
                :reply_sent_to => c[:reply_sent_to],
                :reply_letter => c[:reply_letter] == true,
            }
        end
        respond(:entries => entries, :keep_days => MAILBOX_CHECK_KEEP_DAYS)
    end

    post '/api/send_mailbox_check_reply' do
        require_admin!
        data = parse_request_data(:required_keys => [:id, :to, :subject, :body, :attach_letter], :optional_keys => [:cc, :bcc],
                                  :types => {:attach_letter => Object},
                                  :max_value_lengths => {:id => 64, :to => 256, :subject => 200, :body => 10000, :cc => 1500, :bcc => 1500},
                                  :max_body_length => 32 * 1024)
        assert([true, false].include?(data[:attach_letter]))
        check = neo4j_query("MATCH (c:MailboxCheck {id: $id}) RETURN c;", :id => data[:id]).map { |x| x['c'] }.first
        assert(check, 'no such check')
        recipient = data[:to].strip
        assert(recipient =~ MAIL_REPLY_ADDRESS_RE, 'invalid recipient')
        cc_list = mail_reply_addresses(data[:cc])
        extra_bcc = mail_reply_addresses(data[:bcc])
        if cc_list.nil? || extra_bcc.nil?
            respond(:error => 'invalid_copy_address')
        else
            admin_email = @session_user[:email]
            bcc_list = ([admin_email] + extra_bcc).uniq
            letter = nil
            if data[:attach_letter]
                student = check[:mailbox].sub(/\Aeltern\./, '')
                letter = [Main.print_email_letters([student]), "E-Mail-Brief #{@@user_info[student][:display_name]}.pdf"]
            end
            subject_text = data[:subject].strip
            deliver_mail(data[:body]) do
                to recipient
                cc cc_list unless cc_list.empty?
                from SMTP_FROM
                reply_to admin_email
                bcc bcc_list
                subject subject_text
                add_file :content_type => 'application/pdf', :content => letter[0], :filename => letter[1] if letter
            end
            neo4j_query(<<~END_OF_QUERY, :id => check[:id], :ts => Time.now.to_f, :to => recipient, :letter => !letter.nil?)
                MATCH (c:MailboxCheck {id: $id})
                SET c.ts_reply = $ts, c.reply_sent_to = $to, c.reply_letter = $letter;
            END_OF_QUERY
            respond(:result => 'sent')
        end
    end
end
