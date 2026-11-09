# Functionality review gyst-dashboard

## Summary

Most bugs arise in four places. First, the bots keep state in memory and only re-read incrementally. As a result, besides the ghost appointments that have been fixed, there are also ghost messages and ghost class tests. Second, the bot worker threads don't catch errors: they die silently or crash again on every faulty message (poison message). Third, comments identify lessons via an offset that is not carried along when lessons are deleted or inserted. Fourth, the mail forwarder has no error handling for individual recipients, no retries and no timeouts. Part of the reported dropouts can very probably be explained by SMTP rate limits plus a sending thread that dies in the process. I reproduced two bugs locally: that mails from external senders arrive as raw MIME text, and the A/B week across the 2026/27 year change. Everything marked “(assumption)” is derived from the code and not reproduced.

## Bugs (by severity)

### High

**1. Mail forwarder: mails from external senders arrive as MIME mush, attachments get lost**
- *Symptom:* Recipients see text with `----==_mimepart…` boundaries and Base64 blocks, HTML and attachments are missing.
- *Cause:* `mail-forwarder.rb:258-264` builds `Mail.new { body mail.body.to_s }`. For multipart mails this is the raw MIME body, but without `Content-Type: multipart/...`. Reproduced locally with the mail gem: the result is `text/plain` with all parts as text.
- *Repro:* Send an HTML mail with an attachment from an address in `mail-forwarder-emails.txt` to a distribution list.
- *Fix:* Clone the original mail and only change From/Reply-To/To, instead of copying the body. Alternatively attach it as `message/rfc822`.
- *Test:* Unit test with a multipart fixture: the forwarded part stays multipart, the number of attachments matches.

**2. Mail forwarder: a single sending error aborts delivery to all remaining recipients**
- *Symptom:* Part of a distribution list doesn't get the mail. The sender gets a mail „Weiterleitung fehlgeschlagen“ (forwarding failed) with the list of all still pending addresses.
- *Cause:* `mail-forwarder.rb:269-300`. Every exception, even a 550 for a single address or a temporary 4xx error, renames `recipients.yaml` to `.failed` and aborts. There is no automatic retry.
- *Fix:* Distinguish per recipient: log and skip permanent errors. Leave temporary errors (4xx, timeout) in the list and retry later with backoff.
- *Test:* SMTP mock rejects one address: all others are delivered.

**3. Mail forwarder: mails get lost silently if it crashes after the mail is on disk**
- *Cause:* `mail-forwarder.rb:117-121` first writes `/mails/<id>/mail`. Only after that do `allowed_senders()` (Neo4j query, `@@schueler_for_klasse['11'].each` at `:87`) and the writing of `recipients.yaml` run. If something crashes in between (e.g. Neo4j unreachable), the new process sees `File.exist?(mail_path)`, skips the mail and deletes it from the INBOX (`:207`).
- Similarly: without a Message-ID, mails end up under `/mails/mail`. All later mails without an ID are then considered duplicates. In addition, the glob in `:225` doesn't find the path `/mails/recipients.yaml`, so such mails are never sent. Message-IDs containing `/` create subdirectories that the glob also misses (assumption).
- *Fix:* Write `recipients.yaml` first via a temp file, then rename. Only after that does the file `mail` serve as the “done” marker. Hash the Message-ID (SHA1) instead of using it directly as a path. If the ID is missing, use the hash of the content.
- *Test:* Force an error in `allowed_senders`, restart: the mail is delivered anyway.

**4. Mail forwarder: distribution list in BCC is bounced as „Keine Empfänger“ (no recipients)**
- *Cause:* `mail-forwarder.rb:136` only evaluates the To/Cc/Bcc header lines. The sending server removes the Bcc line. The recipient from the envelope (`Delivered-To`/`X-Original-To`) is not read.
- *Fix:* Also evaluate `Delivered-To`, `X-Original-To` and `Envelope-To`.
- *Test:* Fixture without the distribution list in To/Cc, but with `Delivered-To`.

