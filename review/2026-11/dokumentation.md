# Documentation review gyst-dashboard

## Summary

For the age of the project, the documentation is good. The new chapters (Architektur, Development, Betrieb, Tests, AGENTS.md) are up to date as of November 2026 and largely match the code. There are three big weaknesses:

1. **The older chapters are outdated.** Affected are Installation, Daten and Nextcloud (as of 2021, with wrong links, paths and login procedures).
2. **The configuration is barely documented and scattered.** It is spread across `env.rb`, `credentials.rb`, `/data/config.rb` and **eight further `/data/*/config.rb`**, which `main.rb:78-85` loads hard via `require`. No documentation mentions these eight files. About 10 constants are used by the code, but are neither in the template nor in the example data.
3. **There is practically no help for end users.** `hilfe.html` only explains the school email account and links hard to IONOS in the process.

## Errors and outdated passages

**README.md**
- `:3` The sentence „Einstiegspunkt … im Distanzunterricht“ (entry point … in distance learning) is Corona framing. The feature list (`:19-25`) names 6 of over 30 modules. Surveys, messages, appointments, library, Zeugnisse (report cards), Projekttage (project days) and monitors are missing. Licence (GPLv3), tests and AGENTS.md are not linked. (S)
- `:33` links to specht.github.io. The local build dates from 07/2024, the new chapters are probably not published. (S)

**doc/Installation.md**
- `:3-7` “docker-compose”: Today this is Compose v2 (`docker compose`). `config.rb` can do both. (S)
- `:40`, `:48-52`: According to the docs, you get the login code from the log (`!!!!! … => 224529`). This debug line is commented out (`include/login.rb:608`). In development mode, `123456` applies as a fixed code, `654321` as the second factor (`login.rb:605`, `:157`). Development.md describes this correctly. (S)
- `:106-107`: The TTY note is obsolete, the scripts call `exec -T` (`src/scripts/create-nc-folders.rb`). (S)
- `:113`, Nextcloud.md `:422`/`:462`: The container name `schuldashboarddev_nextcloud_1` depends on `--compatibility`. Better `./config.rb exec -T nextcloud …`. (S)
- `:131-135`: `share-nc-folders.rb --srsly` aborts if `NEXTCLOUD_INSTALL_PATH` is missing (`src/scripts/share-nc-folders.rb:26-28`). In `env.template.rb:33` the value is `nil`, so the sandbox run doesn't work like this. Moving now runs via `nextcloud-share-move-worker.php` via `sudo php` on the host. The description via `user_external` is therefore at least incomplete. (M)
- No reference to Betrieb.md for production operation. (S)

**doc/Development.md**
- `:11-16` „Lokal starten“ (starting locally) leaves out the SSO keys. Without them, every page ends with HTTP 500 after login (`main.rb:547`, TODO.md:189). Adopt or link the step from Installation.md. (S)
- `:41` „Port in `config.rb` auf `127.0.0.1` binden“ (bind port to `127.0.0.1` in `config.rb`) is wrong: there is `NGINX_HOST_ADDRESS` in `env.rb` for that (`config.rb:19`). (S)

**doc/Daten.md**
- `:5` The path `/schul-dashboard/src/example-data/` doesn't exist, correct is `src/example-data/`. (S)
- `:31`, Nextcloud.md `:6`/`:10`: The links `Installation.md` don't work in YARD, they have to be `file.Installation.html`. (S)
- `:37-75`: The holidays only go up to 2021, but the school year of the example data (`config.yaml`) is 2024/25. Example file and docs excerpt don't match. (S)
- `:140` For the teacher's abbreviation, it is not „siehe `faecher/faecher.csv`“ (see `faecher/faecher.csv`) but `lehrer/lehrer.csv`. (S)
- `:145` „Stundenzeiten in `credentials.rb`“ (lesson times in `credentials.rb`) is wrong. They are in `/data/config.rb` (`fix_stundenzeiten`, `HOURS_FOR_KLASSE`). (S)
- `:139` For the class mapping, `credentials.rb` is named. In fact there are `KLASSEN_TR` and `PARSE_KLASSE_TR` in the template, and `/data/config.rb` overrides them (see Configuration). (S)

