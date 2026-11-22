# Plan: checking the new student list with the teachers before the switch

Status 2026-11-22. Builds on [data-uploads.md](data-uploads.md) (upload,
compare, apply as a dated list on `/datenpflege`).

## Goal

The new student list comes from LUSD. Before it replaces the current one, the
people who know the students check it: Klassenleitungen for 5–10, tutors for
11/12. Errors are corrected **in LUSD** and the export uploaded again, until
the list is right; then the switch, during the school year, about one to two
weeks after the teachers were asked.

## Today

- `/datenpflege` (role `can_manage_data`): upload an export, compare it with
  the current list (new, leaving, changed: name, class, Bildungsgang, gender,
  birthday), map LUSD classes, apply as `schueler/JJJJ-MM-TT.TXT`.
- An upload is kept for 24 hours only (`datenpflege_cleanup_pending`), there
  is no draft, no second comparison, no review.

## Flow

1. **Draft.** Upload the export as *the draft*: it is kept until replaced or
   applied and has no effect anywhere (timetables, mailing lists, accounts,
   logins). A new upload replaces it; the previous draft is kept for one
   comparison.
2. **See the consequences.** Two comparisons on `/datenpflege`:
   - draft vs. live list: what the switch would change;
   - draft vs. previous draft: which corrections arrived from LUSD.
3. **Ask the teachers.** One button sends a mail to every Klassenleitung and
   tutor with a link (through `deliver_mail`); a page shows their students.
4. **Teachers check.** Per student »Stimmt« or a correction; at the end
   »Liste bestätigt«. Corrections can be changed until confirmed.
5. **We check again.** Corrections as a to-do list; fix in LUSD, upload again
   (step 1); corrections that arrived are marked done automatically.
   Teachers whose list changed after they confirmed are asked again.
6. **Switch.** Apply the draft through the existing mechanism (dated list,
   data repo, reload). Corrections and confirmations are deleted afterwards.

## The teachers' page

- Their students **as in the draft, all of them**, changes highlighted (not
  only the changes: errors that are in both lists would never show).
  Arriving students (from another class or new) and leaving ones (to another
  class or gone) in their own block.
- Per student: »Stimmt«, or a correction:
  - per field: Rufname, Nachname, Vornamen, Geschlecht, Geburtstag,
    Bildungsgang, Klasse (a choice where there is one);
  - »Nicht mehr an der Schule« (optional: since when);
  - free text for anything else.
- »Fehlt jemand?«: name and a note, for students missing from the draft.
- »Liste bestätigt« at the end; afterwards read-only, with »Ändern«.
- Who sees whom: a Klassenleitung their class (5–10), a tutor their tutees
  (11/12). Nobody else's students; admins with `can_manage_data` everything.
- Text in »du«, new design and old design (the page is new; build it in the
  new design's style, readable in the old one).

## Our view on `/datenpflege`

- Status per class / tutor group: not opened, opened, confirmed, confirmed
  with corrections; »Erinnern« sends the mail again to those not confirmed.
- Corrections as a list: student, field, current draft value, proposed value,
  who, when; done automatically when the next draft has the proposed value
  (per-field corrections, »nicht mehr an der Schule«, »fehlt«), by hand
  otherwise.

## Data

- Draft: the pending files, no longer removed after 24 hours while they are
  the draft; one previous draft for the second comparison.
- `(:StudentReview {key, klasse_or_tutor, confirmed_at, confirmed_by})`,
  `(:StudentCorrection {id, student_key, field, value, text, by, at, done})`.
  `student_key`: the email for students in the live list, the LUSD key
  (Schueler_Schluessel) for new ones – needs that column in the export.
- Everything about the review is deleted after the switch (personal data).

## Overrides for Rufname and gender (decided 2026-11-22)

Some students are officially still listed with their old name and gender;
the dashboard needs its own values that every LUSD import keeps.

- Two fields only: **Rufname** and **Geschlecht** (m/w/d), per student
  (email), kept in the data repo next to the lists (private repository, not
  this one), applied after the list is read – everywhere the dashboard shows
  or uses the name and gender, **except report cards**.
- The Rufname comes from LUSD; the override only where it differs. The
  official names stay as they are (`official_first_name`), and the official
  gender is kept as `official_geschlecht`.
- **Report cards** (Zeugnisse, Sozialverhalten, Zeugnisdruck) use the
  official first name and the official gender (its wording, `@Geschlecht`),
  never an override. A unit test makes sure of that.
- Set and removed on `/datenpflege` (role `can_manage_data`), with who and
  when; nobody else sees that a value is an override. A name report from the
  profile (»Namen melden«) can be taken over as an override in one step.
- The comparisons know them: a LUSD value that differs from an override is
  not a change and does not come up again with every upload; the draft
  comparison shows »Override aktiv« quietly, so it stays visible to us.
- In the teachers' review a correction of Rufname or gender can be marked
  »nur im Dashboard« – it becomes a proposed override instead of a LUSD
  correction.
- Sensitive: no override values in logs, mails, commit messages of this
  repository or test data beyond made-up examples.

## Open points

- **Tutors from LUSD:** does the Abfrageassistent offer the tutor? Expected
  yes; otherwise add the data in LUSD. Checked on 2026-11-23.
- **After the switch:** mail accounts for new students (Postfach-Bot, run by
  the maintainer only), students who left (logins, mailing lists), name
  changes (the email stays the stable id). Listed on `/datenpflege` after the
  switch so nothing is forgotten.

## Order

1. Draft kept, second comparison (draft vs. previous draft). Tests: unit
   (diff of two drafts), E2E (upload, replace, see both comparisons).
2. Overrides for Rufname and gender: read with the list, set on
   `/datenpflege`, known to the comparisons. Tests: unit (applied after
   reading, comparison ignores them), E2E (set, see it in the class list,
   upload a draft with the old value: no change).
3. Teachers' page with corrections and confirmation, permissions. E2E:
   Klassenleitung sees only the own class, corrects, confirms; a student and
   another teacher get nothing.
4. Status and corrections on `/datenpflege`, automatic »done«, mails and
   reminders. E2E with Mailpit.
5. After-switch checklist.

Tests with `src/example-data` only; the test stack's class list and a
made-up export in the test.
