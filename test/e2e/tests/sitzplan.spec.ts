import type { Locator, Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, dashboardDialog } from './fixtures';

// Example data: Clarke is class teacher of 5a (Max, Elli, Mallory).
const KLASSE = '5a';

// The class page links the seating plan of the homeroom; the room comes from
// that link. Two rows with two desks of two seats each (the seat editor has
// its own UI).
async function setUpRoom(page: Page) {
  await page.goto(`/directory/${KLASSE}`);
  const link = page.locator(`a[href^="/sitzplanhelfer/${KLASSE}/"]`).first();
  const raum = decodeURIComponent((await link.getAttribute('href'))!.split('/').pop()!);
  const seats = [0, 1, 3, 4].flatMap((x) => [0, 2].map((y) => [x, y]));
  const room = await page.request.post('/api/sitzplaneditor_save', {
    data: { klasse: KLASSE, raum, seats: JSON.stringify(seats) },
  });
  expect(room.status()).toBe(200);
  // start clean even after an aborted earlier run: no lists, all areas used
  const lists = await page.request.post('/api/sph_save_seating_groups', { data: { klasse: KLASSE, groups: '[]' } });
  expect(lists.status()).toBe(200);
  for (const mode of ['manual', 'spread', 'wishes'])
    for (const area of ['pairs', 'fixed', 'spread']) {
      const reset = await page.request.post('/api/sph_set_rule_area', { data: { klasse: KLASSE, raum, mode, area, active: 'yes' } });
      expect(reset.status()).toBe(200);
    }
  return raum;
}

// Opens the seating plan page and throws away a new plan left over from an
// earlier run on the same test stack.
async function openSeatingPlan(page: Page, raum: string) {
  await page.goto(`/sitzplanhelfer/${KLASSE}/${raum}`);
  const discard = page.locator('#sph_bu_discard_cycle');
  await expect(page.locator('#sph_view_start:visible, #sph_view_work:visible')).toHaveCount(1);
  if (await discard.isVisible()) await discardOpenPlan(page);
}

async function discardOpenPlan(page: Page) {
  await page.locator('#sph_bu_discard_cycle').click();
  await dashboardDialog(page).getByRole('button', { name: 'Verwerfen' }).click();
  await expect(page.locator('#sph_view_start')).toBeVisible();
}

async function startNewPlan(page: Page, way: 'cycle' | 'spread' | 'manual') {
  // the tools on top: "Von Hand verteilen" and "Im Raum verteilen" start
  // right away, the Wunschrunde first asks for the duration below them
  if (way === 'cycle') {
    await page.locator('#sph_room_bar #sph_bu_wishes').click();
    await expect(page.locator('#sph_room_bar #sph_new_choice')).toBeVisible();
  }
  const started = page.waitForResponse('**/api/sph_start_cycle');
  await page.locator(`#sph_bu_start_${way}`).click();
  expect((await started).status()).toBe(200);
  await expect(page.locator('#sph_bu_discard_cycle')).toBeVisible();
}

async function savePlan(page: Page) {
  const saved = page.waitForResponse('**/api/sph_save_cycle');
  await page.locator('#sph_bu_save').click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#sph_status')).toContainText('gespeichert');
  await expect(page.locator('#sph_view_start')).toBeVisible();
}

// Every name element lies completely inside its seat card and shows all of
// its text (nothing cut off by the card or by the name box itself).
async function expectNamesReadable(cards: Locator) {
  const count = await cards.count();
  for (let i = 0; i < count; i++) {
    const card = cards.nth(i);
    await expect(card.locator('.sph-card-photo')).toBeVisible();
    const fits = await card.evaluate((el) => {
      const name = el.querySelector('.sph-card-name') as HTMLElement;
      const c = el.getBoundingClientRect();
      const n = name.getBoundingClientRect();
      return name.scrollWidth <= name.clientWidth + 1 && name.scrollHeight <= name.clientHeight + 1 &&
        n.left >= c.left - 1 && n.right <= c.right + 1 && n.top >= c.top - 1 && n.bottom <= c.bottom + 1;
    });
    expect(fits, `name ${i + 1} fits into its seat`).toBe(true);
  }
}