**doc/Betrieb.md and AGENTS.md**
- AGENTS.md `:182-184` says: “Only `src/static` changed: no restart needed.” That is wrong for bundled files. `code.js`, `styles.css`, `sound.js`, `barcode-widget.js`, `sortable-table.js` and `include/*` are only bundled at startup in production (`main.rb:1752-1830`). (S)
- AGENTS.md `:182` says “restart ruby”, Betrieb.md `:175` „Bots ggf. ebenfalls“ (bots possibly as well). The two contradict each other and are vague. The bots (`timetable`, `mail_bot` …) load the same code, so define clearly which services must be restarted when. (S)
- Betrieb `:276-286` refers to `TODO-NEUES-SCHULJAHR.md`. This file is not in `doc/` and is therefore not publicly visible. (S)
- The script table (`:294-302`) is incomplete. Missing are `json_nodes_to_xlsx.rb`, `reload-monitors.rb`, `vplan-watcher.rb` and `nextcloud-share-move-worker.php`, plus around 20 one-off scripts in `src/ruby/` (`assign-projekttage.rb`, `send-bibliothek-zahlungsaufforderung.rb`, `schedule-beratungstermine*.rb` …). (M)

**doc/Tests.md**
- `:53-67` „Stand“ (status) is outdated. Only colours and parser are listed as unit tests. But there are also `backend_rules`, `frontend_rules`, `gz_output`, `image_upload` and `mail_guard`. For E2E only login tests are listed. Also present are `events`, `lessons`, `messages`, `polls`, `profile`, `session`, `sitzplan`, `directory_admin` and `dialogs`. (S)
- The Playwright project `screens` (`ui-tour.screens.ts`) and `hardening.smoke.ts` are not documented. Describe the latter only neutrally, see AGENTS §1. (S)
- `:146` refers to `src/ruby/test-*.rb`. These files are not versioned, they don't exist publicly. `:165-172` (candidates) and `:181-186` (smoke test as “planned”) are already done. (S)

**doc/Sitzplanhelfer.md**
- `:4` The link `../src/static/sitzplan.html` doesn't work in YARD. `:50`/`:57`: The number “5.” appears twice. The quotation marks are mixed („…" and „…“). (S)
- „Geänderte/neue Dateien“ (changed/new files) and „Umstellung“ (migration) are PR or migration text. Rename to „Dateien“ (files), move the migration to Betrieb or delete it after the migration. (S)

**doc/Architektur.md**
- `:86` „Die Bots sind Sinatra-Anwendungen auf 8080“ (the bots are Sinatra applications on 8080) is not true for `vplan_watcher` and `mail_forwarder`, those are plain scripts. `vplan_watcher`, `mail_forwarder` and `weasyprint` are missing from the diagram. (S)

**env.template.rb**
- `:2-4` „nach Änderung `./config.rb build`“ (after a change `./config.rb build`) is imprecise. `up -d` is usually enough. `build nginx` is only needed if `PROJECT_NAME` or the nginx configuration changes. `:12` typo „vtml.“. (S)

**update-documentation.sh**
- The script depends on `../schul-dashboard/` and `../schul-dashboard-doc/`. `cp -pur` leaves deleted pages in place, `git add *` takes everything along. `.yardopts` also includes all one-off scripts. (S/M)

## What is missing (by target group)

**(a) New developers**
- A glossary of the roughly 95 class variables (`@@user_info`, `@@lessons`, `@@klassen_for_shorthand` …) with origin (`collect_data`, `main.rb:681`) and structure. (M)
- The startup sequence: credentials, then `/data/*.rb`, then `collect_data`, `compile_*` and Neo4j setup (`main.rb:1828-1890`), plus `DASHBOARD_CREDENTIALS` and `SKIP_COLLECT_DATA`. (S)
- A Neo4j data model. So far this only exists for the Sitzplanhelfer (seating plan helper). `schema.dot`/`schema.svg` and `render-schema.rb` are lying around undocumented. (M)
- A module map that assigns each file in `include/*.rb` its page and feature. Of 58 files, only 3 have a header comment. (M)
- The note that `include/cypher.rb` has **nothing** to do with Neo4j Cypher (Morse/puzzles), and neither does `hack.rb`. (S)

