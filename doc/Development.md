# Entwicklerhandbuch

Wie das System aufgebaut ist, steht in [Architektur](file.Architektur.html).
Hier geht es um die tägliche Arbeit am Code.

## Lokal starten

Voraussetzungen: Ruby (nur für `config.rb`), Docker mit Compose und – für
Tailwind – Node.js (`npx`).

```
cp env.template.rb env.rb
cp src/ruby/credentials.template.rb src/ruby/credentials.rb
./config.rb build
./config.rb up
```

Vor der ersten Anmeldung braucht es einmalig die Schlüssel für das Single
Sign-on, sonst endet jede Seite nach der Anmeldung mit HTTP 500 – siehe
„Schlüssel für das Single Sign-on“ in [Installation](file.Installation.html).

Das Dashboard läuft dann unter [http://localhost:8025](http://localhost:8025),
der Neo4j-Browser unter [http://localhost:8021](http://localhost:8021).
`./config.rb up` startet im Development-Modus zusätzlich `tailwind.sh`, das
`src/static/tailwind.css` bei Änderungen neu baut.

Die Stundenpläne sind nach dem ersten Start leer:

```
cd src/scripts && ./update-timetables.rb
```

### Anmelden

Mit den Beispieldaten kann man sich z. B. als `clarke@beispielschule.de`
anmelden. Im Development-Modus ist der Anmeldecode immer `123456`, ein
zweiter Faktor `654321`, und Lehrkräfte müssen keinen zweiten Faktor
verwenden.

> **Achtung:** Diese festen Codes gelten für **jede** Adresse. Eine lokale
> Instanz mit echten Schuldaten (`INPUT_DATA_PATH` zeigt nicht auf
> `src/example-data`) darf deshalb nur auf dem eigenen Rechner erreichbar
> sein. Standardmäßig lauscht nginx im Development-Modus auf allen
> Netzwerkschnittstellen – in fremden oder geteilten Netzen in `env.rb`
> `NGINX_HOST_ADDRESS = '127.0.0.1'` setzen.

### Produktionsdaten in die Entwicklungsinstanz holen

Wer SSH-Zugang zum Server hat, kann den Stand der Produktion in die eigene
Entwicklungsinstanz holen, um einen Fehler mit echten Daten nachzustellen.
In `env.rb` den Server eintragen (Name aus `~/.ssh/config`, siehe
`env.template.rb`):

```
PROD_SSH_HOST = 'mein-server'
```

Dann:

```
cd src/scripts
./pull-prod-data.rb            # zeigt nur, was passieren würde
./pull-prod-data.rb --srsly    # Datenbank und Dateien holen
```

- Auf dem Server wird nur gelesen: Die Datenbank wird im laufenden Betrieb
  exportiert (wie mit `dump-database.rb`, ohne Sperren) und direkt über SSH
  übertragen. Die Dateien kommen per `rsync`. Beides läuft mit niedrigster
  CPU- und I/O-Priorität, `rsync` mit Bandbreitenbegrenzung
  (`--bwlimit=KBPS`, Standard 20000).
- Lokal wird die Entwicklungsinstanz angehalten. `raw`, `gen` und `vplan`
  werden gespiegelt (lokale Dateien, die es auf dem Server nicht gibt,
  werden gelöscht). Die bisherige Datenbank wird nach
  `DATA_PATH/neo4j.previous` verschoben und der Dump in eine leere Neo4j
  geladen. Danach wird geprüft, ob die Zahl der Knoten und Beziehungen
  stimmt. Wenn nicht, wird die alte Datenbank automatisch
  wiederhergestellt.
- `--db-only` / `--files-only` holen nur einen Teil.
  `--restore-previous --srsly` holt die Datenbank von vor dem letzten
  Abruf zurück.
- Vorher prüft das Skript, ob genug Platz auf der Platte ist (`gen` ist
  mehrere GB groß).
- Nicht übertragen werden `DATA_PATH/mails`, `INTERNAL_PATH` und
  `INPUT_DATA_PATH`.
- Das Skript läuft nur mit einer Entwicklungskonfiguration
  (`DEVELOPMENT = true`) und nicht mit `DASHBOARD_ENV`, also nie gegen den
  Test-Stack.

Danach liegen echte personenbezogene Daten auf dem eigenen Rechner – es
gelten dieselben Regeln wie für die Instanz selbst (nur lokal erreichbar,
nichts davon weitergeben).

## Was passiert bei Änderungen?

| Geändert | Wirkung |
|---|---|
| `src/ruby/**/*.rb` | `rerun` startet den Ruby-Server neu. Bis er wieder da ist, zeigt nginx die Neustart-Seite, die sich selbst neu lädt.  Mit Hot Reload (siehe unten) gilt das nicht für `src/ruby/include/*.rb`. |
| `src/static/*.html` | sofort wirksam (Templates werden bei jeder Anfrage gelesen) |
| JS/CSS, die gebündelt werden (`compile_js`/`compile_css` in `main.rb`) | im Development-Modus bei jeder Seitenanfrage neu gebündelt |
| Tailwind-Klassen in HTML/JS | `tailwind.sh` muss laufen |
| Eingangsdaten unter `/data` | Konfigurationsdateien werden im Development-Modus bei jeder Anfrage neu geladen; für Stundenplan- oder Personendaten Ruby neu starten und `update-timetables.rb` ausführen |
| nginx-Konfiguration in `config.rb` | `./config.rb build nginx && ./config.rb up -d nginx` – die Konfiguration wird ins Image kopiert, ein Neustart allein reicht nicht |
| `src/ruby/Gemfile` | `./config.rb build ruby` (Gemfile wird beim Aufruf von `config.rb` nach `docker/ruby` kopiert) |

### Hot Reload

Ein Neustart des Ruby-Servers dauert mit echten Daten 20–40 Sekunden
(`collect_data`). In der Entwicklung werden geänderte Dateien unter
`src/ruby/include/` deshalb bei der nächsten Anfrage neu geladen
(`Sinatra::Reloader`, siehe `src/ruby/dev_reloader.rb`). Neue und geänderte
Routen und Methoden wirken sofort; im Log steht `Hot reload: <datei>`.

Grenzen:

- Startcode läuft nicht noch einmal: Daten aus `collect_data`,
  `configure`-Blöcke und beim Start gesetzte Klassenvariablen bleiben, wie
  sie waren. Wer daran etwas ändert, startet neu (`./config.rb restart ruby`).
- Gelöschte oder umbenannte Methoden bleiben bis zum nächsten Neustart
  definiert. Vor dem Push laufen die Tests ohnehin ohne Hot Reload
  (`./test.sh all`).
- `main.rb`, `parser.rb`, `timetable.rb` usw. starten den Server weiterhin
  über `rerun` neu, ebenso alle Bots bei jeder Änderung unter `src/ruby`.
- Nur in der Entwicklung: `config.rb` schaltet Hot Reload ausschließlich bei
  `DEVELOPMENT = true` und nur für den Dienst `ruby` ein; ein Unit-Test prüft,
  dass der Reloader nirgends sonst geladen wird.
- Abschalten: `DEV_HOT_RELOAD = false` in `env.rb`, dann `./config.rb up -d ruby`.

## Tests

```
./test.sh unit       # Ruby-Unit-Tests
./test.sh e2e        # Browser-Tests gegen einen eigenen Test-Stack (Port 8125)
```

Der Test-Stack läuft parallel zur Entwicklungsinstanz und nur mit
Beispieldaten. Details in [Tests](file.Tests.html).

## Logs und Konsole

```
./config.rb logs -f ruby          # Ruby-Server
./config.rb logs -f timetable     # Stundenplan-Dienst
cd src/scripts && ./pry.rb        # Ruby-Konsole mit geladenem Main
```

## Neue Seite

1. `src/static/meine_seite.html` anlegen – sie ist dann unter
   `/meine_seite` erreichbar und wird in `_template.html` eingebettet.
2. Erste Zeile: eine Zugangsprüfung, z. B.
   `#{this_is_a_page_for_logged_in_users}` (siehe `include/user.rb`).
3. Braucht die Seite Daten vom Server, entweder in der Seiten-Route in
   `main.rb` vorbereiten oder per `api_call` nachladen.
4. Ein Element `<div class='api_messages' style='display: none;'></div>`
   einbauen, damit Lade- und Fehlermeldungen von `api_call` sichtbar sind.
5. Link in der Navigation: `nav_items` in `main.rb`.

Achtung: Alles in `#{…}` ist Ruby-Code (siehe
[Architektur](file.Architektur.html#Seiten)). In JavaScript also `${…}`
verwenden und nie `#{` ausgeben. Daten aus der Datenbank, die in die Seite
eingesetzt werden, HTML- bzw. JSON-sicher maskieren.

## Neue API-Route

1. Passende Datei in `src/ruby/include/` wählen oder neu anlegen
   (`class Main < Sinatra::Base … end`) und in `main.rb` per `require`
   einbinden.
2. Zuerst die Berechtigung prüfen (`require_user!`,
   `user_with_role_logged_in?(:…)` …), dann `parse_request_data` mit
   Pflichtfeldern, Typen und Längen.
3. Cypher immer mit Parametern (`$name`), nie mit `#{…}`.
4. Keine Shell-Strings mit Daten aus Anfragen: `system('befehl', arg1, arg2)`
   statt `system("befehl #{arg}")`.
5. `respond(…)` für die Antwort.
6. Tests dazu schreiben (siehe [Tests](file.Tests.html)).

## Konventionen

- IDs im HTML: `bu_…` für Buttons, `ti_…` für Eingabefelder, `…Modal` für
  Modals. Für E2E-Tests zusätzlich `data-testid` verwenden.
- Texte auf Deutsch; Schüler:innen werden mit „du“ angesprochen.
- Keine nativen Dialoge (`alert`, `confirm`, `prompt`): `dashboardAlert(text, title)`
  und `dashboardConfirm(text, on_confirm, {title, confirm, cancel, danger})` aus
  `_template.html` verwenden.
- Alle Regeln für Menschen und Agenten: [AGENTS.md](https://github.com/specht/schul-dashboard/blob/master/AGENTS.md).
- Seiten müssen mit eigenen Farbschemata und im Dunkelmodus (`body.dark`,
  `dark.css`) lesbar bleiben.
- Echte Schuldaten, Dumps, Exporte und Zugangsdaten gehören nie ins Repo
  (siehe `.gitignore`). Das Repo ist öffentlich.