test('Sitzplan: Wunschrunde, Wunsch von SuS, Plan erzeugen und speichern', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);

  // class page: one button for the seating plan; Shuffler, editor and manual
  // placing live on the seating plan page now
  await page.goto(`/directory/${KLASSE}`);
  await expect(page.locator(`a[href="/sitzplanhelfer/${KLASSE}/${RAUM}"]`)).toHaveText(`Sitzplan Raum ${RAUM}`);
  await expect(page.locator('#additional_teacher_content a[href^="/sitzplan/"], #additional_teacher_content a[href^="/sitzplanverteilen/"], #additional_teacher_content a[href^="/sitzplaneditor/"]')).toHaveCount(0);

  await openSeatingPlan(page, RAUM);
  await expect(page.locator('#sph_link_editor')).toBeVisible();
  // the Shuffler itself stays as it is, it is opened from here
  await expect(page.locator('#sph_link_shuffler')).toBeEnabled();
  await startNewPlan(page, 'cycle');
  // tables, Shuffler and "Von Hand verteilen" stay on top while the wish
  // round runs; starting over by hand asks first
  await expect(page.locator('#sph_room_bar #sph_link_editor')).toBeVisible();
  await expect(page.locator('#sph_room_bar #sph_link_shuffler')).toBeVisible();
  await expect(page.locator('#sph_room_bar #sph_bu_wishes')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#sph_room_bar #sph_bu_start_manual').click();
  await expect(dashboardDialog(page)).toContainText('schon eine Wunschrunde offen');
  await dashboardDialog(page).getByRole('button', { name: 'Abbrechen' }).click();
  await expect(page.locator('#sph_bu_close_wishes')).toBeVisible();

  // Max wishes to sit next to Mallory
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await student.locator('.hint_poll', { hasText: /Sitz/ }).locator('.bu-launch-poll').click();
  const pollModal = student.locator('#pollResponseModal');
  await expect(pollModal).toBeVisible();
  await pollModal.locator('.poll-items').getByText(/Mallory/).first().click();
  const submitted = student.waitForResponse('**/api/submit_poll_run');
  await student.locator('#bu_submit_poll_results').click();
  expect((await submitted).status()).toBe(200);

  // class teacher sees the wish, closes the round, generates and saves
  await page.reload();
  await expect(page.locator('#sph_wishes_body')).toContainText('Mallory');
  // "Wunschrunde jetzt beenden" asks for confirmation; Abbrechen keeps it open
  await page.locator('#sph_bu_close_wishes').click();
  const dialog = dashboardDialog(page);
  await expect(dialog).toContainText('Wunschrunde jetzt vorzeitig beenden?');
  await dialog.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(dialog).toBeHidden();
  await expect(page.locator('#sph_bu_close_wishes')).toBeEnabled();

  await page.locator('#sph_bu_close_wishes').click();
  const closed = page.waitForResponse('**/api/sph_close_wishes');
  await dialog.getByRole('button', { name: 'Wunschrunde beenden' }).click();
  expect((await closed).status()).toBe(200);

  await page.locator('#sph_bu_generate').click();
  await expect(page.locator('#sph_seats')).toContainText('Max');
  await expect(page.locator('#sph_seats')).toContainText('Mallory');
  await savePlan(page);
  // back on the start view with the saved plan, to show and to print
  await expect(page.locator('#sph_seats')).toContainText('Mallory');
  await expect(page.locator('#sph_link_show')).toHaveAttribute('href', `/sitzplananzeige/${KLASSE}/${RAUM}`);
  await expect(page.locator('#sph_link_print')).toHaveAttribute('href', `/sitzplananzeige/${KLASSE}/${RAUM}?print=1`);

  // students do not see the seating plan themselves
  await student.goto(`/sitzplananzeige/${KLASSE}/${RAUM}`);
  await expect(student).not.toHaveURL(/sitzplananzeige/);
  const denied = await student.request.post('/api/sph_get_public_plan', { data: { klasse: KLASSE, raum: RAUM } });
  expect(denied.status()).not.toBe(200);
  expect(await denied.text()).not.toContain('Mallory');

  // teachers do, without wishes
  await page.goto(`/sitzplananzeige/${KLASSE}/${RAUM}`);
  for (const name of ['Max', 'Elli', 'Mallory']) {
    await expect(page.locator('#spa_seats')).toContainText(name);
  }
  // printing is a button of its own on the seating plan page, not here
  await expect(page.locator('.spa-container button')).toHaveCount(0);
});

