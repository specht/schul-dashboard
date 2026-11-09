# Maintenance review: gyst-dashboard

Basis: `AGENTS.md`, `TODO.md` §2/§3, `doc/Architektur.md` and reading/grepping code and Git. I did not open `data/`, `internal/`, `logs/`, `env.rb` and `credentials.rb`. All paths are relative to the root of the repository.

## Summary

- **A lot can go at low risk: roughly 6,000–8,000 lines of Ruby/HTML and around 20 MB of assets.**
  - Code that isn't loaded (`projekte_old.rb`)
  - The `_old` Projekttage (project days) pages, which are already broken
  - Corona leftovers (saLzH/self-tests)
  - Matrix
  - Unused JS libraries that every page loads along in the bundle
  - A good 20 unversioned files
- **I found three real bugs:**
  - **„Einladung ablehnen“ (decline invitation) for the Projekttage goes nowhere.** `projekttage.html:557` calls `/api/reject_projekttage_invitation`, but the route is called `reject_projektage_invitation` (`include/projekte.rb:704`, typo).
  - **Wrong group IDs for the Forschertage (research days).** The parent groups are called `"/af/…"` instead of `"/ft/…"` (`include/directory.rb:644-645`, copied from the Antikenfahrt (classics trip)).
  - **`src/scripts/reload-monitors.rb` doesn't work.** It calls via GET, but the route is `post '/api/force_reload_monitors'` (`include/monitor.rb:30`). The script itself says “not functional yet”.
- **The biggest structural lever is the page route `get '/*'` (`main.rb:3570-4129`).** The templates are evaluated via `eval` in the context of this method and therefore see all its local variables (`user_email` occurs 143 times, also `poll_data`, `stored_events` …). Whoever splits up the route has to preserve these names. A golden master test is needed first.
- **Global state:** 98 different `@@` variables. Most are only written at startup. Really risky are four places that write at runtime (see below).

## Can go

