# Tests

Dieses Kapitel beschreibt, wie die Tests aufgebaut sind und wie sie weiter
ausgebaut werden sollen – so, dass Änderungen am Code (auch größere Umbauten)
abgesichert sind, bevor sie in die Schule gehen.

## Ausführen

Voraussetzungen: Docker und Ruby (für `config.rb`). Alles andere läuft in
Containern.

```
./test.sh unit       # Ruby-Unit-Tests (ca. 2 s, ohne Datenbank)
./test.sh e2e        # Test-Stack starten, Playwright ausführen, Stack entfernen (ca. 1 min)
./test.sh all        # beides
```

Zum Entwickeln von Tests:

```
./test.sh up         # Test-Stack starten: http://localhost:8125
./test.sh e2e-run    # nur Playwright gegen den laufenden Stack
E2E_ARGS="--project=desktop tests/login.spec.ts" ./test.sh e2e-run
./test.sh logs ruby  # Logs des Test-Stacks
./test.sh down       # Stack stoppen und Testdaten löschen
```

Der Test-Stack verwendet `env.test.rb`: Projektname `schuldashboardtest`,
eigene Compose-Datei `docker-compose.test.yaml`, eigene Daten unter
`.test-stack/`, Beispieldaten aus `src/example-data` und eigene Zugangsdaten
(`src/ruby/test/credentials.rb`, alle externen Hosts zeigen auf
`*.test.invalid`). Eine laufende Entwicklungsinstanz wird nicht berührt.

Er läuft **im Produktionsmodus** – mit zufälligen Anmeldecodes,
Zwei-Faktor-Pflicht für Lehrkräfte und einmal gebündeltem JS/CSS, also so
wie in der Schule. Alle Mails gehen an ein Test-Postfach (Mailpit), aus dem
die Tests die Codes lesen:

| Dienst | Adresse |
|---|---|
| Dashboard | http://localhost:8125 |
| Mailpit (Weboberfläche und API) | http://localhost:8126 |

Nach dem Start richtet `test/e2e/seed.cypher` zwei Konten für die
Anmelde-Tests ein: `torstenson@beispielschule.de` muss einen zweiten Faktor
(OTP) verwenden, `clarke@beispielschule.de` meldet sich per OTP-App an.
Das OTP-Geheimnis der Testkonten steht in `test/e2e/tests/fixtures.ts`.

Playwright-Berichte liegen nach einem Lauf unter
`test/e2e/playwright-report/` (HTML) und `test/e2e/test-results/`
(Screenshots, Traces bei Fehlern).

## Stand

- Isolierter Test-Stack (`env.test.rb`, `DASHBOARD_ENV`,
  `DASHBOARD_CREDENTIALS`, konfigurierbare Ports in `config.rb`), Test-Stack
  im Produktionsmodus mit Test-Postfach (Mailpit)
- **Unit-Tests** (`src/ruby/test/unit/`): Parser, Farben, Template-Renderer
  (`page_template`), Regeln für Backend und Frontend (`backend_rules`,
  `frontend_rules`, z. B. keine nativen Dialoge), Mail-Schutz in der
  Entwicklung (`mail_guard`), Mail-Weiterleitung, Dienst-Überwachung
  (`service_status`), A/B-Wochen, Tablet-Sets, Bild-Uploads, `gz_output`,
  Hot Reload (`dev_reloader`)
- **E2E im Browser** (`*.spec.ts`, Desktop und Handy): Anmeldung und Sitzung,
  Profil, Nachrichten, Termine, Umfragen, Kursplanung, Kommentare,
  Klassenarbeiten, Adventskalender, Sitzplan, Verzeichnis (Admin), Monitore,
  Dialoge, Dienste-Seite, Neustart-Seite, Ausgabe von Texten im Template,
  Web-App-Manifest
- **Ohne Browser** (`*.smoke.ts`, Projekt `smoke`): Seiten-Smoke-Test (siehe
  unten), Zugriffsrechte, Anmeldecodes und Anmeldemethoden, öffentliche
  Anmeldung zu Veranstaltungen, News, Lab 8/9, `hardening.smoke.ts`
  (Prüfungen rund um Anmeldung und Uploads)
- **UI-Tour** (`ui-tour.screens.ts`, Projekt `screens`, nur auf Anfrage):
  ganzseitige Screenshots der wichtigsten Seiten je Rolle für UI/UX-Reviews,
  `E2E_ARGS="--project=screens" ./test.sh e2e-run`, Ergebnis unter
  `test/e2e/test-results/ui-tour/`

