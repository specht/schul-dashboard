# Sitzplanhelfer

Der Sitzplanhelfer ist die Sitzplan-Seite der Klassenleitung
(`/sitzplanhelfer/<klasse>/<raum>`). Dort entsteht jeder Sitzplan der
Klasse: mit Sitzwünschen der SuS, zufällig oder von Hand. Die Lehrkraft
behält volle Kontrolle über Vorgaben und das Endergebnis. Daneben steht
unverändert der Sitzplan-Shuffler (`src/static/sitzplan.html`), der vor
der Klasse zufällig mischt (mit optionalen statischen Regeln, siehe
„Sitzdaten“ unten) und nichts speichert.

## Einstieg

Auf der Klassenseite steht im Abschnitt „Sitzplan“ je Klassenraum ein
Knopf „Sitzplan Raum …“: für die Klassenleitung diese Seite, für die
übrigen Lehrkräfte der Klasse die Ansicht ohne Wünsche (siehe unten).
Den Shuffler öffnet die Klassenleitung über den Knopf „Shuffler“ oben auf
dieser Seite. Vorher zeigt ein Kasten seine eigenen Regeln (Bereiche je
Person und Paare mit Häufigkeit, `rules.json`/`bff.json`), die sich dort
ansehen und ändern lassen; „Shuffler starten“ öffnet ihn dann. Diese Regeln
sind getrennt von den Vorgaben der übrigen Werkzeuge. Gespeichert wird nur
unter `/internal/sitzplan` (mit Sicherung der vorigen Fassung), nie in
`/data`; beim ersten Speichern wird die alte Liste aus dem Datenrepo
vollständig übernommen, verändert werden nur die Einträge der eigenen
Klasse. Ist die bisherige Liste nicht lesbar, wird nichts gespeichert. Getrennt davon steht im Abschnitt
„Gruppenbildung“ für alle Lehrkräfte der Klasse „Gruppen bilden“, ein
eigenes Werkzeug ohne Bezug zum Sitzplan. Die früheren Knöpfe „Editor“,
„Helfer“ und „Verteilen“ gibt es dort nicht mehr: Sie stehen als
Werkzeuge oben auf der Sitzplan-Seite (siehe unten). Die alte Adresse
`/sitzplanverteilen/…` leitet auf die Sitzplan-Seite weiter.

## Ablauf für Lehrkräfte

Die Seite hat zwei Ansichten. Lange Erklärungen sind zugeklappt
(„Wie funktioniert das?“), ebenso „Vorgaben“ und „Frühere Sitzpläne“.
Die Seite spricht die Lehrkraft mit „Sie“ an.

1. **Werkzeuge**: Ganz oben steht in jeder Ansicht, auch während einer
   Wunschrunde, eine Leiste mit dem Raum und der Zahl der Plätze (gelb,
   wenn Plätze fehlen) und fünf gleichrangigen Werkzeugen:
   „Tische im Raum“ (der Editor, wo die Klassenleitung die Tische ändern
   darf; „Tische anlegen“, wenn es noch keine gibt), „Shuffler“ (lost
   zufällig aus, speichert nichts), „Von Hand verteilen“, „Im Raum
   verteilen“ und „Wunschrunde“. Das Werkzeug, mit dem der offene
   Plan entsteht, ist hervorgehoben; ist schon ein Plan offen und man
   wählt ein anderes, fragt die Seite, ob er dafür verworfen werden soll.
   Hat der Raum weniger Plätze als die Klasse SuS, lässt sich kein neuer
   Plan beginnen und der Shuffler nicht öffnen.

   **Startansicht** darunter: der aktuell gespeicherte Plan mit „Plan
   ändern“, „Für Schüler anzeigen“ (die Ansicht ohne Wünsche, etwa für den
   Beamer) und „Drucken“, die aufklappbaren „Vorgaben“ (auch ohne offenen
   Plan oder Wunschrunde bearbeitbar) und ganz unten „Frühere Sitzpläne“.
