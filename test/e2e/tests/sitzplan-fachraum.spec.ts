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
  // the section explains what applies to whom: homeroom plan for the class,
  // subject room plans of one's own
  await expect(page.locator('#sitzplan_raum_info')).toContainText('Im Klassenraum gibt es einen Sitzplan für die ganze Klasse');
  await expect(page.locator('#sitzplan_raum_info')).toContainText('am Sitzplan des Klassenraums ändert er nichts');
  await expect(page.locator(`.sitzplan-raum[data-raum="${FACHRAUM}"]`)).toContainText('Fachraum: Ihr eigener Sitzplan für Ihren Unterricht hier. Nur Sie sehen ihn.');
  await expect(page.locator('.sitzplan-raum[data-raum="108"]')).toContainText('Klassenraum: Der Sitzplan der Klassenleitung, zum Ansehen.');
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

  // own Vorgaben, without being class teacher: who must not sit together and
  // who sits in front (no lists for spreading out in a subject room)
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_area_pairs, #sph_area_fixed')).toHaveCount(2);
  await expect(page.locator('#sph_vorgaben_legend')).toContainText('Die Vorgaben der Klassenleitung sehen Sie hier nicht');
  // only the class teacher may copy her own homeroom Vorgaben
  await expect(page.locator('#sph_copy_class_rules_row')).toBeHidden();
  const notAllowed = await page.request.post('/api/sph_copy_class_rules', { data: { klasse: KLASSE, raum: FACHRAUM } });
  expect(notAllowed.status()).not.toBe(200);
  await page.locator('#sph_pair_a').selectOption({ label: 'Elli Mustermann' });
  await page.locator('#sph_pair_b').selectOption({ label: 'Mallory Mustermann' });
  await page.locator('#sph_bu_add_forbidden').click();
  await expect(page.locator('#sph_forbidden_list')).toContainText('Elli Mustermann');
  await page.locator('#sph_rule_sus').selectOption({ label: 'Max Mustermann' });
  await page.locator('#sph_rule_area').selectOption('front');
  await page.locator('#sph_bu_add_rule').click();
  await expect(page.locator('#sph_rules_list')).toContainText('Max Mustermann');

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
  await clarke.goto(`/directory/${KLASSE}`);
  await expect(clarke.locator('.sitzplan-raum[data-raum="108"]')).toContainText('Klassenraum: Ihren Sitzplan hier sehen alle Lehrkräfte der Klasse.');
  await clarke.goto(`/sitzplanhelfer/${KLASSE}/108`);
  await expect(clarke.locator('#sph_fachraum_info')).toBeHidden();
  await expect(clarke.locator('#sph_klassenraum_info')).toContainText('alle Lehrkräfte der Klasse können ihn ansehen');
  await expect(clarke.locator('#sph_room_bar #sph_bu_wishes')).toBeVisible();
});

// Rules of the class teacher stay hers. Only someone who is class teacher of
// the class herself may copy her homeroom Vorgaben into her own subject room
// plan – as a copy: pairs and areas, no exact seats; afterwards both are
// separate.
test('Sitzplan im Fachraum: Klassenleitung übernimmt eigene Vorgaben aus dem Klassenraum als Kopie', async ({ page }) => {
  await login(page, ACCOUNTS.admin); // Clarke: class teacher of 5a, also teaches it in 317
  await saveDesks(page.request, '108', CLARKE_DESKS);
  await saveDesks(page.request, FACHRAUM, CLARKE_DESKS);
  const sus = (await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: '108' } })).json()).sus;
  const email = (name: string) => sus.find((s: any) => s.display_name === name).email;
  const max = email('Max Mustermann');
  const mallory = email('Mallory Mustermann');
  const rule = (raum: string, path: string, extra: object) =>
    page.request.post(path, { data: { klasse: KLASSE, raum, ...extra } });
  // homeroom: Max and Mallory must not sit together, Max sits in front
  // (both rows: the room has two); the subject room starts without them
  const front = { email: max, x_min: 0, x_max: 4, y_min: 0, y_max: 2 };
  try {
    expect((await rule('108', '/api/sph_set_pair', { email_a: max, email_b: mallory, kind: 'forbidden' })).status()).toBe(200);
    expect((await rule('108', '/api/sph_set_fixed_rule', front)).status()).toBe(200);
    await rule(FACHRAUM, '/api/sph_remove_pair', { email_a: max, email_b: mallory, kind: 'forbidden' });
    await rule(FACHRAUM, '/api/sph_remove_fixed_rule', { email: max });

    await page.goto(`/sitzplanhelfer/${KLASSE}/${FACHRAUM}`);
    await expect(page.locator('#sph_view_start:visible, #sph_view_work:visible')).toHaveCount(1);
    await page.locator('#sph_vorgaben > summary').click();
    await expect(page.locator('#sph_forbidden_list')).not.toContainText('Max Mustermann');
    await page.locator('#sph_bu_copy_class_rules').click();
    await dashboardDialog(page).getByRole('button', { name: 'Übernehmen' }).click();
    await expect(page.locator('#sph_status')).toContainText('Übernommen: 1 Paar und 1 Bereich');
    await expect(page.locator('#sph_forbidden_list')).toContainText('Max Mustermann');
    await expect(page.locator('#sph_rules_list')).toContainText('Max Mustermann');

    // a copy: removing it in the subject room leaves the homeroom as it was
    expect((await rule(FACHRAUM, '/api/sph_remove_pair', { email_a: max, email_b: mallory, kind: 'forbidden' })).status()).toBe(200);
    const homeroom = (await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: '108' } })).json()).current_rules;
    expect(homeroom.forbidden_pairs.some((p: string[]) => p.includes(max) && p.includes(mallory))).toBe(true);
  } finally {
    await rule('108', '/api/sph_remove_pair', { email_a: max, email_b: mallory, kind: 'forbidden' });
    await rule('108', '/api/sph_remove_fixed_rule', { email: max });
    await rule(FACHRAUM, '/api/sph_remove_pair', { email_a: max, email_b: mallory, kind: 'forbidden' });
    await rule(FACHRAUM, '/api/sph_remove_fixed_rule', { email: max });
  }
});

