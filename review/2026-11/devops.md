# DevOps review gyst-dashboard

I only read and changed nothing. I did not open `data/`, `internal/`, `logs/`, `env.rb`, `credentials.rb`, `docker-compose.yaml` and `SICHERHEIT.local.md`. I only took measurements on the running test stack, i.e. with example data: startup log of `schuldashboardtest_ruby_1`, gem load time in the container, image contents.

## Summary

The foundation is solid. Ruby is pinned (`ruby:3.4.10-alpine3.24`), the services run without root, code and input data are mounted read-only, logs rotate, and the test stack runs isolated in production mode. The biggest levers:

1. **Startup time**: The startup computes a lot of unnecessary things.
   - `parse_timetable` runs twice and reads all `/vplan/*.json` of the school year each time. The startup therefore keeps getting slower until the summer.
   - On every start, all class variables are written as YAML to `/internal/debug`.
   - `setup()` sends a separate `MERGE` query for each person.
   - Synchronous HTTP calls without a timeout run at startup.
2. **Deployment**: There is no rollback path, no health checks and no migrations. `setup()` works destructively at startup. One wrong assumption in AGENTS.md §7 (see below).
3. **Backups**: They don't run automatically, aren't encrypted, and restoring is not checked.
4. **Neo4j 4.4**: Without support since November 2025. The driver (neo4j-ruby-driver 6.x) is already 5.x-capable. About 10 Cypher spots and one Neo4j setting are still blocking.
5. **Hot reload** with `Sinatra::Reloader` works, but has a concrete trap: the catch-all route `get '/*'` then shadows all reloaded GET routes.

**Error in AGENTS.md §7 / Betrieb.md:** It says “Only `src/static` changed: no restart needed”. This holds for the HTML pages, but not for JS and CSS. In production, `compile_js`/`compile_css` (`src/ruby/main.rb:1752–1816`) bundle `code.js`, `styles.css` and the libraries under `include/*` only at startup. Without a restart the old bundle keeps being served.

## Deployment & operations

| # | Suggestion | Effort | Risk |
|---|---|---|---|
| D1 | **`deploy.sh`** (separate script, `config.rb` stays unchanged), steps see below | S–M | low |
| D2 | **Keep images for rollback**, see below | S | low |
| D3 | **Puma hot restart instead of container restart**, see below | M | medium |
| D4 | **Resolve the nginx upstream dynamically**, see below | S | low |
| D5 | **No second Ruby process in parallel** (blue/green, Puma cluster), see below | – | – |
| D6 | **`compile_js`/`compile_css`: don't delete the old bundle**, see below | S | low |
| D7 | **Introduce migrations**, see below | M | medium |
| D8 | **Health checks in Compose**, see below | S | low |
| D9 | **Move the hourly rewriting of the timetables into the timetable service**, see below | S | low |
| D10 | **`config.rb` writes files only when changed**, see below | S | very low |

**D1 – `deploy.sh`.** Procedure:
- Abort if the working directory is not clean.
- `git fetch`, show the new commits, remember `PREV=$(git rev-parse HEAD)`, `git merge --ff-only`.
- Only build if `docker/` or `Gemfile*` have changed.
- Restart `ruby` and wait for `curl 127.0.0.1:8020/api/ping`, with a timeout.
- Search the first 60 s of the log for `[ERROR]`.
- Then restart the bots one after the other, `timetable` last, because it rewrites everything at startup.
- On an error, `git reset --hard $PREV` and start again.

There is a fundamental problem with deployment: the code is mounted (`./src/ruby:/app:ro`). After `git pull`, running containers immediately see the new code. Pages (`src/static`) are read per request, so until the restart is complete, new HTML runs against old Ruby code. A bot that crashes during this time restarts with the new code because of `restart: always`. Hence pull and restart directly one after the other, by script.

**D2 – Keep images for rollback.** Before `build`, save the current images with `docker tag …_ruby:latest …_ruby:prev`. Without that, a rollback after a Gemfile change needs a rebuild, and that is not reproducible because of `apk upgrade`.

