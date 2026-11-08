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
> Netzwerkschnittstellen – in fremden oder geteilten Netzen den Port in
> `config.rb` auf `127.0.0.1` binden.

## Was passiert bei Änderungen?

| Geändert | Wirkung |
|---|---|
| `src/ruby/**/*.rb` | `rerun` startet den Ruby-Server neu. Bis er wieder da ist, zeigt nginx die Neustart-Seite, die sich selbst neu lädt. |
| `src/static/*.html` | sofort wirksam (Templates werden bei jeder Anfrage gelesen) |
| JS/CSS, die gebündelt werden (`compile_js`/`compile_css` in `main.rb`) | im Development-Modus bei jeder Seitenanfrage neu gebündelt |
| Tailwind-Klassen in HTML/JS | `tailwind.sh` muss laufen |
| Eingangsdaten unter `/data` | Konfigurationsdateien werden im Development-Modus bei jeder Anfrage neu geladen; für Stundenplan- oder Personendaten Ruby neu starten und `update-timetables.rb` ausführen |
| nginx-Konfiguration in `config.rb` | `./config.rb build nginx && ./config.rb up -d nginx` – die Konfiguration wird ins Image kopiert, ein Neustart allein reicht nicht |
| `src/ruby/Gemfile` | `./config.rb build ruby` (Gemfile wird beim Aufruf von `config.rb` nach `docker/ruby` kopiert) |

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
- Seiten müssen mit eigenen Farbschemata und im Dunkelmodus (`body.dark`,
  `dark.css`) lesbar bleiben.
- Echte Schuldaten, Dumps, Exporte und Zugangsdaten gehören nie ins Repo
  (siehe `.gitignore`). Das Repo ist öffentlich.
