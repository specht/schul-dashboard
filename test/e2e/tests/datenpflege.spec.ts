import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, Page, Locator } from '@playwright/test';

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
  await expect(preview.locator('.dp-columns summary')).toContainText('es fehlen: Schulform (kurz)');
  await expect(preview.locator('.dp-columns')).not.toContainText('Schlüssel');
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
  await expect(bob.locator('.dp-new')).toHaveText('-Neu');
  await expect(bob.locator('.dp-old')).toHaveCount(0);
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
// Decisions in the comparison: someone new in LUSD who isn't (any longer)
// at the school, someone in a class the dashboard doesn't know who is, and
// someone LUSD no longer lists who is still there – or gone at once.
test('Datenpflege: Entscheidungen im Vergleich (nicht mehr da, ist doch da, Klasse von Hand)', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(120_000);
  await login(page, ACCOUNTS.admin);
  const cleanup: (() => Promise<unknown>)[] = [];
  try {
    await page.goto('/datenpflege');
    await upload(page, [HEADER,
      'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
      'Mustermann;Elisabeth;Elli;05a;weiblich;02.01.2010',
      'Neu;Niko;;05a;männlich;01.03.2014',
      'Weg;Quinn;;q9;weiblich;02.03.2014',
      // an address too long: a decision of its own in the comparison, and
      // no reason for the other decisions to fail
      'Schneiderhahn-Oberhofer;Anna-Katharina;;05a;weiblich;08.08.2014'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    const preview = page.locator('#dp_preview');

    // new, but not here: kept out by name and birthday – only the draft
    // changes, the services don't read the data again (half a minute)
    const niko = preview.locator('.dp-added tr', { hasText: 'Niko Neu' });
    const nikoEmail = (await niko.locator('.bu_row_gone').getAttribute('data-email'))!;
    cleanup.push(() => page.request.post('/api/datenpflege/gone/remove', { data: { email: nikoEmail } }));
    const nikoGone = page.waitForResponse('**/api/datenpflege/row/gone');
    await niko.locator('.bu_row_gone').click();
    expect(await (await nikoGone).json()).toMatchObject({ ok: true, dashboard_changed: false });
    await expect(preview.locator('.dp-added tr', { hasText: 'Niko Neu' })).toHaveCount(0);
    await expect(preview.locator('.dp-manual tr', { hasText: 'Niko Neu' })).toContainText('als abgegangen vermerkt');

    // a class the dashboard doesn't know: here after all, in 5a
    const quinn = preview.locator('.dp-dropped tr', { hasText: 'Quinn Weg' });
    await quinn.locator('.ti_row_klasse').selectOption('5a');
    await expect(preview.locator('.dp-added tr', { hasText: 'Quinn Weg' })).toContainText('Klasse von Hand (LUSD: q9)');
    const hand = preview.locator('.dp-manual tr', { hasText: 'Quinn Weg' });
    await expect(hand).toContainText('Klasse von Hand statt q9');
    await hand.locator('.bu_row_klasse_remove').click();
    await expect(preview.locator('.dp-dropped tr', { hasText: 'Quinn Weg' })).toHaveCount(1);

    // no longer in LUSD, but still here: kept by hand with the address
    const mallory = preview.locator('.dp-removed tr', { hasText: 'Mallory' });
    const malloryEmail = (await mallory.locator('.bu_row_keep').getAttribute('data-email'))!;
    cleanup.push(() => page.request.post('/api/datenpflege/manual/remove', { data: { email: malloryEmail } }));
    await mallory.locator('.bu_row_keep').click();
    await expect(preview.locator('.dp-removed tr', { hasText: 'Mallory' })).toHaveCount(0);
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Mallory' })).toHaveCount(1);
    await page.request.post('/api/datenpflege/manual/remove', { data: { email: malloryEmail } });
    // … or gone at once (asked first)
    await page.goto('/datenpflege');
    cleanup.push(() => page.request.post('/api/datenpflege/gone/remove', { data: { email: malloryEmail } }));
    await preview.locator('.dp-removed tr', { hasText: 'Mallory' }).locator('.bu_row_gone_now').click();
    // in the dashboard now: this one has the data read again
    const malloryGone = page.waitForResponse('**/api/datenpflege/gone/add');
    await page.locator('.modal.show').getByRole('button', { name: 'Abmelden' }).click();
    expect(await (await malloryGone).json()).toMatchObject({ ok: true, dashboard_changed: true });
    await expect(preview.locator('.dp-removed tr', { hasText: 'Mallory' })).toHaveCount(0);
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-gone-list tr', { hasText: 'Mallory' })).toHaveCount(1);
  } finally {
    for (const undo of cleanup) await undo().catch(() => null);
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});

// After a change the services read the data again – about half a minute in
// production (not in the test stack, simulated here): a bar says so wherever
// the page is scrolled, the page rests, then it is reloaded and comes back to
// the same place with the comparison open (before, the note was out of sight
// and nothing seemed to happen).
test('Datenpflege: nach einer Änderung sichtbar warten, dann zurück an dieselbe Stelle', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(120_000);
  await page.setViewportSize({ width: 1280, height: 600 });
  await login(page, ACCOUNTS.admin);
  let malloryEmail = '';
  try {
    await page.goto('/datenpflege');
    await upload(page, [HEADER,
      'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
      'Mustermann;Elisabeth;Elli;05a;weiblich;02.01.2010',
      'Neu;Niko;;05a;männlich;01.03.2014'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    // the draft opens by itself
    await page.goto('/datenpflege');
    const preview = page.locator('#dp_preview');
    const mallory = preview.locator('.dp-removed tr', { hasText: 'Mallory' });
    const keep = mallory.locator('.bu_row_keep');
    malloryEmail = (await keep.getAttribute('data-email'))!;

    // the restart, simulated: the change answers that the data is read
    // again, the web service has a new time after a few polls
    const before = await page.locator('#data_loaded_at').textContent();
    let polls = 0;
    await page.route('**/api/datenpflege/row/keep', async (route) => {
      const response = await route.fetch();
      await route.fulfill({ response, json: { ...(await response.json()), reload: true } });
    });
    await page.route('**/api/data_status', (route) => route.fulfill({ json: { loaded_at: ++polls >= 2 ? 'neu' : before } }));

    await keep.scrollIntoViewIfNeeded();
    const y = await page.evaluate(() => window.scrollY);
    expect(y).toBeGreaterThan(300);
    await keep.click();
    const bar = page.getByTestId('dp-reloading');
    await expect(bar).toBeInViewport();
    await expect(bar).toContainText('etwa eine halbe Minute');
    await expect(page.locator('body')).toHaveClass(/dp-busy/);

    // reloaded by itself: the comparison open again, at the same place
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Mallory' })).toHaveCount(1, { timeout: 20_000 });
    await expect(bar).toHaveCount(0);
    await expect(page.locator('body')).not.toHaveClass(/dp-busy/);
    await expect(preview.locator('.dp-removed tr', { hasText: 'Mallory' })).toHaveCount(0);
    await expect(preview.locator('.dp-added, .dp-removed, .dp-manual').first()).toBeVisible();
    await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(y - 200);
  } finally {
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    if (malloryEmail) await page.request.post('/api/datenpflege/manual/remove', { data: { email: malloryEmail } }).catch(() => null);
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});

// Name particles: the dashboard keeps them behind the name (»Hofe, von«),
// LUSD writes them in front (»von Hofe«) – the same person, no change to
// check, and shown in front everywhere.
test('Datenpflege: »von« und »de« – gleich, ob vorn oder hinten', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(120_000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  const email = 'hans.von.hofe@mail.beispielschule.de';
  try {
    const added = await (await page.request.post('/api/datenpflege/manual/add', { data: {
      nachname: 'von Hofe', vornamen: 'Hans', klasse: '5a', geschlecht: 'm', geburtstag: '2014-03-03' } })).json();
    expect(added.ok).toBe(true);
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Hans von Hofe' })).toHaveCount(1);
    await upload(page, [HEADER,
      'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
      'von Hofe;Hans;;05a;männlich;03.03.2014'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    const preview = page.locator('#dp_preview');
    // the same person: not new, the entry by hand is now in LUSD
    await expect(preview.locator('.dp-added tr', { hasText: 'Hofe' })).toHaveCount(0);
    await expect(preview.locator('.dp-manual tr', { hasText: 'Hans von Hofe' })).toContainText('jetzt in der LUSD');
    await expect(preview.locator('.dp-changed tr', { hasText: 'Hofe' })).toHaveCount(0);
    // and nothing to check on the list: the particle in front, unchanged
    await page.goto('/schuelerliste?klasse=5a');
    const hans = page.locator('.sl-row', { hasText: 'Hofe' });
    await expect(hans.locator('td.sl-nachname')).toHaveText('von Hofe');
    await expect(hans).not.toHaveClass(/sl-row-changed|sl-row-added/);
    await expect(hans.locator('.dp-old, .dp-new')).toHaveCount(0);
  } finally {
    await page.request.post('/api/datenpflege/manual/remove', { data: { email } });
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
  }
});

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

    // the page opens with the draft shown (what still needs a decision at
    // once), not applied
    await page.goto('/datenpflege');
    await expect(page.locator('.dp-draft')).toContainText('lusd.csv');
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

// Students not yet in LUSD (added by hand) and students gone although LUSD
// still lists them (Parser.schueler_extras, schueler/zusaetzlich.yaml and
// abgaenge.yaml): both work on every list that is read, so an export that
// has them changes nothing – the added student keeps the address, the gone
// one stays out. Made-up students only.
const ALL = [
  HEADER,
  'Mustermann;Max;;05a;männlich;01.01.2010',
  'Mustermann;Elisabeth;Elli;05a;weiblich;02.01.2010',
  'Mustermann;Mallory;;05a;männlich;03.01.2010',
  'Mustermann;Alice;;11;weiblich;04.01.2010',
  'Mustermann;Bob;;12;männlich;05.01.2010',
];

test('Datenpflege: noch nicht in der LUSD, nicht mehr an der Schule', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one file for everybody');
  await login(page, ACCOUNTS.admin);
  let added = '';
  let gone = '';
  try {
    await page.goto('/datenpflege');
    // added by hand: an address at once
    await expect(page.locator('#bu_manual_add')).toBeDisabled();
    await page.locator('#ti_manual_nachname').fill('Zusatz');
    await page.locator('#ti_manual_vornamen').fill('Nora Lea');
    await page.locator('#ti_manual_klasse').selectOption('5b');
    await page.locator('#ti_manual_geschlecht').selectOption('w');
    await page.locator('#ti_manual_geburtstag').fill('2014-04-05');
    await page.locator('#ti_manual_notiz').fill('kommt von einer anderen Schule');
    await page.locator('#bu_manual_add').click();
    const row = page.locator('.dp-manual-list tr', { hasText: 'Nora Lea Zusatz' });
    await expect(row).toContainText('nora.zusatz');
    await expect(row).toContainText('kommt von einer anderen Schule');
    added = (await row.getAttribute('data-email'))!;
    // committed at once
    await expect(page.locator('.dp-uncommitted')).toHaveCount(0);
    // the same person twice: refused
    await page.locator('#ti_manual_nachname').fill('Zusatz');
    await page.locator('#ti_manual_vornamen').fill('Nora Lea');
    await page.locator('#ti_manual_klasse').selectOption('5b');
    await page.locator('#ti_manual_geschlecht').selectOption('w');
    await page.locator('#ti_manual_geburtstag').fill('2014-04-05');
    await page.locator('#bu_manual_add').click();
    await expect(page.locator('.api_messages, #dp_message').filter({ hasText: 'schon von Hand eingetragen' })).toBeVisible();
    await page.goto('/datenpflege');

    // gone: chosen from the list, asks first
    await page.locator('#ti_gone_student').fill('Mallory Mustermann (5a)');
    await page.locator('#ti_gone_seit').fill('2026-11-20');
    await page.locator('#bu_gone_add').click();
    const dialog = page.locator('.modal.show');
    await expect(dialog).toContainText('sofort nicht mehr an der Schule');
    await dialog.getByRole('button', { name: 'Vermerken' }).click();
    const goneRow = page.locator('.dp-gone-list tr', { hasText: 'Mallory Mustermann' });
    await expect(goneRow).toContainText('20.11.2026');
    gone = (await goneRow.getAttribute('data-email'))!;

    // an export still without Nora, still with Mallory: no change at all
    await upload(page, ALL.join('\r\n'), '2000-01-01');
    const preview = page.locator('#dp_preview');
    await expect(preview.locator('.dp-summary')).toContainText('5 Schüler:innen');
    // Mallory neither new nor leaving, Nora not leaving
    await expect(preview.locator('.dp-added .dp-count')).toHaveText('0');
    await expect(preview.locator('.dp-removed tr', { hasText: /Mallory|Nora/ })).toHaveCount(0);
    let manual = preview.locator('.dp-manual');
    await expect(manual).not.toHaveAttribute('open', '');
    await expect(manual.locator('tr', { hasText: 'Mallory Mustermann' })).toContainText('als abgegangen vermerkt');
    await page.locator('#bu_discard_upload').click();
    // Nora now in LUSD: she keeps the address, the entry ends with the list
    await upload(page, [...ALL, 'Zusatz;Nora Lea;;05b;weiblich;05.04.2014'].join('\r\n'), '2098-03-01');
    await expect(preview.locator('.dp-summary')).toContainText('6 Schüler:innen');
    await expect(preview.locator('.dp-added .dp-count')).toHaveText('0');
    await expect(preview.locator('.dp-changed tr', { hasText: 'Nora' })).toHaveCount(0);
    await expect(preview.locator('.dp-removed tr', { hasText: /Mallory|Nora/ })).toHaveCount(0);
    manual = preview.locator('.dp-manual');
    await expect(manual.locator('tr', { hasText: 'Nora Lea Zusatz' })).toContainText('jetzt in der LUSD');
    // applied for a day still to come: until then today's list needs both
    // entries – they stay (and with the list withdrawn as well)
    if (await page.locator('#dp_replace').isVisible()) await page.locator('#ti_replace').check();
    await page.locator('#bu_apply').click();
    const planned = page.locator('.dp-files tr', { hasText: '01.03.2098' });
    await expect(planned).toContainText('geplant');
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Nora Lea Zusatz' })).toBeVisible();
    await expect(page.locator('.dp-gone-list tr', { hasText: 'Mallory Mustermann' })).toBeVisible();
    await planned.locator('.bu_delete_list').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Löschen' }).click();
    await expect(page.locator('.dp-files tr', { hasText: '01.03.2098' })).toHaveCount(0);
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Nora Lea Zusatz' })).toBeVisible();

    // taken back and removed (each asks first)
    await goneRow.locator('.bu_gone_remove').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Zurücknehmen' }).click();
    await expect(page.locator('.dp-gone-list tr', { hasText: 'Mallory' })).toHaveCount(0);
    await page.locator('.dp-manual-list tr', { hasText: 'Nora Lea Zusatz' }).locator('.bu_manual_remove').click();
    await expect(page.locator('.modal.show')).toContainText('kein Konto');
    await page.locator('.modal.show').getByRole('button', { name: 'Entfernen' }).click();
    await expect(page.locator('.dp-manual-list tr', { hasText: 'Nora' })).toHaveCount(0);
  } finally {
    // committed at once: removed the same way, even if the test stopped early
    if (gone) await page.request.post('/api/datenpflege/gone/remove', { data: { email: gone } });
    if (added) await page.request.post('/api/datenpflege/manual/remove', { data: { email: added } });
    await page.request.post('/api/datenpflege/schueler/delete_list', { data: { date: '2098-03-01' } });
  }
});

// Abroad for a while: LUSD keeps them in their class; the dashboard keeps the
// account but takes them out of classes, courses, lists and report cards
// until the return date (the services don't read the data again in the test
// stack: the entry and its answer are checked here, the date in
// parser_abroad_test.rb)
test('Datenpflege: im Ausland, zurück ab einem Tag', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'shared data');
  await login(page, ACCOUNTS.admin);
  let email = '';
  try {
    await page.goto('/datenpflege');
    const section = page.locator('.dp-manual-abroad');
    await expect(section.locator('h5')).toHaveText('Im Ausland');
    await section.locator('#ti_abroad_student').fill('Alice Mustermann (11)');
    await expect(section.locator('#bu_abroad_add')).toBeEnabled();
    await section.locator('#ti_abroad_zurueck').fill('2099-02-01');
    await section.locator('#ti_abroad_notiz').fill('Austausch');
    // (the page reloads at once: the answer read on its way)
    let added: { ok?: boolean, dashboard_changed?: boolean } = {};
    await page.route('**/api/datenpflege/abroad/add', async (route) => {
      const response = await route.fetch();
      added = await response.json();
      await route.fulfill({ response });
    });
    await section.locator('#bu_abroad_add').click();
    await expect(page.locator('.modal.show')).toContainText('in keiner Klasse');
    await page.locator('.modal.show').getByRole('button', { name: 'Vermerken' }).click();
    // out of the class now: the services read the data again
    await expect.poll(() => added).toMatchObject({ ok: true, dashboard_changed: true });
    await page.unrouteAll({ behavior: 'ignoreErrors' });
    const row = page.locator('.dp-abroad-list tr', { hasText: 'Alice' });
    await expect(row).toContainText('01.02.2099');
    await expect(row).toContainText('Austausch');
    email = (await row.getAttribute('data-email'))!;
    // a return date that has come already is refused
    const past = await page.request.post('/api/datenpflege/abroad/add', { data: { email, zurueck: '2000-01-01' } });
    expect(past.ok()).toBe(false);
    // back: at once
    await row.getByRole('button', { name: 'Wieder da' }).click();
    await page.locator('.modal.show').getByRole('button', { name: 'Wieder da' }).click();
    await expect(page.locator('.dp-abroad-list tr', { hasText: 'Alice' })).toHaveCount(0);
    email = '';
  } finally {
    if (email) await page.request.post('/api/datenpflege/abroad/remove', { data: { email } });
  }
});

test('Noch nicht in der LUSD und nicht mehr an der Schule nur mit der Rolle', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  const add = await api.post('/api/datenpflege/manual/add', { data: { nachname: 'X', vornamen: 'Y', klasse: '5a', geschlecht: 'w', geburtstag: '2014-01-01' } });
  expect(add.ok()).toBe(false);
  const away = await api.post('/api/datenpflege/gone/add', { data: { email: ACCOUNTS.schueler } });
  expect(away.ok()).toBe(false);
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
      'Mustermann;Elisabeth Anna;Elli;05a;weiblich;02.01.2010',
      'Neu;Nele;;05a;weiblich;01.03.2014'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();

    await page.goto('/schuelerliste?klasse=5a');
    const cls = page.locator('.sl-class');
    await expect(cls.locator('h3')).toHaveText('Klasse 5a');
    const max = cls.locator('.sl-row', { hasText: 'Maximilian Mustermann' });
    // changes like a diff: the old Rufname struck through, the new one marked
    await expect(max).toHaveClass(/sl-row-changed/);
    // (Nachname, Rufname and Vornamen each in a column; only what differs
    // is marked, inline)
    await expect(page.locator('.sl-table').first().locator('thead th:visible')).toHaveText(
      ['Nr.', 'Nachname', 'Rufname', 'Vornamen', 'Geschlecht', 'Geburtstag', 'Bildungsgang', '']);
    // numbered, so a missing student shows
    await expect(cls.locator('.sl-table').first().locator('tbody tr.sl-row td.sl-nr')).toHaveText(['1.', '2.', '3.']);
    await expect(max.locator('td.sl-rufname .dp-old')).toHaveText('Max');
    await expect(max.locator('td.sl-rufname .dp-new')).toHaveText('Maximilian');
    await expect(max.locator('td.sl-nachname')).toHaveText('Mustermann');
    await expect(max.locator('td.sl-nachname .dp-old, td.sl-nachname .dp-new')).toHaveCount(0);
    // a second first name: just that name in green, nothing struck through
    const elli = cls.locator('.sl-row', { hasText: 'Elli' });
    await expect(elli.locator('td.sl-vornamen')).toHaveText('Elisabeth Anna');
    await expect(elli.locator('td.sl-vornamen .dp-new')).toHaveText('Anna');
    await expect(elli.locator('.dp-old')).toHaveCount(0);
    // the marks readable light and dark: their own ink on their own ground
    // (an inherited ink on a faint tint was hard to read, above all on phones)
    for (const dark of [false, true]) {
      const marks = await page.evaluate((dark) => {
        document.body.classList.toggle('dark', dark);
        const rgb = (c: string) => (c.match(/[\d.]+/g) || []).slice(0, 3).map(Number);
        const lum = (c: string) => {
          const [r, g, b] = rgb(c).map(v => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
          return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        };
        return [...document.querySelectorAll('.sl-table .dp-old, .sl-table .dp-new')].slice(0, 6).map(el => {
          const s = getComputedStyle(el);
          const [a, b] = [lum(s.color), lum(s.backgroundColor)].sort((x, y) => y - x);
          return { contrast: (a + 0.05) / (b + 0.05), own: s.color !== getComputedStyle(el.parentElement!).color, opaque: !/rgba\(.*,\s*0?\.\d+\)$/.test(s.backgroundColor) };
        });
      }, dark);
      expect(marks.length).toBeGreaterThan(1);
      for (const m of marks) {
        expect(m.contrast, `dark=${dark}`).toBeGreaterThanOrEqual(4.5);
        expect(m.own, `dark=${dark}`).toBe(true);
        expect(m.opaque, `dark=${dark}`).toBe(true);
      }
    }
    await page.evaluate(() => document.body.classList.remove('dark'));
    const nele = cls.locator('.sl-row', { hasText: 'Nele Neu' });
    await expect(nele).toHaveClass(/sl-row-added/);
    await expect(nele.locator('.sl-badge-added:visible')).toHaveText('+ neu');
    const mallory = cls.locator('.sl-leaving .sl-row', { hasText: 'Mallory' });
    await expect(mallory).toHaveClass(/sl-row-removed/);
    await expect(mallory.locator('.sl-badge-removed')).toHaveText('− steht nicht mehr in der Liste');
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
    // what »nur im Dashboard« is for, explained next to it
    await expect(page.locator('#sl_dashboard_only_hint')).toContainText('noch nicht amtlich');
    await page.locator('#ti_sl_dashboard_only').check();
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-row', { hasText: 'Mustermann' }).first()).toBeVisible();
    // the correction in a row of its own below, the value exactly in its
    // column; the student's row stays one line; one's own check without a name
    const fix = cls.locator('tr.sl-note-row td.sl-fix-rufname');
    await expect(fix).toHaveCount(1);
    await expect(fix.locator('.sl-fix')).toHaveText('Max');
    await expect(fix).toContainText('(nur im Dashboard)');
    const left = async (l: Locator) => (await l.boundingBox())!.x;
    expect(Math.abs(await left(fix) - await left(max.locator('td.sl-rufname')))).toBeLessThan(1);
    const rowHeight = (name: string) => cls.locator('.sl-row', { hasText: name }).evaluate((tr) => tr.getBoundingClientRect().height);
    expect(await rowHeight('Maximilian')).toBeLessThan(await rowHeight('Nele') + 2);
    await expect(cls.locator('.sl-by')).toHaveCount(0);

    // someone leaving who is still there
    await mallory.locator('.bu_sl_correct').click();
    await expect(page.locator('.sl-fields')).toBeHidden();
    await page.locator('#ti_sl_text').fill('ist noch in der Klasse');
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-leaving .sl-corrected')).toContainText('ist noch in der Klasse');
    // a correction taken back: asked first, then the row is open again
    await mallory.locator('.bu_sl_withdraw').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Abbrechen' }).click();
    await expect(cls.locator('.sl-leaving .sl-corrected')).toHaveCount(1);
    await mallory.locator('.bu_sl_withdraw').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Zurücknehmen' }).click();
    await expect(mallory.locator('.bu_sl_ok')).toBeVisible();
    await expect(cls.locator('.sl-leaving .sl-corrected')).toHaveCount(0);
    await expect(cls.locator('.sl-progress')).toContainText('3 von 4');
    await mallory.locator('.bu_sl_ok').click();
    await expect(mallory.locator('.sl-done')).toBeVisible();

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

    // the Datenpflege's comparison of the draft: what the Klassenleitung
    // confirmed (the new one is here, the leaving one goes) moves out of
    // »Neu« and »Nicht mehr dabei« into closed sections
    await page.goto('/datenpflege');
    const preview = page.locator('#dp_preview');
    await expect(preview.locator('.dp-added-ok tr', { hasText: 'Nele Neu' })).toHaveCount(1);
    await expect(preview.locator('.dp-added tr', { hasText: 'Nele Neu' })).toHaveCount(0);
    await expect(preview.locator('.dp-removed-ok tr', { hasText: 'Mallory' })).toHaveCount(1);
    await expect(preview.locator('.dp-removed tr', { hasText: 'Mallory' })).toHaveCount(0);

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
  const DRAFT = (elliBirthday: string, neleRufname = '') => [HEADER,
    'Mustermann;Max;Maximilian;05a;männlich;01.01.2010',
    `Mustermann;Elisabeth;Elli;05a;weiblich;${elliBirthday}`,
    `Neu;Nele;${neleRufname};05a;weiblich;01.03.2014`].join('\r\n');
  try {
    await page.goto('/datenpflege');
    await upload(page, DRAFT('02.01.2010'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    const row = page.locator('.dp-review-list tr[data-klasse="5a"]');
    // the table takes the width it needs on a wide screen: nothing cut off
    // or to scroll (the page was 60em narrow)
    await page.setViewportSize({ width: 1600, height: 900 });
    const fits = await page.locator('.dp-review-list').evaluate((t) => t.closest('.dp-scroll')!.scrollWidth <= t.closest('.dp-scroll')!.clientWidth + 1);
    expect(fits).toBe(true);
    expect(await page.locator('.dp-review-list').evaluate((t) => t.closest('.dp-scroll')!.clientWidth)).toBeGreaterThan(1000);
    await expect(row).toContainText('noch nicht geöffnet');
    // Elli is in the draft as in the dashboard: no row to check on its own
    await expect(row).toContainText('0 von 3, 1 unverändert');
    // how far each list is, coloured, and all of them in one bar
    await expect(row).toHaveAttribute('data-state', 'waiting');
    await expect(page.locator('.dp-review-legend')).toContainText('noch nicht geöffnet');
    await expect(page.locator('.dp-review-bar .dp-seg-waiting')).toHaveCount(1);

    // the mail: one per Klassenleitung, with the link
    await page.locator('#ti_sl_deadline').fill('2099-12-01');
    await page.locator('#bu_sl_notify').click();
    // first a preview of each mail, exactly as it goes out
    await expect(page.locator('#dpNotifyModal')).toBeVisible();
    await expect(page.locator('#dp_notify_to option')).toContainText([/Clarke.*5a/]);
    await expect(page.locator('#dp_notify_subject')).toContainText('Bitte prüf die neue Schülerliste deiner Klasse');
    await expect(page.locator('#dp_notify_body')).toContainText('/schuelerliste?klasse=5a');
    await expect(page.locator('#dp_notify_body')).toContainText('Bitte bis 01.12.2099');
    await expect(page.locator('#dp_notify_body')).toContainText('mit dem Rufnamen erscheint');
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
    // unchanged: no »Stimmt« (the list's confirmation covers it), a correction still possible
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_ok')).toHaveCount(0);
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_correct')).toBeVisible();
    await expect(cls.locator('.sl-progress')).toContainText('0 von 3 markierten Zeilen geprüft, 1 unverändert');
    await cls.locator('.sl-leaving .sl-row', { hasText: 'Mallory' }).locator('.bu_sl_ok').click();
    await expect(cls.locator('.sl-leaving .sl-row', { hasText: 'Mallory' }).locator('.sl-done')).toBeVisible();
    await cls.locator('.sl-row', { hasText: 'Maximilian' }).locator('.bu_sl_correct').click();
    await page.locator('#ti_sl_rufname').fill('Max');
    await page.locator('#ti_sl_dashboard_only').check();
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('tr.sl-note-row td.sl-fix-rufname')).toContainText('nur im Dashboard');
    await page.locator('#ti_sl_missing_name').fill('Paul Probe');
    await page.locator('#bu_sl_missing').click();
    await expect(cls.locator('.sl-missing li')).toHaveCount(1);

    await page.goto('/datenpflege');
    await expect(row.locator('.dp-review-status')).toContainText('geöffnet am');
    await expect(row).toContainText('2 von 3, 1 unverändert');
    await expect(row).toHaveAttribute('data-state', 'working');
    await expect(row.locator('.dp-review-status')).toContainText('in Arbeit');
    await expect(row.locator('.dp-mini-working > span')).toHaveAttribute('style', /width: 67%/);
    const corrections = page.locator('.dp-corrections');
    await expect(page.locator('.dp-corrections-title')).toContainText('2 offen von 2');
    // by what is to do: »nur im Dashboard« and »fehlt« apart; what the
    // Klassenleitung confirmed only counted (nothing to do in LUSD)
    await expect(page.locator('.dp-corrections-dashboard tr', { hasText: 'Max (nur im Dashboard)' })).toHaveCount(1);
    await expect(page.locator('.dp-corrections-missing tr', { hasText: 'Paul Probe' })).toHaveCount(1);
    await expect(page.locator('.dp-corrections-box > .dp-hint')).toContainText('Bestätigt haben sie 1 Zeile');
    await expect(page.locator('.dp-corrections-box .dp-progress')).toHaveAttribute('aria-valuenow', '0');
    // »nur im Dashboard«: taken over as an override – arrived
    await corrections.locator('tr', { hasText: 'Max (nur im Dashboard)' }).locator('.bu_sl_take_override').click();
    await expect(corrections.locator('tr', { hasText: 'Max (nur im Dashboard)' })).toContainText('angekommen');
    // missing: into the form for students not yet in LUSD, or done by hand
    await corrections.locator('tr', { hasText: 'Paul Probe' }).locator('.bu_sl_take_missing').click();
    await expect(page.locator('#ti_manual_nachname')).toHaveValue('Probe');
    await expect(page.locator('#ti_manual_vornamen')).toHaveValue('Paul');
    // the to-do list: »Geht nicht« with the reason (the teacher sees it),
    // open again, then done
    const paul = corrections.locator('tr', { hasText: 'Paul Probe' });
    // ticked off in place, without a reload (a mark on the page stays)
    await page.evaluate(() => { (window as unknown as { dp_mark: boolean }).dp_mark = true; });
    await paul.locator('.bu_sl_wontfix').click();
    await page.locator('#bu_wontfix_save').click();
    await expect(page.locator('#dpWontfixModal')).toBeVisible();
    await page.locator('#ti_wontfix_reason').fill('ist an keiner Schule gemeldet');
    await page.locator('#bu_wontfix_save').click();
    await expect(paul).toContainText('geht nicht');
    await expect(paul.locator('.dp-wontfix')).toHaveText('ist an keiner Schule gemeldet');
    await expect(page.locator('.dp-corrections-title')).toContainText('0 offen von 2');
    expect(await (await page.request.get('/schuelerliste?klasse=5a')).text()).toContain('Datenpflege: geht nicht – ist an keiner Schule gemeldet');
    await paul.locator('.bu_sl_done').click();
    await expect(page.locator('.dp-corrections-title')).toContainText('1 offen von 2');
    await corrections.locator('tr', { hasText: 'Paul Probe' }).locator('.bu_sl_done').click();
    await expect(corrections.locator('tr', { hasText: 'Paul Probe' })).toContainText('erledigt');
    await expect(corrections.locator('tr', { hasText: 'Paul Probe' }).locator('.bu_sl_take_missing')).toHaveCount(0);
    await expect(page.locator('.dp-corrections-title')).toContainText('0 offen von 2');
    expect(await page.evaluate(() => (window as unknown as { dp_mark?: boolean }).dp_mark)).toBe(true);
    await expect(page.locator('.dp-corrections-box .dp-progress')).toHaveAttribute('aria-valuenow', '2');

    // »nicht mehr an der Schule«: gone in the dashboard at once, without
    // waiting for LUSD – then the correction has arrived
    await page.goto('/schuelerliste?klasse=5a');
    await cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_correct').click();
    await page.locator('#ti_sl_gone').check();
    await page.locator('#ti_sl_gone_since').fill('2026-11-20');
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('.sl-corrected', { hasText: 'nicht mehr an der Schule' })).toHaveCount(1);
    await page.goto('/datenpflege');
    await corrections.locator('tr', { hasText: 'nicht mehr an der Schule' }).locator('.bu_sl_take_gone').click();
    await expect(page.locator('.modal.show')).toContainText('sofort nicht mehr an der Schule');
    await page.locator('.modal.show').getByRole('button', { name: 'Vermerken' }).click();
    const elliGone = page.locator('.dp-gone-list tr', { hasText: 'Elisabeth Mustermann' });
    await expect(elliGone).toContainText('20.11.2026');
    await expect(corrections.locator('tr', { hasText: 'nicht mehr an der Schule' })).toContainText('angekommen');
    await elliGone.locator('.bu_gone_remove').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Zurücknehmen' }).click();
    await expect(page.locator('.dp-gone-list tr', { hasText: 'Elisabeth' })).toHaveCount(0);

    // a correction for LUSD: the Rufname
    await page.goto('/schuelerliste?klasse=5a');
    await cls.locator('.sl-row', { hasText: 'Nele' }).locator('.bu_sl_correct').click();
    await page.locator('#ti_sl_rufname').fill('Nelly');
    await page.locator('#bu_save_sl_correction').click();
    await expect(cls.locator('tr.sl-note-row td.sl-fix-rufname', { hasText: 'Nelly' })).toHaveCount(1);
    // (Max as well by now: his Rufname, taken over as an override, is the dashboard's)
    await expect(cls.locator('.sl-confirm')).toContainText('Alles Markierte geprüft. Mit »Liste bestätigen« bestätigst du auch die 2 unveränderten Zeilen.');

    // done in LUSD (ticked) – but the next export still has the old Rufname:
    // marked, to look at again
    await page.goto('/datenpflege');
    const neleTodo = page.locator('.dp-corrections-lusd tr', { hasText: 'Nelly' });
    await neleTodo.locator('.bu_sl_done').first().click();
    await expect(neleTodo).toContainText('erledigt, wartet auf den nächsten Export');
    await page.waitForTimeout(1100);
    await upload(page, DRAFT('02.01.2010'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    await expect(neleTodo).toContainText('erledigt, aber im neuen Export noch anders');
    await expect(page.locator('.dp-corrections-box .dp-late')).toContainText('im neuen Export noch anders');

    // a new draft changes Elli's birthday: her row is asked again; it also
    // has Nele's Rufname as corrected – that counts as done, not asked again
    await page.goto('/datenpflege');
    await upload(page, DRAFT('03.01.2010', 'Nelly'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    await expect(neleTodo).toContainText('angekommen');
    // (Paul was ticked as done, but the export doesn't have him either)
    await expect(corrections.locator('tr', { hasText: 'Paul Probe' })).toContainText('erledigt, aber im neuen Export noch anders');
    await page.goto('/schuelerliste?klasse=5a');
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('xpath=following-sibling::tr[1]').locator('.sl-changed-row')).toHaveText('geändert seit deiner Prüfung');
    const nele = cls.locator('.sl-row', { hasText: 'Nelly' });
    await expect(nele.locator('.bu_sl_ok')).toHaveCount(0);
    await expect(nele.locator('xpath=following-sibling::tr[1]').locator('.sl-fix-label')).toHaveText('Korrektur übernommen');
    // Elli changed now: the one row to check again
    await expect(cls.locator('.sl-confirm')).toContainText('Noch 1 markierte Zeile zu prüfen.');
    await expect(cls.locator('.sl-row', { hasText: 'Elli' }).locator('.bu_sl_ok')).toHaveCount(1);

    // a remark: read, nothing to change – the Klassenleitung sees that
    const malloryKey = await cls.locator('.sl-leaving .sl-row', { hasText: 'Mallory' }).getAttribute('data-student');
    expect((await page.request.post('/api/schuelerliste/check', { data: { klasse: '5a', student: malloryKey, status: 'correction', text: 'zieht nach Hamburg' } })).ok()).toBe(true);
    await page.goto('/datenpflege');
    const remark = page.locator('.dp-corrections-note tr', { hasText: 'zieht nach Hamburg' });
    await remark.getByRole('button', { name: 'Nichts zu tun' }).click();
    await expect(remark).toContainText('nichts zu tun');
    expect(await (await page.request.get('/schuelerliste?klasse=5a')).text()).toContain('Datenpflege: gelesen, nichts zu ändern');
  } finally {
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
    // the override was committed: removed again
    await page.request.post('/api/datenpflege/override', { data: { email: 'max.mustermann@mail.beispielschule.de', rufname: '', geschlecht: '' } });
    const extras = await page.request.get('/datenpflege');
    const elli = /data-email='([^']+)'[^>]*>\s*<td>Elisabeth Mustermann/.exec(await extras.text());
    if (elli) await page.request.post('/api/datenpflege/gone/remove', { data: { email: elli[1] } });
  }
});

// 11 and 12: no tutor data yet – the teachers of the Leistungskurse check, a
// list per LK (here LA-L108 by Clarke, with Alice in 11 and Bob in 12), with
// a note why they may see students who aren't their tutees; who is in no LK
// stays with the year, for the Datenpflege.
test('Schülerliste prüfen: in 11 und 12 die Lehrkräfte der Leistungskurse', async ({ page, baseURL }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(90_000);
  const MAILPIT = process.env.MAILPIT_URL || 'http://localhost:8126';
  const mailQuery = encodeURIComponent(`to:"${ACCOUNTS.admin}" subject:"Schülerliste"`);
  await fetch(`${MAILPIT}/api/v1/search?query=${mailQuery}`, { method: 'DELETE' });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  let bobEmail = '';
  let group = '';
  try {
    await page.goto('/datenpflege');
    await upload(page, [HEADER,
      'Mustermann;Alice;;11;weiblich;04.01.2010',
      'Mustermann;Bob;;12;männlich;05.01.2010',
      'Neu;Olaf;;11;männlich;06.06.2009'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    await page.goto('/datenpflege');
    const lk = page.locator('.dp-review-list tr[data-klasse^="lk:"]');
    await expect(lk).toHaveCount(1);
    await expect(lk.locator('td').first()).toContainText(/^LK /);
    await expect(lk).toContainText('Clarke');
    // Alice and Bob as in the dashboard: nothing to check on its own
    await expect(lk).toContainText('2 unverändert');
    // the new student is in no LK: with the year, nobody checks it but us
    const year = page.locator('.dp-review-list tr[data-klasse="11"]');
    await expect(year).toContainText('11 ohne LK');
    await expect(year).toContainText('keine');
    // nobody gets a mail for it: not »noch nicht geöffnet«
    await expect(year.locator('.dp-review-status')).toHaveText('niemand zuständig');
    await expect(year).toHaveAttribute('data-state', 'nobody');
    group = (await lk.getAttribute('data-klasse'))!;

    // the LK teacher's list: why they may see students who aren't their tutees
    await page.goto('/schuelerliste?klasse=' + encodeURIComponent(group));
    const cls = page.locator('.sl-class');
    await expect(cls.locator('h3')).toContainText(/^LK /);
    await expect(cls.locator('.sl-lk-note')).toContainText('noch keine Daten, wer Tutor:in ist');
    await expect(cls.locator('.sl-row', { hasText: 'Alice' })).toBeVisible();
    await expect(cls.locator('.sl-row', { hasText: 'Bob' })).toBeVisible();
    await expect(cls.locator('.sl-row', { hasText: 'Olaf' })).toHaveCount(0);
    await expect(cls.locator('.bu_sl_ok')).toHaveCount(0);
    await expect(cls.locator('.sl-progress')).toContainText('Keine Änderungen: 2 Zeilen stehen schon so im Dashboard');
    await expect(page.locator('#bu_sl_confirm')).toBeEnabled();
    await expect(page.locator('#sl_klasse option', { hasText: /^LK / })).toHaveCount(1);

    // the tutees: the LK's teachers tick them (kept after the switch)
    await expect(cls.locator('.sl-lk-note')).toContainText('Spalte »Tutor:in«');
    await expect(cls.locator('.sl-table thead th:visible')).toContainText(['Tutor:in']);
    await expect(cls.locator('.sl-tutor-count')).toHaveText('0');
    const bobRow = cls.locator('.sl-row', { hasText: 'Bob' });
    bobEmail = (await bobRow.getAttribute('data-student'))!;
    await bobRow.locator('.ti_sl_tutor').check();
    await expect(cls.locator('.sl-tutor-count')).toHaveText('1');
    await expect(cls.locator('.sl-row', { hasText: 'Bob' }).locator('.ti_sl_tutor')).toBeChecked();
    await expect(cls.locator('.sl-row', { hasText: 'Alice' }).locator('.ti_sl_tutor')).not.toBeChecked();
    // a teacher not in the LK can't
    const other = await playwrightRequest.newContext({ baseURL });
    await apiLogin(other, ACCOUNTS.teacher);
    expect((await other.post('/api/schuelerliste/tutor', { data: { klasse: group, student: bobEmail, tutor: true } })).ok()).toBe(false);
    expect((await other.get('/api/datenpflege/tutoren.csv')).ok()).toBe(false);
    await other.dispose();
    // the Datenpflege: who is whose tutor, also as CSV for LUSD
    await page.goto('/datenpflege');
    const tutors = page.locator('.dp-tutors');
    await expect(tutors.locator('summary')).toContainText('Tutor:innen in 11 und 12');
    await tutors.locator('summary').click();
    await expect(tutors.locator('tr', { hasText: 'Bob' })).toContainText('Clarke');
    await expect(tutors.locator('tr', { hasText: 'Alice' })).toContainText('noch offen');
    const csv = await (await page.request.get('/api/datenpflege/tutoren.csv')).text();
    const bobLine = csv.split('\r\n').find((l) => l.includes(bobEmail))!;
    expect(bobLine).toContain('Clarke');
    expect(csv.split('\r\n')[0]).toContain('Tutor:in');

    // the mail: class and LK, with the note
    await page.goto('/datenpflege');
    await page.locator('#bu_sl_notify').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Senden' }).click();
    await expect(lk.locator('td').nth(5)).not.toBeEmpty();
    let id = '';
    await expect(async () => {
      const { messages } = await (await fetch(`${MAILPIT}/api/v1/search?query=${mailQuery}`)).json();
      id = messages?.[0]?.ID || '';
      expect(id).not.toBe('');
    }).toPass({ timeout: 15_000 });
    const mail = await (await fetch(`${MAILPIT}/api/v1/message/${id}`)).json();
    expect(mail.Subject).toBe('Bitte prüf die neue Schülerliste deiner Klasse und Leistungskurse');
    expect(mail.Text).toContain('/schuelerliste?klasse=' + encodeURIComponent(group).replace(/%20/g, '+'));
    expect(mail.Text).toContain('noch keine Daten, wer Tutor:in ist');
  } finally {
    if (bobEmail) await page.request.post('/api/schuelerliste/tutor', { data: { klasse: group, student: bobEmail, tutor: false } });
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
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

// The start page (new design): a Klassenleitung finds the list of the class in
// »Zu erledigen« from its release until it is confirmed – with the rows still
// open and the deadline of the mail. Clarke leads 5a.
test('Schülerliste prüfen: in »Zu erledigen« für die Klassenleitung', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one draft for everybody');
  test.setTimeout(90_000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/schuelerliste/reset', { data: {} });
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/datenpflege');
    // Clarke leads 5a and teaches the LK LA-L108 (Alice in 11, Bob in 12)
    await upload(page, [HEADER, 'Mustermann;Max;;05a;männlich;01.01.2010', 'Neu;Nele;;05a;weiblich;01.03.2014',
      'Mustermann;Alice;;11;weiblich;04.01.2010', 'Mustermann;Bob;;12;männlich;05.01.2010'].join('\r\n'), '2000-01-01');
    await page.locator('#bu_keep_draft').click();
    await expect(page.locator('#dp_is_draft')).toBeVisible();
    const todo = page.locator('.pv-todo-row[data-kind="schuelerliste"]');
    // not released: nothing on the start page
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event, #pv_agenda').first()).toBeVisible();
    await expect(todo).toHaveCount(0);
    // the mail releases it, with a deadline
    expect((await page.request.post('/api/schuelerliste/notify', { data: { deadline: '2099-12-01' } })).ok()).toBe(true);
    await page.goto('/');
    await expect(todo).toContainText('Schülerliste prüfen');
    await expect(todo).toContainText(/Klasse 5a: noch \d+ von \d+ Zeilen/);
    await expect(todo).toContainText(/LK [^:]+: nur noch bestätigen/);
    await expect(todo).toContainText('bitte bis 01.12.2099');
    // two lists: to the page, the class first
    await todo.getByRole('link', { name: 'Prüfen' }).or(todo.getByRole('button', { name: 'Prüfen' })).first().click();
    await expect(page).toHaveURL(/\/schuelerliste$/);
    const cls = page.locator('.sl-class');
    await expect(cls.locator('h3')).toHaveText('Klasse 5a');
    const lk = await page.locator('#sl_klasse option', { hasText: /^LK / }).getAttribute('value');
    // every row checked and confirmed, in both lists: gone
    const checkAll = async () => {
      while (await cls.locator('.bu_sl_ok').count() > 0) {
        const n = await cls.locator('.bu_sl_ok').count();
        await cls.locator('.bu_sl_ok').first().click();
        await expect(cls.locator('.bu_sl_ok')).toHaveCount(n - 1);
      }
      await page.locator('#bu_sl_confirm').click();
      await expect(cls.locator('.sl-confirmed')).toBeVisible();
    };
    await checkAll();
    await page.goto('/');
    await expect(todo).not.toContainText('Klasse 5a');
    await expect(todo).toContainText(/LK [^:]+: nur noch bestätigen/);
    await page.goto('/schuelerliste?klasse=' + encodeURIComponent(lk!));
    await checkAll();
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event, #pv_agenda').first()).toBeVisible();
    await expect(todo).toHaveCount(0);
  } finally {
    await page.request.post('/api/schuelerliste/reset', { data: {} });
    const d = await (await page.request.post('/api/datenpflege/schueler/draft', { data: {} })).json().catch(() => ({}));
    if (d.ok && d.token) await page.request.post('/api/datenpflege/schueler/discard', { data: { token: d.token } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
