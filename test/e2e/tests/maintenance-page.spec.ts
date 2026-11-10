import { test, expect, Page } from '@playwright/test';
import fs from 'fs';
import path from 'path';

// The maintenance page (errors/wartung.html) is served by nginx instead of
// the restart page while /gen/wartung.json exists. Here it is loaded from
// src/static, /gen/wartung.json and /api/ping are simulated. The clock is
// fixed at noon, so planned ends never cross midnight.

const STATIC_DIR = process.env.STATIC_DIR || '/static';
const HTML = fs.readFileSync(path.join(STATIC_DIR, 'errors', 'wartung.html'), 'utf8');
const NOON = new Date('2026-03-02T12:00:00');

async function openMaintenancePage(page: Page, info: object | null) {
  const backend = { up: false };
  await page.clock.setFixedTime(NOON);
  await page.route('**/wartung-test', (route) =>
    route.fulfill({ status: 502, contentType: 'text/html; charset=utf-8', body: HTML }));
  await page.route('**/gen/wartung.json*', (route) =>
    info === null
      ? route.fulfill({ status: 404, body: 'Not Found' })
      : route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(info) }));
  await page.route('**/api/ping*', (route) =>
    route.fulfill({ status: backend.up ? 200 : 502, body: backend.up ? 'ok' : 'Bad Gateway' }).catch(() => {}));
  await page.goto('/wartung-test');
  await expect(page.locator('#title')).toHaveText('Wir schrauben gerade am Dashboard!');
  return backend;
}

test('Wartungsseite: zeigt das geplante Ende und den Grund, und lädt neu, wenn das Dashboard wieder da ist', async ({ page }) => {
  const backend = await openMaintenancePage(page, { bis: '13:30', text: 'Wir ziehen die <b>Datenbank</b> um.' });
  await expect(page.locator('#until')).toBeVisible();
  await expect(page.locator('#until-time')).toHaveText('gegen 13:30 Uhr');
  // inserted as text, not as HTML
  await expect(page.locator('#reason')).toHaveText('Wir ziehen die <b>Datenbank</b> um.');
  await expect(page.locator('#reason b')).toHaveCount(0);
  await expect(page.locator('#long-wait')).toBeHidden();
  await expect(page.locator('#countdown')).toContainText(/Prüfe|Nächster Versuch/);

  // nothing overflows on phones
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, 'Seite breiter als der Bildschirm').toBeLessThanOrEqual(0);

  backend.up = true;
  await page.locator('#retry').click();
  await expect(page.locator('#title')).toHaveText('Fertig geschraubt!', { timeout: 10_000 });
  await expect(page.locator('#until')).toBeHidden();
});

test('Wartungsseite: sagt Bescheid, wenn das geplante Ende vorbei ist', async ({ page }) => {
  await openMaintenancePage(page, { bis: '11:40' });
  await expect(page.locator('#until-time')).toHaveText('gegen 11:40 Uhr');
  await expect(page.locator('#long-wait')).toBeVisible();
  await expect(page.locator('#reason')).toBeHidden();
});

test('Wartungsseite: ohne Angaben bleibt sie allgemein', async ({ page }) => {
  await openMaintenancePage(page, null);
  await expect(page.locator('#lead')).toContainText('gewartet');
  await expect(page.locator('#until')).toBeHidden();
  await expect(page.locator('#reason')).toBeHidden();
  await expect(page.locator('#long-wait')).toBeHidden();
});

test('Wartungsseite: ungültige Angaben werden ignoriert', async ({ page }) => {
  await openMaintenancePage(page, { bis: '25:99', text: 42 });
  await expect(page.locator('#until')).toBeHidden();
  await expect(page.locator('#reason')).toBeHidden();
});
