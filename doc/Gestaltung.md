# Gestaltung: Regeln für das neue Design

Dieses Handbuch hält fest, wie das neue Design des Dashboards aussieht und
sich verhält. Es gilt für alles, was im neuen Design läuft, und für alle, die
daran arbeiten, Menschen wie KI-Agenten. Wer eine Seite umbaut oder neu
anlegt, richtet sich danach; wer eine neue Entscheidung trifft, trägt sie hier
ein, damit die nächste Änderung sie kennt.

Das neue Design ist zunächst eine Vorschau, die man im Profil einschaltet.
Beide Designs laufen nebeneinander, mit denselben Seiten.

## 1. Grundsätze

- **Ruhig.** Wenig Rahmen, wenig Farbe, keine Effekte um ihrer selbst willen.
  Farbe zeigt, was wichtig ist: die eine Hauptaktion, das Fach, den Status.
- **Inhalt vor Rahmen.** Kästen, Linien und Schatten trennen nur, wo es
  nötig ist. Was zusammengehört, steht beieinander; was getrennt ist, hat
  Abstand.
- **Gleiches sieht gleich aus.** Ein Knopf, eine Liste, ein Dialog verhalten
  sich auf jeder Seite gleich.
- **Für alle Geräte.** Jede Seite funktioniert am Handy, am Tablet und am
  Desktop, hell und dunkel, mit jedem Farbschema.
- **Das alte Design bleibt, wie es ist.** Solange beide Designs laufen, darf
  eine Änderung für das neue Design das alte nicht verändern, auch nicht um
  ein Pixel.

## 2. Wohin der Code gehört

- **Eine Seite, zwei Rahmen.** Seiten werden nicht kopiert (keine
  `foo.v2.html`). `_template.html` lädt den Rahmen, den die Person gewählt
  hat.
- **Server:** `ui_preview?` (`include/design_preview.rb`) entscheidet. Alles,
  was nur das neue Design braucht, steht hinter dieser Abfrage.
- **Browser:** Seitenverhalten für das neue Design prüft
  `document.body.classList.contains('ui-preview')`.
- **Styles:**
  - `src/static/preview.css`: Rahmen, Tokens und alles, was viele Seiten
    teilen (Knöpfe, Dialoge, Tabellen, Formulare).
  - `src/static/preview/<bereich>.css`: was nur einen Bereich betrifft
    (Nachrichten, Umfragen, Anmeldung …). Diese Dateien werden automatisch
    geladen. Regeln darin beginnen mit `.ui-preview` oder mit einer Klasse,
    die nur die Seite im neuen Design setzt, damit sie nicht in andere
    Seiten durchschlagen.
- **Skripte:** `src/static/preview.js` enthält nur Allgemeines (Navigation,
  Sheets, Menüs). Seitenlogik bleibt in der Seite.
- **Prüfen, dass das alte Design gleich bleibt:** dieselbe Seite mit
  ausgeschalteter Vorschau vor und nach der Änderung vergleichen
  (Screenshots oder DOM), am Desktop und am Handy.

## 3. Der Rahmen

- **Desktop:** eine Seitenleiste links. Oben die Schule, dann Stundenplan,
  Nachrichten und Datentresor, darunter aufklappbare Abschnitte (Unterricht,
  Schule, Verwaltung) mit Untergruppen nur als Abstand. Unten fest: Suche,
  die eigene Person (das Menü öffnet sich nach oben, unten bündig) und ganz
  unten eine leise Zeile mit ©, Impressum und dem GitHub-Symbol. Nur die
  Liste darüber scrollt. Menüs öffnen sich als Feld neben der Leiste, auf
  Höhe ihres Eintrags; sind sie länger als das Fenster, in Spalten.
- **Tablet:** dieselbe Leiste als schmale Symbolleiste, die Namen als
  Tooltip.
- **Handy:** keine Kopfleiste. Unten eine Tab-Leiste (Lehrkräfte: Heute,
  Woche, Nachrichten, Kurse, Mehr; Schülerinnen und Schüler: Heute, Woche,
  Aufgaben, Nachrichten, Mehr). »Mehr« ist ein Sheet mit Suche oben und den
  Einträgen als Kacheln, farbig nach Gruppe.
- **Suche:** überall mit `/` oder `Strg+K`. Sie findet Seiten, Kurse,
  Personen und Links nach Name und Stichwort.
- **Die Seite selbst** steht auf einem Panel (`--pv-surface`, Radius 14 bis
  16 px) über dem Hintergrund des Farbschemas.

## 4. Farben

