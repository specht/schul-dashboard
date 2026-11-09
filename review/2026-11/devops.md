# DevOps-Review gyst-dashboard

Ich habe nur gelesen und nichts verändert. Nicht geöffnet habe ich `data/`, `internal/`, `logs/`, `env.rb`, `credentials.rb`, `docker-compose.yaml` und `SICHERHEIT.local.md`. Gemessen habe ich nur am laufenden Test-Stack, also mit Beispieldaten: Startlog von `schuldashboardtest_ruby_1`, Ladezeit der Gems im Container, Image-Inhalt.

## Kurzfazit

Die Basis ist solide. Ruby ist gepinnt (`ruby:3.4.10-alpine3.24`), die Dienste laufen ohne Root, Code und Eingangsdaten sind read-only gemountet, Logs rotieren, und der Test-Stack läuft isoliert im Produktionsmodus. Die größten Hebel:

1. **Startzeit**: Der Start rechnet viel Unnötiges.
   - `parse_timetable` läuft zweimal und liest dabei jedes Mal alle `/vplan/*.json` des Schuljahrs. Der Start wird deshalb bis zum Sommer immer langsamer.
   - Bei jedem Start werden alle Klassenvariablen als YAML nach `/internal/debug` geschrieben.
   - `setup()` schickt für jede Person eine eigene `MERGE`-Abfrage.
   - Beim Start laufen synchrone HTTP-Aufrufe ohne Timeout.
2. **Deployment**: Es gibt keinen Rollback-Pfad, keine Healthchecks und keine Migrationen. `setup()` arbeitet beim Start destruktiv. Eine falsche Annahme in AGENTS.md §7 (siehe unten).
3. **Backups**: Sie laufen nicht automatisch, sind nicht verschlüsselt, und die Wiederherstellung wird nicht geprüft.
4. **Neo4j 4.4**: Seit November 2025 ohne Support. Der Treiber (neo4j-ruby-driver 6.x) ist schon 5.x-fähig. Etwa 10 Cypher-Stellen und eine Neo4j-Einstellung blockieren noch.
5. **Hot Reload** mit `Sinatra::Reloader` geht, hat aber eine konkrete Falle: Die Catch-all-Route `get '/*'` verdeckt danach alle neu geladenen GET-Routen.

**Fehler in AGENTS.md §7 / Betrieb.md:** Dort steht „Nur `src/static` geändert: kein Neustart nötig“. Das gilt für die HTML-Seiten, nicht aber für JS und CSS. `compile_js`/`compile_css` (`src/ruby/main.rb:1752–1816`) bündeln `code.js`, `styles.css` und die Bibliotheken unter `include/*` in der Produktion nur beim Start. Ohne Neustart wird weiter das alte Bundle ausgeliefert.

## Deployment & Betrieb

| # | Vorschlag | Aufwand | Risiko |
|---|---|---|---|
| D1 | **`deploy.sh`** (eigenes Skript, `config.rb` bleibt unverändert), Schritte siehe unten | S–M | niedrig |
| D2 | **Images für Rollback aufheben**, siehe unten | S | niedrig |
| D3 | **Puma-Hot-Restart statt Container-Neustart**, siehe unten | M | mittel |
| D4 | **nginx-Upstream dynamisch auflösen**, siehe unten | S | niedrig |
| D5 | **Kein zweiter Ruby-Prozess parallel** (Blue/Green, Puma-Cluster), siehe unten | – | – |
| D6 | **`compile_js`/`compile_css`: altes Bundle nicht löschen**, siehe unten | S | niedrig |
| D7 | **Migrationen einführen**, siehe unten | M | mittel |
| D8 | **Healthchecks in Compose**, siehe unten | S | niedrig |
| D9 | **Stündliches Neuschreiben der Stundenpläne in den Timetable-Dienst verlegen**, siehe unten | S | niedrig |
| D10 | **`config.rb` schreibt Dateien nur bei Änderung**, siehe unten | S | sehr niedrig |

