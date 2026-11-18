import { test, expect, login, apiLogin, ACCOUNTS, ROLE_ACCOUNTS, dashboardDialog, listAction } from './fixtures';
import { request as playwrightRequest, APIRequestContext, Page, Locator } from '@playwright/test';

// Neues Design (Vorschau): AGs und Angebote (/angebote) as a list with
// actions – »Meine AGs und Angebote« first, then »Alle anderen« by initial
// letter, a search, the participants folded below each row, the actions in
// the row and in »•••« (a sheet on phones): Bearbeiten, Teilen, Zuweisen,
// Übernehmen, Mitverantwortung abgeben, Löschen. src/static/preview/angebote.js
// and .css. The preview is for admins on the test stack; the teacher Tom
// Technik gets it as a test person for the second test.

const ZEUGNIS = ROLE_ACCOUNTS.zeugnis_admin;
const TECHNIK = ROLE_ACCOUNTS.technikteam;

async function as(baseURL: string | undefined, email: string) {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, email);
  return api;
}

async function create(api: APIRequestContext, name: string, recipients: string[]) {
  const created = await api.post('/api/save_angebot', { data: { name, recipients } });
  expect(created.ok()).toBe(true);
  return (await created.json()).angebot;
}

function row(page: Page, name: string): Locator {
  return page.locator('.pv-agb-row', { has: page.locator('.pv-lrow-title', { hasText: name }) });
}

