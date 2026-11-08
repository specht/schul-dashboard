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