**D1 – `deploy.sh`.** Ablauf:
- Abbrechen, wenn das Arbeitsverzeichnis nicht sauber ist.
- `git fetch`, die neuen Commits anzeigen, `PREV=$(git rev-parse HEAD)` merken, `git merge --ff-only`.
- Nur bauen, wenn sich `docker/` oder `Gemfile*` geändert haben.
- `ruby` neu starten und auf `curl 127.0.0.1:8020/api/ping` warten, mit Timeout.
- Die ersten 60 s im Log nach `[ERROR]` suchen.
- Danach die Bots nacheinander neu starten, `timetable` zuletzt, weil es beim Start alles neu schreibt.
- Bei einem Fehler `git reset --hard $PREV` und erneut starten.

Beim Deployment gibt es ein grundsätzliches Problem: Der Code ist eingebunden (`./src/ruby:/app:ro`). Nach `git pull` sehen laufende Container sofort den neuen Code. Seiten (`src/static`) werden pro Request gelesen, also läuft bis zum fertigen Neustart neues HTML gegen alten Ruby-Code. Ein Bot, der in dieser Zeit abstürzt, startet wegen `restart: always` mit dem neuen Code. Daher Pull und Neustart direkt hintereinander, per Skript.

**D2 – Images für Rollback aufheben.** Vor `build` die aktuellen Images mit `docker tag …_ruby:latest …_ruby:prev` sichern. Ohne das braucht ein Rollback nach einer Gemfile-Änderung einen Neubau, und der ist wegen `apk upgrade` nicht reproduzierbar.

**D3 – Puma-Hot-Restart.**
- `docker compose kill -s SIGUSR2 ruby` behält das Listen-Socket. Neue Verbindungen warten im Kernel-Backlog, statt einen 502 zu bekommen.
- Voraussetzung: Puma direkt starten (`puma -e production -b tcp://0.0.0.0:3000 config.ru`), nicht über `rackup`. Ob der Restart über den rackup-Handler sauber neu startet, ist unsicher, deshalb erst im Test-Stack prüfen.
- Als optionale Einstellung in `config.rb`, damit die Standardausgabe byte-identisch bleibt.
- Dazu `error_page 502 504` und `proxy_read_timeout` ≥ Startzeit. Sonst sehen wartende Requests nach 60 s einen 504 statt der Neustart-Seite.

**D4 – nginx-Upstream dynamisch auflösen.** `proxy_pass http://#{PROJECT_NAME}_ruby_1:3000` wird nur beim Start von nginx aufgelöst. Wird `ruby` neu erstellt (`up -d` nach `build`) und bekommt eine neue IP, liefert nginx 502, bis es selbst neu startet. Mit `DOCKER_NETWORK_RUBY_IP` tritt das nicht auf. Abhilfe: `resolver 127.0.0.11 valid=10s; set $up http://ruby:3000; proxy_pass $up;`. Der Alias `ruby` existiert schon, dann fällt auch die Abhängigkeit von `--compatibility` weg. Das ändert die Ausgabe von `config.rb`, also eine bewusste Entscheidung oder eine optionale Einstellung.

**D5 – Kein zweiter Ruby-Prozess parallel.** Etwa 96 Klassenvariablen dienen als Cache (z. B. `@@lehrmittelverein_state_cache`, `@@ws_clients`). Zwei Prozesse würden auseinanderlaufen. Zusätzlich löscht `compile_js` beim Start `/gen/js/` komplett (`FileUtils::rm_rf`), dem alten Prozess fehlen dann seine Bundles. Erst nach dem TODO „Klassenvariablen absichern“ angehen.

**D6 – Altes Bundle behalten.** Die letzten 2–3 `compiled-*.js/css` liegen lassen. Sonst bekommen Seiten, die während des Neustarts ausgeliefert wurden, beim Laden des Bundles einen 404.

