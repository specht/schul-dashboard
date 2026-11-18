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
  Sheets, Menüs). Seitenlogik bleibt in der Seite. Muss eine Seite im alten
  Design Byte für Byte gleich bleiben, steht ihr Teil für das neue Design in
  `src/static/preview/<seite>.js`, den die Seite nur im neuen Design lädt
  (Beispiel: Termine).
- **Achtung Tailwind:** Die Entwicklungsinstanz erzeugt `tailwind.css` neu,
  sobald sich Dateien unter `src/static` ändern, und liest dabei jedes Wort
  als möglichen Klassennamen, auch in Skripten (`if (!grid)` ergibt eine
  Klasse `!grid`). Ändert sich `tailwind.css` unerwartet, das Wort im Code
  umbenennen und die Datei zurücksetzen, nicht mit einchecken.
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
  Einträgen als Kacheln, farbig nach Gruppe. Alle Kacheln folgen einem
  Muster (Symbol mittig über der Beschriftung, gleiche Höhe, die Symbole
  einer Reihe auf einer Linie, auch bei zweizeiliger Beschriftung), und jede
  Reihe ist voll: Bleiben in einer Gruppe Kacheln übrig, werden die
  letzten breiter (zwei übrig: je halbe Breite; eine übrig: die letzten
  vier als zwei Reihen zu zwei).
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

## 6a. Seitentypen

Die meisten Seiten gehören zu einem dieser Typen; er bestimmt Breite,
Aktionen und das Verhalten am Handy.

| Typ | Beispiele | Breite am Desktop |
|---|---|---|
| Liste mit Aktionen | Umfragen, Abstimmungen, Termine, Verteiler, Gruppen | höchstens etwa 980 px |
| Tabelle | Kurslisten, Klassenlisten, Statistiken, Admin-Übersichten | volle Breite |
| Formular und Editor | Umfrage bearbeiten, Termin anlegen, Profil | höchstens etwa 980 px |
| Lesen und Verlauf | Nachrichten, Kursbuch, Hilfe | höchstens etwa 980 px (Nachrichten: Liste und Nachricht nebeneinander) |
| Überblick | Stundenplan, Monitore | volle Breite |

**Liste mit Aktionen**

- **Desktop und Tablet:** Titel und Hauptaktion in einer Zeile, darunter
  bei Bedarf Filter als Chips. Jede Zeile zeigt Titel und eine leise
  Faktenzeile, rechts ein bis zwei sichtbare Aktionen als leise
  Textknöpfe und »•••« für den Rest. Löschen, Kopieren und seltene
  Aktionen stehen immer im »•••«-Menü, nie in der Zeile.
- **Handy:** die Zeile selbst öffnet das Element (Pfeil »›« am Ende), alle
  Aktionen stehen im »•••«-Sheet. Die Hauptaktion steht im Seitenkopf
  neben dem Titel, kurz beschriftet (»Neu«); kein schwebender Knopf.
- **Unterelemente** (Durchführungen einer Umfrage, Termine einer Reihe):
  laufende und geplante als Zeilen unter dem Element, beendete gefaltet
  (»2 beendete Durchführungen anzeigen«).
- **Eigenes zuerst:** Wo alle die Einträge aller sehen, stehen die eigenen
  (und die mit einem geteilten) als Abschnitt »Meine …« oben, darunter
  »Alle anderen« mit Suche (Beispiel: AGs und Angebote).
- **Mitglieder** (Teilnehmer einer AG) stehen nie als Namensliste in der
  Zeile: die Anzahl ist ein leiser Knopf in der Faktenzeile und klappt sie
  unter der Zeile auf, eine Zeile pro Klasse, die Klasse in fester Spalte.

**Formular und Editor**

- Kurze Formulare in einem Dialog, am Handy als Sheet.
- Lange Editoren als Dialog in voller Höhe, am Handy als Sheet über den
  ganzen Bildschirm; »Speichern« bleibt immer sichtbar.

**Tabelle**

- Am Handy werden Zeilen zu Listenzeilen: Name und die zwei oder drei
  wichtigsten Werte, der Rest beim Öffnen der Zeile.
- Echte Matrizen (Noten pro Arbeit, Anwesenheit pro Tag) scrollen am Handy
  seitlich, die erste Spalte bleibt stehen.
- Ob Tabelle oder Listenzeilen, entscheidet die Breite der Liste
  (Container-Abfrage), nicht das Gerät: Tablets hochkant zeigen schon
  Listenzeilen. Eine Listenzeile öffnet einen Dialog (am Handy ein Sheet)
  mit allen Angaben und Aktionen (Beispiel: Klassenliste).
- Einfache Tabellen ohne eigenen Dialog (Bibliothek) werden in schmalen
  Listen zu Listenzeilen: die erste Spalte als Titel, die übrigen als
  leise Angaben mit ihrem Spaltennamen davor; die Zeile öffnet, was sie
  vorher geöffnet hat.

