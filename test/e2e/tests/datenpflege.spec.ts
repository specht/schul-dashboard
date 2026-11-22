import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, Page } from '@playwright/test';

// Uploading a student list from LUSD on /datenpflege (include/datenpflege.rb):
// compare with the list valid on the chosen day, apply it to the data repo
// (a git repo in the test stack, see test.sh), commit or roll back.
//
// The test stack's services don't restart when the data changes
// (DATA_RELOAD_RESTARTS = false in env.test.rb). Lists are only written for
// days far in the future, so that the list the dashboard uses today stays
// the example data for every other test.

const HEADER = 'Nachname;Vorname;Rufname;Klasse;Geschlecht;Geburtsdatum';

// the example students (src/example-data/schueler/ASCII.TXT), changed:
// Max moves to 5b, Bob's last name is spelled differently (new address),
// Nina is new, Quentin is in a class the dashboard doesn't know
const CHANGED = [
  HEADER,
  'Mustermann;Max;;05b;männlich;01.01.2010',
  'Mustermann;Elisabeth;Elli;05a;weiblich;02.01.2010',
  'Mustermann;Mallory;;05a;männlich;03.01.2010',
  'Mustermann;Alice;;11;weiblich;04.01.2010',
  'Mustermann-Neu;Bob;;12;männlich;05.01.2010',
  'Neu;Nina;;5c;weiblich;06.06.2014',
  'Q;Quentin;;Q9;männlich;07.07.2008',
  'von Schneiderhahn-Oberhofer;Anna-Katharina;;5c;divers;08.08.2014',
].join('\r\n');

async function upload(page: Page, csv: string, date: string) {
  await page.locator('#ti_date').fill(date);
  // choosing the file starts the comparison
  await page.locator('#ti_file').setInputFiles({ name: 'lusd.csv', mimeType: 'text/csv', buffer: Buffer.from(csv, 'utf-8') });
}

test('Datenpflege nur mit der Rolle (Admins haben sie)', async ({ page, baseURL }) => {
  await login(page, ACCOUNTS.teacher);
  await page.goto('/datenpflege');
  await expect(page).not.toHaveURL(/datenpflege/);
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  for (const path of ['/api/datenpflege/schueler/upload', '/api/datenpflege/commit', '/api/datenpflege/rollback', '/api/datenpflege/push', '/api/datenpflege/schueler/delete_list']) {
    const response = await api.post(path, { data: {} });
    expect(response.ok(), path).toBe(false);
  }
});

test('Datenpflege: Vergleich mit der bisherigen Liste', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  await expect(page.locator('.dp-current')).toContainText('ASCII.TXT');
  // a day before any uploaded list: compared with ASCII.TXT
  await upload(page, CHANGED, '2000-01-01');
  const preview = page.locator('#dp_preview');
  await expect(preview.locator('.dp-summary')).toContainText('8 Schüler:innen');
  await expect(preview.locator('.dp-summary')).toContainText('ASCII.TXT');
  // the columns: all needed ones there (closed), the missing optional ones named
  await expect(preview.locator('.dp-columns')).not.toHaveAttribute('open', '');
  await expect(preview.locator('.dp-columns summary')).toContainText('es fehlen: Schüler-Schlüssel');
  // new: the proposed address can be changed; a long name is shortened
  const nina = preview.locator('.dp-added tr', { hasText: 'Nina Neu' });
  await expect(nina.locator('.ti_email')).toHaveValue('nina.neu');
  const anna = preview.locator('.dp-added tr', { hasText: 'Anna-Katharina' });
  await expect(anna.locator('.ti_email')).toHaveValue('anna.schneiderhahn');
  await expect(anna).toContainText('gekürzt');
  // Bob is found by birthday and first name: he keeps his address, only the
  // name changes (marked like in a diff)
  await expect(preview.locator('.dp-moved')).toHaveCount(0);
  const bob = preview.locator('.dp-changed tr', { hasText: 'Bob Mustermann-Neu' });
  await expect(bob.locator('.dp-what')).toHaveText('Name');
  await expect(bob.locator('.dp-new mark')).toHaveText('Mustermann-Neu');
  // Max changes class; the class table says where his class's students were
  const max = preview.locator('.dp-changed tr', { hasText: 'Max Mustermann' });
  await expect(max).toContainText(/Klasse\s*5a\s*5b/);
  const fuenfb = preview.locator('.dp-klassen tr', { has: page.locator('input[data-lusd="5b"]') });
  await expect(fuenfb.locator('input')).toHaveValue('5b');
  await expect(preview.locator('.dp-dropped .dp-count')).toHaveText('1');
  // the unknown class is marked in the class table
  const q9 = preview.locator('.dp-klassen tr', { has: page.locator('input[data-lusd="q9"]') });
  await expect(q9).toContainText('wird weggelassen');
  await expect(preview.locator('.dp-dropped')).toHaveAttribute('open', '');
  await expect(preview.locator('.dp-dropped tr', { hasText: 'Quentin Q' })).toContainText('q9');
  // mapping it to a class of the dashboard: Quentin is no longer left out
  await q9.locator('input').fill('5c');
  await preview.locator('#bu_recheck').click();
  await expect(preview.locator('.dp-added tr', { hasText: 'Quentin Q' })).toBeVisible();
  await expect(preview.locator('.dp-dropped')).toHaveCount(0);
  await expect(page.locator('#dp_apply')).toBeVisible();
  await page.locator('#bu_discard_upload').click();
  await expect(preview).toBeEmpty();
  await expect(page.locator('#dp_apply')).toBeHidden();
});

