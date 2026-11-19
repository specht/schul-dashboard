# TODO

Sammelliste für Verbesserungen. Stand: November 2026.

**Grundsatz:** Erst Tests, dann Änderungen. Bevor ein Bereich umgebaut oder
größer angefasst wird, muss er durch Tests abgedeckt sein – bei allem, was
Nutzer:innen bedienen, auch durch E2E-Tests (siehe
[doc/Tests.md](doc/Tests.md)). Kleine Fixes bekommen mindestens einen Test,
der den Fehler zeigt.

Für das neue Schuljahr siehe [TODO-NEUES-SCHULJAHR.md](TODO-NEUES-SCHULJAHR.md).

Ausführliche Befunde einer Projekt-Durchsicht (UI/UX, Funktionalität,
Performance, DevOps, Monitoring, Wartung, Doku) stehen in
[review/2026-11/](review/2026-11/README.md) – von dort einzelne Punkte
hierher übernehmen, wenn sie angegangen werden.

## 1. Tests

- [x] Test-Umgebung: `config.rb` mit wählbarer env-Datei (`DASHBOARD_ENV`),
      konfigurierbaren Host-Ports und eigenem Projektnamen
- [x] `src/ruby/test/`, `./test.sh unit|e2e`
- [x] Erster E2E-Test (Playwright-Container): Anmeldung und Stundenplan
- [ ] `rack-test` als Test-Gruppe ins Gemfile, `./test.sh integration`
- [ ] Beispieldaten um je ein Konto pro Rolle ergänzen (Admin, Lehrkraft mit
      Klassenleitung, Schüler:in, Elternteil, Gerät)
- [ ] Feste Systemzeit im Test-Stack (Beispieldaten: Schuljahr 2024/25)
- [x] Seiten-Smoke-Test: jede Seite × jede Rolle, Bestandsaufnahme in
      `test/e2e/tests/known-page-errors.json` (257 Fälle) – Liste abbauen
- [ ] Berechtigungsmatrix für alle API-Routen
- [x] Test-Stack im Produktionsmodus mit Test-Postfach (Mailpit)
- [x] E2E: E-Mail-Code, E-Mail + OTP (Lehrkraft), OTP als erster Faktor,
      falscher Code
- [ ] E2E: OTP als erster + E-Mail als zweiter Faktor (braucht eine dritte
      Lehrkraft in den Beispieldaten), Code per E-Mail nachfordern,
      Kontowechsel, Abmelden, abgelaufener Code, zu viele Versuche
- [ ] Hauptabläufe E2E auf Desktop und Handy (Tabelle in
      [doc/Tests.md](doc/Tests.md))
- [ ] Vorhandene Einzeltests (`nextcloud-client-compatibility-test.rb`,
      `puma-integration-test.rb`, `check-all-timetables.js`) übernehmen
- [ ] CI auf Pull Requests

- [ ] Test-Stack um `mail_bot` und `invitation_bot` erweitern: Ihre
      Fehlerbehandlung (eine fehlerhafte Mail bzw. Einladung hält die anderen
      nicht mehr auf) ist bisher nur von Hand geprüft.

- [ ] E2E, selten: `sitzplan.spec.ts` »Vorgaben je Werkzeug« hing am Handy
      einmal 28 s beim Klick auf »Liste löschen« (19.11.2026, in 40
      Wiederholungen nicht wieder aufgetreten) – beobachten

## 2. UI/UX

### Fehler

- [ ] Datentresor ohne Zeugnislisten (außerhalb der Zeugniszeit,
      `determine_zeugnislisten` kehrt früh zurück): Die Zeugnisübersicht zeigt
      nur ihre Überschrift, der Zeugnislisten-Teil der Zeugnisformulare bleibt
      leer, ein Klick auf eine Klasse im Zeugnisdruck bricht ab – jeweils mit
      einem JavaScript-Fehler (`zeugnisliste_for_klasse` ist leer). Das neue
      Design sagt stattdessen, dass es gerade keine Zeugnislisten gibt; das
      alte Design sollte das auch.