2. Drei Werkzeuge beginnen einen neuen Plan:
   - **Von Hand verteilen**: ohne Wünsche und ohne Würfeln stehen alle SuS
     zunächst unter „Noch ohne Platz“; ein Klick auf einen Namen und dann
     auf einen Platz setzt die Person dort hin.
   - **Im Raum verteilen**: ohne Umfrage wird der Plan sofort nach den
     Vorgaben gewürfelt, vor allem nach den Listen für die Verteilung im
     Raum. Jede Liste hat dabei im Plan eine eigene Farbe und ihren
     Buchstaben (nur in diesem Werkzeug). Danach kann man von Hand
     umsetzen; wer dann direkt bei jemandem von derselben Liste sitzt, wird
     rot markiert. Widersprechen sich die Vorgaben selbst (ein Zwangspaar
     auf derselben Liste, oder zwei von derselben Liste mit festen Plätzen
     direkt beieinander), sind beide im Plan knallrot mit ⚠ markiert und
     unter dem Plan aufgeführt. Gibt es noch keine Liste, weist die Seite
     darauf hin.
   - **Wunschrunde** (Umfrage an die Klasse) fragt direkt unter den
     Werkzeugen nach der Dauer (1–60 Tage, Standard 4) und legt dann eine
     Umfrage an. Die SuS sehen sie ganz normal über
     `print_current_polls()` und wählen bis zu drei gleichberechtigte
     Wunschpartner sowie optional eine Person, neben der sie nicht sitzen
     möchten. Solange die Runde läuft, zeigt die Seite die Restlaufzeit und
     wie viele SuS schon geantwortet haben (neue Antworten erscheinen alle
     30 Sekunden ohne Neuladen). „Wunschrunde jetzt beenden“ schließt die
     Umfrage vorzeitig (nach Rückfrage); die bis dahin abgegebenen Wünsche
     bleiben erhalten.

   Noch offene Pläne aus der früheren Auswahl „Zufällig würfeln“
   (`mode` `random`) funktionieren weiter, es gibt dafür nur keinen
   eigenen Startknopf mehr.
3. **Arbeitsansicht** (alle Wege und „Plan ändern“): Bei einer
   Wunschrunde zeigt eine Schrittleiste „Wünsche sammeln – Plan bauen –
   Speichern“. Die Klassenleitung sieht die Wünsche live, inkl.
   🤝-Symbol für wechselseitige Wünsche. Wünsche zählen automatisch; über
   einen Schalter lässt sich jeder einzelne Wunsch **deaktivieren** und
   wieder aktivieren. „Plan würfeln“ bzw. „Neu würfeln“ lässt den
   Algorithmus (client-seitig, siehe unten) mehrere Versuche rechnen und
   zeigt die Trefferquote an.
4. **Von Hand nachbessern**: Jede Person lässt sich per Ziehen auf einen
   anderen Platz setzen (tauscht mit der Person dort oder verschiebt auf
   einen freien Platz), oder man klickt sie an und dann den Zielplatz.
   Eine angeklickte Person lässt sich außerdem „Vom Platz nehmen“ oder mit
   „📌 Platz festhalten“ fest auf ihren jetzigen Platz setzen. Markierungen
   und Trefferquote werden sofort neu berechnet. Umgesetzt mit
   Pointer-Events, funktioniert also auch per Finger oder Stift. Jeder Zug
   lässt sich mit „Rückgängig“ zurücknehmen, auch mehrfach. Wurde von Hand
   geändert, fragt „Neu würfeln“ vorher nach. Grün ist, wer einen
   Wunschpartner neben sich hat, rötlich, bei wem etwas nicht erfüllt ist
   (Grund in der Liste darunter); rot hat Vorrang.