**Bereiche mit eigener Navigation** (Beispiel: Bibliothek)

- Die Seiten eines Bereichs stehen als Zeile leiser Reiter oben auf dem
  Panel, die eigenen Seiten zuerst, die Verwaltung nach einer Haarlinie;
  der aktuelle Reiter in der leisen Akzentfläche. Am Handy scrollt jede
  Gruppe als eigene Zeile seitlich. Links, die nur eine Seite hat
  (»Metadaten bearbeiten«), stehen als zweite, kleinere Zeile darunter.
- Geräte eines Bereichs (die Ausleihstation der Bibliothek) zeigen keine
  Navigation des Dashboards, nur ihre Leiste mit der angemeldeten Person.

**Scannen**

- Kamera und Eingabefeld sind eine ruhige Fläche; ein Scanner tippt wie
  eine Tastatur. Nach jedem Scan bleibt der Fokus im Feld, an Geräten der
  Bibliothek hat es ihn schon beim Laden.
- Ein Modus, der das Scannen ändert (Rückgabe: zurückbuchen oder nur
  prüfen), ist ein Schalter, der seinen Zustand in Worten sagt; »nur
  prüfen« ist leise hervorgehoben, damit man ihn nicht vergisst.

**Lange Listen und Archiv**

- Nie alles auf einmal zeigen: Aktuelles zuerst, Älteres nach Schuljahr
  gefaltet oder nachgeladen. Lange Listen werden in Blöcken von 50 Zeilen
  gezeigt, weitere beim Scrollen, mit einem Knopf »Ältere …« als Rückfall.
- Eine Suche über die ganze Liste, wo Listen lang werden können.
- Das alte Design behält seine Datenwege; Nachladen für das neue Design
  kommt über zusätzliche, nur lesende Abfragen.

**Bausteine** (`pv_list` in `preview.js`, Styles in `preview.css`; Beispiele:
Umfragen, Termine, News verwalten)

- `pv_list.page`: setzt den Seitentyp (`.pv-page-list`, höchstens etwa
  980 px) und stellt Titel und Hauptaktion in eine Zeile, am Handy »Neu«.
- `pv_list.row`: eine Zeile (`.pv-lrow`) mit Titel, leiser Faktenzeile,
  sichtbaren Aktionen und »•••«; am Handy öffnet die Zeile das Element.
- `pv_list.row({sub: true, chip})`: eine Unterzeile, eingerückt, mit
  Status-Chip; laufende mit Akzentlinie links.
- `pv_list.menu`: das »•••«-Menü neben dem Knopf, am Handy ein Sheet mit dem
  Titel oben; Pfeiltasten, Escape schließt, »Zurück« schließt das Sheet,
  Löschen in ruhigem Rot am Ende.
- `pv_list.confirm_delete`: Löschen immer mit `dashboardConfirm` und
  `danger: true`.
- `pv_list.fold`: Gefaltetes hinter »2 beendete Durchführungen anzeigen«.
- `pv_list.group`: ein Abschnitt mit Überschrift (»Schuljahr 2025/26«) und
  Anzahl, gefaltet oder offen, beim ersten Öffnen gefüllt oder nachgeladen.
- `pv_list.blocks`: lange Listen in Blöcken von 50, weitere beim Scrollen,
  »Ältere … laden« als Rückfall.
- `pv_list.school_year`: das Schuljahr eines Datums (1. August bis
  31. Juli), `school_year_label` die Beschriftung.

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
- **Kopieren:** Was man oft kopiert (eine Verteileradresse), ist selbst ein
  leiser Knopf mit Kopier-Symbol; ein Klick kopiert, an Stelle des Symbols
  erscheint kurz ein grüner Haken (Tabler, springt kurz auf, gleich groß, damit
  nichts verrutscht; Screenreader hören »kopiert«). Kein Dialog, kein
  eigenes Eingabefeld. Adressen stehen dafür als einzeiliges graues Feld
  mit dem Kopier-Feld am Ende da; lange Adressen enden in »…«, der Tooltip
  zeigt sie ganz (`pv_copy` in `preview.js`, `.pv-copy` in `preview.css`;
  Beispiele: Verteiler, Klassenliste, Passwörter).
- **Passwörter** stehen im selben Kopier-Feld, aber als Punkte, bis man
  daneben auf das leise »Anzeigen« tippt (dann »Verbergen«). Kopieren geht
  auch verdeckt; Tooltip und Screenreader nennen nie das Passwort selbst,
  nur »Passwort kopieren« (Beispiel: Passwörter).

## 8. Dialoge, Sheets und Menüs

- **Keine nativen Dialoge** (`alert`, `confirm`, `prompt`), sondern
  `dashboardAlert` und `dashboardConfirm` aus `_template.html`. Der Fokus
  liegt zuerst auf »Abbrechen«.
