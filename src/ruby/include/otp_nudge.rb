# Moving teachers from SMS codes to a code app (OTP): /otp explains how it
# works, the login page suggests it while someone waits for an SMS or when
# the SMS gateway is offline, and the start page reminds those who still
# use SMS (snoozable). Usage per person: /sms_anmeldung.

OTP_APPS = [
    {:name => 'Google Authenticator',
     :android => 'https://play.google.com/store/apps/details?id=com.google.android.apps.authenticator2',
     :ios => 'https://apps.apple.com/de/app/google-authenticator/id388497605'},
    {:name => 'Microsoft Authenticator',
     :android => 'https://play.google.com/store/apps/details?id=com.azure.authenticator',
     :ios => 'https://apps.apple.com/de/app/microsoft-authenticator/id983156458'},
    {:name => 'FreeOTP', :note => 'quelloffen, speichert nur auf dem Gerät',
     :android => 'https://play.google.com/store/apps/details?id=org.fedorahosted.freeotp',
     :ios => 'https://apps.apple.com/de/app/freeotp-authenticator/id872559395'},
    {:name => 'Aegis', :note => 'quelloffen, nur für Android',
     :android => 'https://play.google.com/store/apps/details?id=com.beemdevelopment.aegis'},
]

OTP_NUDGE_SNOOZE_DAYS = 30
OTP_STATS_CACHE_SECONDS = 600

