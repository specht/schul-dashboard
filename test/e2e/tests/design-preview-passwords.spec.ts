import { test, expect, login, apiLogin, dashboardDialog, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, type APIRequestContext, type Page, type TestInfo } from '@playwright/test';

// Neues Design (Vorschau): Passwörter (/passwoerter) as a calm form page – a
// clear heading hierarchy, labelled rows with copy fields, the passwords
// hidden until »Anzeigen«, one main action, notes as quiet text; the
// Klassenleitung's students as a table that turns into list rows opening a
// sheet on phones. The same requests and states as today's page
// (passwords.spec.ts), drawn by print_password_page_preview
// (include/mail_password_reset.rb) and src/static/preview/passwoerter.js/.css.
//
// The preview is for admins only on the test stack: the admin gives it to
// the student and the Klassenleitung for the test (and takes it back). The
// Labtest students of class 11 (test/prepare_example_data.rb) are used here,
// desktop and mobile each their own, so that the limits of passwords.spec.ts
// stay untouched; every case is finished here, none is left approved.

const BOT_TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const KLASSENLEITUNG = 'torstensonin@beispielschule.de';
const PAGE = '/passwoerter';

function students(testInfo: TestInfo) {
  const names = testInfo.project.name === 'mobile' ? ['Dana', 'Emil'] : ['Anna', 'Ben'];
  return names.map((first) => ({
    name: `${first} Labtest`,
    email: `${first.toLowerCase()}.labtest@mail.beispielschule.de`,
  }));
}

async function apiAs(email: string, baseURL: string | undefined) {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, email);
  return api;
}

async function latestCaseId(api: APIRequestContext, mailbox: string) {
  const { cases } = await (await api.post('/api/mail_password_reset_status', { data: {} })).json();
  const found = cases.find((c: any) => c.mailboxes.some((m: any) => m.mailbox === mailbox && m.latest));
  expect(found, `a case for ${mailbox}`).toBeDefined();
  return found.id as string;
}

async function step(admin: APIRequestContext, id: string, action: string) {
  const response = await admin.post('/api/update_mail_password_case', { data: { id, action } });
  expect((await response.json()).result, action).toBe('ok');
}

