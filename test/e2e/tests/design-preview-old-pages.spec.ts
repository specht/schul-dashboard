import { test, expect, login, ACCOUNTS } from './fixtures';

// Neues Design: what helps the pages not yet built for it (preview.css,
// preview.js plain_tables): a panel for pages in a full-width white strip,
// plain tables as list rows where the list is narrow, a sentence for an
// empty table, the floating error message beside the sidebar. The old
// design stays as it is.

test('Neues Design: Seiten im weißen Streifen bekommen eine Fläche', async ({ page }, testInfo) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/admin');
    const panel = page.locator('#main_container > .container-fluid.white');
    await expect(panel).toBeVisible();
    expect(await panel.evaluate((el) => getComputedStyle(el).borderTopLeftRadius)).toBe('16px');
    const box = (await panel.boundingBox())!;
    const width = page.viewportSize()!.width;
    // not up to the window's edge
    expect(box.x + box.width).toBeLessThanOrEqual(width - 11);
    // the page never scrolls sideways (tables scroll inside the panel)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    if (testInfo.project.name === 'mobile') {
      // the teachers' table as list rows: the first cell as the title, the
      // others labelled
      const table = panel.locator('table.pv-gt').first();
      await expect(table).toHaveClass(/pv-gt-list/);
      await expect(table.locator('thead')).toBeHidden();
      const row = table.locator('tbody > tr').first();
      expect(await row.evaluate((el) => getComputedStyle(el).display)).toBe('flex');
      expect(await row.locator('td').first().evaluate((el) => getComputedStyle(el).fontWeight)).toBe('700');
      await expect(row.locator('td').nth(1)).toHaveAttribute('data-label', /\S/);
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

const TABLES = `
  <div id="pv_probe">
    <table class="table" id="probe_list"><thead><tr><th>Name</th><th>Klasse</th><th>Raum</th><th>Aktion</th></tr></thead>
      <tbody><tr><td>Mustermann</td><td>5a</td><td>–</td><td><button class="btn btn-sm btn-secondary">Löschen</button></td></tr></tbody></table>
    <table class="table" id="probe_empty"><thead><tr><th>Datei</th><th>Größe</th></tr></thead><tbody></tbody></table>
    <table class="table" id="probe_matrix"><thead><tr><th>Name</th>${Array.from({ length: 14 }, (_, i) => `<th>${i + 1}</th>`).join('')}</tr></thead>
      <tbody><tr><td>Mustermann</td>${Array.from({ length: 14 }, () => '<td>x</td>').join('')}</tr></tbody></table>
  </div>`;

test('Neues Design: einfache Tabellen als Listenzeilen, leere sagen es', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    await page.evaluate((html) => document.querySelector('#main_container .container')!.insertAdjacentHTML('afterbegin', html), TABLES);
    const list = page.locator('#probe_list');
    await expect(list).toHaveClass(/pv-gt-list/);
    await expect(list.locator('td').nth(1)).toHaveAttribute('data-label', 'Klasse');
    if (phone) {
      await expect(list.locator('thead')).toBeHidden();
      // a fact without a value (»–«) is left out, the control comes last
      await expect(list.locator('td').nth(2)).toBeHidden();
      const order = await list.locator('td').evaluateAll((tds) => tds.map((td) => getComputedStyle(td).order));
      expect(order[3]).toBe('10');
    } else {
      await expect(list.locator('thead')).toBeVisible();
    }
    // empty: a sentence instead of a bare header, gone once a row is there
    const empty = page.locator('#probe_empty');
    const note = page.locator('#probe_empty + .pv-gt-empty-note');
    await expect(note).toHaveText('Keine Einträge.');
    await expect(note).toBeVisible();
    await expect(empty).toBeHidden();
    await page.evaluate(() => document.querySelector('#probe_empty tbody')!.insertAdjacentHTML('beforeend', '<tr><td>plan.pdf</td><td>1 MB</td></tr>'));
    await expect(empty).toBeVisible();
    await expect(note).toBeHidden();
    // a matrix stays a table, scrolls inside its frame, the first column stays
    const matrix = page.locator('#probe_matrix');
    await expect(matrix).toHaveClass(/pv-gt-matrix/);
    await expect(matrix.locator('thead')).toBeVisible();
    expect(await matrix.locator('td').first().evaluate((el) => getComputedStyle(el).position)).toBe('sticky');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Ohne Vorschau: einfache Tabellen bleiben, wie sie sind', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/profil');
  await page.evaluate((html) => document.querySelector('#main_container .container')!.insertAdjacentHTML('afterbegin', html), TABLES);
  await page.waitForTimeout(900);
  await expect(page.locator('#main_container .pv-gt, #main_container .pv-gt-wrap, #main_container .pv-gt-empty-note')).toHaveCount(0);
  await expect(page.locator('#probe_list td').nth(1)).not.toHaveAttribute('data-label', /.*/);
});

test('Neues Design: Fehlermeldung unten neben der Seitenleiste', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the sidebar is on larger screens');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const lesson = await page.locator('a[href^="/lessons/"]').first().getAttribute('href');
    await page.goto(lesson!);
    await page.evaluate(() => (window as any).show_error_message('Bei der Bearbeitung der Anfrage ist ein Fehler aufgetreten.'));
    const message = page.locator('.api_messages.overlay');
    await expect(message).toBeVisible();
    const box = (await message.boundingBox())!;
    const side = (await page.locator('nav.navbar').boundingBox())!;
    expect(box.x).toBeGreaterThanOrEqual(side.x + side.width + 12);
    expect(box.width).toBeLessThanOrEqual(641);
    // at the bottom: never over the page's title and tabs
    expect(box.y + box.height).toBeGreaterThan(page.viewportSize()!.height - 120);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
