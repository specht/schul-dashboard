# Architektur

Dieses Kapitel gibt einen Überblick darüber, wie das Dashboard aufgebaut ist:
welche Dienste laufen, wie eine Anfrage verarbeitet wird, wo Daten herkommen
und wo sie landen. Es richtet sich an alle, die am Code arbeiten wollen.

Für den Einstieg in die tägliche Entwicklung siehe das
[Entwicklerhandbuch](file.Development.html), für Tests [Tests](file.Tests.html)
und für den Produktivbetrieb [Betrieb](file.Betrieb.html).

## Überblick

```
             Browser
                │
   (Produktion: vorgelagerter Reverse-Proxy mit TLS)
                │
            ┌───▼────┐   statische Dateien: src/static, /raw, /gen, /ical
            │ nginx  │──────────────────────────────────────────────────┐
            └───┬────┘                                                  │
                │ alles andere                                          │
            ┌───▼────┐   HTTP (intern)   ┌──────────────────────────┐   │
            │  ruby  │──────────────────▶│ timetable, image_bot,    │   │
            │ Sinatra│                   │ mail_bot, stats_bot,     │   │
            └───┬────┘                   │ invitation_bot           │   │
                │ Bolt                   └────────────┬─────────────┘   │
            ┌───▼────┐                                │ schreiben       │
            │ neo4j  │◀───────────────────────────────┘ /gen, /internal │
            └────────┘                                        ▲         │
                                                              └─────────┘
```

Alle Dienste laufen als Docker-Container in einem gemeinsamen Netz.
`config.rb` erzeugt daraus `docker-compose.yaml` und die nginx-Konfiguration
und ruft dann `docker compose` mit den übergebenen Argumenten auf
(siehe [Installation](file.Installation.html)).

## Dienste

| Dienst | Code | Aufgabe |
|---|---|---|
| `nginx` | `docker/nginx`, Konfiguration in `config.rb` | liefert `src/static` und die generierten Dateien aus, leitet alles andere an `ruby` weiter, zeigt beim Neustart von `ruby` die Seite `errors/neustart.html` |
| `ruby` | `src/ruby/main.rb` + `src/ruby/include/*.rb`, gestartet über `config.ru` (Puma, Port 3000) | die eigentliche Anwendung: Seiten, API, Anmeldung |
| `neo4j` | `docker/neo4j` (Neo4j 4.4) | Datenbank für alles, was Nutzer:innen anlegen (Sessions, Notizen, Nachrichten, Umfragen, Buchungen …) |
| `timetable` | `timetable-repl.rb`, `timetable.rb` | schreibt pro Person und Woche den fertigen Stundenplan als JSON nach `/gen/w/…` sowie iCal-Dateien |
| `image_bot` | `image-bot-repl.rb` | rechnet hochgeladene Bilder in mehrere Größen (JPG/WebP) nach `/gen/i` um, rendert Hintergründe (optional, `ENABLE_IMAGE_BOT`) |
| `mail_bot` | `mail-bot-repl.rb` | verschickt fällige E-Mails (z. B. zu Unterrichtsstunden) |
| `stats_bot` | `stats-bot-repl.rb` | berechnet Statistiken (z. B. Projekttage-Wahlen) |
| `invitation_bot` | `invitation-repl.rb` | verschickt Einladungen an externe Personen (Termine, Umfragen) |
| `vplan_watcher` | `vplan-watcher.rb` | holt den Vertretungsplan aus Untis nach `/vplan` |
| `mail_forwarder` | `mail-forwarder.rb` | Mailverteiler (optional, `ENABLE_MAIL_FORWARDER`) |
| `nextcloud` | `docker/nextcloud` | **nur** Sandbox für die Entwicklung (`ENABLE_NEXTCLOUD_SANDBOX`) |
| `weasyprint` | Image `lgatica/weasyprint` | HTML → PDF (Aula, Umfragen, Technik-Post) |

Die Bots sind kleine Sinatra-Anwendungen auf Port 8080, die `main.rb` laden
und damit dieselben Daten kennen. `ruby` stößt sie über interne HTTP-Aufrufe
an (z. B. `GET http://timetable:8080/api/update/…`). Welcher Dienst gerade
läuft, steht in der Umgebungsvariable `DASHBOARD_SERVICE`.

## Verzeichnisse und Volumes

