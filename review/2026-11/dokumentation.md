# Doku-Review gyst-dashboard

## Kurzfazit

Für das Alter des Projekts ist die Doku gut. Die neuen Kapitel (Architektur, Development, Betrieb, Tests, AGENTS.md) sind auf dem Stand vom November 2026 und stimmen weitgehend mit dem Code überein. Es gibt drei große Schwächen:

1. **Die älteren Kapitel sind veraltet.** Betroffen sind Installation, Daten und Nextcloud (Stand 2021, mit falschen Links, Pfaden und Login-Abläufen).
2. **Die Konfiguration ist kaum dokumentiert und liegt verstreut.** Sie verteilt sich auf `env.rb`, `credentials.rb`, `/data/config.rb` und **acht weitere `/data/*/config.rb`**, die `main.rb:78-85` fest per `require` lädt. Keine Doku erwähnt diese acht Dateien. Etwa 10 Konstanten verwendet der Code, sie stehen aber weder in der Vorlage noch in den Beispieldaten.
3. **Für Endnutzer gibt es praktisch keine Hilfe.** `hilfe.html` erklärt nur das Schul-E-Mail-Konto und verlinkt dabei fest auf IONOS.

## Fehler und veraltete Stellen

**README.md**
- `:3` Der Satz „Einstiegspunkt … im Distanzunterricht“ ist Corona-Rahmung. Die Feature-Liste (`:19-25`) nennt 6 von über 30 Modulen. Umfragen, Nachrichten, Termine, Bibliothek, Zeugnisse, Projekttage und Monitore fehlen. Lizenz (GPLv3), Tests und AGENTS.md sind nicht verlinkt. (S)
- `:33` verlinkt specht.github.io. Der lokale Build stammt von 07/2024, die neuen Kapitel sind vermutlich nicht veröffentlicht. (S)

**doc/Installation.md**
- `:3-7` „docker-compose“: Heute ist das Compose v2 (`docker compose`). `config.rb` kann beides. (S)
- `:40`, `:48-52`: Laut Doku soll man den Anmeldecode aus dem Log holen (`!!!!! … => 224529`). Diese Debug-Zeile ist auskommentiert (`include/login.rb:608`). Im Development-Modus gilt fest `123456`, als zweiter Faktor `654321` (`login.rb:605`, `:157`). Development.md beschreibt das richtig. (S)
- `:106-107`: Der TTY-Hinweis ist überholt, die Skripte rufen `exec -T` auf (`src/scripts/create-nc-folders.rb`). (S)
- `:113`, Nextcloud.md `:422`/`:462`: Der Container-Name `schuldashboarddev_nextcloud_1` hängt an `--compatibility`. Besser `./config.rb exec -T nextcloud …`. (S)
- `:131-135`: `share-nc-folders.rb --srsly` bricht ab, wenn `NEXTCLOUD_INSTALL_PATH` fehlt (`src/scripts/share-nc-folders.rb:26-28`). In `env.template.rb:33` steht der Wert auf `nil`, der Sandbox-Durchlauf geht also so nicht. Das Verschieben läuft inzwischen über `nextcloud-share-move-worker.php` per `sudo php` auf dem Host. Die Beschreibung über `user_external` ist deshalb mindestens unvollständig. (M)
- Kein Verweis auf Betrieb.md für den Produktivbetrieb. (S)

**doc/Development.md**
- `:11-16` „Lokal starten“ lässt die SSO-Schlüssel aus. Ohne sie endet nach der Anmeldung jede Seite mit HTTP 500 (`main.rb:547`, TODO.md:189). Den Schritt aus Installation.md übernehmen oder verlinken. (S)
- `:41` „Port in `config.rb` auf `127.0.0.1` binden“ ist falsch: Dafür gibt es `NGINX_HOST_ADDRESS` in `env.rb` (`config.rb:19`). (S)

