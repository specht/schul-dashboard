# Mailbox password reset from the dashboard

Status: phase 1 (dashboard) built, not yet deployed (2026-11-11).

## Problem

Students forget their school mailbox password, write to the admin from a
private address, and wait until the admin logs in to the mail provider's
control panel, resets the password to the original one and mails it back.
The browser script that automates the control panel sometimes stops at a
login confirmation code that goes to someone else.

The mail provider has no API for mailboxes (its developer API covers
domains, DNS and certificates only), so the change itself stays browser
automation – but it can run without waiting for a person.

## Decisions (maintainer, 2026-11-10)

- A reset sets the **original password** (`Main.gen_password_for_email`), as
  the existing E-Mail-Brief and the Nextcloud reset do. Nothing new to store.
- **Who may request a reset of which mailbox:**
  - students: their own mailbox, from their dashboard session
  - Klassenleitung: the mailboxes of the students of their class
  - admin: student and parent (`eltern.…`) mailboxes – parent mailboxes
    only by the admin, so nobody else resets them without the parents
    wanting it
    (parents have no dashboard account: they ask the admin, who reads the
    password off the page after the reset and passes it on)
- After a **student's own** reset, the parents' mailbox gets a short notice
  (a left-open session could otherwise be used to take over a mailbox).
- **One page for both** (2026-11-11): `/passwoerter` combines the Nextcloud
  login data and self-service (reset to the initial password at once, no
  questions asked) with the mailbox reset. `/login_nc` and `/mail_passwort`
  redirect there.
- **Every mailbox reset goes through the admin**, automated or not: a
  request is a case that waits for the admin's approval; the bot only gets
  approved cases. The Klassenleitung may open cases for the students' and
  the parents' mailboxes of their classes and forwards requests that reach
  them by mail to the admin; the admin answers the Klassenleitung with the
  E-Mail-Brief to pass on.
- The admin first adds a request to the list, then resolves it step by
  step: check (reset / reject), reset (bot or by hand: done / didn't work,
  then retry or give up), answer (send the reply or close without one).
- Requests that come in **by mail** (from private addresses; the admin
  establishes who is writing) are entered by the admin as a case: affected
  mailboxes (several possible, also `eltern.…`), reply address, note.
  It lands in the list as an open case like a click on the page.
