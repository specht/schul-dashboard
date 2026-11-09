# Wartungs-Review: gyst-dashboard

Grundlage: `AGENTS.md`, `TODO.md` §2/§3, `doc/Architektur.md` und Lesen/Greppen von Code und Git. `data/`, `internal/`, `logs/`, `env.rb` und `credentials.rb` habe ich nicht geöffnet. Alle Pfade sind relativ zur Wurzel des Repositorys.

## Kurzfazit

- **Viel kann risikoarm weg: grob 6.000–8.000 Zeilen Ruby/HTML und rund 20 MB Assets.**
  - Nicht geladener Code (`projekte_old.rb`)
  - Die `_old`-Projekttage-Seiten, die schon kaputt sind
  - Corona-Reste (saLzH/Selbsttests)
  - Matrix
  - Ungenutzte JS-Bibliotheken, die jede Seite im Bundle mitlädt
  - Gut 20 nicht versionierte Dateien
- **Ich habe drei echte Fehler gefunden:**
  - **„Einladung ablehnen“ bei den Projekttagen geht ins Leere.** `projekttage.html:557` ruft `/api/reject_projekttage_invitation` auf, die Route heißt aber `reject_projektage_invitation` (`include/projekte.rb:704`, Tippfehler).
  - **Falsche Gruppen-IDs bei den Forschertagen.** Die Eltern-Gruppen heißen `"/af/…"` statt `"/ft/…"` (`include/directory.rb:644-645`, kopiert aus der Antikenfahrt).
  - **`src/scripts/reload-monitors.rb` funktioniert nicht.** Es ruft per GET auf, die Route ist aber `post '/api/force_reload_monitors'` (`include/monitor.rb:30`). Das Skript sagt selbst „not functional yet“.
- **Der größte Hebel in der Struktur ist die Seiten-Route `get '/*'` (`main.rb:3570-4129`).** Die Templates werden per `eval` im Kontext dieser Methode ausgewertet und sehen deshalb alle ihre lokalen Variablen (`user_email` kommt 143-mal vor, außerdem `poll_data`, `stored_events` …). Wer die Route zerlegt, muss diese Namen erhalten. Vorher braucht es einen Golden-Master-Test.
- **Globaler Zustand:** 98 verschiedene `@@`-Variablen. Die meisten werden nur beim Start geschrieben. Wirklich riskant sind vier Stellen, die zur Laufzeit schreiben (siehe unten).

## Kann weg