test('Datenpflege: Fehler in der Liste verhindern das Übernehmen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  // m, w and d (divers) are known; anything else is an error
  await upload(page, [HEADER, 'Mustermann;Max;;5a;x;01.01.2010'].join('\n'), '2000-01-01');
  await expect(page.locator('.dp-errors')).toContainText('Zeile 2: Geschlecht »x« (erlaubt: m, w, d)');
  await expect(page.locator('#dp_apply')).toBeHidden();
  // a file without the needed columns: says which, and the earlier
  // comparison is gone
  await upload(page, 'Nachname;Vorname;Klasse\nMustermann;Max;5a\n', '2000-01-01');
  await expect(page.locator('#dp_message')).toContainText('Spalten fehlen im Export: Geschlecht, Geburtsdatum');
  // no comparison, but which columns are there and which are missing
  await expect(page.locator('#dp_preview .dp-summary')).toHaveCount(0);
  const columns = page.locator('#dp_preview .dp-columns');
  await expect(columns).toHaveAttribute('open', '');
  await expect(columns.locator('tr[data-field="geschlecht"]')).toContainText('fehlt (nötig)');
  await expect(columns.locator('tr[data-field="nachname"]')).toContainText('Nachname');
  await expect(columns.locator('tr[data-field="tutor"]')).toContainText('fehlt');
  // no header row at all
  await upload(page, 'Name;Ort\nMustermann;Berlin\n', '2000-01-01');
  await expect(page.locator('#dp_message')).toContainText('Keine Kopfzeile mit Nachname und Klasse gefunden');
  await expect(page.locator('#dp_preview')).toBeEmpty();
});

test('Datenpflege: übernehmen committet sofort, eine geplante Liste lässt sich löschen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  await upload(page, CHANGED, '2099-06-01');
  await expect(page.locator('#dp_future')).toBeVisible();
  const replace = page.locator('#dp_replace');
  if (await replace.isVisible()) await page.locator('#ti_replace').check();
  await page.locator('#bu_apply').click();
  // no restart in the test stack: the page reloads at once – committed, no
  // step left to forget
  const row = page.locator('.dp-files tr', { hasText: '01.06.2099' });
  await expect(row).toContainText('geplant');
  await expect(row).toContainText('Schüler:innen: 2099-06-01.TXT (über das Dashboard');
  await expect(page.locator('.dp-uncommitted')).toHaveCount(0);
  // withdrawn: asks first, committed too
  await row.locator('.bu_delete_list').click();
  const dialog = page.locator('.modal.show');
  await expect(dialog).toContainText('ab 01.06.2099');
  await dialog.getByRole('button', { name: 'Löschen' }).click();
  await expect(page.locator('.dp-files tr', { hasText: '01.06.2099' })).toHaveCount(0);
  await expect(page.locator('.dp-uncommitted')).toHaveCount(0);
});

