import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// Monitors in the school building (full HD) and their previews on
// /manage_monitor (small iframes, on phones only a few hundred pixels wide).
// Everything on the monitors is sized in vw, so the same page has to look
// the same at every width.

const SIZES = [
  { name: 'Monitor', width: 1920, height: 1080 },
  { name: 'Vorschau', width: 480, height: 270 },
];

async function box(page: Page, selector: string) {
  const b = await page.locator(selector).first().boundingBox();
  expect(b, selector).not.toBeNull();
  return b!;
}

for (const size of SIZES) {
  test(`Flur-Monitor: Klassen-Kiesel sitzen auf der Ecke der Karte (${size.name})`, async ({ page }) => {
    await login(page, ACCOUNTS.admin);
    await page.setViewportSize({ width: size.width, height: size.height });
    await page.goto('/monitor');
    const cards = page.locator('.main .klasse');
    await expect(cards.first()).toBeVisible();
    const n = await cards.count();
    for (let i = 0; i < Math.min(n, 6); i++) {
      const card = (await cards.nth(i).boundingBox())!;
      const pebble = (await cards.nth(i).locator('h3').boundingBox())!;
      // the pebble overlaps the upper left corner of its card: it starts
      // above the card's top edge and left of its left edge
      expect(pebble.y, `Kiesel ${i} oben`).toBeLessThanOrEqual(card.y);
      expect(pebble.y + pebble.height, `Kiesel ${i} unten`).toBeGreaterThan(card.y);
      expect(pebble.x, `Kiesel ${i} links`).toBeLessThan(card.x);
    }
  });

  test(`Silentium-Monitor: alle Geräte lesbar auf einer Seite (${size.name})`, async ({ page }) => {
    await login(page, ACCOUNTS.admin);
    await page.setViewportSize({ width: size.width, height: size.height });
    // admins see the Silentium monitor via its preview path
    await page.goto('/monitor/silentium');
    const board = await box(page, '.bm-board');
    // the page is laid out like the timetable: time runs downwards, every
    // tablet set gets a column of its own
    const cols = page.locator('.bm-col');
    await expect(cols.first()).toBeVisible();
    const n = await cols.count();
    expect(n).toBeGreaterThan(1);
    // every device column lies completely inside the board – nothing is cut off
    for (let i = 0; i < n; i++) {
      const r = (await cols.nth(i).boundingBox())!;
      expect(r.x, `Spalte ${i}`).toBeGreaterThanOrEqual(board.x - 1);
      expect(r.x + r.width, `Spalte ${i}`).toBeLessThanOrEqual(board.x + board.width + 1);
      expect(r.y + r.height, `Spalte ${i}`).toBeLessThanOrEqual(board.y + board.height + 1);
    }
    expect(board.y + board.height).toBeLessThanOrEqual(size.height);

    // the booking from test/e2e/seed.cypher: in the column of its tablet set,
    // with the teacher's shorthand and the reason, not clipped
    const col = cols.filter({ has: page.locator('.bm-col-head', { hasText: 'Tabletsatz 1' }) });
    await expect(col).toHaveCount(1);
    const booking = col.locator('.bm-booking', { hasText: 'E2E-Buchung' });
    await expect(booking).toHaveCount(1);
    await expect(booking).toContainText('Ts');
    const what = booking.locator('.bm-booking-main');
    // measured on the subject itself, not on the block: the block is a flex
    // container whose children shrink, so it never reports an overflow
    const clipped = await what.evaluate((e) => e.scrollHeight > e.clientHeight + 1);
    expect(clipped, 'Buchungstext abgeschnitten').toBe(false);
    if (size.width >= 1920) {
      // readable from a few metres away
      const fontSize = await what.evaluate((e) => parseFloat(getComputedStyle(e).fontSize));
      expect(fontSize).toBeGreaterThanOrEqual(18);
    }
  });
}