| Was | Belege für Nicht-Nutzung | Aufwand | Risiko |
|---|---|---|---|
| `src/ruby/include/projekte_old.rb` (832 Z., **nicht versioniert**) | Nicht in `main.rb:100-157` eingebunden; Datei vom 26.04.2025 | Datei löschen | keins |
| `projekttage_old.html`, `projekttage_sus_old.html`, `projekttage_overview_old.html` | Nirgends verlinkt. Sie rufen Routen auf, die nur in der nicht geladenen `projekte_old.rb` stehen (`/api/get_projekte_for_orga_sus`, `/api/update_project`, `/api/get_project_data`), sind also schon kaputt. `projekttage_sus_old` steht in `known-page-errors.json`. Letzte Commits 2024-11 bzw. 2025-05 | 3 Dateien löschen, Einträge aus `known-page-errors.json` entfernen | gering |
| **Corona/saLzH**: `include/salzh.rb` (1194 Z., letzter Commit 2023-01), `salzh.html`, `salzh_protokoll.html`, `self_tests.html` | Rolle `can_manage_salzh` ist auskommentiert (`include/roles.rb:10`), Seiten stürzen für alle ab (`known-page-errors.json`), Menüpunkt auskommentiert (`main.rb:2627`), Panels auskommentiert (`timetable.html:121,125`) | **Mittel**, weil der Code noch läuft: `timetable.rb:208` (Variable `salzh_info` wird nie benutzt, kostet aber eine Abfrage pro Monitor-Update), `:360-363`, `:1631-1659`, `:2345`; `include/directory.rb:77,190-199` (+ auskommentierte Blöcke `88-99`, `127-134`, `213-244`); `techpostadmin.html:816-817` (Variablen werden nie benutzt); `directory.html:98-140`; `timetable.html:948-950,1424-1432,1878-1880,1946`; `monitor.html:658`; Helfer in `include/user.rb:80,274,302`; `SALZH_MODE_*`-Konstanten. Teile von `jitsi.rb:86-105` (`get_homeschooling_for_user_by_dauer_salzh`) prüfen | mittel: Stundenplan-Ausgabe, deshalb Golden-Test vorher (s. u.). Nebenbei steckt in `timetable.rb:1652` ein Kopierfehler (`unless contact_person_sus.empty?` vor `salzh_sus`) |
| **Matrix**: `include/matrix.rb` (209 Z., letzter Commit 2022-04), `write-matrix-corporal-policy.rb` (src/ruby + src/scripts), `@@email_for_matrix_login` (`main.rb:684,773-775,865-866`), `login.rb:353` | Kein Aufruf aus `src/static`. `/api/fetch_matrix_groups` hat keinen Aufrufer, `store_matrix_access_token`/`matrix_hook` nur von außen. Im Template sind alle `MATRIX_*` `nil`/Beispielwerte | klein: Datei + require + Felder in `collect_data`. Der Check „duplicate matrix / nc login“ in `main.rb:774` sollte auf `nc_login` umgestellt werden | gering, vorher fragen, ob in Produktion noch ein Matrix-Server läuft |
| Klassen-Streaming/Livestream (Corona-Zeit) | `PROVIDE_CLASS_STREAM = false` (`credentials.template.rb:204`); `main.rb:1950-1966`, `main.rb:3664-3673` (`livestream`), `fixed_timetable_data` für Streaming-Tablets `main.rb:3752-3781`, `timetable.rb:1760-1770` auskommentiert | mittel | mittel. Jitsi selbst wird noch gepflegt (Commit 2026-08-31), also nur den Streaming-Teil entfernen |
| Verwaiste Seiten `agr_markup` (2021-11), `cling-colors` (2022-10), `lesson_keys_history` (stürzt ab), `aula.html` (Altversion neben `aula_light/sound/progress`), `bib_shelves`, `badges`, `ext_event*` (laut TODO liest es nur das immer leere `show_event`, `main.rb:3616`) | Kein Link in `src/static`, `main.rb` oder `include/` (per grep geprüft) | je eine Datei; bei `ext_event` vorher klären | gering |
| `/login_otp` + `login_otp.html`, `post '/api/login_otp'` (`include/otp.rb:71`) | Laut TODO §2 nicht verlinkt und nicht funktionsfähig | klein | gering |
| Unbenutzte Ruby-Methoden | Kein Aufruf gefunden: `bytes_to_str` (`main.rb:2781`), `print_adventskalender_sidepanel` (`main.rb:3202`), `good_bad_icon` (`admin.rb:85`), `get_current_ab_week` (`directory.rb:528`), `can_checkout_books`, `print_lehrbuchverein_table` (`lehrbuchverein.rb:46,50`), `parse_lab8_node`/`parse_lab9_node` (`lab8.rb:24`, `lab9.rb:24`), `print_login_ranking` (`stats.rb:91`), `this_is_a_page_for_devices` (`user.rb:296`), `urlize`/`anchorize`/`first_letter_dot`/`notify_if_different` (`parser.rb:62,74,161,626`). Außerdem `build_assignment_state`, `assignment_state_feasible?`, `assignment_bottleneck_message`, `safe_projects_for_grade` (`projekte.rb:1287-1480`, 2025/26 – wohl angefangene Zuteilungslogik, vorher nachfragen) | löschen | gering |
| Unbenutzte Variablen in der Seiten-Route | `slug`, `task`, `sha1`, `cat_slug`, `os_family`, `show_offer`, `@task_slug`, `@original_path`, `brand` nur für `{BRAND}` (`main.rb:3586-3606,4025,4031-4032`); `@@lesson_key_back_tr` wird nur zugewiesen (`main.rb:1044`) | löschen | keins (kein Template nutzt sie, per grep `#{…}` geprüft) |
| Toter Zweig für `site.webmanifest` | `main.rb:4089-4121` benutzt das undefinierte `s` und sucht eine Datei, die es nicht gibt. Das Manifest wird schon in `main.rb:3731-3735` geschrieben, endet danach aber im 404-Zweig (Status prüfen). Den Fall besser als eigene `get '/site.webmanifest'`-Route lösen | klein | gering |
| Unbenutzte Konstanten | `IMAP_SERVER`, `VOTING_CONTACT_EMAIL`, `JWT_APPAUD_AGRAPP`, `JWT_APPISS_AGRAPP`, `VPLAN_ENCODING` (`credentials.template.rb:49,108,166-167,199`) | Template bereinigen | keins |
| Admin-Exporte ohne Link | `get_all_sus_emails` (`admin.rb:568`), `get_all_entries_for_phishing_training` (`:591`), `sus_by_birthday_cutoff` (`directory.rb:1233`), `get_lesson_info_archive` (`lesson.rb:557`), `get_tablet_bookings` (`lesson.rb:435`), `print_email_letter_test` (`user.rb:855`), `set_light_aula_event` (`aula.rb:17`), `get_unterstufenparty_sus` (`user.rb:860`) | Nachfragen: in `admin.html` verlinken oder löschen. Wird von außen aufgerufen und bleibt: `website_*`, `get_frontpage_news_*`, `get_hackschule_users`, `get_workspace_users`, `klassenraum_account`, `get_all_user_ids` (`check-all-timetables.js`) | gering |
| Alte Einmal-Skripte in `src/ruby` | `mig-2021-09-05.rb`, `import-news-attic.rb` (2022), `create-cling-color-palette.rb` (2022), `dump-anmeldungen.rb` (2023), `mark-lehrbuchverein-paid.rb` (2024), `collect-nextcloud-files-from-sus.script.rb` (2023), `assign-projekttage.rb` (2025, Vorgänger von `projekttage-assign.rb`), `print-sus.rb` (2022). Keins wird referenziert | löschen; die Git-Historie reicht als Archiv | keins |
| Wrapper in `src/scripts` | Alle nach dem Muster `system("cd ../.. && ./config.rb exec ruby …")`. `reload-monitors.rb` ist kaputt (GET statt POST), `projekttage-assign.rb` hängt `ARGV` an `cd src/scripts` statt an das Skript | ein generisches `src/scripts/run-in-ruby` mit Array-Form von `system` | gering |

