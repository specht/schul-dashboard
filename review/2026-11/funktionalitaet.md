# Funktionalitäts-Review gyst-dashboard

## Kurzfazit

Die meisten Fehler entstehen an vier Stellen. Erstens halten die Bots Zustand im Speicher und lesen nur inkrementell nach. Dadurch gibt es neben den behobenen Geister-Terminen noch Geister-Nachrichten und Geister-Klassenarbeiten. Zweitens fangen die Bot-Worker-Threads Fehler nicht ab: Sie sterben still oder stürzen bei jeder fehlerhaften Nachricht (Poison Message) erneut ab. Drittens identifizieren Kommentare Stunden über einen Offset, der beim Löschen oder Einfügen von Stunden nicht mitgeführt wird. Viertens hat der Mail-Forwarder keine Fehlerbehandlung für einzelne Empfänger, keine Wiederholungen und keine Timeouts. Ein Teil der gemeldeten Aussetzer lässt sich sehr wahrscheinlich mit SMTP-Ratenlimits plus einem dabei sterbenden Sende-Thread erklären. Zwei Fehler habe ich lokal nachgestellt: dass Mails externer Absender als roher MIME-Text ankommen, und die A/B-Woche über den Jahreswechsel 2026/27. Alles mit „(Vermutung)“ ist aus dem Code abgeleitet und nicht reproduziert.

## Bugs (nach Schwere)

### Hoch

**1. Mail-Forwarder: Mails externer Absender kommen als MIME-Salat an, Anhänge gehen verloren**
- *Symptom:* Empfänger:innen sehen Text mit `----==_mimepart…`-Grenzen und Base64-Blöcken, HTML und Anhänge fehlen.
- *Ursache:* `mail-forwarder.rb:258-264` baut `Mail.new { body mail.body.to_s }`. Bei multipart-Mails ist das der rohe MIME-Körper, aber ohne `Content-Type: multipart/...`. Lokal mit dem mail-Gem nachgestellt: Das Ergebnis ist `text/plain` mit allen Teilen als Text.
- *Repro:* Eine HTML-Mail mit Anhang von einer Adresse aus `mail-forwarder-emails.txt` an einen Verteiler senden.
- *Fix:* Original-Mail klonen und nur From/Reply-To/To ändern, statt den Body zu kopieren. Alternativ als `message/rfc822` anhängen.
- *Test:* Unit-Test mit multipart-Fixture: Der weitergeleitete Teil bleibt multipart, die Anhangsanzahl stimmt.

**2. Mail-Forwarder: ein einziger Fehler beim Senden bricht den Versand an alle übrigen Empfänger:innen ab**
- *Symptom:* Ein Teil eines Verteilers bekommt die Mail nicht. Der Absender bekommt eine Mail „Weiterleitung fehlgeschlagen“ mit der Liste aller noch offenen Adressen.
- *Ursache:* `mail-forwarder.rb:269-300`. Jede Exception, auch ein 550 für eine einzelne Adresse oder ein vorübergehender 4xx-Fehler, benennt `recipients.yaml` in `.failed` um und bricht ab. Es gibt kein automatisches Wiederholen.
- *Fix:* Pro Empfänger unterscheiden: Permanente Fehler protokollieren und überspringen. Vorübergehende Fehler (4xx, Timeout) in der Liste lassen und mit Backoff später erneut versuchen.
- *Test:* SMTP-Mock lehnt eine Adresse ab: Alle anderen werden zugestellt.

**3. Mail-Forwarder: Mails gehen still verloren, wenn er abstürzt, nachdem die Mail auf Platte liegt**
- *Ursache:* `mail-forwarder.rb:117-121` schreibt zuerst `/mails/<id>/mail`. Erst danach laufen `allowed_senders()` (Neo4j-Abfrage, `@@schueler_for_klasse['11'].each` bei `:87`) und das Schreiben von `recipients.yaml`. Stürzt etwas dazwischen ab (z. B. Neo4j nicht erreichbar), sieht der neue Prozess `File.exist?(mail_path)`, überspringt die Mail und löscht sie aus der INBOX (`:207`).
- Ähnlich: Ohne Message-ID landen Mails unter `/mails/mail`. Alle späteren Mails ohne ID gelten dann als Dubletten. Außerdem findet der Glob in `:225` den Pfad `/mails/recipients.yaml` nicht, solche Mails werden also nie verschickt. Message-IDs mit `/` erzeugen Unterordner, die der Glob ebenfalls übersieht (Vermutung).
- *Fix:* `recipients.yaml` zuerst über eine Temp-Datei schreiben, dann umbenennen. Die Datei `mail` dient erst danach als „erledigt“-Marker. Die Message-ID hashen (SHA1) statt sie direkt als Pfad zu nehmen. Fehlt die ID, den Hash des Inhalts verwenden.
- *Test:* Einen Fehler in `allowed_senders` erzwingen, neu starten: Die Mail wird trotzdem zugestellt.