**D7 – Migrationen.** Heute gibt es nur einmalige Skripte (`mig-2021-09-05.rb`, `migrate-sitzplan.rb` …) und `setup()` bei jedem Start.
- Nummerierte, idempotente Skripte, die in `(:Migration {id})` festhalten, was gelaufen ist. Explizit im Deploy-Skript nach einem Dump ausführen.
- **Wichtig:** `setup()` löscht beim Start alle `TabletSet`s samt Buchungen, die nicht in den Eingangsdaten stehen. Fehlt die Datei, ist `parse_tablet_sets || {}` leer, und es werden *alle* gelöscht (`src/ruby/main.rb:439–451`). Bei leerer Liste abbrechen. Das ist eine kleine Änderung (S) und sollte zuerst kommen.

**D8 – Healthchecks.** `neo4j`: `cypher-shell 'RETURN 1'`. `ruby`: `curl -f localhost:3000/api/ping` (curl ist im Image). `depends_on: condition: service_healthy`. Optional einschalten, wegen der Byte-Identität.

**D9 – Stündliches Neuschreiben im Timetable-Dienst.** Heute läuft es per Host-Cron über `update-timetables.rb` → `config.rb`. Das erzeugt dabei jede Stunde `docker-compose.yaml` und `default.conf` neu und braucht Ruby auf dem Host. Besser ein Thread im Timetable-Dienst, der stündlich `{which: 'all'}` in die Queue legt. Das ist versioniert und testbar. Seit Commit 49d2caae („write files only when changed“) ist der Lauf ohnehin billig.

**D10 – Dateien nur bei Änderung schreiben.** `config.rb` soll seine Dateien nur schreiben, wenn sich der Inhalt geändert hat. Die Ausgabe bleibt byte-identisch.

## Images & Container

Das Ruby-Image ist **2,23 GB** groß und wird für jeden Ruby-Dienst einzeln gebaut, mit eigenem Tag.

| # | Befund / Vorschlag | Aufwand | Risiko |
|---|---|---|---|
| I1 | **Docker-Engine im Ruby-Image** (`apk add docker`: dockerd, containerd, CLI, ca. 180 MB). Wird nirgends genutzt, kein Socket gemountet → entfernen | S | niedrig |
| I2 | **`ruby-dev` (apk) installiert eine zweite Ruby-Version** (`/usr/bin/ruby` neben `/usr/local/bin/ruby`). Die Header bringt `ruby:alpine` selbst mit → entfernen, `build-base`/`curl-dev` behalten oder in einen Build-Stage verschieben | S | niedrig–mittel (Neubau der nativen Gems prüfen) |
| I3 | **`openjdk11-jre`** (155 MB): LibreOffice braucht für die Umwandlung DOCX→PDF (`include/zeugnisse.rb`) kein Java → testweise entfernen | S | mittel (Zeugnisse liegen nicht im Test-Stack, also von Hand prüfen) |
| I4 | **Ein Image für alle Ruby-Dienste**: `build` nur bei `ruby`, die anderen mit `image: <projekt>_ruby`. Spart Bauzeit und Tags. Ändert die Ausgabe von `config.rb` | S | niedrig |
| I5 | **`apk upgrade` / `apt-get upgrade`**: Reproduzierbarkeit gegen Patches abwägen. Mein Vorschlag: im Dockerfile lassen, aber monatlich `build --pull` (CI-Cron oder Host), dazu Trivy-Scan. Das eigentliche Problem ist, dass Images nur neu gebaut werden, wenn sich das Dockerfile ändert | S | niedrig |
| I6 | **Feste Versionen**: `nginx:stable` → z. B. `nginx:1.28-alpine`; `neo4j:4.4-community` → feste Patch-Version; `lgatica/weasyprint` hat gar keinen Tag und ist ein Fremd-Image → Version oder Digest festlegen, mittelfristig eigenes kleines Image. `MAINTAINER` ist veraltet | S | niedrig |
| I9 | `pry`/`rerun` im Produktions-Image: `main.rb:24` lädt `pry` immer, und `src/scripts/pry.rb` ist die Admin-Konsole der Produktion → `pry` **bewusst behalten**, `rerun` in die Gruppe `:development` | S | niedrig |