test('Datenpflege: eine vorhandene Liste nur mit Bestätigung ersetzen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  // another student each run, so that the list is always a new one
  const name = 'Zufall' + Array.from({ length: 6 }, () => String.fromCharCode(97 + Math.floor(Math.random() * 26))).join('');
  await upload(page, [CHANGED, `${name};Rita;;5b;weiblich;01.02.2014`].join('\r\n'), '2099-12-31');
  await expect(page.locator('#dp_apply')).toBeVisible();
  const replace = page.locator('#dp_replace');
  if (await replace.isVisible()) {
    // from an earlier run (or the other project): replacing needs the tick
    await expect(page.locator('#bu_apply')).toBeDisabled();
    await page.locator('#ti_replace').check();
  }
  await expect(page.locator('#bu_apply')).toBeEnabled();
  await page.locator('#bu_apply').click();
  const row = page.locator('.dp-files tr', { hasText: '31.12.2099' });
  await expect(row).toContainText('geplant');
  await expect(row).toContainText('Schüler:innen: 2099-12-31.TXT (über das Dashboard');
  await expect(page.locator('.dp-uncommitted')).toHaveCount(0);
});

test('Namen melden: im Profil, erledigt auf /datenpflege', async ({ page, browser }, testInfo) => {
  // one student per project, so that desktop and mobile don't replace each
  // other's report
  const student = testInfo.project.name === 'mobile' ? ACCOUNTS.schueler_oberstufe : ACCOUNTS.schueler;
  const note = 'Test ' + Math.random().toString(36).slice(2, 10);
  await login(page, student);
  await page.goto('/profil');
  const box = page.locator('#name_report');
  // the example addresses fit the names: no pointer to a new address
  await expect(box.locator('.nr-mismatch')).toHaveCount(0);
  await box.locator('summary').click();
  await box.locator('#ti_name_report').fill(note);
  await box.locator('#bu_send_name_report').click();
  await expect(page.locator('#name_report .nr-sent')).toContainText('wird bearbeitet');
  // nothing to request on the mailbox page
  await page.goto('/passwoerter');
  await expect(page.locator('#bu_request_email')).toHaveCount(0);

  const context = await browser.newContext();
  const admin = await context.newPage();
  await login(admin, ACCOUNTS.admin);
  await admin.goto('/datenpflege');
  const row = admin.locator('.dp-reports tr', { hasText: note });
  await expect(row).toBeVisible();
  await row.locator('.bu_report_done').click();
  await expect(row).toHaveCount(0);
  await admin.reload();
  await expect(admin.locator('.dp-reports tr', { hasText: note })).toHaveCount(0);
  await context.close();
});

test('Namen melden nur für Schüler:innen, erledigen nur mit der Rolle', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  expect((await api.post('/api/name_report', { data: { kind: 'name', note: 'x' } })).ok()).toBe(false);
  expect((await api.post('/api/name_report/done', { data: { id: 'x' } })).ok()).toBe(false);
});

