# UI/UX-Review Schul-Dashboard (Desktop + Mobil)

Grundlage: Screenshots aus `test/e2e/test-results/ui-tour/` (anonym, schueler, lehrkraft), Quellcode in `src/static` und `src/ruby/main.rb`. Punkte, die schon in TODO.md Abschnitt 2 stehen, wiederhole ich nicht. Wo ich sie genauer fasse, steht „(präzisiert TODO …)“. Annahmen, die ich nicht am Code oder Screenshot belegen konnte, sind mit **[Annahme]** markiert.

## Kurzfazit

Das Dashboard läuft stabil: keine JS-Fehler, alle Seiten liefern HTTP 200. Die größten Hürden liegen im Stundenplan auf dem Handy. Man kann nicht wischen. Es fehlt eine Angabe, welcher Tag oder welche Woche gerade angezeigt wird. Unter dem Unterricht folgen etwa 6 leere Stunden Raster (bis 22 Uhr). Darunter liegen Hausaufgaben und, für Lehrkräfte, die Stundenplan-Auswahl, die man erst nach langem Scrollen erreicht. Dazu kommen einige kleine, risikoarme Fehler, die man sofort beheben kann: In der Kursplanung springt die Seite nie zu „heute“, „Mathe im Advent“ ist fest auf 2025 programmiert, und auf Desktop-Breiten zwischen 768 und 1280 px wird die Navigation für Lehrkräfte zu eng. Viele Seiten tragen außerdem alte Corona-Funktionen, Spaß-Code und leere Tabellen mit sich, die man ohne Nutzerverlust entfernen kann.

## Quick Wins (geringes Risiko, hoher Nutzen)

1. **Kursplanung springt nie zu „heute“ (Fehler)**
   - Was: Beim Öffnen von `/lessons/…` sollte die Seite zur Zeile „heute“ scrollen. Wegen eines Tippfehlers passiert das nie: `if ($(window.width) >= 768)` statt `$(window).width()`.
   - Warum: Lehrkräfte sehen das Schuljahr ab Stunde 1 (mehr als 150 Zeilen) und scrollen jedes Mal selbst. Die Seite wird oft genutzt.
   - Wo: `src/static/lessons.html:2149`; Screenshot `lehrkraft/desktop-lessons_Ma_5a.png` (Zeile „heute“ liegt etwa bei Nr. 20, die Seite steht oben).
   - Vorschlag: `$(window).width()` einsetzen. Auf dem Handy ebenfalls zu „heute“ scrollen (die Bedingung `>= 768` ganz weglassen). E2E-Test: Nach dem Laden ist `.lesson-table-info-row.today` im Sichtbereich.
   - Aufwand S, Risiko niedrig.

2. **„Mathe im Advent“ fest auf 2025**
   - Was: Die Termine werden als `'2025-12-' + day_s` erzeugt. Ab Dezember 2026 erscheinen sie nicht mehr.
   - Wo: `timetable.html:527` und `:541`. Nebenbei: `this_klasse === NaN` (`:513`) ist immer `false`, richtig wäre `isNaN()`.
   - Vorschlag: Das Jahr aus `initial_date` bzw. dem aktuellen Datum ableiten. Das ist in drei Wochen relevant.
   - Aufwand S, Risiko niedrig.

3. **Stundenplan auf dem Handy wischen und am Desktop mit Pfeiltasten blättern** (Wunsch des Maintainers)
   - Was: Eine waagrechte Wischgeste auf `#calendar` ruft `calendar.prev()`/`calendar.next()` auf. Am Desktop zusätzlich ←/→ (und „T“ für heute), solange kein Eingabefeld fokussiert und kein Modal offen ist.
   - Warum: Die Pfeil-Buttons auf dem Handy sind die einzige Möglichkeit zu blättern, und sie liegen oben rechts. Wischen ist die erwartete Geste.
   - Wo: `timetable.html` nach `window.calendar.render()` (`:1655–1657`). FullCalendar 5.1 hat keine eigene Wischgeste.
   - Vorschlag: `touchstart`/`touchend` als `passive` registrieren. Auslösen nur, wenn |dx| > 60 px, |dx| > 1,5·|dy| und die Geste kürzer als 600 ms ist. Gesten ignorieren, die näher als 25 px am Bildschirmrand beginnen, denn dort liegt die „Zurück“-Geste von iOS/Android. Nur in `timeGridDay` aktivieren. Bei offenem `.modal.show` nichts tun. `validRange` für Schüler:innen begrenzt `prev()` bereits.
   - Aufwand S, Risiko niedrig. Im Tagesansicht-Kalender gibt es keinen waagrechten Scroll, der kollidieren könnte. Ein E2E-Test mit `page.touchscreen` bzw. dispatchten Touch-Events im Mobil-Projekt ist möglich.

