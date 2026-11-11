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
- Bot interface, only active when `MAIL_PASSWORD_RESET_BOT_TOKEN` is set:
  - `GET /api/mail_password_reset_bot/pending` → approved cases, each with
    its mailboxes and passwords
  - `POST /api/mail_password_reset_bot/result {id, ok, message}`
  - `Authorization: Bearer <token>`, compared in constant time; the bot can
    run anywhere that reaches the dashboard.
- On `done` after a student's own request: notice to `eltern.<mailbox>`.
  On `failed`: mail to the admin.
- Tests: E2E for student, Klassenleitung (a non-admin class teacher in the
  test data), admin, refused cases (other student, parent mailbox by a
  student or Klassenleitung, limit), the bot interface with the test token,
  and the notice mail in Mailpit.

## Phase 2 – bot

- Small separate service (Node + Puppeteer, like the existing script):
  persistent browser profile, TOTP for the login confirmation, fetches open
  requests every minute, sets the password, reports the result, a screenshot
  on failure for the admin.
- Access data only in its own configuration (not in the dashboard, not in
  the repository).
- Where it runs: open (maintainer's machine or its own container on the
  server).
- The control panel flow for "change password" has to be recorded with the
  maintainer once the two-factor login is set up.