// What the Shuffler drew can become a plan that is then adjusted by hand and
// saved: in the own subject room by its teacher, in the homeroom by the class
// teacher – never over a running wish round.
test('Shuffler: Ergebnis als Plan übernehmen, im Fachraum und im Klassenraum', async ({ page, newUserPage }) => {
  // no music in the example data: play() does nothing, the file is a stand-in
  const noMusic = async (p: Page) => {
    await p.addInitScript(() => { HTMLMediaElement.prototype.play = function () { return Promise.resolve(); }; });
    await p.route('**/api/get_music/**', (route) => route.fulfill({ status: 200, contentType: 'audio/mpeg', body: '' }));
  };
  const shuffle = async (p: Page, raum: string) => {
    await p.goto(`/sitzplan/${KLASSE}/${raum}`);
    await expect(p.locator('#seats .place')).toHaveCount(3);
    await expect(p.locator('#bu_adopt_shuffle')).toBeHidden();
    await p.keyboard.press('Space');
    // taking over does not wait for the music to end
    await expect(p.locator('#bu_adopt_shuffle')).toBeVisible();
    await p.locator('#audio').evaluate((audio) => audio.dispatchEvent(new Event('ended')));
    await expect(p.locator('#bu_print_shuffle')).toBeVisible();
  };
  // who sits where in the Shuffler, as seats of the room's desks
  const drawn = (p: Page, raum: string) => p.evaluate((raum) => {
    const w = window as any;
    const result: Record<string, number> = {};
    w.sus.forEach((s: any, i: number) => {
      const seat = w.seats[w.place_for_sus[i]];
      result[s.email] = w.seats_dict[raum].findIndex((d: number[]) => d[0] === seat[0] && d[1] === seat[1]);
    });
    return result;
  }, raum);

  await noMusic(page);
  await login(page, FACHLEHRKRAFT);
  await removeOwnPlans(page);
  await saveDesks(page.request, FACHRAUM, OWN_DESKS);

  // shuffled, moved one seat further with C, then taken over as a plan
  await shuffle(page, FACHRAUM);
  await page.keyboard.press('KeyC');
  const expected = await drawn(page, FACHRAUM);
  expect(Object.keys(expected)).toHaveLength(3);
  await page.locator('#bu_adopt_shuffle').click();
  await expect(page).toHaveURL(`/sitzplanhelfer/${KLASSE}/${FACHRAUM}`);
  await expect(page.locator('#sph_cycle_info')).toContainText('im Shuffler ausgelost');
  await expect(page.locator('#sph_seats .place:not(.empty)')).toHaveCount(3);
  await expect(page.locator('#sph_unplaced .sph-chip')).toHaveCount(0);
  const state = await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
  expect(state.open_cycle.seats).toEqual(expected);
  expect(state.open_cycle.mode).toBe('manual');

  // shuffled again while that plan is still open: replaced only after asking
  await shuffle(page, FACHRAUM);
  const second = await drawn(page, FACHRAUM);
  await page.locator('#bu_adopt_shuffle').click();
  const dialog = dashboardDialog(page);
  await expect(dialog).toContainText('schon einen neuen Sitzplan angefangen');
  await dialog.getByRole('button', { name: 'Ersetzen' }).click();
  await expect(page).toHaveURL(`/sitzplanhelfer/${KLASSE}/${FACHRAUM}`);
  const replaced = await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
  expect(replaced.open_cycle.id).toBe(state.open_cycle.id);
  expect(replaced.open_cycle.seats).toEqual(second);

  // saved like any plan
  const savedPlan = page.waitForResponse('**/api/sph_save_cycle');
  await page.locator('#sph_bu_save').click();
  expect((await savedPlan).status()).toBe(200);
  await expect(page.locator('#sph_view_start')).toBeVisible();
  const after = await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
  expect(after.open_cycle).toBeNull();
  expect(after.last_cycle.seats).toEqual(second);

  // seats that are not the own desks, or pupils of another class, are refused
  const bad = await page.request.post('/api/sph_adopt_shuffle', {
    data: { klasse: KLASSE, raum: FACHRAUM, seats: JSON.stringify({ [Object.keys(second)[0]]: 99 }) },
  });
  expect(bad.status()).not.toBe(200);
  await removeOwnPlans(page);

  // the homeroom plan is the class teacher's, not a subject teacher's
  const notHers = await page.request.post('/api/sph_adopt_shuffle', {
    data: { klasse: KLASSE, raum: '108', seats: JSON.stringify({ [Object.keys(second)[0]]: 0 }) },
  });
  expect(notHers.status()).not.toBe(200);

  // homeroom: the class teacher takes over the result just the same
  const clarke = await newUserPage();
  await noMusic(clarke);
  await login(clarke, ACCOUNTS.admin);
  await saveDesks(clarke.request, '108', CLARKE_DESKS);
  const homeroomState = async () =>
    (await clarke.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: '108' } })).json();
  const discardHomeroom = async () => {
    const open = (await homeroomState()).open_cycle;
    if (open) expect((await clarke.request.post('/api/sph_discard_open_cycle', { data: { cycle_id: open.id } })).status()).toBe(200);
  };
  await discardHomeroom();
  try {
    // a running wish round is never replaced
    const round = await clarke.request.post('/api/sph_start_cycle', { data: { klasse: KLASSE, raum: '108', mode: 'wishes' } });
    expect(round.status()).toBe(200);
    await shuffle(clarke, '108');
    await expect(clarke.locator('#bu_adopt_shuffle')).toBeVisible();
    await clarke.locator('#bu_adopt_shuffle').click();
    await expect(dashboardDialog(clarke)).toContainText('läuft gerade eine Wunschrunde');
    await dashboardDialog(clarke).getByRole('button', { name: 'OK' }).click();
    expect((await homeroomState()).open_cycle.poll_run_id).toBeTruthy();
    await discardHomeroom();

    await shuffle(clarke, '108');
    const drawnHomeroom = await drawn(clarke, '108');
    await clarke.locator('#bu_adopt_shuffle').click();
    await expect(clarke).toHaveURL(`/sitzplanhelfer/${KLASSE}/108`);
    await expect(clarke.locator('#sph_cycle_info')).toContainText('im Shuffler ausgelost');
    await expect(clarke.locator('#sph_seats .place:not(.empty)')).toHaveCount(3);
    const adopted = (await homeroomState()).open_cycle;
    expect(adopted.seats).toEqual(drawnHomeroom);
    expect(adopted.mode).toBe('manual');
  } finally {
    await discardHomeroom();
  }
});