4. **Stundenplan aktualisieren, wenn man zur Seite zurückkehrt**
   - Was: Kein `visibilitychange`-Handler. Das Manifest setzt `display: standalone` (`main.rb:3731`), viele haben das Dashboard also als App auf dem Startbildschirm. Wer die App am nächsten Morgen wieder öffnet, sieht den Tag von gestern und alte Vertretungen. In der Standalone-Ansicht gibt es auf iOS auch kein „Ziehen zum Aktualisieren“.
   - Wo: `timetable.html` (Initialisierung), ggf. `_template.html`.
   - Vorschlag: Bei `visibilitychange → visible` und mehr als 10 Minuten Abwesenheit `calendar.refetchEvents()` aufrufen. Hat sich das Datum geändert, zusätzlich `calendar.today()`.
   - Aufwand S, Risiko niedrig.

5. **Titel und Datum über dem Stundenplan**
   - Was: `headerToolbar.start` ist leer (`timetable.html:789`). Am Desktop steht nirgends Monat, Jahr oder Kalenderwoche. Auf dem Handy zeigt der Kopf nur „Mo. 9.11.“, ohne Hinweis, ob das heute oder morgen ist. Die Seite „Klassenarbeiten“ zeigt dagegen einen Titel („November 2026“, `tests.html:223`, Screenshot `lehrkraft/desktop-tests.png`).
   - Vorschlag: `start: 'title'` setzen. Für `timeGridDay` über `views: {timeGridDay: {dayHeaderFormat: {weekday:'long', day:'numeric', month:'long'}}}` z. B. „Montag, 9. November“ anzeigen, dazu „heute“/„morgen“. Am Desktop ein Titel wie „9.–13. Nov. 2026 · KW 46“.
   - Aufwand S, Risiko niedrig (nur Toolbar).

6. **Drehen des Handys bzw. Fensterbreite ändern**
   - Was: `narrow_window` wird nur einmal beim Laden geprüft (`timetable.html:780`, ebenso `tests.html:219`). Wer im Querformat lädt oder das Fenster verkleinert, bleibt in der falschen Ansicht.
   - Vorschlag: Im FullCalendar-Callback `windowResize` per `changeView` zwischen `timeGridDay` und `timeGridWeek` an der Grenze 640 px umschalten (nicht für Tablet- und Praktikum-Modus).
   - Aufwand S, Risiko niedrig.

7. **Navigation für Lehrkräfte bei 768–1279 px**
   - Was: Die Navigation klappt schon ab `md` (768 px) auf (`_template.html:799`). Mit 7 Einträgen ist sie bei 1280 px schon randvoll: „Beispielschule“ stößt an „Stundenplan“ (`lehrkraft/desktop-start.png`). Darunter bricht sie um bzw. läuft über **[Annahme, nicht gerendert]**. In `styles.css:559–565` gibt es eine fertige Kompaktvariante `.navbar.hide_icons`, die aber nirgends gesetzt wird.
   - Vorschlag: Dieselben Regeln in `@media (min-width:768px) and (max-width:1279px)` anwenden, dazu das Padding `.nav-icon {padding-right:45px}` verkleinern. Alternativ für Lehrkräfte `navbar-expand-lg`.
   - Aufwand S, Risiko niedrig (reines CSS, auf 1024/1280 prüfen).

8. **Aktiven Navigationspunkt markieren**
   - Was: Auf `/messages` ist „Nachrichten“ nicht hervorgehoben (`lehrkraft/desktop-messages.png`). In `nav_items` gibt es kein `active`/`aria-current`.
   - Wo: `main.rb:2357ff`.
   - Vorschlag: `request.path` mit dem `href` vergleichen und `active` sowie `aria-current="page"` setzen.
   - Aufwand S, Risiko niedrig.

9. **Tippfehler im Admin-Bereich:** „Bitte wählen Sie ein **order** mehrere Kürzel“
   - Wo: `src/ruby/include/admin.rb:320`, `include/techpost.rb:675`; Screenshot `lehrkraft/desktop-admin.png`.
   - Aufwand S, Risiko niedrig.

