import { test, expect, login, apiLogin, ACCOUNTS, ROLE_ACCOUNTS } from './fixtures';
import { request as playwrightRequest, APIRequestContext } from '@playwright/test';

// AGs und Angebote (/angebote, include/angebote.rb). An offer has one
// responsible person (who created it, or whom an admin assigned it to) and
// may be shared with others who run offers; they edit it like the
// responsible person, deleting and sharing stay with the responsible person
// (sharing also with admins). These tests cover the server's rules and
// today's page (the new design: design-preview-angebote.spec.ts).

const ZEUGNIS = ROLE_ACCOUNTS.zeugnis_admin;   // teacher, not an admin
const TECHNIK = ROLE_ACCOUNTS.technikteam;     // teacher, not an admin

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

// Profil, "Meine AGs und Angebote" (students): the person running an AG is a
// teacher, so students see the official name ("Herr Clarke"), not the first
// name (include/angebote.rb, get_angebote_for_session_user) – of everyone
// who runs it.
test('Meine AGs: Lehrkräfte mit offiziellem Namen', async ({ page, baseURL }) => {
  const api = await as(baseURL, ACCOUNTS.admin);
  const name = `Test-AG ${Date.now()}`;
  const angebot = await create(api, name, [ACCOUNTS.schueler]);
  const aid = angebot.aid;
  try {
    await login(page, ACCOUNTS.schueler);
    await page.goto('/profil');
    const entry = page.locator('li', { hasText: name });
    await expect(entry).toContainText('(Herr Clarke)');
    await expect(entry).not.toContainText('Scott');
    // shared with a colleague: both, the responsible one first
    expect((await api.post('/api/share_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(true);
    await page.reload();
    await expect(entry).toContainText('(Herr Clarke, Frau Zeugnis)');
  } finally {
    expect((await api.post('/api/delete_angebot', { data: { aid } })).ok()).toBe(true);
    await api.dispose();
  }
});

test('Teilen und Zuweisen: wer was darf', async ({ baseURL }) => {
  const admin = await as(baseURL, ACCOUNTS.admin);
  const zeugnis = await as(baseURL, ZEUGNIS);
  const technik = await as(baseURL, TECHNIK);
  const student = await as(baseURL, ACCOUNTS.schueler);
  const name = `Rechte-AG ${Date.now()}`;
  const angebot = await create(admin, name, [ACCOUNTS.schueler]);
  const aid = angebot.aid;
  expect(angebot.owner).toBe(ACCOUNTS.admin);
  expect(angebot.recipients).toEqual([ACCOUNTS.schueler]);
  // not shared: no co_owners (today's page gets the same data as before)
  expect(angebot.co_owners).toBeUndefined();
  const update = (api: APIRequestContext, newName: string) =>
    api.post('/api/update_angebot', { data: { aid, name: newName, recipients: [ACCOUNTS.schueler, ACCOUNTS.schueler_oberstufe] } });
  try {
    // ---------- a teacher without rights: nothing ----------
    expect((await update(technik, 'Übernommen')).ok()).toBe(false);
    expect((await technik.post('/api/share_angebot', { data: { aid, email: TECHNIK } })).ok()).toBe(false);
    expect((await technik.post('/api/delete_angebot', { data: { aid } })).ok()).toBe(false);
    expect((await technik.post('/api/assign_angebot', { data: { aid, email: TECHNIK } })).ok()).toBe(false);
    // the responsible person is still there: no taking over
    expect((await technik.post('/api/take_over_angebot', { data: { aid } })).ok()).toBe(false);
    // students not at all
    expect((await student.post('/api/share_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(false);

    // ---------- the responsible person shares ----------
    // only with people who run offers, not with the responsible person
    expect((await admin.post('/api/share_angebot', { data: { aid, email: ACCOUNTS.schueler } })).ok()).toBe(false);
    expect((await admin.post('/api/share_angebot', { data: { aid, email: ACCOUNTS.admin } })).ok()).toBe(false);
    expect((await admin.post('/api/share_angebot', { data: { aid, email: 'niemand@beispielschule.de' } })).ok()).toBe(false);
    let res = await admin.post('/api/share_angebot', { data: { aid, email: ZEUGNIS } });
    expect(res.ok()).toBe(true);
    expect((await res.json()).angebot.co_owners).toEqual([ZEUGNIS]);

    // ---------- the co-owner edits, but neither shares nor deletes ----------
    res = await update(zeugnis, `${name} (geändert)`);
    expect(res.ok()).toBe(true);
    const changed = (await res.json()).angebot;
    expect(changed.info.name).toBe(`${name} (geändert)`);
    expect(changed.recipients).toHaveLength(2);
    expect(changed.owner).toBe(ACCOUNTS.admin);
    expect((await zeugnis.post('/api/share_angebot', { data: { aid, email: TECHNIK } })).ok()).toBe(false);
    expect((await zeugnis.post('/api/delete_angebot', { data: { aid } })).ok()).toBe(false);
    // someone else can't end the sharing
    expect((await technik.post('/api/unshare_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(false);
    // the co-owner gives it up: no more editing
    res = await zeugnis.post('/api/unshare_angebot', { data: { aid, email: ZEUGNIS } });
    expect(res.ok()).toBe(true);
    expect((await res.json()).angebot.co_owners).toBeUndefined();
    expect((await update(zeugnis, 'Nicht mehr')).ok()).toBe(false);

    // ---------- an admin assigns it to someone else ----------
    expect((await zeugnis.post('/api/assign_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(false);
    expect((await admin.post('/api/assign_angebot', { data: { aid, email: ACCOUNTS.schueler } })).ok()).toBe(false);
    expect((await admin.post('/api/assign_angebot', { data: { aid, email: TECHNIK, keep_previous: 'ja' } })).ok()).toBe(false);
    res = await admin.post('/api/assign_angebot', { data: { aid, email: TECHNIK, keep_previous: true } });
    expect(res.ok()).toBe(true);
    let assigned = (await res.json()).angebot;
    expect(assigned.owner).toBe(TECHNIK);
    // the previous one stays co-owner
    expect(assigned.co_owners).toEqual([ACCOUNTS.admin]);
    // the new responsible person edits, shares and ends sharing
    expect((await update(technik, name)).ok()).toBe(true);
    expect((await technik.post('/api/share_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(true);
    res = await technik.post('/api/unshare_angebot', { data: { aid, email: ACCOUNTS.admin } });
    expect((await res.json()).angebot.co_owners).toEqual([ZEUGNIS]);
    // an admin shares any offer (and ends the sharing)
    expect((await admin.post('/api/unshare_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(true);
    // assigning to a co-owner: they are responsible, no longer co-owner
    expect((await technik.post('/api/share_angebot', { data: { aid, email: ZEUGNIS } })).ok()).toBe(true);
    res = await admin.post('/api/assign_angebot', { data: { aid, email: ZEUGNIS } });
    assigned = (await res.json()).angebot;
    expect(assigned.owner).toBe(ZEUGNIS);
    expect(assigned.co_owners).toBeUndefined();
    expect((await admin.post('/api/assign_angebot', { data: { aid, email: TECHNIK, keep_previous: false } })).ok()).toBe(true);
  } finally {
    // whoever is responsible by now deletes it
    for (const api of [technik, zeugnis, admin]) await api.post('/api/delete_angebot', { data: { aid } });
    const list = await (await admin.get('/angebote')).text();
    expect(list).not.toContain(name);
    for (const api of [admin, zeugnis, technik, student]) await api.dispose();
  }
});

// The responsible teacher left the school (test/e2e/seed.cypher): any
// teacher may take the AG over, then it is theirs.
test('Übernehmen: eine AG ohne Verantwortliche', async ({ baseURL }, testInfo) => {
  const aid = `e2everwaist${testInfo.project.name}`;
  const technik = await as(baseURL, TECHNIK);
  const zeugnis = await as(baseURL, ZEUGNIS);
  try {
    // nobody edits it before
    expect((await technik.post('/api/update_angebot', { data: { aid, name: 'x', recipients: [] } })).ok()).toBe(false);
    const res = await technik.post('/api/take_over_angebot', { data: { aid } });
    expect(res.ok()).toBe(true);
    const angebot = (await res.json()).angebot;
    expect(angebot.owner).toBe(TECHNIK);
    expect(angebot.recipients).toEqual([]);
    // now it has someone responsible again: nobody else takes it over
    expect((await zeugnis.post('/api/take_over_angebot', { data: { aid } })).ok()).toBe(false);
    expect((await technik.post('/api/update_angebot', { data: { aid, name: angebot.info.name, recipients: [ACCOUNTS.schueler] } })).ok()).toBe(true);
  } finally {
    await technik.post('/api/delete_angebot', { data: { aid } });
    await technik.dispose();
    await zeugnis.dispose();
  }
});

// Today's page (design preview off): a co-owner sees both names and edits
// the offer, but has no delete button; the others' rows stay closed.
test('Altes Design: Mitverantwortliche bearbeiten', async ({ page, baseURL }) => {
  const admin = await as(baseURL, ACCOUNTS.admin);
  const technik = await as(baseURL, TECHNIK);
  const stamp = Date.now();
  const shared = await create(admin, `Geteilte AG ${stamp}`, [ACCOUNTS.schueler]);
  const foreign = await create(technik, `Fremde AG ${stamp}`, [ACCOUNTS.schueler]);
  // without participants: an empty cell, not "null (undefined)"
  const empty = await create(technik, `Leere AG ${stamp}`, [ACCOUNTS.schueler]);
  expect((await technik.post('/api/update_angebot', { data: { aid: empty.aid, name: empty.info.name, recipients: [] } })).ok()).toBe(true);
  expect((await admin.post('/api/share_angebot', { data: { aid: shared.aid, email: ZEUGNIS } })).ok()).toBe(true);
  try {
    await login(page, ZEUGNIS);
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.goto('/angebote');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(page.locator('.pv-agb-page')).toHaveCount(0);
    const row = page.locator('.angebote-here tr', { hasText: `Geteilte AG ${stamp}` });
    await expect(row).toHaveClass(/clickable/);
    await expect(row).toContainText(/Clarke, .*Zeugnis/);
    await expect(page.locator('.angebote-here tr', { hasText: `Fremde AG ${stamp}` })).not.toHaveClass(/clickable/);
    const emptyRow = page.locator('.angebote-here tr', { hasText: `Leere AG ${stamp}` });
    await expect(emptyRow).toBeVisible();
    await expect(emptyRow).not.toContainText('null');
    await expect(emptyRow).not.toContainText('undefined');

    await row.click();
    const modal = page.locator('#angebotModal');
    await expect(modal).toBeVisible();
    await expect(page.locator('#ti_name')).toHaveValue(`Geteilte AG ${stamp}`);
    await expect(page.locator('#bu_delete_angebot')).toBeHidden();
    await page.locator('#ti_name').fill(`Geteilte AG ${stamp} neu`);
    await page.locator('#ti_name').press('End');
    await page.locator('#bu_save_angebot').click();
    await expect(modal).toBeHidden();
    await expect(page.locator('.angebote-here tr', { hasText: `Geteilte AG ${stamp} neu` })).toContainText(/Clarke, .*Zeugnis/);
    await page.reload();
    await expect(page.locator('.angebote-here tr', { hasText: `Geteilte AG ${stamp} neu` })).toHaveClass(/clickable/);
  } finally {
    await admin.post('/api/delete_angebot', { data: { aid: shared.aid } });
    await technik.post('/api/delete_angebot', { data: { aid: foreign.aid } });
    await technik.post('/api/delete_angebot', { data: { aid: empty.aid } });
    await admin.dispose();
    await technik.dispose();
  }
});

// The responsible person still deletes it on today's page.
test('Altes Design: Löschen durch die Verantwortlichen', async ({ page, baseURL }) => {
  const admin = await as(baseURL, ACCOUNTS.admin);
  const name = `Lösch-AG ${Date.now()}`;
  const angebot = await create(admin, name, [ACCOUNTS.schueler]);
  try {
    await login(page, ACCOUNTS.admin);
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.goto('/angebote');
    await page.locator('.angebote-here tr', { hasText: name }).click();
    await expect(page.locator('#bu_delete_angebot')).toBeVisible();
    await page.locator('#bu_delete_angebot').click();
    await page.locator('#__template_modal').getByRole('button', { name: /Angebot löschen/ }).click();
    await expect(page.locator('#angebotModal')).toBeHidden();
    await expect(page.locator('.angebote-here tr', { hasText: name })).toHaveCount(0);
  } finally {
    await admin.post('/api/delete_angebot', { data: { aid: angebot.aid } });
    await admin.dispose();
  }
});