test('Sitzplan: Plätze mit Foto und vollem Namen, Ziehen, feste Plätze, Verteilung im Raum', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  // "Im Raum verteilen": no poll, the plan is there right away
  await startNewPlan(page, 'spread');
  const cards = page.locator('#sph_seats .place:not(.empty)');
  await expect(cards).toHaveCount(3);
  await expect(page.locator('#sph_seats')).toContainText(/Mallory\s*Mustermann/);
  await expectNamesReadable(cards);

  // long names are made smaller or wrapped, never cut off
  await page.evaluate(() => {
    const w = window as any;
    w.sus[0].first_name = 'Anna-Lena-Marie';
    w.sus[0].last_name = 'Schmidt-Kowalski-Papadopoulos';
    w.render_placement(true);
  });
  await expect(page.locator('#sph_seats')).toContainText('Schmidt-Kowalski-Papadopoulos');
  await expectNamesReadable(cards);

  // drag a student onto a free seat, then take the move back
  const source = cards.first();
  const from = await source.getAttribute('data-seat-index');
  const name = (await source.locator('.sph-card-name').textContent())!;
  const free = page.locator('#sph_seats .place.empty').first();
  const to = await free.getAttribute('data-seat-index');
  // the whole room on screen, so that both seats are where the mouse goes
  await page.locator('#sph_seats').scrollIntoViewIfNeeded();
  await source.dragTo(free);
  const seat = (index: string | null) => page.locator(`#sph_seats .place[data-seat-index="${index}"]`);
  await expect(seat(to)).toHaveText(name);
  await expect(seat(from)).toHaveClass(/empty/);
  await page.locator('#sph_bu_undo').click();
  await expect(seat(from)).toHaveText(name);

  // a click selects a student; the seat can be fixed right in the plan
  await seat(from).click();
  await expect(page.locator('#sph_selection_bar')).toContainText('ist ausgewählt');
  await expect(seat(from)).toHaveClass(/selected/);
  await page.locator('#sph_bu_pin').click();
  await expect(seat(from)).toHaveClass(/pinned/);
  await seat(from).click();
  await expect(page.locator('#sph_bu_pin')).toHaveText(/lösen/);
  await page.locator('#sph_bu_deselect').click();

  // the fixed seat stays; a new plan shows it before anything is shuffled
  await discardOpenPlan(page);
  await startNewPlan(page, 'cycle');
  await expect(page.locator('#sph_seats .place.pinned')).toHaveCount(1);
  await expect(page.locator('#sph_plan_info')).toContainText('Noch kein Plan');
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_rules_list')).toContainText('genauer Platz');
  await page.locator('#sph_rules_list .rule-chip a').first().click();
  await expect(page.locator('#sph_rules_list')).not.toContainText('genauer Platz');
  await expect(page.locator('#sph_seats .place.pinned')).toHaveCount(0);

  // Verteilung im Raum: a list of the class, kept until it is changed
  await page.locator('#sph_bu_add_group').click();
  const list = page.locator('#sph_groups_list .sph-group').first();
  await expect(list).toContainText('Liste A');
  await list.locator('select').selectOption({ label: 'Max Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Max Mustermann' })).toBeVisible();
  await list.locator('select').selectOption({ label: 'Elli Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Elli Mustermann' })).toBeVisible();
  await page.reload();
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_groups_list .sph-group').first()).toContainText('Elli Mustermann');
  await page.locator('#sph_groups_list .sph-group').first().getByRole('button', { name: 'Liste löschen' }).click();
  await dashboardDialog(page).getByRole('button', { name: 'Löschen' }).click();
  await expect(page.locator('#sph_groups_list .sph-group')).toHaveCount(0);

  await discardOpenPlan(page);
});

test('Sitzplan: von Hand verteilen, Vorgaben bleiben, Plan ändern', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  // Vorgaben can be set without any plan or wish round
  await page.locator('#sph_vorgaben > summary').click();
  await page.locator('#sph_pair_a').selectOption({ label: 'Elli Mustermann' });
  await page.locator('#sph_pair_b').selectOption({ label: 'Mallory Mustermann' });
  await page.locator('#sph_bu_add_forced').click();
  await expect(page.locator('#sph_forced_list')).toContainText('Elli Mustermann');

  // "Von Hand": everyone starts in the list without a seat
  await expect(page.locator('#sph_room_bar #sph_bu_start_manual')).toBeVisible();
  await startNewPlan(page, 'manual');
  const chips = page.locator('#sph_unplaced .sph-chip');
  await expect(chips).toHaveCount(3);
  await expect(page.locator('#sph_seats .place:not(.empty)')).toHaveCount(0);
  // nothing moves or changes size while a student is put on a seat
  // (position on the page, not in the window: clicking may scroll)
  const box = () => page.evaluate(() => {
    const room = document.querySelector('#sph_seats')!.getBoundingClientRect();
    const seat0 = document.querySelector('#sph_seats .place[data-seat-index="0"]')!.getBoundingClientRect();
    return [Math.round(room.top + window.scrollY), Math.round(seat0.width), Math.round(seat0.height)];
  });
  const before = await box();
  await chips.filter({ hasText: 'Max' }).click();
  expect(await box()).toEqual(before);
  await page.locator('#sph_seats .place[data-seat-index="0"]').click();
  await expect(page.locator('#sph_seats .place[data-seat-index="0"]')).toContainText('Max');
  await expect(chips).toHaveCount(2);
  expect(await box()).toEqual(before);

  // the Vorgabe from the start page applies here and to the next new plan
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_forced_list')).toContainText('Elli Mustermann');

  // saving with students still in the list asks first
  await page.locator('#sph_bu_save').click();
  const dialog = dashboardDialog(page);
  await expect(dialog).toContainText('2 Personen haben noch keinen Platz');
  const saved = page.waitForResponse('**/api/sph_save_cycle');
  await dialog.getByRole('button', { name: 'Trotzdem speichern' }).click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#sph_status')).toContainText('gespeichert');

  // "Plan ändern" starts from the saved plan
  await page.locator('#sph_bu_edit_saved').click();
  await expect(page.locator('#sph_bu_discard_cycle')).toBeVisible();
  await expect(page.locator('#sph_seats .place[data-seat-index="0"]')).toContainText('Max');
  await discardOpenPlan(page);

  // the next new plan takes over the Vorgaben without asking
  await startNewPlan(page, 'spread');
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_forced_list')).toContainText('Elli Mustermann');
  // leave no Vorgaben behind for the other tests
  await page.locator('#sph_forced_list .pair-chip a').first().click();
  await expect(page.locator('#sph_forced_list')).not.toContainText('Elli Mustermann');
  await savePlan(page);

  // earlier plans are listed, folded away
  await page.locator('#sph_history_section > summary').click();
  await expect(page.locator('#sph_history_body tr').first()).toContainText('aktuell');
});

