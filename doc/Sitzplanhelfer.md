# Sitzplanhelfer

Der Sitzplanhelfer ist ein wunschbasierter Sitzplan-Assistent, der neben
dem bestehenden [Sitzplan-Shuffler](../src/static/sitzplan.html) steht.
Während der Shuffler rein zufällig mischt (mit optionalen statischen
Regeln aus `seats.js`/`rules.js`/`bff.js`), fließen beim Sitzplanhelfer
echte Sitzwünsche der SuS ein, und die Lehrkraft behält volle Kontrolle
über Zwangsvorgaben und das Endergebnis.

## Ablauf für Lehrkräfte

1. **Wunschrunde starten** (`/sitzplanhelfer/<klasse>/<raum>`): legt eine
   neue Umfrage an und startet einen Timer (einstellbar 1–60 Tage,
   Standard 4). Das darf **nur die Klassenleitung** der Klasse (oder
   Admin) – sonst könnte jede Fachlehrkraft spontan eine Umfrage an die
   ganze Klasse auslösen.
2. Die SuS sehen die Umfrage ganz normal über `print_current_polls()`
   (keine eigene Seite nötig) und wählen bis zu drei gleichberechtigte
   Wunschpartner sowie optional eine Person, neben der sie nicht sitzen
   möchten.
3. **Wünsche verwalten**: Jede Lehrkraft der Klasse (nicht nur die
   Klassenleitung) sieht die eingehenden Wünsche live, inkl. 🤝-Symbol
   für wechselseitige Wünsche. Wünsche zählen automatisch – die
   Lehrkraft kann einzelne Wünsche nur aktiv **ablehnen** (rotes Kreuz),
   eine Bestätigung ist nicht nötig.
4. Zusätzlich können **Zwangspaare** (muss/darf nicht zusammensitzen)
   und **feste Plätze** gesetzt werden – diese haben immer Vorrang vor
   Schülerwünschen. Ein Paar kann nie gleichzeitig Zwang und Verbot
   sein. Feste Plätze gibt es in zwei Varianten: eine grobe
   Bereichsvorgabe (vorne/hinten/links/rechts) über die Auswahl, oder
   ein **genauer Platz** per Klick auf die Sitzkarte unter „Feste
   Plätze" – die Karte zeigt dieselben Koordinaten wie der generierte
   Plan/der Shuffler (`seats_dict[raum]`) und passt sich damit
   automatisch an die tatsächliche Bestuhlung des Raums an. Ein
   exakter Platz kann immer nur einer Person zugewiesen sein (Konflikt
   wird abgelehnt), eine grobe Bereichsvorgabe darf mehrere SuS
   gleichzeitig betreffen.
5. **Übernahme vom letzten Plan**: Beim Start einer neuen Wunschrunde
   für dieselbe Klasse+Raum bietet eine Checkbox an, Zwangspaare,
   Verbote und feste Plätze vom zuletzt gespeicherten Plan zu
   übernehmen (voreingestellt an, wenn ein Plan existiert) – erspart
   das erneute Eintippen bei wiederkehrenden Wunschrunden. Bewusst nur
   für dieselbe Klasse+Raum-Kombination, da die Koordinaten fester
   Plätze raumspezifisch sind.
5. **Sitzplan erzeugen** lässt einen Algorithmus (client-seitig, siehe
   unten) mehrere Versuche rechnen und zeigt die Trefferquote
   transparent an. **Speichern** schließt die Wunschrunde automatisch
   (falls noch nicht geschehen) und macht den Plan zum aktuellen, für
   SuS sichtbaren Sitzplan.
6. **Gespeicherte Sitzpläne**: jeder gespeicherte Plan bleibt in einer
   Historie erhalten – einzeln für SuS anzeigbar (auch ältere, nicht
   nur der aktuellste), löschbar (z. B. bei Versehen) und über
   „Bearbeiten" erneut editierbar (siehe unten).

## Datenmodell (Neo4j)

