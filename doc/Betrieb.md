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

## Neue Eingangsdaten

Neue Stundenpläne, Personenlisten usw. in `INPUT_DATA_PATH` ablegen (Format:
[Daten](file.Daten.html)), dann:

```
./config.rb restart ruby
cd src/scripts && ./update-timetables.rb
```

## Logs

- nginx: `LOGS_PATH/access.log`
- Neo4j: `LOGS_PATH/neo4j/`
- alle Dienste: `./config.rb logs -f <dienst>`

Logs können personenbezogene Daten enthalten (E-Mail-Adressen, IP-Adressen
des Proxys). Aufbewahrung begrenzen und nicht weitergeben.

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

Die Liste der zurückzusetzenden Daten steht in `TODO-NEUES-SCHULJAHR.md`.
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
| Matrix | `write-matrix-corporal-policy.rb` |
| Entwicklung | `pry.rb`, `timetable-repl.rb`, `check-all-timetables.js`, `render-cypher-letters.rb` |

Viele Skripte zeigen zunächst nur an, was sie tun würden, und erwarten für
die Ausführung `--srsly`.