**5. Messages: removed recipients still see the message (ghost message)**
- *Cause:* `include/message.rb:54-60` deletes the `TO` edges when editing (`DELETE r`). `timetable.rb:2558-2589` only reads existing edges, so `@messages_for_user[entfernt][mid]` stays. A later deletion of the message doesn't reach this person either, because they no longer have an edge. This lasts until the timetable service restarts. The file `/gen/m/…` remains retrievable.
- *Fix:* As with the events, keep a placement map `mid → Set[email]` and remove the old placements on every hit. Or, instead of `DELETE`, mark the edge with `rt.deleted=true, rt.updated=$ts`.
- *Test:* E2E: send a message to A and B, remove B, log in as B: message not visible.

**6. Deleting or inserting lessons: comments and notes shift, queued parent mails disappear**
- *Cause:* `include/lesson.rb:280-318` only shifts `LessonInfo.offset`. `TextComment` and `AudioComment` carry the offset as their own property (`comment.rb:66,95`) and afterwards hang on the wrong lesson. `DETACH DELETE` of a `LessonInfo` detaches `Mail-[:REGARDING]`. The mail bot then no longer finds the mail (`mail-bot-repl.rb:34`): it isn't sent, and it can no longer be cancelled either. `@lesson_notes_for_lesson_key` is sorted by offset and is not reloaded (`timetable.rb:2684`).
- *Fix:* Shift comments as well (same query on `c.offset`, setting `updated` in the process). Cancel or reattach unsent mails before deleting.
- *Test:* Comment on lesson 3, delete lesson 2: the comment is at the new lesson 2.

**7. Race with `updated >= ts`: changes never appear until a restart**
- *Cause:* Request threads set `timestamp = Time.now.to_i` before a multi-part transaction (e.g. `lesson.rb:14-60`). If another transaction with T+1 commits earlier and the timetable service runs in between, `@lesson_info_last_timestamp` is at T+1 (`timetable.rb:2449`). The later commit with T is never read. The same applies to comments, messages, tests, events and notes (assumption, plausible under load on Monday morning).
- *Fix:* Query with overlap (`>= last_ts - 120`, the processing is idempotent). Or use a counter on the DB side.
- *Test:* Unit test with two rows in reverse commit order.

### Medium

**8. Changing the class of a class test: the date stays in the old class.** `tests.rb:107-126` only triggers the update for the new class, and `timetable.rb:2624-2630` never deletes from `@public_test_entries_for_klasse[alte_klasse]`. *Fix:* read the old class beforehand, trigger both and keep placements per test ID. *Test:* E2E: change the class, then check as SuS (students) of the old class.

**9. A/B weeks swapped after the 2026/27 year change** (if `SWITCH_WEEKS` is active in production). `directory.rb:523` takes the difference of ISO week numbers. 2026 has 53 ISO weeks. Simulated: 28.12. “A”, 04.01.2027 “A”, permanently swapped after that. Affects `tests.rb:23` and `timetable.rb:1876`. *Fix:* `((d - montag(d_info)).to_i / 7)`. *Test:* Unit test across 2026-12 to 2027-01.

**10. Mail bot (parent mails from lessons) only sends when triggered externally and can get stuck.** `PING_TIME` is never used. `perform_update` only runs via `/api/send_pending_mails`, called by `src/scripts/send-pending-emails.rb`. A cron job for this is not documented anywhere (assumption: without cron no mails go out). With `Thread.abort_on_exception = true` (`:16`), every exception ends the process, for instance `@@user_info[sus_email]` = nil for SuS who have left (`:53`) or `@@klassenleiter[klasse]` = nil (`:59`). After that, every further run crashes again on the same mail, and all other mails stay pending. *Fix:* Ping thread in the bot, catch errors per mail and mark the mail as failed.

**11. Invitation bot: endless loop of crash and restart on faulty entries (assumption).** `event.rb:179-185`: With `temp = ….first`, nil leads to a NoMethodError. If the organiser has left the school, `@@user_info[...]` is nil. This happens before `invitation_requested` is removed. `invitation-repl.rb:78` calls `perform_update(:all)` in `configure`, so the bot crashes again right at startup. There is no `rescue` in the worker thread, the thread dies silently. *Fix:* `rescue` per invitation, remove the request flag first.