**4. Mail-Forwarder: Verteiler in BCC wird als „Keine Empfänger“ zurückgeschickt**
- *Ursache:* `mail-forwarder.rb:136` wertet nur die Kopfzeilen To/Cc/Bcc aus. Die Bcc-Zeile entfernt der sendende Server. Der Empfänger aus dem Umschlag (`Delivered-To`/`X-Original-To`) wird nicht gelesen.
- *Fix:* Auch `Delivered-To`, `X-Original-To` und `Envelope-To` auswerten.
- *Test:* Fixture ohne Verteiler in To/Cc, aber mit `Delivered-To`.

**5. Nachrichten: entfernte Empfänger:innen sehen die Nachricht weiter (Geister-Nachricht)**
- *Ursache:* `include/message.rb:54-60` löscht beim Bearbeiten die `TO`-Kanten (`DELETE r`). `timetable.rb:2558-2589` liest nur vorhandene Kanten, deshalb bleibt `@messages_for_user[entfernt][mid]` stehen. Ein späteres Löschen der Nachricht erreicht diese Person auch nicht, weil sie keine Kante mehr hat. Das hält bis zum Neustart des timetable-Dienstes an. Die Datei `/gen/m/…` bleibt abrufbar.
- *Fix:* Wie bei den Events eine Platzierungs-Map `mid → Set[email]` führen und bei jedem Treffer die alten Platzierungen entfernen. Oder statt `DELETE` die Kante mit `rt.deleted=true, rt.updated=$ts` markieren.
- *Test:* E2E: Nachricht an A und B senden, B entfernen, als B einloggen: Nachricht nicht sichtbar.

**6. Stunden löschen oder einfügen: Kommentare und Notizen verrutschen, vorgemerkte Eltern-Mails verschwinden**
- *Ursache:* `include/lesson.rb:280-318` verschiebt nur `LessonInfo.offset`. `TextComment` und `AudioComment` tragen den Offset als eigene Property (`comment.rb:66,95`) und hängen danach an der falschen Stunde. `DETACH DELETE` einer `LessonInfo` trennt `Mail-[:REGARDING]` ab. Der Mail-Bot findet die Mail dann nicht mehr (`mail-bot-repl.rb:34`): kein Versand, und sie ist auch nicht mehr stornierbar. `@lesson_notes_for_lesson_key` ist nach Offset sortiert und wird nicht neu geladen (`timetable.rb:2684`).
- *Fix:* Kommentare ebenfalls verschieben (gleiche Abfrage auf `c.offset`, dabei `updated` setzen). Ungesendete Mails vor dem Löschen stornieren oder umhängen.
- *Test:* Kommentar auf Stunde 3, Stunde 2 löschen: Der Kommentar steht bei der neuen Stunde 2.

**7. Race bei `updated >= ts`: Änderungen erscheinen bis zum Neustart nie**
- *Ursache:* Request-Threads setzen `timestamp = Time.now.to_i` vor einer mehrteiligen Transaktion (z. B. `lesson.rb:14-60`). Committet eine andere Transaktion mit T+1 früher und läuft der timetable-Dienst dazwischen, steht `@lesson_info_last_timestamp` auf T+1 (`timetable.rb:2449`). Der spätere Commit mit T wird nie gelesen. Das gilt genauso für Kommentare, Nachrichten, Tests, Events und Notizen (Vermutung, unter Last am Montagmorgen plausibel).
- *Fix:* Mit Überlappung abfragen (`>= last_ts - 120`, die Verarbeitung ist idempotent). Oder einen Zähler auf DB-Seite nutzen.
- *Test:* Unit-Test mit zwei Zeilen in umgekehrter Commit-Reihenfolge.

### Mittel

**8. Klasse einer Klassenarbeit ändern: Termin bleibt in der alten Klasse stehen.** `tests.rb:107-126` löst die Aktualisierung nur für die neue Klasse aus, und `timetable.rb:2624-2630` löscht nie aus `@public_test_entries_for_klasse[alte_klasse]`. *Fix:* alte Klasse vorher lesen, beide auslösen und Platzierungen pro Test-ID führen. *Test:* E2E: Klasse ändern, dann als SuS der alten Klasse prüfen.