**Erst entscheiden** (wird nicht mehr weiterentwickelt, ist aber sichtbar):
- **Spiele „Dashboard Hackers“/„Code Crackers“/Maze:** `include/hack.rb` (330 Z.) und `include/cypher.rb` (858 Z.), inhaltlich zuletzt 2023-10 bzw. 2024-05 geändert. Dazu kommen `static/hack`, `static/cypher` (3,6 MB) und `static/gb` (7,8 MB, 31 ROMs). Beworben im HTML-Kommentar `_template.html:52-69`, Hintergrund-Sonderfall `_template.html:151,154`, Terminal-Code `code.js:1-8,187-283` (`teletype`/`append_*` werden nirgends aufgerufen). Würde man es auslagern (eigenes Repo), sparen Bundle und Image viel.
- **Phishing-Training** (`phishing.rb`, 2024-06; lädt `/data/phishing/config.rb` fest in `main.rb:81,1987`).
- **Schul-WLAN:** Menüpunkt auskommentiert (`main.rb:2646`), nur für `developer`.
- **Adventskalender:** `main.rb:2345,3090-3216`.

## Vereinfachen / zusammenlegen

1. **Empfänger-Autocomplete in Seiten-JS:** `recipients_cache`, `autocomplete_results`, `compact_address_list`, `gen_recipient_span`, `add/remove_recipient`, `update_net_recipients_list` und den `keyup`-Handler gibt es in 8 Seiten kopiert: `messages.html:65-500`, `events.html:170-690`, `polls.html:292-700`, `groups.html:106-350`, `angebote.html:90-260`, `gev.html`, `techpostadmin.html:806-900`, `salzh.html`. Der Autocomplete-Block messages↔events unterscheidet sich nur in Tab-Fokus-Details. Vorschlag: `recipient_picker.js` mit `RecipientPicker(input, list, opts)`. Die E2E-Tests für messages/events/polls gibt es schon, also zuerst dort umstellen.
2. **Zusätzliche Empfängergruppen in Ruby:** `update_antikenfahrt_groups` und `update_forschertage_groups` (`directory.rb:565-660`) sind Kopien voneinander (Kopierfehler `/af/`). Dazu `@@techpost_*`, `@@lehrbuchverein_mailing_lists`, `@@angebote_mailing_lists`, `@@projekttage_mailing_lists`. Ein generischer Builder `build_group_recipients(prefix, label, klassen, groups)` passt. Außerdem wird jede Gruppe einzeln per `#{@@antikenfahrt_recipients.to_json}` in 5 Seiten gegeben (`messages.html:74`, `events.html:185`, `groups.html:115`, `polls.html:304`, `techpostadmin.html:813`). Besser über `load_recipients` (`code.js:400`) mitliefern.
3. **lab8/lab9:** `include/lab8.rb`/`lab9.rb` (je 495 Z.) unterscheiden sich nach Umbenennen in 52 Zeilen, `lab8.html`/`lab9.html` in 46, die `_overview`-Seiten in 9. Daraus wird ein Modul mit Parameter `:lab8`/`:lab9`.
4. **PDF:** Der Weasyprint-Aufruf `Curl.post('http://weasyprint:5001/pdf', …)` steht sechsmal (`aula.rb:171,223`, `poll.rb:430,460,471`, `techpost.rb:597`) ohne gemeinsame Fehlerbehandlung. Ein Helfer `html_to_pdf(html, css: '')` in `main.rb` reicht. Prawn bleibt für `fragments/fragments.rb` (3031 Z., 9× `sanitize_pdf_with_ghostscript`).
5. **Doppelte Helfer:**
   - `gen_password_for_email`: `main.rb:631-659` und `parser.rb:328-363` sind identisch.
   - `fix_h_to_hh`: `main.rb:207` und `timetable.rb:44`.
   - `srand(...)` verstellt den globalen Zufallsgenerator in einem Prozess mit Threads (`main.rb:636`, `parser.rb:332`, `at.rb:48`, `hack.rb:96`, `cypher.rb:207,249`). Besser `Random.new(seed)`.
