import { test, expect, login, typeEmail, totp, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// Neues Design (Vorschau) on the login pages. Logged out there is no account
// to ask, so switching the preview on also gives the browser a cosmetic
// cookie ("light" or "dark", nothing else); the login pages use the new
// design while it is there (include/design_preview.rb, UI_PREVIEW_COOKIE).
// Logging in works the same in both looks.

const lookCookie = async (page: Page) =>
  (await page.context().cookies()).find((c) => c.name === 'ui_preview');

test('Neues Design: Die Anmeldeseiten merken sich die Vorschau im Browser', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  expect(await lookCookie(page)).toBeUndefined();
  try {
    // switching on: the account and this browser
    expect((await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } })).status()).toBe(200);
    const cookie = await lookCookie(page);
    expect(['light', 'dark']).toContain(cookie?.value);
    expect(cookie?.httpOnly).toBe(true);
    expect(cookie?.sameSite).toBe('Lax');
    // long-lived, like the session
    expect(cookie!.expires * 1000 - Date.now()).toBeGreaterThan(300 * 24 * 3600 * 1000);

    // logged out: the login page in the new design, without navigation
    await page.request.post('/api/logout');
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    await expect(page.locator('body')).toHaveClass(/pv-public/);
    await expect(page.locator('#design_tokens')).toHaveCount(1);
    await expect(page.locator('.navbar')).toBeHidden();
    await expect(page.locator('.pv-login-brand')).toBeVisible();
    await expect(page.locator('#bu_design_feedback')).toHaveCount(0);
    // Impressum stays reachable
    await expect(page.locator('.foot a[href="/impressum"]')).toBeVisible();
    // the explanation of code apps, too; other public pages keep today's look
    await page.goto('/otp');
    await expect(page.locator('body')).toHaveClass(/pv-public/);
    await page.goto('/hilfe');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);

    // one clear main action, calm until there is an address
    await page.goto('/');
    await expect(page.locator('#submit')).toBeDisabled();
    await typeEmail(page, ACCOUNTS.admin);
    await expect(page.locator('#submit')).toBeEnabled();
    const field = await page.locator('#email').boundingBox();
    const button = await page.locator('#submit').boundingBox();
    expect(button!.y).toBeGreaterThan(field!.y + field!.height - 1);
    expect(button!.height).toBeGreaterThanOrEqual(44);

    // the code page: one field with the numeric keyboard
    await page.locator('#submit').click();
    await page.waitForURL(/\/c\//);
    await expect(page.locator('body')).toHaveClass(/pv-public/);
    const code = page.locator('#code');
    await expect(code).toHaveAttribute('type', 'text');
    await expect(code).toHaveAttribute('inputmode', 'numeric');
    await expect(code).toHaveAttribute('autocomplete', 'one-time-code');

    // logging in through the new pages works as always
    await code.fill(totp());
    await page.locator('#submit').click();
    await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    await expect(page.locator('body')).not.toHaveClass(/pv-public/);

    // switching off removes it again
    expect((await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } })).status()).toBe(200);
    expect(await lookCookie(page)).toBeUndefined();
    await page.request.post('/api/logout');
    await page.goto('/');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(page.locator('#code, .pv-login-brand')).toHaveCount(0);
  } finally {
    await login(page, ACCOUNTS.admin);
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Das Cookie ist nur ein Aussehen', async ({ page, baseURL }) => {
  // without it: today's login and code page, unchanged
  await page.goto('/');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('#design_tokens')).toHaveCount(0);

  // only "light" or "dark" count
  await page.context().addCookies([{ name: 'ui_preview', value: '<b>', url: baseURL! }]);
  await page.goto('/');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);

  // set by hand: the login pages look new (dark here) – nothing more
  await page.context().addCookies([{ name: 'ui_preview', value: 'dark', url: baseURL! }]);
  await page.goto('/');
  await expect(page.locator('body')).toHaveClass(/ui-preview/);
  await expect(page.locator('body')).toHaveClass(/\bdark\b/);
  expect((await page.request.post('/api/design_feedback', { data: { text: 'x', page: '/', device: 'phone' } })).status()).not.toBe(200);
  expect((await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } })).status()).not.toBe(200);

  // an account without the preview logs in as always, and the browser
  // forgets the look
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#calendar')).toBeVisible();
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  expect(await lookCookie(page)).toBeUndefined();
  await page.request.post('/api/logout');
  await page.goto('/');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
});

test('Neues Design: Code-Seite ohne Vorschau unverändert', async ({ page }) => {
  await page.goto('/');
  await typeEmail(page, ACCOUNTS.admin);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await expect(page.locator('#code')).toHaveAttribute('type', 'number');
  await expect(page.locator('#code')).not.toHaveAttribute('inputmode', /./);
  await expect(page.locator('.pv-login-brand')).toHaveCount(0);
  // finish the login, so that no open code is left behind
  await page.locator('#code').fill(totp());
  await page.locator('#submit').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
});
