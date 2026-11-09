# Monitoring-Review gyst-dashboard

## Kurzfazit

Heute fällt ein Problem fast nur auf, wenn sich jemand meldet („Stundenplan ist leer“, „Mail kam nicht an“). Es gibt **keinen Healthcheck außer `/api/ping`**, keine „letzter erfolgreicher Lauf“-Marker, keine Statusseite und keinen Alarm. Die einzige Ausnahme: Scheitert eine Verteiler-Mail, bekommt der Maintainer eine Kopie (cc). Mehrere Ausfälle bleiben **still**: Der Sende-Thread des Mail-Forwarders kann sterben, ohne dass der Prozess endet. Der Mail-Bot kann an einer einzelnen fehlerhaften Mail für immer hängen bleiben. Der Worker-Thread vom Einladungs- und vom Statistik-Bot kann sterben, und Aufträge landen danach nur noch in der Warteschlange. Der vplan-watcher schreibt bei Teil-Fehlern trotzdem seinen Zeitstempel.

Für eine Schule genügt etwas Kleines:
1. Jeder Dienst schreibt Heartbeat-Dateien nach `/internal/status/`.
2. Eine `/api/health` pro Dienst.
3. Eine Admin-Statusseite.
4. Ein Watchdog, der bei Zustandswechsel per `deliver_mail` alarmiert.
5. Ein externer Uptime-Check als Totmannschalter.
6. Eine Log-Zeile pro Request mit Dauer, Status und Rolle.

Docker-Healthchecks kommen als optionale Einstellung in `config.rb` dazu.

**Doku-Korrektur nötig:** `doc/Betrieb.md` sagt „Jede Zeile der Ruby-Dienste beginnt mit Datum und Uhrzeit“. Das gilt aber nur für `debug`/`debug_error`. Viele Stellen schreiben direkt mit `STDERR.puts` und haben weder Zeitstempel noch `[ERROR]`: vplan-watcher, mail-forwarder, alle Bots, die `rescue`-Zweige in `timetable.rb` (Zeilen ~2331–2347) und `trigger_update` und Verwandte in `main.rb:2306–2340`. Der empfohlene `grep` findet deshalb z. B. Fehler aus dem Stundenplan-Update nicht.

## Was heute erkennbar ist – und was nicht