**(b) Maintainers in operation**
- Regular jobs: What runs via cron, what has to be triggered by hand (Nextcloud collection, `send-pending-emails`, backups)? (M)
- Connecting the reverse proxy: which Docker network (`DOCKER_NETWORK_NAME`), how nginx-proxy finds the container. (S)
- Setup of the SMS gateway (`include/sms.rb:168`, `SMS_GATEWAY_SECRET`), of Matrix/Corporal, Jitsi JWT, Untis Vertretungsplan (substitution plan) and mail forwarder. So far there is only one line or nothing at all about these. (L)
- A complete procedure for the school year change, including constants to be changed yearly: `LEHRBUCHVEREIN_JAHR`, `PK5_CURRENT_KLASSE`, `DEADLINE_*`, `ZEUGNIS_*` and the hard-coded dates in `main.rb:3572-3573`. (M)
- Troubleshooting: SSO keys missing, port conflict, error lines in the input data at startup. (S)

**(c) Setting up a new school**
- A checklist “What is specific to Gymnasium Steglitz?”. Hard-coded are, among others, the footer (`_template.html:818`), `fragments.rb` (18 hits, e.g. „Berlin, den“ (Berlin, [date])), `hilfe.html` (IONOS) and `send-bibliothek-zahlungsaufforderung.rb`. (M)
- A reference of all input files: `lehrer.csv`, `schueler/ASCII.TXT`, `email-sub.txt`, `roles.txt` with a **list and meaning of all roles**, `klassenleiter.txt`, Kurswahl (course selection), Pausenaufsichten (break supervision), `tablet_sets.yaml`, `extra-dashboard-accounts.csv`, `mock/`. Daten.md only describes three files. (L)
- The eight module configurations `/data/{lab8,lab9,phishing,pk5,projekte,unterstufenparty,zeugnisse,bibliothek}/config.rb`. They are mandatory, otherwise nothing starts. This includes the hook methods in `/data/config.rb` (`fix_stundenzeiten`, `fix_lesson_key_tr`, `fix_lessons_for_shorthand`, `fix_parsed_klasse` …). (M)
- Which modules can be switched off and how. For most this isn't possible today. (M)
- How to generate secrets (e.g. `SecureRandom.hex(32)`) and the warning that they must **never be changed again**. They are embedded in IDs (`main.rb:809`, `:972`, `:1103`, i.e. in `/gen` paths and iCal links) and in the initial passwords (`parser.rb:358-362`). `EMAIL_PASSWORD_SALT` must stay secret. (S)

**(d) End users**
- `hilfe.html` only covers the school email account. The IONOS URLs are hard-coded (`:34`, `:126`, `:133`), although `SCHUL_MAIL_LOGIN_URL` exists. Missing: login by code, setting up two-factor/OTP, switching accounts, iCal link, profile and colours, Nextcloud folders (the procedure from Nextcloud.md would be better placed here), messages and surveys, parent accounts, “what to do if there are problems”. Separated by SuS (students, addressed with „du“), teachers and parents. (L)
- The videos are from 2021. At least mark them as “older version”. (S)

## Configuration (credentials.template.rb / env.template.rb)

**Unused, so delete** (checked by grep over `src/`): `IMAP_SERVER` (`:49`), `VOTING_CONTACT_EMAIL` (`:108`), `JWT_APPAUD_AGRAPP` and `JWT_APPISS_AGRAPP` (`:166-167`), `VPLAN_ENCODING` (`:199`). (S)

**Conditions without effect**: `MESSAGE_DELAY = DEVELOPMENT ? 1 : 1` (`:197`), `JITSI_LESSON_*_TOLERANCE` (`:202-203`). (S)

**Required by the code, but defined neither in the template nor in the example data.** The affected function aborts as soon as it is used:
- Zeugnisse: `NOTEN_CUTOFF`, `DEADLINE_SOZIALNOTEN` (`user.rb:606`), `SHOW_PREVIOUS_NOTEN`, `SOZIALNOTEN_CATS/KEYS/MARKS`, `DETAIL_NOTEN`, `FAECHER_SPRACHEN` (`fragments.rb`). Belong in `example-data/zeugnisse/config.rb`.
- `PK5_PUBLISH_FINAL_THEMA` (`pk5.rb:24`), `WANTS_TO_RECEIVE_TECHPOST_DEBUG_MAIL` (`techpost.rb:53`), `EMAILS_AUS_DEM_UNTERRICHT_KLASSENLEITUNG_CC` (`mail-bot-repl.rb:58`), `AUFSICHT_DAUER` (`parser.rb:1312`). (M)

