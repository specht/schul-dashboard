# TODO

Sammelliste für Verbesserungen. Stand: November 2026.

**Grundsatz:** Erst Tests, dann Änderungen. Bevor ein Bereich umgebaut oder
größer angefasst wird, muss er durch Tests abgedeckt sein – bei allem, was
Nutzer:innen bedienen, auch durch E2E-Tests (siehe
[doc/Tests.md](doc/Tests.md)). Kleine Fixes bekommen mindestens einen Test,
der den Fehler zeigt.

Für das neue Schuljahr siehe [TODO-NEUES-SCHULJAHR.md](TODO-NEUES-SCHULJAHR.md).

## 1. Tests

- [ ] Test-Umgebung: `config.rb` mit wählbarer env-Datei (`DASHBOARD_ENV`),
      konfigurierbaren Host-Ports und eigenem Projektnamen
- [ ] `test`-Gruppe im Gemfile (minitest, rack-test), `src/ruby/test/`,
      `test.sh unit|integration|e2e`
- [ ] Beispieldaten um je ein Konto pro Rolle ergänzen (Admin, Lehrkraft mit
      Klassenleitung, Schüler:in, Elternteil, Gerät)
- [ ] Erster E2E-Test (Playwright-Container): Anmeldung und Stundenplan
- [ ] Seiten-Smoke-Test: jede Seite × jede Rolle, nie HTTP 500
- [ ] Berechtigungsmatrix für alle API-Routen
- [ ] Alle Anmelde-Abläufe (inkl. Zwei-Faktor-Kombinationen) als
      Integrations- und E2E-Tests; Test-Mailpostfach (z. B. Mailpit)
- [ ] Hauptabläufe E2E auf Desktop und Handy (Tabelle in
      [doc/Tests.md](doc/Tests.md))
- [ ] Vorhandene Einzeltests (`nextcloud-client-compatibility-test.rb`,
      `puma-integration-test.rb`, `check-all-timetables.js`) übernehmen
- [ ] CI auf Pull Requests

## 2. UI/UX

### Fehler

- [ ] Klick auf das Icon in einem Button liefert `undefined`: Handler lesen
      `$(e.target).data(…)` (rund 90 Stellen) statt `e.currentTarget`,
      z. B. `.bu-launch-poll` (`_template.html`), `.btn-impersonate`
      (`admin.html`, `include/admin.rb`)
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
- [ ] Zugangsprüfungen per `require_…!` auf Seiten führen zu HTTP 500 statt
      zu Umleitung oder Hinweis (`bib_*`, `kurslisten`, `pk5`, `lab8/9`,
      `groups`, `anmeldungen`, `aula*`)

### Rückmeldung bei Laden und Fehlern

- [ ] 77 Seiten nutzen `api_call`, haben aber kein `.api_messages`-
      Element – Lade- und Fehlermeldungen erscheinen dort nie (u. a.
      `timetable`, `messages`, `polls`, `events`, `profil`, `directory`,
      `sitzplan*`, `admin`). Ein globales Element im Template wäre die
      einfachste Lösung
- [ ] `api_call` (`code.js`): Offline, Zeitüberschreitung, fehlende
      Berechtigung und Serverfehler unterscheiden und verständlich melden;
      während eines Neustarts (502) automatisch erneut versuchen
- [ ] 25 × `alert()` durch die vorhandenen Template-Modals ersetzen
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
- [ ] Jahreszahl im Fuß ist fest („© 2026“)
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

- [ ] Abhängigkeiten aktualisieren: Neo4j 4.4, Nextcloud-Sandbox 30,
      Bootstrap 4.4, jQuery 3.6, FullCalendar 5.1; Neo4j-Treiber ist eine
      Beta-Version
- [ ] Images mit fester Version (`nginx:stable`, `lgatica/weasyprint`);
      reproduzierbare Builds (kein `apk upgrade` im Dockerfile)
- [ ] Entwicklungswerkzeuge (`pry`, `rerun`) nicht ins Produktions-Image
- [ ] `config.rb`: `version: '3'` ist bei Compose v2 überflüssig; Container-
      Namen hängen an `--compatibility`
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