| What | Evidence of non-use | Effort | Risk |
|---|---|---|---|
| `src/ruby/include/projekte_old.rb` (832 lines, **not versioned**) | Not included in `main.rb:100-157`; file from 26 April 2025 | delete file | none |
| `projekttage_old.html`, `projekttage_sus_old.html`, `projekttage_overview_old.html` | Linked nowhere. They call routes that only exist in the unloaded `projekte_old.rb` (`/api/get_projekte_for_orga_sus`, `/api/update_project`, `/api/get_project_data`), so they are already broken. `projekttage_sus_old` is in `known-page-errors.json`. Last commits 2024-11 and 2025-05 | delete 3 files, remove entries from `known-page-errors.json` | low |
| **Corona/saLzH**: `include/salzh.rb` (1194 lines, last commit 2023-01), `salzh.html`, `salzh_protokoll.html`, `self_tests.html` | Role `can_manage_salzh` is commented out (`include/roles.rb:10`), pages crash for everyone (`known-page-errors.json`), menu item commented out (`main.rb:2627`), panels commented out (`timetable.html:121,125`) | **Medium**, because the code still runs: `timetable.rb:208` (variable `salzh_info` is never used, but costs a query per monitor update), `:360-363`, `:1631-1659`, `:2345`; `include/directory.rb:77,190-199` (+ commented-out blocks `88-99`, `127-134`, `213-244`); `techpostadmin.html:816-817` (variables are never used); `directory.html:98-140`; `timetable.html:948-950,1424-1432,1878-1880,1946`; `monitor.html:658`; helpers in `include/user.rb:80,274,302`; `SALZH_MODE_*` constants. Check parts of `jitsi.rb:86-105` (`get_homeschooling_for_user_by_dauer_salzh`) | medium: timetable output, so golden test first (see below). Incidentally, `timetable.rb:1652` contains a copy error (`unless contact_person_sus.empty?` before `salzh_sus`) |
| **Matrix**: `include/matrix.rb` (209 lines, last commit 2022-04), `write-matrix-corporal-policy.rb` (src/ruby + src/scripts), `@@email_for_matrix_login` (`main.rb:684,773-775,865-866`), `login.rb:353` | No call from `src/static`. `/api/fetch_matrix_groups` has no caller, `store_matrix_access_token`/`matrix_hook` only from outside. In the template all `MATRIX_*` are `nil`/example values | small: file + require + fields in `collect_data`. The check “duplicate matrix / nc login” in `main.rb:774` should be switched to `nc_login` | low, ask first whether a Matrix server is still running in production |
| Class streaming/livestream (Corona era) | `PROVIDE_CLASS_STREAM = false` (`credentials.template.rb:204`); `main.rb:1950-1966`, `main.rb:3664-3673` (`livestream`), `fixed_timetable_data` for streaming tablets `main.rb:3752-3781`, `timetable.rb:1760-1770` commented out | medium | medium. Jitsi itself is still maintained (commit 2026-08-31), so only remove the streaming part |
| Orphaned pages `agr_markup` (2021-11), `cling-colors` (2022-10), `lesson_keys_history` (crashes), `aula.html` (old version next to `aula_light/sound/progress`), `bib_shelves`, `badges`, `ext_event*` (according to TODO it only reads the always empty `show_event`, `main.rb:3616`) | No link in `src/static`, `main.rb` or `include/` (checked by grep) | one file each; clarify `ext_event` first | low |
| `/login_otp` + `login_otp.html`, `post '/api/login_otp'` (`include/otp.rb:71`) | According to TODO §2 not linked and not functional | small | low |
| Unused Ruby methods | No call found: `bytes_to_str` (`main.rb:2781`), `print_adventskalender_sidepanel` (`main.rb:3202`), `good_bad_icon` (`admin.rb:85`), `get_current_ab_week` (`directory.rb:528`), `can_checkout_books`, `print_lehrbuchverein_table` (`lehrbuchverein.rb:46,50`), `parse_lab8_node`/`parse_lab9_node` (`lab8.rb:24`, `lab9.rb:24`), `print_login_ranking` (`stats.rb:91`), `this_is_a_page_for_devices` (`user.rb:296`), `urlize`/`anchorize`/`first_letter_dot`/`notify_if_different` (`parser.rb:62,74,161,626`). Also `build_assignment_state`, `assignment_state_feasible?`, `assignment_bottleneck_message`, `safe_projects_for_grade` (`projekte.rb:1287-1480`, 2025/26 – probably unfinished assignment logic, ask first) | delete | low |
| Unused variables in the page route | `slug`, `task`, `sha1`, `cat_slug`, `os_family`, `show_offer`, `@task_slug`, `@original_path`, `brand` only for `{BRAND}` (`main.rb:3586-3606,4025,4031-4032`); `@@lesson_key_back_tr` is only assigned (`main.rb:1044`) | delete | none (no template uses them, checked by grep for `#{…}`) |
| Dead branch for `site.webmanifest` | `main.rb:4089-4121` uses the undefined `s` and looks for a file that doesn't exist. The manifest is already written in `main.rb:3731-3735`, but then ends up in the 404 branch (check status). Better to handle the case as a separate `get '/site.webmanifest'` route | small | low |
| Unused constants | `IMAP_SERVER`, `VOTING_CONTACT_EMAIL`, `JWT_APPAUD_AGRAPP`, `JWT_APPISS_AGRAPP`, `VPLAN_ENCODING` (`credentials.template.rb:49,108,166-167,199`) | clean up template | none |
| Admin exports without a link | `get_all_sus_emails` (`admin.rb:568`), `get_all_entries_for_phishing_training` (`:591`), `sus_by_birthday_cutoff` (`directory.rb:1233`), `get_lesson_info_archive` (`lesson.rb:557`), `get_tablet_bookings` (`lesson.rb:435`), `print_email_letter_test` (`user.rb:855`), `set_light_aula_event` (`aula.rb:17`), `get_unterstufenparty_sus` (`user.rb:860`) | Ask: link in `admin.html` or delete. Called from outside and stays: `website_*`, `get_frontpage_news_*`, `get_hackschule_users`, `get_workspace_users`, `klassenraum_account`, `get_all_user_ids` (`check-all-timetables.js`) | low |
| Old one-off scripts in `src/ruby` | `mig-2021-09-05.rb`, `import-news-attic.rb` (2022), `create-cling-color-palette.rb` (2022), `dump-anmeldungen.rb` (2023), `mark-lehrbuchverein-paid.rb` (2024), `collect-nextcloud-files-from-sus.script.rb` (2023), `assign-projekttage.rb` (2025, predecessor of `projekttage-assign.rb`), `print-sus.rb` (2022). None is referenced | delete; the Git history is enough as an archive | none |
| Wrappers in `src/scripts` | All follow the pattern `system("cd ../.. && ./config.rb exec ruby …")`. `reload-monitors.rb` is broken (GET instead of POST), `projekttage-assign.rb` appends `ARGV` to `cd src/scripts` instead of to the script | one generic `src/scripts/run-in-ruby` with the array form of `system` | low |

