# Moving the dashboard from Neo4j 4.4 to 5.26

Status: plan, rehearsed in parts on a development machine (see "Verified so
far"). Nothing has been changed on the production server. The production
steps need the maintainer's explicit go-ahead.

## Why and where to

- Neo4j 4.4 is out of support since 2025-11-30.
- Target: **Neo4j 5.26 LTS** (`neo4j:5.26.33-community`), supported until
  2028-06-06. The 2026.x releases are only supported until the next monthly
  release. gyst-bib moves to the same version, so both projects stay on one
  version.

## Approach

**Logical dump → fresh 5.26 store → load.** No `neo4j-admin` store
migration:

- `neo4j_bolt dump` writes nodes, relationships, constraints and indexes as
  text. The format doesn't depend on the Neo4j version.
- The dump is loaded into an empty 5.26 data directory.
- The old 4.4 data directory is never touched and is the rollback.
- A rollback that keeps data written after the switch works the same way in
  reverse: dump 5.26, then load into a fresh 4.4.

## Verified so far

| What | Result |
|---|---|
| Property types in the production data (read-only census, all nodes and relationships) | only String/Integer/Float/Boolean/null and lists of these – no temporal or spatial values, so the dump with neo4j_bolt 0.5.0 is lossless (0.5.0 writes temporal values as strings, 0.5.1 fixes that) |
| Dump of a production-sized database (77k nodes, 407k relationships) | 22 s, 48 MB (7 MB gzipped), Neo4j under one core, no memory growth |
| Load into an empty 5.26 | 28 s, node and relationship counts identical, 67 indexes/constraints as RANGE indexes |
| `EXISTS(n.prop)` (10 places) | syntax error on 5.x → replaced by `IS NOT NULL` / `IS NULL` (commit 550bb557, works on 4.4, unit test keeps the old form out) |
| `EXISTS((a)-[…]->(b))`, `CALL dbms.listConnections()`, `id()`, pattern predicates in `WHERE`, `FOREACH`/`MERGE` of the group code | work on 5.26 (`id()` is deprecated, only a warning) |
| `id()` uses (17) | all within one request (grouping keys, follow-up query), never stored or sent to the browser – the new internal IDs after a load are harmless |
| `NEO4J_dbms_logs__timezone` | 5.26 **refuses to start** with it ("Unrecognized setting", strict validation); on 4.4 it was already ignored → removed |
| 5.26 started on an old 4.4 data directory | refuses to start ("store format … no longer supported"): fails safe, no data is changed |
| Full test suite against 5.26.33 (branch below) | green: 58 unit runs, 148 E2E tests (desktop, mobile, page smoke test for all roles) – note that the tests use example data and don't cover every query |

The changes for the switch are on branch `neo4j-5-migration`:

- `docker/neo4j/Dockerfile`: `FROM neo4j:5.26.33-community`
- `config.rb`: neo4j without the timezone setting, `stop_grace_period: 120s`.
  Docker kills after 10 s by default, which can interrupt the checkpoint and
  damage transaction logs.

## Pitfalls

- **`./config.rb` always exits with 0**, whatever `docker compose` returns
  (TODO.md). Don't chain the steps below on exit codes; check every result
  (container state, counts).
- **Cron on the server:**
  - `./config.rb restart mail_bot` runs daily at 19:30. `docker compose
    restart` also starts *stopped* containers, so the mail bot would come
    up in the middle of the window. Choose the window away from 19:30 or
    pause the cron entry.
  - The minute and hour jobs (`send-pending-emails.rb`,
    `update-timetables.rb`) only fail while `ruby` is stopped. That's
    harmless.
- **Merge the branch only in the window.** Every `./config.rb up -d` or
  `build` on master after the merge switches the server to 5.26. On the old
  data that means an outage (5.26 refuses the store, see above). Deploys
  are frozen from the merge to the end of the window, and both people with
  deploy access (Michael, Jonas) know about it.
- **Never let the app run on an empty new store:** between creating the
  new data directory and the verified load, only `neo4j` may run. No
  `./config.rb up -d` without a service name.
- **Development instances:** after the merge, an existing 4.4 dev database
  no longer starts. Run `src/scripts/pull-prod-data.rb --srsly --db-only`,
  which moves the old directory aside and loads into a fresh one. Run
  `./config.rb build neo4j` first, so `up -d neo4j` recreates the container
  with the new image.
- **Row order:** 5.x returns rows without `ORDER BY` (and ties) in a
  different order than 4.4 (seen in gyst-bib). Watch lists in the UI that
  have no explicit order.
- **Memory:** 5.26 starts with a smaller default page cache (512 MB) than
  4.4 effectively used here (about 2 GB RSS for an 810 MB store). Compare
  response times of the heavy pages in the rehearsal, and set
  `NEO4J_server_memory_pagecache_size` if needed.

## Phase A – before the switch, on 4.4 (normal deploys)

1. Deploy 550bb557 (`IS NOT NULL`). It works on both versions.
2. Optional: neo4j_bolt 0.5.1 (`Gemfile`, image build). Not needed for the
   dashboard data (no temporal values). It makes both projects use the same
   version, and its dump runs in one transaction.

## Phase B – rehearsal on a development machine with production data

1. Branch `neo4j-5-migration`: the full suite against 5.26 must be green (done, see above).
2. `./config.rb build neo4j`, then `pull-prod-data.rb --srsly --db-only`:
   that is the migration itself (dump from 4.4 production, load into a
   fresh 5.26).
3. **Verify the content**, not only the counts:
   - node counts per label and relationship counts per type
   - a content comparison of the source dump and a dump of the new
     database, independent of IDs: each node keyed by labels, properties
     and its neighbourhood, each relationship by type, properties and both
     endpoints
   - gyst-bib has `compare-dumps.rb` for this (about 6 s for 90k nodes);
     take it over
4. **Behaviour:**
   - Click through the main pages as several roles (student, teacher,
     admin, staff): start page, timetable, messages, polls, groups,
     directory, admin.
   - Check the `ruby` and `neo4j` logs for Cypher errors.
   - Optionally an API probe before/after (gyst-bib `api-probe.rb` /
     `compare-probes.rb`: the same read-only requests against the old and
     the new stack, compared ignoring row order and timestamps).
     Also ignore values counted relative to now (e.g. "last 7 days", a
     365-day window): in gyst-bib such a value changed between two probes
     minutes apart because one entry dropped out of the window.
   - Bring the stack up the way C7 does, **nginx included**, and load
     pages through nginx, not only through `ruby` directly (see C7).
5. **Measure the time** for the production steps C3–C6. Expected: dump
   about 30 s, cold backup about 1 min, load about 30 s, start and checks a
   few minutes. Planned downtime: 30 minutes including buffer.
6. **Rehearse the rollback** (C8), including "dump 5.26 → load into 4.4".

## Phase C – production window (only with the maintainer's go-ahead)

Choose the window: evening or holidays, not around 19:30 (cron), announced
to the school beforehand. During the window nginx shows the maintenance
page (`errors/wartung.html`, master 79980c65 – deployed beforehand, with the
one-time nginx rebuild): at the start write `<DATA_PATH>/gen/wartung.json`
with the planned end (`{"bis": "…", "text": "…"}`), delete it at the very
end (doc/Betrieb.md, "Wartungsseite").

1. **Before:**
   - free disk space (store about 1 GB, plus dump and backup)
   - `git fetch`, master = tested state
   - freeze deploys (Jonas informed)
   - pause the 19:30 cron entry if it falls into the window
2. **Stop the app, keep 4.4 running:** stop every service except `neo4j`
   and `nginx` (`ruby`, `timetable`, the bots, `mail_forwarder`). Check
   with `docker ps` that only `neo4j` and `nginx` are running.
3. **Dump** (no writers any more, so consistent): with the `ruby` image as
   a one-off container in the project network,
   `neo4j_bolt --host neo4j:7687 dump`, into a file outside the repo
   (`chmod 600`). Count nodes and relationships.
4. **Stop Neo4j cleanly and keep a cold backup:**
   - `docker stop -t 120 <neo4j container>`
   - `tar` of `DATA_PATH/neo4j`
   - `mv DATA_PATH/neo4j DATA_PATH/neo4j-4.4`, then create an empty
     `DATA_PATH/neo4j` (owner = UID of the services)
5. **Switch:**
   - merge `neo4j-5-migration` into master and pull on the server (check
     the commit hash)
   - `./config.rb build neo4j`, then `./config.rb up -d neo4j`
   - wait until `cypher-shell 'RETURN 1'` answers in the container
6. **Load and verify:**
   - load the dump with a one-off container
     (`./config.rb run --rm --no-deps -T --entrypoint 'neo4j_bolt --host
     neo4j:7687 load /dev/stdin' ruby`, dump on stdin)
   - counts per label/type must equal the dump
   - content comparison (B3)
   - only then go on
7. **Start everything:**
   - `./config.rb up -d`
   - then `./config.rb up -d --no-deps --force-recreate nginx`: nginx
     resolves `…_ruby_1` only once at startup (static `proxy_pass`, no
     `resolver`), so after `ruby` was recreated (new image) it can keep
     the old container address and answer 502. `--no-deps` leaves the
     running services alone. (gyst-bib, 2026-11-11: there nginx did not
     come back at all because of a legacy `links:` entry; the dashboard
     has no `links:`, but the stale address has the same cure.)
   - `/api/ping` 200, heartbeats without problems, no new errors in the
     `ruby` and `neo4j` logs
   - log in as several roles and check by hand
   - re-enable the cron entry, lift the deploy freeze
8. **Rollback**, if 6 or 7 fails:
   - stop all services
   - `mv DATA_PATH/neo4j DATA_PATH/neo4j-5.26-failed`,
     `mv DATA_PATH/neo4j-4.4 DATA_PATH/neo4j`
   - revert the merge on master and pull, `./config.rb build neo4j`,
     `./config.rb up -d`, recreate nginx as in 7, checks as in 7
   - If the problem only shows after go-live: don't roll back blindly,
     because data written since then would be lost. Dump 5.26 and load it
     into a fresh 4.4 store instead (rehearsed in B6).
9. **Afterwards:**
   - keep `DATA_PATH/neo4j-4.4` and the cold backup for a few weeks, then
     delete them
   - the server still has old leftovers (`neo4j-old`,
     `neo4j-checkpoint-quarantine`)
   - update the documentation (Installation, Development: dev instances
     need a reload)

## Open decisions (maintainer)

- Date and time of the window.
- neo4j_bolt 0.5.1 before the switch (A2): yes or no.
- A guard in `config.rb` (as in gyst-bib): refuse to start the app services
  while the new data directory has no "loaded" marker. With the steps above
  and fail-safe 5.26 it isn't strictly necessary, but it protects against
  an accidental `up -d` during the window.