test('Sitzplan: im Raum verteilen, Verstoß nach dem Umsetzen rot markiert', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  // five tools on top, side by side
  for (const id of ['sph_link_editor', 'sph_link_shuffler', 'sph_bu_start_manual', 'sph_bu_start_spread', 'sph_bu_wishes'])
    await expect(page.locator(`#sph_room_bar .sph-tools #${id}`)).toBeVisible();

  // a list on the start page, without any plan or wish round
  await page.locator('#sph_vorgaben > summary').click();
  await page.locator('#sph_bu_add_group').click();
  const list = page.locator('#sph_groups_list .sph-group').first();
  await list.locator('select').selectOption({ label: 'Max Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Max Mustermann' })).toBeVisible();
  await list.locator('select').selectOption({ label: 'Elli Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Elli Mustermann' })).toBeVisible();

  await startNewPlan(page, 'spread');
  await expect(page.locator('#sph_room_bar #sph_bu_start_spread')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#sph_cycle_info')).toContainText('1 Verteilungsliste');
  const cards = page.locator('#sph_seats .place:not(.empty)');
  await expect(cards).toHaveCount(3);
  await expect(page.locator('#sph_seats .place.unresolved')).toHaveCount(0);
  // in this tool the students of a list show its colour and letter
  await expect(page.locator('#sph_seats .place .sph-list-tag')).toHaveCount(2);
  await expect(page.locator('#sph_seats .place .sph-list-tag').first()).toHaveText('A');
  await expect(page.locator('#sph_unresolved_summary .sph-list-legend')).toContainText('Liste A');

  // put Elli right next to Max by hand: both are marked red
  const [elli_seat, next_to_max] = await page.evaluate(() => {
    const w = window as any;
    const email = (name: string) => w.sus.find((s: any) => s.display_name === name).email;
    const max = w.seats[w.current_placement[email('Max Mustermann')]];
    const next = w.seats.findIndex((st: number[]) => st[1] === max[1] && Math.abs(st[0] - max[0]) === 1);
    return [w.current_placement[email('Elli Mustermann')], next];
  });
  await page.locator(`#sph_seats .place[data-seat-index="${elli_seat}"]`).click();
  await page.locator(`#sph_seats .place[data-seat-index="${next_to_max}"]`).click();
  await expect(page.locator(`#sph_seats .place[data-seat-index="${next_to_max}"]`)).toContainText('Elli');
  await expect(page.locator('#sph_seats .place.unresolved')).toHaveCount(2);
  await expect(page.locator(`#sph_seats .place[data-seat-index="${next_to_max}"]`)).toHaveAttribute('title', /gleiche Liste/);
  await expect(page.locator('#sph_unresolved_summary')).toContainText('Verteilung im Raum');

  // only in this tool: a plan by hand shows no list colours
  await page.locator('#sph_bu_start_manual').click();
  await dashboardDialog(page).getByRole('button', { name: /Verwerfen/ }).click();
  await expect(page.locator('#sph_room_bar #sph_bu_start_manual')).toHaveAttribute('aria-pressed', 'true');
  await page.locator('#sph_unplaced .sph-chip').filter({ hasText: 'Max' }).click();
  await page.locator('#sph_seats .place[data-seat-index="0"]').click();
  await expect(page.locator('#sph_seats .place[data-seat-index="0"]')).toContainText('Max');
  await expect(page.locator('#sph_seats .sph-list-tag')).toHaveCount(0);

  // leave no list behind for the other tests
  await page.locator('#sph_vorgaben > summary').click();
  await page.locator('#sph_groups_list .sph-group').first().getByRole('button', { name: 'Liste löschen' }).click();
  await dashboardDialog(page).getByRole('button', { name: 'Löschen' }).click();
  await expect(page.locator('#sph_groups_list .sph-group')).toHaveCount(0);
  await discardOpenPlan(page);
});