**Decide first** (no longer being developed, but visible):
- **Games „Dashboard Hackers“/„Code Crackers“/Maze:** `include/hack.rb` (330 lines) and `include/cypher.rb` (858 lines), content last changed 2023-10 and 2024-05 respectively. In addition there are `static/hack`, `static/cypher` (3.6 MB) and `static/gb` (7.8 MB, 31 ROMs). Advertised in the HTML comment `_template.html:52-69`, background special case `_template.html:151,154`, terminal code `code.js:1-8,187-283` (`teletype`/`append_*` are called nowhere). If it were moved out (own repo), the bundle and image would save a lot.
- **Phishing training** (`phishing.rb`, 2024-06; hard-loads `/data/phishing/config.rb` in `main.rb:81,1987`).
- **School Wi-Fi:** menu item commented out (`main.rb:2646`), only for `developer`.
- **Advent calendar:** `main.rb:2345,3090-3216`.

## Simplify / merge

1. **Recipient autocomplete in page JS:** `recipients_cache`, `autocomplete_results`, `compact_address_list`, `gen_recipient_span`, `add/remove_recipient`, `update_net_recipients_list` and the `keyup` handler exist copied in 8 pages: `messages.html:65-500`, `events.html:170-690`, `polls.html:292-700`, `groups.html:106-350`, `angebote.html:90-260`, `gev.html`, `techpostadmin.html:806-900`, `salzh.html`. The autocomplete block messages↔events only differs in tab focus details. Suggestion: `recipient_picker.js` with `RecipientPicker(input, list, opts)`. The E2E tests for messages/events/polls already exist, so switch those over first.
2. **Additional recipient groups in Ruby:** `update_antikenfahrt_groups` and `update_forschertage_groups` (`directory.rb:565-660`) are copies of each other (copy error `/af/`). Plus `@@techpost_*`, `@@lehrbuchverein_mailing_lists`, `@@angebote_mailing_lists`, `@@projekttage_mailing_lists`. A generic builder `build_group_recipients(prefix, label, klassen, groups)` fits. In addition, each group is passed individually via `#{@@antikenfahrt_recipients.to_json}` into 5 pages (`messages.html:74`, `events.html:185`, `groups.html:115`, `polls.html:304`, `techpostadmin.html:813`). Better to deliver it via `load_recipients` (`code.js:400`).
3. **lab8/lab9:** `include/lab8.rb`/`lab9.rb` (495 lines each) differ in 52 lines after renaming, `lab8.html`/`lab9.html` in 46, the `_overview` pages in 9. This becomes one module with a parameter `:lab8`/`:lab9`.
4. **PDF:** The Weasyprint call `Curl.post('http://weasyprint:5001/pdf', …)` appears six times (`aula.rb:171,223`, `poll.rb:430,460,471`, `techpost.rb:597`) without shared error handling. A helper `html_to_pdf(html, css: '')` in `main.rb` is enough. Prawn stays for `fragments/fragments.rb` (3031 lines, 9× `sanitize_pdf_with_ghostscript`).
5. **Duplicate helpers:**
   - `gen_password_for_email`: `main.rb:631-659` and `parser.rb:328-363` are identical.
   - `fix_h_to_hh`: `main.rb:207` and `timetable.rb:44`.
   - `srand(...)` changes the global random number generator in a process with threads (`main.rb:636`, `parser.rb:332`, `at.rb:48`, `hack.rb:96`, `cypher.rb:207,249`). Better `Random.new(seed)`.
