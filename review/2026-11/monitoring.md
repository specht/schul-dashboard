# Monitoring review gyst-dashboard

## Summary

Today a problem is almost only noticed when someone reports it („Stundenplan ist leer“ (timetable is empty), „Mail kam nicht an“ (mail didn't arrive)). There is **no health check except `/api/ping`**, no “last successful run” markers, no status page and no alerting. The only exception: if a distribution list mail fails, the maintainer gets a copy (cc). Several failures stay **silent**: the mail forwarder's sending thread can die without the process ending. The mail bot can get stuck forever on a single faulty mail. The worker thread of the invitation bot and of the statistics bot can die, and jobs then only end up in the queue. The vplan-watcher writes its timestamp even on partial failures.

For a school, something small is enough:
1. Every service writes heartbeat files to `/internal/status/`.
2. An `/api/health` per service.
3. An admin status page.
4. A watchdog that alerts via `deliver_mail` on a state change.
5. An external uptime check as a dead man's switch.
6. One log line per request with duration, status and role.

Docker health checks are added as an optional setting in `config.rb`.

**Documentation correction needed:** `doc/Betrieb.md` says “Every line of the Ruby services starts with date and time”. But that only holds for `debug`/`debug_error`. Many places write directly with `STDERR.puts` and have neither a timestamp nor `[ERROR]`: vplan-watcher, mail-forwarder, all bots, the `rescue` branches in `timetable.rb` (lines ~2331–2347) and `trigger_update` and relatives in `main.rb:2306–2340`. The recommended `grep` therefore doesn't find e.g. errors from the timetable update.

## What is detectable today – and what isn't

| Failure type | How noticed? | Gap |
|---|---|---|
| `ruby` down/restart | nginx shows `neustart.html`, which polls `/api/ping`; upstream proxy | No alert. `/api/ping` only checks “main.rb loaded”, not Neo4j. If `ruby` is permanently in a restart loop, you only see the restart page. |
| Whole server/nginx down | users report it | No external check. |
| Bot container crashes (`restart: always`) | `./config.rb ps` (restart counter), Docker log | Nobody looks; no health check. |
| Timetable not updated for hours | log line `<<< Finished updating … in X s` (`timetable-repl.rb:31`) | No marker for the last success. Errors from `update_timetables` end up as a bare `STDERR.puts e` without timestamp and backtrace. A dead worker thread goes unnoticed. |
| Vertretungsplan (substitution plan) out of date | `/vplan/timestamp.txt`; the monitor shows `vplan_timestamp` (`timetable.rb:229`) | You can't distinguish: Untis hasn't published anything new, or the watcher is broken. There is no “last checked”. `loop do` (`vplan-watcher.rb:345`) has no `rescue`, every HTTP error crashes the process. Missing individual pages only lead to a `WARNING` (`:267`), after which the timestamp is written anyway (`:340`): the partial plan then counts as current. |
| Mail queue (lesson mails) stuck | teachers see „nicht gesendet“ (not sent) (`ts_sent` nil) | Only triggered via `send-pending-emails.rb`, i.e. via a host cron that is not documented. If the cron goes away, the mails pile up silently. `Thread.abort_on_exception = true` plus a mail that e.g. belongs to a deleted student (`@@user_info[sus_email]` is nil) leads to crash, restart, crash on the next run: this one mail blocks all of them. |
| Distribution list forwarder fails | A single mail fails: mail to the sender with cc to the maintainer, plus `recipients.yaml.failed` | If SMTP is completely gone, the notification mail (`mail-forwarder.rb:290`) fails too and t2 dies. t1 keeps running, `t1.join` blocks, so the process stays alive: **mails are accepted and deleted from the mailbox, but never sent.** IMAP errors end t1, the `join` raises and the process restarts (only visible in the Docker log). |
| Invitation or statistics bot | – | `perform_update` without `rescue` and without `abort_on_exception`: the worker dies silently, `/api/send_invites` only fills the queue. |
| Disk full | – | No check. Docker log rotation is optional, rotation of the nginx logs only by documentation. Neo4j store, `/raw` and `/mails` grow without limit (`.archived` is never deleted). |
| Neo4j slow | users notice it | No timing of the queries. Community 4.4 has no `query.log`, heap and page cache are not configured. GC pauses are only in `LOGS_PATH/neo4j/debug.log`. |
| Certificate | browser warning | Handled by the external proxy (acme-companion); no expiry check. |
| Backups | – | Not automated yet (TODO). No evidence of “last dump OK”. |
| Slow requests/500s | Sinatra's `dump_errors` (`- class - message`); nginx `$request_time` | No status and no duration in the Ruby log, no request ID, no aggregation. Expected errors (wrong code, `assert` on pages, 153 cases according to the smoke test) also come as 500 and make real errors invisible. |

## Suggestions, prioritised

**1. Heartbeat files “last success/last error”** – benefit high, effort S, risk low.
A small helper, e.g. `include/status.rb`, without a dependency on `main.rb`, so that `vplan-watcher.rb` can load it too. Signature roughly `Status.ok!(name, extra)` and `Status.error!(name, e)`. It writes atomically (`.tmp` + `rename`, as already done for `neustart-looks.json`) to `/internal/status/<dienst>.json`, with fields like `{ok_at, error_at, error_class, duration_s, files, queue}`. The directory is `/internal` and **not** `/gen`, because nginx serves `/gen` publicly. `/internal` is mounted writable in all Ruby services. Call sites:
- `TimetableRepl.perform_update`
- `perform_refresh`: additionally `checked_at` on every pass, even without a change, so that “checked” and “new” can be distinguished
- `MailBotRepl.perform_update`
- both forwarder threads, one file each
- `InvitationRepl` and `StatsBotRepl`
- the backup script on the host: writes `INTERNAL_PATH/status/backup.json` with size and node count

**2. Prevent silent deaths** – benefit high, effort S, risk low, but tests first.
- `vplan-watcher.rb`: `rescue StandardError` in the loop, then `Status.error!`. Treat missing pages as errors and then **don't** write the timestamp.
- `mail-forwarder.rb`: The thread body gets `begin/rescue`, and the notification mail its own `rescue`. Alternatively `Thread.abort_on_exception = true`, so that Docker restarts it.
- `mail-bot-repl.rb`: Catch and log errors per mail, mark the mail (`m.error`) and skip it, instead of ending the whole process.
- Invitation and stats bot: `rescue` in the worker.
- `trigger_*` in `main.rb`: set `open_timeout`/`read_timeout` short and use `debug_error` instead of `STDERR.puts e`.

**3. `/api/health` per service** – benefit high, effort S–M, risk low.
- **ruby**: in `config.ru` next to `/api/ping`, i.e. without the before filter. Checks:
  - Neo4j `RETURN 1` with measured latency and timeout
  - free space under `/gen`, `/raw`, `/internal` (`df -P` as array `system`/`IO.popen`)
  - the age of the heartbeat files

  Publicly only `200 ok` or `503 degraded` without details. Details only on the admin page. `/api/ping` stays unchanged for `neustart.html`.
- **Bots on 8080**: `get '/api/health'` with `worker_alive` (`@@worker_thread.alive?`), `@@queue.size`, `future_queue.size` and the last success. 503 if the worker is dead.
- **vplan_watcher and mail_forwarder** have no HTTP server. For them the age of the heartbeat file is enough.

**4. Admin status page** – benefit high, effort M, risk low.
New page `src/static/status.html` with `#{this_is_a_page_for_logged_in_admins}` as the first line, plus `.api_messages` and `POST /api/admin_status`. It shows a traffic light per service, with these columns:
- age of the last success, last error (class, time)
- queue lengths: `Mail` with `ts_sent IS NULL AND ts < now-15min`; number of `/mails/*/recipients.yaml`, `*.failed`
- age of the Vplan check and of the Vplan content
- Neo4j latency
- disk space
- certificate, days until expiry: Ruby `OpenSSL::SSL::SSLSocket` to `WEBSITE_HOST:443`. If hairpin NAT prevents this, via the external check.
- age of the backup
- top errors of the last 24 h (see Logging)

No personal data, only numbers. An E2E test with the admin role belongs with it.

**5. Watchdog with mail alert** – benefit high, effort M, risk medium (alert spam).
A thread in **one** service, e.g. `stats_bot`, or optionally a separate `watchdog` service. Every 5 min it evaluates the same checks as the status page (shared code). Thresholds take school hours into account, e.g. Vplan older than 60 min only Mon–Fri 6 am–4 pm. Mail is only sent on a **state change** ok→fail and fail→ok, plus a reminder every 24 h; the state lives in `/internal/status/alerts.json`. Sent via `deliver_mail` to `WEBSITE_MAINTAINER_EMAIL`. **Dev guard:** The mail only goes to the positive list, but on the dev instance almost all checks would be red (no Untis, no forwarder), and the maintainer would get spam. So only arm it with `ENABLE_ALERTS = true` in `env.rb`, off by default; in DEVELOPMENT only log. If the alert itself fails (SMTP down), only `debug_error`.

**6. External dead man's switch** – benefit high, effort S, risk low.
An external service (self-hosted healthchecks.io/Uptime Kuma, e.g. on another school server) checks `https://…/api/health` every 5 min. Only it detects “server, proxy or SMTP completely gone”. Optionally the watchdog additionally pings a heartbeat URL there. This also covers the watchdog itself being dead.

**7. Docker health checks in `config.rb`** – benefit medium, effort S, risk low.
`ENABLE_HEALTHCHECKS` as an optional setting. Without it nothing is set, the generated files stay byte-identical. **Important:** The health check must be set *after* the services are cloned via `YAML.load(…to_yaml)`, i.e. in the block before `File::open(COMPOSE_FILE_PATH…)`. Otherwise all bots inherit the check from `ruby` with port 3000. Sketch:

```ruby
if defined?(ENABLE_HEALTHCHECKS) && ENABLE_HEALTHCHECKS
    hc = lambda { |cmd, start| { :test => ['CMD-SHELL', cmd], :interval => '60s',
        :timeout => '10s', :retries => 3, :start_period => start } }
    s = docker_compose[:services]
    s[:ruby][:healthcheck] = hc.call('curl -fsS http://localhost:3000/api/ping', '10m')
    [:timetable, :mail_bot, :stats_bot, :invitation_bot, :image_bot].each do |k|
        s[k][:healthcheck] = hc.call('curl -fsS http://localhost:8080/api/health', '15m') if s[k]
    end
    s[:vplan_watcher][:healthcheck] = hc.call('find /internal/status/vplan_watcher.json -mmin -10 | grep -q .', '5m')
    # mail_forwarder analog; neo4j: cypher-shell 'RETURN 1'
end
```

`curl` is in the Ruby image. Choose `start_period` generously, because `collect_data` and the full timetable update take minutes with real data. Note for the docs: `restart: always` does **not** restart *unhealthy* containers. The health check serves visibility (`./config.rb ps`) and the watchdog. Don't build in autoheal, that risks restart loops during the long startup. After the change, check both variants (dev and production) by diff.

**8. Neo4j and disk** – effort S.
- Set heap and page cache as an optional setting.
- Check `debug.log` for `stop-the-world pause`, e.g. with `grep`.
- Delete old `/mails/*/*.archived` and `mail` after N days; that is also a data protection matter.

## Logging: concrete improvements

1. **One line per request instead of at the start.** Instead of `debug "[nc_login|email] GET /path"` (`main.rb:2168`, i.e. before status and duration are known), a Rack middleware in `config.ru` before `map '/'`, or `after '*'`: Sinatra's after filters also run after exceptions, with status 500. A format that fits the existing `grep`:
   `2026-11-09 08:15:02 [req] id=3f9a2c role=lehrer POST /api/send_email 200 87ms db=4/31ms`
   - `role` (`lehrer`/`sus`/`eltern`/`admin`/`tablet`/`monitor`/`anon`) instead of email or nc_login; for correlation at most a short HMAC of the user ID.
   - Route pattern from `env['sinatra.route']` instead of the path with IDs (groupable, without tokens or tags).
   - `db=` counts queries and their total time via a `prepend` on `Neo4jBolt#neo4j_query`. Log queries over 500 ms separately, with the first line of the query, **without** parameters.
2. **Request ID**: pass nginx `$request_id` through via `proxy_set_header X-Request-Id` and include it in the `log_format`, together with `$upstream_response_time`. This deliberately changes the generated nginx configuration; `build nginx` afterwards. Without the header, the middleware generates an ID itself. Show the ID in the 500 response, then users can report it.
3. **All `STDERR.puts` to `debug`/`debug_error`** in bots, forwarder and the `rescue` branches of `timetable.rb`; errors always with class and shortened backtrace. For `vplan-watcher.rb`, which doesn't load `main.rb`, move `debug` out into a small `include/log.rb`.
4. **Error aggregation without Sentry**: The fingerprint is the exception class plus the first `/app/` backtrace line. Counters with first_seen, last_seen and an example route go to `/internal/status/errors.json`, the top list onto the status page. The watchdog mails once per *new* fingerprint. Prerequisite: expected errors (wrong code, access `assert` on pages) return 4xx, as planned in the TODO. Otherwise the list is noise.
5. **Metrics** in the status JSON, no Prometheus:
   - p50/p95 and count per route pattern, last hour
   - number of 5xx
   - duration and file count of the timetable update, full and incremental (already in the log line)
   - queue lengths of the bots
   - pending lesson mails, forwarder pending/failed
   - age of the Vplan check and content
   - Neo4j ping
   - disk space
   - `@@ws_clients.size`
6. **Data protection in logs** (important): These places currently write content about students into the Docker log:
   - `include/email.rb:12` (`debug data.to_yaml` with email, reason and free text)
   - `mail-bot-repl.rb:65` (teacher, student email, reason **and details** such as disruptive behaviour)
   - `mail-forwarder.rb:248` (every recipient address individually)

   Replace with tag, reason code and count. With the new request line, email addresses also disappear from every request log.

## Can go / simplify

- **Ping threads** in `image-bot-repl.rb` and `audio-bot-repl.rb`: `future_queue` is never filled. The ping branch would call `perform_update(which)` with the wrong arity, and `DELAYED_UPDATE_TIME` is undefined there. Dead code.
- `PING_TIME` in `mail-bot-repl.rb`: is not used. In `timetable-repl.rb`, `PING_TIME = DEVELOPMENT ? 1 : 1` and `DELAYED_UPDATE_TIME = … 0 : 0`; simplify.
- `audio-bot-repl.rb`/`.ru`: no service in `config.rb`, and the file only lists paths. Remove or version it (already in the TODO).
- Duplicate `docker_compose[:services][:ruby][:user] = …` in `config.rb`. Caution: removing it doesn't change the order of the YAML keys, still check by diff.
- `STDERR.puts "mail_path: …"` and `'-' * 59` separator lines in bots and forwarder: pure noise.
- `Main.log_freiwillig_salzh_sus_for_today` in the full timetable update: a Corona leftover (see TODO on `salzh`).
- Long term: Don't trigger the mail bot via host cron, but with its own timer thread as in `TimetableRepl`. Then there is one fewer undocumented dependency. Until then, document the cron in `doc/Betrieb.md`.

Relevant files:
- config.rb
- doc/Betrieb.md
- src/ruby/config.ru
- src/ruby/main.rb (165–205, 1977–2168, 2251–2340)
- src/ruby/timetable-repl.rb
- src/ruby/timetable.rb (229, 2326–2350)
- src/ruby/vplan-watcher.rb
- src/ruby/mail-forwarder.rb
- src/ruby/mail-bot-repl.rb
- src/ruby/invitation-repl.rb
- src/ruby/stats-bot-repl.rb
- src/ruby/image-bot-repl.rb
- src/ruby/include/email.rb
- src/scripts/send-pending-emails.rb