Farben kommen aus Tokens, nie als feste Werte in die Seite. Die Tokens
werden aus dem Farbschema berechnet (`design_tokens.rb`) und sind für hell
und dunkel auf Kontrast geprüft.

| Token | Wofür |
|---|---|
| `--pv-surface` | Fläche von Panels, Dialogen, Menüs |
| `--pv-ink`, `--pv-muted` | Text, leiser Text |
| `--pv-line` | Haarlinien und Rahmen |
| `--pv-hover` | Hover, leise Flächen (Chips, Status) |
| `--acc`, `--acc-ink` | die Hauptaktion und ihre Schrift |
| `--acc-soft`, `--acc-text` | leise Akzentflächen, Akzent als Textfarbe |
| `--subj-<fach>`, `--subj-<fach>-ink` | Fachfarbe und Schrift darauf |
| `--band-ink`, `--band-scrim` … | Schrift auf dem Hintergrundbild |

- **Kontrast:** Text mindestens 4,5 : 1, große Schrift 3 : 1. Wer die Tokens
  benutzt, hält das ein.
- **Rot** gibt es nur für Löschen und Fehler: als rote Schrift auf ruhigem
  Grund (`#b42318`, dunkel `#ff8f8f`), als volles Rot nur im
  Bestätigungsdialog.
- **Fächer** haben feste Farben aus dem Schema; das Fachkürzel steht immer
  dabei, Farbe ist nie das einzige Merkmal.
- **Farbschemata:** eine kuratierte Auswahl, dazu eigene Schemata aus drei
  Farben. Der Regler »Farbigkeit« dämpft die Spreizung der Fachfarben.
  Änderungen an Schema, Farbigkeit und hell/dunkel wirken sofort, ohne
  Neuladen; neue Elemente müssen das mitmachen (Tokens statt berechneter
  Werte).
- **Hell und dunkel** gibt es für jede Seite, unabhängig vom Farbschema
  (`body.dark`).

## 5. Schrift und Zahlen

- Text in `--pv-text`, Überschriften in `--pv-display`, Code und Kürzel bei
  Bedarf in `--pv-mono`.
- Zahlen, die untereinander stehen oder sich ändern (Uhrzeiten, Daten,
  Zähler), mit `font-variant-numeric: tabular-nums`.
- Wochentage vor Daten in fester Breite (`.pv-weekday`), damit die Daten
  eine Spalte bilden.

## 6. Flächen und Abstände

- **Eine Fläche.** Auf dem Panel einer Seite liegt keine weitere Karte mit
  Rahmen, und in einer Karte keine graue Box. Wer gliedern will, nimmt
  Abschnitte mit Überschrift, eine Haarlinie (`--pv-line`) oder Abstand.
- **Listen** sind Zeilen mit Haarlinien dazwischen, keine Kästen. Ein Status
  darf eine schmale Akzentlinie am linken Rand bekommen.
- **Fakten** in einer leisen Zeile mit Kommas (»26 Teilnehmer, mit Namen«),
  nicht als Reihe von Pillen. Chips nur für Dinge, die man anklickt oder
  entfernt (Empfänger, Filter) oder für einen einzelnen Status.
- **Radien:** Panels und Dialoge 14 bis 16 px, Elemente darin 8 bis 12 px,
  Chips rund.
- **Leere Zustände:** ein kurzer, hilfreicher Satz, was hier erscheint und
  wie man anfängt. Keine gestrichelten Kästen.

## 7. Knöpfe

- **Eine Hauptaktion pro Ansicht** in vollem Akzent (dunkel mit heller
  Schrift): »Senden«, »Neue Umfrage«, »Speichern«.
- **Weitere Aktionen** neutral grau. In Listen, die sich wiederholen, leise
  Textknöpfe ohne Rahmen und Fläche, die erst beim Hover eine Fläche
  bekommen.
- **Löschen** ist ruhig: rote Schrift oder ein Papierkorb-Symbol mit
  `aria-label`. Erst die Bestätigung zeigt volles Rot (`danger: true`) mit
  einer klaren Beschriftung (»Löschen«, »Verwerfen«).
- **Nie über die ganze Breite** gezogen, außer der Hauptaktion in der
  Fußzeile eines Sheets am Handy.
- **Beschriftungen** sind Verben oder klare Ziele (»Ergebnisse«,
  »Bearbeiten«), kurz genug für eine Zeile am Handy. Abläufe für Admins
  lesen sich als Schritte (»1. Prüfen«, »2. Zurücksetzen«).
- **Gruppen** (Eingabe mit Knöpfen) wirken als eine Einheit.
- Reihenfolge in Fußzeilen: Löschen am Anfang, die Hauptaktion am Ende.

