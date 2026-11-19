require 'date'
require 'json'

# Wetter- und Festeffekte für die Monitore im Schulhaus.
#
# Das Wetter kommt aus den amtlichen Warnungen des Deutschen Wetterdienstes
# (Open Data, frei nutzbar mit Quellenangabe, ohne Schlüssel). Nur der Server
# fragt dort an, die Monitore selbst sprechen nie mit dem DWD. Die Effekte
# erscheinen nur bei markanten Warnungen (orange und höher), damit sie etwas
# Besonderes bleiben.
#
# Hier stehen nur reine Funktionen (ohne Netz und Datenbank), damit sie sich
# testen lassen. Abruf, Zwischenspeicher und Route: include/monitor.rb,
# Darstellung: src/static/monitor_effekte.js.
module MonitorEffekte
    DWD_WARNINGS_URL = 'https://www.dwd.de/DWD/warnungen/warnapp/json/warnings.json'
    # Das Warngebiet steht in MONITOR_DWD_WARNCELL (credentials.template.rb).
    # Länger als so viele Sekunden nicht erneuerte Warnungen gelten nicht mehr
    # (falls der DWD eine Warnung vorzeitig aufhebt und wir ihn nicht erreichen).
    HOECHSTALTER = 2 * 60 * 60

    EFFEKTE = %w(schnee regen gewitter hitze sturm glatteis frost).freeze
    FESTE = %w(weihnachten nikolaus ostern valentinstag fasching sommerferien schulanfang adventskonzert forschertag).freeze
    # Storys: kleine Geschichten, die die Monitore von selbst ab und zu zeigen
    STORYS = %w(roehre kiesel rohrbruch gondel spinne schief taube maus raupe ballon blasen heissluft ufo abflug brand kran bienen diebstahl brom ballspiel).freeze
    # Storys nur in den Pausen (Jonas, 18.11.): [von, bis, wie viele]; zufällig im Zeitraum,
    # jede Story höchstens einmal am Tag, alle Flur-Monitore nach demselben Plan
    STORY_PAUSEN = [['07:46', '08:00', 3], ['08:45', '08:50', 1], ['10:20', '10:23', 1], ['10:35', '10:40', 2],
                    ['12:10', '12:15', 2], ['12:45', '12:50', 2], ['13:05', '13:10', 2], ['13:35', '13:40', 2],
                    ['14:25', '14:35', 2]].freeze
    STORY_DAUER = 65     # Sekunden: so lange läuft eine Story höchstens; sie endet vor dem Pausenende
    STORY_LUECKE = 5     # Sekunden zwischen zwei Storys in derselben Pause
    # einzelne Storys dürfen länger dauern (Jonas, 18.11.: die Abflugtafel läuft 75–80 s;
    # höchstens 30 s normal, kaputt und Reparatur, danach 15 s gut) – mit etwas Reserve
    STORY_DAUER_JE = {'abflug' => 90, 'kran' => 70}.freeze
    # Zeiten, in denen eine Story nicht kommen darf (Jonas, 18.11.: die Abflugtafel nicht
    # zwischen 7:45 und 8:00 Uhr); gilt für jede Pause, die diese Zeit berührt
    STORY_SPERRZEITEN = {'abflug' => [['07:45', '08:00']]}.freeze

    def self.story_dauer(story)
        STORY_DAUER_JE.fetch(story, STORY_DAUER)
    end

    # Pausen aus „Monitore verwalten“ prüfen: [[von, bis, anzahl], …] mit HH:MM, von < bis,
    # Anzahl 1–9, höchstens 20 Pausen; nach Beginn sortiert. Ungültig → nil
    def self.pausen_pruefen(liste)
        return nil unless liste.is_a?(Array) && liste.size <= 20
        minuten = lambda { |z| z.is_a?(String) && z =~ /\A([01]?\d|2[0-3]):([0-5]\d)\z/ ? $1.to_i * 60 + $2.to_i : nil }
        pausen = liste.map do |p|
            return nil unless p.is_a?(Array) && p.size == 3
            von, bis, anzahl = minuten.call(p[0]), minuten.call(p[1]), p[2]
            anzahl = anzahl.to_i if anzahl.is_a?(String) && anzahl =~ /\A\d+\z/
            return nil unless von && bis && von < bis && anzahl.is_a?(Integer) && anzahl >= 1 && anzahl <= 9
            [format('%02d:%02d', von / 60, von % 60), format('%02d:%02d', bis / 60, bis % 60), anzahl]
        end
        pausen.sort_by { |p| p[0] }
    end

    # Einzeln ausgeschaltete Storys aus „Monitore verwalten“ prüfen (Wunsch Jonas, 18.11.):
    # nur bekannte Namen, jeder einmal, in der Reihenfolge von STORYS. Ungültig → nil
    def self.storys_aus_pruefen(liste)
        return nil unless liste.is_a?(Array) && liste.size <= STORYS.size * 2 && liste.all? { |x| x.is_a?(String) }
        STORYS.select { |s| liste.include?(s) }
    end

    # Tagesplan: [{:sekunde (seit Mitternacht), :story}], gleich für dasselbe Datum
    def self.story_plan(datum, storys = STORYS, pausen = STORY_PAUSEN)
        return [] if datum.saturday? || datum.sunday? || storys.empty?
        rng = Random.new(datum.strftime('%Y%m%d').to_i * 7919 + 17)
        reihe = storys.shuffle(random: rng)
        sek = lambda { |z| z.split(':').map(&:to_i).inject { |h, m| h * 60 + m } * 60 }
        # Plätze je Pause: so viele, wie Storys normaler Länge hineinpassen
        plaetze = []
        pausen.each_with_index do |(von, bis, anzahl), pi|
            frei = sek.call(bis) - sek.call(von)
            anzahl -= 1 while anzahl > 0 && anzahl * STORY_DAUER + (anzahl - 1) * STORY_LUECKE > frei
            anzahl.times { plaetze << pi }
        end
        # weniger Storys als Plätze: zufällig über alle Pausen des Tages verteilen
        if reihe.size < plaetze.size
            plaetze = plaetze.each_with_index.to_a.sample(reihe.size, random: rng).sort_by(&:last).map(&:first)
        end
        belegung = plaetze.each_with_index.map { |pi, i| [pi, reihe[i]] }
        # gesperrte Pausen: mit einer Story aus einer erlaubten Pause tauschen; geht das nicht,
        # fällt die Story heute aus
        gesperrt = lambda do |story, pi|
            von, bis = sek.call(pausen[pi][0]), sek.call(pausen[pi][1])
            (STORY_SPERRZEITEN[story] || []).any? { |a, b| von < sek.call(b) && bis > sek.call(a) }
        end
        belegung.each_with_index do |(pi, story), i|
            next unless story && gesperrt.call(story, pi)
            j = belegung.each_index.find { |k| k != i && !gesperrt.call(story, belegung[k][0]) && !gesperrt.call(belegung[k][1], pi) }
            if j
                belegung[i][1], belegung[j][1] = belegung[j][1], story
            else
                belegung[i][1] = nil
            end
        end
        je_pause = Hash.new { |h, k| h[k] = [] }
        belegung.each { |pi, story| je_pause[pi] << story if story }
        plan = []
        je_pause.keys.sort.each do |pi|
            liste = je_pause[pi]
            a = sek.call(pausen[pi][0])
            frei = sek.call(pausen[pi][1]) - a
            brauchen = lambda { liste.sum { |x| story_dauer(x) } + (liste.size - 1) * STORY_LUECKE }
            # passt eine lange Story nicht in diese Pause, fällt sie heute aus
            liste.delete_at(liste.index(liste.max_by { |x| story_dauer(x) })) while liste.any? && brauchen.call > frei
            next if liste.empty?
            platz = frei - brauchen.call
            versatz = Array.new(liste.size) { rng.rand * platz }.sort
            schon = 0
            liste.each_with_index do |x, i|
                plan << {:sekunde => (a + versatz[i] + schon).floor, :story => x}
                schon += story_dauer(x) + STORY_LUECKE
            end
        end
        plan
    end
    # Treffen Wetter und Fest zusammen: Einzeltage haben Vorrang vor dem Wetter,
    # Festzeiten über mehrere Tage (Advent, Ostern) lassen dem Wetter den Vortritt.
    FESTE_EINZELTAG = %w(valentinstag fasching sommerferien nikolaus schulanfang adventskonzert forschertag).freeze
    # Schultermine, die auf „Monitore verwalten“ eingetragen werden (je ein Tag)
    SCHULTERMIN_MOTIVE = {'adventskonzert' => 'Adventskonzert', 'forschertag' => 'Forschertag'}.freeze

    # Reihenfolge, wenn mehrere Warnungen gleichzeitig gelten: das, was man
    # draußen am deutlichsten merkt, gewinnt.
    VORRANG = %w(gewitter schnee regen sturm glatteis frost hitze).freeze

    # Level im warnings.json des DWD: 1 Vorabinformation, 2 Wetterwarnung (gelb),
    # 3 markantes Wetter (orange), 4 Unwetter (rot), 5 extremes Unwetter (violett),
    # 10 starke Hitze, 11 extreme Hitze.
    #
    # Je Effekt lässt sich auf „Monitore verwalten“ einstellen, ob er erscheint
    # und ab welcher Stufe. Ohne Einstellung gilt das hier. Sturm erst ab rot,
    # weil Sturmböen (orange) in Berlin häufig sind; Schnee schon ab gelb (beim
    # Schnee zeigt die Stufe sich am Monitor: Streufahrzeug ab orange, Pistenraupen ab rot).
    REGELN_STANDARD = {
        'schnee' => {:an => true, :ab => 2}, 'regen' => {:an => true, :ab => 3},
        'gewitter' => {:an => true, :ab => 3}, 'sturm' => {:an => true, :ab => 4},
        'glatteis' => {:an => true, :ab => 3}, 'frost' => {:an => true, :ab => 3},
        'hitze' => {:an => true, :ab => 10},
    }.freeze
    STUFEN_WAEHLBAR = [2, 3, 4, 5].freeze
    STUFEN_HITZE = [10, 11].freeze

    # Welche Meldungen des DWD zu welchem Effekt gehören (für die Verwaltungsseite;
    # die Zuordnung selbst macht effekt_art an den Wörtern im Ereignisnamen fest).
    PHAENOMENE = {
        'schnee' => ['Leichter Schneefall', 'Schneefall', 'Starker Schneefall', 'Extrem starker Schneefall', 'Schneeverwehung', 'Starke Schneeverwehung'],
        'regen' => ['Starkregen', 'Heftiger Starkregen', 'Extrem heftiger Starkregen', 'Dauerregen', 'Ergiebiger Dauerregen', 'Extrem ergiebiger Dauerregen'],
        'gewitter' => ['Gewitter', 'Starkes Gewitter', 'Schweres Gewitter (mit Orkanböen, Starkregen oder Hagel)', 'Extremes Gewitter'],
        'sturm' => ['Windböen', 'Sturmböen', 'Schwere Sturmböen', 'Orkanartige Böen', 'Orkanböen', 'Extreme Orkanböen', 'Sturm, Starkwind'],
        'glatteis' => ['Glätte', 'Glatteis', 'Gefrierender Regen'],
        'frost' => ['Frost', 'Strenger Frost'],
        'hitze' => ['Starke Hitze', 'Extreme Hitze'],
    }.freeze
    PHAENOMENE_OHNE_EFFEKT = ['Nebel', 'Tauwetter', 'UV-Strahlung', 'Leiterseilschwingungen'].freeze

    # Einstellungen aus der Datenbank mit den Standardwerten ergänzen und prüfen
    def self.regeln(gespeichert = {})
        REGELN_STANDARD.each_with_object({}) do |(effekt, standard), r|
            g = (gespeichert || {})[effekt] || {}
            erlaubt = effekt == 'hitze' ? STUFEN_HITZE : STUFEN_WAEHLBAR
            ab = g[:ab].to_i
            r[effekt] = {
                :an => g.key?(:an) ? !!g[:an] : standard[:an],
                :ab => erlaubt.include?(ab) ? ab : standard[:ab],
            }
        end
    end

    # Liest die Antwort des DWD. Sie ist JSONP: warnWetter.loadWarnings({...});
    def self.parse_dwd(text)
        text = text.to_s.dup.force_encoding('UTF-8')
        text = text.encode('UTF-8', 'ISO-8859-1') unless text.valid_encoding?
        start = text.index('{')
        stop = text.rindex('}')
        return nil unless start && stop && stop > start
        JSON.parse(text[start..stop])
    rescue JSON::ParserError
        nil
    end

    # Zu welchem Effekt eine Meldung gehört, egal wie stark – oder nil
    # (Nebel, Tauwetter, UV, …)
    def self.effekt_art(w)
        event = w['event'].to_s.upcase
        if event.include?('HITZE') then 'hitze'
        elsif event.include?('GEWITTER') then 'gewitter'
        elsif event.include?('SCHNEE') then 'schnee'
        # gefrierender Regen ist Glatteis (vor „Regen“ prüfen)
        elsif event.include?('GEFRIER') || event.include?('GLATTEIS') || event.include?('GLÄTTE') then 'glatteis'
        elsif event.include?('FROST') then 'frost'
        elsif event.include?('REGEN') then 'regen'
        elsif event.include?('ORKAN') || event.include?('STURM') || event.include?('BÖEN') || event.include?('STARKWIND') then 'sturm'
        end
    end

    # Ordnet eine einzelne Warnung einem Effekt zu – oder nil, wenn der Effekt
    # ausgeschaltet ist oder die Warnung unter der eingestellten Stufe liegt.
    # Ergebnis: [effekt, staerke 1..3]
    def self.effekt_fuer_warnung(w, regeln = REGELN_STANDARD)
        art = effekt_art(w)
        return nil unless art
        regel = regeln[art] || REGELN_STANDARD[art]
        level = w['level'].to_i
        return nil unless regel[:an] && level >= regel[:ab]
        if art == 'hitze'
            [art, level >= 11 ? 3 : 2]
        else
            [art, [[level - 2, 1].max, 3].min]
        end
    end

    # Sucht aus allen Warnungen die für die Warnzelle heraus, die gerade gelten,
    # und liefert den wichtigsten Effekt:
    # {:effekt, :staerke, :titel, :bis} oder nil
    def self.wetter(daten, warncell, now = Time.now, regeln = REGELN_STANDARD)
        return nil unless daten.is_a?(Hash)
        liste = (daten['warnings'] || {})[warncell.to_s] || []
        now_ms = (now.to_f * 1000).to_i
        kandidaten = []
        liste.each do |w|
            next unless w.is_a?(Hash)
            start = w['start']
            ende = w['end']
            next if start && now_ms < start.to_i
            next if ende && now_ms >= ende.to_i
            e = effekt_fuer_warnung(w, regeln)
            next unless e
            k = {
                :effekt => e[0],
                :staerke => e[1],
                :titel => titel(w['event']),
                :bis => ende ? ende.to_i : nil,
                :stufe => w['level'].to_i,
            }
            k[:zeus] = true if e[0] == 'gewitter'   # Zeus kommt bei jedem Gewitter (Wunsch Jonas)
            kandidaten << k
        end
        kandidaten.min_by { |k| [VORRANG.index(k[:effekt]), -k[:staerke]] }
    end

    STUFEN = {
        1 => 'Vorabinformation', 2 => 'Wetterwarnung (gelb)', 3 => 'Markantes Wetter (orange)',
        4 => 'Unwetterwarnung (rot)', 5 => 'Warnung vor extremem Unwetter (violett)',
        10 => 'Hitzewarnung', 11 => 'Warnung vor extremer Hitze',
    }.freeze

    # Alle Warnungen des DWD für die Warnzelle, die jetzt gelten oder noch
    # kommen – für die Verwaltungsseite, damit man sieht, was der DWD meldet und
    # warum (nicht) etwas auf den Monitoren passiert. Texte kommen vom DWD.
    def self.warnungen(daten, warncell, now = Time.now, regeln = REGELN_STANDARD)
        return [] unless daten.is_a?(Hash)
        now_ms = (now.to_f * 1000).to_i
        liste = (daten['warnings'] || {})[warncell.to_s] || []
        liste.select { |w| w.is_a?(Hash) && !(w['end'] && now_ms >= w['end'].to_i) }.map do |w|
            e = effekt_fuer_warnung(w, regeln)
            {
                :titel => titel(w['event']),
                :stufe => w['level'].to_i,
                :stufe_text => STUFEN[w['level'].to_i] || "Stufe #{w['level']}",
                :beginn => w['start'] ? w['start'].to_i : nil,
                :ende => w['end'] ? w['end'].to_i : nil,
                :gilt_jetzt => !(w['start'] && now_ms < w['start'].to_i),
                :gebiet => w['regionName'].to_s[0, 200],
                :ueberschrift => w['headline'].to_s[0, 300],
                :beschreibung => w['description'].to_s[0, 2000],
                :hinweise => w['instruction'].to_s[0, 2000],
                :effekt => e ? e[0] : nil,
                :art => effekt_art(w),
            }
        end.sort_by { |w| [w[:gilt_jetzt] ? 0 : 1, -w[:stufe], w[:beginn] || 0] }
    end


    # „STARKER SCHNEEFALL“ → „Starker Schneefall“
    NOMEN =%w(schneefall schneeverwehung regen starkregen dauerregen gewitter hagel
               hitze frost glatteis glätte sturm sturmböen orkanböen böen).freeze

    def self.titel(event)
        woerter = event.to_s.downcase.split(' ')
        woerter.each_with_index.map { |w, i| (i == 0 || NOMEN.include?(w)) ? w.capitalize : w }.join(' ')
    end

    # Test auf den echten Monitoren („Monitore verwalten“): wie lange er läuft und
    # was er zeigt – [wetter, fest] wie bei echtem Wetter bzw. einem echten Fest,
    # bei einer Story [nil, nil, name].
    # Test auf den echten Monitoren: genau ein Durchlauf (Jonas, 19.11.) – eine Story so lange,
    # wie sie höchstens dauert, ein Wetter- oder Festeffekt so lange wie in der Vorschau
    TEST_EFFEKT_SEKUNDEN = 45
    def self.test_dauer(name)
        STORYS.include?(name) ? story_dauer(name) + 10 : TEST_EFFEKT_SEKUNDEN
    end
    def self.test_soll(name)
        if EFFEKTE.include?(name)
            w = {:effekt => name, :staerke => 2, :titel => 'Test', :bis => nil}
            w[:zeus] = true if name == 'gewitter'
            return [w, nil]
        end
        return [nil, {:fest => name, :nah => true}] if FESTE.include?(name)
        return [nil, nil, name] if STORYS.include?(name)
        [nil, nil]
    end

    # Ostersonntag nach dem gregorianischen Kalender (Algorithmus von Meeus,
    # Jones und Butcher)
    def self.ostersonntag(jahr)
        a = jahr % 19
        b = jahr / 100
        c = jahr % 100
        d = b / 4
        e = b % 4
        f = (b + 8) / 25
        g = (b - f + 1) / 3
        h = (19 * a + b - d - g + 15) % 30
        i = c / 4
        k = c % 4
        l = (32 + 2 * e + 2 * i - h - k) % 7
        m = (a + 11 * h + 22 * l) / 451
        monat = (h + l - 7 * m + 114) / 31
        tag = ((h + l - 7 * m + 114) % 31) + 1
        Date.new(jahr, monat, tag)
    end

    # Welches Fest gerade ist: {:fest, :nah} oder nil.
    # Weihnachten: 1. bis 26. Dezember die Lichterkette; „nah“ ab dem
    # 16. Dezember, erst dann fliegt der Weihnachtsmann (Wunsch der Schule).
    # Ostern: der Osterhase hoppelt ab einer Woche vor Beginn der Osterferien
    # (aus dem Ferienkalender des Dashboards, für uns Berlin) bis Ostermontag.
    # Ohne Ferienkalender: ab zwei Wochen vor Ostersonntag.
    # ferien: [{:from => 'JJJJ-MM-TT', :to => …, :title => 'Osterferien'}, …]
    #
    # Valentinstag: 14. Februar. Fasching: Rosenmontag und Faschingsdienstag
    # (48 und 47 Tage vor Ostersonntag). Letzter Schultag vor den Sommerferien:
    # der letzte Werktag vor Beginn der Sommerferien laut Ferienkalender, der kein
    # Ferien- oder Feiertag ist.
    # Liefert [wetter, fest, zurueckgestellt]: höchstens einer von beiden läuft;
    # zurueckgestellt nennt den Effekt, der gerade ruht ('wetter' oder 'fest'), sonst nil.
    def self.vorrang(wetter, fest)
        return [wetter, fest, nil] unless wetter && fest
        if FESTE_EINZELTAG.include?(fest[:fest])
            [nil, fest, 'wetter']
        else
            [wetter, nil, 'fest']
        end
    end

    # zeit: aktuelle Uhrzeit (Time); der Schulanfang endet um 12 Uhr, danach sind
    # Einschulungen. Ohne zeit (Tests) gilt der ganze Tag.
    # Ein eingetragener Schultermin geht an seinen Tagen allen Festen vor.
    # termine: [{:datum => 'JJJJ-MM-TT', :bis => 'JJJJ-MM-TT' oder leer, :motiv => …}]
    def self.schultermin(datum, termine)
        tag = datum.to_s
        t = (termine || []).find do |x|
            bis = x[:bis].to_s.empty? ? x[:datum].to_s : x[:bis].to_s
            x[:datum].to_s <= tag && tag <= bis && SCHULTERMIN_MOTIVE.include?(x[:motiv])
        end
        t ? {:fest => t[:motiv], :nah => true} : nil
    end

    def self.fest(datum = Date.today, ferien = [], zeit = nil)
        # Nikolaus (Stiefel mit Süßigkeiten) geht der Adventsdeko vor
        return {:fest => 'nikolaus', :nah => true} if datum == nikolaustag(datum.year)
        if datum.month == 12 && datum.day <= 26
            return {:fest => 'weihnachten', :nah => datum.day >= 16}
        end
        return {:fest => 'valentinstag', :nah => true} if datum.month == 2 && datum.day == 14
        ostern = ostersonntag(datum.year)
        return {:fest => 'fasching', :nah => true} if datum == ostern - 48 || datum == ostern - 47
        return {:fest => 'sommerferien', :nah => true} if datum == letzter_schultag_vor_sommerferien(datum.year, ferien)
        if datum == erster_schultag_nach_sommerferien(datum.year, ferien) && (zeit.nil? || zeit.hour < 12)
            return {:fest => 'schulanfang', :nah => true}
        end
        ferienbeginn = osterferien_beginn(ostern, ferien)
        beginn = ferienbeginn ? ferienbeginn - 7 : ostern - 14
        if datum >= beginn && datum <= ostern + 1
            return {:fest => 'ostern', :nah => datum >= beginn + 4}
        end
        nil
    end

    # Letzter Schultag vor den Sommerferien eines Jahres – oder nil ohne Ferienkalender
    def self.letzter_schultag_vor_sommerferien(jahr, ferien)
        frei = []
        beginn = nil
        (ferien || []).each do |f|
            von = Date.parse(f[:from].to_s) rescue nil
            bis = Date.parse((f[:to] || f[:from]).to_s) rescue nil
            next unless von && bis
            frei << (von..bis)
            beginn = von if f[:title].to_s =~ /sommer/i && von.year == jahr
        end
        return nil unless beginn
        tag = beginn - 1
        tag -= 1 while tag.saturday? || tag.sunday? || frei.any? { |r| r.cover?(tag) }
        tag
    end

    # Beginn der Osterferien im Jahr dieses Osterfests (die Ferien mit „Oster“
    # im Titel, die am nächsten an Ostern liegen) – oder nil
    # Erster Schultag nach den Sommerferien (in Berlin der Montag nach den Ferien)
    def self.erster_schultag_nach_sommerferien(jahr, ferien)
        frei = []
        ende = nil
        (ferien || []).each do |f|
            von = Date.parse(f[:from].to_s) rescue nil
            bis = Date.parse((f[:to] || f[:from]).to_s) rescue nil
            next unless von && bis
            frei << (von..bis)
            ende = bis if f[:title].to_s =~ /sommer/i && von.year == jahr
        end
        return nil unless ende
        tag = ende + 1
        tag += 1 while tag.saturday? || tag.sunday? || frei.any? { |r| r.cover?(tag) }
        tag
    end

    # Nikolaus am 6. Dezember; fällt er aufs Wochenende, der nächstgelegene Schultag
    # (Samstag → Freitag davor, Sonntag → Montag danach)
    def self.nikolaustag(jahr)
        tag = Date.new(jahr, 12, 6)
        return tag - 1 if tag.saturday?
        return tag + 1 if tag.sunday?
        tag
    end

    def self.osterferien_beginn(ostern, ferien)
        kandidaten = (ferien || []).map do |f|
            next nil unless f[:title].to_s =~ /oster/i
            beginn = Date.parse(f[:from].to_s) rescue nil
            next nil unless beginn && (beginn - ostern).abs <= 21
            beginn
        end.compact
        kandidaten.min_by { |b| (b - ostern).abs }
    end
end