| Ausfallart | Wie bemerkt? | Lücke |
|---|---|---|
| `ruby` down/Neustart | nginx zeigt `neustart.html`, die `/api/ping` abfragt; vorgelagerter Proxy | Kein Alarm. `/api/ping` prüft nur „main.rb geladen“, nicht Neo4j. Läuft `ruby` dauerhaft in einer Restart-Schleife, sieht man nur die Neustartseite. |
| Ganzer Server/nginx down | Nutzer:innen melden es | Kein externer Check. |
| Bot-Container crasht (`restart: always`) | `./config.rb ps` (Restart-Zähler), Docker-Log | Niemand schaut hin; kein Healthcheck. |
| Stundenplan seit Stunden nicht aktualisiert | Logzeile `<<< Finished updating … in X s` (`timetable-repl.rb:31`) | Kein Marker für den letzten Erfolg. Fehler aus `update_timetables` landen als nacktes `STDERR.puts e` ohne Zeitstempel und Backtrace. Ein toter Worker-Thread fällt nicht auf. |
| Vertretungsplan veraltet | `/vplan/timestamp.txt`; der Monitor zeigt `vplan_timestamp` (`timetable.rb:229`) | Man kann nicht unterscheiden: Untis hat nichts Neues veröffentlicht, oder der Watcher ist kaputt. Es gibt kein „zuletzt geprüft“. `loop do` (`vplan-watcher.rb:345`) hat kein `rescue`, jeder HTTP-Fehler crasht den Prozess. Fehlende Einzelseiten führen nur zu `WARNING` (`:267`), danach wird trotzdem der Zeitstempel geschrieben (`:340`): Der Teilplan gilt dann als aktuell. |
| Mail-Queue (Unterrichts-Mails) hängt | Lehrkräfte sehen „nicht gesendet“ (`ts_sent` nil) | Ausgelöst wird nur über `send-pending-emails.rb`, also über einen Host-Cron, der nicht dokumentiert ist. Fällt der Cron weg, stauen sich die Mails still. `Thread.abort_on_exception = true` plus eine Mail, die z. B. zu einem gelöschten Schüler gehört (`@@user_info[sus_email]` ist nil), führt zu Crash, Neustart, Crash beim nächsten Lauf: Diese eine Mail blockiert alle. |
| Verteiler-Forwarder scheitert | Eine einzelne Mail scheitert: Mail an den Absender mit cc an den Maintainer, dazu `recipients.yaml.failed` | Ist SMTP ganz weg, scheitert auch die Hinweis-Mail (`mail-forwarder.rb:290`) und t2 stirbt. t1 läuft weiter, `t1.join` blockiert, der Prozess lebt also: **Mails werden angenommen und aus dem Postfach gelöscht, aber nie verschickt.** IMAP-Fehler beenden t1, das `join` wirft und der Prozess startet neu (nur im Docker-Log sichtbar). |
| Einladungs- oder Statistik-Bot | – | `perform_update` ohne `rescue` und ohne `abort_on_exception`: Der Worker stirbt still, `/api/send_invites` füllt nur noch die Queue. |
| Platte voll | – | Keine Prüfung. Die Docker-Logrotation ist optional, Rotation der nginx-Logs nur per Doku. Neo4j-Store, `/raw` und `/mails` wachsen ohne Grenze (`.archived` wird nie gelöscht). |
| Neo4j langsam | Nutzer:innen merken es | Keine Zeitmessung der Queries. Community 4.4 hat kein `query.log`, Heap und Pagecache sind nicht konfiguriert. GC-Pausen stehen nur in `LOGS_PATH/neo4j/debug.log`. |
| Zertifikat | Browser-Warnung | Liegt beim externen Proxy (acme-companion); kein Ablauf-Check. |
| Backups | – | Noch nicht automatisiert (TODO). Kein Nachweis „letzter Dump OK“. |
| Langsame Requests/500er | `dump_errors` von Sinatra (`- Klasse - Nachricht`); nginx-`$request_time` | Kein Status und keine Dauer im Ruby-Log, keine Request-ID, keine Aggregation. Erwartbare Fehler (falscher Code, `assert` auf Seiten, laut Smoke-Test 153 Fälle) kommen ebenfalls als 500 und machen echte Fehler unsichtbar. |

## Vorschläge, priorisiert

**1. Heartbeat-Dateien „letzter Erfolg/letzter Fehler“** – Nutzen hoch, Aufwand S, Risiko gering.
Ein kleiner Helfer, z. B. `include/status.rb`, ohne Abhängigkeit von `main.rb`, damit `vplan-watcher.rb` ihn auch laden kann. Signatur etwa `Status.ok!(name, extra)` und `Status.error!(name, e)`. Er schreibt atomar (`.tmp` + `rename`, wie schon bei `neustart-looks.json`) nach `/internal/status/<dienst>.json`, mit Feldern wie `{ok_at, error_at, error_class, duration_s, files, queue}`. Das Verzeichnis ist `/internal` und **nicht** `/gen`, denn `/gen` liefert nginx öffentlich aus. `/internal` ist in allen Ruby-Diensten beschreibbar gemountet. Aufrufstellen:
- `TimetableRepl.perform_update`
- `perform_refresh`: zusätzlich `checked_at` bei jedem Durchlauf, auch ohne Änderung, damit „geprüft“ und „neu“ unterscheidbar sind
- `MailBotRepl.perform_update`
- beide Forwarder-Threads, je eine Datei
- `InvitationRepl` und `StatsBotRepl`
- das Backup-Skript auf dem Host: schreibt `INTERNAL_PATH/status/backup.json` mit Größe und Knotenzahl

**2. Stille Tode verhindern** – Nutzen hoch, Aufwand S, Risiko gering, aber vorher Tests.
- `vplan-watcher.rb`: `rescue StandardError` in der Schleife, dann `Status.error!`. Fehlende Seiten als Fehler werten und den Zeitstempel dann **nicht** schreiben.
- `mail-forwarder.rb`: Der Thread-Körper bekommt `begin/rescue`, und die Hinweis-Mail ein eigenes `rescue`. Alternativ `Thread.abort_on_exception = true`, damit Docker neu startet.
- `mail-bot-repl.rb`: Fehler pro Mail abfangen und loggen, die Mail markieren (`m.error`) und überspringen, statt den ganzen Prozess zu beenden.
- Invitation- und Stats-Bot: `rescue` im Worker.
- `trigger_*` in `main.rb`: `open_timeout`/`read_timeout` kurz setzen und `debug_error` statt `STDERR.puts e`.

