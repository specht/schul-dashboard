import { test, expect, login, ACCOUNTS } from './fixtures';

// Example data: Clarke is class teacher of 5a (Max, Elisabeth and Mallory
// Mustermann); Alice Mustermann is in class 11.

test('Klassenleitung sieht die Klassenliste ihrer Klasse', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/directory/5a');
  await expect(page).toHaveURL(/\/directory\/5a/);
  // last and first name are separate columns; Elisabeth goes by "Elli"
  const rows = page.locator('tr', { hasText: 'Mustermann' });
  for (const firstName of ['Max', 'Elli', 'Mallory']) {
    await expect(rows.filter({ hasText: firstName }).first()).toBeVisible();
  }
  // nobody from other classes
  await expect(page.locator('tr', { hasText: 'Alice' })).toHaveCount(0);
});

test('Schüler:innen anderer Klassen sehen die Klassenliste nicht', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  await page.goto('/directory/5a');
  await expect(page).not.toHaveURL(/\/directory\/5a/);
  await expect(page.getByText('Mallory')).toHaveCount(0);
});

test('Admin meldet sich als andere Person an', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  const impersonate = page.locator(`.btn-impersonate[data-impersonate-email="${ACCOUNTS.schueler}"]`).first();
  await impersonate.scrollIntoViewIfNeeded();
  const response = page.waitForResponse('**/api/impersonate');
  // click the label, not the icon (see TODO.md: handlers read e.target)
  await impersonate.getByText('Anmelden').click();
  expect((await response).status()).toBe(200);
  await page.waitForURL((url) => url.pathname === '/');
  await expect(page.locator('#navbarDropdownProfile')).toContainText('Max Mustermann');
});