**D3 – Puma hot restart.**
- `docker compose kill -s SIGUSR2 ruby` keeps the listen socket. New connections wait in the kernel backlog instead of getting a 502.
- Prerequisite: start Puma directly (`puma -e production -b tcp://0.0.0.0:3000 config.ru`), not via `rackup`. Whether the restart via the rackup handler restarts cleanly is uncertain, so check in the test stack first.
- As an optional setting in `config.rb`, so that the default output stays byte-identical.
- Plus `error_page 502 504` and `proxy_read_timeout` ≥ startup time. Otherwise waiting requests see a 504 after 60 s instead of the restart page.

**D4 – Resolve the nginx upstream dynamically.** `proxy_pass http://#{PROJECT_NAME}_ruby_1:3000` is only resolved when nginx starts. If `ruby` is recreated (`up -d` after `build`) and gets a new IP, nginx returns 502 until it restarts itself. With `DOCKER_NETWORK_RUBY_IP` this doesn't happen. Remedy: `resolver 127.0.0.11 valid=10s; set $up http://ruby:3000; proxy_pass $up;`. The alias `ruby` already exists; this also removes the dependency on `--compatibility`. This changes the output of `config.rb`, so it is a deliberate decision or an optional setting.

**D5 – No second Ruby process in parallel.** About 96 class variables serve as caches (e.g. `@@lehrmittelverein_state_cache`, `@@ws_clients`). Two processes would drift apart. In addition, `compile_js` deletes `/gen/js/` completely at startup (`FileUtils::rm_rf`), and the old process then lacks its bundles. Only tackle this after the TODO „Klassenvariablen absichern“ (secure class variables).

**D6 – Keep the old bundle.** Leave the last 2–3 `compiled-*.js/css` in place. Otherwise pages that were served during the restart get a 404 when loading the bundle.

**D7 – Migrations.** Today there are only one-off scripts (`mig-2021-09-05.rb`, `migrate-sitzplan.rb` …) and `setup()` on every start.
- Numbered, idempotent scripts that record in `(:Migration {id})` what has run. Run them explicitly in the deploy script after a dump.
- **Important:** At startup, `setup()` deletes all `TabletSet`s, including bookings, that are not in the input data. If the file is missing, `parse_tablet_sets || {}` is empty, and *all* of them are deleted (`src/ruby/main.rb:439–451`). Abort on an empty list. This is a small change (S) and should come first.

**D8 – Health checks.** `neo4j`: `cypher-shell 'RETURN 1'`. `ruby`: `curl -f localhost:3000/api/ping` (curl is in the image). `depends_on: condition: service_healthy`. Optionally switchable, because of the byte identity.

**D9 – Hourly rewriting in the timetable service.** Today it runs via host cron through `update-timetables.rb` → `config.rb`. In the process this regenerates `docker-compose.yaml` and `default.conf` every hour and needs Ruby on the host. Better a thread in the timetable service that puts `{which: 'all'}` into the queue every hour. That is versioned and testable. Since commit 49d2caae (“write files only when changed”) the run is cheap anyway.

**D10 – Write files only when changed.** `config.rb` should only write its files when the content has changed. The output stays byte-identical.

## Images & containers

The Ruby image is **2.23 GB** in size and is built separately for each Ruby service, with its own tag.

