# Creating missing school mailboxes with the Postfach-Bot
# (src/mail-account-bot, plan in review/2026-11/mail-password-reset.md).
#
# Which mailboxes exist comes from the mail provider's address list (the
# export), which the bot uploads; until the first upload the file
# /data/current-email-addresses.csv is used. Missing are only mailboxes of
# students – their own address on SCHUL_MAIL_DOMAIN and the parents'
# eltern.<address> – nothing else (teachers' and all other accounts are never
# touched). The admin approves them on /postfaecher; the bot creates them with
# the password of the E-Mail-Brief and reports back.
#
#   (:IonosAddressList {key: 'current', ts, addresses, types, wanted_ts})
#   (:MailAccountCreateCase {id, mailbox, state, ts, decided_by, ts_done, message})
#       state: 'approved' -> 'done' | 'exists' | 'failed'; 'failed' -> 'approved' (retry)
#              | 'cancelled'

class Main < Sinatra::Base
    MAIL_ADDRESS_LIST_MAX = 20000
    MAIL_ADDRESS_LIST_MIN = 100
    MAIL_ADDRESS_LIST_STALE_AFTER = 7 * 24 * 3600
    MAIL_ACCOUNT_CREATE_MAX = 600
    MAIL_ACCOUNT_CREATE_SHOW_DAYS = 30
    MAIL_ADDRESS_RE = /\A[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}\z/

    # {:ts, :addresses (Set), :source => 'ionos' | 'file'}
    def mail_address_list
        row = neo4j_query("MATCH (l:IonosAddressList {key: 'current'}) RETURN l.ts AS ts, l.addresses AS addresses, l.wanted_ts AS wanted_ts;").first
        if row && row['addresses']
            {:ts => row['ts'], :addresses => Set.new(row['addresses']), :source => 'ionos', :wanted_ts => row['wanted_ts']}
        else
            {:ts => nil, :addresses => Set.new(@@current_email_addresses.map { |x| x.to_s.downcase }), :source => 'file',
             :wanted_ts => row ? row['wanted_ts'] : nil}
        end
    end

    # the dashboard's students on the school mail domain, in class order
    def mail_account_students
        result = []
        @@klassen_order.each do |klasse|
            (@@schueler_for_klasse[klasse] || []).each do |email|
                next unless email.end_with?("@#{SCHUL_MAIL_DOMAIN}")
                next unless user_has_role(email, :schueler)
                result << email
            end
        end
        result
    end

    # the mailbox belongs to a student of the dashboard: own or eltern.<own>
    def mail_account_kind(mailbox)
        student = mailbox.sub(/\Aeltern\./, '')
        return nil unless student.end_with?("@#{SCHUL_MAIL_DOMAIN}") && @@user_info[student] && user_has_role(student, :schueler)
        mailbox == student ? 'student' : 'parents'
    end

    # being created, or created / found existing since the list was fetched
    def mail_account_active_creations
        Set.new(neo4j_query("MATCH (c:MailAccountCreateCase) WHERE c.state IN ['approved', 'failed', 'done', 'exists'] RETURN c.mailbox AS mailbox;").map { |x| x['mailbox'] })
    end

    # missing student / parents mailboxes, without the ones being created
    def missing_mail_accounts(list = mail_address_list)
        active = mail_account_active_creations
        missing = []
        mail_account_students.each do |email|
            [email, "eltern.#{email}"].each do |mailbox|
                next if list[:addresses].include?(mailbox) || active.include?(mailbox)
                missing << mailbox
            end
        end
        missing
    end

    def mail_account_wake_bot_for_creation
        self.class.wake_mail_account_bot
    end

    # ---- the admin's side (/postfaecher) ----

    post '/api/mail_account_creation_status' do
        require_admin!
        list = mail_address_list
        missing = missing_mail_accounts(list).map do |mailbox|
            student = mailbox.sub(/\Aeltern\./, '')
            info = @@user_info[student] || {}
            {:mailbox => mailbox, :kind => mail_account_kind(mailbox), :name => info[:display_name], :klasse => tr_klasse(info[:klasse])}
        end
        cases = neo4j_query(<<~END_OF_QUERY, :since => Time.now.to_f - MAIL_ACCOUNT_CREATE_SHOW_DAYS * 24 * 3600).map { |x| x['c'] }
            MATCH (c:MailAccountCreateCase)
            WHERE c.ts >= $since OR c.state IN ['approved', 'failed']
            RETURN c ORDER BY c.ts DESC;
        END_OF_QUERY
        respond(:list => {:ts => list[:ts], :source => list[:source], :count => list[:addresses].size, :wanted_ts => list[:wanted_ts]},
                :missing => missing,
                :cases => cases.map { |c| {:id => c[:id], :mailbox => c[:mailbox], :state => c[:state], :ts => c[:ts], :ts_done => c[:ts_done], :message => c[:message]} })
    end

    # the bot fetches the address list from the mail provider next time
    post '/api/request_ionos_address_list' do
        require_admin!
        neo4j_query("MERGE (l:IonosAddressList {key: 'current'}) SET l.wanted_ts = $ts;", :ts => Time.now.to_i)
        mail_account_wake_bot_for_creation
        respond(:result => 'ok')
    end

    post '/api/approve_mail_account_creation' do
        require_admin!
        data = parse_request_data(:required_keys => [:mailboxes], :types => {:mailboxes => Array}, :max_body_length => 128 * 1024)
        mailboxes = data[:mailboxes].map { |x| x.to_s.strip.downcase }.uniq
        assert(!mailboxes.empty? && mailboxes.size <= MAIL_ACCOUNT_CREATE_MAX, 'invalid mailboxes')
        # only what is missing right now – and only student / parents mailboxes
        missing = Set.new(missing_mail_accounts)
        mailboxes.each do |mailbox|
            assert(missing.include?(mailbox) && mail_account_kind(mailbox), 'not a missing student mailbox')
        end
        ts = Time.now.to_f
        mailboxes.each_with_index do |mailbox, i|
            neo4j_query(<<~END_OF_QUERY, :id => RandomTag.generate(16), :mailbox => mailbox, :ts => ts + i * 0.001, :by => @session_user[:email])
                CREATE (:MailAccountCreateCase {id: $id, mailbox: $mailbox, state: 'approved', ts: $ts, decided_by: $by});
            END_OF_QUERY
        end
        mail_account_wake_bot_for_creation
        respond(:result => 'ok', :count => mailboxes.size)
    end

    # failed -> approved (retry) | cancelled
    post '/api/update_mail_account_creation' do
        require_admin!
        data = parse_request_data(:required_keys => [:id, :action], :max_value_lengths => {:id => 64, :action => 16})
        to = {'retry' => 'approved', 'cancel' => 'cancelled'}[data[:action]]
        assert(to, 'unknown action')
        row = neo4j_query(<<~END_OF_QUERY, :id => data[:id], :to => to, :ts => Time.now.to_f, :by => @session_user[:email]).first
            MATCH (c:MailAccountCreateCase {id: $id, state: 'failed'})
            SET c.state = $to, c.ts_updated = $ts
            // a retry is a new approval: the bot checks who gave it
            FOREACH (_ IN CASE WHEN $to = 'approved' THEN [1] ELSE [] END | SET c.decided_by = $by, c.ts_decided = $ts)
            RETURN c.id AS id;
        END_OF_QUERY
        mail_account_wake_bot_for_creation if row && to == 'approved'
        respond(:result => row ? 'ok' : 'wrong_state')
    end

    # ---- the bot's side (Authorization: Bearer <token>) ----

    # what to create, and whether the address list is wanted
    def mail_account_bot_creation_work
        rows = neo4j_query("MATCH (c:MailAccountCreateCase {state: 'approved'}) RETURN c.id AS id, c.mailbox AS mailbox, c.decided_by AS decided_by, COALESCE(c.ts_decided, c.ts) AS ts_decided ORDER BY c.ts;")
        list = mail_address_list
        wanted = !rows.empty? || list[:ts].nil? || (list[:wanted_ts] && (list[:ts].nil? || list[:wanted_ts] > list[:ts])) ||
                 Time.now.to_i - list[:ts].to_i > MAIL_ADDRESS_LIST_STALE_AFTER
        {
            :create => rows.map do |row|
                {:id => row['id'], :mailbox => row['mailbox'], :kind => mail_account_kind(row['mailbox']),
                 :approved_by => row['decided_by'], :approved_at => row['ts_decided'],
                 :password => Main.gen_password_for_email(row['mailbox'])}
            end,
            :address_list => {:ts => list[:ts], :wanted => !!wanted},
        }
    end

    get '/api/mail_account_bot/creation' do
        require_mail_account_bot!
        if mail_account_bot_state[:paused_ts]
            respond(:create => [], :address_list => {:wanted => false}, :paused => true)
        else
            respond(mail_account_bot_creation_work.merge(:paused => false))
        end
    end

    # the export from the mail provider: replaces the stored list
    post '/api/mail_account_bot/address_list' do
        require_mail_account_bot!
        data = parse_request_data(:required_keys => [:addresses, :types], :types => {:addresses => Array, :types => Array},
                                  :max_body_length => 4 * 1024 * 1024)
        addresses = data[:addresses].map { |x| x.to_s.strip.downcase }
        types = data[:types].map { |x| x.to_s[0, 40] }
        assert(addresses.size == types.size, 'lengths differ')
        assert(addresses.size >= MAIL_ADDRESS_LIST_MIN && addresses.size <= MAIL_ADDRESS_LIST_MAX, 'implausible size')
        # catch-all entries like *@verteiler… are kept as they are
        assert(addresses.all? { |x| x =~ MAIL_ADDRESS_RE || x =~ /\A\*@[a-z0-9.-]+\z/ }, 'invalid address')
        neo4j_query(<<~END_OF_QUERY, :ts => Time.now.to_i, :addresses => addresses, :types => types)
            MERGE (l:IonosAddressList {key: 'current'})
            SET l.ts = $ts, l.addresses = $addresses, l.types = $types;
        END_OF_QUERY
        # creations that the list shows as existing are done
        existing = Set.new(addresses)
        neo4j_query("MATCH (c:MailAccountCreateCase {state: 'approved'}) RETURN c.id AS id, c.mailbox AS mailbox;").each do |row|
            next unless existing.include?(row['mailbox'])
            neo4j_query("MATCH (c:MailAccountCreateCase {id: $id, state: 'approved'}) SET c.state = 'exists', c.ts_done = $ts, c.message = 'Gibt es laut Adressliste schon';",
                        :id => row['id'], :ts => Time.now.to_f)
        end
        respond(:result => 'ok', :count => addresses.size)
    end

    post '/api/mail_account_bot/create_result' do
        require_mail_account_bot!
        data = parse_request_data(:required_keys => [:id, :ok], :optional_keys => [:message], :types => {:ok => Object},
                                  :max_value_lengths => {:id => 64, :message => 500}, :max_body_length => 4096)
        assert([true, false].include?(data[:ok]))
        row = neo4j_query(<<~END_OF_QUERY, :id => data[:id], :state => data[:ok] ? 'done' : 'failed', :ts => Time.now.to_f, :message => data[:message]).first
            MATCH (c:MailAccountCreateCase {id: $id, state: 'approved'})
            SET c.state = $state, c.ts_done = $ts, c.message = $message
            RETURN c.mailbox AS mailbox;
        END_OF_QUERY
        if row && data[:ok]
            # it exists now: into the stored list until the next export
            neo4j_query(<<~END_OF_QUERY, :mailbox => row['mailbox'])
                MATCH (l:IonosAddressList {key: 'current'})
                WHERE l.addresses IS NOT NULL AND NOT $mailbox IN l.addresses
                SET l.addresses = l.addresses + [$mailbox], l.types = l.types + ['Mail Basic'];
            END_OF_QUERY
        end
        if row && !data[:ok]
            notify_admin_about_mail_password_reset('Dashboard: Postfach konnte nicht angelegt werden', [
                "Das Postfach #{CGI.escapeHTML(row['mailbox'])} konnte nicht angelegt werden.",
                "Meldung: #{CGI.escapeHTML(data[:message].to_s)}",
            ])
        end
        respond(:result => row ? 'ok' : 'not_approved')
    end
end
