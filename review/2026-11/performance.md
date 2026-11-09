# Performance-Review gyst-dashboard

## Kurzfazit (mit Zahlen)

- **Timetable-Update:** Die meiste Zeit fressen zwei **JSON-Round-Trips pro Event**, die man nicht braucht: `timetable.rb:1781` (nur SuS) und `timetable.rb:1880` (alle Nutzer, beide Modi, auch vergangene Wochen). Im Microbenchmark kosten sie zusammen ca. 0,95 ms pro SuS-Datei. Das ist mehr als `to_json` (0,21 ms), SHA1 (0,04 ms) und der Rest zusammen. Hochgerechnet auf ~86.000 SuS- und ~10.000 LuL-Dateien sind das **ca. 75–90 s von 173 s (Schätzung)**. Beide lassen sich so ersetzen, dass die Ausgabe **byte-identisch** bleibt. Mit weiteren risikoarmen Hoistings sind **~60–80 s** pro Vollupdate realistisch, mit gemeinsamer Berechnung von private/public **~40–60 s** (Schätzung).
- **Request-Pfad:** Der Hauptfresser ist die **Template-Schleife** (`main.rb:4061-4081`). Sie greift zeichenweise auf einen UTF-8-String zu (`s[i]`), und jeder Zugriff ist O(n). Gemessen mit den echten Templates: Timetable-Seite 228 ms von ~300 ms, Profil 93 von 157 ms, Login 27 von 35 ms. Dieselbe Schleife byteweise dauert **10,9 ms** statt 228 ms. 16 parallele Aufrufe der Timetable-Seite brauchen 4,7 s Wandzeit, weil sie durch die GVL nacheinander laufen.
- **Neo4j:** Die Unique-Constraints liegen auf `key`, die Queries suchen aber nach `{id: …}` (Event 22×, PollRun 38×, Group 8×, Poll 6×, Angebot 6×, WebsiteEvent 4×, Message 3×). `EXPLAIN` zeigt dafür einen **NodeByLabelScan**. Auf `updated` (inkrementelle Abfragen) gibt es keine Indizes. Pro Update laufen ~48×3 Queries für die Website-Events, davon 2/3 DELETE-Schreibtransaktionen.
- **Frontend:** Das JS-Bundle hat **2,14 MB roh / 570 KB gzip**, das CSS 429 KB / 73 KB. Beide sind content-gehasht, haben aber nur `Cache-Control: max-age=60`. Auf jeder Timetable-Seite wird eine versteckte **450-KB-PNG** (`porsche.png`) geladen, und es kommen 135 KB Inline-JS dazu.
- **Startup (Test):** Der Test-Stack braucht 31 s bis „Server is up“. Davon hängen **20 s an einem blockierenden HTTP-Aufruf an `image_bot`** (`main.rb:1877`, DNS-Fehler im Test). `parse_timetable` läuft in `collect_data` **zweimal** (`main.rb:1044` und `1077`), und das auch bei jedem Vollupdate.

## Messungen (was du gemessen hast, wie)

Alles lief gegen den Test-Stack (Port 8125, Beispieldaten, production). Dev (8025), `data/`, `logs/` und die Credentials habe ich nicht angefasst.