- **`SeatingCycle`**: ein Durchlauf pro Klasse+Raum. Enthält
  `poll_id`/`poll_run_id` (verweist auf die zugehörige, ganz normale
  Umfrage), `forced_pairs`/`forbidden_pairs`/`fixed_rules` (JSON), und
  nach dem Speichern zusätzlich `seats` (E-Mail → Sitzplatz-Index),
  `unresolved` (nicht erfüllte Vorgaben mit Begründung),
  `satisfied_emails` und `saved_at`. Pro Klasse+Raum ist immer nur
  **ein** Zyklus gleichzeitig offen (`saved_at IS NULL`).
- **`SeatWish`**: nur die Lehrkraft-Entscheidung pro Wunsch
  (`want1_status`/`want2_status`/`want3_status`/`avoid1_status`,
  Status `pending` oder `rejected`). Die eigentlichen Wunschdaten
  kommen live aus der ganz normalen `PollResponse` der Umfrage, nicht
  aus einer eigenen Tabelle.

Die Wunschabgabe selbst ist technisch eine gewöhnliche
Umfrage/`PollRun` – der Sitzplanhelfer legt sie nur automatisch an und
liest sie aus. Für die SuS gibt es keinen sichtbaren Unterschied zu
jeder anderen Umfrage im Dashboard.

## Berechtigungen

- **Wunschrunde starten**: nur Klassenleitung der Klasse oder Admin
  (`klassenleiter_for_klasse_or_admin_logged_in?`).
- **Alles andere** (Wünsche ablehnen, Paare/Regeln setzen, Plan
  erzeugen/speichern/löschen/bearbeiten): jede Lehrkraft, die laut
  `@@teachers_for_klasse` diese Klasse unterrichtet, oder Admin
  (`sph_can_manage?`).
- Die öffentliche SuS-Ansicht (`sitzplananzeige.html`) zeigt nur Namen
  und Plätze, nie Wünsche/Paare/Regeln ("Lehrergeheimnis").

## Algorithmus (client-seitig, `sitzplanhelfer.html`)

1. Feste Regeln, dann Zwangspaare werden zuerst platziert und danach
   nicht mehr angetastet.
2. Die restlichen SuS werden zufällig verteilt und anschließend über
   4000 zufällige Zweiertausche lokal optimiert (Hill-Climbing).
   Bewertet werden: erfüllte aktive Wünsche (wechselseitige Wünsche
   deutlich stärker gewichtet, da sie fast immer erfüllbar sind),
   verletzte Vermeidungswünsche/Verbotspaare, sowie eine Rotation
   vorne/hinten gegenüber dem zuletzt gespeicherten Plan.
3. SuS, die in der Vorrunde einen aktiven (nicht abgelehnten) Wunsch
   hatten, der nur mangels Paarung nicht erfüllt wurde, werden dieses
   Mal bevorzugt; wer seinen Wunsch letztes Mal bekam, tritt etwas
   zurück (Fairness über mehrere Runden hinweg).
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

Der Sitzplanhelfer setzt voraus, dass für den Raum ein Layout in
`/data/sitzplan/seats.js` hinterlegt ist – dieselbe Datei, die der
Sitzplan-Shuffler ohnehin benötigt. Fehlt sie oder der betreffende
Raum darin, erscheint ein entsprechender Hinweis statt eines Plans.

## Geänderte/neue Dateien

| Datei | Zweck |
|---|---|
| `src/ruby/include/sitzplanhelfer.rb` | alle API-Endpunkte + Berechtigungs-Helper |
| `src/static/sitzplanhelfer.html` | Lehrkraft-Oberfläche inkl. Algorithmus |
| `src/static/sitzplananzeige.html` | wunschfreie SuS-Ansicht (auch für ältere, gespeicherte Pläne per `?cycle=`) |
| `src/ruby/main.rb` | `require './include/sitzplanhelfer.rb'` |
| `src/static/directory.html` | „Helfer"-Button direkt neben dem Shuffler-Button pro Raum, gemeinsam unter der Rubrik „Sitzplan" |

Raumaufteilung (`seats.js`) wird mit dem Shuffler geteilt; `rules.js`
und `bff.js` sind ausschließlich Shuffler-spezifisch und werden vom
Sitzplanhelfer nicht gelesen.