## Backups

Heute: nur das manuelle `dump-database.rb`, Empfehlungen in `doc/Betrieb.md`.

| # | Vorschlag | Aufwand | Risiko |
|---|---|---|---|
| B1 | **Nächtlicher Lauf per systemd-Timer/Cron** (`backup.sh` im Repo), siehe unten | S–M | niedrig |
| B2 | **Restic als Ziel**: verschlüsselt auf dem Client, dedupliziert, Rotation mit `forget --keep-daily 7 --keep-weekly 8 --keep-monthly 12 --prune`, offsite. Repo-Passwort getrennt vom Server aufbewahren (Papier oder Passwortmanager der Schulleitung). Externer Speicher nur mit AV-Vertrag | S | niedrig |
| B3 | **Wiederherstellung automatisch prüfen**, siehe unten | M | niedrig |
| B4 | **Überwachung**: Erfolg oder Fehler per Ping (Healthchecks.io o. Ä.) oder Mail. Ohne Alarm bemerkt niemand ein ausgefallenes Backup | S | – |
| B5 | Vor jedem Deployment mit Migration und vor dem Schuljahreswechsel einen Pflicht-Dump, über `deploy.sh` | S | – |

**B1 – Nächtlicher Lauf.**
- `dump-database.rb` mit Ausgabe nach stdout, durch `gzip`.
- Dazu `DATA_PATH/raw`, `INTERNAL_PATH` **ohne `debug/`**, `INPUT_DATA_PATH`, `env.rb`, `credentials.rb`.
- Der logische Dump über Bolt ist unabhängig vom Store-Format und damit zugleich der Migrationsweg zu Neo4j 5. Er ist nicht transaktional konsistent, nachts aber unkritisch.
- `neo4j-admin dump` müsste in der Community-Edition die DB anhalten.

**B3 – Wiederherstellung prüfen.**
- Monatlich, auf dem Server.
- Einen Wegwerf-Neo4j-Container starten (ohne Ruby, ohne Mail, ohne Ports) und den letzten Dump einspielen.
- Knoten- und Kantenzahlen je Label mit der Live-DB oder dem Dump-Header vergleichen.
- Auf das Ergebnis alarmieren und den Container wieder löschen.
- Echte Daten bleiben dabei auf dem Server, nie in CI.

## CI

| # | Vorschlag | Aufwand | Risiko |
|---|---|---|---|
| C1 | **`.github/workflows/test.yml`**, siehe unten | M | niedrig |
| C2 | **Prüfung der Byte-Identität automatisieren**, siehe unten | S | niedrig |
| C3 | **Dependabot** für `bundler` (`src/ruby`), `npm` (`test/e2e`), `github-actions`, `docker` (FROM-Zeilen in `docker/*`) | S | niedrig |
| C4 | **Monatlicher Lauf** (`schedule`): fängt datumsabhängige Fehler und Drift der Basis-Images ab. Dazu `trivy image` (nur berichten) | S | – |
| C5 | Test-Stack näher an die Produktion bringen: `image_bot`, `mail_bot`, `weasyprint` aufnehmen, siehe unten | S–M | niedrig |

**C1 – Workflow.**
- Trigger: `pull_request` und `push` auf master. **Kein `pull_request_target`**.
- `permissions: contents: read`, `concurrency` mit `cancel-in-progress`, Actions per SHA festlegen.
- Erst `./test.sh unit` für schnelle Rückmeldung, dann `./test.sh e2e`.
- Bei Fehlschlag `playwright-report`/`test-results` und `./test.sh logs` als Artefakt (7 Tage). Das geht nur, weil ausschließlich Beispieldaten im Spiel sind.
- Es werden keine Secrets gebraucht. Das ist für ein öffentliches Repo mit Forks ideal.
- Die Bauzeit des 2,2-GB-Images ist der Engpass: buildx-Cache (`type=gha`) oder ein wöchentlich nach GHCR gebautes Basis-Image als `cache-from`. I1–I3 machen das Image deutlich kleiner.
- Den Status-Check auf master verpflichtend machen.

