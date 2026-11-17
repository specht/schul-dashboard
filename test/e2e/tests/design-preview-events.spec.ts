import type { Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, dashboardDialog, listAction, isoDate } from './fixtures';

// Neues Design (Vorschau): Termine as a list with actions (preview/events.js,
// pv_list in preview.js). The page embeds what is coming and the last four
// weeks; older events are folded by school year and loaded when opened
// (/api/get_events_archive), in blocks of 50. The preview is for admins only
// on the test stack. Each project uses a school year of its own.

async function createEvent(page: Page, title: string, date: string) {
  const r = await page.request.post('/api/save_event', {
    data: { title, jitsi: 'no', date, start_time: '15:00', end_time: '16:00', recipients: [], description: '' },
  });
  expect(r.status()).toBe(200);
  return (await r.json()).event.eid as string;
}

function daysFromToday(n: number) {
  const d = new Date();
  d.setDate(d.getDate() + n);
  return isoDate(d);
}

test('Neues Design: Termine, Älteres nach Schuljahr nachgeladen, in Blöcken von 50', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const tag = `${testInfo.project.name} ${Date.now().toString(36)}`;
  const year = testInfo.project.name === 'mobile' ? 2012 : 2011;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const eids: string[] = [];
  try {
    eids.push(await createEvent(page, `Bald ${tag}`, daysFromToday(3)));
    eids.push(await createEvent(page, `Neulich ${tag}`, daysFromToday(-10)));
    for (let i = 0; i < 55; i++) {
      const d = new Date(Date.UTC(year, 8, 1 + i));
      eids.push(await createEvent(page, `Archiv ${tag} Nr. ${i + 1}`, d.toISOString().slice(0, 10)));
    }
    await page.goto('/events');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    // today's table is not shown, the list takes its place
    await expect(page.locator('.events-container')).toBeHidden();
    await expect(page.locator('.pv-events-upcoming .pv-event', { hasText: `Bald ${tag}` })).toBeVisible();
    await expect(page.locator('.pv-events-recent .pv-event', { hasText: `Neulich ${tag}` })).toBeVisible();
    await expect(page.locator('.pv-events-upcoming .pv-event', { hasText: `Bald ${tag}` }).locator('.pv-lrow-facts'))
      .toContainText('15:00 bis 16:00 Uhr, 0 Teilnehmer');
    // the older ones are not in the page
    expect(await page.evaluate((t) => (window as any).stored_events.some((e: any) => e.info.title.startsWith(`Archiv ${t}`)), tag)).toBe(false);

    const group = page.locator(`.pv-events-year[data-school-year="${year}"]`);
    const toggle = group.locator('.pv-lgroup-toggle');
    await expect(toggle).toContainText(`Schuljahr ${year}/${String((year + 1) % 100).padStart(2, '0')}`);
    await expect(toggle).toContainText('55 Termine');
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    const loaded = page.waitForResponse('**/api/get_events_archive');
    await toggle.click();
    expect((await loaded).status()).toBe(200);
    const rows = group.locator('.pv-event');
    // the first block of 50, newest first
    await expect(rows).toHaveCount(50);
    await expect(rows.first()).toContainText(`Archiv ${tag} Nr. 55`);
    const more = group.locator('.pv-lblocks-more');
    await expect(more).toHaveText('Ältere Termine laden');
    // more when scrolled to the end (or with the button)
    await more.scrollIntoViewIfNeeded();
    await expect(rows).toHaveCount(55);
    await expect(more).toBeHidden();

    // an older event opens like any other
    const byTitle = (n: number) => rows.filter({ has: page.locator('.pv-lrow-title', { hasText: new RegExp(`Nr\\. ${n}$`) }) });
    const row = byTitle(1);
    await row.locator('.pv-lrow-title').click();
    await expect(page.locator('#composeModal')).toBeVisible();
    await expect(page.locator('#ti_title')).toHaveValue(`Archiv ${tag} Nr. 1`);
    await page.locator('#bu_close_event_modal').evaluate((b: HTMLElement) => b.click());
    await expect(page.locator('#composeModal')).toBeHidden();

    // deleting: in the "•••" menu, confirmed in red
    const victim = byTitle(2);
    await listAction(page, victim, 'Löschen');
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(`Archiv ${tag} Nr. 2`);
    await expect(dialog.getByRole('button', { name: 'Löschen' })).toHaveClass(/btn-danger/);
    const deleted = page.waitForResponse('**/api/delete_event');
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    expect((await deleted).status()).toBe(200);
    await expect(rows).toHaveCount(54);
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    await expect(toggle).toContainText('54 Termine');

    // the main action beside the title
    const main = page.locator('.pv-lhead .bu-new-event');
    await expect(main).toHaveText(testInfo.project.name === 'mobile' ? 'Neu' : 'Neuer Termin', { useInnerText: true });
  } finally {
    for (const eid of eids) await page.request.post('/api/delete_event', { data: { eid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: /events#eid öffnet auch einen älteren Termin', async ({ page }, testInfo) => {
  const title = `Alt verlinkt ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const eid = await createEvent(page, title, '2014-03-12');
  try {
    await page.goto(`/events#${eid}`);
    await expect(page.locator('#composeModal')).toBeVisible();
    await expect(page.locator('#ti_title')).toHaveValue(title);
  } finally {
    await page.request.post('/api/delete_event', { data: { eid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Termine ohne Vorschau: die Tabelle mit allen Terminen wie bisher', async ({ page }, testInfo) => {
  const tag = `${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const eids = [
    await createEvent(page, `Wie bisher alt ${tag}`, '2013-10-01'),
    await createEvent(page, `Wie bisher neu ${tag}`, daysFromToday(2)),
  ];
  try {
    await page.goto('/events');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(page.locator('.pv-events-list')).toHaveCount(0);
    await expect(page.locator('.pv-lhead')).toHaveCount(0);
    await expect(page.locator('.events-container')).toBeVisible();
    // everything is embedded, the old one too
    await expect(page.locator('.events-here tr', { hasText: `Wie bisher alt ${tag}` })).toHaveCount(1);
    await expect(page.locator('.events-here tr', { hasText: `Wie bisher neu ${tag}` })).toHaveCount(1);
    expect(await page.evaluate(() => typeof (window as any).pv_events_archive)).toBe('undefined');
    await page.locator('.events-here tr', { hasText: `Wie bisher alt ${tag}` }).click();
    await expect(page.locator('#composeModal')).toBeVisible();
  } finally {
    for (const eid of eids) await page.request.post('/api/delete_event', { data: { eid } });
  }
});