10. **Sitzplanhelfer ohne Weg zum Editor**
    - Was: Der Text verweist auf den „Sitzplan-Editor im Klassenbereich“, verlinkt ihn aber nicht (`lehrkraft/phone-sitzplanhelfer_5a_108.png`).
    - Vorschlag: Einen Button „Zum Sitzplan-Editor“ einfügen. Ziel ist dasselbe wie „Editor Raum 108“ auf `/directory/5a`.
    - Aufwand S, Risiko niedrig.

11. **Login-Feld:** `autocomplete='on'` statt `autocomplete="username"` bzw. `"email"` (`login.html:16`). Passwortmanager und iOS schlagen die Adresse dann zuverlässiger vor. Aufwand S, Risiko niedrig.

## Verbesserungen Mobil

**M1. Sichtbaren Zeitraum an den Inhalt anpassen statt 7–22 Uhr.**
- Was: `slotMinTime 07:00`, `slotMaxTime 22:00`, feste Höhe 1330/1350 px (`timetable.html:791–796`). Auf dem Handy folgen auf den letzten Block etwa 6 leere Stunden, also rund 450 px (`schueler/phone-start.png`, `lehrkraft/phone-start.png`).
- Vorschlag: In `render_timetable` das späteste Ende der Woche ermitteln (mindestens 16:00, plus eine Stunde Puffer). Dann `setOption('slotMaxTime', …)` und **gleichzeitig** `setOption('height', Kopf + Stunden × 75)`. Wichtig: Wegen `expandRows: true` müssen 75 px pro Stunde erhalten bleiben, sonst verrutschen die Pausen-Streifen, die mit `75.0/60.0` rechnen (`:863–864`). Eine Stunde mit Abendtermin bleibt damit sichtbar.
- Aufwand M, Risiko mittel. E2E-Test mit Termin nach 18 Uhr nötig.

**M2. Hausaufgaben und Wochenend-Termine liegen unter dem Kalender** (präzisiert TODO „Kalender mit fester Höhe“).
- Was: Unter 992 px stapelt sich das rechte Seitenpanel (`timetable.html:143–147`) unter den etwa 1350 px hohen Kalender. Schüler:innen sehen ihre Hausaufgaben auf dem Handy erst nach langem Scrollen **[Annahme, Beispieldaten ohne HA]**.
- Vorschlag (risikoarm): Neben „Heute“ auf dem Handy einen Chip „Hausaufgaben (n)“ einblenden, der zum Panel scrollt. Stärker wäre, das Panel unter 992 px eingeklappt *über* dem Kalender anzuzeigen (Bootstrap-Klasse `order-first order-lg-0`).
- Aufwand S–M, Risiko niedrig.

**M3. Stundenplan-Auswahl für Lehrkräfte auf dem Handy.**
- Was: Die Buttons für Kürzel, Klassen und Räume liegen unter dem Kalender (`lehrkraft/phone-start.png`, etwa y = 1470). Wählt man dort z. B. „108“ aus, ändert sich der Kalender außerhalb des Sichtbereichs, und es gibt keine Beschriftung, welcher Plan gerade angezeigt wird. „Alle Lehrkräfte“ blendet alle Kürzel als Buttons ein (`main.rb:2894`), an der echten Schule vermutlich etwa 100 **[Annahme]**.
- Vorschlag:
  - (a) Nach `load_timetable()` auf schmalen Bildschirmen `#calendar.scrollIntoView()` aufrufen.
  - (b) Den Titel aus Quick Win 5 um „Stundenplan 5a / Raum 108 / Ta“ ergänzen.
  - (c) „Alle Lehrkräfte“ durch ein Such- bzw. Auswahlfeld ersetzen.
- Aufwand S (a, b), M (c). Risiko niedrig.

**M4. Wochentags-Leiste in der Tagesansicht.**
- Was: Auf dem Handy springt man nur tageweise. Für „Was habe ich Donnerstag?“ braucht man drei Taps.
- Vorschlag: Unter der Toolbar eine Leiste „Mo Di Mi Do Fr“ der aktuellen Woche mit `calendar.gotoDate()`, der aktive Tag hervorgehoben.
- Aufwand M, Risiko niedrig. Optional, die Wischgeste deckt das Grundbedürfnis schon ab.

