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
  for (const path of ['/api/datenpflege/schueler/upload', '/api/datenpflege/commit', '/api/datenpflege/rollback']) {
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
  await expect(page.locator('#dp_preview')).toBeEmpty();
  // no header row at all
  await upload(page, 'Name;Ort\nMustermann;Berlin\n', '2000-01-01');
  await expect(page.locator('#dp_message')).toContainText('Keine Kopfzeile mit Nachname und Klasse gefunden');
});

test('Datenpflege: übernehmen und zurücknehmen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  await upload(page, CHANGED, '2099-06-01');
  await expect(page.locator('#dp_future')).toBeVisible();
  await page.locator('#bu_apply').click();
  // no restart in the test stack: the page reloads at once
  const pending = page.locator('.dp-uncommitted');
  await expect(pending).toContainText('schueler/2099-06-01.TXT (neu)');
  await expect(page.locator('.dp-files tr', { hasText: '01.06.2099' })).toContainText('geplant');
  await page.locator('#bu_rollback').click();
  const dialog = page.locator('.modal.show');
  await expect(dialog).toContainText('nicht committeten Änderungen');
  await dialog.getByRole('button', { name: 'Zurücknehmen' }).click();
  await expect(page.locator('.dp-files tr', { hasText: '01.06.2099' })).toHaveCount(0);
  await expect(pending).toHaveCount(0);
});

test('Datenpflege: übernehmen und committen, eine vorhandene Liste nur mit Bestätigung ersetzen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  // another student each run, so that there is always something to commit
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
  await expect(page.locator('.dp-uncommitted')).toContainText('schueler/2099-12-31.TXT');
  await page.locator('#bu_commit').click();
  await expect(page.locator('.dp-uncommitted')).toHaveCount(0);
  const row = page.locator('.dp-files tr', { hasText: '31.12.2099' });
  await expect(row).toContainText('geplant');
  await expect(row).toContainText('Schüler:innen: 2099-12-31.TXT (über das Dashboard');
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
