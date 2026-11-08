import {
  test, expect, login, typeEmail, clearLoginMails, waitForMailedCode, totp, ACCOUNTS,
} from './fixtures';

test('Ohne Anmeldung erscheint die Anmeldeseite', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('#email')).toBeVisible();
  await expect(page.locator('#submit')).toBeDisabled();
  await typeEmail(page, ACCOUNTS.teacher);
  await expect(page.locator('#submit')).toBeEnabled();
});

test('Schüler:in meldet sich mit Code aus der E-Mail an', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('#calendar')).toBeVisible();
});

test('Lehrkraft braucht einen zweiten Faktor (E-Mail-Code, dann OTP)', async ({ page }) => {
  await clearLoginMails(ACCOUNTS.teacher);
  await page.goto('/');
  await typeEmail(page, ACCOUNTS.teacher);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await page.locator('#code').fill(await waitForMailedCode(ACCOUNTS.teacher));
  await page.locator('#submit').click();

  // first factor alone is not enough
  await expect(page.locator('#div_forced_2fa')).toBeVisible();
  await expect(page.locator('#span_sent')).toContainText('OTP-Code');
  await page.goto('/');
  await expect(page.locator('#email')).toBeVisible();
});

test('Lehrkraft meldet sich mit zwei Faktoren an und sieht den Stundenplan', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('#calendar')).toBeVisible();
});

test('Anmeldung mit OTP-App als erstem Faktor', async ({ page }) => {
  await page.goto('/');
  await typeEmail(page, ACCOUNTS.admin);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await expect(page.getByText('OTP-Code')).toBeVisible();
  await page.locator('#code').fill(totp());
  await page.locator('#submit').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
  await expect(page.locator('#calendar')).toBeVisible();
});

test('Falscher Code wird abgelehnt', async ({ page, serverErrors }) => {
  await page.goto('/');
  await typeEmail(page, ACCOUNTS.schueler);
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