6. **`api_call` variants** (`code.js:109-176`): `bib_api_call` and `tresor_api_call` are the same JWT cache logic with a different prefix. A `jwt_api_call(prefix, host, token_url, …)` combines them. `*_no_jwt` are one-liners.
7. **`timetable.rb:907-1016`:** The clean-up of moved tablet and tablet set bookings consists of two almost identical blocks.
8. **`collect_data` parses the timetable twice with the same arguments** (`main.rb:1044` and `:1077`). This lengthens every start. Check whether `parse_timetable` has side effects, then drop the second call.
9. **Error handling:**
   - Numbers: 324× `assert(`, 29× `raise 'nope'/'oops'`, 49 bare `rescue`, only 8× `respond(:error …)`.
   - Suggestion: `class ApiError < StandardError` with status and code, `error ApiError do … end` once in `Main`, and `require_…!` raises 403 instead of 500. This also takes care of the 153 access cases from TODO §2.
   - Dangerous: the bare `rescue` in `main.rb:2151` deletes the session on *any* error while building the session.
10. **Commented-out code:** larger blocks in `main.rb:1093-1101,1607-1624,1914-1923,2586-2605,3325-3338`, `timetable.rb:270-286,1225-1233,1760-1770,2239-2253,2590-2611`, `parser.rb:832-844,1376-1407,1527-1577`, `poll.rb:343-398` (56 lines).
11. **Hard-coded values in the page route:**
    - date headers in `main.rb:3572-3573` (summer holidays 2026, Christmas 2026)
    - external link `main.rb:~2619` (SV (student council) website)
    - `gen_poll_data(request.path.sub('/jitsi/', ''))` (`main.rb:3663`, copied; only works because `poll.rb:946` removes `/poll/` itself)
12. **Global state written at runtime** (16 Puma threads):
    - `@@lesson_notes_for_session_user_cache`/`_last_timestamp` is changed per page view without a mutex (`main.rb:3784-3797`).
    - `refresh_bib_data` sets `@@bib_summoned_books = {}` *before* loading, other threads briefly see an empty list (`main.rb:1728`). In addition, it runs in every `before` (`main.rb:2001`).
    - `@@ws_clients` is changed in the WebSocket thread and iterated in request threads (`bib_login.rb:10-31,72`, `monitor.rb:24`).
    - `@@public_event_config`, `@@mittagessen` (mtime reload) and `@@current_jitsi_rooms` are caches.
    - Everything else is only written in `collect_data`. Use the existing pattern “build completely first, then swap” (`main.rb:1413`) there as well.

## Structure: steps for main.rb and timetable.rb (with tests needed first)

**Tests first:**

- **T1 – Golden master for pages:** For every page × role from the smoke test, save the HTML body (after normalising timestamps, SHA1 bundles, random colours) and compare. This is an extension of `pages.smoke.ts` with a snapshot option. The prerequisite is the missing fixed system time (TODO §1).
- **T2 – Golden master for `collect_data`:** `main.rb:1449-1458` already writes all class variables to `/internal/debug/*.yaml`. Compare before/after in the test stack with example data (unit test or `./test.sh` step).
- **T3 – Golden master for the timetable service:** With a fixed time, generate `/gen/w/<id>/<woche>.json.gz` for all example users and compare. Adopt `src/scripts/check-all-timetables.js` (TODO §1).
- **T4 – API permission matrix** (TODO §1), before `before '*'` is touched. Plus tablet, monitor and device sessions in the seed.

**main.rb (4130 lines) in small steps**, each deployable on its own:

1. *Without test risk:* Move feature routes from `main.rb` into `include/*.rb` (only a change of location):
   - JWT token routes `3217-3261` → `include/jwt_tokens.rb`
   - library dump `3262-3277` → `bib_login.rb`
   - `hackschule`/`workspace` `3278-3343` → `include/export.rb`
   - photos/class memory `3344-3516` → `include/klassenmemory.rb`
   - Advent calendar `2345-2356,3090-3216` → `include/advent.rb`
   - SSO `547-612,2171-2250` → `include/sso.rb`
   - monitor deep links `3517-3549` → `monitor.rb`

   That is about 700 lines. Don't forget the new requires in `main.rb` (AGENTS.md).
