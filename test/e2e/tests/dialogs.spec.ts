import { test, expect, login, ACCOUNTS, dashboardDialog } from './fixtures';

// dashboardAlert()/dashboardConfirm() from _template.html replace the
// browser's alert()/confirm() on every page.

test('Hinweis-Dialog zeigt Text als Text, nicht als HTML', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  await page.evaluate(() => (window as any).dashboardAlert('Zeile 1\n<b>Zeile 2</b>', 'Achtung'));
  const dialog = dashboardDialog(page);
  await expect(dialog.locator('.modal-title')).toHaveText('Achtung');
  await expect(dialog.locator('.modal-body')).toContainText('<b>Zeile 2</b>');
  await expect(dialog.locator('.modal-body b')).toHaveCount(0);
  await expect(dialog.getByRole('button', { name: 'OK' })).toBeFocused();
  await dialog.getByRole('button', { name: 'OK' }).click();
  await expect(dialog).toBeHidden();
});

test('Bestätigungs-Dialog: Abbrechen und Bestätigen', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  const ask = () => page.evaluate(() => {
    (window as any).confirmed = false;
    (window as any).dashboardConfirm('Wirklich?', () => { (window as any).confirmed = true; },
      { confirm: 'Löschen', danger: true });
  });
  const dialog = dashboardDialog(page);

  await ask();
  // cancel has the focus, so Enter cannot delete anything by accident
  await expect(dialog.getByRole('button', { name: 'Abbrechen' })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(dialog).toBeHidden();
  expect(await page.evaluate(() => (window as any).confirmed)).toBe(false);

  await ask();
  await expect(dialog.getByRole('button', { name: 'Löschen' })).toHaveClass(/btn-danger/);
  await dialog.getByRole('button', { name: 'Löschen' }).click();
  await expect(dialog).toBeHidden();
  expect(await page.evaluate(() => (window as any).confirmed)).toBe(true);
});
