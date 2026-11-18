import { test, expect, login, apiLogin, ACCOUNTS, ROLE_ACCOUNTS } from './fixtures';

// Neues Design (Vorschau): E-Mail-Verteiler (/mailing_lists) as a list with
// actions – sections per class or group of lists, a search, the address of a
// list copied with one click, the recipients in a dialog (a sheet on phones,
// loaded with /api/mailing_list_recipients). src/static/preview/mailing_lists.js
// and .css. The preview is for admins only on the test stack; the admin
// (a teacher, class teacher of 5a) may see the recipients. Today's page stays
// as it was (last test).

const DOMAIN = 'verteiler.beispielschule.de';

test('Neues Design: Verteiler suchen, Adresse kopieren, Empfänger zeigen', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/mailing_lists');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);

    // ---------- the page: a title, a quiet line, no yellow box, no table ----------
    await expect(page.locator('.pv-lhead h2')).toHaveText('E-Mail-Verteiler');
    await expect(page.locator('.pv-ml-intro')).toContainText('die Sie verwenden können');
    await expect(page.locator('.alert-warning', { hasText: 'Hier sehen Sie alle E-Mail-Verteiler' })).toBeHidden();
    await expect(page.locator('.ml-table table')).toHaveCount(0);
    await expect(page.locator('.list_email_emails')).toHaveCount(0);

    // ---------- sections: empty ones left out, one's own class open ----------
    const sections = page.locator('.pv-ml-section');
    const own = sections.filter({ has: page.getByRole('button', { name: /^Klasse 5a\b/ }) });
    await expect(own).toHaveCount(1);
    await expect(own.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'true');
    await expect(own.locator('.pv-lgroup-count')).toHaveText('3 Verteiler');
    await expect(sections.filter({ hasText: 'Klasse 5b' })).toHaveCount(0);
    const school = sections.filter({ has: page.getByRole('button', { name: /^Gesamte Schule\b/ }) });
    await expect(school.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'false');
    await expect(school.locator('.pv-lgroup-body')).toBeHidden();
    await school.locator('.pv-lgroup-toggle').click();
    await expect(school.locator('.pv-ml-row', { hasText: 'Gesamtes Kollegium' })).toBeVisible();
    await school.locator('.pv-lgroup-toggle').click();
    await expect(school.locator('.pv-lgroup-body')).toBeHidden();

    // ---------- a row: name, address, count ----------
    const row = own.locator('.pv-ml-row', { hasText: 'SuS der Klasse 5a' });
    await expect(row.locator('.pv-lrow-title')).toHaveText('SuS der Klasse 5a');
    await expect(row.locator('.pv-ml-addr')).toHaveText(new RegExp(`^klasse\\.5a@${DOMAIN.replace(/\./g, '\\.')}`));
    await expect(row.locator('.pv-ml-count')).toHaveText('3 Adressen');
    // "Empfänger" in the row on larger screens; on phones the row opens it
    await expect(row.locator('.pv-lact', { hasText: 'Empfänger' })).toBeVisible({ visible: !phone });
    await expect(row.locator('.pv-lrow-chev')).toBeVisible({ visible: phone });
    // no separator dot anywhere
    expect(await page.locator('.pv-ml-page').innerText()).not.toContain('·');

    // ---------- one click copies the address ----------
    await row.locator('.pv-ml-addr').click();
    await expect(row.locator('.pv-ml-addr')).toHaveClass(/pv-ml-copied/);
    await expect(row.locator('.pv-ml-addr .pv-ml-done')).toBeVisible();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`klasse.5a@${DOMAIN}`);
    // copying does not open the list
    await expect(page.locator('#mailingListModal')).toHaveCount(0);
    await expect(row.locator('.pv-ml-addr')).not.toHaveClass(/pv-ml-copied/, { timeout: 5000 });

    // ---------- the search over all lists ----------
    const search = page.locator('#ti_ml_search');
    await search.fill('eltern 5a');
    await expect(page.locator('.pv-ml-row:visible')).toHaveCount(1);
    await expect(page.locator('.pv-ml-row:visible')).toHaveText(/Eltern der Klasse 5a/);
    await search.fill('klassenstufe');
    // folded sections open while searching
    await expect(page.locator('.pv-ml-section:visible')).not.toHaveCount(0);
    for (const s of await page.locator('.pv-ml-section:visible').all()) {
      await expect(s.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'true');
    }
    await search.fill('kein-verteiler-heisst-so');
    await expect(page.locator('.pv-ml-none')).toHaveText('Kein Verteiler passt zu »kein-verteiler-heisst-so«.');
    await expect(page.locator('.pv-ml-section:visible')).toHaveCount(0);
    // clearing it brings back the sections as they were
    await search.press('Escape');
    await expect(search).toHaveValue('');
    await expect(page.locator('.pv-ml-none')).toBeHidden();
    await expect(own.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'true');
    await expect(school.locator('.pv-lgroup-toggle')).toHaveAttribute('aria-expanded', 'false');

    // ---------- the recipients: a dialog, a sheet on phones ----------
    const loaded = page.waitForResponse('**/api/mailing_list_recipients');
    if (phone) await row.locator('.pv-lrow-title').click();
    else await row.locator('.pv-lact', { hasText: 'Empfänger' }).click();
    expect((await loaded).status()).toBe(200);
    const modal = page.locator('#mailingListModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('.modal-title')).toHaveText('SuS der Klasse 5a');
    await expect(modal.locator('.pv-ml-modal-facts .pv-ml-count')).toHaveText('3 Adressen');
    const people = modal.locator('.pv-ml-person');
    await expect(people).toHaveCount(3);
    // a short list needs no search
    await expect(modal.locator('.pv-ml-people-search')).toBeHidden();
    await expect(modal.locator('.pv-ml-bcc')).toContainText('BCC');
    const addresses = await people.locator('.pv-ml-addr-text').allTextContents();
    expect(addresses.every((a) => a.endsWith('@mail.beispielschule.de'))).toBe(true);
    // "Alle Adressen kopieren": for BCC when the list itself does not work
    await modal.locator('#bu_ml_copy_all').click();
    await expect(modal.locator('#bu_ml_copy_all')).toHaveClass(/pv-ml-copied/);
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(addresses.join('; '));
    // one address
    await people.first().locator('.pv-ml-addr').click();
    await expect(people.first().locator('.pv-ml-addr')).toHaveClass(/pv-ml-copied/);
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(addresses[0]);
    // back closes the dialog and stays on the page
    await page.goBack();
    await expect(modal).toBeHidden();
    await expect(page).toHaveURL(/\/mailing_lists$/);

    // ---------- a long list: a search over its recipients ----------
    await search.fill('Alle Schülerinnen');
    const all = page.locator('.pv-ml-row:visible', { hasText: 'Alle Schülerinnen und Schüler' });
    await expect(all).toHaveCount(1);
    const total = parseInt((await all.locator('.pv-ml-count').innerText()).replace(/\D/g, ''), 10);
    expect(total).toBeGreaterThan(12);
    await all.locator('.pv-lrow-title').click();
    await expect(modal).toBeVisible();
    await expect(people).toHaveCount(Math.min(total, 100));
    const own_search = modal.locator('#ti_ml_people_search');
    await expect(own_search).toBeVisible();
    await own_search.fill('Mustermann');
    await expect(people.first()).toContainText('Mustermann');
    expect(await people.count()).toBeLessThan(total);
    await own_search.fill('niemand-heisst-so');
    await expect(modal.locator('.pv-ml-people .pv-lempty')).toContainText('Niemand in diesem Verteiler');
    await page.keyboard.press('Escape');
    await expect(modal).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Some list names carry markup for the old table (Antikenfahrt: the flag in a
// <span>, GROUP_AF_ICONS); the new page shows the name as text, not the tags.
test('Neues Design: Verteilernamen ohne HTML', async ({ page, playwright, baseURL }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  // an upper-school student in a trip group makes the group's lists appear
  // (set by whoever manages the Antikenfahrt; the keys cycle '', 'it', 'gr')
  const manager = await playwright.request.newContext({ baseURL });
  await apiLogin(manager, ROLE_ACCOUNTS.zeugnis_admin);
  const toggle = async () => {
    const r = await manager.post('/api/toggle_group_af_for_user', { data: { email: ACCOUNTS.schueler_oberstufe } });
    expect(r.ok()).toBe(true);
    return (await r.json()).group_af as string;
  };
  let group = await toggle();
  try {
    expect(group).not.toBe('');
    await page.goto('/mailing_lists');
    await page.locator('#ti_ml_search').fill('Antikenfahrt');
    const rows = page.locator('.pv-ml-row', { hasText: 'Antikenfahrt' });
    await expect(rows.first()).toBeVisible();
    for (const text of await rows.allInnerTexts()) {
      expect(text).not.toContain('<');
      expect(text).not.toContain('font-size');
    }
  } finally {
    for (let i = 0; i < 3 && group !== ''; i++) group = await toggle();
    await manager.dispose();
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Empfänger eines Verteilers: nur für Berechtigte und nur für Verteiler der Seite', async ({ playwright }) => {
  const admin = await playwright.request.newContext({ baseURL: process.env.BASE_URL });
  const sv = await playwright.request.newContext({ baseURL: process.env.BASE_URL });
  const anon = await playwright.request.newContext({ baseURL: process.env.BASE_URL });
  try {
    await apiLogin(admin, ACCOUNTS.admin);
    const ok = await admin.post('/api/mailing_list_recipients', { data: { email: `klasse.5a@${DOMAIN}` } });
    expect(ok.status()).toBe(200);
    const body = await ok.json();
    expect(body.recipients).toHaveLength(3);
    expect(body.recipients[0]).toEqual({ name: expect.any(String), email: expect.stringContaining('@') });
    // not a list of the page
    expect((await admin.post('/api/mailing_list_recipients', { data: { email: 'nobody@example.com' } })).status()).not.toBe(200);
    expect((await admin.post('/api/mailing_list_recipients', { data: {} })).status()).not.toBe(200);
    // the student council may use the lists but sees no recipients (as today)
    await apiLogin(sv, ROLE_ACCOUNTS.sv);
    expect((await sv.post('/api/mailing_list_recipients', { data: { email: `klasse.5a@${DOMAIN}` } })).status()).not.toBe(200);
    expect((await anon.post('/api/mailing_list_recipients', { data: { email: `klasse.5a@${DOMAIN}` } })).status()).not.toBe(200);
  } finally {
    await admin.dispose();
    await sv.dispose();
    await anon.dispose();
  }
});

test('Altes Design: E-Mail-Verteiler als Tabelle wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/mailing_lists');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('h3', { hasText: 'E-Mail-Verteiler' })).toBeVisible();
  await expect(page.locator('.alert-warning', { hasText: 'Hier sehen Sie alle E-Mail-Verteiler' })).toBeVisible();
  await expect(page.locator('.pv-ml-page')).toHaveCount(0);
  await expect(page.locator('.ml-table th', { hasText: 'Klasse 5a' })).toBeVisible();
  const label = page.locator('.list_email_label', { hasText: 'SuS der Klasse 5a' });
  const listRow = page.locator('tr.user_row', { has: label });
  await expect(listRow.locator('input')).toHaveValue(`klasse.5a@${DOMAIN}`);
  // the recipients unfold below the list, with the line for BCC
  const emails = page.locator(`tbody.list_email_emails[data-list-email="klasse.5a@${DOMAIN}"]`);
  await expect(emails).toBeHidden();
  await listRow.locator('.bu-toggle-adresses').click();
  await expect(emails).toBeVisible();
  await expect(emails.locator('tr.user_row')).toHaveCount(4);
  await expect(emails).toContainText('Bei Verteiler-Ausfall (bitte in BCC)');
  await listRow.locator('.bu-toggle-adresses').click();
  await expect(emails).toBeHidden();
});