**M5. Nach Schulschluss den nächsten Schultag anzeigen (optional).**
- Was: Abends zeigt das Handy weiterhin den heutigen, schon vergangenen Tag. Gebraucht wird meist „morgen“.
- Vorschlag: Nur auf dem Handy nach dem Ende der letzten Stunde (oder ab 17 Uhr) mit dem nächsten Schultag starten. Im Titel muss dann deutlich „morgen“ stehen (Quick Win 5).
- Aufwand S, Risiko mittel (geänderte Gewohnheit, vorher abstimmen).

**M6. Kursplanung auf dem Handy:** Der Bearbeitungsbereich steht oben, die Liste darunter ist etwa 8000 px lang (`lehrkraft/phone-lessons_Ma_5a.png`). Nach dem Antippen einer Stunde sieht man das Formular nicht.
- Vorschlag: Nach `selection_updated()` auf schmalen Bildschirmen zum Bereich `.lesson_pane` scrollen und dort einen Button „Zurück zur Liste“ (zur gewählten Zeile) anbieten. Dazu Quick Win 1 (zu „heute“ springen).
- Aufwand S–M, Risiko niedrig.

**M7. Profil ist etwa 8500 px lang** (`schueler/phone-profil.png`).
- Was: Etwa 45 Farbschemata stehen je als volle Zeile untereinander. „Anmeldung und Zwei-Faktor-Authentifizierung“, also die einzige sicherheitsrelevante Einstellung (für Lehrkräfte mit Frist), steht ganz unten (`profil.html:237`).
- Vorschlag:
  - (a) Die Farbfelder auf dem Handy als Raster mit 3–4 Spalten anzeigen.
  - (b) Oben eine Sprungnavigation: Persönliches · Darstellung · Anmeldung & Geräte · Kalender (iCal).
  - (c) „Anmeldung/2FA“ und „Angemeldete Geräte“ vor die Darstellung verschieben.
- Aufwand S–M, Risiko niedrig.

**M8. Fußzeile auf dem Handy nicht fixieren** (ergänzt TODO „Fixierte Fußzeile“).
- Was: Die 24 px hohe, fixierte `.foot` (`styles.css:284`) kostet dauerhaft Platz. Der runde GitHub-Button (`.github`, `styles.css:333`) überlappt sie (`anonym/phone-start.png`).
- Vorschlag: Unter 768 px `position: static` (am Seitenende) verwenden. Damit ist auch das Problem mit den Modals gelöst. Den GitHub-Link als Textlink in die Fußzeile verschieben.
- Aufwand S, Risiko niedrig.

**M9. Verteiler-Adressen auf `/directory/<klasse>` sind auf dem Handy unsichtbar** (präzisiert TODO „table-responsive“).
- Was: „E-Mail an die Klasse“ bzw. „an alle Eltern“ stehen als letzte Tabellenzeile in den rechten Spalten. Auf dem Handy sieht man nur graue, leere Balken (`lehrkraft/phone-directory_5a.png`, y ≈ 380 und 1335). Selbst am Desktop bei 1280 px ist der Eltern-Verteiler abgeschnitten (`desktop-directory_5a.png`).
- Vorschlag: Die Verteiler als eigene Karte mit Kopier-Buttons über die Tabelle setzen. Das ist die meistgenutzte Information der Seite **[Annahme]**.
- Aufwand S–M, Risiko niedrig.

## Verbesserungen Desktop

**D1. Leere Abendstunden:** Wie M1 liegt auch am Desktop auf einem 1080p-Bildschirm etwa die Hälfte des Rasters unterhalb des sichtbaren Bereichs, obwohl dort meist nichts steht (`schueler/desktop-start.png`). Dieselbe Lösung (M1) hilft hier am meisten.

**D2. Lehrkräfte-Funktionen stecken im Profilmenü** (präzisiert TODO „Profil- und Admin-Menü sind sehr lange Dropdowns“).
- Was: Klassenarbeiten, Termine, Umfragen, Abstimmungen, E-Mail-Verteiler, Meine Gruppen, AGs, Lab 8/9, 5. PK und Projekttage liegen im Avatar-Menü (`main.rb:2603–2648`). Funktionen unter dem eigenen Namen erwartet dort niemand. Lab 8/9, 5. PK und Projekttage erscheinen für alle Lehrkräfte unabhängig von Phase und Zuständigkeit (`:2603–2607`).
- Vorschlag: Ein Menü „Werkzeuge“ (oder Erweiterung von „Planung“) für Termine, Umfragen, Klassenarbeiten, Abstimmungen, Verteiler und Gruppen. Das Avatar-Menü behält nur Konto-Themen: Profil, Kontowechsel, Hell/Dunkel, Hilfe, Abmelden. Saisonale Punkte nur in ihrer Phase anzeigen (wie bei Schüler:innen schon über `projekttage_phase()`).
- Aufwand M, Risiko mittel (gewohnte Wege ändern sich, kurz ankündigen).