**9. A/B-Wochen nach dem Jahreswechsel 2026/27 vertauscht** (falls `SWITCH_WEEKS` in Produktion aktiv ist). `directory.rb:523` bildet die Differenz von ISO-Wochennummern. 2026 hat 53 ISO-Wochen. Simuliert: 28.12. „A“, 04.01.2027 „A“, danach dauerhaft vertauscht. Betrifft `tests.rb:23` und `timetable.rb:1876`. *Fix:* `((d - montag(d_info)).to_i / 7)`. *Test:* Unit-Test über 2026-12 bis 2027-01.

**10. Mail-Bot (Eltern-Mails aus dem Unterricht) verschickt nur auf externen Anstoß und kann sich festfahren.** `PING_TIME` wird nie benutzt. `perform_update` läuft nur über `/api/send_pending_mails`, aufgerufen von `src/scripts/send-pending-emails.rb`. Ein Cronjob dafür ist nirgends dokumentiert (Vermutung: ohne Cron gehen keine Mails raus). Mit `Thread.abort_on_exception = true` (`:16`) beendet jede Exception den Prozess, etwa `@@user_info[sus_email]` = nil für abgegangene SuS (`:53`) oder `@@klassenleiter[klasse]` = nil (`:59`). Danach stürzt jeder weitere Lauf an derselben Mail wieder ab, und alle anderen Mails bleiben liegen. *Fix:* Ping-Thread im Bot, Fehler pro Mail abfangen und Mail als fehlgeschlagen markieren.

**11. Einladungs-Bot: Endlosschleife aus Absturz und Neustart bei fehlerhaften Einträgen (Vermutung).** `event.rb:179-185`: Mit `temp = ….first` entsteht bei nil ein NoMethodError. Hat die Organisatorin die Schule verlassen, ist `@@user_info[...]` nil. Das passiert, bevor `invitation_requested` entfernt wird. `invitation-repl.rb:78` ruft `perform_update(:all)` im `configure` auf, also stürzt der Bot schon beim Start wieder ab. Im Worker-Thread gibt es kein `rescue`, der Thread stirbt still. *Fix:* `rescue` pro Einladung, Request-Flag zuerst entfernen.

**12. Monitor und Vertretungsplan: „Stand“ 1–2 Stunden zu früh.** `vplan-watcher.rb:298` formatiert `Last-Modified` in GMT. `timetable.rb:234` hängt den lokalen Offset an. *Fix:* vor dem Formatieren `.new_offset(DateTime.now.offset)`.

**13. Vertretungsplan:** Tage, die aus dem Untis-Export verschwinden, behalten ihre alten `/vplan/<datum>.json` (`:222` schreibt nur Tage aus `datum_list`, Vermutung). Bei jeder Änderung landet ein `update/all` in der Queue (`:342`). Die FIFO-Queue im timetable-Dienst dedupliziert nicht. Ändert Untis öfter, als ein Vollupdate dauert, warten Lehrkräfte-Aktionen hinter mehreren Vollläufen. Wenn sich das Format ändert (`raise 'unexpected table'`, `assert` auf Überschriften), stürzt der Watcher bei jedem Lauf erneut ab.

### Niedrig
- `timetable-repl.rb:93-96`: Aus `"<key>/wait"` werden zwei Queue-Einträge, auch `"wait"` als eigener Schlüssel. Folge: unnötige Läufe.
- `timetable.rb:2571`: `fetched_message_count = rows.size` nimmt die falsche Variable (das Log zeigt Audio-Kommentare).
- `timetable.rb:2672-2676`: `@events_last_timestamp` rückt nur vor, wenn das Event Teilnehmende hat. Events ohne Teilnehmende werden bei jedem Update erneut geladen.
- `stats-bot-repl.rb:271`: kein `rescue`, der Worker stirbt still, HTTP nimmt aber weiter Aufträge an.
- `admin.rb:675`: Das EV-Passwort hängt vom Kalenderjahr ab (`Date.today.year`) statt vom Schuljahr und ändert sich am 1. Januar (Vermutung).
- `poll.rb:699`: `WHERE pr.anonymous = $anonymous`. Schickt der Client einen anderen Wert, gibt es HTTP 500 statt einer verständlichen Meldung.

## Veralteter/inkonsistenter Zustand

