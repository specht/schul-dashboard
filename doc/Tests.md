# Tests

Stand: Plan. Das Dashboard hat bisher keine automatisierten Tests im
eigentlichen Sinn. Dieses Kapitel beschreibt, wie wir sie aufbauen wollen –
so, dass Änderungen am Code (auch größere Umbauten) abgesichert sind, bevor
sie in die Schule gehen.

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

## Testebenen

| Ebene | Werkzeug | Läuft gegen | Wofür |
|---|---|---|---|
| Unit | minitest | einzelne Ruby-Dateien, Abhängigkeiten gestubbt | Parser, Hilfsfunktionen, Validierung |
| Integration | minitest + rack-test | `Main` mit Beispieldaten und Test-Neo4j | API-Verträge, Rollenprüfungen, alle Seiten rendern |
| E2E | Playwright (Container `mcr.microsoft.com/playwright`) | kompletter Stack (nginx, ruby, neo4j, timetable …) | echte Abläufe im Browser, Desktop und Handy |
| ergänzend | axe-core in Playwright, Screenshots | E2E-Stack | Barrierefreiheit, ungewollte Layout-Änderungen |

### Unit-Tests

Viele Funktionen hängen an `Main` und Klassenvariablen. Es gibt aber schon ein
brauchbares Muster (siehe die bisherigen Einzeltests unter `src/ruby/test-*.rb`
bzw. `nextcloud-client-compatibility-test.rb`):

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

Gute erste Kandidaten:

- `parser.rb`: Untis-Stundenplan, Lehrkräfte-/SuS-Listen, Ferien, Kurswahlen
  mit den Dateien aus `src/example-data`.
- `include/color.rb`, `include/theme.rb`, `color_palette_for_color_scheme`.
- `parse_request_data`: Pflichtfelder, Typen, Längen.
- Hilfsfunktionen in `include/user.rb` (Rollen-Helfer mit gestubbten
  `@@users_for_role`).

### Integrationstests

`main.rb` lädt beim Start `/data/config.rb`, verbindet sich mit Neo4j und
liest alle Eingangsdaten. Integrationstests nutzen genau das – mit
Beispieldaten und einer frischen Datenbank – und sprechen die Anwendung über
`rack-test` an, ohne Browser.

Geplante Suiten:

1. **Seiten-Smoke-Test**: Jede Seite in `src/static/*.html` wird für jede
   Rolle (anonym, Schüler:in, Lehrkraft, Admin, Gerät) einmal abgerufen.
   Erwartet: Seite rendert oder leitet um, aber nie HTTP 500. Diese Suite ist
   die Voraussetzung für Umbauten am Template-Renderer.
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
Beispieldaten. Im Development-Modus ist der Anmeldecode fest (`123456`,
zweiter Faktor `654321`), sodass sich Tests ohne Mailserver anmelden können.
Für die Prüfung der echten Zwei-Faktor-Abläufe braucht es zusätzlich einen
Modus, in dem 2FA aktiv ist, die Codes aber abgefragt werden können (z. B. ein
Test-Mailpostfach wie Mailpit als weiterer Container).

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

Ziel: ein Befehl pro Ebene.

```
./test.sh unit
./test.sh integration
./test.sh e2e
```

Geplante Bausteine:

1. **Testgruppe im Gemfile**: `minitest`, `rack-test` (nur im Test-Image bzw.
   per `BUNDLE_WITH=test`).
2. **Verzeichnis** `src/ruby/test/` mit `unit/`, `integration/`, `fixtures/`
   und einem `test_helper.rb`; E2E unter `test/e2e/` (Playwright,
   `package.json`, `playwright.config.ts`).
3. **Eigene Umgebung für Tests**: `config.rb` liest bisher fest `env.rb`.
   Vorschlag: Umgebungsvariable `DASHBOARD_ENV` (Standard `env.rb`), damit
   `DASHBOARD_ENV=env.test.rb ./config.rb …` einen eigenen Projektnamen
   (`schuldashboardtest`), eigene Ports und ein eigenes, temporäres
   `DATA_PATH` verwendet. Ebenso müssen die bisher fest verdrahteten Host-Ports
   (8021–8025, 7687) konfigurierbar werden.
4. **Frische Datenbank pro Lauf**: Datenverzeichnis des Test-Stacks wird vor
   jedem Lauf gelöscht; Stundenpläne werden nach dem Start einmal geschrieben.
5. **Test-Konto-Daten**: `src/example-data` um je ein Konto pro Rolle
   ergänzen (Admin, Lehrkraft mit Klassenleitung, Schüler:in, Elternteil,
   Gerät), damit alle Abläufe abgedeckt werden können.
6. **CI** (später): GitHub Actions, die `./test.sh unit integration e2e` auf
   jedem Pull Request ausführen. Das Repo ist öffentlich – Testnamen und
   Fixtures neutral halten.

## Vorhandene Ansätze

- `src/ruby/nextcloud-client-compatibility-test.rb` (minitest)
- `src/ruby/puma-integration-test.rb` (startet Puma, prüft Kodierungen und
  WebSockets)
- `src/scripts/check-all-timetables.js` (Puppeteer gegen eine laufende
  Instanz)

Diese werden in die neue Struktur übernommen.

## Reihenfolge

1. **Grundgerüst**: Test-Umgebung (`DASHBOARD_ENV`, Ports), Gemfile-Gruppe,
   `test.sh`, ein erster Unit-Test, ein erster E2E-Test (Anmeldung).
2. **Sicherheitsnetz für Umbauten**: Seiten-Smoke-Test, Berechtigungsmatrix,
   alle Anmelde-Abläufe als Integration **und** E2E.
3. **Hauptabläufe E2E** (Tabelle oben), Desktop und Handy.
4. **Module**: je Modul die wichtigsten API-Abläufe als Integrationstests.
5. **Laufend**: jeder Bugfix mit Test; CI.
