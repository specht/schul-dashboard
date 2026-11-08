import { test, expect, login, typeEmail, ACCOUNTS } from './fixtures';

test('Ohne Anmeldung erscheint die Anmeldeseite', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#email')).toBeVisible();
  await expect(page.locator('#submit')).toBeDisabled();
  await typeEmail(page, ACCOUNTS.teacher);
  await expect(page.locator('#submit')).toBeEnabled();
});

test('Lehrkraft meldet sich mit Code an und sieht den Stundenplan', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('#calendar')).toBeVisible();
});

test('Falscher Code wird abgelehnt', async ({ page, serverErrors }) => {
  await page.goto('/');
  await typeEmail(page, ACCOUNTS.teacher);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await page.locator('#code').fill('000000');
  const confirm = page.waitForResponse('**/api/confirm_login');
  await page.locator('#submit').click();
  // The API currently signals a wrong code with HTTP 500 (assert) –
  // see TODO.md. Accept exactly that one here.
  expect((await confirm).status()).toBe(500);
  expect(serverErrors).toEqual([expect.stringContaining('/api/confirm_login')]);
  serverErrors.length = 0;
  // stays on the code page, no session
  await expect(page).toHaveURL(/\/c\//);
  await page.goto('/');
  await expect(page.locator('#email')).toBeVisible();
});