// A draft (review/2026-11/student-data-review.md): an upload kept until the
// LUSD data is right – it has no effect, is shown again when the page opens,
// keeps the choices made for it, and a new export is compared with it. One
// draft for everybody: desktop only, made-up students of its own.
test('Datenpflege: Entwurf behalten, neuen Export damit vergleichen, ersetzen, verwerfen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  const preview = page.locator('#dp_preview');
  const ENTWURF_1 = [HEADER,
    'Entwurf;Erik;;5c;männlich;01.02.2014',
    'Entwurf;Frida;;5a;weiblich;02.02.2014'].join('\r\n');
  const ENTWURF_2 = [HEADER,
    'Entwurf;Erik;;5c;männlich;01.02.2014',
    'Entwurf;Frida;;5b;weiblich;02.02.2014',
    'Entwurf;Greta;;5c;weiblich;03.02.2014'].join('\r\n');
  try {
    await upload(page, ENTWURF_1, '2000-01-01');
    await expect(preview.locator('.dp-summary')).toContainText('2 Schüler:innen');
    await expect(page.locator('#bu_keep_draft')).toHaveText('Als Entwurf behalten');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await expect(page.locator('#bu_keep_draft')).toBeHidden();
    // an address chosen for the draft stays with it
    const erik = preview.locator('.dp-added tr', { hasText: 'Erik Entwurf' });
    await erik.locator('.ti_email').fill('erik.e');
    await erik.locator('.ti_email').blur();
    await expect(preview.locator('.dp-added tr', { hasText: 'Erik Entwurf' }).locator('.ti_email')).toHaveValue('erik.e');

    // the page opens with the draft offered, not applied
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-draft')).toContainText('lusd.csv');
    await expect(preview).toBeEmpty();
    await page.locator('#bu_open_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await expect(page.locator('#ti_date')).toHaveValue('2000-01-01');
    await expect(preview.locator('.dp-added tr', { hasText: 'Erik Entwurf' }).locator('.ti_email')).toHaveValue('erik.e');

    // a new export: compared with the draft, its choices taken over
    await upload(page, ENTWURF_2, '2000-01-01');
    const since = preview.locator('.dp-since');
    await expect(since.locator('h5')).toHaveText('Seit dem Entwurf');
    await expect(since.locator('.dp-since-added tr', { hasText: 'Greta Entwurf' })).toHaveCount(1);
    await expect(since.locator('.dp-since-changed tr', { hasText: 'Frida Entwurf' })).toContainText(/Klasse\s*5a\s*5b/);
    await expect(since.locator('.dp-since-removed .dp-count')).toHaveText('0');
    await expect(preview.locator('.dp-added tr', { hasText: 'Erik Entwurf' }).locator('.ti_email')).toHaveValue('erik.e');
    await expect(page.locator('#dp_is_draft')).toBeHidden();
    await expect(page.locator('#bu_keep_draft')).toHaveText('Entwurf ersetzen');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    // the draft against the one before
    await expect(since.locator('h5')).toHaveText('Seit dem vorigen Entwurf');
    await expect(since.locator('.dp-since-added tr', { hasText: 'Greta Entwurf' })).toHaveCount(1);

    // discarding the draft asks first
    await page.locator('#bu_discard_upload').click();
    const dialog = page.locator('.modal.show');
    await expect(dialog).toContainText('Entwurf');
    await dialog.getByRole('button', { name: 'Verwerfen' }).click();
    await expect(preview).toBeEmpty();
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-draft')).toHaveCount(0);
  } finally {
    // no draft left for other tests
    const r = await page.request.post('/api/datenpflege/schueler/draft', { data: {} });
    const d = await r.json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});

// Rufname and gender in the dashboard (Parser.schueler_overrides): set on
// /datenpflege, kept by every LUSD export – the comparison doesn't count it
// as a change, but shows it (closed). One file for everybody: desktop only,
// a student no other test looks at, rolled back at the end.
test('Datenpflege: Rufname und Geschlecht im Dashboard festlegen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one file for everybody');
  await login(page, ACCOUNTS.admin);
  let email = '';
  try {
    await page.goto('/datenpflege');
    email = await page.evaluate(() => JSON.parse(document.getElementById('dp_override_data')!.textContent!)
      .find((x: { label: string }) => x.label === 'Mallory Mustermann (5a)').email);
    await page.locator('#ti_override_student').fill('Mallory Mustermann (5a)');
    await expect(page.locator('#bu_override_save')).toBeEnabled();
    await page.locator('#ti_override_rufname').fill('Mel');
    await page.locator('#ti_override_geschlecht').selectOption('d');
    await page.locator('#bu_override_save').click();
    // no restart in the test stack: the page reloads at once
    const row = page.locator('.dp-override-list tr', { hasText: 'Mallory Mustermann' });
    await expect(row).toContainText('Mel');
    await expect(row).toContainText('divers');
    // committed at once
    await expect(page.locator('.dp-uncommitted')).toHaveCount(0);

    // a LUSD export with the old values: no change, the difference shown
    await upload(page, [HEADER, 'Mustermann;Mallory;;05a;männlich;03.01.2010'].join('\r\n'), '2000-01-01');
    const preview = page.locator('#dp_preview');
    await expect(preview.locator('.dp-changed tr', { hasText: 'Mustermann' })).toHaveCount(0);
    const shown = preview.locator('.dp-overridden');
    await expect(shown).not.toHaveAttribute('open', '');
    await expect(shown.locator('.dp-count')).toHaveText('1');
    await expect(shown.locator('tr', { hasText: 'Mel Mustermann' })).toContainText(/Rufname\s*LUSD Mallory, Dashboard Mel/);
    await page.locator('#bu_discard_upload').click();

    // removed again: asks first
    await page.locator('.dp-override-list .bu_override_remove').first().click();
    const dialog = page.locator('.modal.show');
    await expect(dialog).toContainText('wie in der LUSD');
    await dialog.getByRole('button', { name: 'Entfernen' }).click();
    await expect(page.locator('.dp-override-list tr', { hasText: 'Mallory' })).toHaveCount(0);
  } finally {
    // committed at once: removed the same way, even if the test stopped early
    if (email) await page.request.post('/api/datenpflege/override', { data: { email, rufname: '', geschlecht: '' } });
  }
});

