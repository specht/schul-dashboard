import type { Page } from '@playwright/test';
import {
  test, expect, login, ACCOUNTS, dashboardDialog, displayedSchoolWeek, germanDate,
} from './fixtures';

// Neues Design (Vorschau): the Kursbuch (/lessons/<course>) as a list of
// lessons with the editing pane beside it (from 1024 px) or as a sheet
// (tablets, phones) – preview/lessons.js and .css. Today's table and pane
// stay the engine (selection, saving, Umplanen), so this checks what the new
// look adds: rows with text and links, the pane's title and buttons, the
// sheet with back and unsaved changes, Umplanen as a menu that asks before
// removing. The preview is for admins only on the test stack; the admin
// (Clarke) teaches Mathematik and Naturwissenschaften in 5a. Today's page
// stays as it was (last test).

const SHEET_WIDTH = 1023;

// a lesson of the displayed week (the page has a lesson every school day).
// Tests open it by its date: the row's middle may hold a link from
// an earlier test (the topic »Siehe https://…«), which opens a new tab.
function weekRow(page: Page) {
  const week = displayedSchoolWeek();
  const short = week.map((d) => `${d.getDate()}.${d.getMonth() + 1}.`);
  return page.locator('tr.lesson').filter({
    has: page.locator('.pv-kb-day', { hasText: new RegExp(`(${short.map((s) => s.replace(/\./g, '\\.')).join('|')})$`) }),
  }).first();
}