**C2 – Byte-Identität prüfen.** `config.rb` mit `env.template.rb` erzeugen, je einmal mit `DEVELOPMENT=true` und `false`, `UID` normalisieren. Das Ergebnis mit eingecheckten Referenzdateien vergleichen (`test/fixtures/compose-*.yaml`, `nginx-*.conf`). So wird die Regel aus AGENTS.md maschinell geprüft.

**C5 – Test-Stack erweitern.** Ohne `image_bot` wartet `ruby` beim Start im Test-Stack 5 s auf einen DNS-Timeout (siehe Startlog).

## Abhängigkeiten & Upgrades (inkl. Neo4j 5)

**Neo4j 4.4 → 5.26 LTS bzw. 2025.x/2026.x** (lokal liegt bereits `neo4j:2026.06.0-enterprise` aus einem anderen Projekt). Aufwand M, Risiko mittel.

1. **Treiber**: `neo4j_bolt 0.5.0` verwendet `neo4j-ruby-driver 6.2.1.beta.4` (Bolt 5, `element_id` vorhanden). Die Schema-Befehle im Gem verwenden schon die 5er-Syntax (`CREATE CONSTRAINT … IF NOT EXISTS FOR … REQUIRE`). Der Haken: Die Beta-Version ist exakt festgelegt.
2. **Cypher** (≈10 Stellen):
   - `EXISTS(n.prop)` ist in 5 entfernt und wird zu `n.prop IS NOT NULL`. Betroffen: `timetable.rb:1132`, `include/stats.rb:6`, `include/message.rb:121–123`, `include/ical.rb:6`, `include/salzh.rb:22,1003`, `include/directory.rb:868,873`.
   - Musterform `EXISTS((u)-[…]->(v))` in `include/techpost.rb:6` → `EXISTS { … }`.
   - `id()` (≈17 Stellen) ist nur veraltet und funktioniert weiter.
3. **Konfiguration**: `NEO4J_dbms_logs__timezone` gibt es in 5 nicht mehr (Logging läuft über log4j2). Wegen der strikten Konfigurationsprüfung startet der Container sonst nicht.
4. **Daten**: logischer Dump aus 4.4, Laden in ein leeres 5.x, Zahlen vergleichen. Das alte Datenverzeichnis als Rollback aufheben.
5. **Ablauf**: Auf einem Branch nur die FROM-Zeile in `docker/neo4j/Dockerfile` ändern und `./test.sh all` laufen lassen. Der Test-Stack ist dafür genau richtig. Danach die Generalprobe mit einer Kopie der echten Daten auf der Dev-Instanz.

**Ruby-Gems**: aktuell (Sinatra 4.2.1, Puma 8.0.2, Rack 3.2.7). Offene Punkte:
- Festlegungen `rubyzip <3`, `prawn <2.5`, `ttfunk <1.8` begründen oder lösen.
- Der `mustermann`-Kommentar passt nicht zur Angabe `>=3.0.3` (steht schon in TODO).
- Dependabot (C3) übernimmt die laufende Pflege. Aufwand S.

**JS unter `src/static/include`** (fest eingecheckt, unsichtbar für Dependabot):

| Bibliothek | Version | Stand |
|---|---|---|
| Bootstrap | 4.4.1 | seit 2023 ohne Fixes |
| jQuery | 3.6.1 | |
| jQuery UI | 1.13.2 | |
| FullCalendar | 5.1.0 | aktuell 6.x |
| Chart.js | 2.9.4 | |
| JSZip | 3.6.0 | |
| clipboard | 2.0.0 | |
| moment | ? | nur noch im Wartungsmodus |

