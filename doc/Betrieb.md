# Betrieb

Hinweise für den Produktivbetrieb. Für die Einrichtung einer Testumgebung
siehe [Installation](file.Installation.html), für den Aufbau
[Architektur](file.Architektur.html).

## Produktivkonfiguration

In `env.rb`:

- `DEVELOPMENT = false` – schaltet u. a. echte Anmeldecodes, die Zwei-Faktor-
  Pflicht für Lehrkräfte, `restart: always` für alle Dienste und die
  Variablen für den vorgelagerten Proxy ein.
- `INPUT_DATA_PATH`, `DATA_PATH`, `INTERNAL_PATH`, `LOGS_PATH` auf
  Verzeichnisse **außerhalb** des Repos setzen.
- `ENABLE_NEXTCLOUD_SANDBOX = false` (die Sandbox ist nur für die
  Entwicklung gedacht).

In `src/ruby/credentials.rb` **alle** Werte aus der Vorlage ersetzen,
insbesondere Salts, Passwörter und Schlüssel – nicht die Werte aus
`credentials.template.rb` übernehmen.

nginx lauscht in Produktion nur auf `127.0.0.1:8020`. TLS und der öffentliche
Hostname kommen von einem vorgelagerten Reverse-Proxy (über die Variablen
`VIRTUAL_HOST`/`LETSENCRYPT_HOST`, z. B. nginx-proxy mit acme-companion), der
nicht Teil dieses Repos ist.

## Aktualisieren

```
git pull
./config.rb build        # wenn sich Dockerfiles, Gemfile oder die nginx-Konfiguration geändert haben
./config.rb up -d
```

- Die nginx-Konfiguration wird von `config.rb` erzeugt und **ins Image
  kopiert**. Nach Änderungen daran: `./config.rb build nginx && ./config.rb up -d nginx`.
  Ein `up -d` ohne `build` verwendet weiter die alte Konfiguration.
- Nur Ruby-Code geändert: `./config.rb restart ruby` genügt (Bots ggf.
  ebenfalls neu starten, sie laden denselben Code).
- Während `ruby` neu startet, zeigt nginx die Seite `errors/neustart.html`,
  die sich automatisch neu lädt. Bei `./config.rb down` ist auch nginx weg –
  dann antwortet der vorgelagerte Proxy mit seiner eigenen Fehlerseite.

## Wartungsseite

Für geplante, längere Unterbrechungen (z. B. Datenbank-Umzug) gibt es statt
der Neustart-Seite die Wartungsseite `errors/wartung.html`. nginx zeigt sie,
solange die Datei `wartung.json` im `gen`-Verzeichnis liegt (im Container
`/gen/wartung.json`) und `ruby` nicht erreichbar ist:

```
echo '{"bis": "19:30", "text": "Wir ziehen die Datenbank um."}' > <DATA_PATH>/gen/wartung.json
# … Wartung …
rm <DATA_PATH>/gen/wartung.json
```

- Beide Angaben sind optional. `bis` (Uhrzeit, heute) erscheint als
  „Voraussichtlich wieder da“; ist die Zeit um mehr als 5 Minuten
  überschritten, sagt die Seite, dass es länger dauert. `text` erscheint als
  zusätzlicher Satz.
- Die Datei ist öffentlich abrufbar (`/gen/wartung.json`) – nur Text
  hineinschreiben, den alle sehen dürfen.
- Ein Neustart von nginx ist dafür nicht nötig. Die Datei nach der Wartung
  wieder löschen, sonst erscheint bei jedem Neustart die Wartungsseite.
- Die Seite prüft wie die Neustart-Seite regelmäßig `/api/ping` und lädt neu,
  sobald das Dashboard wieder antwortet.

## Passwörter zurücksetzen

Die Seite `/passwoerter` (Profilmenü „Passwörter und Nextcloud…“; die alten
Adressen `/login_nc` und `/mail_passwort` leiten dorthin weiter) hat zwei
Teile:

