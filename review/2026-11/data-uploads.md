# Plan: uploading student and timetable data in the dashboard

Status: in progress (2026-11-20). Decisions by the maintainer are marked
**decided**.

## Goal

Today a new timetable or student list means: change the file in the private
data repo, push, pull on the server, restart the services. Instead, people
with a new role upload the export in the dashboard, see what would change,
pick the date from which it is valid (today, a past or a future date) and
confirm. The files stay in the data repo, with history.

## Today

- Every service reads all input data once at startup (`Main.collect_data`)
  from `/data`, the data repo checkout, mounted **read-only**. Only the
  timetable service reloads it with each full update.
- Timetables are already dated: `stundenplan/<date>.zip` (Untis HTML
  export) is valid from `<date>` on (`Parser#timetable_sources`).
  Pausenaufsichten come from the same ZIP (or `pausenaufsichten/<date>.TXT`).
- Students are a single `schueler/ASCII.TXT` without a date (WinSchule
  format). The LUSD converter (`src/ruby/lusd_import.rb`,
  `src/scripts/lusd-to-ascii.rb`) produces that format.
- Production services run with `restart: always`.

## Design

### 1. Reloading without a restart

A confirmed upload (or an admin button) writes a marker
`/internal/data-version`. Each service checks it about every 10 s and re-executes
itself when it changed (same container, new data). nginx
shows the existing restart page (`errors/neustart.html`) during the short
gap. Exiting is safer than rereading in place: `collect_data` empties and
refills class variables that puma threads read concurrently.

This alone shortens the manual routine to "push, pull, reload".

### 2. Upload page (new role `datenpflege`)

- Accepts `.zip` (Untis) and `.xlsx`/`.csv` (LUSD). Extension whitelist,
  size limit, parsed in memory; nothing is stored before confirming.
- **Preview against what is valid on the chosen date:**
  - Students: per class before/after, new, gone, changed e-mail address
    (same matching as the converter), rows with errors. Class names mapped
    as in the converter, with the mapping editable on the page and stored in
    the data repo (`schueler/klassen-tr.yaml`).
  - Timetable: lessons added/removed/changed per class and teacher,
    Pausenaufsichten per teacher, unknown teachers/subjects/classes.
- Date picker "gültig ab" (default today; past dates allowed; a warning for
  dates before the start of the school year or far in the past).
- Errors block confirming (e.g. gender other than m/w, unknown classes).

### 3. Files in the data repo (**decided**: server commits and pushes)

- Students **decided**: the converted text file, dated:
  `schueler/<date>.TXT` in the ASCII.TXT format. The parser uses the newest
  file whose date is not in the future, falling back to `ASCII.TXT`. A
  future date takes effect by itself: the services reload at midnight when
  another file becomes current.
- Timetables: `stundenplan/<date>.zip` as today.
- The ruby service gets a second, writable mount of the data checkout
  (e.g. `/data-repo`), only when `DATA_REPO_WRITABLE` is set in `env.rb`
  (generated files stay byte-identical without it). `/data` stays
  read-only for every other service.
- Confirming writes the file atomically, then `git add <file>`,
  `git commit` (author: dashboard, message names the uploader and the
  file), `git pull --rebase`, `git push`. Git runs with argument arrays,
  never shell strings. If the push fails, the upload is still committed
  locally and the page says so; the next upload or a retry button pushes.
- Needs: `git` and `openssh-client` in the ruby image; a deploy key with
  write access to the data repo only, stored under `/internal` (not in any
  repo). Setting up the key needs the maintainer.

## Order and tests

1. Reload marker + services exit on change (unit tests for the watcher;
   E2E for the admin button).
2. Dated student files in the parser (unit tests with example data).
3. Upload + preview for students (unit tests for the diff, E2E for the page
   on desktop and phone, example data only).
4. Commit and push (tested against a throwaway bare repo in the test
   stack).
5. Timetable ZIP upload + preview.

## Decided (2026-11-20)

- Admins get the upload role by default (`datenpflege` is implied by
  `admin`); more people can be given it in `roles.txt`.
- A timetable upload may replace the file for an existing date, but the
  page says so and asks for an explicit confirmation first.
- No mail after uploads. Instead an overview page: all data files by type
  and validity date (current, future, past), who uploaded them and when
  (from the data repo's history), and the last reload.

## Progress

- Step 1 done: `DataVersion` (`src/ruby/data_version.rb`), "Daten → Neu
  laden" on the admin page. A service that sees a new version re-executes
  its own command line in the same process (pid and container stay), so it
  works without Docker's restart policy (development, test stack). Checked
  by hand in the test stack: web and timetable restart, the dashboard
  answers again after about 15 s, and a second change restarts them again.
