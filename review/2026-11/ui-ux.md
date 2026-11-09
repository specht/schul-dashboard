# UI/UX review of the school dashboard (desktop + mobile)

Basis: screenshots from `test/e2e/test-results/ui-tour/` (anonym, schueler, lehrkraft), source code in `src/static` and `src/ruby/main.rb`. I don't repeat points that are already in TODO.md section 2. Where I state them more precisely, this is marked “(refines TODO …)”. Assumptions I could not back up with code or a screenshot are marked **[assumption]**.

## Summary

The dashboard runs stably: no JS errors, all pages return HTTP 200. The biggest obstacles are in the timetable on the phone. You can't swipe. There is no indication of which day or week is currently shown. Below the lessons follow about 6 empty hours of grid (until 10 pm). Below that are the homework and, for teachers, the timetable selection, which you only reach after a lot of scrolling. On top of that there are some small, low-risk bugs that can be fixed right away: in the course planning the page never jumps to „heute“ (today), „Mathe im Advent“ (Maths Advent calendar) is hard-coded to 2025, and at desktop widths between 768 and 1280 px the navigation becomes too cramped for teachers. Many pages also carry old Corona features, fun code and empty tables that can be removed without any loss for users.

## Quick wins (low risk, high benefit)

1. **Course planning never jumps to „heute“ (bug)**
   - What: When opening `/lessons/…` the page should scroll to the „heute“ row. Because of a typo this never happens: `if ($(window.width) >= 768)` instead of `$(window).width()`.
   - Why: Teachers see the school year from lesson 1 onwards (more than 150 rows) and scroll by themselves every time. The page is used often.
   - Where: `src/static/lessons.html:2149`; screenshot `lehrkraft/desktop-lessons_Ma_5a.png` (the „heute“ row is at about no. 20, the page stays at the top).
   - Suggestion: Use `$(window).width()`. Also scroll to „heute“ on the phone (drop the `>= 768` condition entirely). E2E test: after loading, `.lesson-table-info-row.today` is in the viewport.
   - Effort S, risk low.

2. **„Mathe im Advent“ hard-coded to 2025**
   - What: The dates are generated as `'2025-12-' + day_s`. From December 2026 on they no longer appear.
   - Where: `timetable.html:527` and `:541`. Incidentally: `this_klasse === NaN` (`:513`) is always `false`, correct would be `isNaN()`.
   - Suggestion: Derive the year from `initial_date` or the current date. This becomes relevant in three weeks.
   - Effort S, risk low.