2. `nav_items` (`2357-2780`) and `print_*` helpers (`2794-3020`) → `include/navigation.rb`. Safeguarded by T1.
3. `SetupDatabase` (`313-538`), the top-level helper functions (`38-310`) and `compile_js/css` (`1704-1817`) into separate files (`lib/setup_database.rb`, `lib/helpers.rb`, `lib/assets.rb`).
4. Split `collect_data` (`681-1464`) along the existing sections into `self.collect_users`, `collect_roles`, `collect_tablets`, `collect_timetable`, `collect_kurswahl`, `collect_mailing_lists`, plus `update_mailing_lists` (`1465-1703`). Safeguarded by T2. Remove the duplicate `parse_timetable` in this step.
5. `before '*'`: device token, session lookup and the pseudo-account block (`2046-2116`, seven almost identical hashes) → `PSEUDO_ACCOUNTS = { 'monitor' => {...}, … }` plus `load_session_user`. Safeguarded by T4 and `session.spec.ts`.
6. Page route `3570-4129`:
   - (a) Move the renderer (`4043-4084`, incl. the `#{}` scanner) out into `render_page(path, binding)`. It receives the route's `binding`, so templates stay unchanged.
   - (b) Rebuild the `if path == …` cascade (`3619-3987`) into a table `PAGE_PREPARERS = { 'messages' => :prepare_messages_page, … }`. The methods set **instance variables**, and in a transition phase the route fills the previous local names from them (`sent_messages = @sent_messages`), so that `eval` still finds them.
   - (c) Then switch the templates over to `@…` page by page.

   Safeguarded by T1. Only once there are no more local names can one think about ERB.

**timetable.rb (2705 lines):** T3 first.
1. Remove saLzH (see table).
2. Turn the duplicate booking purge `907-1016` into one method with label/relation as parameters.
3. Split `update_timetables` (329-1078) into `refresh_vplan`, `build_day_events`, `purge_moved_bookings`, `unfix_moved_lesson_infos`.
4. Split `update_weeks` (1125-2170, over 1000 lines) along the existing comments into `write_user_weeks` (1293-2035), `write_lesson_series` (2036-2058), `write_messages` (2059-2103), `write_homework` (2104-). The event enrichment (birthdays, notes, cancellations) as individual functions `enrich_*(events)` that can be tested with small unit tests.

## Dependencies (unused/outdated)

**JS bundle** (`main.rb:1752-1783`, served to every page):
- Used nowhere (checked by grep):
  - `turn.min.js` (turn.js 4.1.0), `zoom.min.js`, `scissor.min.js` (both belong to turn.js), `hash.js` (2012)
  - `jszip` (3.6.0, 1.2 MB including sources and Bower files)
  - `bootstrap-autocomplete.min.js` (no `.autoComplete(`)
  - `flowbite.js`: not a single `data-*-toggle`/`data-*-target`. The CSS `flowbite.min.css` stays as long as Tailwind classes need it.
- Hardly used:
  - `typewriter.js` (only `clairvoyant.html`)
  - `odometer` (`bib_confirm`, `timetable`)
  - `print.min.js` (only `bib_process_order.html`)
  - `zxing.min.js` (in the bundle *and* additionally loaded in `bib_scan_shelf.html:87`)
  - `jquery-ui` (only `.draggable` in `lessons.html:643`)

  Include these per page instead of in the bundle.
- `include/quagga.js/quagga.min.js` is unused. `opencv.js` (11 MB, versioned) is only needed by `up.html:92`. That is fine, but it would be better placed in the container than in the repo.
- Outdated: jQuery 3.6.1, Bootstrap 4.4.1, FullCalendar 5.1.0, Chart.js 2.9.4, clipboard.js 2.0.0, jQuery UI 1.13.2, moment (maintenance mode). This is already in TODO §3.

