import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest } from '@playwright/test';

// Exports on the admin page (include/admin.rb).

// LogoDIDACT, "Alle SuS": one line per student,
// Nachname;Vorname;Klasse;Geschlecht;Geburtstag (TT.MM.JJJJ). Students whose
// birthday is missing in the student list (new 5th graders, until the data is
// complete) are exported too, with an empty birthday.
test('LogoDIDACT-Export: alle SuS, auch ohne Geburtstag', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.admin);
  const response = await api.get('/api/all_sus_logo_didact');
  expect(response.status()).toBe(200);
  const lines = (await response.text()).split('\n').filter((line) => line.length > 0);
  expect(lines).toContain('Postfachtest;Anna;11;w;01.01.2010');
  expect(lines).toContain('Ohnegeburtstag;Gina;11;w;');
  // every line has the five fields
  for (const line of lines) expect(line.split(';'), line).toHaveLength(5);
});

test('LogoDIDACT-Export nur für die Administration', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  const response = await api.get('/api/all_sus_logo_didact');
  expect(response.ok()).toBe(false);
});

// Teacher list on the admin page: the two-factor status and the reset button
// share one line.
test('Lehrkräfte-Liste: 2FA-Status und Zurücksetzen in einer Zeile', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  const cell = page.locator('td.teacher-2fa').filter({ has: page.locator('.btn-reset-teacher-2fa') }).first();
  await cell.scrollIntoViewIfNeeded();
  const status = await cell.locator('.teacher-2fa-status').boundingBox();
  const button = await cell.locator('.btn-reset-teacher-2fa').boundingBox();
  expect(status && button).toBeTruthy();
  const middle = (box: { y: number; height: number }) => box.y + box.height / 2;
  expect(Math.abs(middle(status!) - middle(button!))).toBeLessThan(8);
  expect(button!.x).toBeGreaterThan(status!.x + status!.width);
});

test('Admin-Seite: Exporte und Listen sind verlinkt', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  for (const href of ['/api/all_sus_logo_didact', '/api/all_lul_logo_didact', '/api/all_sus_untis', '/api/all_kurse_untis',
    '/api/all_users_informatik_biber.xlsx', '/api/all_users_informatik_biber', '/sus_ohne_kurse', '/dienste', '#teachers']) {
    await expect(page.locator(`.admin-links a[href="${href}"]`)).toHaveCount(1);
  }
});

// The link rows start below the floating status line and use the full width
// (on phones the first row was squeezed next to it: one button per line).
test('Admin-Seite: Link-Zeilen nutzen die ganze Breite', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  const row = page.locator('.admin-link-row').first();
  const label = await row.locator('.admin-link-label').boundingBox();
  const lineHeight = await row.locator('.admin-link-label').evaluate((el) => parseFloat(getComputedStyle(el).lineHeight) || 24);
  expect(label!.height).toBeLessThan(lineHeight * 1.5);
  const buttons = row.locator('a.btn');
  const first = await buttons.nth(0).boundingBox();
  const second = await buttons.nth(1).boundingBox();
  expect(Math.abs(first!.y - second!.y)).toBeLessThan(4);
});

// "Daten neu laden" on the admin page (data_version.rb): asks first and shows
// when the data was read. Confirming would restart every service of the
// shared test stack, so the test only cancels; the restart itself is covered
// by the unit tests of the watcher.
test('Daten neu laden: fragt erst nach, Abbrechen lädt nichts', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  const status = page.locator('#data_loaded_at');
  await expect(status).toHaveText(/^Gelesen am \d\d\.\d\d\.\d{4}, \d\d:\d\d:\d\d$/);
  const before = await status.textContent();
  let reloads = 0;
  page.on('request', (r) => { if (r.url().endsWith('/api/reload_data')) reloads += 1; });
  await page.locator('#bu_reload_data').click();
  const dialog = page.locator('.modal.show');
  await expect(dialog).toContainText('Daten neu laden');
  await expect(dialog).toContainText('etwa eine Minute');
  await dialog.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(dialog).toBeHidden();
  expect(reloads).toBe(0);
  await expect(status).toHaveText(before!);
});

test('Daten neu laden nur für die Administration', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  for (const path of ['/api/reload_data', '/api/data_status']) {
    const response = await api.post(path, { data: {} });
    expect(response.ok(), path).toBe(false);
  }
});