test('Sitzplan: Vorgaben je Werkzeug berücksichtigen oder nicht', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  // the entries are made once, for all tools; without a plan there is no switch
  await page.locator('#sph_vorgaben > summary').click();
  await page.locator('#sph_bu_add_group').click();
  const list = page.locator('#sph_groups_list .sph-group').first();
  await list.locator('select').selectOption({ label: 'Max Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Max Mustermann' })).toBeVisible();
  await list.locator('select').selectOption({ label: 'Elli Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Elli Mustermann' })).toBeVisible();
  await expect(page.locator('#sph_area_spread')).toBeHidden();

  // "Im Raum verteilen": Verteilung im Raum switched off for this tool
  await startNewPlan(page, 'spread');
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_area_spread')).toBeChecked();
  const switched = page.waitForResponse('**/api/sph_set_rule_area');
  await page.locator('label[for="sph_area_spread"]').click();
  expect((await switched).status()).toBe(200);
  await expect(page.locator('label[for="sph_area_spread"]')).toHaveText('nicht berücksichtigen');
  await expect(page.locator('#sph_cycle_info')).toContainText('nicht berücksichtigt');
  await expect(page.locator('#sph_seats .sph-list-tag')).toHaveCount(0);
  const [elli_seat, next_to_max] = await page.evaluate(() => {
    const w = window as any;
    const email = (name: string) => w.sus.find((s: any) => s.display_name === name).email;
    const max = w.seats[w.current_placement[email('Max Mustermann')]];
    const next = w.seats.findIndex((st: number[]) => st[1] === max[1] && Math.abs(st[0] - max[0]) === 1);
    return [w.current_placement[email('Elli Mustermann')], next];
  });
  await page.locator(`#sph_seats .place[data-seat-index="${elli_seat}"]`).click();
  await page.locator(`#sph_seats .place[data-seat-index="${next_to_max}"]`).click();
  await expect(page.locator(`#sph_seats .place[data-seat-index="${next_to_max}"]`)).toContainText('Elli');
  await expect(page.locator('#sph_seats .place.unresolved')).toHaveCount(0);

  // switched on again right here: colours and red marks are back
  await page.locator('label[for="sph_area_spread"]').click();
  await expect(page.locator('#sph_seats .sph-list-tag')).toHaveCount(2);
  await expect(page.locator('#sph_seats .place.unresolved')).toHaveCount(2);

  // off again for this tool; the Wunschrunde keeps its own switch, and the
  // list is still there
  await page.locator('label[for="sph_area_spread"]').click();
  await expect(page.locator('#sph_area_spread')).not.toBeChecked();
  await discardOpenPlan(page);

  // the Wunschrunde chosen (its box open, not started yet): the one switch
  // at each area now belongs to the Wunschrunde
  await page.locator('#sph_bu_wishes').click();
  await expect(page.locator('#sph_area_spread')).toBeChecked();
  await expect(page.locator('label[for="sph_area_pairs"]')).toHaveText('berücksichtigen');
  const wish_switched = page.waitForResponse('**/api/sph_set_rule_area');
  await page.locator('label[for="sph_area_pairs"]').click();
  expect((await wish_switched).status()).toBe(200);
  await expect(page.locator('label[for="sph_area_pairs"]')).toHaveText('nicht berücksichtigen');
  const started = page.waitForResponse('**/api/sph_start_cycle');
  await page.locator('#sph_bu_start_cycle').click();
  expect((await started).status()).toBe(200);
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_area_spread')).toBeChecked();
  await expect(page.locator('#sph_area_pairs')).not.toBeChecked();
  await expect(page.locator('#sph_groups_list .sph-group').first()).toContainText('Elli Mustermann');

  // leave nothing behind for the other tests
  await page.locator('#sph_groups_list .sph-group').first().getByRole('button', { name: 'Liste löschen' }).click();
  await dashboardDialog(page).getByRole('button', { name: 'Löschen' }).click();
  await expect(page.locator('#sph_groups_list .sph-group')).toHaveCount(0);
  await discardOpenPlan(page);
  for (const [mode, area] of [['spread', 'spread'], ['wishes', 'pairs']]) {
    const reset = await page.request.post('/api/sph_set_rule_area', {
      data: { klasse: KLASSE, raum: RAUM, mode, area, active: 'yes' },
    });
    expect(reset.status()).toBe(200);
  }
});