Vorschläge:
- Zuerst eine Inventarliste (`src/static/include/VERSIONS.md`). Aufwand S.
- Dann Patch-Updates, die nichts brechen: jQuery 3.7.x, JSZip 3.10. Aufwand S, Risiko niedrig.
- Der Wechsel Bootstrap 4 → 5 / FullCalendar 6 hängt an der UI-Entscheidung Bootstrap/Tailwind/Flowbite. Erst mit E2E-Abdeckung angehen. Aufwand L, Risiko hoch.

**Nextcloud-Sandbox 30.0.6** → aktuelle Version, nur Entwicklung. Aufwand S, Risiko niedrig.

## Entwicklung: Startzeit & Hot Reload (konkreter Plan mit Risiken)

### Wohin die Startzeit geht

Messung im Test-Stack (Beispieldaten), 32 s vom Containerstart bis „Server is up“:

| Phase | Dauer | Bemerkung |
|---|---|---|
| Containerstart, Gem-Requires, `wait_for_neo4j` | ≈7 s | davon Requires 1,7 s, gemessen |
| `collect_data` | ≈1 s | mit echten Daten das Vielfache |
| `setup()` | 3,5 s | Constraints/Indizes einzeln mit `IF NOT EXISTS` |
| SVG-Hintergründe | 15 s | 920 Dateien, nur weil `.test-stack` jedes Mal gelöscht wird; in der Produktion gecacht |
| DNS-Timeout `image_bot` | 5 s | Dienst fehlt im Test-Stack |
| `refresh_bib_data` | – | scheitert hier sofort |

In der Produktion dürften die 30–40 s vor allem hier entstehen:

1. **`parse_timetable` zweimal** (`main.rb:1044` und `:1077`, Letzteres nur zum „Patchen“). Jeder Aufruf liest alle Stundenplan-Quellen und **alle `/vplan/*.json` des Jahres** (`parser.rb:1163`). Ergebnis wiederverwenden. Aufwand S–M, Risiko mittel (Kernlogik; erst `parser_test.rb` ergänzen).
2. **YAML-Dump aller Klassenvariablen** nach `/internal/debug` bei jedem Start (`main.rb:1449–1460`). Psych ist bei großen Hashes langsam. Außerdem ist das eine unverschlüsselte Kopie aller Personendaten, die mit `INTERNAL_PATH` im Backup landet. Nur noch mit `DASHBOARD_DEBUG_DUMP=1` oder im Hintergrund-Thread. Aufwand S, Risiko niedrig.
3. **`setup()`**: einzelne `MERGE` je E-Mail-Adresse, Tablet und PEU. Ersetzen durch `UNWIND $emails AS e MERGE (:User {email: e})`. Constraints nur anlegen, wenn sie nach `SHOW CONSTRAINTS` fehlen (Änderung im Gem). Aufwand S, Risiko niedrig.
4. **Synchrone Netzaufrufe beim Start**: `image_bot/api/update_all` (Net::HTTP mit 60-s-Timeouts) und `refresh_bib_data` (Curl ohne Timeout). Letzteres blockiert in der Produktion auch einmal pro Stunde einen Request im `before`-Filter. In einen Thread verlegen und Timeouts von 2–5 s setzen. Aufwand S, Risiko niedrig.
5. **Jeder Bot führt `collect_data` aus**, weil er `main.rb` lädt. Bei `restart` laufen also sechs Prozesse gleichzeitig um die CPU. Mittelfristig das Ergebnis von `collect_data` als Marshal-Cache ablegen, mit den Änderungszeiten der Eingangsdateien als Schlüssel; Bots und Neustarts lesen ihn in Millisekunden. Aufwand M, Risiko mittel (Cache-Invalidierung).
6. **Erst messen**: Dauer jeder Phase mit `debug` ausgeben. Aufwand S. Ohne Zahlen aus der Produktion sind 1, 2 und 5 Schätzungen.
7. Im Test-Stack `.test-stack/data/gen/bg` über Läufe hinweg behalten: ≈15 s weniger pro E2E-Lauf. Aufwand S.
8. Geringer Nutzen: YJIT (`RUBY_YJIT_ENABLE=1`), bootsnap (spart weniger als 1 s).