- When such a case is done, the dashboard sends the **answer**: editable
  text (default: "Sehr geehrte Frau / Herr …, ich habe das Passwort für das
  Postfach von [Name] zurückgesetzt und sende Ihnen die Zugangsdaten im
  Anhang. Viele Grüße [Name des Admins]"), the E-Mail-Brief as PDF attached,
  from the dashboard's address with Reply-To and Bcc to the admin.
- The provider account gets app-based two-factor authentication (set up by
  the maintainer with the Schulleitung), so the bot can confirm logins
  itself instead of waiting for a code sent by mail.

## Phase 1 – dashboard (tests first)

- Node `MailPasswordCase {id, ts, source, requested_by, reply_to, note,
  mailboxes, state, …}` with `[:FOR]` to one lock node per mailbox; states
  `open` → `approved` → `done` | `failed`, or `open` → `rejected`.
- `POST /api/request_mail_password_reset {mailbox}`: permission check as
  above; at most one open request per mailbox; a limit per mailbox and day.
- Status for the requester: pending ("dauert meist nur wenige Minuten"),
  done (students see their password, as on the Nextcloud page; Klassenleitung
  can print the E-Mail-Brief), failed (the admin is informed).
- Admin page: all open and recent requests; "erledigt" / "fehlgeschlagen"
  by hand, so phase 1 already helps before the bot exists (the admin gets a
  mail per new request while no bot is configured).
- Bot interface, only active when `MAIL_ACCOUNT_BOT_TOKEN` is set:
  - `GET /api/mail_account_bot/pending` → approved cases, each with
    its mailboxes and passwords
  - `POST /api/mail_account_bot/result {id, ok, message}`
  - `Authorization: Bearer <token>`, compared in constant time; the bot can
    run anywhere that reaches the dashboard.
- On `done` after a student's own request: notice to `eltern.<mailbox>`.
  On `failed`: mail to the admin.
- Tests: E2E for student, Klassenleitung (a non-admin class teacher in the
  test data), admin, refused cases (other student, parent mailbox by a
  student or Klassenleitung, limit), the bot interface with the test token,
  and the notice mail in Mailpit.

## Phase 2 – bot

- **Built (2026-11-13), not yet run against IONOS:** `src/mail-account-bot`
  (Node + Playwright with the local Chrome; usage and safeguards in its
  README). The IONOS steps are provisional until recorded with the
  maintainer (`FLOW_STATUS`); the bot refuses real runs until then. Tests
  against a fake control panel: `test/e2e/tests/mail-account-bot.spec.ts`.
- Persistent browser profile, TOTP for the login confirmation, sets the
  password for approved cases, reports the result, a screenshot on failure
  for the admin.
- Access data only in its own configuration (not in the dashboard, not in
  the repository).
- **Where it runs (decided 2026-11-12): only on the maintainer's machine.**
  The IONOS session (browser profile, cookies) lives where the browser runs,
  so IONOS always sees the maintainer's machine. The dashboard server only
  keeps the list of cases and never talks to IONOS; the bot fetches approved
  cases over HTTPS with the bot token and reports back.
  - The bot's configuration (IONOS login, TOTP secret, dashboard token) is a
    chmod-600 file outside the repository, only on that machine. Without it
    the bot refuses to start; it also checks a hostname named in that file,
    so a copied configuration doesn't run elsewhere.
  - Nobody else starts it – not Jonas, not an agent. Recorded in AGENTS.md.
  - A lock file keeps a second instance from running. Two runs resetting the
    same mailbox would be harmless anyway: it is always reset to the same
    original password, so no claim step in the dashboard.
  - When the machine is off, approved cases simply wait; the admin can still
    reset by hand and mark them done.
- The control panel flow for "change password" has to be recorded with the
  maintainer once the two-factor login is set up.

### Don't get the account locked (decided 2026-11-12)

The IONOS account is the school's only access to all mailboxes. If IONOS
takes the bot for an account takeover and locks or challenges the account,
nobody can reset passwords until support unlocks it. So the bot behaves like
one careful person at one computer:

- **Few logins.** One persistent browser profile (cookies kept), the same
  machine and IP every time, a normal visible Chrome rather than an obvious
  headless setup with a changing fingerprint. Reuse the session as long as
  IONOS keeps it; log in (password + TOTP) only when it has expired.
- **Batches, not polling the control panel.** The bot may ask the dashboard
  every few minutes whether approved cases exist (that never touches
  IONOS); it only opens the control panel when there are some, then handles
  all of them in one sitting. Optionally only within fixed hours (school
  day), so a burst of approvals doesn't become a burst of logins.
- **Human pace.** Wait for each page to finish, pauses of a few seconds
  between steps with some variation, one mailbox after the other, never in
  parallel. A hard cap per day (e.g. 20 resets); above it the rest waits for
  the next day or for the admin.
- **Stop at the first surprise, never retry blindly.** A failed login, a
  wrong TOTP, a captcha, a "new device / security check" page, a layout the
  recorded flow doesn't know: take a screenshot, mark the case "didn't
  work", notify the admin, and pause the bot (no further logins) until the
  admin resumes it. At most one login attempt per run; a TOTP code is never
  used twice (wait for the next 30-second window).
- **Exactly this mailbox.** Only addresses matching the configured student
  pattern; exactly one row with exactly this address, and a mailbox (not a
  forwarding); the dialog shows exactly this address (checked twice); the
  password read back from both fields; afterwards an IMAP login with the
  new password proves it reached the right mailbox. A mailbox that already
  accepts its original password is not touched in the control panel.
- **Dry run first.** Record the flow with the maintainer, then run it against
  a test mailbox by hand-triggered single runs before it handles real cases.
- Keep the IONOS recovery codes from the 2FA setup offline (not with the
  bot), so a lockout can be undone without support.


## Phase 3 – one IONOS bot for the whole mailbox process (decided 2026-11-14)

Status 2026-11-14: password resets run in production with the bot (2FA
login recorded, cleared after watched dry runs). Creating mailboxes and the
address list upload are built and tested against the fake; creating is
recorded but not yet cleared (`CREATE_FLOW_STATUS`).

The same bot also creates mailboxes and fetches the IONOS address list, so
`create-account.js` (and its plain-text passwords) and the hand-made export
file can go.

- **Scope – vital:** the bot only ever touches two kinds of mailbox, both
  on the school's `@mail.` subdomain:
  - a student's own address (dashboard user with role schueler)
  - the parents' mailbox `eltern.<that student>`

  Teacher mailboxes (main domain, created only by the Schulleitung),
  function accounts, external accounts on `@mail.` and `ev.<Klasse>` are
  never touched. This is checked by the dashboard and again by the bot
  (domain, role, `eltern.` + existing student). The old "required
  addresses" list on `/email_accounts` also counts teachers – it is not
  used for bot work.
- **Address list:** the bot downloads the IONOS export (address, account
  type, contract) and sends it to the dashboard, instead of a file in the
  data repo. To be recorded with the maintainer. Never polled: the bot
  fetches it only
  - in the same sitting right before creating approved mailboxes (to
    confirm they are still missing),
  - when the admin asks for it on the page, and
  - otherwise at most about once a week, in a sitting that is logged in
    anyway.

  The dashboard shows how old the list is. The export has no mailbox
  numbers; the bot learns them from the address list when it needs them.
- **Missing mailboxes:** the dashboard lists students and parents' mailboxes
  that are missing in the export. The admin approves them, the bot creates
  them with the E-Mail-Brief password, proves each one by an IMAP login,
  and reports back; then the letters are printed as before. The creation
  page is to be recorded.
- **Volume:** no artificial daily limit. Like the old script, all approved
  mailboxes go in one sitting, one after the other at a person's pace. If
  something gets stuck, the bot stops; after `resume`, the next run fetches
  the address list first, so nothing is created twice.
- **Several machines:**
  - The configuration is in `~/.ssh` (kept by the maintainer) and lists the
    allowed machine names, e.g. home and laptop.
  - Pause, counters and the "one run at a time" lock move to the dashboard,
    so they hold across machines. The admin page shows the pause and lifts
    it.
  - The browser profile with the IONOS session stays per machine.
- **Deleting mailboxes:** later. Scheduling them for deletion already exists
  on `/email_accounts`, but nothing has ever been deleted; any automation
  needs its own decision.