**Duplicate or contradictory**
- `DEVELOPMENT` and `WEBSITE_HOST` are in `env.rb` **and** in `credentials.rb` (`:6`, `:99`). In credentials, `DEVELOPMENT` is a string or `nil` from the environment. Add the comment “don't change”. (S)
- `KLASSEN_ORDER`, `KLASSEN_TR`, `AUFSICHT_ZEIT`, `SWITCH_WEEKS`, `TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS` and `WECHSELUNTERRICHT_KLASSENSTUFEN` are in the template **and** in `example-data/config.rb`. The second definition wins, and Ruby warns about it. The values contradict each other: `KLASSEN_TR` is `8o` in the template, but `9o` in the example data. In addition there is `PARSE_KLASSE_TR` as the reverse mapping without a comment. (M)
- `ROOM_ORDER` doesn't match the example data (already in TODO.md). `example-data/pk5/config.rb` refers to credentials for `PK5_CURRENT_KLASSE`. (S)

**Misplaced**
- School structure and yearly values belong in `/data`: `KLASSEN_*`, `ROOM_ORDER`, `AUFSICHT_ZEIT`, `PK5_CURRENT_KLASSE`, `LEHRBUCHVEREIN_JAHR`, `DEADLINE_*`, `ZEUGNISKONFERENZEN`, `GROUP_AF/FT_ICONS`, `TABLET_COLORS`.
- Code in the configuration: the `Mail.defaults` block (`:56-68`), `MAILING_LIST_FORWARDER_ACCOUNTS` with a duplicate hash and the method `override_email_login_recipient_for_chat` (`:248`).
- Corona legacy: `WECHSELUNTERRICHT_*`, `SWITCH_WEEKS` with dates from 2021, `EXCLUDE_FROM_SELF_TEST_REPORT`, `PROVIDE_CLASS_STREAM`, `STREAMING_TABLET_*`, `JWT_*_STREAM`. (M to L, matches TODO.md §3)

**Without any comment** (selection of the most important):
- `DEVELOPMENT_MAIL_DELIVERY_POSITIVE_LIST`: security-relevant, so far only explained in AGENTS.md.
- `MAX_LOGIN_TRIES`, `COOKIE_EXPIRY_TIME`, `MAINTENANCE_MODE`, `LOGIN_STATS_D`, `GEN_IMAGE_WIDTHS`.
- All `MATRIX_*`, `JWT_*`, `BIB_HOST`, `DATENTRESOR_*`, `SMS_*`, `WEBSITE_READ_INFO_SECRET`, `SCHOOL_WEBSITE_API_URL`, `UNTIS_VERTRETUNGSPLAN_*`, `MONITOR_*_DEEP_LINK`, `KLASSENRAUM_ACCOUNT_DEEP_LINK_CODE`, `SEMI_PUBLIC_LINKS`, `DEMO_ACCOUNT_*`, `FOTO_PASSWORD`, `FACH_CONSOLIDATE_FOR_VERTEILER`, `VERTEILER_*`.

Suggestion: structure the template into sections (mandatory / secrets / mail / integrations per module / optional / deprecated) and comment every constant with one line. (M)

**env.template.rb**
- The optional switches from `config.rb:17-22`, `:160`, `:271`, `:288` are missing: `NGINX_HOST_ADDRESS`, `NGINX_HOST_PORT`, `PUBLISH_DEV_PORTS`, `COMPOSE_FILE`, `NGINX_CONFIG_FILE`, `CREDENTIALS_FILE`, `EXTRA_SERVICES`, `RESTART_SERVICES`. Add them as commented-out examples. (S)
- `DOCKER_NETWORK_NAME` has no comment. That `NEXTCLOUD_SANDBOX_INSTALL_ADMIN_PASSWORD` must equal `NEXTCLOUD_PASSWORD` in credentials is stated nowhere. Likewise the note that `WEB_ROOT` in credentials must match `NGINX_HOST_PORT` is missing. (S)

## Code documentation: where comments and overview are most urgently missing