**Gems** (`src/ruby/Gemfile`):
- `pry` is **always** loaded in `main.rb:24`. `rerun` doesn't belong in the production image either (TODO).
- `http` is only used by `mig-2021-09-05.rb` and `write-matrix-corporal-policy.rb`, both on the can-go list. After that the gem can go.
- `wavefile` and `chunky_png` are only needed by `cypher.rb` (game), `xsv` only by the Beratungstermin (counselling appointment) and import scripts, `girocode` only by `send-bibliothek-zahlungsaufforderung.rb`, `prawn-svg` only by `fragments.rb`. All legitimate, but move them into a `:scripts` group.
- Missing from the Gemfile although required: `caxlsx` (`src/scripts/json_nodes_to_xlsx.rb`, not versioned) and `paint` (`gen-maze.rb`, not versioned).
- `require 'net/imap'` in `main.rb:17` is only needed by `mail-forwarder.rb`, `require 'csv'` only by `parser.rb`. Move them there.
- `mustermann`: comment and version don't match (in TODO).

## Unfinished work in the working directory

**Active, belongs to the ongoing test work (keep, commit):**
- Modified: `test.sh`, `test/e2e/playwright.config.ts` (project `screens`), `test/e2e/tests/fixtures.ts` (`ROLE_ACCOUNTS`), `pages.smoke.ts`, `test/prepare_example_data.rb` (+46 lines of role accounts). Changes were added during my analysis, so someone is currently working here.
- New: `test/e2e/tests/ui-tour.screens.ts` (from 9 November 2026), belongs with it.
- `src/ruby/test-admin-reset-teacher-2fa.rb` and `src/ruby/test-informatik-biber-export.rb` (1 November 2026): standalone minitests for code in `include/admin.rb`. Move to `src/ruby/test/unit/` so that `./test.sh unit` runs them.

**Probably keep (ask):**
- `src/scripts/json_nodes_to_xlsx.rb` (2026-08): tool for dumps; add `caxlsx` to the Gemfile (group `:scripts`) or switch to `write_xlsx`.
- `src/ruby/fragments/dump-assigned-projects.rb` (2026-06): reads `/internal/debug/*.yaml`, one-off tool for Projekttage. Keep or delete. It must not write any output into the repo.
- `src/ruby/email-templates/letter-page.ru.tex` (2022): Russian letter variant, but `print-email-letters.rb` doesn't know about it. Integrate or delete.

**Delete:**
- `src/ruby/include/projekte_old.rb` (see above)
- `src/ruby/include/SUMMER-2021-TODO.md`
- `src/ruby/audio-bot-repl.rb`/`.ru` (2021/2023; not in `config.rb`)
- Schema tools from 2022: `dashboard-schema.rb`, `render-schema.rb`, `schema_renderer.rb`, `schema.dot`, `schema.svg`, `visualize-db.rb`. The `schema` page uses `neo4j_bolt visualize` anyway (`main.rb:3728`).
- `migrate-sus-with-amt.rb` (2024-09)
- `/migrate-to-neo4j-4.rb` (2022)
- `/count-lines.rb`
- `/jitsi-custom-css.css` (2021)
- `src/static/include/bootstra.386/` (3.7 MB) and `src/static/include/gantt/`: no reference
- `src/static/gyst.png` (2022): no reference found, `gyst-inverse.png` is versioned
- Maze tools `gen-maze.rb`, `parse-maze-font.rb`, `maze-font.json` and `src/static/cypher/maze/*.jpg`: only if the game is not developed further
- `src/ruby/fonts/LilitaOne-Regular.ttf` and `Pacifico-Regular.ttf`: only if no code needs them (not found by grep)

**Caution:** `src/static/wind.html` (2022) and `src/static/wallpapers.html` (2022) are not versioned and still end up in the page smoke test locally, because it reads all files from `STATIC_DIR`. They are missing in other checkouts, so the results can diverge. Delete them or commit them with an access check.

**Graphics sources:** `art/*.png` and `app-icon.svg` (2021) are source files for graphics. `art/timetable/4013017-freepik.ai` has a Freepik licence that would need checking. If the repo needs the sources: commit the `.svg` files, delete the rest or store it outside the repo.