// the bot reports the approved case of one mailbox as done; returns the password
async function botFinishes(baseURL: string | undefined, mailbox: string) {
  const api = await playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${BOT_TOKEN}` } });
  const all: { id: string; mailboxes: { mailbox: string; password: string }[] }[] = (await (await api.get('/api/mail_account_bot/pending')).json()).cases;
  const open = all.filter((c) => c.mailboxes.some((m) => m.mailbox === mailbox));
  expect(open).toHaveLength(1);
  const result = await api.post('/api/mail_account_bot/result', { data: { id: open[0].id, ok: true, message: '' } });
  expect((await result.json()).result).toBe('ok');
  return open[0].mailboxes.find((m) => m.mailbox === mailbox)!.password;
}

async function tester(admin: APIRequestContext, email: string, mode: 'on' | 'off') {
  expect((await admin.post('/api/set_ui_preview_tester', { data: { email, mode } })).status()).toBe(200);
}

// the parts every view shares: headings, no boxes, no separator dots
async function calmPage(page: Page) {
  await expect(page.locator('body')).toHaveClass(/ui-preview/);
  await expect(page.locator('.pv-pw')).toBeVisible();
  const h2 = page.locator('#main_container h2').first();
  await expect(h2).toHaveText('Passwörter');
  const sizes = await page.evaluate(() => {
    const size = (el: Element | null) => (el ? parseFloat(getComputedStyle(el).fontSize) : 0);
    return {
      h2: size(document.querySelector('#main_container h2')),
      h3: Array.from(document.querySelectorAll('.pv-pw h3')).map(size),
      h4: Array.from(document.querySelectorAll('.pv-pw h4')).map(size),
    };
  });
  for (const h3 of sizes.h3) expect(h3).toBeLessThan(sizes.h2);
  for (const h4 of sizes.h4) expect(h4).toBeLessThan(Math.min(...sizes.h3));
  // no coloured boxes, nothing of today's page
  await expect(page.locator('.pv-pw .alert')).toHaveCount(0);
  await expect(page.locator('#ti_nc_login, .mail-reset-row, .nc-login-table')).toHaveCount(0);
  expect(await page.locator('.pv-pw').innerText()).not.toContain('·');
  // the page never scrolls sideways
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
}

test('Neues Design: Passwörter für Schüler:innen (Nextcloud, eigenes Postfach)', async ({ page, baseURL }, testInfo) => {
  const [student] = students(testInfo);
  const admin = await apiAs(ACCOUNTS.admin, baseURL);
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await tester(admin, student.email, 'on');
  try {
    await login(page, student.email);
    await page.goto(PAGE);
    await calmPage(page);
    await expect(page.locator('.pv-pw h3')).toHaveText(['Nextcloud', 'E-Mail-Postfach']);

    // ---------- Nextcloud: labelled rows, copy fields ----------
    const nc = page.locator('#pv_pw_nextcloud');
    await expect(nc.locator('dt')).toHaveText(['Adresse', 'Login', 'Initialpasswort']);
    const ncLogin = nc.locator('#bu_pv_nc_login');
    const loginText = await ncLogin.getAttribute('data-copy');
    expect(loginText!.length).toBeGreaterThan(0);
    await expect(ncLogin).toHaveText(loginText!);
    await ncLogin.click();
    await expect(ncLogin).toHaveClass(/pv-copied/);
    await expect(ncLogin.locator('.pv-copy-ok')).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(loginText);
    // the labels in one column, the fields in another (desktop); on phones
    // the label above its field
    const [dtBox, ddBox] = [await nc.locator('dt').first().boundingBox(), await nc.locator('dd').first().boundingBox()];
    if (testInfo.project.name === 'mobile') expect(ddBox!.y).toBeGreaterThan(dtBox!.y + dtBox!.height - 1);
    else expect(ddBox!.x).toBeGreaterThan(dtBox!.x + dtBox!.width);

    // the password: dots until »Anzeigen«, never in a tooltip
    const secret = nc.locator('#bu_pv_nc_password');
    const password = await secret.getAttribute('data-copy');
    expect(password!.length).toBeGreaterThan(0);
    await expect(secret.locator('.pv-copy-text')).not.toHaveText(password!);
    expect(await secret.getAttribute('title')).toBe('Initialpasswort kopieren');
    await secret.click();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(password);
    const show = nc.locator('.bu_pv_show_password');
    await expect(show).toHaveText('Anzeigen');
    await show.click();
    await expect(secret.locator('.pv-copy-text')).toHaveText(password!);
    await expect(show).toHaveText('Verbergen');
    await show.click();
    await expect(secret.locator('.pv-copy-text')).not.toHaveText(password!);

    // one main action, left-aligned with the text
    await expect(page.locator('.pv-pw .btn-primary')).toHaveCount(1);
    const main = page.locator('#bu_pv_nc_login_page');
    await expect(main).toHaveAttribute('href', new RegExp(`/index\\.php/login\\?user=${encodeURIComponent(loginText!).replace(/\./g, '\\.')}$`));
    const [mainBox, headBox] = [await main.boundingBox(), await nc.locator('h3').boundingBox()];
    expect(Math.abs(mainBox!.x - headBox!.x)).toBeLessThan(2);

    // resetting the own Nextcloud password: asked first, a quiet line after
    await page.locator('#bu_pv_reset_nc_password').click();
    const confirm = dashboardDialog(page);
    await expect(confirm).toContainText('Ein selbst gewähltes Passwort funktioniert danach nicht mehr');
    await confirm.getByRole('button', { name: 'Zurücksetzen' }).click();
    await expect(page.locator('#pv_nc_reset_result')).toHaveAttribute('data-result', 'ok');
    await expect(page.locator('#pv_nc_reset_result .ti-circle-check')).toBeVisible();

    // ---------- E-Mail: the own mailbox ----------
    const own = page.locator(`.pv-pw-own[data-mailbox="${student.email}"]`);
    await expect(own.locator('.pv-copy')).toHaveText(student.email);
    await expect(page.locator('#pv_pw_parents_hint')).toContainText(`eltern.${student.email}`);
    await expect(page.locator('#pv_pw_parents_hint .ti-info-circle')).toBeVisible();
    const request = own.locator('.bu_pv_request_mail_reset');
    await request.scrollIntoViewIfNeeded();
    await expect(request).toBeInViewport({ ratio: 1 });
    await request.click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toContainText('Deine Eltern bekommen eine kurze Nachricht');
    await dialog.getByRole('button', { name: 'Beantragen' }).click();
    await expect(own.locator('.pv-pw-st')).toHaveAttribute('data-state', 'open');
    await expect(own.locator('.pv-pw-st')).toContainText('Wartet auf Freigabe, beantragt am');
    await expect(own).toContainText('Die Administration schaut sich die Anfrage an.');
    await expect(request).toBeHidden();

    // approved and done (the bot): the password, hidden until »Anzeigen«
    await step(admin, await latestCaseId(admin, student.email), 'approve');
    const mailPassword = await botFinishes(baseURL, student.email);
    await page.reload();
    await expect(own.locator('.pv-pw-st')).toHaveAttribute('data-state', 'done');
    await expect(own.locator('.pv-pw-st')).toContainText('Zurückgesetzt am');
    await expect(own.locator('.pv-pw-secret-field .pv-copy-text')).not.toHaveText(mailPassword);
    await own.locator('.bu_pv_show_password').click();
    await expect(own.locator('.pv-pw-secret-field .pv-copy-text')).toHaveText(mailPassword);
    await expect(request).toBeVisible();
  } finally {
    await tester(admin, student.email, 'off');
  }
});

test('Neues Design: Klassenleitung beantragt für Schüler- und Eltern-Postfach', async ({ page, baseURL }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  const [, student] = students(testInfo);
  const parents = `eltern.${student.email}`;
  const admin = await apiAs(ACCOUNTS.admin, baseURL);
  await tester(admin, KLASSENLEITUNG, 'on');
  try {
    await login(page, KLASSENLEITUNG);
    await page.goto(PAGE);
    await calmPage(page);
    await expect(page.locator('#pv_pw_mail h3')).toHaveText('E-Mail-Postfächer');
    await expect(page.locator('#pv_pw_forward_hint')).toContainText('leite sie bitte an');
    const klasse = page.locator('.pv-pw-class[data-klasse="11"]');
    await expect(klasse.locator('h4')).toContainText('Klasse 11');
    await expect(klasse.locator('.pv-pw-count')).toHaveText(/^\d+ Schülerinnen und Schüler$/);
    const row = klasse.locator(`.pv-pw-student[data-student="${student.email}"]`);
    await expect(row).toHaveCount(1);
    // no admin link for the Klassenleitung
    await expect(page.locator('#pv_pw_admin_link')).toHaveCount(0);

    if (phone) {
      // a list row with »›«: it opens a sheet with both mailboxes
      await expect(klasse.locator('thead')).toBeHidden();
      await expect(row.locator('.pv-pw-cell').first()).toBeHidden();
      await expect(row.locator('.pv-pw-open .ti-chevron-right')).toBeVisible();
      await row.locator('.pv-pw-open').click();
      const sheet = page.locator('#mailPasswordModal');
      await expect(sheet).toBeVisible();
      await expect(sheet).toHaveClass(/pv-sheet/);
      await expect(sheet.locator('.modal-title')).toHaveText(student.name);
      await expect(sheet.locator('.pv-pw-mbox-title')).toHaveText(['Postfach', 'Eltern-Postfach']);
      await expect(sheet.locator('.pv-pw-addr')).toHaveText([student.email, parents]);
      await sheet.locator(`.pv-pw-mbox[data-mailbox="${parents}"] .bu_pv_request_mail_reset`).click();
      // the sheet goes, the confirmation comes
      await expect(sheet).toBeHidden();
    } else {
      // a table: name, the two mailboxes with a quiet »Zurücksetzen…« each
      await expect(klasse.locator('thead th')).toHaveText(['Schüler:in', 'Postfach', 'Eltern-Postfach']);
      await expect(row.locator('.pv-pw-open')).toBeHidden();
      await expect(row.locator('.pv-pw-name')).toHaveText(student.name);
      await expect(row.locator('.bu_pv_request_mail_reset')).toHaveText(['Zurücksetzen…', 'Zurücksetzen…']);
      await row.locator(`.pv-pw-cell[data-mailbox="${parents}"] .bu_pv_request_mail_reset`).click();
    }
    const dialog = dashboardDialog(page);
    await expect(dialog).toContainText(`Eltern von ${student.name} (${parents})`);
    await dialog.getByRole('button', { name: 'Beantragen' }).click();
    if (phone) {
      await expect(row.locator('.pv-pw-row-facts')).toHaveText('Eltern-Postfach: Wartet auf Freigabe');
    } else {
      const cell = row.locator(`.pv-pw-cell[data-mailbox="${parents}"]`);
      await expect(cell.locator('.pv-pw-st')).toHaveAttribute('data-state', 'open');
      await expect(cell.locator('.bu_pv_request_mail_reset')).toBeHidden();
      await expect(row.locator(`.pv-pw-cell[data-mailbox="${student.email}"] .bu_pv_request_mail_reset`)).toBeVisible();
    }

    // the admin rejects: »Abgelehnt« with a hint, the button back
    await step(admin, await latestCaseId(admin, parents), 'reject');
    await page.reload();
    let where = row.locator(`.pv-pw-cell[data-mailbox="${parents}"]`);
    if (phone) {
      await expect(row.locator('.pv-pw-row-facts')).toHaveText('Eltern-Postfach: Abgelehnt');
      await row.locator('.pv-pw-open').click();
      where = page.locator(`#mailPasswordModal .pv-pw-mbox[data-mailbox="${parents}"]`);
    }
    await expect(where.locator('.pv-pw-st')).toHaveAttribute('data-state', 'rejected');
    await expect(where).toContainText('Bitte wende dich an die Administration.');
    await expect(where.locator('.bu_pv_request_mail_reset')).toBeVisible();
  } finally {
    await tester(admin, KLASSENLEITUNG, 'off');
  }
});

test('Neues Design: Administration sieht den Weg zu den Postfächern', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto(PAGE);
    await calmPage(page);
    // the admin leads 5a
    await expect(page.locator('.pv-pw-class[data-klasse="5a"]')).toHaveCount(1);
    const link = page.locator('#pv_pw_admin_link');
    await expect(link.locator('.ti-inbox')).toBeVisible();
    await expect(link.getByRole('link', { name: 'Postfächer (Administration)' })).toHaveAttribute('href', /\/postfaecher$/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design aus: die Seite wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  await page.goto(PAGE);
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('.pv-pw')).toHaveCount(0);
  await expect(page.locator('#ti_nc_login')).toBeVisible();
  await expect(page.locator('.mail-reset-row')).toHaveCount(1);
  await expect(page.locator('.nc-actions .btn')).toHaveCount(2);
});
