# Performance review gyst-dashboard

## Summary (with numbers)

- **Timetable update:** Most of the time is eaten up by two **JSON round trips per event** that aren't needed: `timetable.rb:1781` (SuS (students) only) and `timetable.rb:1880` (all users, both modes, past weeks too). In a microbenchmark they cost about 0.95 ms per SuS file combined. That is more than `to_json` (0.21 ms), SHA1 (0.04 ms) and the rest together. Extrapolated to ~86,000 SuS and ~10,000 LuL (teacher) files, that is **about 75–90 s out of 173 s (estimate)**. Both can be replaced in a way that keeps the output **byte-identical**. With further low-risk hoisting, **~60–80 s** per full update is realistic, with a shared computation of private/public **~40–60 s** (estimate).
- **Request path:** The main hog is the **template loop** (`main.rb:4061-4081`). It accesses a UTF-8 string character by character (`s[i]`), and every access is O(n). Measured with the real templates: timetable page 228 ms out of ~300 ms, profile 93 out of 157 ms, login 27 out of 35 ms. The same loop working byte-wise takes **10.9 ms** instead of 228 ms. 16 parallel requests for the timetable page take 4.7 s wall time, because they run one after the other due to the GVL.
- **Neo4j:** The unique constraints are on `key`, but the queries search by `{id: …}` (Event 22×, PollRun 38×, Group 8×, Poll 6×, Angebot 6×, WebsiteEvent 4×, Message 3×). `EXPLAIN` shows a **NodeByLabelScan** for these. There are no indexes on `updated` (incremental queries). Per update, ~48×3 queries run for the website events, 2/3 of them DELETE write transactions.
- **Frontend:** The JS bundle is **2.14 MB raw / 570 KB gzip**, the CSS 429 KB / 73 KB. Both are content-hashed, but only have `Cache-Control: max-age=60`. Every timetable page loads a hidden **450 KB PNG** (`porsche.png`), plus 135 KB of inline JS.
- **Startup (test):** The test stack takes 31 s until “Server is up”. **20 s of that hang on a blocking HTTP call to `image_bot`** (`main.rb:1877`, DNS error in the test). `parse_timetable` runs **twice** in `collect_data` (`main.rb:1044` and `1077`), and that on every full update too.

## Measurements (what you measured, how)

Everything ran against the test stack (port 8125, example data, production). I did not touch dev (8025), `data/`, `logs/` or the credentials.