| Im Container | Auf dem Host (Standard) | Inhalt |
|---|---|---|
| `/app` | `src/ruby` (nur lesen) | Ruby-Code |
| `/static` | `src/static` (nur lesen) | Seiten-Templates, CSS, JS, Bilder |
| `/data` | `INPUT_DATA_PATH` (nur lesen), z. B. `src/example-data` | Eingangsdaten der Schule (Stundenplan, Lehrkräfte, SuS, Rollen …) |
| `/raw` | `DATA_PATH/raw` | Uploads (Bilder, Dateien, Audio-Kommentare) |
| `/gen` | `DATA_PATH/gen` | alles Generierte: Stundenpläne, Nachrichten, Bilder, Hintergründe, gebündeltes JS/CSS |
| `/internal` | `INTERNAL_PATH` | interne Dateien, die nicht ausgeliefert werden (Schlüssel, Debug-Ausgaben, Uploads für Umfragen …) |
| `/vplan` | `DATA_PATH/vplan` | Vertretungsplan-Daten |
| Neo4j `/data` | `DATA_PATH/neo4j` | Datenbank |

Wichtig: Alles unter `src/static`, `/raw` und `/gen` wird von nginx direkt
ausgeliefert, ohne dass Ruby beteiligt ist.

## Eingangsdaten

Beim Start (und im Development-Modus bei jeder Anfrage teilweise erneut)
liest `collect_data` in `main.rb` mit Hilfe von `parser.rb` die Dateien unter
`/data` ein: Schuljahr (`config.yaml`), Fächer, Ferien, Lehrkräfte,
Schüler:innen, Klassenleitungen, Rollen, Tablets, Stundenpläne (Untis-Export),
Pausenaufsichten, Kurswahlen und den Vertretungsplan aus `/vplan`.
Das Format ist in [Daten](file.Daten.html) beschrieben, ein vollständiges
Beispiel liegt in `src/example-data`.

Das Ergebnis liegt **im Speicher** des Ruby-Prozesses, in Klassenvariablen
wie `@@user_info`, `@@lessons` oder `@@users_for_role`. Die Datenbank enthält
nur, was im Betrieb entsteht. Ändern sich die Eingangsdaten, muss `ruby`
neu gestartet und anschließend der Stundenplan neu geschrieben werden
(`src/scripts/update-timetables.rb`).

## Ablauf einer Anfrage

1. nginx prüft, ob es eine passende Datei gibt (`try_files`). Wenn nicht,
   geht die Anfrage an `ruby`.
2. `config.ru` beantwortet `/api/ping` selbst (für die Neustart-Seite) und
   reicht alles andere an `Main` weiter.
3. Der Filter `before '*'` in `main.rb` liest die Cookies, sucht die Session
   in Neo4j und setzt `@session_user` (bzw. `@session_device` für Geräte wie
   Bibliotheks-Scanner oder Monitore).
4. Dann greift entweder eine API-Route (`/api/…`) oder die Seiten-Route
   `get '/*'`.

### Seiten

Die Seiten-Route nimmt das erste Pfadsegment (`/messages` → `messages`,
`/` → `index` → je nach Anmeldung `timetable` oder `login`), bereitet je nach
Seite Daten vor und liest dann `src/static/<seite>.html`. Diese Datei wird in
`src/static/_template.html` (Navigation, Farbschema, globale Skripte)
eingesetzt.

Anschließend wird jeder Ausdruck `#{…}` im Ergebnis **als Ruby-Code
ausgewertet** – das Template funktioniert also wie ein großer Ruby-String.
Dadurch können Seiten direkt Hilfsfunktionen aufrufen, z. B.

```html
#{this_is_a_page_for_logged_in_users}
<script>var sent_messages = #{sent_messages.to_json};</script>
```

Daraus folgt:

- Die erste Zeile einer Seite ist üblicherweise eine Zugangsprüfung
  (`this_is_a_page_for_…` leitet um, `require_…!` bricht ab).
- Ein `#{` im JavaScript einer Seite wird von Ruby ausgewertet, auch in
  HTML-Kommentaren. Für JS-Template-Strings `${…}` verwenden.
- Werte aus der Datenbank, die in eine Seite eingesetzt werden, müssen
  passend maskiert werden (HTML bzw. JSON).
- Teil-Templates (`_bib_public_template.html`, `_tresor_public_template.html`)
  werden per `#{File.read(…)}` eingebunden.

Seiten, deren Name mit `_` beginnt oder einen Punkt enthält, werden nicht
direkt gerendert.

### API