test('Neues Design: Kursbuch, Stunde wählen, eintragen, Links, speichern', async ({ page }) => {
  const sheet = (page.viewportSize()?.width ?? 0) <= SHEET_WIDTH;
  const stamp = Date.now().toString(36);
  const thema = `Brüche ${stamp}`;
  const topic = `Siehe https://example.org/kb-${stamp}. Danach Übung`;
  const homework = `Buch S. 12\nNr. 4 ${stamp}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);

    // ---------- the page: a header, rows instead of the table's columns ----------
    await expect(page.locator('.pv-kb-head h2')).toHaveText('Mathematik (5a)');
    await expect(page.locator('.pv-kb-head-facts')).toHaveText(/^Kursbuch, \d+ Schülerinnen und Schüler$/);
    await expect(page.locator('#bu_kb_pdf')).toHaveAttribute('href', '/api/kursbuch_pdf/Ma_5a');
    await expect(page.locator('.lesson_table_table thead')).toBeHidden();
    await expect(page.locator('tr.pv-kb-month').first()).toBeVisible();
    const row = weekRow(page);
    await expect(row).toBeVisible();
    await expect(row.locator('.pv-kb-hour')).toHaveText(/^\d+\. Stunde$/);
    // the old cells are there (today's page writes into them), but hidden
    await expect(row.locator('td.tc_thema')).toBeHidden();
    // a line for today
    await expect(page.locator('#pv_kb_today')).toHaveText('Heute');
    expect(await page.locator('.pv-kb').innerText()).not.toContain('·');

    // ---------- nothing selected: a hint, no disabled fields ----------
    if (!sheet) {
      await expect(page.locator('.pv-kb-hint')).toBeVisible();
      await expect(page.locator('#ti_thema')).toBeHidden();
    } else {
      await expect(page.locator('.lesson_pane')).toBeHidden();
    }

    // ---------- select the lesson: the pane (a sheet on smaller screens) ----------
    await row.locator('.pv-kb-day').click();
    const pane = page.locator('.lesson_pane');
    await expect(pane).toBeVisible();
    if (sheet) await expect(page.locator('.pv-kb-sheet')).toBeVisible();
    await expect(page.locator('#pv_kb_pane_title')).toHaveText(/^(Mo|Di|Mi|Do|Fr), \d+\.\d+\., \d+\. Stunde$/);
    await expect(page.locator('.pv-kb-pane-sub')).toHaveText(/^Stunde \d+ im Kurs$/);
    const save = page.locator('.pv-kb-pane-foot .bu-save-changes');
    await expect(save).toBeVisible();
    await expect(save).toBeDisabled();
    await page.locator('#ti_thema').fill(thema);
    await page.locator('#ti_stundenthema_text').fill(topic);
    await page.locator('#ti_hausaufgaben_text').fill(homework);
    await expect(save).toBeEnabled();
    await expect(page.locator('.pv-kb-dirty-label')).toBeVisible();
    await expect(page.locator('.pv-kb-dirty-label')).toHaveText('Noch nicht gespeichert');
    // the buttons fit in the pane (Speichern was cut off at its edge)
    const paneBox = (await pane.boundingBox())!;
    const saveBox = (await save.boundingBox())!;
    expect(saveBox.x + saveBox.width).toBeLessThanOrEqual(paneBox.x + paneBox.width);
    if (!sheet) {
      // another lesson while there are changes: the selection stays, the
      // note stands out
      const other = page.locator('tr.lesson:not(.selected)').first();
      await other.click();
      await expect(row).toHaveClass(/selected/);
      await expect(pane).toHaveClass(/pv-kb-attention/);
    }
    const saved = page.waitForResponse('**/api/save_lesson_data');
    await save.click();
    expect((await saved).status()).toBe(200);

    // saving closes the sheet; the row shows the entries as text, the link
    // opens in a new tab
    if (sheet) await expect(page.locator('.pv-kb-sheet')).toBeHidden();
    await expect(row.locator('.pv-kb-title')).toHaveText(thema);
    await expect(row.locator('.pv-kb-topic')).toContainText('Danach Übung');
    const link = row.locator('.pv-kb-topic a');
    await expect(link).toHaveText(`https://example.org/kb-${stamp}`);
    await expect(link).toHaveAttribute('target', '_blank');
    await expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    await expect(row.locator('.pv-kb-hw')).toContainText(`Buch S. 12`);
    await expect(row.locator('.pv-kb-hw br')).toHaveCount(1);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Kursbuch-Sheet, Zurück schließt, ungespeicherte Änderungen werden nachgefragt', async ({ page }) => {
  test.skip((page.viewportSize()?.width ?? 0) > SHEET_WIDTH, 'sheet only on tablets and phones');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a');
    const row = weekRow(page);
    const sheet = page.locator('.pv-kb-sheet');
    // back closes the sheet and stays on the page
    await row.locator('.pv-kb-day').click();
    await expect(sheet).toBeVisible();
    await expect(page.locator('body')).toHaveClass(/pv-sheet-open/);
    await page.goBack();
    await expect(sheet).toBeHidden();
    await expect(page).toHaveURL(/\/lessons\/Ma_5a/);
    await expect(page.locator('body')).not.toHaveClass(/pv-sheet-open/);
    await expect(row).not.toHaveClass(/selected/);

    // unsaved changes: back asks first, "Weiter bearbeiten" keeps the sheet
    await row.locator('.pv-kb-day').click();
    await expect(sheet).toBeVisible();
    await page.locator('#ti_notizen').fill('nicht speichern');
    // (the page puts its entry back at once: Playwright's goBack would wait
    // for a navigation that never comes)
    await page.evaluate(() => history.back());
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('Änderungen verwerfen?');
    await dialog.getByRole('button', { name: 'Weiter bearbeiten' }).click();
    await expect(dialog).toBeHidden();
    await expect(sheet).toBeVisible();
    await expect(page.locator('#ti_notizen')).toHaveValue('nicht speichern');
    // the close button asks as well; "Verwerfen" closes without saving
    await page.locator('#bu_kb_close').click();
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Verwerfen' }).click();
    await expect(sheet).toBeHidden();
    await expect(row.locator('.pv-kb-note')).toHaveCount(0);
    // and back leaves the page afterwards (no entry of the sheet is left)
    await page.goBack();
    await expect(page).not.toHaveURL(/\/lessons\/Ma_5a/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Kursbuch, Umplanen als Menü, Entfernen fragt nach', async ({ page }) => {
  const sheet = (page.viewportSize()?.width ?? 0) <= SHEET_WIDTH;
  const stamp = Date.now().toString(36);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    // Naturwissenschaften (5a): its own course, so that Mathematik stays as it is
    await page.goto('/lessons/Ma_5a');
    const href = await page.locator('a[href^="/lessons/"]', { hasText: 'Naturwissenschaften' }).first().getAttribute('href');
    expect(href).toBeTruthy();
    await page.goto(href!);
    const rows = page.locator('tr.lesson');
    await expect(rows.nth(3)).toBeAttached();
    // an entry in the fourth lesson
    const key = decodeURIComponent(href!.split('/')[2]);
    const r = await page.request.post('/api/save_lesson_data', {
      data: { lesson_key: key, lesson_offsets: [3], data: { thema: `Umplanen ${stamp}` } },
    });
    expect(r.status()).toBe(200);
    await page.reload();
    await expect(rows.nth(3).locator('.pv-kb-title')).toHaveText(`Umplanen ${stamp}`);

    // insert a lesson above the third one: the entry moves down by one
    await rows.nth(2).scrollIntoViewIfNeeded();
    await rows.nth(2).click();
    await page.locator('#bu_kb_umplanen').click();
    const menu = page.locator('.pv-amenu');
    await expect(menu).toBeVisible();
    await expect(menu.getByRole('menuitem')).toHaveText([
      'Eine Stunde oberhalb einfügen', 'Doppelstunde oberhalb einfügen', 'Diese Stunde aus dem Verlauf entfernen',
    ]);
    const inserted = page.waitForResponse('**/api/insert_lesson');
    await menu.getByRole('menuitem', { name: 'Eine Stunde oberhalb einfügen' }).click();
    expect((await inserted).status()).toBe(200);
    await expect(rows.nth(4).locator('.pv-kb-title')).toHaveText(`Umplanen ${stamp}`);
    await expect(rows.nth(3).locator('.pv-kb-title')).toHaveCount(0);

    // remove the (now empty) third lesson again: asks first, cancel keeps it
    if (sheet && !(await page.locator('.pv-kb-sheet').isVisible())) await rows.nth(2).click();
    await page.locator('#bu_kb_umplanen').click();
    await menu.getByRole('menuitem', { name: 'Diese Stunde aus dem Verlauf entfernen' }).click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('Diese Stunde entfernen?');
    await expect(dialog.locator('.btn-danger')).toHaveText('Entfernen');
    await dialog.getByRole('button', { name: 'Abbrechen' }).click();
    await expect(dialog).toBeHidden();
    await expect(rows.nth(4).locator('.pv-kb-title')).toHaveText(`Umplanen ${stamp}`);
    if (sheet && !(await page.locator('.pv-kb-sheet').isVisible())) await rows.nth(2).click();
    await page.locator('#bu_kb_umplanen').click();
    await menu.getByRole('menuitem', { name: 'Diese Stunde aus dem Verlauf entfernen' }).click();
    const deleted = page.waitForResponse('**/api/delete_lessons');
    await dialog.getByRole('button', { name: 'Entfernen' }).click();
    expect((await deleted).status()).toBe(200);
    await expect(rows.nth(3).locator('.pv-kb-title')).toHaveText(`Umplanen ${stamp}`);
    await page.reload();
    await expect(rows.nth(3).locator('.pv-kb-title')).toHaveText(`Umplanen ${stamp}`);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// from the timetable (»Kursbuch« in the lesson dialog): /lessons/<course>#<offset>
test('Neues Design: Kursbuch mit Stunde in der Adresse öffnet sie', async ({ page }) => {
  const sheet = (page.viewportSize()?.width ?? 0) <= SHEET_WIDTH;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a#4');
    await expect(page.locator('tr.lesson').nth(4)).toHaveClass(/selected/);
    await expect(page.locator('.pv-kb-pane-sub')).toHaveText('Stunde 5 im Kurs');
    await expect(page.locator('#ti_thema')).toBeVisible();
    if (sheet) await expect(page.locator('.pv-kb-sheet')).toBeVisible();
    await expect(page.locator('tr.lesson').nth(4)).toBeInViewport();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Wide screens: the pane reaches the window's right edge (no empty strip
// beside it), and the admins' quick switch stays clear of its buttons.
test('Neues Design: Kursbuch auf breiten Bildschirmen ohne Lücke rechts', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'breiter Bildschirm');
  await page.setViewportSize({ width: 1840, height: 920 });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_ui_preview_quick', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a');
    await weekRow(page).locator('.pv-kb-day').click();
    const pane = (await page.locator('.lesson_pane').boundingBox())!;
    const width = await page.evaluate(() => document.documentElement.clientWidth);
    expect(width - (pane.x + pane.width)).toBeLessThan(2);
    const save = (await page.locator('.pv-kb-pane-foot .bu-save-changes').boundingBox())!;
    const quick = (await page.locator('.design-quick-toggle').boundingBox())!;
    const overlap = !(quick.x + quick.width <= save.x || save.x + save.width <= quick.x ||
                      quick.y + quick.height <= save.y || save.y + save.height <= quick.y);
    expect(overlap).toBe(false);
  } finally {
    await page.request.post('/api/set_ui_preview_quick', { data: { mode: 'off' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Wide lists (from 900 px of list, beside the sidebar and the pane): the
// lessons as a table with column headings, each entry in its column, the
// rest as quiet icons, empty cells empty, rows compact. Narrower: the rows
// with labels again.
test('Neues Design: Kursbuch auf breiten Bildschirmen als Tabelle', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'breiter Bildschirm');
  await page.setViewportSize({ width: 1840, height: 920 });
  const stamp = Date.now().toString(36);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a');
    await expect(weekRow(page)).toBeVisible();
    // the lesson after the first one of the week (the first test writes there)
    const offset = 1 + await weekRow(page).evaluate((tr) => (window as any).jQuery(tr).data('lesson_offset'));
    const r = await page.request.post('/api/save_lesson_data', {
      data: {
        lesson_key: 'Ma_5a', lesson_offsets: [offset], data: {
          thema: `Tabelle ${stamp}`, stundenthema_text: `Für alle ${stamp}`, hausaufgaben_text: `AB ${stamp}`,
          homework_est_time: '20', homework_nc: true, notizen: `Notiz ${stamp}`, lesson_jitsi: true,
        },
      },
    });
    expect(r.status()).toBe(200);
    await page.reload();

    // the column headings
    const heads = page.locator('tr.pv-kb-colhead th');
    await expect(heads).toHaveText(['Nr.', 'Datum', /^Thema/, /^Stundenthema/, 'Hausaufgaben', 'Weiteres']);
    await expect(heads.nth(2)).toBeVisible();

    // each entry in its column, all in one line
    const row = page.locator('tr.lesson').nth(offset);
    await row.scrollIntoViewIfNeeded();
    await expect(row.locator('.pv-kb-title')).toHaveText(`Tabelle ${stamp}`);
    await expect(row.locator('.pv-kb-topic .pv-kb-v')).toHaveText(`Für alle ${stamp}`);
    await expect(row.locator('.pv-kb-hw .pv-kb-v')).toHaveText(`AB ${stamp}`);
    await expect(row.locator('.pv-kb-hw-meta')).toBeVisible();
    await expect(row.locator('.pv-kb-hw-meta')).toContainText('etwa 20 Min.');
    await expect(row.locator('.pv-kb-hw-meta')).toContainText('Nextcloud');
    // no labels in the cells (the headings say it), no line of facts
    await expect(row.locator('.pv-kb-topic .pv-kb-k')).toBeHidden();
    await expect(row.locator('.pv-kb-facts')).toBeHidden();
    // the note and Jitsi as quiet icons with their meaning
    await expect(row.locator('.pv-kb-note')).toBeHidden();
    await expect(row.locator(`.pv-kb-marks [aria-label="Notiz: Notiz ${stamp}"]`)).toBeVisible();
    await expect(row.locator('.pv-kb-marks [aria-label="Jitsi"]')).toBeVisible();
    const columns: [string, number][] = [['.pv-kb-title', 2], ['.pv-kb-topic', 3], ['.pv-kb-hw', 4], ['.pv-kb-marks', 5]];
    const rowBox = (await row.boundingBox())!;
    for (const [cell, head] of columns) {
      const box = (await row.locator(cell).boundingBox())!;
      const headBox = (await heads.nth(head).boundingBox())!;
      expect(Math.abs(box.x - headBox.x), cell).toBeLessThan(2);
      expect(box.x + box.width, cell).toBeLessThanOrEqual(headBox.x + headBox.width + 1);
    }
    // a filled lesson: at most two lines (the homework's time and Nextcloud
    // follow its text, on a second line when the column is too narrow for
    // both – that depends on the lesson the week shows)
    expect(rowBox.height).toBeLessThanOrEqual(64);

    // empty lessons: nothing repeated, compact
    const empty = await page.locator('tr.lesson').evaluateAll((trs) => trs
      .filter((tr) => !tr.querySelector('.pv-kb-title, .pv-kb-topic, .pv-kb-hw, .pv-kb-marks'))
      .map((tr) => ({ h: tr.getBoundingClientRect().height, text: (tr as HTMLElement).innerText })));
    expect(empty.length).toBeGreaterThan(0);
    for (const e of empty) {
      expect(e.h).toBeLessThanOrEqual(44);
      expect(e.text).not.toContain('Noch nichts eingetragen');
    }
    expect(await page.locator('.pv-kb').innerText()).not.toContain('·');

    // the headings stay in view while the list scrolls
    await page.mouse.wheel(0, 1500);
    await expect.poll(async () => (await heads.nth(2).boundingBox())!.y).toBeLessThan(40);
    await expect(heads.nth(2)).toBeInViewport();

    // a narrower window: the rows with labels again
    await page.setViewportSize({ width: 1280, height: 900 });
    await expect(heads.nth(2)).toBeHidden();
    await row.scrollIntoViewIfNeeded();
    await expect(row.locator('.pv-kb-topic .pv-kb-k')).toBeVisible();
    await expect(row.locator('.pv-kb-note')).toBeVisible();
    await expect(row.locator('.pv-kb-marks')).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Kursbuch ohne Vorschau: wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const html = await (await page.request.get('/lessons/Ma_5a')).text();
  expect(html).not.toContain('preview/lessons.js');
  expect(html).not.toContain('pv_lessons');
  await page.goto('/lessons/Ma_5a');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('tr.lesson').first()).toBeAttached();
  await expect(page.locator('.pv-kb, .pv-kb-head, .pv-kb-sheet, #bu_kb_umplanen')).toHaveCount(0);
  await expect(page.locator('tr.lesson td.pv-kb-cell')).toHaveCount(0);
  await expect(page.locator('.lesson_table_table thead th').first()).toHaveText('Nr.');
  // the pane with its buttons where they were
  await expect(page.locator('.lesson_pane .bu-save-discard-container .bu-save-changes')).toHaveCount(1);
  await expect(page.locator('.lesson_pane a[href="/api/kursbuch_pdf/Ma_5a"]')).toHaveCount(1);
});

// Phones: the lesson sheet closes when pulled down by its head, like every
// sheet; with unsaved changes it springs back and asks. The chosen row's
// tint reaches past the text, so its accent line doesn't touch the text.
test('Neues Design: Kursbuch-Sheet nach unten wischen, Auswahl mit Abstand', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'touch on phones');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/lessons/Ma_5a');
    const row = weekRow(page);
    const sheet = page.locator('.pv-kb-sheet');
    const pull = async () => {
      const head = (await page.locator('.pv-kb-pane-head').boundingBox())!;
      const cdp = await page.context().newCDPSession(page);
      const x = head.x + head.width / 2, y = head.y + 20;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      for (let i = 1; i <= 8; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y + i * 25 }] });
        await page.waitForTimeout(30);
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    };
    await row.locator('.pv-kb-day').click();
    await expect(sheet).toBeVisible();
    // the chosen row: tint and line left of the text, the text where it was
    await expect(row).toHaveClass(/selected/);
    const other = page.locator('.pv-kb .lesson_table tr.lesson:not(.selected)').first();
    const textX = async (r: typeof row) => (await r.locator('.pv-kb-day').boundingBox())!.x;
    expect(Math.abs((await textX(row)) - (await textX(other)))).toBeLessThan(1);
    expect((await textX(row)) - (await row.boundingBox())!.x).toBeGreaterThanOrEqual(8);
    // pulled down: closed
    await pull();
    await expect(sheet).toBeHidden();
    await expect(page.locator('body')).not.toHaveClass(/pv-sheet-open/);
    // unsaved changes: it stays and asks
    await row.locator('.pv-kb-day').click();
    await expect(sheet).toBeVisible();
    await page.locator('#ti_notizen').fill('nicht speichern');
    await pull();
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText('Änderungen verwerfen?');
    await dialog.getByRole('button', { name: 'Verwerfen' }).click();
    await expect(sheet).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