test('Sitzplan: Widerspruch in den Vorgaben knallrot markiert', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  // Max and Elli on the same list and at the same time a forced pair
  await page.locator('#sph_vorgaben > summary').click();
  await page.locator('#sph_bu_add_group').click();
  const list = page.locator('#sph_groups_list .sph-group').first();
  await list.locator('select').selectOption({ label: 'Max Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Max Mustermann' })).toBeVisible();
  await list.locator('select').selectOption({ label: 'Elli Mustermann' });
  await expect(list.locator('.pair-chip', { hasText: 'Elli Mustermann' })).toBeVisible();
  await page.locator('#sph_pair_a').selectOption({ label: 'Max Mustermann' });
  await page.locator('#sph_pair_b').selectOption({ label: 'Elli Mustermann' });
  await page.locator('#sph_bu_add_forced').click();
  await expect(page.locator('#sph_forced_list')).toContainText('Elli Mustermann');

  await startNewPlan(page, 'spread');
  await expect(page.locator('#sph_seats .place.sph-conflict')).toHaveCount(2);
  await expect(page.locator('#sph_seats .place.sph-conflict').first()).toHaveAttribute('title', /Widerspruch in den Vorgaben/);
  await expect(page.locator('#sph_unresolved_summary .sph-conflict-list')).toContainText('Zwangspaar');
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_groups_list .sph-group-hint')).toContainText('Zwangspaar');

  // pairs not used by this tool: no conflict, no hint under the list
  const off = page.waitForResponse('**/api/sph_set_rule_area');
  await page.locator('label[for="sph_area_pairs"]').click();
  expect((await off).status()).toBe(200);
  await expect(page.locator('#sph_seats .place.sph-conflict')).toHaveCount(0);
  await expect(page.locator('#sph_groups_list .sph-group-hint')).toHaveCount(0);
  const on = page.waitForResponse('**/api/sph_set_rule_area');
  await page.locator('label[for="sph_area_pairs"]').click();
  expect((await on).status()).toBe(200);
  await expect(page.locator('#sph_seats .place.sph-conflict')).toHaveCount(2);

  // the forced pair removed: no more conflict
  await page.locator('#sph_forced_list .pair-chip a').first().click();
  await expect(page.locator('#sph_forced_list')).not.toContainText('Elli Mustermann');
  await expect(page.locator('#sph_seats .place.sph-conflict')).toHaveCount(0);

  await page.locator('#sph_groups_list .sph-group').first().getByRole('button', { name: 'Liste löschen' }).click();
  await dashboardDialog(page).getByRole('button', { name: 'Löschen' }).click();
  await expect(page.locator('#sph_groups_list .sph-group')).toHaveCount(0);
  await discardOpenPlan(page);
});