- **timetable-Caches** ohne Behandlung für Löschen und Umziehen: Nachrichten (#5), Klassenarbeiten (#8), Notizen und Kommentare nach Offset-Verschiebung (#6). `@lesson_info` wird nur gelöscht, wenn genau dieser Lesson-Key ausgelöst wird (`timetable.rb:2369-2378`).
- **Abhängigkeit von `Date.today` beim Schreiben:** `regular_events_from` und das Ausblenden vergangener Events (`timetable.rb:1165-1167, 1881`) sowie `today`/`tomorrow` des Monitors (`:211`) werden nur bei Vollläufen neu berechnet. Ohne Änderung im Vertretungsplan nach Mitternacht (Montag früh, nach Ferien) zeigt der Monitor weiter den alten Tag (`monitor.html:732`).
- **`update_mailing_lists` (`main.rb:1465ff`):** wird aus Puma-Request-Threads aufgerufen und setzt `@@mailing_lists = {}`, bevor die Liste neu befüllt ist. Gleichzeitige Leser sehen leere oder halbe Listen. Zwei gleichzeitige Aufrufe schreiben in **dieselbe** Datei `mailing_lists.yaml.tmp` (`:1697-1700`). Dadurch kann eine verschränkte oder abgeschnittene YAML entstehen, oder das zweite `mv` scheitert mit HTTP 500 (Vermutung). Fix: Liste lokal bauen und am Ende in einem Schritt zuweisen, eindeutige Temp-Namen, Mutex.
- Dasselbe Muster findet sich in `directory.rb:583-760` (`@@angebote_mailing_lists = {}` usw.).
- **`@@ws_clients`** wird in `monitor.rb:36-51` durchlaufen, während `open`/`close` in anderen Threads Schlüssel hinzufügen oder entfernen. Mögliche Folge: „can't add a new key into hash during iteration“. `monitor.json` wird nicht atomar geschrieben (`timetable.rb:320`), gleichzeitiges Lesen kann einen JSON-ParserError auslösen.
- **`MERGE (i:LessonInfo {offset})-[:BELONGS_TO]->(l)`** (`lesson.rb:17`, `email.rb:28`) ist ohne Constraint nicht atomar. Gleichzeitige Saves können doppelte LessonInfos anlegen, spätere `expect_one` brechen dann mit HTTP 500 ab (Vermutung).
- **Die Bots arbeiten mit Daten vom Start:** Mail-Forwarder (erlaubte Absender, Rollen), Stats-Bot (`@@user_info`) und Einladungs-Bot kennen neue Lehrkräfte oder Rollen erst nach ihrem eigenen Neustart. `doc/Betrieb.md` nennt nur `restart ruby`.
- **`trigger_update` schluckt Fehler** (`main.rb:2306-2313`), ohne Timeout und ohne Wiederholung. Ist der timetable-Dienst hängend erreichbar, blockiert der Request-Thread bis zu 60 s.
- **`update(nil)`** fängt Fehler in `update_timetables` und `update_recipients` ab und protokolliert sie ohne Backtrace (`timetable.rb:2329-2348`). Ein einzelner `nil`-Eintrag bricht das Schreiben **aller** `recipients.json` ab (z. B. `:2257`).

## Mail-Forwarder: mögliche Ursachen der Aussetzer

Nach Wahrscheinlichkeit sortiert, alles abgeleitet aus dem Code:

1. **SMTP-Ratenlimit des Providers.** Jede:r Empfänger:in bedeutet eine eigene SMTP-Verbindung mit AUTH, im Abstand von nur 0,1 s (`:267, :307`). Eine große Elternliste erreicht schnell Limits pro Minute oder Stunde. Folge: Exception, Rest geht nach `.failed`, und es gibt **keine Wiederholung** (#2). Wird das Limit nach einer Stunde zurückgesetzt, „funktioniert es wieder“. Das passt genau zum Symptom.
2. **Der Sende-Thread t2 stirbt still.** Schlägt im `rescue` auch die Benachrichtigungsmail fehl (`:290`, bei Ratenlimit sehr wahrscheinlich), verlässt die Exception den Thread. Der Hauptthread wartet aber in `t1.join` (`:317`). t1 holt deshalb weiter Mails, kopiert sie nach „Forwarded“ und löscht sie, verschickt aber nichts mehr. Erst ein IMAP-Fehler in t1 beendet den Prozess, Docker startet ihn neu (`restart: always`), und t2 arbeitet die liegengebliebenen `recipients.yaml` ab. Wann der nächste IMAP-Schluckauf kommt, ist zufällig: „ein paar Stunden Aussetzer, dann wieder gut“. Ein abgeschnittenes `recipients.yaml` nach SIGKILL (Trap auskommentiert, `:26-30`, nicht-atomares Schreiben `:304`) tötet t2 dauerhaft.
3. **IMAP ohne Lese-Timeout:** Hängt eine Verbindung (NAT, Provider), blockiert t1, bis TCP aufgibt. Das kann zig Minuten bis zu 2 h dauern (Vermutung). In der Zeit kommen keine neuen Mails an.
4. **Defekte `mailing_lists.yaml`** durch die tmp-Kollision (siehe oben). Ungültiges YAML führt zu Absturzschleifen. Fehlende Listen erzeugen Bounces „Ungültige Verteiler-Adresse“, bis zum nächsten `update_mailing_lists`. Nebenbei: Der Tippfehler `@@mailing_lists` vs. `@@mailing_list` (`:51/58`) bewirkt, dass die Datei bei jedem Aufruf neu gelesen wird.
5. **Fehlerhafte Nachrichten:** Ein nicht parsebarer `From` (`:109`) lässt t1 bei derselben INBOX-Mail immer wieder abstürzen. Dann ruht alles, bis jemand die Mail entfernt.

**Diagnose:** Im Log nach `terminated with exception`, `Forwarding mail failed`, SMTP-Codes `421|45[0-4]|5\.7\.` und `Unable to resolve` suchen. In `MAIL_FORWARDER_PATH` nach `*.failed` und nach `recipients.yaml` suchen, die älter als eine Stunde sind.

**Fix-Paket:** Pro Empfänger `rescue` mit Retry-Queue. Eine SMTP-Verbindung für den ganzen Batch und Drosselung nach Provider-Limit. `Thread.abort_on_exception = true` oder ein `begin/rescue/retry` um jeden Loop-Durchlauf. IMAP-Timeouts. Atomare Schreibvorgänge. Ein Heartbeat-File, das ein Healthcheck prüft.

## Halbfertig / tot / kaputt

- `timetable.rb:2183` „TODO: Also handle angebote!“: Der Trigger `_angebote_` (`angebote.rb:85,130,148`) schreibt nur `recipients.json` neu, ohne Angebote. Effektiv bewirkt er nichts.
- `poll.rb:686, 749`: Trigger auskommentiert. Damit ist der Zweig `_poll_run_` in `timetable.rb:2398-2411` und in `timetable-repl.rb:88` toter Code.
- `image-bot-repl.rb:93-101`: Logik für `future_queue` und Ping ist tot. Würde sie greifen, ruft sie `perform_update(which)` mit falscher Argumentzahl auf.
- `mail-bot-repl.rb:10`: `PING_TIME` wird nie benutzt (siehe #10).
- `main.rb:2350-2351`: Adventskalender fest auf 2021, liefert immer 0. `monitor.html:450` hängt daran.
- `main.rb:3572-3573`: Header `X-Tage-Bis-…` mit fest eingetragenen Daten aus 2026.
- `mail-forwarder.rb`:
  - `:85` feste Schul-Domain statt `SCHUL_MAIL_DOMAIN` (bricht in Forks)
  - `:87` fest eingetragene Klasse „11“ als erlaubte Absender
  - `:153-155/191-195` Hinweis auf umgezogene Adressen, halb auskommentiert
  - `:26-30` SIGTERM-Trap auskommentiert
  - `:40-44` ungenutzte Klartext-IMAP-Verbindung als „DNS-Test“
- `main.rb:1667`: `:extra_allowed_users` (Projekt-Organisator:innen) wird geschrieben, aber nirgends gelesen. Organisator:innen ohne Rolle bekommen ihre Mails zurückgeschickt.
- `timetable.rb:1779`: eigenes TODO „this code can't work“ (Hausaufgaben im Stunden-Modal).
- `timetable.rb:2345`: Corona-Logging `log_freiwillig_salzh_sus_for_today` läuft bei jedem Volllauf mit. `timetable.rb:656`: Datumsweiche von 2022.
- `include/test_events.rb:4-8`: Aufräumen alter Einträge auskommentiert, `TestEvent`-Knoten sammeln sich an.
- `lab8.rb`/`lab9.rb`: fast identische Kopien. Zusammen mit `projekte_old.rb` Kandidaten zum Konsolidieren oder Entfernen.
- `main.rb:1445` „TODO: Temporarily disabled“ steht über Code, der aktiv läuft. Der Kommentar ist irreführend.