6. **`api_call`-Varianten** (`code.js:109-176`): `bib_api_call` und `tresor_api_call` sind dieselbe JWT-Cache-Logik mit anderem Präfix. Ein `jwt_api_call(prefix, host, token_url, …)` fasst sie zusammen. `*_no_jwt` sind Einzeiler.
7. **`timetable.rb:907-1016`:** Das Aufräumen verschobener Tablet- und Tablet-Set-Buchungen sind zwei fast gleiche Blöcke.
8. **`collect_data` parst den Stundenplan zweimal mit denselben Argumenten** (`main.rb:1044` und `:1077`). Das verlängert jeden Start. Prüfen, ob `parse_timetable` Seiteneffekte hat, dann den zweiten Aufruf streichen.
9. **Fehlerbehandlung:**
   - Zahlen: 324× `assert(`, 29× `raise 'nope'/'oops'`, 49 nackte `rescue`, nur 8× `respond(:error …)`.
   - Vorschlag: `class ApiError < StandardError` mit Status und Code, einmal `error ApiError do … end` in `Main`, und `require_…!` wirft 403 statt 500. Damit erledigen sich auch die 153 Zugangsfälle aus TODO §2.
   - Gefährlich: Der nackte `rescue` in `main.rb:2151` löscht bei *jedem* Fehler im Session-Aufbau die Session.
10. **Auskommentierter Code:** größere Blöcke in `main.rb:1093-1101,1607-1624,1914-1923,2586-2605,3325-3338`, `timetable.rb:270-286,1225-1233,1760-1770,2239-2253,2590-2611`, `parser.rb:832-844,1376-1407,1527-1577`, `poll.rb:343-398` (56 Z.).
11. **Fest eingetragene Werte in der Seiten-Route:**
    - Datums-Header in `main.rb:3572-3573` (Sommerferien 2026, Weihnachten 2026)
    - Externer Link `main.rb:~2619` (SV-Website)
    - `gen_poll_data(request.path.sub('/jitsi/', ''))` (`main.rb:3663`, kopiert; funktioniert nur, weil `poll.rb:946` selbst `/poll/` entfernt)