- **Nextcloud:** Zugangsdaten anzeigen und das eigene Nextcloud-Passwort
  sofort auf das Initialpasswort zurücksetzen – ohne Rückfrage, für alle mit
  Nextcloud-Zugang.
- **E-Mail-Postfach:** Zurücksetzen auf das ursprüngliche Passwort aus dem
  E-Mail-Brief. Jede Anfrage landet in der Liste „Offene Anfragen“ der
  Administration; ohne ihre Entscheidung wird nichts zurückgesetzt:
  - Schüler:innen beantragen es für das eigene Postfach; nach dem
    Zurücksetzen bekommen die Eltern (`eltern.…`) eine kurze Nachricht.
    Haben die Eltern ihr Passwort vergessen, verweist die Seite sie an die
    Klassenleitung oder per E-Mail an die Administration.
  - Klassenleitungen beantragen es für das Postfach oder das Eltern-Postfach
    der Schüler:innen ihrer Klassen. E-Mails mit solchen Bitten leiten sie an
    die Administration weiter.
  - Die Administration bearbeitet die Anfragen auf der eigenen Seite
    `/postfaecher` (Admin-Menü „Postfach-Anfragen und E-Mail-Briefe“). Dort
    sucht sie Schüler:innen nach Name, Klasse oder Adresse, öffnet den
    E-Mail-Brief und trägt Anfragen per E-Mail selbst ein („Neue Anfrage“:
    betroffene Postfächer, Antwortadresse, Notiz).
  - „Postfach prüfen…“ hilft, wenn jemand schreibt, dass keine E-Mails mehr
    ankommen: Die Adressliste des Mail-Anbieters zeigt, ob es ein Postfach
    gibt oder nur eine Weiterleitung; dann meldet sich das Dashboard per
    IMAP mit dem ursprünglichen Passwort an und liest je Ordner nur Anzahl
    und Eingangsdatum der E-Mails – keine Betreffzeilen, Absender oder Inhalte
    (nur lesend, `EXAMINE`). Daraus folgt eine Einschätzung (kommen an, aber
    werden nicht abgerufen; Filterregel; nichts Neues; fast voll; Passwort
    geändert) und ein Antwortentwurf mit Verweis auf die Anleitung
    `/hilfe#email-programm`, auf Wunsch mit dem E-Mail-Brief im Anhang.
    Gespeichert wird nur, wer wann welches Postfach geprüft hat, ob die
    Anmeldung klappte und ob eine Antwort ging (Knoten `MailboxCheck`); die
    Liste „Postfach-Prüfungen“ sehen nur Admins, Einträge werden nach 90
    Tagen gelöscht. Weiterleitungen und Filterregeln, die jemand im Webmail
    selbst eingerichtet hat, sieht das Dashboard nicht – nur ihre Wirkung.
  - Jeder offene Fall zeigt den nächsten Schritt: 1. prüfen (Zurücksetzen
    oder Ablehnen), 2. zurücksetzen (Bot oder von Hand im Kundenbereich des
    Mail-Anbieters, dann „Erledigt“ oder „Hat nicht geklappt“), 3. antworten
    – bei Anfragen per E-Mail an die Antwortadresse, bei Anfragen einer
    Klassenleitung an sie. „Antwort senden…“ schickt einen änderbaren Text
    mit dem E-Mail-Brief als PDF im Anhang; Antworten gehen an die
    Administration, die eine Kopie bekommt. Erledigte Fälle stehen unter
    „Abgeschlossen“.

Pro Postfach ist immer nur ein offener Fall möglich und nur wenige Anfragen
pro Tag. Das Ändern beim Mail-Anbieter übernimmt ein Bot, der nur
freigegebene Fälle über `GET /api/mail_account_bot/pending` abholt und
das Ergebnis an `POST /api/mail_account_bot/result` meldet
(`Authorization: Bearer <MAIL_ACCOUNT_BOT_TOKEN>` aus
`credentials.rb`; ohne Token ist die Schnittstelle aus). Solange der Bot
nicht läuft, setzt die Administration freigegebene Fälle von Hand zurück und
markiert sie auf der Seite als erledigt. Schlägt der Bot fehl, bekommt die
Administration eine Mail.