API-Routen liegen thematisch in `src/ruby/include/*.rb`. Jede Datei öffnet
die Klasse `Main` erneut und wird in `main.rb` explizit per `require`
eingebunden. Typisches Muster:

```ruby
# gekürzt aus include/event.rb
post '/api/save_event' do
    assert(user_with_role_logged_in?(:can_create_events))
    data = parse_request_data(:required_keys => [:title, :date, :recipients],
                              :types => {:recipients => Array})
    event = neo4j_query_expect_one(<<~END_OF_QUERY, :title => data[:title], :date => data[:date])['e']
        CREATE (e:Event {title: $title, date: $date})
        RETURN e;
    END_OF_QUERY
    # …
    respond(:ok => true)
end
```

- `parse_request_data` liest den JSON-Body, prüft Pflicht- und optionale
  Felder, Typen und Längen.
- `respond(hash)` legt die Antwort fest; ein `after`-Filter serialisiert sie
  als JSON.
- Fehler werden meist über `assert(…)` signalisiert und enden als HTTP 500.
- Neo4j-Abfragen immer mit Parametern (`$name`) statt mit `#{…}` im
  Cypher-Text.

Im Browser ruft `api_call(url, data, callback)` aus `src/static/code.js` die
API auf und zeigt Fortschritt und Fehler in einem Element mit der Klasse
`.api_messages` an, sofern die Seite eines hat.

### Stundenplan und Nachrichten

Was sich für viele Personen gleichzeitig ändert, wird nicht pro Anfrage
berechnet, sondern vom `timetable`-Dienst vorab als gzip-JSON geschrieben
(`/gen/w/<user-id>/<jahr-woche>.json.gz`, Nachrichten, Hausaufgaben). Der
Browser lädt diese Dateien direkt von nginx und entpackt sie mit `pako`.
Nach Änderungen (z. B. neue Notiz zu einer Stunde) stößt `ruby` den
`timetable`-Dienst an, der die betroffenen Dateien neu schreibt.

## Anmeldung und Rollen

- Anmeldung ohne Passwort: Code per E-Mail, SMS oder OTP-App
  (`include/login.rb`, `include/otp.rb`, `include/sms.rb`). Lehrkräfte
  müssen einen zweiten Faktor verwenden.
- Nach erfolgreicher Anmeldung gibt es eine Session in Neo4j und ein Cookie
  `sid`. Mehrere Konten können parallel angemeldet sein (Kontowechsel im
  Profilmenü).
- Geräte (Tablets, Bibliotheksstationen, Monitore) haben eigene Anmeldewege
  und Pseudo-Konten.
- Rollen stehen in `/data/roles/roles.txt` und werden über
  `ROLE_TRANSITIONS` in `include/roles.rb` erweitert (z. B. bringt `teacher`
  weitere Rechte mit). Abfragen über `user_with_role_logged_in?(:rolle)`
  bzw. die vielen `…_logged_in?`- und `require_…!`-Helfer in
  `include/user.rb`.

## Frontend

- Grundgerüst: Bootstrap 4 und jQuery, dazu FullCalendar (Stundenplan),
  Summernote (Editor), Chart.js, Dropzone und weitere Bibliotheken aus
  `src/static/include`.
- `compile_js`/`compile_css` in `main.rb` bündeln diese Dateien beim Start
  nach `/gen/js` und `/gen/css` (im Development-Modus bei jeder Anfrage).
- Tailwind wird zusätzlich verwendet (`tailwind.config.js`, `tailwind.sh`),
  vor allem in den Bibliotheksseiten.
- Jede Person kann Farbschema, Hintergrund, Dunkelmodus, Schrift und Filter
  selbst wählen (`profil.html`, `include/theme.rb`). Seiten müssen deshalb
  mit beliebigen Farben und mit `body.dark` (`dark.css`) funktionieren.
- Die Oberfläche ist deutsch und spricht Schüler:innen mit „du“ an.

## Weitere Teile des Repos

- `src/scripts/`: Skripte, die auf dem Host laufen und Befehle per
  `./config.rb exec ruby …` im Container ausführen (Stundenpläne neu
  schreiben, Nextcloud-Ordner anlegen, Dumps …), siehe
  [Betrieb](file.Betrieb.html).
- `src/go/party`: kleines Terminalprogramm für den Einlass bei der
  Unterstufenparty.
- `doc/`: diese Dokumentation; sie wird mit YARD gebaut
  (`update-documentation.sh`) und öffentlich veröffentlicht.