12. **Globaler Zustand, der zur Laufzeit geschrieben wird** (16 Puma-Threads):
    - `@@lesson_notes_for_session_user_cache`/`_last_timestamp` wird pro Seitenaufruf ohne Mutex geändert (`main.rb:3784-3797`).
    - `refresh_bib_data` setzt `@@bib_summoned_books = {}` *bevor* geladen wird, andere Threads sehen kurz eine leere Liste (`main.rb:1728`). Außerdem läuft es in jedem `before` (`main.rb:2001`).
    - `@@ws_clients` wird im WebSocket-Thread geändert und in Request-Threads durchlaufen (`bib_login.rb:10-31,72`, `monitor.rb:24`).
    - `@@public_event_config`, `@@mittagessen` (mtime-Reload) und `@@current_jitsi_rooms` sind Caches.
    - Alles andere wird nur in `collect_data` geschrieben. Das vorhandene Muster „erst komplett aufbauen, dann austauschen“ (`main.rb:1413`) dort auch verwenden.

## Struktur: Schritte für main.rb und timetable.rb (mit nötigen Tests vorher)

**Tests zuerst:**

- **T1 – Golden Master für Seiten:** Für jede Seite × Rolle aus dem Smoke-Test den HTML-Body speichern (nach Normalisierung von Zeitstempeln, SHA1-Bundles, Zufallsfarben) und vergleichen. Das ist eine Erweiterung von `pages.smoke.ts` um eine Snapshot-Option. Voraussetzung ist die fehlende feste Systemzeit (TODO §1).
- **T2 – Golden Master für `collect_data`:** `main.rb:1449-1458` schreibt schon alle Klassenvariablen nach `/internal/debug/*.yaml`. Im Test-Stack mit Beispieldaten vorher/nachher vergleichen (Unit-Test oder `./test.sh`-Schritt).
- **T3 – Golden Master für den Stundenplan-Dienst:** Mit fester Zeit `/gen/w/<id>/<woche>.json.gz` für alle Beispielnutzer erzeugen und vergleichen. `src/scripts/check-all-timetables.js` übernehmen (TODO §1).
- **T4 – API-Berechtigungsmatrix** (TODO §1), bevor `before '*'` angefasst wird. Dazu Tablet-, Monitor- und Gerätesessions im Seed.

**main.rb (4130 Z.) in kleinen Schritten**, jeder einzeln deploybar:

1. *Ohne Test-Risiko:* Feature-Routen aus `main.rb` in `include/*.rb` verschieben (nur Ortswechsel):
   - JWT-Token-Routen `3217-3261` → `include/jwt_tokens.rb`
   - Bib-Dump `3262-3277` → `bib_login.rb`
   - `hackschule`/`workspace` `3278-3343` → `include/export.rb`
   - Fotos/Klassenmemory `3344-3516` → `include/klassenmemory.rb`
   - Adventskalender `2345-2356,3090-3216` → `include/advent.rb`
   - SSO `547-612,2171-2250` → `include/sso.rb`
   - Monitor-Deep-Links `3517-3549` → `monitor.rb`

   Das sind etwa 700 Zeilen. Neue requires in `main.rb` nicht vergessen (AGENTS.md).
2. `nav_items` (`2357-2780`) und `print_*`-Helfer (`2794-3020`) → `include/navigation.rb`. Abgesichert durch T1.
3. `SetupDatabase` (`313-538`), die Hilfsfunktionen auf oberster Ebene (`38-310`) und `compile_js/css` (`1704-1817`) in eigene Dateien (`lib/setup_database.rb`, `lib/helpers.rb`, `lib/assets.rb`).
4. `collect_data` (`681-1464`) anhand der vorhandenen Abschnitte in `self.collect_users`, `collect_roles`, `collect_tablets`, `collect_timetable`, `collect_kurswahl`, `collect_mailing_lists` zerlegen, dazu `update_mailing_lists` (`1465-1703`). Abgesichert durch T2. In diesem Schritt den doppelten `parse_timetable` entfernen.
5. `before '*'`: Geräte-Token, Session-Lookup und der Pseudo-Konten-Block (`2046-2116`, sieben fast gleiche Hashes) → `PSEUDO_ACCOUNTS = { 'monitor' => {...}, … }` plus `load_session_user`. Abgesichert durch T4 und `session.spec.ts`.
6. Seiten-Route `3570-4129`:
   - (a) Den Renderer (`4043-4084`, inkl. `#{}`-Scanner) in `render_page(path, binding)` auslagern. Er bekommt das `binding` der Route, sodass Templates unverändert bleiben.
   - (b) Die `if path == …`-Kaskade (`3619-3987`) in eine Tabelle `PAGE_PREPARERS = { 'messages' => :prepare_messages_page, … }` umbauen. Die Methoden setzen **Instanzvariablen**, und in einer Übergangsphase füllt die Route daraus die bisherigen lokalen Namen (`sent_messages = @sent_messages`), damit `eval` sie weiter findet.
   - (c) Danach die Templates seitenweise auf `@…` umstellen.

   Abgesichert durch T1. Erst wenn es keine lokalen Namen mehr gibt, kann man über ERB nachdenken.