| Messung | Methode | Ergebnis |
|---|---|---|
| Vollupdate Test | `docker logs schuldashboardtest_timetable_1` | 750 Wochendateien in ~1 s (update_weeks); bei Testdaten dominiert der Overhead pro Woche |
| Dateigrößen `/gen/w` (Test) | `zcat` über `.test-stack/data/gen/w` | gz Ø 418 B, roh Ø 3,5 KB, max 13 KB. Pro Event werden alle Label-Varianten, `lehrer_list:"#<Set: {…}>"` (Set#to_s-Müll) und bei LuL `schueler_for_lesson` mitgeschrieben |
| Kosten pro Datei | Microbenchmark mit `ruby -e` und synthetischen, realistisch großen Events (20 SuS-Events bzw. 25 LuL-Events mit je 25 SuS) | SuS: `to_json` 0,21 ms, Round-Trip+symbolize 0,53 ms, Round-Trip 0,41 ms, SHA1 0,04 ms, gzip 0,08 ms. LuL: `to_json` 0,47 ms, Round-Trip 1,16 ms, Aufbau `schueler_for_lesson` 0,20 ms |
| `user_has_role` | Microbenchmark | 450 ns pro Aufruf (assert baut die Message-String-Interpolation bei jedem Aufruf) |
| Seiten (SuS-Login über `/api/login` und Mailpit-Code) | `curl -w %{time_total}` | `/` (Timetable) 300 ms / 191 KB; `/profil` 157 ms; Login-Seite 35 ms; 16 parallele Timetable-Aufrufe: Median 4,2 s, Wand 4,7 s |
| Template-Schleife isoliert | Echte `_template.html` + Seite, `eval` durch Konstante ersetzt | Timetable 180 KB, 178 Platzhalter: **228 ms UTF-8 vs. 10,9 ms bytes**; Profil 93 vs. 5,8 ms; Login 27 vs. 2,3 ms |
| Assets | `curl -D -` | JS 570.432 B gzip (on-the-fly), CSS 72.966 B, beide `max-age=60`; `/images/porsche.png` 449.662 B ohne Cache-Control; forkawesome woff2 91 KB |
| Indizes | `cypher-shell SHOW INDEXES` / `EXPLAIN` im Test-Neo4j | siehe Datenbank |
| Startup | `docker logs -t` | Start 00:53:52 → SSO-Key 58,9 (7 s Gems/Load) → collect_data ~1 s → setup 3,5 s → **image_bot-Fehler nach 20 s** → up 00:54:23 |

Den Mehraufwand im Dev-Modus (Seiten-Timings) habe ich nicht gemessen, er ist Code-Analyse.

## Timetable-Update: Optimierungen

Grundlage: 173 s / ~107k Dateien ≈ 1,6 ms pro Datei. Das deckt sich mit meinem Benchmark-Modell (SuS ~1,3 ms, LuL ~2,5 ms).

| # | Maßnahme | erwarteter Gewinn (Schätzung) | Risiko | Output identisch? |
|---|---|---|---|---|
| 1 | **Jitsi-Zählung ohne Round-Trip** (`timetable.rb:1877-1908`): Bei `mode == :public` ganz überspringen (dort gibt es weder `data` noch `is_event`). Wochen mit `p1 < today` überspringen. `Date.today.strftime` hoisten. Direkt auf Symbol- und String-Keys zugreifen (`h.key?(k) ? h[k] : h[k.to_s]`, nötig weil SuS-`data` String-Keys hat) | 30–50 s | niedrig | ja (gleiche Iterationsreihenfolge → gleiche `jitsi_projection.json`, wird nur von `stats.html` gelesen) |
| 2 | **`JSON.parse(_event.to_json)` bei SuS ersetzen** (`1778-1801`). Die Homework-Injektion trifft nie: `event[:lesson_key]` ist nach dem Parse nil, siehe TODO 1779. Ersatz: `e = _event.dup; e[:data] = e[:data].transform_keys(&:to_s) if e[:data].is_a?(Hash)` | 30–45 s | niedrig–mittel | ja, **wenn** die `data`-Keys zu Strings werden. Sonst bekäme das SuS-iCal plötzlich Stundenthema/HA, denn `1934ff` liest `data[:sym]` und findet heute nichts |
| 3 | **private und public einmal berechnen** (`1310`): lesson_keys, cache_indices, fixed_events, Filter einmal bauen, danach zweimal serialisieren. Für public `is_event`-Events und `:data/:per_user` auf Kopien entfernen (heute mutiert `1814-1817` per `delete`) | 15–25 s | mittel | ja (Ausnahme: `hide_from_sus` mit `.sample` in 1842ff ist ohnehin zufällig) |
| 4 | **lesson_keys pro Nutzer einmal vorberechnen** statt pro Woche×Modus (`1323-1340`, inklusive `Set.new(@@lessons[:lesson_keys].keys)` für Praktikum). Den `only_these_lesson_keys`-Filter vorziehen | 1–3 s voll; bei Teilupdates der Großteil des Fixkostenanteils | niedrig | ja |
| 5 | **`Main.get_website_events` vor die Wochenschleife** (`1264`, `include/website.rb:11-28`). Statt 3 Queries × ~48 Wochen (96 DELETE-Schreib-Tx) einmal pro Update | 1–3 s, auch bei jedem Teilupdate | niedrig | ja |
| 6 | **Rollen pro Nutzer cachen** (`is_teacher`, `is_schueler`). Rund 125 `user_has_role`-Aufrufe pro SuS-Datei (1442-1463, 1577, 1588, 1611, 1711) | ~5–6 s | niedrig | ja |
| 7 | **`schueler_for_lesson` pro lesson_key einmal bauen** (`1612-1621`) | 2–4 s | niedrig | ja |
| 8 | salzh-Block (`1632-1660`): `Set.new(@@current_salzh_status_by_email.keys)` pro Update statt pro Event; überspringen, wenn leer | klein bis mittel (je nach Daten) | niedrig | ja |
| 9 | `.dup` auf Label-/Folder-Strings weglassen (`1442-1463`) | <1 s | niedrig | ja |
| 10 | `GzOutput.stored_sha1`: In-Memory-Cache path→sha1 statt 107k `GzipReader.open` (`gz_output.rb:44`); dazu `mkpath` nur einmal pro Verzeichnis | 1–2 s | niedrig | ja |
| 11 | `parse_timetable` nur einmal in `collect_data` (`main.rb:1044` und `1077`). Wird bei jedem Vollupdate über `timetable.rb:332` aufgerufen und liest alle `/vplan/*.json` | 1–5 s (unbekannt, bitte messen) | niedrig–mittel | ja, falls `parse_timetable` deterministisch ist |
| 12 | Payload verschlanken: `lehrer_list/klassen_list/raum_list` (Set#to_s, `timetable.rb:691`), nicht genutzte Label-Varianten, `cache_index` | 10–20 % von to_json/SHA1, dazu Netz und Browser | mittel (Frontend prüfen) | **nein** |
| 13 | JSON-Fragment-Cache pro (cache_index, Variante) | 10–20 s | hoch | ja, wenn sauber |
| 14 | Parallelisieren (fork pro Wochenbereich; `jitsi`/`ical` mergen) | Faktor ≈ Kerne | hoch | nur, wenn Punkt „Achtung“ unten gelöst ist |

**Achtung, verstecktes Verhalten (wichtig für jede Umstellung):** `timetable.rb:1750-1757` löscht `:notizen` und `:booked_tablet*` aus `event[:data]`. Dieses Objekt ist aber **das geteilte `events_with_data_cache[lesson_key][offset]`** (`1605`, nur flach dupliziert in `1439`). LuL-Dateien enthalten Notizen nur deshalb, weil in `@@user_info` die Lehrkräfte vor den SuS stehen (`main.rb:153` vs. `236`). Klassenansichten (`_5a`) kommen danach und haben deshalb nie Notizen. Wer die Reihenfolge ändert oder parallelisiert, ändert die Ausgabe. Wenn man das explizit regelt (copy-on-write), bekommen die Klassenansichten Notizen, und das ist eine fachliche Entscheidung.

Weitere Nebenbefunde:
- Das SuS-iCal enthält wegen der String-Keys nie Stundenthema oder Hausaufgaben.
- Die Worker-Queue (`timetable-repl.rb:52-74`) arbeitet jeden Key einzeln ab. Mehrere wartende Keys sollte man zu einem `update(Set[...])` zusammenfassen. Ein Vollupdate (jede Vplan-Änderung, `vplan-watcher.rb:342`) blockiert alle Teilupdates für ~3 min.

## Request-Pfad

**before-Filter (`main.rb:1977-2169`), Produktion:**
- Session-Lookup (`2029-2034`) und Device-Token (`2008-2012`) sind **Schreib-Queries bei jedem Request** (`SET last_access`). Besser: nur schreiben, wenn sich `last_access` geändert hat (In-Process-Cache email→Datum), sonst reiner Read. Gemessen kostet ein API-Request mit Session ~7 ms.
- `refresh_bib_data` (`1723-1750`) läuft stündlich **synchron im Request-Thread**, mit zwei `Curl.get` ohne Timeout. Vorher werden die Hashes auf `{}` gesetzt, sodass andere Threads während des Abrufs oder nach einem Fehler eine Stunde lang leere Bib-Daten sehen. Besser: Hintergrund-Thread, Timeout, atomarer Austausch.
- `dashboard_sso` (`590-610`, `2165`) ist unkritisch. JWT wird pro Request nur unverifiziert dekodiert (µs), ES256 signiert nur bei <15 min Restlaufzeit.
- Nur im Dev-Modus: `compile_js/css` bei jedem Nicht-API-Request (`1993-1996`) mit `rm_rf` und Neuschreiben von 2,6 MB (`1787-1791`, `1811-1815`), dazu `load` von 8 Config-Dateien. Das erklärt einen Teil der Dev-Timings. Besser: nur bei geänderter SHA schreiben.

**Seiten-Route (`3570-4129`):**
- **Hauptkosten ist die Template-Schleife `4061-4081`.** `s.index`, `s.size` und `s[index+length]` arbeiten mit Zeichenindizes auf einem UTF-8-String mit Umlauten, jeder Zugriff ist O(n). Pro Platzhalter wird außerdem von vorne gesucht und im 180-KB-String in-place ersetzt. Gemessen sind das ~75 % der Seitenzeit. Lösung: byteweise arbeiten (`byteindex`/`getbyte`/`byteslice`, Ausgabe in neuen Puffer) oder das Template beim Start einmal in eine Ruby-Methode kompilieren (spart auch die ~180 `eval`-Compiles). **Achtung:** `_template.html:151` verlässt sich auf das erneute Scannen von eval-Ausgaben (`'/gen/bg/bg-#{color_scheme}.jpg'` in einfachen Quotes). Erwartung: Timetable-Seite ~300 → ~70–80 ms (Schätzung). `/mailing_lists` (1,5 s) leidet vermutlich an derselben Schleife mit großem Inhalt (nicht gemessen, kein LuL-Login im Test möglich).
- `@template ||= {}` (`4045`) ist eine Instanzvariable und wird damit **pro Request** neu gelesen; Seite und CSS ebenfalls (`4029`, `4053`). Kleiner Effekt, aber sie gehören in eine Klassenvariable.
- Pro Seite laufen `purge_missing_sessions` (1 Query pro SID, `include/login.rb:483`), `get_unread_messages` und für SuS die LessonNote-Abfrage `3786-3790` (Scan ohne Index, siehe unten). Auf der Timetable-Seite wird `print_timetable_chooser` dreimal aufgerufen.
- `/schema` (`3726-3730`) startet `neo4j_bolt visualize | dot` pro Aufruf (19 s). Besser: SVG cachen und nur auf Knopfdruck oder im Hintergrund neu erzeugen.

## Datenbank

- **Constraint auf falscher Property:** `CONSTRAINTS_LIST` (`main.rb:316-353`) hat `Event/key`, `Poll/key`, `PollRun/key`, `Group/key`, `Message/key`, `WebsiteEvent/key`, `Angebot/key`, `TextComment/key`, `AudioComment/key`. Gesucht wird aber mit `{id:}` (`{key:}` kommt 0× vor). `EXPLAIN MATCH (pr:PollRun {id:'x'})` → `NodeByLabelScan`, ebenso für Event. Lösung: Constraints `…/id` ergänzen. Vorher Duplikate prüfen, sonst schlägt `CREATE CONSTRAINT` fehl.
- **Keine Indizes auf `updated`** für die inkrementellen Abfragen in `Timetable#update`: `LessonInfo.updated` (2×, `timetable.rb:2427`, `2439`), `TextComment`, `AudioComment`, `Message` (mit `OR rt.updated`, schlecht indexierbar), `Test`, `Event`, `LessonNote` (dort zusätzlich bei jedem SuS-Seitenaufruf). Bei jedem Teilupdate laufen damit mehrere Full-Scans. Gewinn wächst mit der DB-Größe (Schätzung: 0,5–3 s pro Teilupdate).
- **N+1 / Schleifen-Queries:**
  - `get_website_events` pro Woche, mit DELETE in einem Lesepfad
  - `get_homework_feedback_for_lesson_key` pro lesson_key (`timetable.rb:1578`), besser eine Query für alle Keys
  - Startup-MERGE pro User (`main.rb:419-425`, ~1000 Round-Trips), besser `UNWIND $emails`; dasselbe für Tablets und PredefinedExternalUser
  - `purge_missing_sessions` pro SID
- Die Schreiblast pro Request (`SET last_access`) gehört ebenfalls hierher (siehe oben).

## Frontend

- **Bundle:** 2,14 MB roh / 570 KB gzip, nginx komprimiert bei jeder Auslieferung neu (Stufe 6). Die größten Teile in KB, roh/gzip:
  - `moment-with-locales` 369/75: nur `de` nötig, spart ~300 KB roh
  - `zxing` 292/87: nur für Bib-Scanner, lazy laden
  - jQuery UI 255/68, FullCalendar 246/68, Chart.js 173/53, Summernote 151/37, Flowbite 124/24, JSZip 99/28, turn.js 34
  - Seiten-spezifisch nachladen spart grob 50 % des gzip-Volumens (Schätzung).
- **Caching:** `/gen/js/compiled-<sha>.js` und `/gen/css/…` haben nur `max-age=60` (`config.rb:56`, `106`). Für content-gehashte Dateien gehört `max-age=31536000, immutable` in eine eigene `location`, dazu `gzip_static` mit vorkomprimierten Dateien. Statische Dateien unter `/` (tailwind.css, Fonts, PNGs) haben gar kein Cache-Control und verlassen sich auf heuristisches Caching.
- **Timetable-Seite:** HTML 191 KB / 37,5 KB gzip, davon 135 KB Inline-Script (bei jeder Navigation übertragen und geparst; macht außerdem die Template-Schleife teurer). Weitere Requests:
  - Bundle-JS/-CSS, `tailwind.css`, `new_design.css`, `dark.css`, `brand.png`, Hintergrund-SVG, Fonts
  - Woche (`/gen/w/<id>/<yw>.json.gz` als octet-stream + pako, `timetable.html:815`; für LuL mit `?Date.now()`-Cachebuster), `homework.json.gz`, `recipients.json.gz`
  - **`porsche.png` (450 KB) in einem versteckten Div** (`timetable.html:113`): `display:none` verhindert den Download nicht. Fix: `src` erst in `porsche()` setzen.

## Startzeit

Gemessen im Test, mit kaum Daten: 31 s bis „Server is up“.
- **20 s Hänger am `image_bot`-Aufruf** (`main.rb:1876-1881`, `Net::HTTP` mit Default-Timeouts von 60 s), synchron im `configure`. In Produktion vermutlich schnell, solange image_bot läuft; wenn nicht, blockiert er. Fix: in einem Thread mit kurzem Timeout.
- `refresh_bib_data` beim Start (`1883`): Curl ohne Timeout.
- ~7 s für Gem-Load und `wait_for_neo4j` vor `collect_data`. Viele Gems werden pauschal geladen (`pry`, prawn, write_xlsx, nokogiri, zip …); ein Teil ließe sich lazy laden (Schätzung 1–3 s).
- `collect_data`: `parse_timetable` läuft **zweimal** (`main.rb:1044`, `1077`) und liest alle `/vplan/*.json`. Mit echten Daten vermutlich der größte Parser-Block. Den zweiten Aufruf streichen, sofern die Funktion deterministisch ist.
- `setup` (`390-527`): ~70 idempotente `CREATE … IF NOT EXISTS` (~1–2 s) und ~1000 Einzel-MERGEs, besser als `UNWIND`. Danach rendert der Start Hintergründe für alle genutzten Farbschemata synchron, nur wenn sie fehlen. `determine_lehrmittelverein_state_for_all` habe ich nicht untersucht.
- Empfehlung: Debug-Zeitstempel pro Phase einbauen (collect_data-Teilschritte, setup, render, compile), dann gezielt optimieren. Für echte Daten kann ich keine Zahlen liefern; ich schätze 30–40 s → 15–20 s nach den oben genannten Fixes.
- Dazu kommt: Der Timetable-Dienst macht bei jedem Start ein Vollupdate (`timetable-repl.rb:50`), ~173 s, in denen Teilupdates warten.

Alle Dateipfade beziehen sich auf `src/ruby/` bzw. `…/src/static/`. Insbesondere: `src/ruby/timetable.rb`, `src/ruby/main.rb`, `src/ruby/gz_output.rb`, `src/ruby/include/website.rb`, `src/ruby/include/poll.rb`, `src/ruby/include/login.rb`, `src/ruby/timetable-repl.rb`, `src/static/_template.html`, `src/static/timetable.html`, `config.rb`.