**3. `/api/health` pro Dienst** – Nutzen hoch, Aufwand S–M, Risiko gering.
- **ruby**: in `config.ru` neben `/api/ping`, also ohne den before-Filter. Prüft:
  - Neo4j `RETURN 1` mit gemessener Latenz und Timeout
  - freien Platz unter `/gen`, `/raw`, `/internal` (`df -P` als Array-`system`/`IO.popen`)
  - das Alter der Heartbeat-Dateien

  Öffentlich nur `200 ok` bzw. `503 degraded` ohne Details. Details nur auf der Admin-Seite. `/api/ping` bleibt unverändert für `neustart.html`.
- **Bots auf 8080**: `get '/api/health'` mit `worker_alive` (`@@worker_thread.alive?`), `@@queue.size`, `future_queue.size` und dem letzten Erfolg. 503, wenn der Worker tot ist.
- **vplan_watcher und mail_forwarder** haben keinen HTTP-Server. Für sie reicht das Alter der Heartbeat-Datei.

**4. Admin-Statusseite** – Nutzen hoch, Aufwand M, Risiko gering.
Neue Seite `src/static/status.html` mit `#{this_is_a_page_for_logged_in_admins}` als erster Zeile, dazu `.api_messages` und `POST /api/admin_status`. Gezeigt wird eine Ampel pro Dienst, mit diesen Spalten:
- Alter des letzten Erfolgs, letzter Fehler (Klasse, Zeit)
- Queue-Längen: `Mail` mit `ts_sent IS NULL AND ts < now-15min`; Anzahl `/mails/*/recipients.yaml`, `*.failed`
- Alter von Vplan-Prüfung und Vplan-Inhalt
- Neo4j-Latenz
- Platz auf der Platte
- Zertifikat, Tage bis zum Ablauf: Ruby-`OpenSSL::SSL::SSLSocket` zu `WEBSITE_HOST:443`. Falls Hairpin-NAT das verhindert, über den externen Check.
- Alter des Backups
- Top-Fehler der letzten 24 h (siehe Logging)

Keine personenbezogenen Daten, nur Zahlen. Ein E2E-Test mit Admin-Rolle gehört dazu.

**5. Watchdog mit Mail-Alarm** – Nutzen hoch, Aufwand M, Risiko mittel (Alarm-Spam).
Ein Thread in **einem** Dienst, z. B. `stats_bot`, oder optional ein eigener Dienst `watchdog`. Er wertet alle 5 min dieselben Checks wie die Statusseite aus (gemeinsamer Code). Schwellen beachten die Schulzeit, z. B. Vplan nur Mo–Fr 6–16 Uhr älter als 60 min. Gemailt wird nur bei **Zustandswechsel** ok→fail und fail→ok, plus eine Erinnerung alle 24 h; der Zustand liegt in `/internal/status/alerts.json`. Versand über `deliver_mail` an `WEBSITE_MAINTAINER_EMAIL`. **Dev-Guard:** Die Mail geht zwar nur an die Positivliste, aber auf der Dev-Instanz wären fast alle Checks rot (kein Untis, kein Forwarder), und der Maintainer bekäme Spam. Deshalb nur mit `ENABLE_ALERTS = true` in `env.rb` scharf schalten, Standard aus; in DEVELOPMENT nur loggen. Scheitert der Alarm selbst (SMTP down), nur `debug_error`.

**6. Externer Totmannschalter** – Nutzen hoch, Aufwand S, Risiko gering.
Ein externer Dienst (selbst gehostetes healthchecks.io/Uptime Kuma, z. B. auf einem anderen Schulserver) prüft `https://…/api/health` alle 5 min. Nur er erkennt „Server, Proxy oder SMTP ganz weg“. Optional pingt der Watchdog dort zusätzlich eine Heartbeat-URL. Das deckt auch ab, dass der Watchdog selbst tot ist.