3. **Swipe through the timetable on the phone and page with arrow keys on desktop** (maintainer's request)
   - What: A horizontal swipe gesture on `#calendar` calls `calendar.prev()`/`calendar.next()`. On desktop additionally ←/→ (and “T” for today), as long as no input field is focused and no modal is open.
   - Why: The arrow buttons on the phone are the only way to page, and they sit at the top right. Swiping is the expected gesture.
   - Where: `timetable.html` after `window.calendar.render()` (`:1655–1657`). FullCalendar 5.1 has no swipe gesture of its own.
   - Suggestion: Register `touchstart`/`touchend` as `passive`. Only trigger if |dx| > 60 px, |dx| > 1.5·|dy| and the gesture is shorter than 600 ms. Ignore gestures that start closer than 25 px to the screen edge, because that is where the iOS/Android “back” gesture lives. Only enable in `timeGridDay`. Do nothing while a `.modal.show` is open. `validRange` already limits `prev()` for students.
   - Effort S, risk low. In the day-view calendar there is no horizontal scroll that could collide. An E2E test with `page.touchscreen` or dispatched touch events in the mobile project is possible.

4. **Refresh the timetable when returning to the page**
   - What: No `visibilitychange` handler. The manifest sets `display: standalone` (`main.rb:3731`), so many people have the dashboard as an app on their home screen. Whoever reopens the app the next morning sees yesterday's day and old substitutions. In the standalone view on iOS there is also no “pull to refresh”.
   - Where: `timetable.html` (initialisation), possibly `_template.html`.
   - Suggestion: On `visibilitychange → visible` and more than 10 minutes of absence, call `calendar.refetchEvents()`. If the date has changed, additionally `calendar.today()`.
   - Effort S, risk low.

5. **Title and date above the timetable**
   - What: `headerToolbar.start` is empty (`timetable.html:789`). On desktop, month, year or calendar week are shown nowhere. On the phone the header only shows „Mo. 9.11.“, with no hint whether that is today or tomorrow. The „Klassenarbeiten“ (class tests) page, by contrast, shows a title („November 2026“, `tests.html:223`, screenshot `lehrkraft/desktop-tests.png`).
   - Suggestion: Set `start: 'title'`. For `timeGridDay` show e.g. „Montag, 9. November“ via `views: {timeGridDay: {dayHeaderFormat: {weekday:'long', day:'numeric', month:'long'}}}`, plus „heute“/„morgen“ (today/tomorrow). On desktop a title like „9.–13. Nov. 2026 · KW 46“.
   - Effort S, risk low (toolbar only).

6. **Rotating the phone or changing the window width**
   - What: `narrow_window` is only checked once on load (`timetable.html:780`, likewise `tests.html:219`). Whoever loads in landscape or shrinks the window stays in the wrong view.
   - Suggestion: In the FullCalendar callback `windowResize`, switch between `timeGridDay` and `timeGridWeek` via `changeView` at the 640 px boundary (not for tablet and Praktikum (internship) mode).
   - Effort S, risk low.

7. **Navigation for teachers at 768–1279 px**
   - What: The navigation already expands from `md` (768 px) (`_template.html:799`). With 7 entries it is already full to the brim at 1280 px: „Beispielschule“ (example school) bumps into „Stundenplan“ (timetable) (`lehrkraft/desktop-start.png`). Below that it wraps or overflows **[assumption, not rendered]**. In `styles.css:559–565` there is a ready-made compact variant `.navbar.hide_icons`, but it is not set anywhere.
   - Suggestion: Apply the same rules in `@media (min-width:768px) and (max-width:1279px)`, and reduce the padding `.nav-icon {padding-right:45px}`. Alternatively `navbar-expand-lg` for teachers.
   - Effort S, risk low (pure CSS, check at 1024/1280).

8. **Mark the active navigation item**
   - What: On `/messages`, „Nachrichten“ (messages) is not highlighted (`lehrkraft/desktop-messages.png`). There is no `active`/`aria-current` in `nav_items`.
   - Where: `main.rb:2357ff`.
   - Suggestion: Compare `request.path` with the `href` and set `active` as well as `aria-current="page"`.
   - Effort S, risk low.

9. **Typo in the admin area:** „Bitte wählen Sie ein **order** mehrere Kürzel“ (“Please select one **order** [sic, for „oder“ = or] more abbreviations”)
   - Where: `src/ruby/include/admin.rb:320`, `include/techpost.rb:675`; screenshot `lehrkraft/desktop-admin.png`.
   - Effort S, risk low.

10. **Sitzplanhelfer (seating plan helper) with no way to the editor**
    - What: The text refers to the „Sitzplan-Editor im Klassenbereich“ (seating plan editor in the class area), but does not link to it (`lehrkraft/phone-sitzplanhelfer_5a_108.png`).
    - Suggestion: Add a button „Zum Sitzplan-Editor“ (to the seating plan editor). The target is the same as „Editor Raum 108“ (editor room 108) on `/directory/5a`.
    - Effort S, risk low.

11. **Login field:** `autocomplete='on'` instead of `autocomplete="username"` or `"email"` (`login.html:16`). Password managers and iOS then suggest the address more reliably. Effort S, risk low.

## Mobile improvements

**M1. Fit the visible time range to the content instead of 7 am–10 pm.**
- What: `slotMinTime 07:00`, `slotMaxTime 22:00`, fixed height 1330/1350 px (`timetable.html:791–796`). On the phone the last block is followed by about 6 empty hours, i.e. around 450 px (`schueler/phone-start.png`, `lehrkraft/phone-start.png`).
- Suggestion: In `render_timetable` determine the latest end of the week (at least 16:00, plus one hour of buffer). Then `setOption('slotMaxTime', …)` and **at the same time** `setOption('height', header + hours × 75)`. Important: because of `expandRows: true`, 75 px per hour must be kept, otherwise the break stripes, which calculate with `75.0/60.0` (`:863–864`), shift. An hour with an evening appointment thus stays visible.
- Effort M, risk medium. E2E test with an appointment after 6 pm needed.

**M2. Homework and weekend appointments are below the calendar** (refines TODO „Kalender mit fester Höhe“ (calendar with fixed height)).
- What: Below 992 px the right side panel (`timetable.html:143–147`) stacks under the roughly 1350 px tall calendar. Students only see their homework on the phone after a lot of scrolling **[assumption, example data without homework]**.
- Suggestion (low-risk): Next to „Heute“ (today) on the phone, show a chip „Hausaufgaben (n)“ (homework (n)) that scrolls to the panel. Stronger would be to show the panel collapsed *above* the calendar below 992 px (Bootstrap class `order-first order-lg-0`).
- Effort S–M, risk low.

**M3. Timetable selection for teachers on the phone.**
- What: The buttons for abbreviations, classes and rooms are below the calendar (`lehrkraft/phone-start.png`, at about y = 1470). If you select e.g. „108“ there, the calendar changes outside the viewport, and there is no label saying which plan is currently shown. „Alle Lehrkräfte“ (all teachers) shows all abbreviations as buttons (`main.rb:2894`), probably about 100 at the real school **[assumption]**.
- Suggestion:
  - (a) After `load_timetable()` call `#calendar.scrollIntoView()` on narrow screens.
  - (b) Extend the title from quick win 5 with „Stundenplan 5a / Raum 108 / Ta“ (timetable 5a / room 108 / Ta).
  - (c) Replace „Alle Lehrkräfte“ with a search or select field.
- Effort S (a, b), M (c). Risk low.

**M4. Weekday bar in the day view.**
- What: On the phone you can only move day by day. “What do I have on Thursday?” takes three taps.
- Suggestion: Below the toolbar, a bar „Mo Di Mi Do Fr“ (Mon Tue Wed Thu Fri) for the current week using `calendar.gotoDate()`, with the active day highlighted.
- Effort M, risk low. Optional, the swipe gesture already covers the basic need.

**M5. After school show the next school day (optional).**
- What: In the evening the phone still shows today's day, which is already over. What is usually needed is „morgen“ (tomorrow).
- Suggestion: Only on the phone, after the end of the last lesson (or from 5 pm), start with the next school day. The title must then clearly say „morgen“ (quick win 5).
- Effort S, risk medium (changes a habit, agree on it beforehand).

**M6. Course planning on the phone:** The editing area is at the top, the list below it is about 8000 px long (`lehrkraft/phone-lessons_Ma_5a.png`). After tapping a lesson you don't see the form.
- Suggestion: After `selection_updated()` on narrow screens, scroll to the `.lesson_pane` area and offer a button „Zurück zur Liste“ (back to the list) there (to the selected row). Plus quick win 1 (jump to „heute“).
- Effort S–M, risk low.

**M7. Profile is about 8500 px long** (`schueler/phone-profil.png`).
- What: About 45 colour schemes are listed one below the other, each as a full row. „Anmeldung und Zwei-Faktor-Authentifizierung“ (login and two-factor authentication), i.e. the only security-relevant setting (for teachers with a deadline), is at the very bottom (`profil.html:237`).
- Suggestion:
  - (a) Show the colour swatches on the phone as a grid with 3–4 columns.
  - (b) A jump navigation at the top: Persönliches · Darstellung · Anmeldung & Geräte · Kalender (iCal) (personal · appearance · login & devices · calendar (iCal)).
  - (c) Move „Anmeldung/2FA“ and „Angemeldete Geräte“ (logged-in devices) before the appearance section.
- Effort S–M, risk low.

**M8. Don't fix the footer on the phone** (complements TODO „Fixierte Fußzeile“ (fixed footer)).
- What: The 24 px tall, fixed `.foot` (`styles.css:284`) permanently takes up space. The round GitHub button (`.github`, `styles.css:333`) overlaps it (`anonym/phone-start.png`).
- Suggestion: Below 768 px use `position: static` (at the end of the page). This also solves the problem with the modals. Move the GitHub link into the footer as a text link.
- Effort S, risk low.

**M9. Distribution list addresses on `/directory/<klasse>` are invisible on the phone** (refines TODO „table-responsive“).
- What: „E-Mail an die Klasse“ (email to the class) and „an alle Eltern“ (to all parents) are in the last table row in the right-hand columns. On the phone you only see grey, empty bars (`lehrkraft/phone-directory_5a.png`, y ≈ 380 and 1335). Even on desktop at 1280 px the parents' list is cut off (`desktop-directory_5a.png`).
- Suggestion: Put the distribution lists above the table as a separate card with copy buttons. This is the most used information on the page **[assumption]**.
- Effort S–M, risk low.

## Desktop improvements

**D1. Empty evening hours:** As in M1, on desktop on a 1080p screen about half of the grid is below the visible area, although there is usually nothing there (`schueler/desktop-start.png`). The same solution (M1) helps most here.

**D2. Teacher features are hidden in the profile menu** (refines TODO „Profil- und Admin-Menü sind sehr lange Dropdowns“ (profile and admin menus are very long dropdowns)).
- What: Klassenarbeiten, Termine (appointments), Umfragen (surveys), Abstimmungen (votes), E-Mail-Verteiler (email distribution lists), Meine Gruppen (my groups), AGs (clubs), Lab 8/9, 5. PK (5th exam component) and Projekttage (project days) are in the avatar menu (`main.rb:2603–2648`). Nobody expects features under their own name. Lab 8/9, 5. PK and Projekttage appear for all teachers regardless of phase and responsibility (`:2603–2607`).
- Suggestion: A menu „Werkzeuge“ (tools) (or an extension of „Planung“ (planning)) for Termine, Umfragen, Klassenarbeiten, Abstimmungen, Verteiler and Gruppen. The avatar menu keeps only account topics: Profil, Kontowechsel (switch account), Hell/Dunkel (light/dark), Hilfe (help), Abmelden (log out). Show seasonal items only in their phase (as already done for students via `projekttage_phase()`).
- Effort M, risk medium (familiar paths change, announce briefly).

**D3. „Planung“ and „Lerngruppen“ (learning groups) have the same icon** (`fa-address-book`, `main.rb:~2664` and `~2700`). For Lerngruppen e.g. `fa-users`. Effort S, risk low.

**D4. Admin page** (`lehrkraft/desktop-admin.png`): All users are in one long list without a filter. With around 1000 accounts this is only usable with Ctrl+F **[assumption about the real length]**.
- Suggestion: A filter field above the tables (hide rows client-side). The 15 grey jump buttons at the top would be better as a plain anchor bar.
- Effort S–M, risk low.

**D5. Error on `/bibliothek` leaves the page empty:** When the request fails you only see the overlay „Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten.“ (An error occurred while processing the request.) and nothing else (`schueler/phone-bibliothek.png`, in the test stack without a library service **[assumption about the cause]**). In addition to the TODO about `api_call`: a placeholder card „Die Bibliothek ist gerade nicht erreichbar – versuch es später noch einmal.“ (The library is currently unreachable – try again later.) Effort S, risk low.

## Consistency & accessibility (only what is new compared to TODO.md)

**K1. Calendar buttons are called “prev”/“next” for screen readers.** FullCalendar 5.1 sets `aria-label` on icon buttons to the internal name (`main.min.js`: `{"aria-label":c}`). The print button has no label at all, because its content is replaced by an icon (`timetable.html:687`). Suggestion: After `render()` set `aria-label`/`title`: „Vorheriger Tag/Woche“ (previous day/week), „Nächster …“ (next …), „Stundenplan als PDF drucken“ (print timetable as PDF). Effort S, risk low.

**K2. The timetable selection cannot be reached by keyboard.** The buttons are `<a … onclick=…>` without `href` (`main.rb:2860, 2870, 2889, 2911`) and therefore get no focus. Suggestion: Use `<button type="button">` with the same classes. Effort S, risk low (the `.ttc` selectors stay the same).

**K3. Consistent empty states.**
- Messages: „Keine Nachrichten gefunden! ¯\\_(ツ)_/¯“ (No messages found!) (`messages.html:508`).
- Surveys: no text at all (`lehrkraft/phone-polls.png`).
- Appointments, groups, „Externe Nutzer“ (external users) in the admin area: only table headers (`phone-events.png`, `phone-groups.png`).
- Suggestion: A pattern „Noch keine Umfragen. Mit „Neue Umfrage“ kannst du …“ (No surveys yet. With „Neue Umfrage“ (new survey) you can …) (form of address matching the role) and hide empty tables.
- Effort S, risk low.

**K4. Sitzplananzeige (seating plan display) without a card:** The text sits directly on the background image (`schueler/phone-sitzplananzeige_5a_108.png`). With dark or colourful colour schemes it becomes unreadable. The Sitzplanhelfer already uses a card. Suggestion: Use `.container` or a card. Effort S, risk low.

**K5. Corona texts with „Dich/Deine“ (you/your) capitalised** (`timetable.html:459–463`). Resolved by removing this block (see below).

**K6. Truncated homework:** `.ha_text {max-height: 300px; overflow-y: hidden}` (`styles.css:2805`) cuts off long homework texts without any hint. Suggestion: Show a „mehr“ (more) link or remove the limit. Effort S, risk low.

**K7. Events in the calendar can only be opened by mouse or tap.** FullCalendar 5.1 does not make events without a `url` focusable **[assumption, not tested]**. Suggestion: In `eventDidMount` set `tabindex="0"`, `role="button"` and an Enter handler. Effort S, risk low.

## Can go / simplify (UI elements, pages, options)

1. **Fun and single-user code in the timetable** (all in `timetable.html`):
   - `rsag()` with around 250 hard-coded Rostock stops and an iframe (`:580–599`)
   - `porsche()` (`:601–608`)
   - both switched on for individual accounts via hash (`:1922–1926`)
   - physics animation whose function immediately executes `return` (`:610–678`, `:1927–1940`)
   - a user-specific rotation `body{transform:rotate(1deg)}` in `_template.html:111`

   This makes the page longer without any benefit for the roughly 1000 users. Effort S, risk low.
2. **Corona leftovers:**
   - Wechselunterricht (alternating classes) / „zu Hause“ (at home) notice (`timetable.html:453–470`)
   - self-test button `.bu-add-self-test` with the formal „Sie“ form of address (`:1941–1953`)
   - `bu_minimize_salzh_explanation` (`:1878`)
   - hybrid note field `#ta_sus_notes` („Hybridstunde … zu Hause“ (hybrid lesson … at home), `:167–170`)
   - commented-out panels (`:120–125`)

   Check and remove. Complements TODO „Corona-Seiten“ (Corona pages) with these spots *in* the timetable. Effort S, risk low to medium (check beforehand whether `WECHSELUNTERRICHT_KLASSENSTUFEN` is empty).
3. **Commented-out Android WebView notice** with hard-coded addresses (`timetable.html:76–93`). It is shipped along, because HTML comments in the template are evaluated and sent. Effort S, risk low.
4. **Profile, „Rollen“ (roles) section:** an internal permissions table. No use for students and parents. Move it into a collapsible section „Technische Details“ (technical details) or show it only to teachers. **„Muster“** (patterns) appears empty in the test stack (`schueler/desktop-profil.png`), probably because of missing generated images **[assumption, matches the many 404s in `*-notes.txt`]**. Hide it when the list is empty. Effort S, risk low.
5. **Analog, sepia and contrast sliders** into a collapsible group „Erweitert“ (advanced) (complements the TODO about the brightness switches). Fewer options, same possibilities. Effort S, risk low.
6. **Course planning, Dashboard-Amt (dashboard duty) and hybrid:** Sections like „Rückmeldung von Schülerinnen und Schülern“ (feedback from students) and „Notizen“ (notes) fill the screen on the phone before the list starts (`lehrkraft/phone-lessons_Ma_5a.png`). Check whether they are still used. Otherwise collapse them by default. Effort S, risk medium (clarify usage beforehand).
7. **Print button on the phone:** It opens a weekly PDF and is probably rarely needed on mobile **[assumption]**. Hide it on narrow screens to make room for the title. Effort S, risk low.

**Recommended order:** Quick wins 1, 2, 9 (pure bugs) → 3, 4, 5, 6 (timetable on the phone, each with E2E in the `mobile` project) → M1/M2/M3 → navigation (7, 8, D2) → clean-up.

**Note on the console messages:** The many `404` and `ERR_NAME_NOT_RESOLVED` in the `*-notes.txt` probably come from missing generated files and external hosts in the test stack, not from UI bugs **[assumption]**. They should still be checked, though, so that real errors in the list don't get lost.