5. **Vorgaben** (aufklappbar, die Zahl steht in der Überschrift) haben
   immer Vorrang vor Schülerwünschen:
   - **Paare**: „müssen zusammensitzen“ und „dürfen nicht
     zusammensitzen“. Ein Paar kann nie gleichzeitig beides sein.
   - **Feste Plätze**: eine grobe Bereichsvorgabe (vorne = die ersten
     zwei Reihen, hinten, links, rechts) über die Auswahl, oder ein
     **genauer Platz** mit „📌 Platz festhalten“ im Plan. Ein genauer
     Platz kann immer nur einer Person gehören, eine Bereichsvorgabe darf
     mehrere SuS betreffen.
   - **Verteilung im Raum**: Listen von SuS (Liste A, B, …). Wer auf
     derselben Liste steht, wird im Raum verteilt: nicht am selben Tisch,
     nicht direkt davor oder dahinter und nicht schräg daneben. Das wirkt
     auch ganz ohne Wünsche (mit „Im Raum verteilen“); gibt es Wünsche,
     zählen die innerhalb einer Liste nicht (🔒). „Muss zusammen“ geht
     vor. Die Listen gehören zur Klasse und sind nur für die
     Klassenleitung sichtbar.

   Die Eingaben gelten für alle Werkzeuge. Ob ein Bereich berücksichtigt
   wird, stellt man direkt am Bereich ein, mit einem Schalter für das
   gewählte Werkzeug: Bei offenem Plan steht an
   jeder Überschrift (Paare, Feste Plätze, Verteilung im Raum) ein Schalter
   „berücksichtigen / nicht berücksichtigen“. Er gilt für das Werkzeug des
   offenen Plans, etwa „Im Raum verteilen“ oder die Wunschrunde, und wird
   je Werkzeug gespeichert. Ist der Kasten der Wunschrunde offen (vor dem
   Start), gehören die Schalter schon zur Wunschrunde. Ein ausgeschalteter Bereich bleibt erhalten,
   wirkt in diesem Werkzeug aber weder beim Würfeln noch bei den roten
   Markierungen. „Plan ändern“ richtet sich nach dem Werkzeug, mit dem der
   Plan entstanden ist. Gespeichert wird das in `SeatingRules.areas`,
   fehlende Einträge sind eingeschaltet.

   Vorgaben gelten, bis die Klassenleitung sie ändert: Jeder neue Plan
   und „Plan ändern“ übernehmen den zuletzt eingestellten Stand für
   dieselbe Klasse+Raum, auch wenn der Plan, in dem sie geändert wurden,
   verworfen wird. Ohne offenen Plan ändert man sie direkt auf der
   Startseite. Bewusst je Klasse+Raum, da die Koordinaten fester Plätze
   raumspezifisch sind. Ist noch nicht gewürfelt, zeigt der Plan die
   festen Plätze (📌), damit man sieht, wer wo festgehalten ist.
6. **Speichern** schließt eine laufende Wunschrunde automatisch und macht
   den Plan zum aktuellen Sitzplan. Bleiben SuS ohne Platz, fragt die
   Seite vorher nach. Danach zeigt die Startansicht den neuen Plan.
   **Verwerfen** (mit Rückfrage) wirft nur den offenen Plan weg; der
   gespeicherte Plan und die Vorgaben bleiben.
7. **Plan ändern** (aktueller Plan) bzw. **Bearbeiten** (jeder Plan unter
   „Frühere Sitzpläne“) öffnet einen gespeicherten Plan wieder in der
   Arbeitsansicht, ohne neue Umfrage und auf Basis der bereits erhobenen
   Wünsche. Er läuft im Werkzeug weiter, mit dem er entstanden ist (z. B.
   „Im Raum verteilen“ mit farbigen Listen), als wäre er nie gespeichert
   worden. **Speichern** überschreibt genau diesen Plan; er behält seinen
   Platz in der Liste und zeigt „geändert am …“. **Verwerfen** lässt ihn,
   wie er war.
8. **Frühere Sitzpläne**: Jeder gespeicherte Plan bleibt erhalten, ist
   einzeln anzeigbar, bearbeitbar und löschbar (z. B. bei Versehen; nicht,
   solange er gerade bearbeitet wird).
9. **Drucken** öffnet die Ansicht ohne Wünsche direkt mit Druckdialog
   (`?print=1`), sobald die Fotos geladen sind. Gedruckt werden nur
   Überschrift, Tafel und Plätze mit Foto und Namen, auf eine A4-Seite
   quer skaliert, ohne Dashboard-Menü und Hintergrund. Die Fotos sind
   echte Bilder, keine Hintergrundbilder, damit sie auch ohne die
   Browser-Einstellung „Hintergrundgrafiken“ auf dem Papier landen. Die
   Ansicht „Für Schüler anzeigen“ selbst hat keinen eigenen Druckknopf.

Jeder Platz zeigt wie im Shuffler oben das Foto (aus der Nextcloud) und
darunter den ganzen Namen, Vor- und Nachname je in einer Zeile. Passt ein
Name nicht, wird erst die Schrift kleiner, dann das Foto; abgeschnitten
wird nichts. Ist ein Raum für den Bildschirm zu breit, lässt er sich
seitlich verschieben, damit die Namen lesbar bleiben.