| # | Finding / suggestion | Effort | Risk |
|---|---|---|---|
| I1 | **Docker engine in the Ruby image** (`apk add docker`: dockerd, containerd, CLI, about 180 MB). Not used anywhere, no socket mounted → remove | S | low |
| I2 | **`ruby-dev` (apk) installs a second Ruby version** (`/usr/bin/ruby` next to `/usr/local/bin/ruby`). `ruby:alpine` brings the headers itself → remove, keep `build-base`/`curl-dev` or move them into a build stage | S | low–medium (check the rebuild of native gems) |
| I3 | **`openjdk11-jre`** (155 MB): LibreOffice doesn't need Java for the DOCX→PDF conversion (`include/zeugnisse.rb`) → remove on a trial basis | S | medium (Zeugnisse (report cards) aren't in the test stack, so check by hand) |
| I4 | **One image for all Ruby services**: `build` only for `ruby`, the others with `image: <projekt>_ruby`. Saves build time and tags. Changes the output of `config.rb` | S | low |
| I5 | **`apk upgrade` / `apt-get upgrade`**: weigh reproducibility against patches. My suggestion: leave it in the Dockerfile, but `build --pull` monthly (CI cron or host), plus a Trivy scan. The actual problem is that images are only rebuilt when the Dockerfile changes | S | low |
| I6 | **Fixed versions**: `nginx:stable` → e.g. `nginx:1.28-alpine`; `neo4j:4.4-community` → fixed patch version; `lgatica/weasyprint` has no tag at all and is a third-party image → pin a version or digest, in the medium term a small image of our own. `MAINTAINER` is deprecated | S | low |
| I9 | `pry`/`rerun` in the production image: `main.rb:24` always loads `pry`, and `src/scripts/pry.rb` is the production admin console → **deliberately keep** `pry`, move `rerun` into the `:development` group | S | low |

## Backups

Today: only the manual `dump-database.rb`, recommendations in `doc/Betrieb.md`.