**timetable.rb (2705 Z.):** Erst T3.
1. saLzH entfernen (siehe Tabelle).
2. Den doppelten Buchungs-Purge `907-1016` in eine Methode mit Label/Relation als Parameter.
3. `update_timetables` (329-1078) in `refresh_vplan`, `build_day_events`, `purge_moved_bookings`, `unfix_moved_lesson_infos` aufteilen.
4. `update_weeks` (1125-2170, über 1000 Zeilen) entlang der vorhandenen Kommentare in `write_user_weeks` (1293-2035), `write_lesson_series` (2036-2058), `write_messages` (2059-2103), `write_homework` (2104-) aufteilen. Die Ereignis-Anreicherung (Geburtstage, Notizen, Entfall) als einzelne Funktionen `enrich_*(events)`, die sich mit kleinen Unit-Tests testen lassen.

## Abhängigkeiten (ungenutzt/veraltet)

**JS-Bundle** (`main.rb:1752-1783`, wird jeder Seite ausgeliefert):
- Nirgends benutzt (per grep geprüft):
  - `turn.min.js` (turn.js 4.1.0), `zoom.min.js`, `scissor.min.js` (beide gehören zu turn.js), `hash.js` (2012)
  - `jszip` (3.6.0, 1,2 MB inklusive Quellen und Bower-Dateien)
  - `bootstrap-autocomplete.min.js` (kein `.autoComplete(`)
  - `flowbite.js`: kein einziges `data-*-toggle`/`data-*-target`. Das CSS `flowbite.min.css` bleibt, solange Tailwind-Klassen es brauchen.
- Kaum benutzt:
  - `typewriter.js` (nur `clairvoyant.html`)
  - `odometer` (`bib_confirm`, `timetable`)
  - `print.min.js` (nur `bib_process_order.html`)
  - `zxing.min.js` (im Bundle *und* zusätzlich in `bib_scan_shelf.html:87` geladen)
  - `jquery-ui` (nur `.draggable` in `lessons.html:643`)

  Diese seitenweise einbinden statt im Bundle.
- `include/quagga.js/quagga.min.js` ist unbenutzt. `opencv.js` (11 MB, versioniert) braucht nur `up.html:92`. Das ist in Ordnung, wäre aber im Container besser aufgehoben als im Repo.
- Veraltet: jQuery 3.6.1, Bootstrap 4.4.1, FullCalendar 5.1.0, Chart.js 2.9.4, clipboard.js 2.0.0, jQuery UI 1.13.2, moment (Wartungsmodus). Das steht schon in TODO §3.

**Gems** (`src/ruby/Gemfile`):
- `pry` wird in `main.rb:24` **immer** geladen. `rerun` gehört auch nicht ins Produktions-Image (TODO).
- `http` nutzen nur `mig-2021-09-05.rb` und `write-matrix-corporal-policy.rb`, beide auf der Kann-weg-Liste. Danach entfällt das Gem.
- `wavefile` und `chunky_png` braucht nur `cypher.rb` (Spiel), `xsv` nur Beratungstermin- und Import-Skripte, `girocode` nur `send-bibliothek-zahlungsaufforderung.rb`, `prawn-svg` nur `fragments.rb`. Alle legitim, aber in eine Gruppe `:scripts` verschieben.
- Fehlen im Gemfile, obwohl required: `caxlsx` (`src/scripts/json_nodes_to_xlsx.rb`, nicht versioniert) und `paint` (`gen-maze.rb`, nicht versioniert).
- `require 'net/imap'` in `main.rb:17` braucht nur `mail-forwarder.rb`, `require 'csv'` nur `parser.rb`. Dorthin verschieben.
- `mustermann`: Kommentar und Version passen nicht zusammen (steht in TODO).