**doc/Daten.md**
- `:5` Den Pfad `/schul-dashboard/src/example-data/` gibt es nicht, richtig ist `src/example-data/`. (S)
- `:31`, Nextcloud.md `:6`/`:10`: Die Links `Installation.md` funktionieren in YARD nicht, sie müssen `file.Installation.html` heißen. (S)
- `:37-75`: Die Ferien gehen nur bis 2021, das Schuljahr der Beispieldaten (`config.yaml`) ist aber 2024/25. Beispieldatei und Doku-Auszug passen nicht zusammen. (S)
- `:140` Für das Kürzel der Lehrkraft gilt nicht „siehe `faecher/faecher.csv`“, sondern `lehrer/lehrer.csv`. (S)
- `:145` „Stundenzeiten in `credentials.rb`“ ist falsch. Sie stehen in `/data/config.rb` (`fix_stundenzeiten`, `HOURS_FOR_KLASSE`). (S)
- `:139` Für das Klassen-Mapping wird `credentials.rb` genannt. Tatsächlich gibt es `KLASSEN_TR` und `PARSE_KLASSE_TR` in der Vorlage, und `/data/config.rb` überschreibt sie (siehe Konfiguration). (S)

**doc/Betrieb.md und AGENTS.md**
- AGENTS.md `:182-184` sagt: „Only `src/static` changed: no restart needed.“ Das ist falsch für gebündelte Dateien. `code.js`, `styles.css`, `sound.js`, `barcode-widget.js`, `sortable-table.js` und `include/*` werden in Produktion nur beim Start gebündelt (`main.rb:1752-1830`). (S)
- AGENTS.md `:182` sagt „restart ruby“, Betrieb.md `:175` „Bots ggf. ebenfalls“. Beides widerspricht sich und ist unscharf. Die Bots (`timetable`, `mail_bot` …) laden denselben Code, also klar festlegen, welche Dienste wann neu starten müssen. (S)
- Betrieb `:276-286` verweist auf `TODO-NEUES-SCHULJAHR.md`. Diese Datei liegt nicht in `doc/` und ist damit öffentlich nicht sichtbar. (S)
- Die Skripttabelle (`:294-302`) ist unvollständig. Es fehlen `json_nodes_to_xlsx.rb`, `reload-monitors.rb`, `vplan-watcher.rb` und `nextcloud-share-move-worker.php`, außerdem rund 20 Einmal-Skripte in `src/ruby/` (`assign-projekttage.rb`, `send-bibliothek-zahlungsaufforderung.rb`, `schedule-beratungstermine*.rb` …). (M)

**doc/Tests.md**
- `:53-67` „Stand“ ist veraltet. Als Unit-Tests stehen nur Farben und Parser drin. Es gibt aber auch `backend_rules`, `frontend_rules`, `gz_output`, `image_upload` und `mail_guard`. Bei E2E stehen nur Login-Tests drin. Vorhanden sind auch `events`, `lessons`, `messages`, `polls`, `profile`, `session`, `sitzplan`, `directory_admin` und `dialogs`. (S)
- Das Playwright-Projekt `screens` (`ui-tour.screens.ts`) und `hardening.smoke.ts` sind nicht dokumentiert. Bei Letzterem nur neutral beschreiben, siehe AGENTS §1. (S)
- `:146` verweist auf `src/ruby/test-*.rb`. Diese Dateien sind nicht versioniert, öffentlich gibt es sie nicht. `:165-172` (Kandidaten) und `:181-186` (Smoke-Test als „geplant“) sind schon erledigt. (S)

