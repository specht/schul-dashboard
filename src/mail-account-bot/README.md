# Mail account bot (Postfach-Bot)

Resets school mailboxes (students' and parents' `eltern.…` mailboxes) to
their original password in the IONOS control panel – only for cases the
admin approved on `/passwoerter`. Plan and decisions:
[review/2026-11/mail-password-reset.md](../../review/2026-11/mail-password-reset.md).

**Runs only on the maintainer's machines, started only by him.** Nobody
else starts it – not Jonas, not an agent (AGENTS.md, section 4). The
IONOS account is the school's only access to all mailboxes; unusual logins
can get it locked.

## Safeguards

- **No configuration, no bot.** `~/.ssh/gyst-mail-account-bot/config.json`
  (directory 700, file 600, owned by the user) names the machines it may
  run on (`hosts`, e.g. home and laptop); anywhere else the bot refuses to
  start. Limits in it can only be lowered.
- **Content from the dashboard, secrets only here.** Which mailboxes, of
  which kind (student / parents) and the password come from the production
  dashboard. The IONOS login, its 2FA secret and the dashboard token stay
  in the configuration on these machines.
- **Shared state on the dashboard.** Pause, the IONOS logins of the day (at
  most 10 for all machines together; the admin can reset the count on the
  page "Passwörter" when trying things out) and the run lock (one machine at a
  time) live on the dashboard, so they hold whichever machine runs.
- **Few logins.** One browser profile (`~/.local/state/gyst-mail-account-bot/profile`),
  the session is reused while IONOS keeps it. At most one login attempt
  per run; a TOTP time step is never used twice.
- **Nothing to do, no IONOS.** If a mailbox already accepts its original
  password (IMAP check), the control panel isn't opened at all.
- **The maintainer says yes.** Before every sitting the bot asks in the
  terminal with the list of mailboxes; no answer, no action – also in
  background mode (`serve`), which therefore runs in a terminal.
- **One sitting, human pace.** All approved cases one after another, with
  pauses and typing like a person; then the bot stays 20 minutes with the
  same session in case more get approved.
- **Exactly this mailbox.**
  - Only addresses matching `allowed_mailboxes` are accepted, and the
    dashboard must name the kind: `student` for an address, `parents` for
    `eltern.…` – anything else is refused.
  - In the list, exactly one row must have exactly this address, and it
    must be a mailbox, not a forwarding address.
  - The mailbox id from that row must match the menu link, the page
    address, the breadcrumb and the "Abbrechen" link; the page must show
    exactly this address, before typing and again right before the click.
    "Löschen", right next to "Passwort ändern" in the menu, is never used.
  - The password is read back from the field before submitting.
  - Afterwards, an IMAP login with the new password proves it arrived at
    the right mailbox.
- **Stop at the first surprise, never retry.** The bot stops and pauses on
  any of these:
  - an unknown or ambiguous page
  - a captcha or security check
  - a rejected login, or no second factor asked
  - a redirect to another site, or a new window
  - an error from IONOS
  - no confirmation after saving
  - a new password that doesn't work

  When it stops, it takes a screenshot (local only), reports the case as
  failed and pauses the bot on the dashboard – the admin gets a mail, the
  page "Passwörter" shows the reason. It also shows a desktop
  notification. No machine runs again until the admin lifts the pause on
  that page.
- **Creating mailboxes: Mail Basic, nothing else.** Before creating, the bot
  fetches the provider's address list (the export) and sends it to the
  dashboard; whatever is in it already is never created. It creates only
  student and `eltern.…` mailboxes the admin approved: only the "Mail Basic"
  card (never Mail Business, Exchange or a forwarding), exactly the
  approved address on exactly its domain (offered exactly once), no paid
  or extra option ticked (Virenschutz, Archivierung, KI), no forwarding
  target. Afterwards the page must show exactly this address, and an IMAP
  login with the letter's password must work.
