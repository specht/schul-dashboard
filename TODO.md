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

## 2. UI/UX

### Fehler

- [ ] Externe Nutzer:innen hinzufügen: Steht statt einer E-Mail-Adresse etwas
      anderes im Feld (z. B. ein Gruppenname wie „Eltern 10a“), endet
      `/api/add_external_users` mit HTTP 500 (`Mail::AddressList` in
      `include/ext_user.rb`) statt mit einem verständlichen Hinweis. Kommt in
      Produktion vor.
- [ ] Umfrage beantworten: Eine Freitext-Antwort wird erst übernommen, wenn das
      Textfeld den Fokus verliert (`change`), vorher bleibt „Absenden“
      deaktiviert. Besser auf `input` reagieren (`_template.html`,
      `textarea.change(…)`).
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

### Wünsche

- [ ] Termine direkt im Stundenplan anlegen (Klick in den Kalender wie bei
      Google Kalender) für alle, die Termine erstellen dürfen – statt über
      die Seite „Termine“

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
- [ ] Sitzplan-Ansicht auf dem Handy: Namen werden mitten im Wort
      umbrochen („Musterman / n“)

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
      weißer Schrift möglich)
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

### Aufräumen

- [ ] Alte Seiten entfernen oder archivieren: `projekttage_old`,
      `projekttage_overview_old`, `projekttage_sus_old`
- [ ] Nicht verlinkte Seiten prüfen: `wind`, `maze`, `badges`,
      `wallpapers`, `agr_markup`, `cling-colors`, `lesson_keys_history`,
      `aula`, `logout`, `login_otp`
- [ ] Corona-Seiten (`salzh`, `salzh_protokoll`, `self_tests`) noch nötig?
- [ ] Rund 290 `console.log`-Aufrufe, u. a. jede Minute in
      `render_timespans` (`_template.html`)

## 3. Wartung

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