Der Bot (`src/mail-account-bot`, siehe dessen README) läuft nur auf den
Rechnern der Administration, nicht auf dem Server. Er führt nur Fälle aus,
die eine der Personen aus seiner eigenen Konfiguration (`approvers`)
freigegeben hat – das Dashboard nennt ihm dazu, wer freigegeben hat;
„Erneut versuchen“ zählt als neue Freigabe. Fälle anderer Admins meldet er
als nicht erledigt, ohne den Mail-Anbieter zu öffnen. Vor jedem Durchgang
fragt er am Rechner nach, mit der Liste der Postfächer und wer sie wann
freigegeben hat. Hält er an, ist er für
alle Rechner angehalten, bis die Administration ihn auf der Seite
„Postfach-Anfragen und E-Mail-Briefe“ wieder freigibt; dort steht auch, ob
er verbunden ist, was er zuletzt getan hat, und darunter sein Protokoll (die
letzten 14 Tage, Knoten `MailAccountBotLog`). Seine Anmeldungen bei IONOS
werden gezählt, aber nicht begrenzt. Er hält eine Websocket-Verbindung zu
`/ws_mail_account_bot`: Ein Reverse-Proxy vor dem Dashboard muss diesen Pfad
als Websocket durchreichen (wie `/ws_monitor`), sonst fragt der Bot nur alle
15 Minuten nach.

## Neue Eingangsdaten

Neue Stundenpläne, Personenlisten usw. in `INPUT_DATA_PATH` ablegen (Format:
[Daten](file.Daten.html)), dann:

```
./config.rb restart ruby
cd src/scripts && ./update-timetables.rb
```

## Logs

| Was | Wo |
|---|---|
| Ruby-Dienste (`ruby`, Bots) | `./config.rb logs -f <dienst>` (Docker-Log) |
| nginx | `LOGS_PATH/access.log`, `LOGS_PATH/error.log` |
| Neo4j | `LOGS_PATH/neo4j/` |

Ausgaben über `debug`/`debug_error` beginnen mit Datum und Uhrzeit und der
Stelle im Code, z. B. `2026-11-09 08:15:02 [main:2145] …`; Fehler sind mit
`[ERROR]` markiert, Ausnahmen erscheinen mit Stacktrace. Manche Stellen
schreiben aber direkt nach STDERR, ohne Zeitstempel und ohne `[ERROR]` –
u. a. die Bots, `vplan_watcher`, `mail_forwarder` und Fehlerzweige der
Stundenplan-Aktualisierung. Mit `-t` setzt Docker vor jede Zeile den
Zeitpunkt. Nützlich:

```
./config.rb logs --since 24h ruby | grep -E '\[ERROR\]| - [A-Z][A-Za-z:]+ - '
./config.rb logs -t --since 24h timetable mail_bot | grep -i -E 'error|exception'
```

Beim Start fasst das Dashboard Probleme in den Eingangsdaten pro Datei bzw.
Rolle in einer Zeile zusammen (z. B. unbekannte E-Mail-Adressen in
`roles.txt` oder `geschwister.txt`) – diese Zeilen nach jedem Datenimport
durchsehen.

### Rotation

Docker behält Container-Logs ohne Begrenzung. In `env.rb`:

```ruby
DOCKER_LOG_MAX_SIZE = '50m'
DOCKER_LOG_MAX_FILES = 5
```

und danach `./config.rb up -d` (die Container werden neu erstellt). Neue
Installationen haben das über `env.template.rb` bereits gesetzt.

Die nginx-Logs liegen als Dateien in `LOGS_PATH` und wachsen ebenfalls
unbegrenzt. Auf dem Host mit logrotate, z. B. `/etc/logrotate.d/dashboard`:

```
/pfad/zu/LOGS_PATH/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

### Datenschutz

Logs enthalten personenbezogene Daten (E-Mail-Adressen, Kürzel, IP-Adressen
des Proxys, aufgerufene Seiten). Aufbewahrung begrenzen (Rotation),
Zugriff beschränken, nicht weitergeben und keine Log-Auszüge ungeprüft in
Issues oder Chats kopieren.

## Überwachung

Jeder Dienst (Webdienst `ruby`, `timetable`, die Bots, `vplan_watcher`,
`mail_forwarder`) schreibt einmal pro Minute eine Statusdatei nach
`/internal/status/<dienst>.json` (`src/ruby/service_status.rb`). Dienste mit
Arbeits-Threads melden dabei auch, ob diese noch laufen – ein still
beendeter Thread, während der Prozess weiterläuft, fällt so ebenfalls auf.

- **Übersicht:** `/dienste` (nur Administration, verlinkt auf `/admin`).
- **E-Mail:** Der Webdienst prüft die Statusdateien jede Minute. Meldet sich
  ein Dienst länger als fünf Minuten nicht oder ist ein Arbeits-Thread
  beendet, geht **eine** E-Mail an `WEBSITE_MAINTAINER_EMAIL` – und eine
  weitere, wenn es wieder in Ordnung ist. Nach einem Neustart des
  Webdienstes wartet die Prüfung fünf Minuten. In der Entwicklung wird nur
  ins Log geschrieben.
- **Grenze:** Fällt der Webdienst selbst (oder der ganze Server) aus, kann er
  das nicht melden. Dafür braucht es eine Prüfung von außen, z. B. einen
  Dienst, der regelmäßig `/api/ping` abruft.
- Ein Dienst, der dauerhaft entfernt wurde, bleibt als „keine Rückmeldung“
  stehen, bis seine Datei in `/internal/status` gelöscht wird.

## SMS-Anmeldung

SMS-Codes laufen über ein SMS-Gateway, das sich per Websocket mit `/ws_sms`
verbindet. Ist es nicht verbunden, gehen die Codes per E-Mail. Der Server
schickt dem Gateway alle 20 Sekunden einen Ping; bleibt die Antwort 60
Sekunden aus (z. B. weil die Internetverbindung des Gateways weg ist, die
Verbindung für den Server aber noch offen aussieht), gilt es als offline,
die Verbindung wird getrennt und die Codes gehen wieder per E-Mail.

- **Übersicht:** `/sms_anmeldung` (nur Administration, verlinkt auf
  `/admin`): Status des Gateways, gesendete SMS, alle Personen mit
  hinterlegter Telefonnummer – zuerst die ohne OTP – mit der Zahl ihrer SMS
  in den letzten 30 und 90 Tagen und wofür (Anmeldung, zweiter Faktor,
  Tresor, Nummer bestätigen, Zeugniskonferenz). Ein Knopf kopiert die
  Adressen der Personen ohne OTP.
- **Aufzeichnung:** Jede SMS legt einen Knoten `SmsSend` (Zeitpunkt, Zweck)
  an der Person an – ohne Telefonnummer und ohne Text. Einträge, die älter
  als 180 Tage sind, werden beim Senden gelöscht. `SmsDay` zählt weiterhin
  nur die SMS pro Tag.
- **Weg von der SMS:** `/otp` erklärt die Anmeldung mit einer
  Authenticator-App (ohne Anmeldung erreichbar, mit Links und QR-Codes zu
  den Apps). Lehrkräfte sehen einen Hinweis darauf, wenn sie auf der
  Anmeldeseite einige Sekunden auf eine SMS warten und wenn der SMS-Versand
  gerade nicht erreichbar ist. Auf der Startseite erinnert eine Kachel
  Lehrkräfte, die SMS ohne App nutzen, und schlägt denen, die eine App
  haben, aber SMS als Standard, die Umstellung auf »Code per E-Mail« vor
  (»Später« blendet sie 30 Tage aus). Wie viele Lehrkräfte schon eine App
  nutzen, sehen nur angemeldete Lehrkräfte (Kachel und `/otp`), nicht die
  Anmeldeseite; gezählt werden alle, die das Dashboard schon benutzt haben.
- **Gateway offline:** Lehrkräfte ohne App können sich dann nicht anmelden
  (der erste Code kommt per E-Mail, der zweite Faktor wäre die SMS). Hat
  zwei Minuten lang kein Gateway geantwortet, zeigt die Anmeldeseite allen
  einen Hinweis darauf (nicht schon während des kurzen Wiederverbindens
  nach einem Neustart); die Seite zur Code-Eingabe sagt es den Betroffenen
  ausdrücklich.

## Mails aus dem Unterricht

Lehrkräfte schicken aus einer Stunde im Stundenplan (Knopf »Mail«) eine
E-Mail an die Eltern, z. B. bei fehlenden Hausaufgaben. Der Versand läuft
zeitverzögert über den `mail_bot`. Die Texte der sieben Gründe ändern
Admins unter `/unterrichtsmails` (Administration → Seiten), mit einer
Vorschau für Max bzw. Erika Mustermann (5a) und dem eigenen Namen als
Lehrkraft.

- Platzhalter: `{Vorname}`, `{Name}`, `{Klasse}`, `{Fach}`, `{Notiz}`
  (wird zu » (Notiz)« oder entfällt), `{Lehrkraft}`, `{Lehrkraft der Stunde}`;
  vom Geschlecht abhängige Wörter als `{männlich|weiblich}`, z. B.
  `{Ihr Sohn|Ihre Tochter}`.
- Wer die Mail schickt, unterschreibt sie (`{Lehrkraft}`) und bekommt die
  Antworten. Otium-Mails schickt die Otium-Aufsicht für die Stunde, aus der
  das Kind ins Otium kam; der Text nennt die Lehrkraft der Stunde, die eine
  Kopie bekommt (ebenso die Klassenleitung).
- Lehrkräfte sehen im Mail-Dialog eine Vorschau der Mail für jedes Kind der
  Stunde, bevor sie sie senden.
- Geänderte Texte liegen als `LessonMailTemplate`-Knoten in der Datenbank;
  ohne Knoten gilt der Standardtext aus `src/ruby/lesson_mail_templates.rb`.
  Der `mail_bot` liest die Texte vor jedem Durchlauf, ein Neustart ist nicht
  nötig.

## Neues Design (Vorschau)

Ein neues Design entsteht schrittweise und lässt sich vorab ausprobieren:
im Profil unter »Helligkeit« mit dem Schalter »Neues Design (Vorschau)«.
Vorerst steht der Schalter nur Admins zur Verfügung; wer ihn sonst sehen
darf, legt `UI_PREVIEW_FOR` in `src/ruby/include/design_preview.rb` fest
(`:admins`, `:teachers`, `:all`). Mit eingeschalteter Vorschau berechnet
das Dashboard die Farben aus dem Farbschema (`design_tokens.rb`, Kontrast
für hell und dunkel geprüft) und lädt `preview.css`.

Unten links erscheint dann »Feedback zum neuen Design«. Gespeichert werden
der Text, die Seite, Handy oder Desktop, hell oder dunkel, das Farbschema und
die Rolle – die E-Mail-Adresse nur, wenn die Person angesprochen werden
möchte. Admins sehen alles unter `/design_feedback` (Administration →
Seiten), dazu, wie viele die Vorschau gerade nutzen und wie viele sie wieder
abgeschaltet haben. Die Rückmeldungen (`DesignFeedback`) werden nach der
Vorschauphase gelöscht.

Admins können sich im Profil zusätzlich einen »Schnellumschalter« einblenden:
ein Knopf unten rechts auf jeder Seite, der mit einem Klick zwischen
bisherigem und neuem Design wechselt – um laufend zu prüfen, dass das
bisherige Design weiter funktioniert.

Der ältere Schalter »Design: alt/neu« (`new_design.css`, seit 2024) ist davon
unabhängig.

## Werkstatt (Entwürfe)

Unter `/api/werkstatt` sehen Admins eine Seite mit Entwürfen und Ideen für
das Dashboard. Sie liegt nicht im Repository, sondern nur auf dem Server
als `internal/werkstatt.html` (eine einzelne HTML-Datei, Bilder darin
eingebettet) und wird unverändert ausgeliefert. Fehlt die Datei, sagt die
Adresse das. Eine neue Fassung wird per `scp` an dieselbe Stelle kopiert;
ein Neustart ist nicht nötig.

## Datensicherung

Was gesichert werden muss:

| Was | Wo | Warum |
|---|---|---|
| Datenbank | Dump über `src/scripts/dump-database.rb` | alles, was im Betrieb entsteht |
| Uploads | `DATA_PATH/raw` | Bilder, Dateien, Audio-Kommentare |
| Internes | `INTERNAL_PATH` | Schlüssel, interne Uploads, Konfiguration |
| Eingangsdaten | `INPUT_DATA_PATH` | falls nicht anderswo gesichert |
| Konfiguration | `env.rb`, `src/ruby/credentials.rb` | Zugangsdaten |

`DATA_PATH/gen` muss nicht gesichert werden; es wird neu erzeugt.

Datenbank sichern und wiederherstellen:

```
cd src/scripts
./dump-database.rb > /pfad/ausserhalb/des/repos/dump-$(date +%F).txt
./load-dump.rb /pfad/zum/dump.txt          # Achtung: lädt in die laufende Datenbank
```

Empfehlungen:

- Regelmäßig automatisch sichern (z. B. täglich per Cron), mit Rotation.
- Dumps enthalten personenbezogene Daten: verschlüsselt ablegen, **nie** im
  Repo-Verzeichnis (`.gitignore` schützt nur vor versehentlichem Committen),
  alte Dumps löschen.
- Wiederherstellung gelegentlich auf einer Testinstanz ausprobieren.

## Neues Schuljahr

Die Liste der zurückzusetzenden Daten steht in
[TODO-NEUES-SCHULJAHR.md](https://github.com/specht/schul-dashboard/blob/master/TODO-NEUES-SCHULJAHR.md)
(im Repository, nicht Teil dieser Dokumentation).
Ablauf:

1. **Vorher** einen Dump ziehen und sicher ablegen.
2. Neue Eingangsdaten (Schuljahr in `config.yaml`, Stundenplan, Listen)
   bereitstellen.
3. Die Knoten aus `TODO-NEUES-SCHULJAHR.md` in Neo4j löschen.
4. `./config.rb restart ruby`, `./update-timetables.rb`.
5. Stichprobenartig mit verschiedenen Rollen anmelden und prüfen.

## Skripte in `src/scripts`

Die Skripte laufen auf dem Host und führen den eigentlichen Befehl im
`ruby`-Container aus (`./config.rb exec ruby …`). Aus `src/scripts` heraus
aufrufen.

| Zweck | Skripte |
|---|---|
| Stundenpläne und Inhalte neu schreiben | `update-timetables.rb`, `update-messages.rb`, `refresh-images.rb` |
| E-Mails | `send-pending-emails.rb`, `print-email-letters.rb` |
| Datenbank | `dump-database.rb`, `load-dump.rb`, `clear-database.rb` (**löscht alles**) |
| Nextcloud | `create-nc-users.rb`, `create-nc-folders.rb`, `share-nc-folders.rb`, `unshare-shares-to-klassen.rb`, `scan-nc-user-folders.rb`, `archive-nc-folders.rb`, `remove-broken-nc-shares.rb`, `collect-nextcloud-files-from-sus.rb` (siehe [Nextcloud](file.Nextcloud.html)) |
| Projekte, Listen, Druck | `import-projekte.rb`, `projekttage-assign.rb`, `print-sus.rb`, `print-zeugniskonferenz.rb` |
| Entwicklung | `pry.rb`, `timetable-repl.rb`, `check-all-timetables.js`, `render-cypher-letters.rb`, `pull-prod-data.rb` (Produktionsdaten holen, siehe [Development](file.Development.html)) |

Viele Skripte zeigen zunächst nur an, was sie tun würden, und erwarten für
die Ausführung `--srsly`.