- **Unrecorded flow, no real runs.** The IONOS steps in `lib/ionos.js` have a
  `FLOW_STATUS`. `provisional` means no real run is possible. `recorded`
  allows dry runs and the test mailbox only. `verified` allows real cases.
  `CREATE_FLOW_STATUS` is the same for creating mailboxes (the export is
  read-only and always allowed).

The tests (`test/e2e/tests/mail-account-bot.spec.ts`, fake IONOS in
`fake-ionos.ts`) check each of these against a fake control panel; the
bot's browser never reaches the real IONOS there. The dashboard's side
(shared state, websocket, background mode) is in
`mail-account-bot-dashboard.spec.ts`.

## Setup (maintainer's machine)

```sh
cd src/mail-account-bot && npm ci
mkdir -p -m 700 ~/.ssh/gyst-mail-account-bot
touch ~/.ssh/gyst-mail-account-bot/config.json
chmod 600 ~/.ssh/gyst-mail-account-bot/config.json
```

`config.json` (values here are placeholders):

```json
{
  "hosts": ["<output of `hostname` at home>", "<… on the laptop>"],
  "dashboard_url": "https://<dashboard host>",
  "dashboard_token": "<MAIL_ACCOUNT_BOT_TOKEN from the server's credentials.rb>",
  "ionos_login": "<IONOS customer number or login>",
  "ionos_password": "<IONOS password>",
  "totp_secret": "<base32 secret or the otpauth:// URI from the QR code>",
  "allowed_mailboxes": "^(eltern\\.)?[a-z0-9.-]+@<student mail domain, dots escaped>$",
  "test_mailbox": "<a mailbox only for tests>",
  "test_mailbox_passwords": ["<password A>", "<password B>"]
}
```

For `record` only `hosts` (and optionally `test_mailbox`) is needed – you
type the login yourself.

## Commands

The usual way: `./src/scripts/postfach-bot.sh` (from the repository) starts
the background mode and handles approved jobs until you press Ctrl+C – the
first Ctrl+C lets a mailbox in progress finish, a second one stops at once.

| Command | What it does |
|---|---|
| `node bot.js check [--imap]` | Checks the configuration and shows the current TOTP code (compare it with the app). Checks the dashboard token. With `--imap`, also checks the test mailbox passwords. Doesn't touch IONOS. |
| `node bot.js record` | Opens the bot's browser. You log in and click through by hand, and the page structure is written to `~/.local/state/gyst-mail-account-bot/recordings/` without input values or addresses. |
| `node bot.js run --dry-run` | Goes up to the filled-in dialog, then "Abbrechen". Nothing is changed or reported. |
| `node bot.js run --test-mailbox` | Resets the test mailbox. The two passwords take turns. |
| `node bot.js run` | Handles the approved cases once (with the question in the terminal). |
| `node bot.js serve` | Runs in the background: connected to the dashboard by a websocket, it starts a run when the admin approves a case (and every 15 minutes in case the connection died). The page "Passwörter" shows whether it is connected. |
| `node bot.js status` | Shows whether the bot is paused (on the dashboard) and the last stop on this machine with its screenshot. The pause is lifted on the page "Passwörter". |

Logs and screenshots stay in `~/.local/state/gyst-mail-account-bot/` and
can contain addresses – don't share them.

## Getting to `verified`

1. `check`: the TOTP code matches the app.
2. `record`:
   - log in by hand
   - open the e-mail addresses
   - on the test mailbox, choose "Passwort ändern", then "Abbrechen"
   - again, this time really change it, to password A
   - close the window
3. Adapt `lib/ionos.js` and `fake-ionos.ts` to the recording; status `recorded`.
4. `run --dry-run --test-mailbox`, then `run --test-mailbox`, watched.
   If both go through, set the status to `verified`.
5. Set `MAIL_ACCOUNT_BOT_TOKEN` on the server (credentials.rb,
   restart ruby) and put it into `config.json`.

If IONOS changes its pages later, the bot stops at the first difference.
Record again, adapt, set the status back to `recorded`, and watch a dry run.