### Hot Reload: heute

`rerun` beobachtet `/app` in **jedem** Ruby-Dienst (7 Container). Jede Änderung, auch unter `test/` oder in `email-templates/*.html`, startet alle neu. Jeder führt `collect_data` aus, und `timetable` schreibt alle Stundenpläne neu (mit echten Daten Minuten). Schon `--ignore "test/*"` hilft. Aufwand S.

### Plan mit Sinatra::Reloader (sinatra-contrib 4.2.1 ist im Bundle)

1. **Neue Datei `src/ruby/dev_reloader.rb`**, in `main.rb` *vor* den `include/*.rb` geladen (≈Zeile 99). So wird der `before`-Hook des Reloaders vor `before '*'` registriert, und alle Routen werden erfasst:

```ruby
if DEVELOPMENT && ENV['DASHBOARD_HOT_RELOAD'] == '1' && ENV['DASHBOARD_SERVICE'] == 'ruby'
  require 'sinatra/reloader'
  class Main < Sinatra::Base
    register Sinatra::Reloader
    set :reloader, true   # rackup läuft mit --env production → development? ist false
    also_reload './include/*.rb'   # Dateien nur mit def werden sonst nicht beobachtet
    dont_reload './main.rb', './parser.rb', './timetable.rb', './include/color-schemes.rb'
    after_reload do
      %w(GET HEAD).each do |verb|
        r = routes[verb] or next
        tail, rest = r.partition { |x| x[0].to_s == '/*' }
        r.replace(rest + tail)   # Catch-all wieder ans Ende
      end
    end
  end
end
```

2. **`config.rb`**: Mit einer optionalen Einstellung `DEV_HOT_RELOAD = true` setzt `ruby` die Variable `DASHBOARD_HOT_RELOAD=1` und `rerun … --ignore "include/*"`. Ohne die Einstellung bleibt die Ausgabe byte-identisch. Die Bots ignorieren `include/*` ebenfalls. Wer Bot-Code in `include/` ändert, startet den Bot von Hand neu (dokumentieren).
3. **Absicherung durch Unit-Test** (Stil `backend_rules_test.rb`): `sinatra/reloader` darf nur in `dev_reloader.rb` vorkommen, und diese Datei nur unter der dreifachen Bedingung.

**Risiken:**

- **Catch-all-Route (das eigentliche Problem)**: Der Reloader entfernt die Routen einer geänderten Datei und hängt sie beim Neuladen *ans Ende*, hinter `get '/*'` (`main.rb:3570`). Ohne den `after_reload`-Fix ist jede GET-Route einer neu geladenen Include-Datei stumm tot. POST ist nicht betroffen. Die Signatur von `after_reload` in 4.2.1 prüfen.
- **Reihenfolge allgemein**: Auch zwischen Include-Dateien ändert sich die Vorrangfolge. Bei überlappenden Mustern (`/api/x/:id` gegen `/api/x/foo`) kann sich das Verhalten ändern. Ein Test auf überlappende Routen hilft.
- **Warum nicht einfach `load`**: Ein schlichtes `load include/x.rb` (wie heute für `fragments.rb`) ist nur für die ≈10 Dateien ohne Routen sicher. In Dateien mit Routen hängt es Duplikate an, die alte Route gewinnt, und Änderungen am Routenrumpf wirken *still nicht*. Deshalb der Reloader.
- **`main.rb` nie neu laden**: Das würde alle `configure`-Blöcke erneut ausführen (`collect_data`, `setup`, Schreiben nach `/gen`, `@@ws_clients = {}`, Konstante `ES256_PRIVATE_KEY`). Das ist praktisch ein Neustart mit halb initialisiertem Zustand unter 16 Threads. Deshalb `dont_reload`; für `main.rb` bleibt `rerun` zuständig.
- **Zustand auf Klassenebene**:
  - `include/sitzplaneditor.rb:2` setzt `@@room_hours_for_klasse = {}` zurück.
  - `include/sitzplan_daten.rb:29` erzeugt einen neuen `WRITE_MUTEX` (kurzzeitig zwei Mutexe). Absichern mit `const_defined?`.
  - Top-Level-Konstanten erzeugen Warnungen.
  - `color-schemes.rb` wird nur beim Start ausgewertet, deshalb auf `dont_reload`.