**7. Docker-Healthchecks in `config.rb`** – Nutzen mittel, Aufwand S, Risiko gering.
`ENABLE_HEALTHCHECKS` als optionale Einstellung. Ohne sie wird nichts gesetzt, die erzeugten Dateien bleiben byte-identisch. **Wichtig:** Der Healthcheck muss *nach* dem Klonen der Dienste per `YAML.load(…to_yaml)` gesetzt werden, also im Block vor `File::open(COMPOSE_FILE_PATH…)`. Sonst erben alle Bots den Check von `ruby` mit Port 3000. Skizze:

```ruby
if defined?(ENABLE_HEALTHCHECKS) && ENABLE_HEALTHCHECKS
    hc = lambda { |cmd, start| { :test => ['CMD-SHELL', cmd], :interval => '60s',
        :timeout => '10s', :retries => 3, :start_period => start } }
    s = docker_compose[:services]
    s[:ruby][:healthcheck] = hc.call('curl -fsS http://localhost:3000/api/ping', '10m')
    [:timetable, :mail_bot, :stats_bot, :invitation_bot, :image_bot].each do |k|
        s[k][:healthcheck] = hc.call('curl -fsS http://localhost:8080/api/health', '15m') if s[k]
    end
    s[:vplan_watcher][:healthcheck] = hc.call('find /internal/status/vplan_watcher.json -mmin -10 | grep -q .', '5m')
    # mail_forwarder analog; neo4j: cypher-shell 'RETURN 1'
end
```

`curl` ist im Ruby-Image. `start_period` großzügig wählen, denn `collect_data` und das volle Stundenplan-Update brauchen mit echten Daten Minuten. Hinweis für die Doku: `restart: always` startet *unhealthy*-Container **nicht** neu. Der Healthcheck dient der Sichtbarkeit (`./config.rb ps`) und dem Watchdog. Kein Autoheal einbauen, das riskiert Restart-Schleifen beim langen Start. Nach der Änderung beide Varianten (Dev und Produktion) per Diff prüfen.

**8. Neo4j und Platte** – Aufwand S.
- Heap und Pagecache als optionale Einstellung setzen.
- `debug.log` auf `stop-the-world pause` prüfen, z. B. mit `grep`.
- Alte `/mails/*/*.archived` und `mail` nach N Tagen löschen; das ist auch eine Frage des Datenschutzes.

## Logging: konkrete Verbesserungen

1. **Eine Zeile pro Request statt am Anfang.** Statt `debug "[nc_login|email] GET /path"` (`main.rb:2168`, also bevor Status und Dauer bekannt sind) eine Rack-Middleware in `config.ru` vor `map '/'`, oder `after '*'`: Die after-Filter von Sinatra laufen auch nach Exceptions, mit Status 500. Format, das zum bestehenden `grep` passt:
   `2026-11-09 08:15:02 [req] id=3f9a2c role=lehrer POST /api/send_email 200 87ms db=4/31ms`
   - `role` (`lehrer`/`sus`/`eltern`/`admin`/`tablet`/`monitor`/`anon`) statt E-Mail oder nc_login; zur Korrelation höchstens ein kurzer HMAC der User-ID.
   - Route-Muster aus `env['sinatra.route']` statt Pfad mit IDs (gruppierbar, ohne Tokens oder Tags).
   - `db=` zählt Queries und deren Gesamtzeit über ein `prepend` auf `Neo4jBolt#neo4j_query`. Queries über 500 ms extra loggen, mit der ersten Zeile der Query, **ohne** Parameter.