- [ ] Externe Nutzer:innen hinzufügen: Steht statt einer E-Mail-Adresse etwas
      anderes im Feld (z. B. ein Gruppenname wie „Eltern 10a“), endet
      `/api/add_external_users` mit HTTP 500 (`Mail::AddressList` in
      `include/ext_user.rb`) statt mit einem verständlichen Hinweis. Kommt in
      Produktion vor.
- [ ] Umfrage beantworten: Eine Freitext-Antwort wird erst übernommen, wenn das
      Textfeld den Fokus verliert (`change`), vorher bleibt „Absenden“
      deaktiviert. Besser auf `input` reagieren (`_template.html`,
      `textarea.change(…)`).
- [ ] Klassenmemory, Hall of Fame: Der Server zählt die Klassen 11 und 12
      als Stufe „OS“ (`/api/get_recognize_hall_of_fame`), die Seite bildet
      ihre Spalten aber als „11“ und „12“ – für die Oberstufe steht deshalb
      immer „–“, obwohl die Erkannten in „Gesamt“ mitzählen. Außerdem prüft
      der Server `!@@user_info[:teacher]` statt der erkannten Person.
- [ ] Klick auf das Icon in einem Button liefert `undefined`: Handler lesen
      `$(e.target).data(…)` (rund 90 Stellen) statt `e.currentTarget`,
      z. B. `.bu-launch-poll` (`_template.html`), `.btn-impersonate`
      (`admin.html`, `include/admin.rb`)
- [ ] Anmeldeseite: Der Button „Code zusenden“ wird nur bei `keyup`/`change`
      aktiviert – nach Einfügen per Kontextmenü oder Autofill bleibt er
      deaktiviert, bis das Feld den Fokus verliert (`login.html`, auf
      `input` hören)
- [ ] Ein falscher Anmeldecode wird mit HTTP 500 beantwortet (`assert`);
      erwartbare Fehler sollten 4xx mit Fehlercode liefern (gilt allgemein
      für die API)
- [ ] `/login_otp` (nicht verlinkt) legt den Anmeldecode ohne `method`
      an, `confirm_login` vergleicht dann mit einem E-Mail-Code – der Weg
      funktioniert laut Code nicht. Entfernen oder reparieren; die
      OTP-Anmeldung über die Profil-Einstellung funktioniert
- [ ] `c.html:55`: Selektor ohne Punkt
      (`$('send-code-via-email-confirmation')`)
- [ ] Stundenplan: Laden der Wochendaten hat keine Fehlerbehandlung – bei
      Netzwerkfehler bleibt der Kalender kommentarlos leer
      (`timetable.html`)
- [ ] `ext_event.html` liest `show_event`, das in `main.rb` immer leer ist –
      Seite reparieren oder entfernen
- [ ] Seiten mit fehlenden/ungültigen Parametern enden in HTTP 500
      (z. B. `/directory` ohne Klasse, `/lessons/<unbekannt>`, `/c/<unbekannt>`);
      unbekannte Seiten liefern eine leere Seite. Freundliche 404/500-Seiten
      im Stil der Neustart-Seite
- [ ] Klassenliste einer Klasse ohne Schüler:innen (Beispieldaten: `/directory/5b`)
      endet für Lehrkräfte im bisherigen Design in HTTP 500
      (`mail_addresses_table`: `@@schueler_for_klasse[klasse].size`); das neue
      Design zeigt einen leeren Zustand
- [ ] `/api/print_email_letters`: der `reject!`-Block verlässt mit `return true`
      die ganze Route, statt die Adresse auszusortieren – Lehrkräfte ohne
      Klassenleitung bekommen statt einer Fehlermeldung eine leere Antwort
      (»Alle E-Mail-Briefe« zeigt das neue Design nur Klassenleitung,
      Admins und Sekretariat)
- [ ] Zugangsprüfungen per `require_…!`/`assert` auf Seiten führen zu
      HTTP 500 statt zu Umleitung oder Hinweis – laut Smoke-Test 153 Fälle
      über alle Rollen (`bib_*`, `kurslisten`, `pk5`, `lab8/9`, `aula*`,
      `anmeldungen` …); für Abgemeldete wäre die Anmeldeseite mit
      `return_to` richtig
