# Neues Design (Vorschau): what the start page asks of someone, in one place
# instead of boxes in a column of their own beside the timetable.
#
# - "Zu erledigen" (preview/start.js, preview/start.css): open polls, books
#   the library needs back, deadlines of the Datentresor and the hint about
#   the Authenticator app – from the same queries as the panels of today's
#   design (start_page_panels_html in include/user.rb), as data for the page.
#   No badge on "Stundenplan" / "Heute": the list is on the page itself.
#   Every poll can be hidden there (answered or not).
# - The Datentresor hotline (admins with the role datentresor_hotline): a
#   request means someone is waiting on the phone right now, so it is a bar
#   on every page (preview/hotline.js). Releasing stays exactly as it was:
#   the dialog on the start page (timetable.html), which the bar opens there
#   and leads to from other pages (/#hotline=<email>).
#
# Today's design keeps its panels and gets none of this.
class Main < Sinatra::Base
    # how long a request waits (/api/create_ad_hoc_2fa_request sets it)
    AD_HOC_2FA_REQUEST_TTL = 10 * 60

    # everything "Zu erledigen" shows, in this order: what has an end (by
    # its end), books, the hint about the app; then polls already answered
    # and hidden ones. Each entry: :kind and what the page needs to show it.
    def start_page_todos
        return @start_page_todos if @start_page_todos
        email = @session_user[:email]
        dated = []
        tresor_deadlines_soon.each do |key, deadline|
            dated << {:kind => 'deadline', :key => key, :end => Time.parse(deadline).strftime('%Y-%m-%dT%H:%M:%S')}
        end
        polls = current_poll_entries.map do |entry|
            pr = entry[:poll_run]
            organizer = @@user_info[entry[:organizer]] || {}
            {
                :kind => 'poll', :prid => pr[:id], :title => entry[:poll_title].to_s,
                :organizer => organizer[:display_name_official] || organizer[:display_name] || '',
                :avatar => organizer[:nc_login] ? "#{NEXTCLOUD_URL}/index.php/avatar/#{organizer[:nc_login]}/128" : nil,
                :end => "#{pr[:end_date]}T#{pr[:end_time]}:00",
                :hidden => !!entry[:hidden],
            }
        end
        unless polls.empty?
            # answered: still open to change, but nothing to do any more
            answered = Set.new(neo4j_query(<<~END_OF_QUERY, :email => email, :prids => polls.map { |x| x[:prid] }).map { |x| x['prid'] })
                MATCH (u:User {email: $email})<-[:RESPONSE_BY]-(:PollResponse)-[:RESPONSE_TO]->(pr:PollRun)
                WHERE pr.id IN $prids
                RETURN DISTINCT pr.id AS prid;
            END_OF_QUERY
            polls.each { |x| x[:answered] = answered.include?(x[:prid]) }
        end
        dated += polls.reject { |x| x[:hidden] || x[:answered] }
        todos = dated.sort_by { |x| x[:end] }
        # Klassenleitungen: the new student list of their class, from its
        # release until confirmed (include/schuelerliste.rb); never breaks
        # the page
        begin
            sl = start_page_schuelerliste_todo
            todos << sl if sl
        rescue StandardError => e
            debug "start_page_schuelerliste_todo: #{e}"
        end
        books = ((@@bib_summoned_books || {})[email] || []).size
        todos << {:kind => 'books', :count => books} if books > 0
        otp = otp_nudge_kind
        todos << {:kind => 'otp', :variant => otp} if otp
        todos += polls.select { |x| x[:answered] && !x[:hidden] }
        todos += polls.select { |x| x[:hidden] }
        @start_page_todos = todos
    end

    def start_page_todo_open?(todo)
        !(todo[:hidden] || todo[:answered])
    end

    # for the start page and /api/refresh_start_page
    def start_page_todo_data
        todos = start_page_todos
        {:items => todos, :count => todos.count { |x| start_page_todo_open?(x) }}
    end

    # the badge: those who have the start page, in the new design; never
    # breaks a page (it is only a number)
    def start_page_todo_count
        return 0 unless ui_preview? && user_logged_in? && !external_user_logged_in? && !tablet_logged_in?
        start_page_todos.count { |x| start_page_todo_open?(x) }
    rescue StandardError => e
        debug "start_page_todo_count: #{e}"
        0
    end

    # timetable.html: the data and the script, only in the new design
    def start_page_todo_script
        return '' unless ui_preview? && !tablet_logged_in?
        data = start_page_todo_data
        "<script>var pv_todo_data = #{data.to_json.gsub('<', '\\u003c')};</script>\n" +
        "<script defer src='#{preview_asset('/preview/start.js')}'></script>"
    end

    # ---------- Datentresor hotline ----------

    # open requests, longest waiting first: who (the name for the bar, the
    # name and address for the dialog) and for how long. Only reads – expired
    # requests are removed where they always were (print_ad_hoc_2fa_panel,
    # /api/allow_ad_hoc_2fa_request).
    def hotline_requests
        now = Time.now.to_i
        rows = neo4j_query(<<~END_OF_QUERY, :ts => now)
            MATCH (ahr:AdHocTwoFaRequest)-[:BELONGS_TO]->(:Session)-[:BELONGS_TO]->(u:User)
            WHERE ahr.ts_expire >= $ts
            RETURN u.email AS email, MIN(ahr.ts_expire) AS ts_expire
            ORDER BY ts_expire;
        END_OF_QUERY
        rows.map do |row|
            info = @@user_info[row['email']]
            next nil unless info
            {
                :email => row['email'],
                :name => info[:display_name_official] || info[:display_name],
                :dialog_name => info[:display_name],
                :waiting => [now - (row['ts_expire'] - AD_HOC_2FA_REQUEST_TTL), 0].max,
                :expires_in => row['ts_expire'] - now,
            }
        end.compact
    end

    # the bar on every page (_template.html, after the tab bar): admins with
    # the hotline role, in the new design
    def start_page_hotline_bar_html
        return '' unless ui_preview? && user_logged_in? && admin_2fa_hotline_logged_in?
        requests = hotline_requests rescue []
        data = {:requests => requests}
        # the hash is read before the start page clears it (timetable.html)
        "<div id='pv_hotline' class='pv-hotline' role='status' aria-live='polite'#{requests.empty? ? ' hidden' : ''}></div>" +
        "<script>window.pv_hotline_hash = location.hash; window.pv_hotline_data = #{data.to_json.gsub('<', '\\u003c')};</script>" +
        "<script defer src='#{preview_asset('/preview/hotline.js')}'></script>"
    end

    # the open requests for the bar, which asks every ~20 s while the page
    # is visible
    post '/api/hotline_requests' do
        require_admin_2fa_hotline!
        parse_request_data(:max_body_length => 64)
        respond(:requests => hotline_requests)
    end
end