2. **Request-ID**: nginx-`$request_id` per `proxy_set_header X-Request-Id` durchreichen und ins `log_format` aufnehmen, zusammen mit `$upstream_response_time`. Das ändert die erzeugte nginx-Konfiguration bewusst; danach `build nginx`. Ohne Header erzeugt die Middleware selbst eine ID. Die ID in der 500-Antwort zeigen, dann können Nutzer:innen sie melden.
3. **Alle `STDERR.puts` auf `debug`/`debug_error`** in Bots, Forwarder und den `rescue`-Zweigen von `timetable.rb`; Fehler immer mit Klasse und gekürztem Backtrace. Für `vplan-watcher.rb`, der `main.rb` nicht lädt, `debug` in eine kleine `include/log.rb` auslagern.
4. **Fehler-Aggregation ohne Sentry**: Der Fingerabdruck ist Exception-Klasse plus erste `/app/`-Backtracezeile. Zähler mit first_seen, last_seen und Beispiel-Route kommen nach `/internal/status/errors.json`, die Top-Liste auf die Statusseite. Der Watchdog mailt einmal pro *neuem* Fingerabdruck. Voraussetzung: Erwartbare Fehler (falscher Code, Zugriffs-`assert` auf Seiten) liefern 4xx, wie im TODO vorgesehen. Sonst ist die Liste Rauschen.
5. **Metriken** in der Status-JSON, kein Prometheus:
   - p50/p95 und Anzahl pro Route-Muster, letzte Stunde
   - Anzahl 5xx
   - Dauer und Dateizahl des Stundenplan-Updates, voll und inkrementell (steht schon in der Logzeile)
   - Queue-Längen der Bots
   - offene Unterrichts-Mails, Forwarder-pending/failed
   - Alter von Vplan-Prüfung und -Inhalt
   - Neo4j-Ping
   - Platz auf der Platte
   - `@@ws_clients.size`
6. **Datenschutz in Logs** (wichtig): Diese Stellen schreiben heute Inhalte über Schüler:innen ins Docker-Log:
   - `include/email.rb:12` (`debug data.to_yaml` mit E-Mail, Grund und Freitext)
   - `mail-bot-repl.rb:65` (Lehrkraft, Schüler-E-Mail, Grund **und Details** wie Störverhalten)
   - `mail-forwarder.rb:248` (jede Empfängeradresse einzeln)

   Ersetzen durch Tag, Grund-Code und Anzahl. Mit der neuen Request-Zeile verschwinden auch E-Mail-Adressen aus jedem Request-Log.

## Kann weg / vereinfachen

- **Ping-Threads** in `image-bot-repl.rb` und `audio-bot-repl.rb`: `future_queue` wird nie gefüllt. Der Ping-Zweig würde `perform_update(which)` mit falscher Stelligkeit aufrufen, und `DELAYED_UPDATE_TIME` ist dort undefiniert. Toter Code.
- `PING_TIME` in `mail-bot-repl.rb`: wird nicht benutzt. In `timetable-repl.rb` ist `PING_TIME = DEVELOPMENT ? 1 : 1` und `DELAYED_UPDATE_TIME = … 0 : 0`; vereinfachen.
- `audio-bot-repl.rb`/`.ru`: Kein Dienst in `config.rb`, und die Datei listet nur Pfade auf. Entfernen oder versionieren (steht schon im TODO).
- Doppeltes `docker_compose[:services][:ruby][:user] = …` in `config.rb`. Achtung: Entfernen ändert die Reihenfolge der YAML-Keys nicht, trotzdem per Diff prüfen.
- `STDERR.puts "mail_path: …"` und `'-' * 59`-Trennzeilen in Bots und Forwarder: reines Rauschen.
- `Main.log_freiwillig_salzh_sus_for_today` im vollen Stundenplan-Update: ein Corona-Überbleibsel (siehe TODO zu `salzh`).
- Langfristig: Den Mail-Bot nicht per Host-Cron anstoßen, sondern mit einem eigenen Timer-Thread wie in `TimetableRepl`. Dann gibt es eine Abhängigkeit weniger, die nicht dokumentiert ist. Bis dahin den Cron in `doc/Betrieb.md` dokumentieren.

Relevante Dateien:
- config.rb
- doc/Betrieb.md
- src/ruby/config.ru
- src/ruby/main.rb (165–205, 1977–2168, 2251–2340)
- src/ruby/timetable-repl.rb
- src/ruby/timetable.rb (229, 2326–2350)
- src/ruby/vplan-watcher.rb
- src/ruby/mail-forwarder.rb
- src/ruby/mail-bot-repl.rb
- src/ruby/invitation-repl.rb
- src/ruby/stats-bot-repl.rb
- src/ruby/image-bot-repl.rb
- src/ruby/include/email.rb
- src/scripts/send-pending-emails.rb