test('Neues Design: AGs ansehen, suchen, teilen, zuweisen, löschen', async ({ page, baseURL }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  const stamp = `${testInfo.project.name} ${Date.now().toString(36)}`;
  const admin = await as(baseURL, ACCOUNTS.admin);
  const technik = await as(baseURL, TECHNIK);
  const own = await create(admin, `Pv-Theater-AG ${stamp}`, [ACCOUNTS.schueler, ACCOUNTS.schueler_oberstufe]);
  const foreign = await create(technik, `Pv-Robotik-AG ${stamp}`, [ACCOUNTS.schueler]);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/angebote');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);

    // ---------- the page: title and main action, a short line, no table ----------
    await expect(page.locator('.pv-lhead h2')).toHaveText('AGs und Angebote');
    const main = page.locator('.pv-lhead .bu-new-angebot');
    await expect(main).toBeVisible();
    await expect(main).toHaveAttribute('aria-label', 'Neues Angebot');
    await expect(main.locator(phone ? '.pv-l-short' : '.pv-l-long')).toBeVisible();
    await expect(main.locator('.pv-l-short')).toHaveText('Neu');
    await expect(page.locator('.pv-agb-intro')).toContainText('Trag hier AGs');
    await expect(page.locator('.pv-agb-intro a[href="/mailing_lists"]')).toBeVisible();
    await expect(page.locator('.angebote-container')).toBeHidden();
    await expect(page.getByText('Bitte tragen Sie hier AGs ein')).toBeHidden();
    expect(await page.locator('.pv-agb-page').innerText()).not.toContain('·');

    // ---------- mine first, then all others by initial letter ----------
    const mine = page.locator('.pv-agb-mine');
    const others = page.locator('.pv-agb-others');
    await expect(mine.locator('.pv-lgroup-label')).toHaveText('Meine AGs und Angebote');
    await expect(others.locator('.pv-lgroup-label')).toHaveText('Alle anderen');
    const ownRow = mine.locator('.pv-agb-row', { hasText: own.info.name });
    const foreignRow = others.locator('.pv-agb-row', { hasText: foreign.info.name });
    await expect(ownRow).toBeVisible();
    await expect(foreignRow).toBeVisible();
    // a short list: no initial letters
    await expect(others.locator('.pv-agb-letter')).toHaveCount(0);
    // the seeded AG of a teacher who left the school
    const orphan = others.locator('.pv-agb-row', { hasText: `Verwaiste Pv-AG ${testInfo.project.name}` });
    await expect(orphan.locator('.pv-agb-who')).toContainText('(nicht mehr an der Schule)');
    await expect(orphan.locator('.pv-agb-count')).toHaveText('keine Teilnehmer');

    // ---------- a row: name, who, how many; the participants folded ----------
    await expect(ownRow.locator('.pv-lrow-title')).toHaveText(own.info.name);
    await expect(ownRow.locator('.pv-agb-who')).toHaveText(/^Verantwortlich: .*Clarke$/);
    const count = ownRow.locator('button.pv-agb-count');
    await expect(count).toHaveText('2 Teilnehmer');
    await expect(count).toHaveAttribute('aria-expanded', 'false');
    await expect(ownRow.locator('.pv-agb-people')).toHaveCount(0);
    // everything at the top: the actions level with the name
    const titleBox = (await ownRow.locator('.pv-lrow-title').boundingBox())!;
    const moreBox = (await ownRow.locator('.pv-lmore').boundingBox())!;
    expect(Math.abs(moreBox.y - titleBox.y)).toBeLessThan(12);
    await count.click();
    await expect(count).toHaveAttribute('aria-expanded', 'true');
    const people = ownRow.locator('.pv-agb-people');
    await expect(people).toBeVisible();
    await expect(people.locator('.pv-agb-klasse')).toHaveCount(2);
    await expect(people.locator('.pv-agb-klasse').first().locator('.pv-agb-kl')).toHaveText('5a');
    await expect(people.locator('.pv-agb-klasse').first().locator('.pv-agb-names')).toContainText('Max');
    // the name folds them again (on phones the whole row)
    await ownRow.locator('.pv-lrow-title').click();
    await expect(people).toBeHidden();
    await expect(count).toHaveAttribute('aria-expanded', 'false');

    // ---------- the search ----------
    const search = page.locator('#ti_ag_search');
    await search.fill(`robotik ${testInfo.project.name}`);
    await expect(page.locator('.pv-agb-row:visible')).toHaveCount(1);
    await expect(foreignRow).toBeVisible();
    await expect(mine).toBeHidden();
    // also by who is responsible
    await search.fill('Technik Robotik');
    await expect(foreignRow).toBeVisible();
    await search.fill('keine-ag-heisst-so');
    await expect(page.locator('.pv-agb-none')).toHaveText('Kein Angebot passt zu »keine-ag-heisst-so«.');
    await search.press('Escape');
    await expect(search).toHaveValue('');
    await expect(ownRow).toBeVisible();
    await expect(page.locator('.pv-agb-none')).toBeHidden();

    // ---------- Bearbeiten opens today's editor (a sheet on phones) ----------
    await listAction(page, ownRow, 'Bearbeiten');
    const editor = page.locator('#angebotModal');
    await expect(editor).toBeVisible();
    await expect(editor).toHaveClass(/pv-sheet/);
    await expect(page.locator('#ti_name')).toHaveValue(own.info.name);
    await expect(page.locator('#ti_name')).toHaveAttribute('placeholder', /Name des Angebots/);
    // (on phones "Schließen" is only there for keyboards: the sheet is pulled down)
    await page.locator('#bu_close_angebot_modal').evaluate((b: HTMLElement) => b.click());
    await expect(editor).toBeHidden();

    // ---------- the menu of someone else's offer (admin): no Bearbeiten, no Löschen ----------
    await expect(foreignRow.locator('.pv-lact', { hasText: 'Bearbeiten' })).toHaveCount(0);
    await foreignRow.locator('.pv-lmore').click();
    const menu = page.locator('.pv-amenu');
    await expect(menu.getByRole('menuitem')).toHaveText(['Teilen', 'Zuweisen']);
    await page.keyboard.press('Escape');
    await expect(menu).toHaveCount(0);

    // ---------- Teilen: add a colleague, then take it back ----------
    await listAction(page, ownRow, 'Teilen');
    const share = page.locator('#angebotShareModal');
    await expect(share).toBeVisible();
    await expect(share.locator('.modal-title')).toHaveText(`»${own.info.name}« teilen`);
    await expect(share.locator('.pv-agb-person')).toHaveCount(1);
    await share.locator('#ti_ag_share').fill('zeugn');
    const shared = page.waitForResponse('**/api/share_angebot');
    await share.locator('.pv-agb-result', { hasText: 'Zeugnis' }).click();
    expect((await shared).status()).toBe(200);
    await expect(share.locator('.pv-agb-person')).toHaveCount(2);
    await expect(share.locator('.pv-agb-person').nth(1)).toContainText('bearbeitet mit');
    // the one already in the list is not offered again
    await share.locator('#ti_ag_share').fill('zeugn');
    await expect(share.locator('.pv-agb-result')).toHaveCount(0);
    await expect(share.locator('.pv-agb-noresult')).toBeVisible();
    await expect(ownRow.locator('.pv-agb-who')).toHaveText(/Clarke, .*Zeugnis$/);
    await share.getByRole('button', { name: /Zeugnis entfernen/ }).click();
    await expect(share.locator('.pv-agb-person')).toHaveCount(1);
    await expect(ownRow.locator('.pv-agb-who')).toHaveText(/^Verantwortlich: .*Clarke$/);
    await share.getByRole('button', { name: 'Fertig' }).evaluate((b: HTMLElement) => b.click());
    await expect(share).toBeHidden();

    // ---------- Zuweisen: someone else becomes responsible ----------
    await listAction(page, foreignRow, 'Zuweisen');
    const assign = page.locator('#angebotAssignModal');
    await expect(assign).toBeVisible();
    await expect(assign.locator('.pv-agb-now')).toContainText('Technik');
    await expect(page.locator('#bu_ag_assign')).toBeDisabled();
    await assign.locator('#ti_ag_assign').fill('zeugn');
    await assign.locator('.pv-agb-result', { hasText: 'Zeugnis' }).click();
    await expect(assign.locator('.pv-agb-chosen')).toContainText('Zeugnis');
    await expect(page.locator('#cb_ag_keep_previous')).toBeChecked();
    await expect(assign.locator('.pv-agb-keep')).toContainText('Technik bearbeitet das Angebot weiter mit');
    await page.locator('#bu_ag_assign').click();
    await expect(assign).toBeHidden();
    await expect(foreignRow.locator('.pv-agb-who')).toHaveText(/Zeugnis, .*Technik$/);

    // ---------- Löschen: in the menu, with a confirmation ----------
    await listAction(page, ownRow, 'Löschen');
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(own.info.name);
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    await expect(ownRow).toHaveCount(0);
    await page.reload();
    await expect(page.locator('.pv-lrow-title', { hasText: own.info.name })).toHaveCount(0);

    // ---------- a new offer appears under »Meine« ----------
    await main.click();
    await expect(editor).toBeVisible();
    await page.locator('#ti_name').pressSequentially(`Pv-Neue-AG ${stamp}`);
    await page.locator('#ti_recipients').pressSequentially('Max Muster');
    await page.locator('.recipient-input-dropdown .recipient').first().click();
    await page.locator('#bu_save_angebot').click();
    await expect(editor).toBeHidden();
    await expect(mine.locator('.pv-agb-row', { hasText: `Pv-Neue-AG ${stamp}` })).toBeVisible();
    await expect(mine.locator('.pv-agb-row', { hasText: `Pv-Neue-AG ${stamp}` }).locator('.pv-agb-count')).toHaveText('1 Teilnehmer');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    const all = (await (await admin.get('/angebote')).text()).match(/var stored_angebote = (.*);\n/);
    const list = all ? JSON.parse(all[1]) : [];
    const zeugnis = await as(baseURL, ZEUGNIS);
    for (const a of list.filter((x: any) => x.info.name.includes(stamp))) {
      for (const api of [admin, technik, zeugnis]) await api.post('/api/delete_angebot', { data: { aid: a.aid } });
    }
    for (const api of [admin, technik, zeugnis]) await api.dispose();
  }
});