- [ ] Beispieldaten unvollständig – auf einer frischen Installation stürzen
      dadurch Seiten ab: `NOTEN_CUTOFF` (zeugnisse/config.rb, 8 Seiten),
      `public_events/public_events.yaml` (öffentliche Anmeldung),
      `mittagessen/mittagessen.yaml`, `email_is_eligible_for_lab8?`/`lab9?`,
      Phasen für Projekttage und PK5. Seiten sollten fehlende Konfiguration
      abfangen; die Beispieldaten sollten alles enthalten
- [ ] `credentials.template.rb` deklariert `ROOM_ORDER = %w(101 102 103 104)`,
      der Beispiel-Stundenplan nutzt aber 108, 129, 317, 323 – auf einer
      frischen Installation hat keine Klasse einen Raum, Sitzpläne sind
      nicht nutzbar (der Test-Stack setzt die passenden Räume)
- [ ] Fußzeile: „© 2026 Gymnasium Steglitz“ ist fest im Template statt
      `SCHUL_NAME` und aktuellem Jahr
- [ ] `salzh`, `salzh_protokoll`, `self_tests` verweisen auf die entfernte
      Rolle `can_manage_salzh` und stürzen für alle ab

- [ ] Schüler:innen sehen Änderungen am Stundenplan erst bis zu 60 s später:
      `/gen/` wird mit `max-age=60` ausgeliefert, und nur Lehrkräfte laden
      Wochendateien mit Cache-Buster (`timetable.html`). In der Entwicklung
      ist der Cache abgeschaltet
- [ ] Menüleiste für Admins zwischen 768 und etwa 1100 px Breite zu breit:
      Schullogo und Name werden links abgeschnitten. Darüber hilft
      `code.js` (Suche) nacheinander: ohne „Suchen“, ohne Menü-Icons, ohne
      Schulnamen neben dem Logo
- [ ] Termine ohne Teilnehmende: Die Abfrage liefert `recipients: [null]`,
      die Tabelle im bisherigen Design zeigt dann „1 Teilnehmer“ an
      (`include/event.rb`, `organized_events`). Das neue Design zählt nur
      echte Teilnehmende.
- [ ] Kursbuch (bisheriges Design): „Speichern“ wird nur bei `keyup`/`change`
      aktiv – nach Einfügen per Kontextmenü bleibt es deaktiviert, bis das
      Feld den Fokus verliert (`lessons.html`, `.pane_items .form-control`).
      Das neue Design hört zusätzlich auf `input` (`preview/lessons.js`).
- [ ] Kursbuch (bisheriges Design): „… aus dem Verlauf entfernen“ löscht
      ohne Rückfrage die Einträge und Kommentare der Stunde; das neue Design
      fragt vorher nach.
- [ ] Bibliothek, Nutzerseite (`bib_user.html`): Hat die Person aufgehobene
      Ausleihen, überschreibt die Tabelle dafür die Variable `table` – neu
      gescannte Ausleihen erscheinen dann in »Aufgehobene Ausleihen« statt
      in »Ausgeliehene Medien« (gebucht wird richtig, nur die Anzeige ist
      falsch, bis die Seite neu geladen wird).
- [ ] Neuigkeiten: `/api/store_news_entry` verwendet den Zeitstempel in
      Sekunden als Schlüssel; zwei Einträge in derselben Sekunde scheitern am
      Unique-Constraint. Betrifft praktisch nur Skripte.

### Wünsche

- [ ] Termine direkt im Stundenplan anlegen (Klick in den Kalender wie bei
      Google Kalender) für alle, die Termine erstellen dürfen – statt über
      die Seite „Termine“
- [ ] Externe Kalender (`ical_import.rb`): Terminserien (`RRULE`, `EXDATE`)
      übernehmen; bedingtes Abrufen (`If-None-Match`/`If-Modified-Since`),
      damit unveränderte Kalender nichts kosten