**D3. „Planung“ und „Lerngruppen“ haben dasselbe Icon** (`fa-address-book`, `main.rb:~2664` und `~2700`). Für Lerngruppen z. B. `fa-users`. Aufwand S, Risiko niedrig.

**D4. Admin-Seite** (`lehrkraft/desktop-admin.png`): Alle Nutzer:innen stehen in einer langen Liste ohne Filter. Bei rund 1000 Konten ist das nur mit Strg+F nutzbar **[Annahme zur realen Länge]**.
- Vorschlag: Ein Filterfeld über den Tabellen (clientseitig Zeilen ausblenden). Die 15 grauen Sprung-Buttons oben lieber als schlichte Ankerleiste.
- Aufwand S–M, Risiko niedrig.

**D5. Fehler auf `/bibliothek` lässt die Seite leer:** Bei fehlgeschlagener Anfrage sieht man nur das Overlay „Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten.“ und sonst nichts (`schueler/phone-bibliothek.png`, im Test-Stack ohne Bibliotheksdienst **[Annahme zur Ursache]**). Ergänzend zum TODO zu `api_call`: eine Platzhalterkarte „Die Bibliothek ist gerade nicht erreichbar – versuch es später noch einmal.“ Aufwand S, Risiko niedrig.

## Konsistenz & Barrierefreiheit (nur Neues gegenüber TODO.md)

**K1. Kalender-Buttons heißen für Screenreader „prev“/„next“.** FullCalendar 5.1 setzt bei Icon-Buttons `aria-label` auf den internen Namen (`main.min.js`: `{"aria-label":c}`). Der Druck-Button hat gar kein Label, weil sein Inhalt durch ein Icon ersetzt wird (`timetable.html:687`). Vorschlag: Nach `render()` `aria-label`/`title` setzen: „Vorheriger Tag/Woche“, „Nächster …“, „Stundenplan als PDF drucken“. Aufwand S, Risiko niedrig.

**K2. Stundenplan-Auswahl ist per Tastatur nicht erreichbar.** Die Buttons sind `<a … onclick=…>` ohne `href` (`main.rb:2860, 2870, 2889, 2911`) und bekommen deshalb keinen Fokus. Vorschlag: `<button type="button">` mit denselben Klassen verwenden. Aufwand S, Risiko niedrig (Selektoren `.ttc` bleiben gleich).

**K3. Einheitliche Leerzustände.**
- Nachrichten: „Keine Nachrichten gefunden! ¯\\_(ツ)_/¯“ (`messages.html:508`).
- Umfragen: gar kein Text (`lehrkraft/phone-polls.png`).
- Termine, Gruppen, „Externe Nutzer“ im Admin: nur Tabellenköpfe (`phone-events.png`, `phone-groups.png`).
- Vorschlag: Ein Muster „Noch keine Umfragen. Mit „Neue Umfrage“ kannst du …“ (Anrede passend zur Rolle) und leere Tabellen ausblenden.
- Aufwand S, Risiko niedrig.

**K4. Sitzplananzeige ohne Karte:** Der Text steht direkt auf dem Hintergrundbild (`schueler/phone-sitzplananzeige_5a_108.png`). Bei dunklen oder bunten Farbschemata wird er unlesbar. Der Sitzplanhelfer nutzt bereits eine Karte. Vorschlag: `.container` bzw. Karte verwenden. Aufwand S, Risiko niedrig.

**K5. Corona-Texte mit „Dich/Deine“ in Großschreibung** (`timetable.html:459–463`). Erledigt sich mit dem Entfernen dieses Blocks (siehe unten).

**K6. Abgeschnittene Hausaufgaben:** `.ha_text {max-height: 300px; overflow-y: hidden}` (`styles.css:2805`) schneidet lange Hausaufgabentexte ohne Hinweis ab. Vorschlag: Einen „mehr“-Link einblenden oder die Begrenzung entfernen. Aufwand S, Risiko niedrig.

