import { test, expect, login, ACCOUNTS, dashboardDialog, listAction } from './fixtures';

// Neues Design (Vorschau): the news administration as a list with actions
// (manage_news.html, pv_list in preview.js). This year's entries first,
// earlier years folded and loaded when opened (/api/get_news with a year).
// Earlier years come from test/e2e/seed.cypher (2019: three, 2018: one).

async function newsEntry(page: import('@playwright/test').Page, title: string) {
  const year = new Date().getFullYear();
  const r = await page.request.post('/api/get_news', { data: { year } });
  expect(r.status()).toBe(200);
  return ((await r.json()).news as any[]).find((n) => n.title === title);
}

test('Neues Design: News nach Jahren, ältere nachgeladen, Aktionen im Menü', async ({ page }, testInfo) => {
  const title = `Sportfest ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  expect((await page.request.post('/api/store_news_entry', { data: { title, content: 'Am Freitag.' } })).status()).toBe(200);
  const entry = await newsEntry(page, title);
  expect(entry).toBeTruthy();
  try {
    const first = page.waitForResponse((r) => r.url().endsWith('/api/get_news'));
    await page.goto('/manage_news');
    expect((await first).request().postDataJSON()).toEqual({ year: new Date().getFullYear() });
    await expect(page.locator('#news_here').locator('xpath=ancestor::table/..')).toBeHidden();
    const current = page.locator(`.pv-news-year[data-year="${new Date().getFullYear()}"]`);
    await expect(current.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'true');
    const row = current.locator('.pv-news-entry', { hasText: title });
    await expect(row).toBeVisible();
    await expect(row.locator('.pv-lrow-facts')).toContainText('nicht veröffentlicht');

    // earlier years: folded, loaded when opened
    const y2019 = page.locator('.pv-news-year[data-year="2019"]');
    await expect(y2019.locator('.pv-lgroup-toggle')).toContainText('3 Beiträge');
    await expect(y2019.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'false');
    await expect(page.locator('.pv-news-year[data-year="2018"] .pv-lgroup-toggle')).toContainText('1 Beitrag');
    const loaded = page.waitForResponse((r) => r.url().endsWith('/api/get_news'));
    await y2019.locator('.pv-lgroup-toggle').click();
    expect((await loaded).request().postDataJSON()).toEqual({ year: 2019 });
    await expect(y2019.locator('.pv-news-entry')).toHaveCount(3);
    await expect(y2019.locator('.pv-news-entry').first()).toContainText('Archiv-Beitrag 2019 Nr. 3');

    // publishing: in the row on larger screens, in the sheet on phones
    const published = page.waitForResponse('**/api/set_news_published');
    await listAction(page, row, 'Veröffentlichen');
    expect((await published).status()).toBe(200);
    await expect(row.locator('.pv-lrow-facts')).toContainText(/, veröffentlicht/);
    // the opened year stays open when the list is drawn again
    await expect(y2019.locator('.pv-news-entry')).toHaveCount(3);

    // pinning lives in the menu
    await listAction(page, row, 'Anheften');
    await expect(row.locator('.pv-lrow-facts')).toContainText('angeheftet');

    // deleting: in the menu, confirmed in red
    await listAction(page, row, 'Löschen');
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(title);
    await expect(dialog.getByRole('button', { name: 'Löschen' })).toHaveClass(/btn-danger/);
    const deleted = page.waitForResponse('**/api/delete_news_entry');
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    expect((await deleted).status()).toBe(200);
    await expect(page.locator('.pv-news-entry', { hasText: title })).toHaveCount(0);
    expect(await newsEntry(page, title)).toBeUndefined();
  } finally {
    if (await newsEntry(page, title))
      await page.request.post('/api/delete_news_entry', { data: { timestamp: entry.timestamp } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('News ohne Vorschau: die Tabelle mit allen Beiträgen wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const first = page.waitForResponse((r) => r.url().endsWith('/api/get_news'));
  await page.goto('/manage_news');
  expect((await first).request().postDataJSON()).toEqual({});
  await expect(page.locator('.pv-news-list')).toHaveCount(0);
  await expect(page.locator('#news_here tr', { hasText: 'Archiv-Beitrag 2019 Nr. 1' })).toHaveCount(1);
  await expect(page.locator('#news_here tr', { hasText: 'Archiv-Beitrag 2018 Nr. 1' })).toHaveCount(1);
});