- [ ] Terminfinder (`/terminfinder`, bisher nur im neuen Design): für alle
      Lehrkräfte freigeben, sobald das neue Design für alle läuft; dann
      überlegen, ob der Tagesrahmen (bis 18 Uhr) einstellbar sein soll

### Rückmeldung bei Laden und Fehlern

- [ ] 77 Seiten nutzen `api_call`, haben aber kein `.api_messages`-
      Element – Lade- und Fehlermeldungen erscheinen dort nie (u. a.
      `timetable`, `messages`, `polls`, `events`, `profil`, `directory`,
      `sitzplan*`, `admin`). Ein globales Element im Template wäre die
      einfachste Lösung
- [ ] `api_call` (`code.js`): Offline, Zeitüberschreitung, fehlende
      Berechtigung und Serverfehler unterscheiden und verständlich melden;
      während eines Neustarts (502) automatisch erneut versuchen
- [x] Native `alert()`/`confirm()` durch `dashboardAlert()`/`dashboardConfirm()`
      ersetzt (29 Stellen in `sitzplanhelfer.html` und `admin.html`); ein
      Unit-Test und die E2E-Tests verhindern neue native Dialoge
- [ ] Nach Aktionen nicht pauschal `location.reload()` (51 Stellen) –
      Eingaben, Scrollposition und offene Modals gehen verloren

### Mobil

- [ ] Fixierte Fußzeile (`.foot`, `z-index: 100000` in `styles.css`) liegt
      über Modals (`z-index: 8000`) und kann auf dem Handy Buttons wie
      „Senden“ im Umfrage-Modal verdecken
- [ ] Kalender mit fester Höhe (`timetable.html`)
- [ ] Nur 20 von 71 Tabellen in `table-responsive`
- [ ] Profil- und Admin-Menü sind sehr lange Dropdowns
- [ ] Summernote-Editor auf dem Handy schwer bedienbar (Nachrichten,
      Termine)
- [x] Sitzplan-Ansicht auf dem Handy: Namen werden mitten im Wort
      umbrochen („Musterman / n“) – Plätze zeigen jetzt Foto und ganzen
      Namen, breite Räume lassen sich seitlich verschieben

### Barrierefreiheit

- [ ] Kein `<img>` hat `alt` (u. a. Logo in der Navigation, `hilfe.html`)
- [ ] Icon-only-Buttons ohne `aria-label` (z. B. `lessons.html`, `pk5.html`,
      GitHub-Link im Fuß)
- [ ] Labels ohne `for` bzw. mit falschem Ziel (`profil.html`-Schieberegler,
      `anmeldung.html` → `staticEmail`)
- [ ] Code-Eingaben in `c.html`: `inputmode="numeric"
      autocomplete="one-time-code"` statt `type="number"` (Autofill aus SMS/
      Mail, keine Pfeiltasten-Änderung)
- [ ] Modals verweisen auf nicht vorhandenes `exampleModalLabel`
- [ ] Navigation: Label „Toggle navigation“ auf Deutsch
- [ ] `.text-muted` ist fest `#666` und im Dunkelmodus kaum lesbar
- [ ] `sitzplan*`-Seiten haben keine Dunkelmodus-Regeln (weiße Karte mit
      weißer Schrift möglich) – erledigt für Sitzplan-Seite und Ansicht
      ohne Wünsche, offen für Editor und Shuffler
- [ ] Kontraste bei eigenen Farbschemata und Filtern (Kontrast,
      Helligkeit) prüfen, z. B. mit axe-core in den E2E-Tests
- [ ] Sichtbare Fokus-Rahmen (teilweise durch `dark.css` überschrieben)

### Gestaltung und Texte

- [ ] Profil: drei sich überschneidende Schalter (Hintergrund hell/dunkel,
      Helligkeit hell/dunkel, Helligkeits-Regler) zusammenfassen
- [ ] Bootstrap 4, Tailwind (inkl. Preflight) und Flowbite überlagern sich;
      Richtung festlegen und schrittweise vereinheitlichen