**12. Monitor and Vertretungsplan (substitution plan): „Stand“ (as of) 1–2 hours too early.** `vplan-watcher.rb:298` formats `Last-Modified` in GMT. `timetable.rb:234` appends the local offset. *Fix:* `.new_offset(DateTime.now.offset)` before formatting.

**13. Vertretungsplan:** Days that disappear from the Untis export keep their old `/vplan/<datum>.json` (`:222` only writes days from `datum_list`, assumption). Every change puts an `update/all` into the queue (`:342`). The FIFO queue in the timetable service does not deduplicate. If Untis changes more often than a full update takes, teacher actions wait behind several full runs. If the format changes (`raise 'unexpected table'`, `assert` on headings), the watcher crashes again on every run.

### Low
- `timetable-repl.rb:93-96`: `"<key>/wait"` becomes two queue entries, including `"wait"` as a key of its own. Consequence: unnecessary runs.
- `timetable.rb:2571`: `fetched_message_count = rows.size` takes the wrong variable (the log shows audio comments).
- `timetable.rb:2672-2676`: `@events_last_timestamp` only advances if the event has participants. Events without participants are reloaded on every update.
- `stats-bot-repl.rb:271`: no `rescue`, the worker dies silently, but HTTP keeps accepting jobs.
- `admin.rb:675`: The EV (parents' council) password depends on the calendar year (`Date.today.year`) instead of the school year and changes on 1 January (assumption).
- `poll.rb:699`: `WHERE pr.anonymous = $anonymous`. If the client sends a different value, there is an HTTP 500 instead of an understandable message.

## Stale/inconsistent state

- **timetable caches** without handling for deletion and moving: messages (#5), class tests (#8), notes and comments after an offset shift (#6). `@lesson_info` is only deleted if exactly this lesson key is triggered (`timetable.rb:2369-2378`).
- **Dependency on `Date.today` when writing:** `regular_events_from` and the hiding of past events (`timetable.rb:1165-1167, 1881`) as well as the monitor's `today`/`tomorrow` (`:211`) are only recalculated on full runs. Without a change in the Vertretungsplan after midnight (Monday morning, after holidays), the monitor keeps showing the old day (`monitor.html:732`).
- **`update_mailing_lists` (`main.rb:1465ff`):** is called from Puma request threads and sets `@@mailing_lists = {}` before the list has been refilled. Concurrent readers see empty or half lists. Two concurrent calls write to the **same** file `mailing_lists.yaml.tmp` (`:1697-1700`). This can produce interleaved or truncated YAML, or the second `mv` fails with HTTP 500 (assumption). Fix: build the list locally and assign it in one step at the end, unique temp names, mutex.
- The same pattern is found in `directory.rb:583-760` (`@@angebote_mailing_lists = {}` etc.).
- **`@@ws_clients`** is iterated in `monitor.rb:36-51` while `open`/`close` add or remove keys in other threads. Possible consequence: “can't add a new key into hash during iteration”. `monitor.json` is not written atomically (`timetable.rb:320`), concurrent reading can raise a JSON ParserError.
- **`MERGE (i:LessonInfo {offset})-[:BELONGS_TO]->(l)`** (`lesson.rb:17`, `email.rb:28`) is not atomic without a constraint. Concurrent saves can create duplicate LessonInfos, later `expect_one` calls then abort with HTTP 500 (assumption).
- **The bots work with data from startup:** mail forwarder (allowed senders, roles), stats bot (`@@user_info`) and invitation bot only know new teachers or roles after their own restart. `doc/Betrieb.md` only mentions `restart ruby`.
- **`trigger_update` swallows errors** (`main.rb:2306-2313`), without timeout and without retry. If the timetable service is reachable but hanging, the request thread blocks for up to 60 s.
- **`update(nil)`** catches errors in `update_timetables` and `update_recipients` and logs them without a backtrace (`timetable.rb:2329-2348`). A single `nil` entry aborts the writing of **all** `recipients.json` (e.g. `:2257`).

## Mail forwarder: possible causes of the dropouts

Sorted by likelihood, all derived from the code:

1. **The provider's SMTP rate limit.** Each recipient means a separate SMTP connection with AUTH, only 0.1 s apart (`:267, :307`). A large parents' list quickly hits per-minute or per-hour limits. Consequence: exception, the rest goes to `.failed`, and there is **no retry** (#2). If the limit resets after an hour, “it works again”. This matches the symptom exactly.
2. **The sending thread t2 dies silently.** If the notification mail in the `rescue` also fails (`:290`, very likely with a rate limit), the exception leaves the thread. The main thread, however, waits in `t1.join` (`:317`). t1 therefore keeps fetching mails, copies them to “Forwarded” and deletes them, but no longer sends anything. Only an IMAP error in t1 ends the process, Docker restarts it (`restart: always`), and t2 works through the pending `recipients.yaml`. When the next IMAP hiccup comes is random: “a few hours of dropouts, then fine again”. A truncated `recipients.yaml` after SIGKILL (trap commented out, `:26-30`, non-atomic writing `:304`) kills t2 permanently.
3. **IMAP without a read timeout:** If a connection hangs (NAT, provider), t1 blocks until TCP gives up. That can take dozens of minutes up to 2 h (assumption). During that time no new mails arrive.
4. **Broken `mailing_lists.yaml`** due to the tmp collision (see above). Invalid YAML leads to crash loops. Missing lists produce bounces „Ungültige Verteiler-Adresse“ (invalid distribution list address) until the next `update_mailing_lists`. Incidentally: the typo `@@mailing_lists` vs. `@@mailing_list` (`:51/58`) causes the file to be re-read on every call.
5. **Faulty messages:** An unparseable `From` (`:109`) makes t1 crash again and again on the same INBOX mail. Then everything rests until someone removes the mail.

**Diagnosis:** Search the log for `terminated with exception`, `Forwarding mail failed`, SMTP codes `421|45[0-4]|5\.7\.` and `Unable to resolve`. In `MAIL_FORWARDER_PATH` look for `*.failed` and for `recipients.yaml` older than an hour.

**Fix package:** Per-recipient `rescue` with a retry queue. One SMTP connection for the whole batch and throttling according to the provider limit. `Thread.abort_on_exception = true` or a `begin/rescue/retry` around each loop iteration. IMAP timeouts. Atomic writes. A heartbeat file that a health check checks.

## Half-finished / dead / broken

- `timetable.rb:2183` “TODO: Also handle angebote!”: The trigger `_angebote_` (`angebote.rb:85,130,148`) only rewrites `recipients.json`, without Angebote (offerings). Effectively it does nothing.
- `poll.rb:686, 749`: trigger commented out. This makes the `_poll_run_` branch in `timetable.rb:2398-2411` and in `timetable-repl.rb:88` dead code.
- `image-bot-repl.rb:93-101`: the logic for `future_queue` and ping is dead. If it were to kick in, it would call `perform_update(which)` with the wrong number of arguments.
- `mail-bot-repl.rb:10`: `PING_TIME` is never used (see #10).
- `main.rb:2350-2351`: Advent calendar hard-coded to 2021, always returns 0. `monitor.html:450` depends on it.
- `main.rb:3572-3573`: header `X-Tage-Bis-…` with hard-coded dates from 2026.
- `mail-forwarder.rb`:
  - `:85` hard-coded school domain instead of `SCHUL_MAIL_DOMAIN` (breaks in forks)
  - `:87` hard-coded class “11” as allowed senders
  - `:153-155/191-195` notice about moved addresses, half commented out
  - `:26-30` SIGTERM trap commented out
  - `:40-44` unused plain-text IMAP connection as a “DNS test”
- `main.rb:1667`: `:extra_allowed_users` (project organisers) is written but read nowhere. Organisers without a role get their mails bounced.
- `timetable.rb:1779`: its own TODO “this code can't work” (homework in the lesson modal).
- `timetable.rb:2345`: Corona logging `log_freiwillig_salzh_sus_for_today` runs along on every full run. `timetable.rb:656`: date switch from 2022.
- `include/test_events.rb:4-8`: clean-up of old entries commented out, `TestEvent` nodes accumulate.
- `lab8.rb`/`lab9.rb`: almost identical copies. Together with `projekte_old.rb` candidates for consolidation or removal.
- `main.rb:1445` “TODO: Temporarily disabled” sits above code that is actively running. The comment is misleading.
