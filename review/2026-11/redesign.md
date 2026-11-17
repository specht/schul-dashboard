# Redesign: plan and page inventory

November 2026. Status: phase 1 started (switch, colour tokens, feedback – for admins). The design ideas this
builds on are on the "Werkstatt" page for admins (`/api/werkstatt`, kept on
the server only).

## What the maintainer decided so far

- **Opt-in first, switch at the end.** Users try the new design voluntarily;
  only when it has proven itself does it become the default, with a way back
  for a while, and then the old look goes away.
- **One set of pages, two shells.** The 134 pages stay single files. A user
  setting decides which frame `_template.html` loads (today's top navigation
  or the new sidebar / tab bar). No `foo.v2.html` copies – they would drift
  apart long before the switch.
- **Design tokens from the colour scheme.** Accent, text on backdrops and the
  subject colours are computed from the three colours of the user's scheme,
  contrast-corrected for light and dark. Subjects get fixed colours from that
  palette (proposal: languages towards the left colour, Mathematik on the main
  colour, sciences around it, social subjects, arts and sport towards the
  right). The subject code stays on every tile, so colour is never the only
  cue.
- **Real backdrops** from `background-renderer.rb` (light and dark variants,
  all ten patterns): on desktop behind the content, fading far down; on phones
  a larger-scale section in the header.
- **Light and dark** for every page, independent of the colour scheme.
- **No colour sliders in the new design.** The six sliders under
  "Farbeinstellungen" (hue, saturation, brightness, contrast, sepia, analog
  grain) filter the whole page, which undoes the per-scheme contrast and is
  noisy for some. About a third of all accounts has moved at least one, so
  they stay in today's design until the switch; the preview ignores them
  already, and the new design does not offer them. Colour scheme, pattern and
  light/dark remain the personal touch.
- **Feedback during opt-in** (see phase 1).
- **Tabler icons** instead of Fork Awesome (today about 1 150 uses of 157
  different icons in 92 files). Self-hosted (MIT), no CDN. A mapping table
  from each Fork Awesome icon to its Tabler counterpart; in the preview a small
  script swaps the icons in the browser (also those created by JavaScript), so
  the pages need no change yet; converted pages write Tabler icons directly;
  Fork Awesome goes away at the switch.