test('Shuffler: Regeln vor dem Start ansehen und ändern', async ({ page }) => {
  // no music in the example data
  await page.route('**/api/get_music/**', (route) => route.fulfill({ status: 200, contentType: 'audio/mpeg', body: '' }));
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);

  await page.locator('#sph_link_shuffler').click();
  const box = page.locator('#sph_shuffler_box');
  await expect(box).toBeVisible();
  await expect(page.locator('#sph_sh_start')).toHaveAttribute('href', `/sitzplan/${KLASSE}/${RAUM}`);
  // left over from an aborted earlier run
  while (await page.locator('#sph_sh_rules_list a, #sph_sh_pairs_list a').count() > 0) {
    const removed = page.waitForResponse('**/api/sitzplan_shuffler_rules_save');
    await page.locator('#sph_sh_rules_list a, #sph_sh_pairs_list a').first().click();
    await removed;
  }

  // an area and a pair, only for the Shuffler
  await page.locator('#sph_sh_rule_sus').selectOption({ label: 'Max Mustermann' });
  await page.locator('#sph_sh_rule_area').selectOption('front');
  let saved = page.waitForResponse('**/api/sitzplan_shuffler_rules_save');
  await page.locator('#sph_sh_bu_add_rule').click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#sph_sh_rules_list')).toContainText('Max Mustermann (vorne)');
  await page.locator('#sph_sh_pair_a').selectOption({ label: 'Elli Mustermann' });
  await page.locator('#sph_sh_pair_b').selectOption({ label: 'Mallory Mustermann' });
  await page.locator('#sph_sh_pair_freq').selectOption('2');
  saved = page.waitForResponse('**/api/sitzplan_shuffler_rules_save');
  await page.locator('#sph_sh_bu_add_pair').click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#sph_sh_pairs_list')).toContainText('jedes 2. Mal');

  // the Shuffler knows one partner per person only
  await page.locator('#sph_sh_pair_a').selectOption({ label: 'Max Mustermann' });
  await page.locator('#sph_sh_pair_b').selectOption({ label: 'Elli Mustermann' });
  await page.locator('#sph_sh_bu_add_pair').click();
  await expect(dashboardDialog(page)).toContainText('nur einen Partner');
  await dashboardDialog(page).getByRole('button', { name: 'OK' }).click();

  // kept, and the Vorgaben of the other tools are untouched
  await page.reload();
  await page.locator('#sph_vorgaben > summary').click();
  await expect(page.locator('#sph_forced_list')).toContainText('keine');
  await expect(page.locator('#sph_rules_list')).toContainText('keine festen Plätze');
  await page.locator('#sph_link_shuffler').click();
  await expect(page.locator('#sph_sh_rules_list')).toContainText('Max Mustermann (vorne)');

  // "Shuffler starten": the Shuffler gets exactly these rules
  await page.locator('#sph_sh_start').click();
  await expect(page.locator('#seats .place')).toHaveCount(3);
  expect(await page.evaluate(() => [(window as any).rules.length, (window as any).bff.length, (window as any).bff[0][2]])).toEqual([1, 1, 2]);

  // leave nothing behind
  await page.goto(`/sitzplanhelfer/${KLASSE}/${RAUM}`);
  await page.locator('#sph_link_shuffler').click();
  for (let i = 0; i < 2; i++) {
    const removed = page.waitForResponse('**/api/sitzplan_shuffler_rules_save');
    await page.locator('#sph_sh_rules_list a, #sph_sh_pairs_list a').first().click();
    expect((await removed).status()).toBe(200);
  }
  await expect(page.locator('#sph_sh_rules_list')).toContainText('keine');
  await expect(page.locator('#sph_sh_pairs_list')).toContainText('keine');
});

test('Gruppenbildung: eigener Abschnitt, Gruppen für die Klasse mischen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto(`/directory/${KLASSE}`);
  // a tool of its own, apart from the seating plan
  await expect(page.locator('#additional_teacher_content h3', { hasText: 'Gruppenbildung' })).toBeVisible();
  await expect(page.locator('#additional_teacher_content h3', { hasText: 'Sitzplan und' })).toHaveCount(0);
  await page.locator(`a[href="/zufallsgruppen/${KLASSE}"]`).filter({ hasText: 'Gruppen bilden' }).click();
  await expect(page.locator('h1')).toContainText('Gruppenbildung');
  await expect(page.locator('#zg_bu_mix')).toBeVisible();
  await page.locator('#zg_bu_mix').click();
  await expect(page.locator('#zg_groups')).toContainText('Gruppe 1');
  for (const name of ['Max', 'Elli', 'Mallory']) {
    await expect(page.locator('#zg_groups')).toContainText(name);
  }
});

test('Shuffler: nach dem Auslosen den Plan drucken', async ({ page }) => {
  // No music in the example data: play() does nothing, the music file is a
  // stand-in, and the print dialog is only counted.
  await page.addInitScript(() => {
    HTMLMediaElement.prototype.play = function () { return Promise.resolve(); };
    (window as any).__printed = 0;
    window.print = () => { (window as any).__printed++; };
  });
  await page.route('**/api/get_music/**', (route) => route.fulfill({ status: 200, contentType: 'audio/mpeg', body: '' }));
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await page.goto(`/sitzplan/${KLASSE}/${RAUM}`);
  await expect(page.locator('#seats .place')).toHaveCount(3);
  await expect(page.locator('#bu_print_shuffle')).toBeHidden();

  // shuffle; when the music is over, the plan stands still and can be printed
  await page.keyboard.press('Space');
  await expect(page.locator('#bu_print_shuffle')).toBeHidden();
  await page.locator('#audio').evaluate((audio) => audio.dispatchEvent(new Event('ended')));
  await expect(page.locator('#bu_print_shuffle')).toBeVisible();
  await page.locator('#bu_print_shuffle').click();
  expect(await page.evaluate(() => (window as any).__printed)).toBe(1);

  // on paper only the plan, without buttons
  await page.emulateMedia({ media: 'print' });
  await expect(page.locator('.keys')).toBeHidden();
  await expect(page.locator('#seats .place').first()).toBeVisible();
  await expect(page.locator('h1')).toContainText(KLASSE);
  // the photos are background images: printed only when forced
  const adjust = await page.locator('#seats .place img').first().evaluate((img) => {
    const style = getComputedStyle(img);
    return style.getPropertyValue('print-color-adjust') || style.getPropertyValue('-webkit-print-color-adjust');
  });
  expect(adjust).toBe('exact');
});