## Gruppenbildung

`/zufallsgruppen/<klasse>` mischt für eine Gruppenarbeit Gruppen einer
wählbaren Größe (geht es nicht auf, werden einige Gruppen größer oder
kleiner), wahlweise mit Jungen und Mädchen gemischt oder getrennt. Fehlende
SuS lassen sich antippen und werden dann nicht eingeteilt. Es gibt eine
Ansicht für den Beamer. Die Seite können alle Lehrkräfte der Klasse
nutzen; die zuletzt gemischten Gruppen sieht nur, wer gemischt hat. Die
Klassenleitung kann zusätzlich die Listen für die Verteilung im Raum und
die Zwangspaare berücksichtigen lassen; anderen Lehrkräften werden diese
gar nicht erst übertragen.

`/zufallsgruppen/kollegium` ist dieselbe Seite für das ganze Kollegium
(z. B. für Konferenzen), für Admins und die Lehrkräfte, die ein Admin dort
freigibt. Weil ganze Namen bei vielen Lehrkräften auf dem Beamer zu klein
werden, zeigt sie standardmäßig die Kürzel mit dem Nextcloud-Bild der
Person davor (der Name steht im Tooltip); auf Wunsch die Namen, die Wahl
wird gemerkt.

Die Beamer-Ansicht füllt den Bildschirm: Sie misst die Beschriftungen in
der verwendeten Schrift und probiert alle Kombinationen aus Spalten (Karten)
und Namensspalten je Karte; genommen wird die mit der größten Schrift.
Kürzel stehen so nebeneinander in gleich breiten Zellen (eine
unvollständige letzte Zeile mittig), Namen untereinander.

## Datenmodell (Neo4j)

- **`SeatingCycle`**: ein Durchlauf pro Klasse+Raum. Enthält `mode`
  (`spread`/`manual`/`random` für Pläne ohne Umfrage, fehlt bei
  Wunschrunden),
  bei Wunschrunden `poll_id`/`poll_run_id` (verweist auf die zugehörige,
  ganz normale Umfrage), `forced_pairs`/`forbidden_pairs`/`fixed_rules`
  (JSON), und
  nach dem Speichern zusätzlich `seats` (E-Mail → Sitzplatz-Index),
  `unresolved` (nicht erfüllte Vorgaben mit Begründung),
  `satisfied_emails` und `saved_at`. Pro Klasse+Raum ist immer nur
  **ein** Zyklus gleichzeitig offen (`saved_at IS NULL`).
- **`SeatingRules`** (`key` = `<klasse>/<raum>`): die geltenden
  Vorgaben, nach jeder Änderung aus dem offenen Zyklus übernommen. Neue
  Pläne starten von hier (fehlt der Knoten, vom zuletzt gespeicherten
  Plan).
- **`SeatingGroups`** (`klasse`): die Listen für die Verteilung im Raum.
- **`RandomGroups`** (`key` = `<E-Mail>/<klasse>`): die zuletzt
  gemischten Zufallsgruppen einer Lehrkraft.
- **`SeatWish`**: nur die Lehrkraft-Entscheidung pro Wunsch
  (`want1_status`/`want2_status`/`want3_status`/`avoid1_status`,
  Status `pending` = aktiv oder `rejected` = deaktiviert). Die eigentlichen Wunschdaten
  kommen live aus der ganz normalen `PollResponse` der Umfrage, nicht
  aus einer eigenen Tabelle.

Die Wunschabgabe selbst ist technisch eine gewöhnliche
Umfrage/`PollRun` – der Sitzplanhelfer legt sie nur automatisch an und
liest sie aus. Für die SuS gibt es keinen sichtbaren Unterschied zu
jeder anderen Umfrage im Dashboard.

## Berechtigungen

Den Sitzplan einer Klasse macht ihre Klassenleitung, und zwar für den
Klassenraum.

- **Sitzplan-Seite, Shuffler, Editor**: nur die Klassenleitung der
  eigenen Klasse oder Admin (`sph_can_manage?`,
  `require_sitzplan_klassenleitung!`), auf den Seiten und in allen
  Endpunkten. Den Editor bekommt die Klassenleitung nur für den
  Klassenraum, Admins auch für Fachräume.
