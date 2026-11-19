# Profile: an external calendar (iCal feed) in one's own timetable – for
# people with the role :can_import_ical, in the new design only (for now).
# The fetching and parsing is in ical_import.rb, done by the timetable
# service; here the address is stored and the state shown.
class Main < Sinatra::Base
    ICAL_IMPORT_MAX_URL_LENGTH = 2000

    # asks the timetable service to fetch the feed now (or to drop it)
    def trigger_ical_import(email)
        begin
            http = Net::HTTP.new('timetable', 8080)
            http.request(Net::HTTP::Get.new("/api/ical_import/#{CGI.escape(email)}"))
        rescue StandardError => e
            STDERR.puts e
        end
    end

    # The address is a secret (whoever has it reads the calendar): the page
    # only ever gets its host.
    def ical_import_state
        row = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]}).first || {}
            MATCH (u:User {email: $email})
            RETURN u.ical_import_url AS url, u.ical_import_ok_at AS ok_at, u.ical_import_count AS count,
                   u.ical_import_recurring AS recurring, u.ical_import_error AS error, u.ical_import_error_at AS error_at;
        END_OF_QUERY
        url = row['url']
        {
            :active => !url.nil?,
            :host => url ? (URI.parse(url).hostname rescue '') : nil,
            :ok_at => row['ok_at'],
            :count => row['count'],
            :recurring => row['recurring'],
            :error => row['error'],
            :error_at => row['error_at'],
        }
    end

    post '/api/ical_import_state' do
        assert(user_with_role_logged_in?(:can_import_ical))
        respond(ical_import_state)
    end

    post '/api/ical_import_set' do
        assert(user_with_role_logged_in?(:can_import_ical))
        data = parse_request_data(:required_keys => [:url],
                                  :max_value_lengths => {:url => ICAL_IMPORT_MAX_URL_LENGTH})
        url = data[:url].strip
        # webcal:// is how calendar apps are offered a feed: the same over https
        url = url.sub(/\Awebcals?:\/\//i, 'https://')
        uri = (URI.parse(url) rescue nil)
        assert(uri.is_a?(URI::HTTP) && !uri.hostname.to_s.empty?, 'invalid uri')
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :url => url})
            MATCH (u:User {email: $email})
            SET u.ical_import_url = $url
            REMOVE u.ical_import_ok_at, u.ical_import_count, u.ical_import_recurring,
                   u.ical_import_error, u.ical_import_error_at;
        END_OF_QUERY
        trigger_ical_import(@session_user[:email])
        respond(ical_import_state)
    end

    post '/api/ical_import_delete' do
        assert(user_with_role_logged_in?(:can_import_ical))
        neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email]})
            MATCH (u:User {email: $email})
            REMOVE u.ical_import_url, u.ical_import_ok_at, u.ical_import_count, u.ical_import_recurring,
                   u.ical_import_error, u.ical_import_error_at;
        END_OF_QUERY
        trigger_ical_import(@session_user[:email])
        respond(ical_import_state)
    end

    # the profile's section (profil.html): only with the role, only in the
    # new design – everyone else gets the page as before
    def ical_import_profile_section
        return '' unless ui_preview? && user_with_role_logged_in?(:can_import_ical)
        <<~END_OF_HTML
            <div class='pv-icim' id='ical_import'>
                <h2 style='margin-bottom: 30px; margin-top: 30px;'>Kalender einbinden</h2>
                <p class='pv-icim-lead'>Termine aus einem anderen Kalender erscheinen in deinem Stundenplan, nur für dich. Trag die Adresse des Kalenders ein (iCal, endet oft auf <code>.ics</code>). Das Dashboard holt ihn alle 15 Minuten neu.</p>
                <div class='pv-icim-state' role='status'></div>
                <div class='pv-icim-form'>
                    <label for='ti_ical_import_url' class='sr-only'>Adresse des Kalenders</label>
                    <input type='url' id='ti_ical_import_url' class='form-control' autocomplete='off' spellcheck='false' placeholder='https://…/kalender.ics' />
                    <button type='button' class='btn btn-success' id='bu_ical_import_save'>Einbinden</button>
                </div>
                <button type='button' class='btn btn-link pv-icim-remove' id='bu_ical_import_delete' hidden>Kalender entfernen</button>
                <hr />
            </div>
            <script src='#{preview_asset('/preview/ical_import.js')}'></script>
        END_OF_HTML
    end
end