// A teacher (test person for the preview): a shared offer is under »Meine«,
// they edit it and can give it up; an AG whose teacher left can be taken over.
test('Neues Design: geteilte AG und Übernehmen als Lehrkraft', async ({ page, baseURL }, testInfo) => {
  const stamp = `${testInfo.project.name} ${Date.now().toString(36)}`;
  const admin = await as(baseURL, ACCOUNTS.admin);
  const sharedAg = await create(admin, `Pv-Chor ${stamp}`, [ACCOUNTS.schueler]);
  expect((await admin.post('/api/share_angebot', { data: { aid: sharedAg.aid, email: TECHNIK } })).ok()).toBe(true);
  expect((await admin.post('/api/set_ui_preview_tester', { data: { email: TECHNIK, mode: 'on' } })).ok()).toBe(true);
  try {
    await login(page, TECHNIK);
    await page.goto('/angebote');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    const mine = page.locator('.pv-agb-mine');
    const shared = mine.locator('.pv-agb-row', { hasText: sharedAg.info.name });
    await expect(shared).toBeVisible();
    await expect(shared.locator('.pv-agb-who')).toHaveText(/Clarke, .*Technik$/);
    // a co-owner edits, but neither shares nor deletes
    await shared.locator('.pv-lmore').click();
    await expect(page.locator('.pv-amenu').getByRole('menuitem')).toHaveText(
      testInfo.project.name === 'mobile' ? ['Bearbeiten', 'Mitverantwortung abgeben'] : ['Mitverantwortung abgeben']);
    await page.keyboard.press('Escape');
    await expect(page.locator('.pv-amenu')).toHaveCount(0);
    await listAction(page, shared, 'Bearbeiten');
    await expect(page.locator('#angebotModal')).toBeVisible();
    await expect(page.locator('#bu_delete_angebot')).toBeHidden();
    await page.locator('#ti_name').fill(`Pv-Chor ${stamp} neu`);
    await page.locator('#ti_name').press('End');
    await page.locator('#bu_save_angebot').click();
    await expect(page.locator('#angebotModal')).toBeHidden();
    const renamed = mine.locator('.pv-agb-row', { hasText: `Pv-Chor ${stamp} neu` });
    await expect(renamed).toBeVisible();
    await expect(renamed.locator('.pv-agb-who')).toHaveText(/Clarke, .*Technik$/);

    // ---------- giving it up ----------
    await listAction(page, renamed, 'Mitverantwortung abgeben');
    const dialog = dashboardDialog(page);
    await expect(dialog).toContainText('nicht mehr bearbeiten');
    await dialog.getByRole('button', { name: 'Abgeben' }).click();
    const gone = page.locator('.pv-agb-others .pv-agb-row', { hasText: `Pv-Chor ${stamp} neu` });
    await expect(gone).toBeVisible();
    await expect(mine.locator('.pv-agb-row', { hasText: `Pv-Chor ${stamp}` })).toHaveCount(0);
    await expect(gone.locator('.pv-lact', { hasText: 'Bearbeiten' })).toHaveCount(0);

    // ---------- taking over an AG whose teacher left ----------
    // (test/e2e/seed.cypher, one per Playwright project)
    const orphanName = `Verwaiste Pv-AG ${testInfo.project.name}`;
    const orphan = page.locator('.pv-agb-others .pv-agb-row', { hasText: orphanName });
    await expect(orphan.locator('.pv-agb-who')).toContainText('(nicht mehr an der Schule)');
    await listAction(page, orphan, 'Übernehmen');
    await expect(dialog).toContainText(orphanName);
    await dialog.getByRole('button', { name: 'Übernehmen' }).click();
    const taken = mine.locator('.pv-agb-row', { hasText: orphanName });
    await expect(taken).toBeVisible();
    await expect(taken.locator('.pv-agb-who')).toHaveText(/^Verantwortlich: .*Technik$/);
    // now it is the teacher's: Löschen is in the menu
    await taken.locator('.pv-lmore').click();
    await expect(page.locator('.pv-amenu').getByRole('menuitem', { name: 'Löschen' })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('.pv-amenu')).toHaveCount(0);
  } finally {
    await admin.post('/api/set_ui_preview_tester', { data: { email: TECHNIK, mode: 'off' } });
    await admin.post('/api/delete_angebot', { data: { aid: sharedAg.aid } });
    await admin.dispose();
  }
});