## 8. Dialoge, Sheets und Menüs

- **Keine nativen Dialoge** (`alert`, `confirm`, `prompt`), sondern
  `dashboardAlert` und `dashboardConfirm` aus `_template.html`. Der Fokus
  liegt zuerst auf »Abbrechen«.
- **Am Handy** sind Dialoge und Menüs Sheets von unten (`.pv-sheet` auf dem
  Modal): sie gleiten hoch, lassen sich nach unten ziehen oder über den
  Schleier schließen und liegen über der Tab-Leiste.
- Ungespeicherte Änderungen werden vor dem Schließen nachgefragt.
- Auf dem Desktop öffnen sich Menüs der Seitenleiste als Feld daneben (siehe
  3); Menüs im Fuß öffnen sich nach oben.

## 9. Ausrichtung und Listen

- **Oben ausrichten:** Symbole, Fach-Chips, Profilbilder und Pfeile neben
  Text, der umbrechen kann, stehen auf Höhe der ersten Zeile, nicht mittig.
  Ausnahme: einzeilige Tabellenzellen werden in ihrer Zeile mittig
  ausgerichtet.
- Tabellenzellen vertikal mittig (außer im Kursbuch), Zahlen rechtsbündig
  oder in fester Breite.
- Daten kurz und lesbar: »Mo, 9.11., 8:00 Uhr«, Zeitspannen mit »bis«.
  Überschriften für Tage: »Heute«, »Gestern«, »Montag, 16.11.«.

## 10. Sprache

- Die Oberfläche ist deutsch. Schülerinnen und Schüler werden mit »du«
  angesprochen, Lehrkräfte mit »Sie« dort, wo sich ein Text nur an sie
  richtet.
- **Kein Mittelpunkt »·« als Trenner**, nirgends in sichtbarem Text. Statt
  dessen Kommas, kurze Wörter (»um«, »statt«, »bis«) oder Abstand.
- Kurz, sachlich, freundlich. Keine Ausrufezeichen-Kaskaden, keine
  Füllwörter, keine Fachsprache, wo ein Alltagswort reicht.

## 11. Bilder und Symbole

- **Profilbilder** sind immer Kreise (feste Größe, `aspect-ratio: 1`). Sie
  kommen aus der Nextcloud, die ohne eigenes Bild selbst ein Standardbild
  liefert. Keine erfundenen Bilder oder Initialen.
- **Symbole:** Tabler Icons (selbst gehostet). Im neuen Design werden
  Fork-Awesome-Symbole im Browser ersetzt; neue Stellen schreiben gleich
  Tabler-Symbole. Ein Symbol neben Text ist leiser als der Text.

## 12. Stundenplan

- Handy: der Tag als Agenda mit Kopf auf dem Hintergrund und Tagesleiste
  Mo bis Fr; größere Bildschirme: nur die Woche, auf breiten Bildschirmen
  mit einer Spalte daneben.
- Eine Doppelstunde ist doppelt so hoch wie eine Einzelstunde, mit kleinen
  Kerben links und rechts und einer schwachen Naht in der Mitte.
- Der Zeitraster der Woche zeigt den Schultag (frühester bis spätester
  Unterricht).
- **Achtung FullCalendar:** im Zeitraster selbst (`.fc-timegrid-body`,
  Spalten, Slots) keine Polster oder Verschiebungen. FullCalendar misst
  dort und rendert sonst endlos neu, die Seite friert ein. Abstand gehört in
  die Trennzeile (`.fc-timegrid-divider`) oder außerhalb des Kalenders.

## 13. Bewegung

- Sheets und Menüs gleiten kurz (0,2 bis 0,3 s); nichts blinkt oder hüpft.
- Bei `prefers-reduced-motion` keine Animationen.

## 14. Prüfen vor dem Übergeben

- Screenshots am Desktop (1280 × 900), Tablet und Handy (390 × 844), hell
  und dunkel, mit mindestens zwei Farbschemata.
- Mit realistisch vollen Daten: lange Namen, viele Einträge, Vertretungen,
  leere Zustände.
- Die Seite mit ausgeschalteter Vorschau: unverändert.
- E2E-Tests für das neue Design liegen in `test/e2e/tests/design-preview*.spec.ts`
  (Vorschau im Test einschalten, im `finally` wieder aus).

## Entscheidungen nachtragen

Neue Entscheidungen zum Design kommen in den passenden Abschnitt, kurz und
mit der Regel, nicht mit der Geschichte dahinter. Was nur eine Seite
betrifft, steht im Kommentar am Anfang ihres Stylesheets in
`src/static/preview/`.