1. **Template evaluation**, `main.rb:~4060-4115`. Every `#{…}` goes through `eval`, with bracket counting. This is the most surprising mechanism in the project. A block comment on rules, error behaviour and security is needed. (S)
2. **`get '/*'`**, `main.rb:3570` ff. Several hundred lines of data preparation per page, plus hard-coded dates in the header (`:3572-3573`). A section comment per page and a list of which page sets which variables. (M)
3. **`collect_data`**, `main.rb:681` to about 1400: every `@@` variable with structure and example. (M)
4. **`include/login.rb`**: 1137 lines, 25 comment lines. Describe code, tag, second factor, session and device as a state machine. Security-critical. (M)
5. **`timetable.rb`** (2705 lines): Which files are created under `/gen`, in which format, and when are they rewritten? (M)
6. **`include/roles.rb`** (70 lines, 1 comment): meaning of each role and each transition. (S)
7. **`fragments/fragments.rb`** (3031 lines, Prawn PDFs for Zeugnisse among others): header comment, who calls it, what is school-specific. (S)
8. **`include/projekte.rb`** (2087 lines, 27 comments), **`share-nc-folders.rb`** (1299 lines, 32 comments, starts PHP on the host), **`include/directory.rb`**. (M)
9. **`Neo4jGlobal`** is defined three times (`main.rb:227`, `stats-bot-repl.rb:10`, `mail-bot-repl.rb:12`). Comment or merge. (S)
10. **`code.js` `api_call`** and the template helpers: document behaviour and error contract. (S)
11. A header comment for all `include/*.rb` (so far 3 of 58 have one). (M)

## Can go / merge

- **AGENTS.md ↔ Development.md „Konventionen“ (conventions) ↔ Architektur „Daraus folgt“ (consequences)**: The rules are stated three times. AGENTS.md should be the single source of the rules, `doc/` only explains the why and links. The language split is defensible in itself, agents read both. With a German-speaking team and German code context, however, AGENTS.md in German would be more consistent. More important than the language is reducing the duplicates. (S)
- **Tests.md „Stand“, „Noch offen“ (still open), „Reihenfolge“ (order) ↔ TODO.md §1**: Keep the plan only in TODO.md. Tests.md then only describes how to run and write tests. (S)
- **TODO-NEUES-SCHULJAHR.md**: include it in Betrieb.md as a checklist (with dump, Cypher, yearly constants, Nextcloud archive), then delete it or replace it with a script (already in TODO.md). The Cypher line for „Antikenfahrt“ (classics trip) is school-specific. (S)
- **Installation.md**: Merge the dev start part with Development.md. Move the Nextcloud part to Nextcloud.md. (M)
- **Nextcloud.md**, section „Ablauf/Beispiel“ (procedure/example): The user part belongs in the end-user help, the long log outputs can go. (S)
- **Sitzplanhelfer.md**: Drop or shorten „Umstellung“ and „Geänderte Dateien“. (S)
- **YARD API docs**: The code comments are so thin that it hardly brings any benefit. Only publish the Markdown chapters (e.g. via GitHub Pages or Actions). (S)
- Review unversioned legacy files (`count-lines.rb`, `migrate-to-neo4j-4.rb`, `jitsi-custom-css.css`, `include/SUMMER-2021-TODO.md`, `src/ruby/test-*.rb`), as planned in TODO.md §3. (S)

## Proposal for a documentation structure

```
README.md            short description, feature list (current), links, licence
AGENTS.md            binding rules only (single source), links to doc/
TODO.md              the only planning list (incl. test plan)
doc/
  README.md          index by target group
  Schnellstart.md    dev instance in 10 minutes (from Installation + Development)
  Architektur.md     + startup sequence, class variable glossary, Neo4j model
  Development.md     day-to-day, new page/route, pitfalls (template eval)
  Tests.md           only the “how”
  Konfiguration.md   NEW: env.rb / credentials.rb / /data/config.rb / /data/*/config.rb,
                     table of all constants (mandatory/optional/module/deprecated)
  Daten.md           all input files + list of roles
  Neue-Schule.md     NEW: setup checklist + school-specific places
  Betrieb.md         production, proxy, updates, backups, cron jobs, school year change
  Integrationen.md   NEW: Nextcloud (admin part), Jitsi, Matrix, SMS, Untis, mail forwarder
  Module/            Sitzplanhelfer.md, later Zeugnisse, Projekttage, Bibliothek …
src/static/hilfe.html  end-user help: login/2FA, profile, iCal, Nextcloud,
                       messages/surveys; separated by SuS/teachers/parents;
                       values from SCHUL_MAIL_* instead of hard-coded IONOS URLs
```

Order: first correct the wrong passages (S). Then `Konfiguration.md` with the cleaned-up template (M). After that `Neue-Schule.md` and the end-user help (L).
