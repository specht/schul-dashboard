class Main < Sinatra::Base
    # What the search in the navigation bar finds: only things every teacher
    # may open anyway (class and course lists, timetables). Built from memory,
    # no database query. The pages of the person's own menu are added in the
    # browser (code.js, quick search).
    def quick_search_index
        require_teacher!
        items = []
        led_klassen = {}
        @@klassen_order.each do |klasse|
            (@@klassenleiter[klasse] || []).each do |shorthand|
                led_klassen[shorthand] ||= []
                led_klassen[shorthand] << tr_klasse(klasse)
            end
        end

        @@klassen_order.each do |klasse|
            sus = @@schueler_for_klasse[klasse] || []
            sub = ["#{sus.size} Schüler:innen"]
            klassenleiter = @@klassenleiter[klasse] || []
            sub << "Klassenleitung #{klassenleiter.join(', ')}" unless klassenleiter.empty?
            item = {
                :kind => 'klasse',
                :label => "Klasse #{tr_klasse(klasse)}",
                :sub => sub.join(' · '),
                :terms => "Klasse #{tr_klasse(klasse)} #{klasse}",
                :href => "/directory/#{CGI.escape(klasse)}",
            }
            if @@klassen_id[klasse]
                item[:actions] = [['Stundenplan', "/timetable/#{@@klassen_id[klasse]}"]]
            end
            items << item
        end

        @@lehrer_order.each do |email|
            user = @@user_info[email]
            next unless user
            sub = [user[:shorthand]]
            sub << "Klassenleitung #{led_klassen[user[:shorthand]].join(', ')}" if led_klassen[user[:shorthand]]
            items << {
                :kind => 'lehrer',
                :label => user[:display_name],
                :sub => sub.join(' · '),
                :terms => [user[:first_name], user[:last_name], user[:display_name]].join(' '),
                :shorthand => user[:shorthand],
                :href => "/timetable/#{user[:id]}",
            }
        end

        @@klassen_order.each do |klasse|
            (@@schueler_for_klasse[klasse] || []).each do |email|
                user = @@user_info[email]
                next unless user
                items << {
                    :kind => 'schueler',
                    :label => user[:display_name],
                    :sub => "Klasse #{tr_klasse(klasse)}",
                    :terms => [user[:first_name], user[:last_name], user[:display_name]].join(' '),
                    :href => "/directory/#{CGI.escape(klasse)}#quick=#{user[:id]}",
                    :actions => [['Stundenplan', "/timetable/#{user[:id]}"]],
                }
            end
        end

        # courses with their own list (upper school, electives)
        @@kurse_for_lehrer.values.flatten.uniq.each do |lesson_key|
            info = @@lessons[:lesson_keys][lesson_key]
            next unless info
            fach = @@faecher[info[:fach]] || info[:fach]
            sub = ['Kurs']
            sub << info[:lehrer].join(', ') unless (info[:lehrer] || []).empty?
            sub << "#{(@@schueler_for_lesson[lesson_key] || []).size} Schüler:innen"
            items << {
                :kind => 'kurs',
                :label => info[:pretty_folder_name],
                :sub => sub.join(' · '),
                :terms => [info[:pretty_folder_name], fach, (info[:lehrer] || []).join(' ')].join(' '),
                :href => "/directory/#{CGI.escape(lesson_key)}",
            }
        end
        items
    end

    # Pages beyond the menu, each only for those who may open it, and words
    # the pages are found by (also for the pages of the menu, by href; a key
    # ending in * matches every href starting with it).
    QUICK_SEARCH_KEYWORDS = {
        '/' => 'Stundenplan Heute Woche Vertretung Vertretungsplan',
        '/messages' => 'Post Posteingang Postausgang schreiben',
        '/profil' => 'Einstellungen Konto Farbschema Farbe Design dunkel hell Schrift Profilbild',
        '/passwoerter' => 'Passwort Kennwort Nextcloud Zugang',
        '/bibliothek' => 'Bücher Buch ausleihen ausgeliehen Medien',
        '/tests' => 'Klassenarbeit Klausur Test Arbeiten Termine',
        '/events' => 'Termine Kalender Veranstaltung',
        '/polls' => 'Umfrage Abstimmung Fragebogen',
        '/groups' => 'Gruppen Verteiler',
        '/mailing_lists' => 'Verteiler Mail E-Mail Liste',
        '/hilfe' => 'Hilfe Anleitung Fragen Support',
        '/kurslisten' => 'Kurse Listen Oberstufe',
        '/school_wifi' => 'WLAN WiFi Internet',
        '/tablets' => 'Tablet iPad Geräte',
        '/bookings' => 'Buchung Raum Tablet reservieren',
        '/manage_news' => 'News Neuigkeiten Startseite',
        '/manage_calendar' => 'Termine Kalender verwalten',
        '/manage_monitor' => 'Monitor Bildschirm Anzeige',
        '/stats' => 'Statistik Zahlen Nutzung',
        '/email_accounts' => 'E-Mail Postfach Mailbox',
        '/postfaecher' => 'Postfach Passwort zurücksetzen E-Mail-Brief',
        '/show_all_login_codes' => 'Anmeldung Login Codes live',
        '/angebote' => 'AG Arbeitsgemeinschaft Angebot',
        '/lehrbuchverein' => 'Lehrmittel Bücher Verein',
        '/upload_files' => 'Datei hochladen Upload',
        '/upload_images' => 'Bild Foto hochladen Upload',
        '/zufallsgruppen/*' => 'Gruppen zufällig',
        '/projekttage*' => 'Projekt Projektwoche',
        '/lessons/*' => 'Kursbuch Unterricht Stunde Hausaufgaben',
        '/directory/*' => 'Klassenliste Schülerliste E-Mail Eltern Sitzplan',
    }

    def quick_search_pages
        pages = []
        add = lambda { |href, label, section, terms = ''| pages << {:kind => 'seite', :label => label, :sub => section, :terms => terms, :href => href} }
        add.call('/profil#anmeldung', 'Anmeldung und Zwei-Faktor', 'Profil', 'OTP Authenticator SMS Handy Telefonnummer 2FA Sicherheit')
        if teacher_logged_in? || can_manage_bib_logged_in?
            add.call('/bib_browse', 'Katalog', 'Bibliothek', 'Bücher Buch suchen Medien')
        end
        if teacher_logged_in? && !device_logged_in?
            add.call('/bib_orders', 'Bestellungen', 'Bibliothek', 'Bücher bestellen Klassensatz')
        end
        if can_manage_bib_logged_in?
            [['/bib_overview', 'Übersicht'], ['/bib_books', 'Medien'], ['/bib_users', 'Nutzer'], ['/bib_all_orders', 'Alle Bestellungen'],
             ['/bib_scan', 'Bücher scannen'], ['/bib_return', 'Rückgabe'], ['/bib_discard', 'Ausmustern']].each do |href, label|
                add.call(href, label, 'Bibliothek', 'Bücher Buch')
            end
        end
        if admin_logged_in?
            ADMIN_PAGE_LINKS.each { |href, label, _| add.call(href, label, 'Administration') }
            [['#teachers', 'Lehrkräfte'], ['#sus', 'Schüler:innen'], ['#external_users', 'Externe Konten'], ['#tablets', 'Tablets'], ['#monitor', 'Monitor']].each do |anchor, label|
                add.call("/admin#{anchor}", "#{label} (Administration)", 'Administration', 'Konten Nutzer')
            end
        end
        add.call(NEXTCLOUD_URL, 'Nextcloud', 'Extern', 'Dateien Cloud Ordner Unterrichtsmaterial')
        pages.each { |page| page[:external] = true unless page[:href].start_with?('/') }
        pages
    end

    get '/api/quick_search_index' do
        require_teacher!
        response.headers['Cache-Control'] = 'no-store'
        respond_raw_with_mimetype({:items => quick_search_index + quick_search_pages, :keywords => QUICK_SEARCH_KEYWORDS}.to_json, 'application/json')
    end
end