- [ ] „Neues Design“ (`new_design.css`) ist nur Opt-in – übernehmen oder
      entfernen
- [ ] Anrede: an einigen Stellen „Sie“ für Lehrkräfte/Eltern, an anderen
      „du“ (z. B. Zwei-Faktor-Hinweis in `timetable.html`); einheitlich
      regeln
- [ ] Einheitliche Schreibweisen: „Nutzer“/„Nutzer:innen“, „...“/„…“,
      Fehlermeldungen
- [ ] `data-testid` an Navigation, Template-Modals und Haupt-Buttons

### Neues Design: Seiten, die noch fehlen (Durchsicht 19.11.2026)

Alle Seiten mit Beispieldaten in drei Breiten (Handy, Tablet, Desktop)
fotografiert und gegen `doc/Gestaltung.md` geprüft.

- [x] Gemeinsam (erledigt): Fläche für `container-fluid white`, einfache
      Tabellen als Listenzeilen und leere Tabellen mit Satz
      (`plain_tables`), schwebende Fehlermeldungen unten neben der Seitenleiste,
      keine zweite „Karteikarte“, ruhiger Link zur Übersicht
- [ ] Noch ohne Fläche (bewusst „solid“ oder Gerät): `inactive_sus`,
      `sus_ohne_kurse`, `unterrichtsmails` (eigene Seiten mit Titel und
      Fläche wären besser), `aula_progress`, `aula_light`
- [ ] Kursbuch: das Schließen-Kreuz der schwebenden Fehlermeldung
      reagiert nicht
- [ ] `lab8`: zwei Trennlinien zwischen Feldern und Bearbeitungshistorie
- [ ] Viel genutzt, noch altes Design: `bookings` (am Handy kaputt: Titel
      bricht im Wort, Buchungen abgeschnitten), `techpost`, `jitsi`
      (alle, „Sie“, Hinweiskästen), `groups`,
      `upload_images`, `upload_files`, `email_overview`,
      `show_login_codes`, `kurslisten`, `gev`
- [ ] Verwaltung, noch altes Design: `admin`, `stats`, `email_accounts`,
      `postfaecher`, `inactive_sus`, `sus_ohne_kurse`, `dienste`,
      `techpostadmin`, `manage_calendar`, `manage_test_calendar`,
      `manage_monitor` („Sie“), `show_all_login_codes`, `lehrbuchverein`
- [ ] Zeitweise genutzt: Lab 8/9, PK5, Projekttage (Karteikarten und
      Übersichten), `anmeldung`/`anmeldungen`, `up`
- [ ] Kaputt: `agr_markup` (Knopfraster ragt rechts aus der Seite, scrollt
      seitlich), `aula_light` (`padding: 1vh 80vh`, scrollt seitlich),
      `bib_scan_isbn` (JS-Fehler ohne Buch in der Adresse, `data.book`
      ungeprüft)
- [ ] Kleinigkeiten auf fast fertigen Seiten: `manage_news` (»Artikel
      schreiben« nicht in der Titelzeile), `angebote` (Linie unter
      »Meine …« zu kurz, Suche über »Meine …«), `tests` (Tablet:
      »Eintragen« rutscht unter den Titel), `directory` (Sitzplan-Hinweis
      mit „Sie“, doppelt), `passwoerter` (Aktionen in Linkfarbe),
      `hilfe`/`impressum` (Lesebreite höchstens 980 px), `profil` (leere
      Tabelle »Schulinterne Links«), `timetable` (überlappende Stunden
      am Tablet abgeschnitten), `events` (Dialog »Neuer Termin«: Platzhalter
      mit „Sie“, gelbe Teilnehmer-Chips, »Schließen« neben »Verwerfen«)
- [ ] Nicht geprüft (im Teststack nicht erreichbar): Bibliothek-Verwaltung,
      Zeugnisse, Datentresor, Sitzplan-Seiten, Mittagessen,
      Zufallsgruppen, AGR-App

### Aufräumen