- **Ansehen**: Die übrigen Lehrkräfte der Klasse sehen im Klassenbereich
  „Sitzplan Raum …“, die Ansicht ohne Wünsche (`sitzplananzeige.html`,
  `sph_can_view?`). Sie zeigt nur Namen, Fotos und Plätze, nie
  Wünsche, Vorgaben oder Listen.
- **SuS** sehen den Sitzplan im Dashboard nicht, weder die Seite noch den
  Endpunkt `sph_get_public_plan`.
- **Gruppenbildung**: alle Lehrkräfte der Klasse (`zg_can_use?`).

## Algorithmus (client-seitig, `sitzplanhelfer.html`)

1. Zuerst werden genaue Plätze besetzt, dann Zwangspaare (der Partner
   einer Person mit genauem Platz bekommt deren Nachbarplatz, bevor ihn
   eine grobe Bereichsvorgabe belegen kann), zuletzt die groben
   Bereiche. Diese Personen werden danach nicht mehr angetastet; ein
   Versuch, in dem eine Vorgabe trotzdem nicht aufgeht, verliert beim
   Vergleich der Versuche immer.
2. Die restlichen SuS werden zufällig verteilt und anschließend über
   4000 zufällige Zweiertausche lokal optimiert (Hill-Climbing).
   Bewertet werden: erfüllte aktive Wünsche (wechselseitige Wünsche
   deutlich stärker gewichtet, da sie fast immer erfüllbar sind),
   verletzte Vermeidungswünsche/Verbotspaare, sowie eine Rotation
   vorne/hinten gegenüber dem zuletzt gespeicherten Plan. „Nicht neben“
   und Verbotspaare wiegen schwerer als jeder Wunsch. Sagt B „nicht
   neben A“, zählt der Wunsch von A nach B nicht (🚫 in der Tabelle),
   solange die Lehrkraft das „Nicht neben“ nicht deaktiviert.
3. SuS, die in der Vorrunde einen aktiven (nicht abgelehnten) Wunsch
   hatten, der nur mangels Paarung nicht erfüllt wurde, bekommen
   diesmal sicher einen Wunschpartner: ein fester Vorrang-Bonus
   (`UNLUCKY_BONUS`), größer als jeder Wunsch anderer. Vorgaben der
   Lehrkraft und „Nicht neben“ gehen vor. Bei Zweiertischen heißt das
   auch: Ein Zwangspaar belegt den einzigen Nachbarplatz. In Tests ohne
   solche Vorgaben bekamen alle Bevorzugten ihren Wunsch. Wer seinen
   Wunsch letztes Mal bekam, tritt etwas zurück (Fairness über mehrere
   Runden hinweg). In der Wunschtabelle und im erzeugten Plan
   kennzeichnet 👑 die Bevorzugten. Maßstab ist der zuletzt gespeicherte
   Plan mit Wünschen vor dieser Runde; zufällig oder von Hand gesetzte
   Pläne dazwischen zählen dafür nicht, weil sie keine Wünsche hatten.
   Wird ein gespeicherter Plan nachträglich geändert, gilt dessen
   Vorgänger (sonst würde der Plan mit sich selbst verglichen). Für die
   Rotation vorne/hinten zählt der zuletzt gespeicherte Plan jeder Art.
   Wer in dieser Runde bevorzugt wird, zeigt die Seite offen als
   Namensliste über den Wünschen an.
4. Das Ganze läuft 10-mal unabhängig mit neuem Zufall, das beste
   Ergebnis wird übernommen.

## Bekannte Grenzen

Die erreichbare Trefferquote hängt stark vom Raumlayout ab. Besteht ein
Raum ausschließlich aus isolierten 2er-Tischen, hat jede Person
strukturell nur **einen** möglichen Tischnachbarn – bei drei
gleichberechtigten Wunschpartnern ist das dann kein Algorithmus-,
sondern ein Raum-Problem. In einem solchen Raum lagen die Testläufe mit
30 SuS bei rund 80 %. Bei Räumen mit größeren Tischgruppen ist mehr zu
erwarten.