Jeder E2E-Test schlägt bei HTTP 5xx, nicht abgefangenen JavaScript-Fehlern
und nativen Browser-Dialogen fehl. Offen ist alles Weitere aus
[Reihenfolge](#Reihenfolge).

## Seiten-Smoke-Test

`test/e2e/tests/pages.smoke.ts` ruft jede Seite aus `src/static` für jede
Rolle einmal ohne Browser auf (Playwright-Projekt `smoke`, ca. 1 min). Eine
Seite darf rendern oder umleiten; HTTP 5xx ist nur erlaubt, wenn die Seite
für diese Rolle in `test/e2e/tests/known-page-errors.json` steht – mit der
Ursache als Text.

Die Liste ist eine **Bestandsaufnahme, kein Ziel**. Der Test schlägt in beide
Richtungen fehl:

- **neue Serverfehler**: eine Seite, die vorher funktionierte, ist kaputt.
- **behoben**: eine gelistete Seite funktioniert jetzt – dann den Eintrag
  aus der Liste entfernen, damit der Fix nicht wieder verloren geht.

Liste nach bewussten Änderungen neu schreiben (vorhandene Erklärungen
bleiben erhalten):

```
./test.sh up
UPDATE_KNOWN_PAGE_ERRORS=1 E2E_ARGS="--project=smoke" ./test.sh e2e-run
git diff test/e2e/tests/known-page-errors.json
```

Stand November 2026: 257 bekannte Fälle, davon 153 Zugangsprüfungen per
`assert` (HTTP 500 statt Umleitung), der Rest überwiegend unvollständige
Beispieldaten und fehlende URL-Parameter.

## Grundsätze

1. **Nur Beispieldaten.** Tests laufen ausschließlich gegen
   `src/example-data` und eine leere, wegwerfbare Datenbank – nie gegen
   echte Schuldaten, nie gegen die Produktion.
2. **Alles in Containern.** Lokal und später in CI identisch, ohne Ruby-,
   Node- oder Browser-Installation auf dem Host.
3. **Getrennt von der Entwicklungsinstanz.** Eigener Compose-Projektname,
   eigene Ports, eigene Daten-Verzeichnisse. Eine laufende Dev-Instanz bleibt
   unberührt.
4. **Erst absichern, dann umbauen.** Vor jeder größeren Änderung (z. B. am
   Template-Renderer oder an der Anmeldung) muss der betroffene Bereich durch
   Tests abgedeckt sein, insbesondere durch E2E-Tests der echten Abläufe.
5. **Jeder behobene Fehler bekommt einen Test**, der ihn vorher gezeigt hätte.

## Erkundungslauf gegen eine Entwicklungsinstanz

Der Seiten-Smoke-Test kann auch gegen eine laufende Entwicklungsinstanz
laufen, z. B. mit einer aktuellen Kopie der echten Daten. Das findet Fehler,
die die Beispieldaten nicht auslösen. Es gibt dabei keinen Vergleich mit der
Bestandsaufnahme, sondern einen Bericht mit Statuscode und Antwortzeit pro
Seite und Rolle in `test/e2e/test-results/page-report.json`.

```
E2E_BASE_URL=http://localhost:8025 LOGIN_CODE=123456 \
SMOKE_ACCOUNTS='{"admin": "…", "lehrkraft": "…", "schueler": "…"}' \
E2E_ARGS="--project=smoke tests/pages.smoke.ts" ./test.sh e2e-run
```

- `LOGIN_CODE` ist der feste Anmeldecode im Development-Modus.
- Ist ein `admin` angegeben, werden die übrigen Rollen über „Anmelden als“
  angemeldet (für Konten mit OTP-App).
- Die Seiten werden nur abgerufen (GET), JavaScript läuft nicht.
- **Echte Daten:** Konten nur über die Umgebung übergeben, den Bericht
  nicht committen (`test-results/` ist ignoriert), in Auswertungen nur
  Seitennamen, Fehlerarten und Zeiten nennen.

## Testebenen

| Ebene | Werkzeug | Läuft gegen | Wofür |
|---|---|---|---|
| Unit | minitest | einzelne Ruby-Dateien, Abhängigkeiten gestubbt | Parser, Hilfsfunktionen, Validierung |
| Integration | minitest + rack-test | `Main` mit Beispieldaten und Test-Neo4j | API-Verträge, Rollenprüfungen, alle Seiten rendern |
| E2E | Playwright (Container `mcr.microsoft.com/playwright`) | kompletter Stack (nginx, ruby, neo4j, timetable …) | echte Abläufe im Browser, Desktop und Handy |
| ergänzend | axe-core in Playwright, Screenshots | E2E-Stack | Barrierefreiheit, ungewollte Layout-Änderungen |

### Unit-Tests

Viele Funktionen hängen an `Main` und Klassenvariablen. Für Unit-Tests
(`src/ruby/test/unit/`) gibt es deshalb dieses Muster:

```ruby
require 'minitest/autorun'
module Sinatra; class Base; def self.get(*) end; def self.post(*) end; end; end
class Main < Sinatra::Base
  def assert(cond, msg = 'assertion failed', *) = (raise msg unless cond)
end
require_relative '../include/color'

class ColorTest < Minitest::Test
  def test_luminance
    assert_in_delta 255.0, Main.allocate.luminance('#ffffff'), 0.01
    assert_in_delta 0.0, Main.allocate.luminance('#000000'), 0.01
  end
end
```

Weitere Kandidaten:

- `parser.rb`: Untis-Stundenplan und Kurswahlen (Fächer, Lehrkräfte und
  Ferien sind abgedeckt).
- `include/theme.rb`, `color_palette_for_color_scheme`.
- `parse_request_data`: Pflichtfelder, Typen, Längen.
- Hilfsfunktionen in `include/user.rb` (Rollen-Helfer mit gestubbten
  `@@users_for_role`).

### Integrationstests

`main.rb` lädt beim Start `/data/config.rb`, verbindet sich mit Neo4j und
liest alle Eingangsdaten. Integrationstests nutzen genau das – mit
Beispieldaten und einer frischen Datenbank – und sprechen die Anwendung über
`rack-test` an, ohne Browser.

Geplante Suiten:

1. **Seiten-Smoke-Test** – umgesetzt in `pages.smoke.ts` (siehe oben) für
   anonym, Schüler:innen, Lehrkraft, Admin und weitere Rollen; es fehlt noch
   die Rolle „Gerät“.
2. **Berechtigungsmatrix**: Für jede API-Route (`grep -h "^ *\(get\|post\) '/api/" src/ruby -r`)
   wird mit jeder Rolle ein minimaler Aufruf gemacht. Die erwarteten
   Ergebnisse stehen in einer Tabelle (`test/fixtures/api_roles.yaml`).
   Neue Routen ohne Eintrag lassen den Test fehlschlagen.
3. **Anmeldung**: E-Mail-Code, OTP, Zwei-Faktor für Lehrkräfte (alle
   Kombinationen aus erstem und zweitem Faktor), abgelaufene Codes, zu viele
   Versuche, Kontowechsel, Abmelden.
4. **Uploads**: erlaubte und abgelehnte Dateitypen, Dateinamen mit
   Sonderzeichen.
5. **Fachliche Abläufe pro Modul**: Nachricht senden/lesen, Umfrage
   anlegen/beantworten, Termin anlegen, Notiz zur Stunde speichern – jeweils
   inklusive der Prüfung, was danach in Neo4j und unter `/gen` steht.

Für Zeitabhängigkeiten (viele Stellen nutzen `Date.today`/`Time.now`) läuft
der Test-Container mit fester Systemzeit (`libfaketime`, z. B. ein Datum im
Schuljahr der Beispieldaten).

### E2E-Tests

Playwright im offiziellen Container, gegen den kompletten Stack mit
Beispieldaten im Produktionsmodus. `login(page, email)` und
`apiLogin(request, email)` in `tests/fixtures.ts` melden sich wie ein Mensch
an: Code aus der Mail (Mailpit) oder aus der OTP-App (TOTP wird im Test
berechnet), bei Lehrkräften mit zweitem Faktor.

Abläufe, die zuerst abgedeckt werden (Desktop **und** Handy-Viewport):

| Ablauf | Einstieg | Rolle |
|---|---|---|
| Anmeldung per Code, Weiterleitung `return_to`, Abmelden | `/` | alle |
| Zwei-Faktor-Anmeldung Lehrkraft (E-Mail, SMS-Stub, OTP) | `/` → `/c/…` | Lehrkraft |
| Stundenplan anzeigen, Woche wechseln, Stunde öffnen | `/` | SuS, Lehrkraft |
| Notiz/Hausaufgabe zur Stunde speichern, bei SuS sichtbar | `/lessons/…`, `/` | Lehrkraft → SuS |
| Nachricht schreiben und empfangen | `/messages` | Lehrkraft → SuS |
| Umfrage anlegen, beantworten, Ergebnis ansehen | `/polls`, Seitenleiste | Lehrkraft, SuS |
| Termin anlegen, Einladung | `/events` | Lehrkraft |
| Profil: Farbschema, Dunkelmodus, Schrift | `/profil` | alle |
| Sitzplan erstellen und anzeigen | `/sitzplan…` | Lehrkraft |
| Admin: Übersicht, Kontowechsel als andere Person | `/admin` | Admin |
| Neustart-Seite erscheint und lädt neu, wenn `ruby` gestoppt/gestartet wird | beliebig | alle |

Selektoren: vorhandene IDs (`bu_…`, `ti_…`, `…Modal`) nutzen; wo es keine
stabilen Haken gibt (z. B. serverseitig erzeugte Tabellen, Navigation),
schrittweise `data-testid` ergänzen.

Zusätzlich in jedem E2E-Lauf:

- Browser-Konsole auf JavaScript-Fehler prüfen (Test schlägt fehl).
- Keine Antwort mit Status 500 im Netzwerkverlauf.
- axe-core auf den Hauptseiten (zunächst nur berichten, nicht fehlschlagen).

## Infrastruktur

Aufbau:

- `src/ruby/test/unit/` – Unit-Tests (`*_test.rb`, gemeinsames Setup in
  `test_helper.rb`), Runner `src/ruby/test/run_unit.rb`. minitest ist bereits
  im Bundle enthalten.
- `src/ruby/test/credentials.rb` – Zugangsdaten des Test-Stacks.
- `src/ruby/test/create_sso_keys.rb` – Wegwerf-Schlüssel für den Test-Stack.
- `test/e2e/` – Playwright (`package.json`, `playwright.config.ts`,
  `tests/*.spec.ts`, gemeinsame Hilfen in `tests/fixtures.ts`). Läuft im
  Container `mcr.microsoft.com/playwright` mit derselben Version wie
  `@playwright/test`.
- Datenverzeichnis des Test-Stacks wird bei jedem Start und Stopp gelöscht;
  Stundenpläne werden nach dem Start einmal geschrieben.

Noch offen:

1. **Integrationstests**: `rack-test` als Test-Gruppe ins Gemfile,
   `src/ruby/test/integration/`, `./test.sh integration`.
2. **Test-Konto-Daten**: `src/example-data` um je ein Konto pro Rolle
   ergänzen (Admin, Lehrkraft mit Klassenleitung, Schüler:in, Elternteil,
   Gerät), damit alle Abläufe abgedeckt werden können.
3. **Feste Systemzeit** für den Test-Stack (Beispieldaten gelten für das
   Schuljahr 2024/25).
4. **CI** (später): GitHub Actions, die `./test.sh all` auf jedem Pull
   Request ausführen. Das Repo ist öffentlich – Testnamen und Fixtures
   neutral halten.

## Vorhandene Ansätze

- `src/ruby/nextcloud-client-compatibility-test.rb` (minitest)
- `src/ruby/puma-integration-test.rb` (startet Puma, prüft Kodierungen und
  WebSockets)
- `src/scripts/check-all-timetables.js` (Puppeteer gegen eine laufende
  Instanz)

Diese werden in die neue Struktur übernommen.

## Reihenfolge

1. ~~**Grundgerüst**: Test-Umgebung (`DASHBOARD_ENV`, Ports), `test.sh`,
   ein erster Unit-Test, ein erster E2E-Test (Anmeldung).~~ erledigt
2. **Sicherheitsnetz für Umbauten**: ~~Seiten-Smoke-Test~~ (erledigt),
   Berechtigungsmatrix, alle Anmelde-Abläufe als Integration **und** E2E.
3. **Hauptabläufe E2E** (Tabelle oben), Desktop und Handy.
4. **Module**: je Modul die wichtigsten API-Abläufe als Integrationstests.
5. **Laufend**: jeder Bugfix mit Test; CI.