// The plan shown to the class must fit on the screen in one piece, also for a
// big room (e.g. on the projector): no seat outside the window, no scrolling.
test('Sitzplan anzeigen: auch ein großer Raum passt ganz ins Fenster', async ({ page }) => {
  await login(page, FACHLEHRKRAFT);
  await removeOwnPlans(page);
  const BIG = Array.from({ length: 9 }, (_, y) => Array.from({ length: 12 }, (_, x) => [x, y])).flat(); // 108 seats
  await saveDesks(page.request, FACHRAUM, BIG);
  try {
    const state = await (await page.request.post('/api/sph_get_state', { data: { klasse: KLASSE, raum: FACHRAUM } })).json();
    const emails = state.sus.map((s: any) => s.email);
    // the far corners and the middle
    const seats = { [emails[0]]: 0, [emails[1]]: BIG.length - 1, [emails[2]]: 11 };
    const started = await (await page.request.post('/api/sph_start_cycle', { data: { klasse: KLASSE, raum: FACHRAUM, mode: 'manual' } })).json();
    const saved = await page.request.post('/api/sph_save_cycle', {
      data: { cycle_id: started.cycle_id, seats: JSON.stringify(seats), unresolved: '[]' },
    });
    expect(saved.status()).toBe(200);

    await page.goto(`/sitzplananzeige/${KLASSE}/${FACHRAUM}`);
    await expect(page.locator('#spa_seats .place')).toHaveCount(3);
    const outside = await page.evaluate(() => {
      const w = window.innerWidth, h = window.innerHeight;
      return [...document.querySelectorAll('#spa_seats .place')].map((el) => el.getBoundingClientRect())
        .filter((r) => r.left < 0 || r.top < 0 || r.right > w || r.bottom > h).length;
    });
    expect(outside).toBe(0);
    // the names stay readable
    for (const name of ['Max', 'Elli', 'Mallory']) await expect(page.locator('#spa_seats')).toContainText(name);
  } finally {
    await removeOwnPlans(page);
    await saveDesks(page.request, FACHRAUM, OWN_DESKS);
  }
});