| Measurement | Method | Result |
|---|---|---|
| Full update test | `docker logs schuldashboardtest_timetable_1` | 750 week files in ~1 s (update_weeks); with test data the per-week overhead dominates |
| File sizes `/gen/w` (test) | `zcat` over `.test-stack/data/gen/w` | gz avg 418 B, raw avg 3.5 KB, max 13 KB. Per event, all label variants, `lehrer_list:"#<Set: {…}>"` (Set#to_s garbage) and, for LuL, `schueler_for_lesson` are written along |
| Cost per file | Microbenchmark with `ruby -e` and synthetic, realistically sized events (20 SuS events or 25 LuL events with 25 SuS each) | SuS: `to_json` 0.21 ms, round trip+symbolize 0.53 ms, round trip 0.41 ms, SHA1 0.04 ms, gzip 0.08 ms. LuL: `to_json` 0.47 ms, round trip 1.16 ms, building `schueler_for_lesson` 0.20 ms |
| `user_has_role` | Microbenchmark | 450 ns per call (assert builds the message string interpolation on every call) |
| Pages (SuS login via `/api/login` and Mailpit code) | `curl -w %{time_total}` | `/` (timetable) 300 ms / 191 KB; `/profil` 157 ms; login page 35 ms; 16 parallel timetable requests: median 4.2 s, wall 4.7 s |
| Template loop in isolation | Real `_template.html` + page, `eval` replaced by a constant | Timetable 180 KB, 178 placeholders: **228 ms UTF-8 vs. 10.9 ms bytes**; profile 93 vs. 5.8 ms; login 27 vs. 2.3 ms |
| Assets | `curl -D -` | JS 570,432 B gzip (on the fly), CSS 72,966 B, both `max-age=60`; `/images/porsche.png` 449,662 B without Cache-Control; forkawesome woff2 91 KB |
| Indexes | `cypher-shell SHOW INDEXES` / `EXPLAIN` in the test Neo4j | see Database |
| Startup | `docker logs -t` | Start 00:53:52 → SSO key 58.9 (7 s gems/load) → collect_data ~1 s → setup 3.5 s → **image_bot error after 20 s** → up 00:54:23 |

I did not measure the additional cost in dev mode (page timings), that part is code analysis.

## Timetable update: optimisations

Basis: 173 s / ~107k files ≈ 1.6 ms per file. This matches my benchmark model (SuS ~1.3 ms, LuL ~2.5 ms).

| # | Measure | Expected gain (estimate) | Risk | Output identical? |
|---|---|---|---|---|
| 1 | **Jitsi count without round trip** (`timetable.rb:1877-1908`): skip entirely for `mode == :public` (there is neither `data` nor `is_event` there). Skip weeks with `p1 < today`. Hoist `Date.today.strftime`. Access symbol and string keys directly (`h.key?(k) ? h[k] : h[k.to_s]`, needed because SuS `data` has string keys) | 30–50 s | low | yes (same iteration order → same `jitsi_projection.json`, only read by `stats.html`) |
| 2 | **Replace `JSON.parse(_event.to_json)` for SuS** (`1778-1801`). The homework injection never hits: `event[:lesson_key]` is nil after the parse, see TODO 1779. Replacement: `e = _event.dup; e[:data] = e[:data].transform_keys(&:to_s) if e[:data].is_a?(Hash)` | 30–45 s | low–medium | yes, **if** the `data` keys become strings. Otherwise the SuS iCal would suddenly get lesson topic/homework, because `1934ff` reads `data[:sym]` and finds nothing today |
| 3 | **Compute private and public once** (`1310`): build lesson_keys, cache_indices, fixed_events, filters once, then serialise twice. For public, remove `is_event` events and `:data/:per_user` on copies (today `1814-1817` mutates via `delete`) | 15–25 s | medium | yes (exception: `hide_from_sus` with `.sample` in 1842ff is random anyway) |
| 4 | **Precompute lesson_keys once per user** instead of per week×mode (`1323-1340`, including `Set.new(@@lessons[:lesson_keys].keys)` for Praktikum (internship)). Move the `only_these_lesson_keys` filter forward | 1–3 s full; for partial updates most of the fixed-cost share | low | yes |
| 5 | **`Main.get_website_events` before the week loop** (`1264`, `include/website.rb:11-28`). Once per update instead of 3 queries × ~48 weeks (96 DELETE write tx) | 1–3 s, also on every partial update | low | yes |
| 6 | **Cache roles per user** (`is_teacher`, `is_schueler`). Around 125 `user_has_role` calls per SuS file (1442-1463, 1577, 1588, 1611, 1711) | ~5–6 s | low | yes |
| 7 | **Build `schueler_for_lesson` once per lesson_key** (`1612-1621`) | 2–4 s | low | yes |
| 8 | salzh block (`1632-1660`): `Set.new(@@current_salzh_status_by_email.keys)` per update instead of per event; skip if empty | small to medium (depending on data) | low | yes |
| 9 | Drop `.dup` on label/folder strings (`1442-1463`) | <1 s | low | yes |
| 10 | `GzOutput.stored_sha1`: in-memory cache path→sha1 instead of 107k `GzipReader.open` (`gz_output.rb:44`); plus `mkpath` only once per directory | 1–2 s | low | yes |
| 11 | `parse_timetable` only once in `collect_data` (`main.rb:1044` and `1077`). Is called on every full update via `timetable.rb:332` and reads all `/vplan/*.json` | 1–5 s (unknown, please measure) | low–medium | yes, if `parse_timetable` is deterministic |
| 12 | Slim down the payload: `lehrer_list/klassen_list/raum_list` (Set#to_s, `timetable.rb:691`), unused label variants, `cache_index` | 10–20 % of to_json/SHA1, plus network and browser | medium (check frontend) | **no** |
| 13 | JSON fragment cache per (cache_index, variant) | 10–20 s | high | yes, if done cleanly |
| 14 | Parallelise (fork per week range; merge `jitsi`/`ical`) | factor ≈ cores | high | only if the “Caution” point below is solved |

**Caution, hidden behaviour (important for any change):** `timetable.rb:1750-1757` deletes `:notizen` and `:booked_tablet*` from `event[:data]`. This object, however, is **the shared `events_with_data_cache[lesson_key][offset]`** (`1605`, only shallow-duplicated in `1439`). LuL files only contain notes because in `@@user_info` the teachers come before the SuS (`main.rb:153` vs. `236`). Class views (`_5a`) come after that and therefore never have notes. Whoever changes the order or parallelises changes the output. If this is handled explicitly (copy-on-write), the class views get notes, and that is a domain decision.

Further side findings:
- Because of the string keys, the SuS iCal never contains the lesson topic or homework.
- The worker queue (`timetable-repl.rb:52-74`) processes each key individually. Several waiting keys should be combined into one `update(Set[...])`. A full update (every Vplan change, `vplan-watcher.rb:342`) blocks all partial updates for ~3 min.

## Request path

**before filter (`main.rb:1977-2169`), production:**
- Session lookup (`2029-2034`) and device token (`2008-2012`) are **write queries on every request** (`SET last_access`). Better: only write when `last_access` has changed (in-process cache email→date), otherwise a pure read. Measured, an API request with a session costs ~7 ms.
- `refresh_bib_data` (`1723-1750`) runs hourly **synchronously in the request thread**, with two `Curl.get` without a timeout. Before that, the hashes are set to `{}`, so other threads see empty library data during the fetch or for an hour after an error. Better: background thread, timeout, atomic swap.
- `dashboard_sso` (`590-610`, `2165`) is uncritical. The JWT is only decoded unverified per request (µs), ES256 only signs when less than 15 min of validity remain.
- Dev mode only: `compile_js/css` on every non-API request (`1993-1996`) with `rm_rf` and rewriting 2.6 MB (`1787-1791`, `1811-1815`), plus `load` of 8 config files. This explains part of the dev timings. Better: only write when the SHA has changed.

**Page route (`3570-4129`):**
- **The main cost is the template loop `4061-4081`.** `s.index`, `s.size` and `s[index+length]` work with character indexes on a UTF-8 string with umlauts, every access is O(n). In addition, for each placeholder the search starts from the beginning and replaces in place in the 180 KB string. Measured, this is ~75 % of the page time. Solution: work byte-wise (`byteindex`/`getbyte`/`byteslice`, output into a new buffer) or compile the template into a Ruby method once at startup (also saves the ~180 `eval` compiles). **Caution:** `_template.html:151` relies on eval output being re-scanned (`'/gen/bg/bg-#{color_scheme}.jpg'` in single quotes). Expectation: timetable page ~300 → ~70–80 ms (estimate). `/mailing_lists` (1.5 s) probably suffers from the same loop with large content (not measured, no LuL login possible in the test).
- `@template ||= {}` (`4045`) is an instance variable and is therefore re-read **per request**; page and CSS too (`4029`, `4053`). Small effect, but they belong in a class variable.
- Per page, `purge_missing_sessions` (1 query per SID, `include/login.rb:483`), `get_unread_messages` and, for SuS, the LessonNote query `3786-3790` (scan without index, see below) run. On the timetable page `print_timetable_chooser` is called three times.
- `/schema` (`3726-3730`) starts `neo4j_bolt visualize | dot` per call (19 s). Better: cache the SVG and regenerate it only on a button press or in the background.

## Database

- **Constraint on the wrong property:** `CONSTRAINTS_LIST` (`main.rb:316-353`) has `Event/key`, `Poll/key`, `PollRun/key`, `Group/key`, `Message/key`, `WebsiteEvent/key`, `Angebot/key`, `TextComment/key`, `AudioComment/key`. But lookups use `{id:}` (`{key:}` occurs 0×). `EXPLAIN MATCH (pr:PollRun {id:'x'})` → `NodeByLabelScan`, likewise for Event. Solution: add `…/id` constraints. Check for duplicates first, otherwise `CREATE CONSTRAINT` fails.
- **No indexes on `updated`** for the incremental queries in `Timetable#update`: `LessonInfo.updated` (2×, `timetable.rb:2427`, `2439`), `TextComment`, `AudioComment`, `Message` (with `OR rt.updated`, hard to index), `Test`, `Event`, `LessonNote` (there additionally on every SuS page view). So every partial update runs several full scans. The gain grows with the DB size (estimate: 0.5–3 s per partial update).
- **N+1 / loop queries:**
  - `get_website_events` per week, with DELETE in a read path
  - `get_homework_feedback_for_lesson_key` per lesson_key (`timetable.rb:1578`), better one query for all keys
  - startup MERGE per user (`main.rb:419-425`, ~1000 round trips), better `UNWIND $emails`; the same for tablets and PredefinedExternalUser
  - `purge_missing_sessions` per SID
- The write load per request (`SET last_access`) also belongs here (see above).

## Frontend

- **Bundle:** 2.14 MB raw / 570 KB gzip, nginx recompresses on every delivery (level 6). The largest parts in KB, raw/gzip:
  - `moment-with-locales` 369/75: only `de` needed, saves ~300 KB raw
  - `zxing` 292/87: only for the library scanner, load lazily
  - jQuery UI 255/68, FullCalendar 246/68, Chart.js 173/53, Summernote 151/37, Flowbite 124/24, JSZip 99/28, turn.js 34
  - Loading page-specifically saves roughly 50 % of the gzip volume (estimate).
- **Caching:** `/gen/js/compiled-<sha>.js` and `/gen/css/…` only have `max-age=60` (`config.rb:56`, `106`). For content-hashed files, `max-age=31536000, immutable` belongs in a separate `location`, plus `gzip_static` with precompressed files. Static files under `/` (tailwind.css, fonts, PNGs) have no Cache-Control at all and rely on heuristic caching.
- **Timetable page:** HTML 191 KB / 37.5 KB gzip, 135 KB of which is inline script (transferred and parsed on every navigation; also makes the template loop more expensive). Further requests:
  - bundle JS/CSS, `tailwind.css`, `new_design.css`, `dark.css`, `brand.png`, background SVG, fonts
  - week (`/gen/w/<id>/<yw>.json.gz` as octet-stream + pako, `timetable.html:815`; for LuL with a `?Date.now()` cache buster), `homework.json.gz`, `recipients.json.gz`
  - **`porsche.png` (450 KB) in a hidden div** (`timetable.html:113`): `display:none` does not prevent the download. Fix: only set `src` in `porsche()`.

## Startup time

Measured in the test, with hardly any data: 31 s until “Server is up”.
- **20 s hang on the `image_bot` call** (`main.rb:1876-1881`, `Net::HTTP` with default timeouts of 60 s), synchronously in `configure`. In production probably fast as long as image_bot is running; if not, it blocks. Fix: in a thread with a short timeout.
- `refresh_bib_data` at startup (`1883`): Curl without timeout.
- ~7 s for gem load and `wait_for_neo4j` before `collect_data`. Many gems are loaded wholesale (`pry`, prawn, write_xlsx, nokogiri, zip …); some of them could be loaded lazily (estimate 1–3 s).
- `collect_data`: `parse_timetable` runs **twice** (`main.rb:1044`, `1077`) and reads all `/vplan/*.json`. With real data probably the largest parser block. Drop the second call, provided the function is deterministic.
- `setup` (`390-527`): ~70 idempotent `CREATE … IF NOT EXISTS` (~1–2 s) and ~1000 individual MERGEs, better as `UNWIND`. After that, the startup renders backgrounds for all used colour schemes synchronously, only if they are missing. I did not examine `determine_lehrmittelverein_state_for_all`.
- Recommendation: add debug timestamps per phase (collect_data sub-steps, setup, render, compile), then optimise in a targeted way. I can't provide numbers for real data; I estimate 30–40 s → 15–20 s after the fixes mentioned above.
- In addition: the timetable service does a full update on every start (`timetable-repl.rb:50`), ~173 s during which partial updates wait.

All file paths refer to `src/ruby/` or `…/src/static/`. In particular: `src/ruby/timetable.rb`, `src/ruby/main.rb`, `src/ruby/gz_output.rb`, `src/ruby/include/website.rb`, `src/ruby/include/poll.rb`, `src/ruby/include/login.rb`, `src/ruby/timetable-repl.rb`, `src/static/_template.html`, `src/static/timetable.html`, `config.rb`.