- **Am Handy** sind Dialoge und Menüs Sheets von unten (`.pv-sheet` auf dem
  Modal): sie gleiten hoch, lassen sich nach unten ziehen oder über den
  Schleier schließen und liegen über der Tab-Leiste.
- **Hinter einem offenen Sheet steht die Seite still:** sie scrollt nicht
  mit, auch nicht beim Wischen auf dem Schleier, und steht nach dem
  Schließen wieder genau dort, wo sie war (`preview.js`; eigene Sheets
  setzen dafür `body.pv-sheet-open`). Scrollt ein Sheet selbst, endet das
  an seinem Rand.
- Ungespeicherte Änderungen werden vor dem Schließen nachgefragt.
- **Zurück schließt, was wie ein eigener Bildschirm aufgeht.** Die
  Zurück-Geste (Wischen vom Rand, Zurück-Taste des Handys oder Browsers)
  schließt das oberste Sheet, den obersten Dialog, »Mehr« oder eine
  geöffnete Nachricht und verlässt die Seite nicht. Bootstrap-Dialoge und
  »Mehr« machen das von selbst (`preview.js`); eigene Ebenen melden sich mit
  `pv_back.opened(id, schließen)` beim Öffnen und `pv_back.closed(id)` beim
  Schließen an. Ansichten, die man teilen oder neu laden können soll (eine
  geöffnete Nachricht), stehen zusätzlich in der Adresse (Hash), damit
  Neuladen sie wieder öffnet.
- **Wischgesten** der Seite (Tag für Tag, Karten) beginnen nicht in den
  äußersten 24 px am Rand: dort liegt die Zurück-Geste des Systems.
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

- Die Oberfläche ist deutsch. Das Dashboard spricht alle mit »du« an,
  Schülerinnen und Schüler, Eltern und Lehrkräfte. Alte Texte mit »Sie«
  werden angepasst, wenn eine Seite ins neue Design kommt.
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
- **Nur Tabler, keine eigenen Zeichen:** Pfeile, Haken, Kreuze und Menüpunkte
  sind immer Tabler-Symbole (`ti-chevron-right`, `ti-chevron-down`,
  `ti-check`, `ti-x`, `ti-dots`). Nie mit CSS gezeichnet (gedrehte Rahmen,
  eigene SVG-Pfade) und nie Schriftzeichen als Symbol (»›«, »×«, »✓«,
  »•••«, »▾«): sie sehen in jeder Schrift anders aus. Im CSS (`::after`)
  geht ein Tabler-Symbol mit seinem Zeichencode und
  `font-family: "tabler-icons"`. Aufgeklappt dreht sich der Pfeil.

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

## 12a. Monitore im Flur

- **Eigener Schalter pro Bildschirm.** Die Monitore laufen den ganzen Tag im
  Schulhaus und folgen nie der Vorschau eines Kontos. Das neue Design
  bekommt nur ein Monitor, dessen Adresse `?design=neu` (hell) oder
  `?design=neu-dunkel` (dunkel) trägt, und nur im Flur; Sekretariat,
  Lehrerzimmer und Silentium bleiben, wie sie sind. Ohne den Parameter
  liefert `/monitor` dieselben Bytes wie vorher (`include/monitor_neu.rb`,
  `preview/monitor/`).
- **Feste Kacheln.** Jede Klasse hat immer ihre Kachel an derselben Stelle,
  auch ohne Änderungen (dann steht nur der Name darin, leise). Wo eine
  Klasse steht, hängt nie davon ab, welche Klassen heute Änderungen haben:
  man findet seine Klasse jeden Tag am selben Platz. Die Verteilung ist
  die des bisherigen Monitors, mit Absicht: die Klassen in der Reihenfolge
  von `KLASSEN_ORDER` von oben nach unten in Spalten zu je sieben, vier
  Spalten nebeneinander, 11 und 12 höher (wie bisher 9,8 zu 6,2). Leere
  Plätze für Klassen, die es nicht gibt, kommen nicht vor.
- **Blättern statt Scrollen.** Was nicht in eine Kachel passt, blättert in
  der Kachel (Punkte zeigen die Seite); alle Kacheln blättern im selben
  Takt, jede Seite steht 15 Sekunden, ein Balken im Fuß zeigt die
  Standzeit. Nichts wird abgeschnitten.
- **Aufteilung:** Kopf mit Titel, Datum und Stand, großer Uhr und der
  laufenden Stunde auf dem Hintergrund des Farbschemas, darunter die
  Kacheln; im Fuß Nachrichten und das Farbschema.
- **Zustände als Marke** (Vertretung, Entfall, Raum, Klausur, Verlegt,
  Aufgaben) statt Durchgestrichenem; »Se statt Pe« in Worten.
- **Maße in `vw`**, damit dieselbe Seite auf Full HD und in den kleinen
  Vorschauen auf »Monitore verwalten« gleich aussieht. Einträge mindestens
  1,15 vw (22 px auf Full HD, heute 20 px).

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