**K7. Ereignisse im Kalender sind nur per Maus bzw. Tippen zu öffnen.** FullCalendar 5.1 macht Termine ohne `url` nicht fokussierbar **[Annahme, nicht getestet]**. Vorschlag: In `eventDidMount` `tabindex="0"`, `role="button"` und einen Enter-Handler setzen. Aufwand S, Risiko niedrig.

## Kann weg / vereinfachen (UI-Elemente, Seiten, Optionen)

1. **Spaß- und Einzelnutzer-Code im Stundenplan** (alles in `timetable.html`):
   - `rsag()` mit rund 250 fest eingetragenen Rostocker Haltestellen und iframe (`:580–599`)
   - `porsche()` (`:601–608`)
   - beide per Hash auf einzelne Konten geschaltet (`:1922–1926`)
   - Physik-Animation, deren Funktion sofort `return` ausführt (`:610–678`, `:1927–1940`)
   - eine nutzerspezifische Drehung `body{transform:rotate(1deg)}` in `_template.html:111`

   Das verlängert die Seite, ohne Nutzen für die rund 1000 Nutzer:innen. Aufwand S, Risiko niedrig.
2. **Corona-Reste:**
   - Wechselunterrichts-/„zu Hause“-Hinweis (`timetable.html:453–470`)
   - Selbsttest-Button `.bu-add-self-test` mit „Sie“-Anrede (`:1941–1953`)
   - `bu_minimize_salzh_explanation` (`:1878`)
   - Hybrid-Notizfeld `#ta_sus_notes` („Hybridstunde … zu Hause“, `:167–170`)
   - auskommentierte Panels (`:120–125`)

   Prüfen und entfernen. Ergänzt TODO „Corona-Seiten“ um diese Stellen *im* Stundenplan. Aufwand S, Risiko niedrig bis mittel (vorher prüfen, ob `WECHSELUNTERRICHT_KLASSENSTUFEN` leer ist).
3. **Auskommentierter Android-WebView-Hinweis** mit festen Adressen (`timetable.html:76–93`). Er wird mit ausgeliefert, weil HTML-Kommentare im Template ausgewertet und gesendet werden. Aufwand S, Risiko niedrig.
4. **Profil, Bereich „Rollen“:** eine interne Rechte-Tabelle. Für Schüler:innen und Eltern ohne Nutzen. In einen aufklappbaren Bereich „Technische Details“ verschieben oder nur für Lehrkräfte zeigen. **„Muster“** erscheint im Test-Stack leer (`schueler/desktop-profil.png`), vermutlich wegen fehlender generierter Bilder **[Annahme, passt zu den vielen 404 in `*-notes.txt`]**. Bei leerer Liste ausblenden. Aufwand S, Risiko niedrig.
5. **Analog-, Sepia- und Kontrast-Regler** in eine einklappbare Gruppe „Erweitert“ (ergänzt das TODO zu den Helligkeits-Schaltern). Weniger Optionen, gleiche Möglichkeiten. Aufwand S, Risiko niedrig.
6. **Kursplanung, Dashboard-Amt und Hybrid:** Bereiche wie „Rückmeldung von Schülerinnen und Schülern“ und „Notizen“ füllen auf dem Handy den Bildschirm, bevor die Liste beginnt (`lehrkraft/phone-lessons_Ma_5a.png`). Prüfen, ob sie noch genutzt werden. Sonst standardmäßig einklappen. Aufwand S, Risiko mittel (Nutzung vorher klären).
7. **Druck-Button auf dem Handy:** Er öffnet ein Wochen-PDF und wird mobil vermutlich selten gebraucht **[Annahme]**. Auf schmalen Bildschirmen ausblenden, um Platz für den Titel zu schaffen. Aufwand S, Risiko niedrig.

**Empfohlene Reihenfolge:** Quick Wins 1, 2, 9 (reine Fehler) → 3, 4, 5, 6 (Stundenplan auf dem Handy, je mit E2E im Projekt `mobile`) → M1/M2/M3 → Navigation (7, 8, D2) → Aufräumen.

**Hinweis zu den Konsolenmeldungen:** Die vielen `404` und `ERR_NAME_NOT_RESOLVED` in den `*-notes.txt` stammen vermutlich von fehlenden generierten Dateien und externen Hosts im Test-Stack, nicht von UI-Fehlern **[Annahme]**. Sie sollten aber geprüft werden, damit echte Fehler in der Liste nicht untergehen.