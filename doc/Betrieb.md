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