Der Sitzplanhelfer setzt voraus, dass für den Raum eine Bestuhlung
hinterlegt ist. Fehlt sie, erscheint ein entsprechender Hinweis statt
eines Plans.

## Sitz-Editor

**Sitzplan-Editor** (`/sitzplaneditor/<klasse>/<raum>`, auf der
Sitzplan-Seite „Tische im Raum ändern“): Plätze per Klick setzen und
entfernen, nebeneinanderliegende Plätze werden Tische; Modus „Längs“ für
U-Formen (Blickrichtung als dritter Wert eines Platzes). Darf nur die
Klassenleitung im eigenen Klassenraum, Fachräume nur Admins, weil die
Bestuhlung für alle Klassen im Raum gilt.

## Sitzdaten

`/data` ist das von Hand gepflegte Datenrepo und bleibt schreibgeschützt.
Was das Dashboard selbst verwaltet, liegt unter `/internal/sitzplan`
(Zugriff nur über `src/ruby/include/sitzplan_daten.rb`):

| Datei | Inhalt |
|---|---|
| `raeume/<raum>.json` | Bestuhlung eines Raums: `[[x, y], [x, y, blickrichtung], …]` |
| `raeume/backup/` | die letzten 10 Fassungen pro Raum |
| `rules.json` | Regeln des Shufflers: `[nc_login, [x_min, x_max], [y_min, y_max]]` |
| `bff.json` | Paare des Shufflers: `[nc_login_1, nc_login_2, häufigkeit]` |

**Umstellung alter Sitzdaten:** `seats.js`, `rules.js` und `bff.js` (oder `bff.json`) aus
`/data/sitzplan` einmalig umwandeln. Im Ruby-Container:

```bash
ruby migrate-sitzplan.rb
ruby migrate-sitzplan.rb --apply
```

Der erste Aufruf zeigt nur die Anzahlen. Das Skript gibt keine Inhalte aus,
überschreibt nichts und schreibt gar nichts, wenn eine Datei nicht sicher
lesbar ist. Danach können die drei Dateien aus dem Datenrepo entfernt
werden; die `.mp3`-Dateien des Shufflers bleiben dort. Vor der Umwandlung
gelten weiter die alten Dateien, die Seiten laufen also in beiden Zuständen.

**Vertraulichkeit:** `rules` und `bff` können geheime Absprachen enthalten.
Der Shuffler rechnet im Browser und bekommt deshalb nur die Einträge der
Klasse aus der URL, und auch nur für Lehrkräfte dieser Klasse. Andere
Lehrkräfte mischen ohne Regeln. Für die Lehrkräfte der Klasse stehen die
Einträge weiterhin im Seitenquelltext.

## Dateien

| Datei | Zweck |
|---|---|
| `src/ruby/include/sitzplanhelfer.rb` | alle API-Endpunkte + Berechtigungs-Helper |
| `src/static/sitzplanhelfer.html` | Sitzplan-Seite der Klassenleitung inkl. Algorithmus |
| `src/static/sitzplananzeige.html` | Ansicht ohne Wünsche für die Lehrkräfte der Klasse, auch zum Drucken (auch für ältere, gespeicherte Pläne per `?cycle=`) |
| `src/ruby/include/zufallsgruppen.rb`, `src/static/zufallsgruppen.html` | Gruppenbildung |
| `src/ruby/include/sitzplan_daten.rb` | Sitzdaten lesen und schreiben, siehe oben |
| `src/ruby/migrate-sitzplan.rb` | einmalige Umwandlung der alten Dateien |
| `src/ruby/include/sitzplaneditor.rb` | Endpunkt des Editors, Klassenraum-Ermittlung |
| `src/static/sitzplaneditor.html` | Editor |
| `src/static/sitzplanverteilen.html` | leitet die alte Adresse von „Verteilen“ auf die Sitzplan-Seite weiter |
| `src/ruby/main.rb` | `require`-Zeilen, Wochenstunden pro Klasse und Raum |
| `src/static/directory.html` | für den Klassenraum „Sitzplan“ unter der Rubrik „Sitzplan“, getrennt davon „Gruppen bilden“ unter „Gruppenbildung“ (Klassenraum: Raum mit mindestens 20 Wochenstunden der Klasse, sonst der mit den meisten; jede Stunde zählt einmal, auch bei Teilung) |