**doc/Sitzplanhelfer.md**
- `:4` Der Link `../src/static/sitzplan.html` funktioniert in YARD nicht. `:50`/`:57`: Die Nummer „5.“ kommt doppelt vor. Die Anführungszeichen sind gemischt („…" und „…“). (S)
- „Geänderte/neue Dateien“ und „Umstellung“ sind PR- bzw. Migrationstext. Umbenennen in „Dateien“, die Migration nach Betrieb verschieben oder nach der Umstellung löschen. (S)

**doc/Architektur.md**
- `:86` „Die Bots sind Sinatra-Anwendungen auf 8080“ stimmt nicht für `vplan_watcher` und `mail_forwarder`, das sind reine Skripte. Im Diagramm fehlen `vplan_watcher`, `mail_forwarder` und `weasyprint`. (S)

**env.template.rb**
- `:2-4` „nach Änderung `./config.rb build`“ ist ungenau. Meist reicht `up -d`. `build nginx` braucht man nur, wenn sich `PROJECT_NAME` oder die nginx-Konfiguration ändert. `:12` Tippfehler „vtml.“. (S)

**update-documentation.sh**
- Das Skript hängt an `../schul-dashboard/` und `../schul-dashboard-doc/`. `cp -pur` lässt gelöschte Seiten liegen, `git add *` nimmt alles mit. `.yardopts` nimmt auch alle Einmal-Skripte auf. (S/M)

## Was fehlt (nach Zielgruppe)

**(a) Neue Entwickler:innen**
- Ein Glossar der etwa 95 Klassenvariablen (`@@user_info`, `@@lessons`, `@@klassen_for_shorthand` …) mit Herkunft (`collect_data`, `main.rb:681`) und Struktur. (M)
- Der Startablauf: credentials, dann `/data/*.rb`, dann `collect_data`, `compile_*` und Neo4j-Setup (`main.rb:1828-1890`), plus `DASHBOARD_CREDENTIALS` und `SKIP_COLLECT_DATA`. (S)
- Ein Neo4j-Datenmodell. Bisher gibt es das nur für den Sitzplanhelfer. `schema.dot`/`schema.svg` sowie `render-schema.rb` liegen undokumentiert herum. (M)
- Eine Modulkarte, die jeder Datei in `include/*.rb` ihre Seite und ihr Feature zuordnet. Von 58 Dateien haben nur 3 einen Kopfkommentar. (M)
- Der Hinweis, dass `include/cypher.rb` **nichts** mit Neo4j-Cypher zu tun hat (Morse/Rätsel), ebenso wenig `hack.rb`. (S)

**(b) Maintainer im Betrieb**
- Regelmäßige Jobs: Was läuft per Cron, was muss man von Hand anstoßen (Nextcloud-Einsammeln, `send-pending-emails`, Backups)? (M)
- Anbindung des Reverse-Proxys: welches Docker-Netz (`DOCKER_NETWORK_NAME`), wie nginx-proxy den Container findet. (S)
- Einrichtung des SMS-Gateways (`include/sms.rb:168`, `SMS_GATEWAY_SECRET`), von Matrix/Corporal, Jitsi-JWT, Untis-Vertretungsplan und Mail-Forwarder. Bisher steht dazu nur eine Zeile oder gar nichts. (L)
- Ein vollständiger Ablauf für den Schuljahreswechsel, einschließlich jährlich zu ändernder Konstanten: `LEHRBUCHVEREIN_JAHR`, `PK5_CURRENT_KLASSE`, `DEADLINE_*`, `ZEUGNIS_*` und die fest eingetragenen Daten in `main.rb:3572-3573`. (M)
- Störungsbehebung: SSO-Schlüssel fehlen, Port-Konflikt, Fehlerzeilen in den Eingangsdaten beim Start. (S)

**(c) Neue Schule einrichten**
- Eine Checkliste „Was ist Gymnasium Steglitz-spezifisch?“. Fest eingetragen sind u. a. die Fußzeile (`_template.html:818`), `fragments.rb` (18 Treffer, etwa „Berlin, den“), `hilfe.html` (IONOS) und `send-bibliothek-zahlungsaufforderung.rb`. (M)
- Eine Referenz aller Eingangsdateien: `lehrer.csv`, `schueler/ASCII.TXT`, `email-sub.txt`, `roles.txt` mit **Liste und Bedeutung aller Rollen**, `klassenleiter.txt`, Kurswahl, Pausenaufsichten, `tablet_sets.yaml`, `extra-dashboard-accounts.csv`, `mock/`. Daten.md beschreibt nur drei Dateien. (L)
- Die acht Modul-Konfigurationen `/data/{lab8,lab9,phishing,pk5,projekte,unterstufenparty,zeugnisse,bibliothek}/config.rb`. Sie sind Pflicht, sonst startet nichts. Dazu gehören die Hook-Methoden in `/data/config.rb` (`fix_stundenzeiten`, `fix_lesson_key_tr`, `fix_lessons_for_shorthand`, `fix_parsed_klasse` …). (M)
- Welche Module man abschalten kann und wie. Für die meisten geht das heute nicht. (M)
- Wie man Secrets erzeugt (z. B. `SecureRandom.hex(32)`) und die Warnung, dass man sie **nie wieder ändern** darf. Sie stecken in IDs (`main.rb:809`, `:972`, `:1103`, also in `/gen`-Pfaden und iCal-Links) und in den Startpasswörtern (`parser.rb:358-362`). `EMAIL_PASSWORD_SALT` muss geheim bleiben. (S)

**(d) Endnutzer:innen**
- `hilfe.html` behandelt nur das Schul-E-Mail-Konto. Die IONOS-URLs stehen fest drin (`:34`, `:126`, `:133`), obwohl es `SCHUL_MAIL_LOGIN_URL` gibt. Es fehlen: Anmeldung per Code, Zwei-Faktor/OTP einrichten, Konto wechseln, iCal-Link, Profil und Farben, Nextcloud-Ordner (der Ablauf aus Nextcloud.md wäre hier besser aufgehoben), Nachrichten und Umfragen, Elternkonten, „Was tun bei Problemen“. Getrennt nach SuS (du), Lehrkräfte und Eltern. (L)
- Die Videos sind von 2021. Mindestens als „älterer Stand“ kennzeichnen. (S)

## Konfiguration (credentials.template.rb / env.template.rb)

**Ungenutzt, also löschen** (Prüfung per grep über `src/`): `IMAP_SERVER` (`:49`), `VOTING_CONTACT_EMAIL` (`:108`), `JWT_APPAUD_AGRAPP` und `JWT_APPISS_AGRAPP` (`:166-167`), `VPLAN_ENCODING` (`:199`). (S)

**Bedingungen ohne Wirkung**: `MESSAGE_DELAY = DEVELOPMENT ? 1 : 1` (`:197`), `JITSI_LESSON_*_TOLERANCE` (`:202-203`). (S)

**Vom Code verlangt, aber weder in der Vorlage noch in den Beispieldaten definiert.** Die betroffene Funktion bricht ab, sobald sie benutzt wird:
- Zeugnisse: `NOTEN_CUTOFF`, `DEADLINE_SOZIALNOTEN` (`user.rb:606`), `SHOW_PREVIOUS_NOTEN`, `SOZIALNOTEN_CATS/KEYS/MARKS`, `DETAIL_NOTEN`, `FAECHER_SPRACHEN` (`fragments.rb`). Gehören nach `example-data/zeugnisse/config.rb`.
- `PK5_PUBLISH_FINAL_THEMA` (`pk5.rb:24`), `WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL` (`techpost.rb:53`), `EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC` (`mail-bot-repl.rb:58`), `AUFSICHT_DAUER` (`parser.rb:1312`). (M)

**Doppelt oder widersprüchlich**
- `DEVELOPMENT` und `WEBSITE_HOST` stehen in `env.rb` **und** in `credentials.rb` (`:6`, `:99`). In credentials ist `DEVELOPMENT` ein String bzw. `nil` aus der Umgebung. Den Kommentar „nicht ändern“ ergänzen. (S)
- `KLASSEN_ORDER`, `KLASSEN_TR`, `AUFSICHT_ZEIT`, `SWITCH_WEEKS`, `TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS` und `WECHSELUNTERRICHT_KLASSENSTUFEN` stehen in der Vorlage **und** in `example-data/config.rb`. Die zweite Definition gewinnt, Ruby warnt dabei. Die Werte widersprechen sich: `KLASSEN_TR` ist `8o` in der Vorlage, aber `9o` in den Beispieldaten. Dazu kommt `PARSE_KLASSE_TR` als umgekehrte Abbildung ohne Kommentar. (M)
- `ROOM_ORDER` passt nicht zu den Beispieldaten (steht schon in TODO.md). `example-data/pk5/config.rb` verweist für `PK5_CURRENT_KLASSE` auf credentials. (S)

**Falsch platziert**
- Schulstruktur und Jahreswerte gehören nach `/data`: `KLASSEN_*`, `ROOM_ORDER`, `AUFSICHT_ZEIT`, `PK5_CURRENT_KLASSE`, `LEHRBUCHVEREIN_JAHR`, `DEADLINE_*`, `ZEUGNISKONFERENZEN`, `GROUP_AF/FT_ICONS`, `TABLET_COLORS`.
- Code in der Konfiguration: der Block `Mail.defaults` (`:56-68`), `MAILING_LIST_FORWARDER_ACCOUNTS` mit doppeltem Hash und die Methode `override_email_login_recipient_for_chat` (`:248`).
- Corona-Altlasten: `WECHSELUNTERRICHT_*`, `SWITCH_WEEKS` mit Daten von 2021, `EXCLUDE_FROM_SELF_TEST_REPORT`, `PROVIDE_CLASS_STREAM`, `STREAMING_TABLET_*`, `JWT_*_STREAM`. (M bis L, deckt sich mit TODO.md §3)

**Ohne jeden Kommentar** (Auswahl der wichtigsten):
- `DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST`: sicherheitsrelevant, bisher nur in AGENTS.md erklärt.
- `MAX_LOGIN_TRIES`, `COOKIE_EXPIRY_TIME`, `MAINTENANCE_MODE`, `LOGIN_STATS_D`, `GEN_IMAGE_WIDTHS`.
- Alle `MATRIX_*`, `JWT_*`, `BIB_HOST`, `DATENTRESOR_*`, `SMS_*`, `WEBSITE_READ_INFO_SECRET`, `SCHOOL_WEBSITE_API_URL`, `UNTIS_VERTRETUNGSPLAN_*`, `MONITOR_*_DEEP_LINK`, `KLASSENRAUM_ACCOUNT_DEEP_LINK_CODE`, `SEMI_PUBLIC_LINKS`, `DEMO_ACCOUNT_*`, `FOTO_PASSWORD`, `FACH_CONSOLIDATE_FOR_VERTEILER`, `VERTEILER_*`.

Vorschlag: die Vorlage in Abschnitte gliedern (Pflicht / Secrets / Mail / Integrationen je Modul / optional / veraltet) und jede Konstante mit einer Zeile kommentieren. (M)

**env.template.rb**
- Die optionalen Schalter aus `config.rb:17-22`, `:160`, `:271`, `:288` fehlen: `NGINX_HOST_ADDRESS`, `NGINX_HOST_PORT`, `PUBLISH_DEV_PORTS`, `COMPOSE_FILE`, `NGINX_CONFIG_FILE`, `CREDENTIALS_FILE`, `EXTRA_SERVICES`, `RESTART_SERVICES`. Als auskommentierte Beispiele aufnehmen. (S)
- `DOCKER_NETWORK_NAME` hat keinen Kommentar. Dass `NEXTCLOUD_SANDBOX_INSTALL_ADMIN_PASSWORD` gleich `NEXTCLOUD_PASSWORD` in credentials sein muss, steht nirgends. Ebenso fehlt der Hinweis, dass `WEB_ROOT` in credentials zu `NGINX_HOST_PORT` passen muss. (S)

## Code-Dokumentation: wo Kommentare und Überblick am dringendsten fehlen

1. **Template-Auswertung**, `main.rb:~4060-4115`. Jedes `#{…}` geht per `eval` durch, mit Klammerzählung. Das ist der überraschendste Mechanismus im Projekt. Nötig ist ein Blockkommentar zu Regeln, Fehlerverhalten und Sicherheit. (S)
2. **`get '/*'`**, `main.rb:3570` ff. Mehrere hundert Zeilen Datenaufbereitung pro Seite, dazu fest eingetragene Daten im Header (`:3572-3573`). Ein Abschnittskommentar pro Seite und eine Liste, welche Seite welche Variablen setzt. (M)
3. **`collect_data`**, `main.rb:681` bis etwa 1400: jede `@@`-Variable mit Struktur und Beispiel. (M)
4. **`include/login.rb`**: 1137 Zeilen, 25 Kommentarzeilen. Code, Tag, zweiter Faktor, Session und Gerät als Zustandsautomat beschreiben. Sicherheitskritisch. (M)
5. **`timetable.rb`** (2705 Zeilen): Welche Dateien entstehen unter `/gen`, mit welchem Format, und wann werden sie neu geschrieben? (M)
6. **`include/roles.rb`** (70 Zeilen, 1 Kommentar): Bedeutung jeder Rolle und jedes Übergangs. (S)
7. **`fragments/fragments.rb`** (3031 Zeilen, Prawn-PDFs für Zeugnisse u. a.): Kopfkommentar, wer es aufruft, was schulspezifisch ist. (S)
8. **`include/projekte.rb`** (2087 Zeilen, 27 Kommentare), **`share-nc-folders.rb`** (1299 Zeilen, 32 Kommentare, startet PHP auf dem Host), **`include/directory.rb`**. (M)
9. **`Neo4jGlobal`** ist dreifach definiert (`main.rb:227`, `stats-bot-repl.rb:10`, `mail-bot-repl.rb:12`). Kommentieren oder zusammenführen. (S)
10. **`code.js` `api_call`** und die Template-Helfer: Verhalten und Fehler-Vertrag dokumentieren. (S)
11. Ein Kopfkommentar für alle `include/*.rb` (bisher haben ihn 3 von 58). (M)

## Kann weg / zusammenlegen

- **AGENTS.md ↔ Development.md „Konventionen“ ↔ Architektur „Daraus folgt“**: Die Regeln stehen dreimal da. AGENTS.md sollte die einzige Quelle der Regeln sein, `doc/` erklärt nur das Warum und verlinkt. Die Sprachaufteilung ist an sich vertretbar, Agenten lesen beides. Bei einem deutschsprachigen Team und deutschem Code-Kontext wäre AGENTS.md auf Deutsch aber konsequenter. Wichtiger als die Sprache ist, die Duplikate abzubauen. (S)
- **Tests.md „Stand“, „Noch offen“, „Reihenfolge“ ↔ TODO.md §1**: Den Plan nur in TODO.md führen. Tests.md beschreibt nur noch, wie man Tests ausführt und schreibt. (S)
- **TODO-NEUES-SCHULJAHR.md** in Betrieb.md als Checkliste aufnehmen (mit Dump, Cypher, Jahreskonstanten, Nextcloud-Archiv), danach löschen oder durch ein Skript ersetzen (steht schon in TODO.md). Die Cypher-Zeile für „Antikenfahrt“ ist schulspezifisch. (S)
- **Installation.md**: Den Teil Dev-Start mit Development.md zusammenlegen. Den Nextcloud-Teil nach Nextcloud.md verschieben. (M)
- **Nextcloud.md**, Abschnitt „Ablauf/Beispiel“: Der Nutzerteil gehört in die Endnutzer-Hilfe, die langen Log-Ausgaben können weg. (S)
- **Sitzplanhelfer.md**: „Umstellung“ und „Geänderte Dateien“ streichen oder kürzen. (S)
- **YARD-API-Doku**: Die Code-Kommentare sind so dünn, dass sie kaum Nutzen bringt. Nur die Markdown-Kapitel veröffentlichen (z. B. über GitHub Pages oder Actions).rb`. (S)
- Nicht versionierte Altdateien (`count-lines.rb`, `migrate-to-neo4j-4.rb`, `jitsi-custom-css.css`, `include/SUMMER-2021-TODO.md`, `src/ruby/test-*.rb`) sichten, wie in TODO.md §3 vorgesehen. (S)

## Vorschlag für eine Doku-Struktur

```
README.md            Kurzbeschreibung, Feature-Liste (aktuell), Links, Lizenz
AGENTS.md            nur verbindliche Regeln (eine Quelle), Links auf doc/
TODO.md              einzige Planungsliste (inkl. Testplan)
doc/
  README.md          Index nach Zielgruppe
  Schnellstart.md    Dev-Instanz in 10 Minuten (aus Installation + Development)
  Architektur.md     + Startablauf, Klassenvariablen-Glossar, Neo4j-Modell
  Development.md     Alltag, neue Seite/Route, Fallstricke (Template-eval)
  Tests.md           nur „wie“
  Konfiguration.md   NEU: env.rb / credentials.rb / /data/config.rb / /data/*/config.rb,
                     Tabelle aller Konstanten (Pflicht/optional/Modul/veraltet)
  Daten.md           alle Eingangsdateien + Rollenliste
  Neue-Schule.md     NEU: Checkliste Einrichtung + schulspezifische Stellen
  Betrieb.md         Produktion, Proxy, Updates, Backups, Cron-Jobs, Schuljahreswechsel
  Integrationen.md   NEU: Nextcloud (Admin-Teil), Jitsi, Matrix, SMS, Untis, Mail-Forwarder
  Module/            Sitzplanhelfer.md, später Zeugnisse, Projekttage, Bibliothek …
src/static/hilfe.html  Endnutzer-Hilfe: Anmeldung/2FA, Profil, iCal, Nextcloud,
                       Nachrichten/Umfragen; getrennt nach SuS/Lehrkräfte/Eltern;
                       Werte aus SCHUL_MAIL_* statt fester IONOS-URLs
```

Reihenfolge: zuerst die falschen Stellen korrigieren (S). Dann `Konfiguration.md` mit der bereinigten Vorlage (M). Danach `Neue-Schule.md` und die Endnutzer-Hilfe (L).
