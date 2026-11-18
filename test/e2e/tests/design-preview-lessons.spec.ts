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

// a lesson of the displayed week (the page has a lesson every school day)
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
    await row.click();
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
    await row.click();
    await expect(sheet).toBeVisible();
    await expect(page.locator('body')).toHaveClass(/pv-sheet-open/);
    await page.goBack();
    await expect(sheet).toBeHidden();
    await expect(page).toHaveURL(/\/lessons\/Ma_5a/);
    await expect(page.locator('body')).not.toHaveClass(/pv-sheet-open/);
    await expect(row).not.toHaveClass(/selected/);

    // unsaved changes: back asks first, "Weiter bearbeiten" keeps the sheet
    await row.click();
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