class Main < Sinatra::Base
    # Teachers who have used the dashboard, and how many of them have a code
    # app – for "Schon 50 von 81 Lehrkräften …", shown to logged-in teachers
    # only (start page panel, /otp). Cached for a few minutes.
    @@otp_teacher_stats = nil

    def otp_teacher_stats
        if @@otp_teacher_stats.nil? || Time.now.to_i - @@otp_teacher_stats[:ts] > OTP_STATS_CACHE_SECONDS
            emails = @@user_info.select { |_, info| info[:teacher] && info[:can_log_in] != false }.keys
            row = neo4j_query_expect_one(<<~END_OF_QUERY, {:emails => emails})
                MATCH (u:User) WHERE u.email IN $emails AND u.last_access IS NOT NULL
                RETURN count(u) AS total, count(u.otp_token) AS otp;
            END_OF_QUERY
            @@otp_teacher_stats = {:ts => Time.now.to_i, :total => row['total'], :otp => row['otp']}
        end
        @@otp_teacher_stats
    end

    def otp_stats_sentence
        stats = otp_teacher_stats
        return '' if stats[:otp] < 2
        "Schon <strong>#{stats[:otp]} von #{stats[:total]} Lehrkräften</strong> melden sich mit einer Authenticator-App an."
    end

    def otp_help_contact
        if DATENTRESOR_HOTLINE.to_s.strip.empty?
            "schreib eine E-Mail an #{CGI.escapeHTML(WEBSITE_MAINTAINER_EMAIL)}"
        else
            "melde dich bei #{DATENTRESOR_HOTLINE}"
        end
    end

    # A hint for the login page (c.html), for teachers only.
    #   :waiting_sms     – the code is on its way by SMS
    #   :sms_down_first  – SMS preferred, but the gateway is offline: e-mail instead
    #   :sms_down_second – the second factor would have been an SMS, but the
    #                      gateway is offline (and there is no code app)
    def otp_nudge_html(kind)
        why = {
            :waiting_sms => "<strong>Warten auf die SMS?</strong> Mit einer Authenticator-App brauchst du keine: Der Code steht sofort in der App auf deinem Handy – auch ohne Netz.",
            :sms_down_first => "<strong>Der SMS-Versand ist gerade nicht erreichbar</strong>, deshalb kommt dein Code diesmal per E-Mail. Mit einer Authenticator-App bist du davon unabhängig: Der Code steht sofort in der App auf deinem Handy.",
            :sms_down_second => "<strong>Der SMS-Versand ist gerade nicht erreichbar</strong>, deshalb können wir dir keinen zweiten Code schicken. Bitte versuch es später noch einmal oder #{otp_help_contact}. Mit einer Authenticator-App bist du davon unabhängig: Der Code steht sofort in der App auf deinem Handy.",
        }[kind]
        StringIO.open do |io|
            io.puts "<div class='otp-nudge' data-kind='#{kind}'>"
            io.puts "<div class='otp-nudge-icon'><i class='fa fa-qrcode'></i></div>"
            io.puts "<div>"
            # no usage numbers here: the login page is shown before anyone is logged in
            io.puts "<p>#{why}</p>"
            io.puts "<a href='/otp' target='_blank' class='btn btn-sm btn-outline-secondary'>So funktioniert die Authenticator-App&nbsp;<i class='fa fa-angle-double-right'></i></a>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    # the hint shown on c.html right away (or after a moment, while waiting
    # for an SMS); '' for everyone but teachers
    def otp_login_hint(email, method, sms_fallback)
        return '' unless (@@user_info[email] || {})[:teacher]
        if method == 'sms'
            otp_nudge_html(:waiting_sms)
        elsif method == 'email' && sms_fallback
            otp_nudge_html(:sms_down_first)
        else
            ''
        end
    end

    # Start page: teachers who still get codes by SMS.
    def print_otp_nudge_panel
        return '' unless teacher_logged_in?
        row = neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            RETURN u.otp_token IS NOT NULL AS otp,
                   COALESCE(size(u.telephone_number), 0) > 0 AS phone,
                   COALESCE(u.preferred_login_method, 'email') AS preferred,
                   COALESCE(u.otp_nudge_snoozed_until, 0) AS snoozed_until;
        END_OF_QUERY
        return '' if row['snoozed_until'] > Time.now.to_i
        if row['otp'] && row['preferred'] == 'sms'
            kind = 'switch'
            title = 'Deine Authenticator-App kann mehr'
            text = "Du hast schon eine Authenticator-App eingerichtet, bekommst deinen ersten Anmeldecode aber per SMS. Wenn du »Code per E-Mail« als Standard wählst, kommt der zweite Code aus deiner App – ganz ohne SMS."
            buttons = "<button class='btn btn-sm btn-success bu-otp-nudge-switch'><i class='fa fa-check'></i>&nbsp;&nbsp;Umstellen</button>"
        elsif !row['otp'] && row['phone']
            kind = 'setup'
            title = 'Anmelden ohne SMS'
            text = "Mit einer Authenticator-App steht dein Anmeldecode sofort auf dem Handy – auch ohne Netz und wenn der SMS-Versand ausfällt. #{otp_stats_sentence}"
            buttons = "<a href='/profil#anmeldung' class='btn btn-sm btn-success'><i class='fa fa-qrcode'></i>&nbsp;&nbsp;Einrichten</a>" +
                      "<a href='/otp' class='btn btn-sm btn-outline-secondary'>So funktioniert's</a>"
        else
            return ''
        end
        StringIO.open do |io|
            io.puts "<div class='col-lg-12 col-md-4 col-sm-6'>"
            io.puts "<div class='hint otp-nudge-panel' data-kind='#{kind}'>"
            io.puts "<div class='otp-nudge-panel-title'><i class='fa fa-qrcode'></i>&nbsp;&nbsp;#{title}</div>"
            io.puts "<p>#{text}</p>"
            io.puts "<div class='otp-nudge-panel-buttons'>#{buttons}<button class='btn btn-sm btn-link bu-otp-nudge-snooze'>Später</button></div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end

    post '/api/snooze_otp_nudge' do
        require_teacher!
        neo4j_query_expect_one(<<~END_OF_QUERY, {:email => @session_user[:email], :until => Time.now.to_i + OTP_NUDGE_SNOOZE_DAYS * 24 * 60 * 60})
            MATCH (u:User {email: $email})
            SET u.otp_nudge_snoozed_until = $until
            RETURN u.email;
        END_OF_QUERY
        respond(:ok => true)
    end

    # the apps on /otp, with store links and (on larger screens) QR codes
    def print_otp_apps
        qr = lambda do |url|
            RQRCode::QRCode.new(url).as_svg(offset: 0, color: '000', shape_rendering: 'crispEdges',
                                            module_size: 3, standalone: true).gsub("\n", '')
        end
        StringIO.open do |io|
            io.puts "<div class='otp-apps'>"
            OTP_APPS.each do |app|
                io.puts "<div class='otp-app'>"
                io.puts "<div class='otp-app-name'>#{CGI.escapeHTML(app[:name])}</div>"
                io.puts "<div class='otp-app-note text-muted'>#{CGI.escapeHTML(app[:note] || 'kostenlos, für Android und iPhone')}</div>"
                io.puts "<div class='otp-app-stores'>"
                [[:android, 'Android'], [:ios, 'iPhone']].each do |key, label|
                    next unless app[key]
                    io.puts "<a class='otp-app-store' href='#{CGI.escapeHTML(app[key])}' target='_blank' rel='noopener'>"
                    io.puts "<span class='otp-app-qr' aria-hidden='true'>#{qr.call(app[key])}</span>"
                    io.puts "<span class='btn btn-sm btn-outline-secondary'><i class='fa fa-#{key == :android ? 'android' : 'apple'}'></i>&nbsp;&nbsp;#{label}</span>"
                    io.puts "</a>"
                end
                io.puts "</div>"
                io.puts "</div>"
            end
            io.puts "</div>"
            io.string
        end
    end
end