## Halbfertige Arbeit im Arbeitsverzeichnis

**Aktiv, gehört zur laufenden Test-Arbeit (behalten, committen):**
- Geändert: `test.sh`, `test/e2e/playwright.config.ts` (Projekt `screens`), `test/e2e/tests/fixtures.ts` (`ROLE_ACCOUNTS`), `pages.smoke.ts`, `test/prepare_example_data.rb` (+46 Zeilen Rollenkonten). Während meiner Analyse kamen Änderungen dazu, hier arbeitet also gerade jemand.
- Neu: `test/e2e/tests/ui-tour.screens.ts` (vom 09.11.2026), passt dazu.
- `src/ruby/test-admin-reset-teacher-2fa.rb` und `src/ruby/test-informatik-biber-export.rb` (01.11.2026): eigenständige Minitests für Code in `include/admin.rb`. Nach `src/ruby/test/unit/` verschieben, damit `./test.sh unit` sie ausführt.

**Wahrscheinlich behalten (nachfragen):**
- `src/scripts/json_nodes_to_xlsx.rb` (2026-08): Werkzeug für Dumps; `caxlsx` ins Gemfile (Gruppe `:scripts`) oder auf `write_xlsx` umstellen.
- `src/ruby/fragments/dump-assigned-projects.rb` (2026-06): liest `/internal/debug/*.yaml`, Einmal-Werkzeug für Projekttage. Behalten oder löschen. Es darf keine Ausgaben ins Repo schreiben.
- `src/ruby/email-templates/letter-page.ru.tex` (2022): russische Briefvariante, aber `print-email-letters.rb` kennt sie nicht. Einbauen oder löschen.

**Löschen:**
- `src/ruby/include/projekte_old.rb` (s. o.)
- `src/ruby/include/SUMMER-2021-TODO.md`
- `src/ruby/audio-bot-repl.rb`/`.ru` (2021/2023; nicht in `config.rb`)
- Schema-Werkzeuge von 2022: `dashboard-schema.rb`, `render-schema.rb`, `schema_renderer.rb`, `schema.dot`, `schema.svg`, `visualize-db.rb`. Die Seite `schema` nutzt ohnehin `neo4j_bolt visualize` (`main.rb:3728`).
- `migrate-sus-with-amt.rb` (2024-09)
- `/migrate-to-neo4j-4.rb` (2022)
- `/count-lines.rb`
- `/jitsi-custom-css.css` (2021)
- `src/static/include/bootstra.386/` (3,7 MB) und `src/static/include/gantt/`: kein Verweis
- `src/static/gyst.png` (2022): kein Verweis gefunden, `gyst-inverse.png` ist versioniert
- Maze-Werkzeuge `gen-maze.rb`, `parse-maze-font.rb`, `maze-font.json` und `src/static/cypher/maze/*.jpg`: nur, wenn das Spiel nicht weiterentwickelt wird
- `src/ruby/fonts/LilitaOne-Regular.ttf` und `Pacifico-Regular.ttf`: nur, wenn kein Code sie braucht (per grep nicht gefunden)

**Achtung:** `src/static/wind.html` (2022) und `src/static/wallpapers.html` (2022) sind nicht versioniert und landen lokal trotzdem im Seiten-Smoke-Test, weil der alle Dateien aus `STATIC_DIR` liest. In anderen Checkouts fehlen sie, deshalb können die Ergebnisse auseinanderlaufen. Löschen oder mit Zugangsprüfung committen.

**Grafikquellen:** `art/*.png` und `app-icon.svg` (2021) sind Quelldateien für Grafik. `art/timetable/4013017-freepik.ai` hat eine Freepik-Lizenz, die man prüfen müsste. Wenn das Repo die Quellen braucht: `.svg`-Dateien committen, Rest löschen oder außerhalb des Repos ablegen.
