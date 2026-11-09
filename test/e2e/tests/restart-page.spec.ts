import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';

// The restart page (errors/neustart.html) is served by nginx only while
// Ruby is unreachable. Here it is loaded from src/static and /api/ping is
// simulated: first slow failures (502), then the dashboard is back.

const STATIC_DIR = process.env.STATIC_DIR || '/static';
const HTML = fs.readFileSync(path.join(STATIC_DIR, 'errors', 'neustart.html'), 'utf8');

test('Neustart-Seite: der Knopf bleibt ruhig, bis das Dashboard wieder da ist', async ({ page }) => {
  let up = false;
  await page.route('**/neustart-test', (route) =>
    route.fulfill({ status: 502, contentType: 'text/html; charset=utf-8', body: HTML }));
  await page.route('**/api/ping*', async (route) => {
    // a slow check, so a state change during the check would be visible
    await new Promise((r) => setTimeout(r, 1200));
    await route.fulfill({ status: up ? 200 : 502, body: up ? 'ok' : 'Bad Gateway' }).catch(() => {});
  });
  await page.goto('/neustart-test');
  const button = page.locator('#retry');
  await expect(button).toBeVisible();

  // sample the button during several automatic checks
  const states = new Set<string>();
  const box0 = await button.boundingBox();
  for (let i = 0; i < 60; i++) {
    const s = await button.evaluate((b: HTMLButtonElement) =>
      `${b.disabled}/${getComputedStyle(b).opacity}`);
    states.add(s);
    const box = await button.boundingBox();
    expect(Math.abs(box!.y - box0!.y), 'Knopf springt').toBeLessThan(1);
    await page.waitForTimeout(150);
  }
  expect([...states], 'Knopf blinkt').toEqual(['false/1']);
  await expect(page.locator('#countdown')).toContainText(/Prüfe|Nächster Versuch/);

  // the dashboard is back: the page wakes up and reloads
  up = true;
  await button.click();
  await expect(page.locator('#title')).toHaveText('Da bin ich wieder!', { timeout: 10_000 });
});
