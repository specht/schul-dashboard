import { test, expect, login, loginOnCurrentPage, openProfileMenu, ACCOUNTS } from './fixtures';

test('Abmelden führt zurück zur Anmeldeseite', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#calendar')).toBeVisible();
  await openProfileMenu(page);
  await page.getByRole('link', { name: 'Abmelden' }).click();
  await expect(page.locator('#email')).toBeVisible();
  // the session is really gone
  await page.goto('/messages');
  await expect(page).not.toHaveURL(/\/messages/);
  await page.goto('/');
  await expect(page.locator('#email')).toBeVisible();
});

test('Zweites Konto anmelden und zwischen den Konten wechseln', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  const navbar = page.locator('#navbarDropdownProfile');
  await expect(navbar).toContainText('Max Mustermann');

  await openProfileMenu(page);
  await page.getByRole('link', { name: 'Zusätzliche Anmeldung…' }).click();
  await loginOnCurrentPage(page, ACCOUNTS.schueler_oberstufe);
  await expect(navbar).toContainText('Alice Mustermann');

  // switch back to the first account
  await openProfileMenu(page);
  await page.locator('.switch-session', { hasText: 'Max Mustermann' }).click();
  await expect(navbar).toContainText('Max Mustermann');
});

// Logged in as someone else in another tab: the cookie's first session is
// theirs now. The first tab neither gets their data in the background nor
// saves anything in their name; it says so and offers to reload.
test('Zweite Anmeldung in einem anderen Tab: der erste Tab zeigt keine fremden Daten', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  const navbar = page.locator('#navbarDropdownProfile');
  await expect(navbar).toContainText('Max Mustermann');
  const other = await page.context().newPage();
  await other.goto('/login');
  await loginOnCurrentPage(other, ACCOUNTS.schueler_oberstufe);
  await expect(other.locator('#navbarDropdownProfile')).toContainText('Alice Mustermann');

  // the first tab asks in the background (as the start page does)
  const answer = await page.evaluate(() => new Promise((resolve) =>
    (window as unknown as { api_call: (u: string, d: object, cb: (r: unknown) => void) => void }).api_call('/api/refresh_start_page', {}, resolve)));
  expect(answer).toMatchObject({ success: false, error: 'wrong_user' });
  await expect(page.locator('.modal.show')).toContainText('jemand anderes angemeldet');
  // fetch as well
  const status = await page.evaluate(() => fetch('/api/refresh_start_page', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).then((r) => r.status));
  expect(status).toBe(409);
  // the second tab goes on as before
  const own = await other.evaluate(() => fetch('/api/refresh_start_page', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).then((r) => r.status));
  expect(own).toBe(200);

  // reloaded: the current login
  await page.locator('.modal.show').getByRole('button', { name: 'Neu laden' }).click();
  await expect(navbar).toContainText('Alice Mustermann');
  await other.close();
});

// Logged out in another tab: the first tab says that, not »someone else«
test('Abgemeldet in einem anderen Tab: der erste Tab sagt es', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#navbarDropdownProfile')).toContainText('Max Mustermann');
  const other = await page.context().newPage();
  await other.goto('/');
  await other.evaluate(() => fetch('/api/logout', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }));
  const answer = await page.evaluate(() => new Promise((resolve) =>
    (window as unknown as { api_call: (u: string, d: object, cb: (r: unknown) => void) => void }).api_call('/api/refresh_start_page', {}, resolve)));
  expect(answer).toMatchObject({ success: false, error: 'wrong_user' });
  await expect(page.locator('.modal.show')).toContainText('abgemeldet');
  await other.close();
});