test('Rufname und Geschlecht im Dashboard nur mit der Rolle', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  const r = await api.post('/api/datenpflege/override', { data: { email: ACCOUNTS.schueler, rufname: 'X', geschlecht: '' } });
  expect(r.ok()).toBe(false);
  await api.dispose();
});

// The teachers' check of the draft (/schuelerliste, include/schuelerliste.rb):
// the class as in the draft, changes marked, every row »Stimmt« or a
// correction, missing students, then confirmed. Clarke leads 5a (and may see
// every class with the Datenpflege role); a teacher without a class sees
// nothing and can't check.
test('Schülerliste prüfen: Klassenleitung prüft, korrigiert und bestätigt', async ({ page, baseURL }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(90_000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  try {
    await page.goto('/datenpflege');
    await upload(page, [HEADER,
      'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
      'Mustermann;Elisabeth;Elli;05a;weiblich;02.01.2010',
      'Neu;Nele;;05a;weiblich;01.03.2014'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();

    await page.goto('/schuelerliste?klasse=5a');
    const cls = page.locator('.sl-class');
    await expect(cls.locator('h3')).toHaveText('Klasse 5a');
    const max = cls.locator('.sl-row', { hasText: 'Maximilian Mustermann' });
    await expect(max.locator('.sl-notes')).toContainText('Rufname: bisher Max');
    await expect(cls.locator('.sl-row', { hasText: 'Nele Neu' }).locator('.sl-notes')).toHaveText('neu');
    const mallory = cls.locator('.sl-leaving .sl-row', { hasText: 'Mallory' });
    await expect(mallory).toContainText('steht nicht mehr in der Liste');
    await expect(cls.locator('.sl-progress')).toContainText('0 von 4');
    await expect(page.locator('#bu_sl_confirm')).toBeDisabled();

    await cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_ok').click();
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.sl-done')).toContainText('stimmt');
    await cls.locator('.sl-row', { hasText: 'Nele Neu' }).locator('.bu_sl_ok').click();
    await expect(cls.locator('.sl-row', { hasText: 'Nele Neu' }).locator('.sl-done')).toBeVisible();

    // a correction: only what differs; Rufname in the dashboard only
    await max.locator('.bu_sl_correct').click();
    const modal = page.locator('#slCorrectModal');
    await expect(modal).toBeVisible();
    await expect(page.locator('#ti_sl_rufname')).toHaveValue('Maximilian');
    await page.locator('#ti_sl_rufname').fill('Max');
    await page.locator('#ti_sl_dashboard_only').check();
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-row', { hasText: 'Mustermann' }).first()).toBeVisible();
    await expect(cls.locator('.sl-corrected', { hasText: 'Rufname: Max (nur im Dashboard)' })).toHaveCount(1);

    // someone leaving who is still there
    await mallory.locator('.bu_sl_correct').click();
    await expect(page.locator('.sl-fields')).toBeHidden();
    await page.locator('#ti_sl_text').fill('ist noch in der Klasse');
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-leaving .sl-corrected')).toContainText('ist noch in der Klasse');

    // missing: entered
    await page.locator('#ti_sl_missing_name').fill('Paul Probe');
    await page.locator('#bu_sl_missing').click();
    await expect(cls.locator('.sl-missing li', { hasText: 'Paul Probe' })).toHaveCount(1);

    // all rows checked: confirm, and change again
    await expect(cls.locator('.sl-progress')).toContainText('4 von 4');
    await page.locator('#bu_sl_confirm').click();
    await expect(cls.locator('.sl-confirmed')).toContainText('Bestätigt am');
    await page.locator('#bu_sl_unconfirm').click();
    await expect(page.locator('#bu_sl_confirm')).toBeEnabled();

    // a teacher without a class: nothing to check
    const api = await playwrightRequest.newContext({ baseURL });
    await apiLogin(api, ACCOUNTS.teacher);
    expect((await api.post('/api/schuelerliste/check', { data: { klasse: '5a', student: ACCOUNTS.schueler, status: 'ok' } })).ok()).toBe(false);
    expect((await api.post('/api/schuelerliste/reset', { data: {} })).ok()).toBe(false);
    // (not released: no list for Klassenleitungen at all)
    const html = await (await api.get('/schuelerliste')).text();
    expect(html).toContain('Gerade gibt es keine neue Schülerliste zu prüfen');
    await api.dispose();
  } finally {
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});

// The Datenpflege's view of the check (/datenpflege): per class how far it
// is, a mail to the Klassenleitungen, the corrections – arrived ones marked
// by themselves (here: »nur im Dashboard« taken over as an override), others
// by hand; a new draft that changes a row asks again.
test('Schülerliste prüfen: Stand, Mail an die Klassenleitungen, Korrekturen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(120_000);
  const MAILPIT = process.env.MAILPIT_URL || 'http://localhost:8126';
  const mailQuery = encodeURIComponent(`to:"${ACCOUNTS.admin}" subject:"Schülerliste"`);
  await fetch(`${MAILPIT}/api/v1/search?query=${mailQuery}`, { method: 'DELETE' });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  const DRAFT = (elliBirthday: string) => [HEADER,
    'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
    `Mustermann;Elisabeth;Elli;05a;weiblich;${elliBirthday}`,
    'Neu;Nele;;05a;weiblich;01.03.2014'].join('\r\n');
  try {
    await page.goto('/datenpflege');
    await upload(page, DRAFT('02.01.2010'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    const row = page.locator('.dp-review-list tr[data-klasse="5a"]');
    await expect(row).toContainText('noch nicht geöffnet');
    await expect(row).toContainText('0 von 4');

    // the mail: one per Klassenleitung, with the link
    await page.locator('#ti_sl_deadline').fill('2099-12-01');
    await page.locator('#bu_sl_notify').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Senden' }).click();
    await expect(page.locator('.dp-review-list tr[data-klasse="5a"] td').nth(5)).not.toBeEmpty();
    let id = '';
    await expect(async () => {
      const { messages } = await (await fetch(`${MAILPIT}/api/v1/search?query=${mailQuery}`)).json();
      id = messages?.[0]?.ID || '';
      expect(id).not.toBe('');
    }).toPass({ timeout: 15_000 });
    const mail = await (await fetch(`${MAILPIT}/api/v1/message/${id}`)).json();
    expect(mail.Text).toContain('/schuelerliste?klasse=5a');
    expect(mail.Text).toContain('Bitte bis 01.12.2099');

    // the Klassenleitung opens it and checks
    await page.goto('/schuelerliste?klasse=5a');
    const cls = page.locator('.sl-class');
    await cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_ok').click();
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.sl-done')).toBeVisible();
    await cls.locator('.sl-row', { hasText: 'Maximilian' }).locator('.bu_sl_correct').click();
    await page.locator('#ti_sl_rufname').fill('Max');
    await page.locator('#ti_sl_dashboard_only').check();
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-corrected')).toContainText('nur im Dashboard');
    await page.locator('#ti_sl_missing_name').fill('Paul Probe');
    await page.locator('#bu_sl_missing').click();
    await expect(cls.locator('.sl-missing li')).toHaveCount(1);

    await page.goto('/datenpflege');
    await expect(row.locator('.dp-review-status')).toContainText('geöffnet am');
    await expect(row).toContainText('2 von 4');
    const corrections = page.locator('.dp-corrections');
    await expect(page.locator('.dp-corrections-title')).toContainText('2 offen von 2');
    // »nur im Dashboard«: taken over as an override – arrived
    await corrections.locator('tr', { hasText: 'Rufname: Max' }).locator('.bu_sl_take_override').click();
    await expect(corrections.locator('tr', { hasText: 'Rufname: Max' })).toContainText('angekommen');
    // missing: done by hand
    await corrections.locator('tr', { hasText: 'Paul Probe' }).locator('.bu_sl_done').click();
    await expect(corrections.locator('tr', { hasText: 'Paul Probe' })).toContainText('erledigt');
    await expect(page.locator('.dp-corrections-title')).toContainText('0 offen von 2');

    // a new draft changes Elli's birthday: her row is asked again
    await upload(page, DRAFT('03.01.2010'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/schuelerliste?klasse=5a');
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.sl-changed-row')).toHaveText('geändert seit deiner Prüfung');
  } finally {
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
    // the override was committed: removed again
    await page.request.post('/api/datenpflege/override', { data: { email: 'max.mustermann@mail.beispielschule.de', rufname: '', geschlecht: '' } });
  }
});

// A draft is for the Datenpflege only until it is released for the
// Klassenleitungen (a button, or the first mail): the export can be tried and
// fixed before anybody starts checking. A new draft keeps the release. The
// teacher here leads no class: released, the page says so; not released, it
// has no list at all.
test('Schülerliste prüfen: erst nach der Freigabe für Klassenleitungen', async ({ page, baseURL }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(90_000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  const teacher = await playwrightRequest.newContext({ baseURL });
  await apiLogin(teacher, ACCOUNTS.teacher);
  const teacherSees = async () => (await (await teacher.get('/schuelerliste')).text());
  const DRAFT = (n: string) => [HEADER, 'Mustermann;Max;;05a;männlich;01.01.2010', `Neu;${n};;05a;weiblich;01.03.2014`].join('\r\n');
  try {
    await page.goto('/datenpflege');
    await upload(page, DRAFT('Nele'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    const release = page.locator('.dp-release');
    await expect(release).toContainText('Noch nicht freigegeben');
    expect(await teacherSees()).toContain('Gerade gibt es keine neue Schülerliste zu prüfen');

    await page.locator('#bu_sl_release').click();
    await expect(release).toContainText('Für die Klassenleitungen freigegeben');
    expect(await teacherSees()).toContain('Du hast keine Klasse, die du prüfen kannst');

    // a new export as the draft: still released
    await upload(page, DRAFT('Nora'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    await expect(release).toContainText('Für die Klassenleitungen freigegeben');

    // taken back; the first mail releases it again
    await page.locator('#bu_sl_release').click();
    await expect(release).toContainText('Noch nicht freigegeben');
    expect(await teacherSees()).toContain('Gerade gibt es keine neue Schülerliste zu prüfen');
    expect((await page.request.post('/api/schuelerliste/notify', { data: {} })).ok()).toBe(true);
    await page.goto('/datenpflege');
    await expect(release).toContainText('Für die Klassenleitungen freigegeben');

    // the release is the Datenpflege's
    expect((await teacher.post('/api/schuelerliste/release', { data: { released: false } })).ok()).toBe(false);
  } finally {
    await teacher.dispose();
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});