- [ ] Nicht verlinkte Seiten prüfen: `wind`, `maze`, `badges`,
      `wallpapers`, `agr_markup`, `cling-colors`, `lesson_keys_history`,
      `aula`, `logout`, `login_otp`
- [ ] Corona-Seiten (`salzh`, `salzh_protokoll`, `self_tests`) noch nötig?
- [ ] Rund 290 `console.log`-Aufrufe, u. a. jede Minute in
      `render_timespans` (`_template.html`)

## 3. Wartung

- [ ] Bot für das Zurücksetzen von E-Mail-Passwörtern (Phase 2 in
      `review/2026-11/mail-password-reset.md`): Zwei-Faktor-Anmeldung per
      App beim Mail-Anbieter einrichten, Ablauf „Passwort ändern“ im
      Kundenbereich aufzeichnen, Standort des Bots festlegen
- [ ] Schulstruktur aus `credentials.rb` in die Datenkonfiguration
      (`/data/config.rb`) verschieben: `KLASSEN_ORDER`, `KLASSEN_TR`,
      `ROOM_ORDER`, Zeiten, Schulname … – Zugangsdaten bleiben in
      `credentials.rb`. Die Produktion definiert Klassen bereits in
      `/data/config.rb` (überschreibt `credentials.rb`); dokumentieren, was
      wohin gehört, und Template/Beispieldaten entsprechend aufteilen
- [ ] Abhängigkeiten aktualisieren: Neo4j 4.4, Nextcloud-Sandbox 30,
      Bootstrap 4.4, jQuery 3.6, FullCalendar 5.1; Neo4j-Treiber ist eine
      Beta-Version
- [ ] Images mit fester Version (`nginx:stable`, `lgatica/weasyprint`);
      reproduzierbare Builds (kein `apk upgrade` im Dockerfile)
- [ ] Entwicklungswerkzeuge (`pry`, `rerun`) nicht ins Produktions-Image
- [ ] `config.rb`: `version: '3'` ist bei Compose v2 überflüssig; Container-
      Namen hängen an `--compatibility`
- [ ] Frische Installation: Ohne `INTERNAL_PATH/sso-keys/` endet jede Seite
      nach der Anmeldung mit HTTP 500 (`issue_dashboard_sso_cookie!`). Bis
      das robuster ist, steht die Erzeugung in `doc/Installation.md`
- [ ] `config.rb` reicht Argumente als Shell-String an `docker compose`
      weiter; Argumente mit Anführungszeichen oder `$` gehen kaputt
      (Array-Form von `system` verwenden)
- [ ] `config.rb` endet immer mit Exit-Code 0, auch wenn `docker compose`
      fehlschlägt (z. B. `./config.rb restart ruby` oder
      `./config.rb exec … false`). Skripte und Deploys können sich darauf
      nicht verlassen; den Exit-Code von `docker compose` weiterreichen
      (vorher prüfen, welche Aufrufer das betrifft)
- [ ] Gemfile-Kommentar zu `mustermann` passt nicht zur Versionsangabe
- [ ] `update-documentation.sh` wechselt in `../schul-dashboard/`, das zum
      Namen des Checkouts passen muss
- [ ] Repo-Hygiene: verbliebene nicht versionierte Dateien sichten
      (u. a. `audio-bot-repl.rb`, Schema-/Maze-Werkzeuge, `test-*.rb`,
      `bootstra.386/`, `gantt/`, `art/`) – committen oder löschen
- [ ] `TODO-NEUES-SCHULJAHR.md` in ein Skript überführen (mit Dump vorher,
      Trockenlauf, Bestätigung)
- [ ] Automatische, rotierende Datensicherung (siehe
      [doc/Betrieb.md](doc/Betrieb.md))
- [ ] `main.rb` (über 4000 Zeilen) entflechten: Seiten-Route und
      Datenaufbereitung pro Seite in eigene Dateien – erst nach dem
      Seiten-Smoke-Test
- [ ] Rund 96 Klassenvariablen als globaler Zustand bei 16 Puma-Threads:
      Zugriffe prüfen und, wo nötig, absichern – erst nach Tests
