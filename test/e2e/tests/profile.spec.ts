import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

async function toggleDarkMode(page: Page) {
  await page.goto('/profil');
  const saved = page.waitForResponse('**/api/set_dark_css');
  // the page reloads itself after saving – wait for that, otherwise the
  // next page.goto() collides with the reload (net::ERR_ABORTED)
  const reloaded = page.waitForEvent('load');
  // bootstrap-toggle hides the checkbox and puts a clickable wrapper around it
  await page.locator('.toggle:has(#dark_css_switch)').click();
  expect((await saved).status()).toBe(200);
  await reloaded;
}

test('Dunkelmodus lässt sich im Profil ein- und ausschalten', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  await page.goto('/');
  const wasDark = await page.locator('body.dark').count() > 0;

  await toggleDarkMode(page);
  await page.goto('/');
  await expect(page.locator('body')).toHaveClass(wasDark ? /^(?!.*\bdark\b)/ : /\bdark\b/);

  await toggleDarkMode(page);
  await page.goto('/');
  await expect(page.locator('body')).toHaveClass(wasDark ? /\bdark\b/ : /^(?!.*\bdark\b)/);
});

test('Schriftart lässt sich im Profil ändern', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  const setFont = async (font: string) => {
    await page.goto('/profil');
    const saved = page.waitForResponse('**/api/set_font');
    await page.locator(`.bu_set_font[data-font="${font}"]`).click();
    expect((await saved).status()).toBe(200);
    await page.goto('/');
    return page.evaluate(() => getComputedStyle(document.body).fontFamily);
  };
  expect(await setFont('Roboto')).toContain('Roboto');
  expect(await setFont('Alegreya')).toContain('Alegreya');
});

test('Farbschema lässt sich im Profil wählen', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  await page.goto('/profil');
  const before = await page.evaluate(() => (window as any).color_scheme as string);

  const request = page.waitForRequest('**/api/set_color_scheme');
  await page.locator('.swatches .swatch:not(.active)').first().click();
  const chosen = (await request).postDataJSON().scheme as string;
  expect(chosen).not.toBe(before);

  await page.goto('/');
  expect(await page.evaluate(() => (window as any).color_scheme as string)).toBe(chosen);
});