| # | Suggestion | Effort | Risk |
|---|---|---|---|
| B1 | **Nightly run via systemd timer/cron** (`backup.sh` in the repo), see below | S–M | low |
| B2 | **Restic as the target**: encrypted on the client, deduplicated, rotation with `forget --keep-daily 7 --keep-weekly 8 --keep-monthly 12 --prune`, offsite. Keep the repo password separate from the server (paper or the school management's password manager). External storage only with a data processing agreement | S | low |
| B3 | **Check restoring automatically**, see below | M | low |
| B4 | **Monitoring**: success or failure via ping (Healthchecks.io or similar) or mail. Without an alert nobody notices a failed backup | S | – |
| B5 | A mandatory dump before every deployment with a migration and before the school year change, via `deploy.sh` | S | – |

**B1 – Nightly run.**
- `dump-database.rb` with output to stdout, through `gzip`.
- Plus `DATA_PATH/raw`, `INTERNAL_PATH` **without `debug/`**, `INPUT_DATA_PATH`, `env.rb`, `credentials.rb`.
- The logical dump via Bolt is independent of the store format and thus also the migration path to Neo4j 5. It is not transactionally consistent, but uncritical at night.
- `neo4j-admin dump` would have to stop the DB in the Community Edition.

**B3 – Check restoring.**
- Monthly, on the server.
- Start a throwaway Neo4j container (without Ruby, without mail, without ports) and load the latest dump.
- Compare node and relationship counts per label with the live DB or the dump header.
- Alert on the result and delete the container again.
- Real data stays on the server in the process, never in CI.

## CI

| # | Suggestion | Effort | Risk |
|---|---|---|---|
| C1 | **`.github/workflows/test.yml`**, see below | M | low |
| C2 | **Automate the byte-identity check**, see below | S | low |
| C3 | **Dependabot** for `bundler` (`src/ruby`), `npm` (`test/e2e`), `github-actions`, `docker` (FROM lines in `docker/*`) | S | low |
| C4 | **Monthly run** (`schedule`): catches date-dependent bugs and drift of the base images. Plus `trivy image` (report only) | S | – |
| C5 | Bring the test stack closer to production: add `image_bot`, `mail_bot`, `weasyprint`, see below | S–M | low |

**C1 – Workflow.**
- Trigger: `pull_request` and `push` on master. **No `pull_request_target`**.
- `permissions: contents: read`, `concurrency` with `cancel-in-progress`, pin actions by SHA.
- First `./test.sh unit` for quick feedback, then `./test.sh e2e`.
- On failure, `playwright-report`/`test-results` and `./test.sh logs` as an artifact (7 days). This is only possible because exclusively example data is involved.
- No secrets are needed. That is ideal for a public repo with forks.
- The build time of the 2.2 GB image is the bottleneck: buildx cache (`type=gha`) or a base image built weekly to GHCR as `cache-from`. I1–I3 make the image considerably smaller.
- Make the status check on master mandatory.

**C2 – Check byte identity.** Generate `config.rb` with `env.template.rb`, once each with `DEVELOPMENT=true` and `false`, normalise `UID`. Compare the result with checked-in reference files (`test/fixtures/compose-*.yaml`, `nginx-*.conf`). This way the rule from AGENTS.md is checked mechanically.

**C5 – Extend the test stack.** Without `image_bot`, `ruby` waits 5 s for a DNS timeout at startup in the test stack (see startup log).

## Dependencies & upgrades (incl. Neo4j 5)

**Neo4j 4.4 → 5.26 LTS or 2025.x/2026.x** (`neo4j:2026.06.0-enterprise` from another project is already present locally). Effort M, risk medium.

1. **Driver**: `neo4j_bolt 0.5.0` uses `neo4j-ruby-driver 6.2.1.beta.4` (Bolt 5, `element_id` available). The schema commands in the gem already use the 5.x syntax (`CREATE CONSTRAINT … IF NOT EXISTS FOR … REQUIRE`). The catch: the beta version is pinned exactly.
2. **Cypher** (≈10 spots):
   - `EXISTS(n.prop)` is removed in 5 and becomes `n.prop IS NOT NULL`. Affected: `timetable.rb:1132`, `include/stats.rb:6`, `include/message.rb:121–123`, `include/ical.rb:6`, `include/salzh.rb:22,1003`, `include/directory.rb:868,873`.
   - Pattern form `EXISTS((u)-[…]->(v))` in `include/techpost.rb:6` → `EXISTS { … }`.
   - `id()` (≈17 spots) is only deprecated and keeps working.
3. **Configuration**: `NEO4J_dbms_logs__timezone` no longer exists in 5 (logging runs via log4j2). Because of the strict configuration check, the container won't start otherwise.
4. **Data**: logical dump from 4.4, load into an empty 5.x, compare counts. Keep the old data directory as a rollback.
5. **Procedure**: On a branch, only change the FROM line in `docker/neo4j/Dockerfile` and run `./test.sh all`. The test stack is exactly right for this. After that, the dress rehearsal with a copy of the real data on the dev instance.

**Ruby gems**: up to date (Sinatra 4.2.1, Puma 8.0.2, Rack 3.2.7). Open points:
- Justify or lift the pins `rubyzip <3`, `prawn <2.5`, `ttfunk <1.8`.
- The `mustermann` comment doesn't match the specification `>=3.0.3` (already in TODO).
- Dependabot (C3) takes over the ongoing maintenance. Effort S.

**JS under `src/static/include`** (checked in, invisible to Dependabot):

| Library | Version | Status |
|---|---|---|
| Bootstrap | 4.4.1 | no fixes since 2023 |
| jQuery | 3.6.1 | |
| jQuery UI | 1.13.2 | |
| FullCalendar | 5.1.0 | current 6.x |
| Chart.js | 2.9.4 | |
| JSZip | 3.6.0 | |
| clipboard | 2.0.0 | |
| moment | ? | only in maintenance mode |

Suggestions:
- First an inventory list (`src/static/include/VERSIONS.md`). Effort S.
- Then patch updates that don't break anything: jQuery 3.7.x, JSZip 3.10. Effort S, risk low.
- The switch Bootstrap 4 → 5 / FullCalendar 6 depends on the UI decision Bootstrap/Tailwind/Flowbite. Only tackle it with E2E coverage. Effort L, risk high.

**Nextcloud sandbox 30.0.6** → current version, development only. Effort S, risk low.

## Development: startup time & hot reload (concrete plan with risks)

### Where the startup time goes

Measurement in the test stack (example data), 32 s from container start to “Server is up”:

| Phase | Duration | Remark |
|---|---|---|
| Container start, gem requires, `wait_for_neo4j` | ≈7 s | requires 1.7 s of that, measured |
| `collect_data` | ≈1 s | a multiple with real data |
| `setup()` | 3.5 s | constraints/indexes individually with `IF NOT EXISTS` |
| SVG backgrounds | 15 s | 920 files, only because `.test-stack` is deleted every time; cached in production |
| DNS timeout `image_bot` | 5 s | service missing in the test stack |
| `refresh_bib_data` | – | fails immediately here |

In production, the 30–40 s probably arise mainly here:

1. **`parse_timetable` twice** (`main.rb:1044` and `:1077`, the latter only for “patching”). Each call reads all timetable sources and **all `/vplan/*.json` of the year** (`parser.rb:1163`). Reuse the result. Effort S–M, risk medium (core logic; extend `parser_test.rb` first).
2. **YAML dump of all class variables** to `/internal/debug` on every start (`main.rb:1449–1460`). Psych is slow with large hashes. In addition, this is an unencrypted copy of all personal data that ends up in the backup along with `INTERNAL_PATH`. Only with `DASHBOARD_DEBUG_DUMP=1` or in a background thread. Effort S, risk low.
3. **`setup()`**: individual `MERGE` per email address, tablet and PEU. Replace with `UNWIND $emails AS e MERGE (:User {email: e})`. Only create constraints if they are missing according to `SHOW CONSTRAINTS` (change in the gem). Effort S, risk low.
4. **Synchronous network calls at startup**: `image_bot/api/update_all` (Net::HTTP with 60 s timeouts) and `refresh_bib_data` (Curl without timeout). In production the latter also blocks a request in the `before` filter once an hour. Move into a thread and set timeouts of 2–5 s. Effort S, risk low.
5. **Every bot runs `collect_data`**, because it loads `main.rb`. So on `restart`, six processes compete for the CPU at the same time. In the medium term, store the result of `collect_data` as a Marshal cache, keyed by the modification times of the input files; bots and restarts read it in milliseconds. Effort M, risk medium (cache invalidation).
6. **Measure first**: output the duration of each phase with `debug`. Effort S. Without numbers from production, 1, 2 and 5 are estimates.
7. In the test stack, keep `.test-stack/data/gen/bg` across runs: ≈15 s less per E2E run. Effort S.
8. Little benefit: YJIT (`RUBY_YJIT_ENABLE=1`), bootsnap (saves less than 1 s).

### Hot reload: today

`rerun` watches `/app` in **every** Ruby service (7 containers). Every change, even under `test/` or in `email-templates/*.html`, restarts all of them. Each runs `collect_data`, and `timetable` rewrites all timetables (minutes with real data). Even `--ignore "test/*"` helps. Effort S.

### Plan with Sinatra::Reloader (sinatra-contrib 4.2.1 is in the bundle)

1. **New file `src/ruby/dev_reloader.rb`**, loaded in `main.rb` *before* the `include/*.rb` (≈line 99). This way the reloader's `before` hook is registered before `before '*'`, and all routes are captured:

```ruby
if DEVELOPMENT && ENV['DASHBOARD_HOT_RELOAD'] == '1' && ENV['DASHBOARD_SERVICE'] == 'ruby'
  require 'sinatra/reloader'
  class Main < Sinatra::Base
    register Sinatra::Reloader
    set :reloader, true   # rackup läuft mit --env production → development? ist false
    also_reload './include/*.rb'   # Dateien nur mit def werden sonst nicht beobachtet
    dont_reload './main.rb', './parser.rb', './timetable.rb', './include/color-schemes.rb'
    after_reload do
      %w(GET HEAD).each do |verb|
        r = routes[verb] or next
        tail, rest = r.partition { |x| x[0].to_s == '/*' }
        r.replace(rest + tail)   # Catch-all wieder ans Ende
      end
    end
  end
end
```

2. **`config.rb`**: With an optional setting `DEV_HOT_RELOAD = true`, `ruby` sets the variable `DASHBOARD_HOT_RELOAD=1` and `rerun … --ignore "include/*"`. Without the setting the output stays byte-identical. The bots ignore `include/*` as well. Whoever changes bot code in `include/` restarts the bot by hand (document this).
3. **Safeguard via unit test** (in the style of `backend_rules_test.rb`): `sinatra/reloader` may only appear in `dev_reloader.rb`, and that file only under the triple condition.

**Risks:**

- **Catch-all route (the actual problem)**: The reloader removes the routes of a changed file and, on reloading, appends them *at the end*, behind `get '/*'` (`main.rb:3570`). Without the `after_reload` fix, every GET route of a reloaded include file is silently dead. POST is not affected. Check the signature of `after_reload` in 4.2.1.
- **Order in general**: The precedence between include files changes too. With overlapping patterns (`/api/x/:id` vs. `/api/x/foo`), the behaviour can change. A test for overlapping routes helps.
- **Why not simply `load`**: A plain `load include/x.rb` (as done today for `fragments.rb`) is only safe for the ≈10 files without routes. In files with routes it appends duplicates, the old route wins, and changes to the route body *silently have no effect*. Hence the reloader.
- **Never reload `main.rb`**: That would run all `configure` blocks again (`collect_data`, `setup`, writing to `/gen`, `@@ws_clients = {}`, constant `ES256_PRIVATE_KEY`). That is practically a restart with half-initialised state under 16 threads. Hence `dont_reload`; `rerun` remains responsible for `main.rb`.
- **State at class level**:
  - `include/sitzplaneditor.rb:2` resets `@@room_hours_for_klasse = {}`.
  - `include/sitzplan_daten.rb:29` creates a new `WRITE_MUTEX` (briefly two mutexes). Guard with `const_defined?`.
  - Top-level constants produce warnings.
  - `color-schemes.rb` is only evaluated at startup, hence on `dont_reload`.
- **Startup code is not run again**: `self.*` methods (`parse_zeugnisformulare`, `determine_lehrmittelverein_state_for_all` …) are redefined, but not run again. Report in the log: “reloaded, startup data unchanged”.
- **Deleted and renamed methods stay defined**: Locally, things then still work that fail after a restart. The test stack runs without the reloader, and `./test.sh all` before every push catches this.
- **Threads**: `Reloader.perform` runs under a mutex, but parallel requests keep running. Running calls keep the old method body. Acceptable for development.

**Gain:** Changes to `include/*.rb` (49 of 59 files with routes) take effect on the next request instead of after 30–40 s, and there is no restart storm across 7 containers. Total effort M, risk for production low (triple safeguard), medium in development.

## Can go / simplify

All items with effort S:

| What | Risk |
|---|---|
| Docker engine, `ruby-dev` (second Ruby version), probably `openjdk11-jre` in the Ruby image | low |
| The second `parse_timetable` in `collect_data` | medium |
| Debug YAML dump on every start (`/internal/debug`) | low |
| `version: '3'`, `MAINTAINER`; dependency on `_ruby_1`/`--compatibility` (via the alias `ruby`) | low |
| Sixfold build of the same Ruby image | low |
| Host cron for the hourly rewriting → thread in the timetable service | low |
| `src/scripts/reload-monitors.rb` (“not functional yet”), `migrate-to-neo4j-4.rb`, old `mig-*`/`migrate-*.rb` → archive | low |
| `rerun` in all bots in development → only `ruby` automatically, bots by hand | low |
| `rm_rf('/gen/js/')` → only clean up old bundles | low |
| Correction in AGENTS.md §7 and `doc/Betrieb.md`: changes to JS/CSS in the bundle need a restart of `ruby` in production | none |

## Relevant files

- `config.rb`
- `docker/ruby/Dockerfile`
- `docker/neo4j/Dockerfile`
- `docker/nginx/Dockerfile`
- `src/ruby/main.rb`: setup 390–537, collect_data 681–1462, compile 1704–1816, configure 1818–1898, dev `before` 1977–1995, catch-all 3570
- `src/ruby/parser.rb`: 955ff., 1163
- `src/ruby/timetable-repl.rb`
- `src/ruby/include/sitzplaneditor.rb`
- `src/ruby/include/sitzplan_daten.rb`
- `src/scripts/dump-database.rb`
- `test.sh`
- `doc/Betrieb.md`
- `AGENTS.md`
