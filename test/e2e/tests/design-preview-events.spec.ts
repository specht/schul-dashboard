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

// The dialog: the label of the participants field is cut to one line by
// styles.css, and its overflowing text lay over »Externe Teilnehmer…«, which
// then took no taps. »Speichern« stays disabled without a title or
// participants: a quiet hint says why.
test('Neues Design: Termin-Dialog, Externe Teilnehmer und Hinweis zum Speichern', async ({ page }, testInfo) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/events');
    await page.locator('.bu-new-event').first().click();
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    // the editor without colours and fonts, the placeholder in »du« form
    await expect(modal.locator('.note-color, .note-fontname, .note-fontsize').first()).toBeHidden();
    await expect(modal.locator('.note-placeholder')).toHaveText('Beschreibung des Termins (optional)');
    const hint = modal.locator('.pv-ev-save-hint');
    // nothing changed yet: no hint, »Schließen« works
    await expect(hint).toBeHidden();
    await page.locator('#ti_start_time').fill('17:00');
    await expect(hint).toHaveText('Zum Speichern fehlen noch Titel und Teilnehmer.');
    // »Verwerfen« and »Speichern« in one row (each was on a line of its
    // own); the hint right before »Speichern«, on phones on its own line above
    const [h, d, sv] = await Promise.all([hint, page.locator('#bu_discard_event'), page.locator('#bu_save_event')].map((l) => l.boundingBox()));
    expect(Math.abs(d!.y - sv!.y)).toBeLessThan(2);
    if (testInfo.project.name === 'mobile') {
      expect(h!.y + h!.height).toBeLessThanOrEqual(d!.y + 1);
    } else {
      expect(Math.abs((h!.y + h!.height / 2) - (sv!.y + sv!.height / 2))).toBeLessThan(2);
      expect(h!.x + h!.width).toBeLessThanOrEqual(sv!.x);
    }
    await expect(page.locator('#ti_title')).toHaveAttribute('placeholder', 'Titel des Termins');
    await page.locator('#ti_title').fill('Elternabend');
    await expect(page.locator('#bu_save_event')).toBeDisabled();
    await expect(hint).toHaveText('Zum Speichern fehlen noch Teilnehmer.');
    // the button takes the tap (not the label's text above it)
    await page.locator('.bu_open_ext_users_modal').click({ timeout: 5000 });
    await expect(page.locator('#externalUsersModal')).toBeVisible();
    // (phones: a sheet without »Schließen« – it closes like every sheet)
    if (testInfo.project.name === 'mobile') await page.keyboard.press('Escape');
    else await page.locator('#bu_close_ext_user_modal').click();
    await expect(page.locator('#externalUsersModal')).toBeHidden();
    await page.locator('#bu_discard_event').click();
    await expect(hint).toBeHidden();
  } finally {
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

// Desktop: the dialog for a new Termin fits a usual screen without its own
// scrollbar – the editor starts small and grows with its text.
test('Neues Design: Termin-Dialog ohne Scrollleiste', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'Desktop-Dialog');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1280, height: 1000 });
    await page.goto('/events');
    await page.locator('.bu-new-event').first().click();
    const body = page.locator('#composeModal > .modal-dialog > .modal-content > .modal-body');
    await expect(body).toBeVisible();
    await page.locator('#ti_start_time').fill('17:00');
    await expect(page.locator('#composeModal .pv-ev-save-hint')).toBeVisible();
    await page.waitForTimeout(300);
    expect(await body.evaluate((el) => el.scrollHeight - el.clientHeight)).toBeLessThanOrEqual(1);
    // a long text: the editor grows, then scrolls itself
    await page.locator('#composeModal .note-editable').fill(Array(60).fill('Zeile').join('\n'));
    const editor = await page.locator('#composeModal .note-editable').boundingBox();
    expect(editor!.height).toBeLessThanOrEqual(1000 * 0.4 + 2);
    await page.locator('#bu_discard_event').click();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The editor's menus (format, alignment, table) open in full: the editor's
// frame cut them off, a click on the wand seemed to do nothing.
test('Neues Design: Menüs im Texteditor nicht abgeschnitten', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'Desktop-Dialog');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/events');
    await page.locator('.bu-new-event').first().click();
    await expect(page.locator('#composeModal')).toBeVisible();
    for (const group of ['.note-style', '.note-para', '.note-table']) {
      await page.locator(`#composeModal ${group} .dropdown-toggle`).first().click();
      const menu = page.locator(`#composeModal ${group} .note-dropdown-menu`).first();
      await expect(menu).toBeVisible();
      // away from the button, so that its tooltip goes
      await page.mouse.move(5, 5);
      await expect(page.locator('.tooltip')).toHaveCount(0);
      // every corner of the menu can be clicked (nothing cut off above it;
      // 14 px inside, past the rounded corner)
      const hidden = await menu.evaluate((m) => {
        const r = m.getBoundingClientRect();
        return [[r.left + 14, r.top + 14], [r.right - 14, r.top + 14], [r.left + 14, r.bottom - 14], [r.right - 14, r.bottom - 14]]
          .filter(([x, y]) => !m.contains(document.elementFromPoint(x, y)))
          .map(([x, y]) => `${Math.round(x - r.left)},${Math.round(y - r.top)} of ${Math.round(r.width)}x${Math.round(r.height)}: ${document.elementFromPoint(x, y)?.className}`);
      });
      expect(hidden, group).toEqual([]);
      await page.locator('#composeModal .lb_title').click();
      await expect(menu).toBeHidden();
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
