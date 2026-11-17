import type { APIRequestContext, Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, dashboardDialog } from './fixtures';

// Example data (test/prepare_example_data.rb): class 5a has its homeroom 108,
// where Clarke (admin, class teacher) teaches it. Both Clarke and Frieda
// Fachraum also teach 5a in room 317 – a subject room, where each of them
// makes an own seating plan with own desks.
const KLASSE = '5a';
// only in the test stack's copy of the example data
const FACHLEHRKRAFT = 'fachraum@beispielschule.de';
const FACHRAUM = '317';

const CLARKE_DESKS = [0, 1, 3, 4].flatMap((x) => [0, 2].map((y) => [x, y])); // 8 seats
const OWN_DESKS = [[0, 0], [1, 0], [0, 1], [1, 1]]; // 4 seats

async function saveDesks(request: APIRequestContext, raum: string, seats: number[][]) {
  const res = await request.post('/api/sitzplaneditor_save', {
    data: { klasse: KLASSE, raum, seats: JSON.stringify(seats) },
  });
  expect(res.status()).toBe(200);
}

// Throws away the own plans in the subject room from earlier runs (the other
// Playwright project uses the same accounts).
async function removeOwnPlans(page: Page) {
  const state = await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
  if (state.open_cycle) {
    const res = await page.request.post('/api/sph_discard_open_cycle', { data: { cycle_id: state.open_cycle.id } });
    expect(res.status()).toBe(200);
  }
  const list = await (await page.request.post('/api/sph_list_saved_cycles', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
  for (const c of list.cycles) {
    const res = await page.request.post('/api/sph_delete_cycle', { data: { cycle_id: c.id } });
    expect(res.status()).toBe(200);
  }
}

test('Sitzplan im Fachraum: eigene Tische übernehmen, eigener Plan, getrennt von der Klassenleitung', async ({ page, newUserPage }) => {
  // Clarke's own desks in the subject room
  const clarke = await newUserPage();
  await login(clarke, ACCOUNTS.admin);
  await saveDesks(clarke.request, FACHRAUM, CLARKE_DESKS);
  // the homeroom's desks, as in sitzplan.spec.ts
  await saveDesks(clarke.request, '108', CLARKE_DESKS);

  await login(page, FACHLEHRKRAFT);
  await removeOwnPlans(page);
  await saveDesks(page.request, FACHRAUM, OWN_DESKS);

  // class page: the subject room has its own seating plan button; the
  // homeroom plan belongs to the class teacher and can only be looked at
  await page.goto(`/directory/${KLASSE}`);
  await expect(page.locator(`a[href="/sitzplanhelfer/${KLASSE}/${FACHRAUM}"]`)).toHaveText(`Sitzplan Raum ${FACHRAUM}`);
  await expect(page.locator(`#additional_teacher_content`)).toContainText('Ihr eigener Sitzplan für Ihren Unterricht in diesem Raum.');
  await expect(page.locator(`a[href^="/sitzplanhelfer/${KLASSE}/"]`)).toHaveCount(1);

  // seat editor: take over Clarke's desks as a copy, then save them as own
  await page.goto(`/sitzplaneditor/${KLASSE}/${FACHRAUM}`);
  await expect(page.locator('#spe_subtitle')).toContainText('Ihre eigenen Tische');
  await expect(page.locator('#spe_count')).toContainText('4 Sitzplätze');
  const copies = page.locator('#spe_copy_list .spe-copy-item');
  await expect(copies).toHaveCount(1);
  await expect(copies.first()).toContainText('Clarke');
  await expect(copies.first()).toContainText('8 Plätze');
  await expect(copies.first().locator('svg rect')).toHaveCount(8);
  await copies.first().getByRole('button', { name: 'Übernehmen' }).click();
  await dashboardDialog(page).getByRole('button', { name: 'Ersetzen' }).click();
  await expect(page.locator('#spe_count')).toContainText('8 Sitzplätze');
  const saved = page.waitForResponse('**/api/sitzplaneditor_save');
  await page.locator('#spe_save').click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#spe_status')).toContainText('Gespeichert');

  // the seating plan page: own plan, only the tools for a subject room
  await page.goto(`/sitzplanhelfer/${KLASSE}/${FACHRAUM}`);
  await expect(page.locator('#sph_fachraum_info')).toContainText('Ihr eigener Sitzplan');
  await expect(page.locator('#sph_room_info')).toHaveText(`Raum ${FACHRAUM}: 8 Plätze für 3 SuS`);
  await expect(page.locator('#sph_room_bar #sph_link_editor')).toBeVisible();
  await expect(page.locator('#sph_room_bar #sph_link_shuffler')).toBeEnabled();
  await expect(page.locator('#sph_room_bar #sph_bu_start_manual')).toBeVisible();
  await expect(page.locator('#sph_bu_wishes, #sph_bu_start_spread, #sph_spread_area, #sph_shuffler_box')).toHaveCount(0);
  await expect(page.locator('#sph_start_info')).toContainText('noch kein Sitzplan gespeichert');

  // by hand: everyone gets a seat by dice, then the plan is saved
  const started = page.waitForResponse('**/api/sph_start_cycle');
  await page.locator('#sph_bu_start_manual').click();
  expect((await started).status()).toBe(200);
  await expect(page.locator('#sph_unplaced .sph-chip')).toHaveCount(3);
  await page.locator('#sph_bu_generate').click();
  await expect(page.locator('#sph_seats .place:not(.empty)')).toHaveCount(3);
  const savedPlan = page.waitForResponse('**/api/sph_save_cycle');
  await page.locator('#sph_bu_save').click();
  expect((await savedPlan).status()).toBe(200);
  await expect(page.locator('#sph_view_start')).toBeVisible();
  await expect(page.locator('#sph_start_info')).toContainText('Diesen Plan sehen nur Sie.');
  await expect(page.locator('#sph_unresolved_summary')).toContainText('Alle Vorgaben sind erfüllt.');
  await expect(page.locator('#sph_unresolved_summary')).not.toContainText('Wünsche');
  await page.locator('#sph_history_section > summary').click();
  const ownPlanId = await page.locator('#sph_history_body .bu-edit-cycle').first().getAttribute('data-id');
  expect(ownPlanId).toBeTruthy();

  // the Shuffler uses the own desks and none of the class teacher's rules
  // (its music is not part of the example data)
  await page.route('**/api/get_music/**', (route) => route.fulfill({ status: 200, contentType: 'audio/mpeg', body: '' }));
  await page.goto(`/sitzplan/${KLASSE}/${FACHRAUM}`);
  expect(await page.evaluate((raum) => (window as any).seats_dict[raum].length, FACHRAUM)).toBe(8);
  expect(await page.evaluate(() => (window as any).rules.length)).toBe(0);

  // shown for the class: the own plan, with photos
  await page.goto(`/sitzplananzeige/${KLASSE}/${FACHRAUM}`);
  await expect(page.locator('#spa_seats img.spa-card-photo')).toHaveCount(3);

  // the homeroom plan stays the class teacher's
  await page.goto(`/sitzplanhelfer/${KLASSE}/108`);
  await expect(page.locator('#sph_room_bar')).toHaveCount(0);
  const state = await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: '108' } });
  expect(state.status()).not.toBe(200);

  // Clarke teaches 5a in the same room: his own plan there knows nothing of
  // Frieda's, and his homeroom keeps the wish round
  await clarke.goto(`/directory/${KLASSE}`);
  await expect(clarke.locator(`a[href="/sitzplanhelfer/${KLASSE}/${FACHRAUM}"]`)).toHaveText(`Sitzplan Raum ${FACHRAUM}`);
  await clarke.goto(`/sitzplanhelfer/${KLASSE}/${FACHRAUM}`);
  await expect(clarke.locator('#sph_fachraum_info')).toBeVisible();
  await expect(clarke.locator('#sph_room_info')).toHaveText(`Raum ${FACHRAUM}: 8 Plätze für 3 SuS`);
  await expect(clarke.locator(`#sph_history_body [data-id="${ownPlanId}"]`)).toHaveCount(0);
  const foreign = await clarke.request.post('/api/sph_reopen_saved_cycle', { data: { cycle_id: ownPlanId } });
  expect(foreign.status()).not.toBe(200);
  // a plan Clarke made in another subject room before there were own plans
  // there (test/e2e/seed.cypher) is still his and visible
  await saveDesks(clarke.request, '323', CLARKE_DESKS);
  await clarke.goto(`/sitzplanhelfer/${KLASSE}/323`);
  await expect(clarke.locator('#sph_fachraum_info')).toBeVisible();
  await expect(clarke.locator('#sph_history_body [data-id="e2efachraumalt"]')).toHaveCount(2);
  await clarke.goto(`/sitzplanhelfer/${KLASSE}/108`);
  await expect(clarke.locator('#sph_fachraum_info')).toBeHidden();
  await expect(clarke.locator('#sph_room_bar #sph_bu_wishes')).toBeVisible();
});