- **Admins first.** The preview starts with admins only; the next stages
  (teachers, everyone) are one constant (\`UI_PREVIEW_FOR\` in
  \`include/design_preview.rb\`).
- **A curated set of colour palettes (2026-11-17).** Deriving everything from
  each of the 46 existing schemes gives uneven results (some muddy, some
  too dark). The new design gets a small, hand-designed set of palettes
  (each again three colours, so backdrops keep working); every existing
  scheme maps automatically to the closest new one, and people can pick
  again. An admin page shows all schemes and their mapping side by side to
  tune the set before rollout. Buttons stay dark with light type (solid
  accent); tonal buttons were tried and rejected.

## What the inventory shows

Usage is page views over six weeks (4 October to 17 November 2026, autumn
holidays included), counted per page from the web server log – successful
GET requests by first path segment, nothing else. Pages used only at certain
times of the year (report cards, Projekttage, enrolment) can show up as rare
or unused here although they matter; check before retiring anything.

- **Usage is extremely concentrated.** The start page (timetable) alone makes
  up about 80 % of all page views, two thirds of them from phones. Ten more
  pages are used a lot (messages, login and code page, class lists,
  Projekttage, tests, 5th exam component, profile, monitor). 18 pages are in
  the middle, 59 are rare, 46 had no visits at all in these weeks.
- **Tests:** 36 pages have their own E2E tests, every page is opened by the
  smoke test. 12 pages with real use have no test of their own:
  `projekttage_overview`, `bib_book`, `pk5_overview`, `anmeldung`,
  `bib_confirm`, `bib_users`, `jitsi`, `bib_user`,
  `klassenmemory_assign`, `mailing_lists`, `bib_all_orders`,
  `bib_browse`. They need tests before they are converted (rule 3).
- **Own colours:** 7 pages paint with `color_palette` themselves; they have
  to move to the tokens, otherwise they look wrong in the new design.
- **Library and Datentresor have no pages of their own.** gyst-bib and
  gyst-tresor are backends; their interface is in the dashboard (23 pages talk
  to the library, 2 to the Tresor). Converting the dashboard pages covers
  them. A local gyst-bib with production data is available for developing the
  library pages.
- **Monitors** use their own layout without the frame and are a separate
  track.

## Phases

1. **Foundation, behind the switch.** User setting (admins can switch it on
   for others), tokens, the new shell (sidebar on desktop, tab bar plus
   "Mehr" on phones, quick search), feedback, and the test setup:
   - *Feedback:* a button in the new shell with one line of text; page,
     device, light/dark, scheme and role are saved with it, a name only if
     the person agrees to be contacted. An admin page lists the
     feedback by page and role and shows how many opted in and out. Feedback
     is deleted after the opt-in phase.
   - *Tests:* Playwright projects for the new shell (desktop and phone) run
     the converted pages and the smoke test over all pages; the full suite
     keeps running in today's look.
2. **Pages in order of use.** Start page and timetable first (including the
   lesson dialog and mails to parents), then login and code page, messages,
   profile, class lists, Kursbuch; then the high and medium pages; library
   pages with the local gyst-bib; rare pages last – unconverted pages keep
   working in the new shell.
3. **Rollout in stages:** maintainer and Jonas, volunteer teachers, the
   student council (also for the colour schemes), everyone with a way back.
   Each stage moves on when feedback, opt-out rate and error logs allow it.
4. **Switch:** the new design becomes the default, the old shell stays
   reachable for a while, then goes away.

## Open questions

- What the setting is called, and whether parents and external accounts are
  part of the opt-in.
- When the monitors follow.
- Which of the pages without visits are seasonal and which can be retired.

## Inventory

"Use" is very high (≥ 20 000 views in six weeks), high (≥ 1 000), medium
(≥ 100), rare or none. "Phones" is the rounded share of views from phones.
"Contains" lists what makes a page harder to convert. "Own E2E test": a test
opens the page by its address (all pages are also opened by the smoke test).

| Page | Use | Phones | Who | Backend | Contains | Lines | Own E2E test |
|---|---|---|---|---|---|---|---|
| `timetable` | very high | ~60 % | all logged in |  | calendar, 35 modals, table, own colours, form | 2454 | yes |
| `login_nc` | high | ~50 % | public / own check |  |  | 2 | yes |
| `messages` | high | ~60 % | all logged in |  | 7 modals, table, form | 558 | yes |
| `c` | high | ~40 % | public / own check |  | form | 165 | yes |
| `directory` | high | ~30 % | public / own check |  |  | 293 | yes |
| `projekttage` | high | ~50 % | public / own check |  | 7 modals, form | 550 | yes |
| `tests` | high | ~30 % | teachers |  | calendar, 14 modals, own colours, form | 400 | yes |
| `pk5` | high | ~50 % | public / own check |  | 7 modals, form | 587 | yes |
| `profil` | high | ~70 % | all logged in |  | 14 modals, own colours, form | 878 | yes |
| `monitor` | high | ~0 % | monitor or user who can manage monitors |  | table, own colours | 1175 | yes |
| `login` | high | ~40 % | public / own check |  | form | 89 | yes |
| `projekttage_overview` | medium | ~40 % | public / own check |  | table | 171 | – |
| `bibliothek` | medium | ~60 % | library | library |  | 42 | yes |
| `lessons` | medium | ~20 % | teachers |  | 33 modals, table, own colours, form | 2344 | yes |
| `passwoerter` | medium | ~50 % | passwords |  |  | 177 | yes |
| `hilfe` | medium | ~50 % | public / own check |  | table | 139 | yes |
| `bib_book` | medium | ~50 % | library | library | table, form | 611 | – |
| `pk5_overview` | medium | ~30 % | public / own check |  |  | 88 | – |
| `impressum` | medium | ~60 % | public / own check |  |  | 19 | yes |
| `anmeldung` | medium | ~50 % | user who can manage news |  | 7 modals, form | 217 | – |
| `bib_confirm` | medium | ~70 % | library | library |  | 129 | – |
| `bib_users` | medium | ~10 % | user who can manage bib | library | form | 137 | – |
| `jitsi` | medium | ~40 % | public / own check |  |  | 60 | – |
| `polls` | medium | ~30 % | role can_create_polls |  | 21 modals, table, form | 1656 | yes |
| `bib_user` | medium | ~20 % | user who can manage bib | library | table, form | 249 | – |
| `klassenmemory_assign` | medium | ~30 % | teachers |  | table, form | 799 | – |
| `mailing_lists` | medium | ~20 % | role can_use_mailing_lists |  |  | 47 | – |
| `bib_all_orders` | medium | ~20 % | user who can manage bib | library |  | 156 | – |
| `bib_browse` | medium | ~10 % | library | library | form | 92 | – |
| `tresor` | rare | ~10 % | teachers |  | 7 modals, form | 185 | – |
| `bib_process_order` | rare | ~20 % | user who can manage bib | library | table | 422 | – |
| `events` | rare | ~20 % | role can_create_events |  | 14 modals, table, form | 751 | yes |
| `manage_monitor` | rare | ~10 % | people who can manage monitors |  | form | 108 | – |
| `poll` | rare | ~70 % | public / own check |  |  | 47 | – |
| `admin` | rare | ~20 % | admins |  |  | 193 | yes |
| `sitzplanhelfer` | rare | ~40 % | sitzplan klassenleitung |  | table, form | 2780 | yes |
| `login_otp` | rare | ~30 % | public / own check |  | form | 67 | – |
| `bookings` | rare | ~30 % | user who can manage tablets |  | 14 modals, table, form | 347 | – |
| `bib_orders` | rare | ~30 % | library | library |  | 101 | – |
| `bib_return` | rare | ~10 % | user who can manage bib | library |  | 99 | – |
| `bib_books` | rare | ~20 % | user who can manage bib | library | form | 153 | – |
| `postfaecher` | rare | ~0 % | admins |  | 14 modals, table, form | 927 | yes |
| `anmeldungen` | rare | ~0 % | admin or sekretariat |  |  | 23 | – |
| `email_overview` | rare | ~20 % | teachers |  |  | 5 | – |
| `manage_news` | rare | ~0 % | news team |  | 5 modals, table, form | 335 | – |
| `show_all_login_codes` | rare | ~100 % | admins |  |  | 25 | – |
| `angebote` | rare | ~10 % | role can_manage_angebote |  | 7 modals, table, form | 480 | – |
| `sitzplananzeige` | rare | ~10 % | teacher |  |  | 310 | yes |
| `groups` | rare | ~10 % | public / own check |  | 14 modals, table, form | 559 | yes |
| `zeugnis_at` | rare | ~0 % | teachers |  | form | 174 | – |
| `prepare_vote` | rare | ~30 % | role can_create_polls |  | table, form | 114 | – |
| `sitzplan` | rare | ~10 % | sitzplan klassenleitung |  |  | 543 | yes |
| `zeugnisuebersicht` | rare | ~0 % | teachers | Tresor | table | 256 | – |
| `lehrbuchverein` | rare | ~90 % | all logged in |  | form | 168 | – |
| `bib_book_edit` | rare | ~10 % | user who can manage bib | library | form | 361 | – |
| `poll_not_found` | rare | ~40 % | public / own check |  |  | 8 | – |
| `bib_exemplar` | rare | ~0 % | user who can manage bib | library |  | 137 | – |
| `up` | rare | ~40 % | user with role |  | form | 419 | – |
| `zufallsgruppen` | rare | ~20 % | zg access |  | form | 920 | yes |
| `bib_overview` | rare | ~0 % | user who can manage bib | library | table | 368 | – |
| `h4ck` | rare | ~0 % | all logged in |  |  | 211 | – |
| `manage_calendar` | rare | ~0 % | news team |  | 7 modals, table, form | 142 | – |
| `bib_print_label` | rare | ~0 % | user who can manage bib | library | form | 110 | – |
| `dienste` | rare | ~60 % | admins |  |  | 13 | yes |
| `bib_add_exemplare` | rare | ~0 % | user who can manage bib | library | form | 84 | – |
| `otp` | rare | ~30 % | public / own check |  |  | 182 | yes |
| `sitzplaneditor` | rare | ~30 % | sitzplan klassenleitung |  | form | 341 | yes |
| `show_login_codes` | rare | ~0 % | teachers |  |  | 25 | – |
| `upload_images` | rare | ~0 % | uploaders |  | 7 modals, table, form | 323 | – |
| `cyph3r` | rare | ~0 % | all logged in |  |  | 214 | – |
| `gev` | rare | ~0 % | logged in gev |  | form | 192 | – |
| `lab8_overview` | rare | ~20 % | public / own check |  |  | 70 | – |
| `techpostadmin` | rare | ~100 % | role can_manage_tablets |  | 21 modals, table, form | 1015 | yes |
| `bib_scan` | rare | ~0 % | user who can manage bib | library | 6 modals | 345 | – |
| `lab9_overview` | rare | ~30 % | public / own check |  |  | 65 | – |
| `projekttage_sus` | rare | ~30 % | all logged in |  |  | 388 | – |
| `sms_anmeldung` | rare | ~70 % | admins |  |  | 56 | yes |
| `techpost` | rare | ~100 % | role can_report_tech_problems |  | 21 modals, table, form | 383 | – |
| `sitzplanverteilen` | rare | ~50 % | sitzplan klassenleitung |  |  | 10 | yes |
| `aula_light` | rare | ~0 % | user who can use aula |  | 14 modals, table, form | 255 | – |
| `bib_discard` | rare | ~100 % | user who can manage bib | library | form | 165 | – |
| `bib_postpone` | rare | ~100 % | library | library |  | 34 | – |
| `email_accounts` | rare | ~0 % | admins |  |  | 44 | – |
| `kurslisten` | rare | ~0 % | public / own check |  |  | 10 | – |
| `manage_test_calendar` | rare | ~0 % | news team |  | 7 modals, table, form | 104 | – |
| `school_wifi` | rare | ~0 % | role developer |  | table, form | 185 | – |
| `unterrichtsmails` | rare | ~100 % | admins |  | form | 329 | yes |
| `upload_files` | rare | ~0 % | uploaders |  | 7 modals, table, form | 237 | – |
| `agr_app` | none |  | teachers | AGR | 7 modals, table | 473 | – |
| `agr_markup` | none |  | public / own check |  | form | 371 | – |
| `anlage_sozialverhalten` | none |  | teachers |  | table | 205 | – |
| `at_overview` | none |  | teachers |  |  | 5 | – |
| `aula` | none |  | user who can use aula |  |  | 15 | – |
| `aula_progress` | none |  | user who can use aula |  | 7 modals, table, form | 223 | – |
| `aula_sound` | none |  | user who can manage tablets |  |  | 16 | – |
| `badges` | none |  | public / own check |  |  | 91 | – |
| `bib` | none |  | user who can manage bib | library | table | 64 | – |
| `bib_login` | none |  | public / own check |  |  | 141 | – |
| `bib_scan_isbn` | none |  | library | library |  | 69 | – |
| `bib_scan_shelf` | none |  | user who can manage bib | library | 6 modals | 216 | – |
| `bib_shelves` | none |  | user who can manage bib | library | table | 37 | – |
| `clairvoyant` | none |  | public / own check |  |  | 57 | – |
| `cling-colors` | none |  | public / own check |  |  | 499 | – |
| `development` | none |  | role developer |  |  | 15 | – |
| `ext_event` | none |  | public / own check |  |  | 23 | – |
| `ext_event_expired` | none |  | public / own check |  |  | 9 | – |
| `inactive_sus` | none |  | admins |  |  | 13 | – |
| `lab8` | none |  | public / own check |  | 7 modals, form | 237 | yes |
| `lab9` | none |  | public / own check |  | 7 modals, form | 205 | yes |
| `lesson_keys_history` | none |  | admins |  |  | 15 | – |
| `logout` | none |  | public / own check |  |  | 6 | – |
| `mail_passwort` | none |  | public / own check |  |  | 2 | yes |
| `maze` | none |  | public / own check |  |  | 54 | – |
| `mittagessen` | none |  | user |  | table | 79 | – |
| `mittagessen_overview` | none |  | user with role |  | table | 58 | – |
| `monitor_buchungen` | none |  | monitor or user who can manage monitors |  | own colours | 514 | – |
| `phishing` | none |  | phishing training |  | form | 163 | – |
| `pk5_termine` | none |  | public / own check |  |  | 53 | – |
| `projekttauschboerse` | none |  | public / own check |  | table | 110 | – |
| `salzh` | none |  | salzh managers |  | 7 modals, table, form | 675 | – |
| `salzh_protokoll` | none |  | salzh managers |  |  | 12 | – |
| `schema` | none |  | admins |  |  | 11 | – |
| `self_tests` | none |  | salzh managers |  | table | 75 | – |
| `stats` | none |  | admins |  | table | 107 | – |
| `sus_ohne_kurse` | none |  | admins |  | table | 24 | yes |
| `tablets` | none |  | role developer |  | form | 67 | – |
| `upload_schulbuchverein_bank_statement` | none |  | user with role |  | table | 123 | – |
| `wallpapers` | none |  | public / own check |  | own colours | 39 | – |
| `wind` | none |  | public / own check |  |  | 85 | – |
| `zeugnis_angebote_bemerkungen` | none |  | teachers |  | form | 109 | – |
| `zeugnis_fehltage` | none |  | teachers |  |  | 59 | – |
| `zeugnisdruck` | none |  | teachers | Tresor |  | 203 | – |
| `zeugnisformulare` | none |  | logged in zeugnis admins |  | table, form | 133 | – |
| `zeugnislisten` | none |  | teachers |  | table | 140 | – |