- **Startcode wird nicht erneut ausgeführt**: `self.*`-Methoden (`parse_zeugnisformulare`, `determine_lehrmittelverein_state_for_all` …) werden zwar neu definiert, aber nicht neu ausgeführt. Im Log melden: „neu geladen, Startdaten unverändert“.
- **Gelöschte und umbenannte Methoden bleiben definiert**: Lokal funktioniert dann noch, was nach einem Neustart scheitert. Der Test-Stack läuft ohne Reloader, und `./test.sh all` vor jedem Push fängt das ab.
- **Threads**: `Reloader.perform` läuft unter einer Mutex, parallele Requests laufen aber weiter. Laufende Aufrufe behalten den alten Methodenrumpf. Für die Entwicklung vertretbar.

**Gewinn:** Änderungen an `include/*.rb` (49 von 59 Dateien mit Routen) wirken beim nächsten Request statt nach 30–40 s, und es gibt keinen Neustart-Sturm über 7 Container. Gesamtaufwand M, Risiko für die Produktion niedrig (dreifach abgesichert), in der Entwicklung mittel.

## Kann weg / vereinfachen

Alle Punkte mit Aufwand S:

| Was | Risiko |
|---|---|
| Docker-Engine, `ruby-dev` (zweite Ruby-Version), wahrscheinlich `openjdk11-jre` im Ruby-Image | niedrig |
| Das zweite `parse_timetable` in `collect_data` | mittel |
| Debug-YAML-Dump bei jedem Start (`/internal/debug`) | niedrig |
| `version: '3'`, `MAINTAINER`; Abhängigkeit von `_ruby_1`/`--compatibility` (über den Alias `ruby`) | niedrig |
| Sechsfacher Build desselben Ruby-Images | niedrig |
| Host-Cron für das stündliche Neuschreiben → Thread im Timetable-Dienst | niedrig |
| `src/scripts/reload-monitors.rb` („not functional yet“), `migrate-to-neo4j-4.rb`, alte `mig-*`/`migrate-*.rb` → archivieren | niedrig |
| `rerun` in allen Bots in der Entwicklung → nur `ruby` automatisch, Bots von Hand | niedrig |
| `rm_rf('/gen/js/')` → nur alte Bundles aufräumen | niedrig |
| Korrektur in AGENTS.md §7 und `doc/Betrieb.md`: Änderungen an JS/CSS im Bundle brauchen in der Produktion einen Neustart von `ruby` | keins |

## Relevante Dateien

- `config.rb`
- `docker/ruby/Dockerfile`
- `docker/neo4j/Dockerfile`
- `docker/nginx/Dockerfile`
- `src/ruby/main.rb`: setup 390–537, collect_data 681–1462, compile 1704–1816, configure 1818–1898, Dev-`before` 1977–1995, Catch-all 3570
- `src/ruby/parser.rb`: 955ff., 1163
- `src/ruby/timetable-repl.rb`
- `src/ruby/include/sitzplaneditor.rb`
- `src/ruby/include/sitzplan_daten.rb`
- `src/scripts/dump-database.rb`
- `test.sh`
- `doc/Betrieb.md`
- `AGENTS.md`