test('Sitzplan: gespeicherten Plan bearbeiten, an derselben Stelle speichern, mit Fotos drucken', async ({ page }) => {
  await page.addInitScript(() => {
    (window as any).__printed = 0;
    window.print = () => { (window as any).__printed++; };
  });
  await login(page, ACCOUNTS.admin);
  const RAUM = await setUpRoom(page);
  await openSeatingPlan(page, RAUM);
  await startNewPlan(page, 'spread');
  await savePlan(page);

  const history = page.locator('#sph_history_body tr');
  await page.locator('#sph_history_section > summary').click();
  await expect(history.first()).toContainText('aktuell');
  const count = await history.count();
  const savedId = await history.first().locator('.bu-edit-cycle').getAttribute('data-id');

  // reopened from the list, the plan continues in the tool it was made with
  await history.first().getByRole('button', { name: 'Bearbeiten' }).click();
  await expect(page.locator('#sph_bu_discard_cycle')).toBeVisible();
  await expect(page.locator('#sph_cycle_info')).toContainText('Sie bearbeiten den gespeicherten Sitzplan');
  await expect(page.locator('#sph_room_bar #sph_bu_start_spread')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('#sph_seats .place:not(.empty)')).toHaveCount(3);
  await expect(history.first()).toContainText('wird bearbeitet');
  await expect(history.first().locator('.bu-edit-cycle, .bu-delete-cycle')).toHaveCount(0);

  // move Max to a free seat
  const [maxSeat, freeSeat] = await page.evaluate(() => {
    const w = window as any;
    const email = w.sus.find((s: any) => s.display_name === 'Max Mustermann').email;
    const taken = new Set(Object.values(w.current_placement));
    return [w.current_placement[email], w.seats.findIndex((_: unknown, i: number) => !taken.has(i))];
  });
  await page.locator(`#sph_seats .place[data-seat-index="${maxSeat}"]`).click();
  await page.locator(`#sph_seats .place[data-seat-index="${freeSeat}"]`).click();
  await expect(page.locator(`#sph_seats .place[data-seat-index="${freeSeat}"]`)).toContainText('Max');

  // saving overwrites the edited plan instead of adding another one
  const saved = page.waitForResponse('**/api/sph_save_cycle');
  await page.locator('#sph_bu_save').click();
  expect((await saved).status()).toBe(200);
  await expect(page.locator('#sph_status')).toContainText('überschrieben');
  await expect(page.locator('#sph_view_start')).toBeVisible();
  await expect(history.first()).toContainText('geändert am');
  await expect(history).toHaveCount(count);
  await expect(history.first().locator('.bu-edit-cycle')).toHaveAttribute('data-id', savedId!);
  await expect(page.locator(`#sph_seats .place[data-seat-index="${freeSeat}"]`)).toContainText('Max');

  // discarding an edit leaves the saved plan as it was
  await history.first().getByRole('button', { name: 'Bearbeiten' }).click();
  await expect(page.locator('#sph_cycle_info')).toContainText('Sie bearbeiten den gespeicherten Sitzplan');
  await discardOpenPlan(page);
  await expect(page.locator(`#sph_seats .place[data-seat-index="${freeSeat}"]`)).toContainText('Max');
  await expect(history).toHaveCount(count);

  // printing: the photos are real images (browsers leave out background
  // images on paper), loaded before the print dialog opens
  await page.goto(`/sitzplananzeige/${KLASSE}/${RAUM}?print=1`);
  const photos = page.locator('#spa_seats img.spa-card-photo');
  await expect(photos).toHaveCount(3);
  await expect.poll(() => page.evaluate(() => (window as any).__printed), { timeout: 15000 }).toBe(1);
  expect(await photos.evaluateAll((imgs) => imgs.every((i) => (i as HTMLImageElement).complete && !!(i as HTMLImageElement).src))).toBe(true);
  // the page is drawn again for paper with the same, already loaded images
  await photos.first().evaluate((img) => { (img as any).__mark = 1; });
  await page.evaluate(() => window.dispatchEvent(new Event('beforeprint')));
  await expect(photos).toHaveCount(3);
  expect(await photos.evaluateAll((imgs) => imgs.some((i) => (i as any).__mark === 1))).toBe(true);
  await page.evaluate(() => window.dispatchEvent(new Event('afterprint')));
});
