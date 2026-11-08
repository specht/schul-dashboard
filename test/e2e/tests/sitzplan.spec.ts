import { test, expect, login, ACCOUNTS } from './fixtures';

// Example data: Clarke is class teacher of 5a (Max, Elli, Mallory).
const KLASSE = '5a';

test('Sitzplanhelfer: Wunschrunde, Wunsch von SuS, Plan erzeugen und speichern', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);

  // the class page knows which rooms belong to the class (homeroom or
  // rooms from the timetable)
  await page.goto(`/directory/${KLASSE}`);
  const editorLink = page.locator(`a[href^="/sitzplaneditor/${KLASSE}/"]`).first();
  const RAUM = decodeURIComponent((await editorLink.getAttribute('href'))!.split('/').pop()!);

  // setup: two rows with two desks of two seats each (the seat editor has
  // its own UI)
  const seats = [0, 1, 3, 4].flatMap((x) => [0, 2].map((y) => [x, y]));
  const room = await page.request.post('/api/sitzplaneditor_save', {
    data: { klasse: KLASSE, raum: RAUM, seats: JSON.stringify(seats) },
  });
  expect(room.status()).toBe(200);

  // class teacher starts a wish round
  await page.goto(`/sitzplanhelfer/${KLASSE}/${RAUM}`);
  const discard = page.locator('#sph_bu_discard_cycle');
  if (await discard.isVisible()) {
    // left over from an earlier run on the same test stack
    page.once('dialog', (dialog) => dialog.accept());
    await discard.click();
    await expect(page.locator('#sph_bu_start_cycle')).toBeVisible();
  }
  const started = page.waitForResponse('**/api/sph_start_cycle');
  await page.locator('#sph_bu_start_cycle').click();
  expect((await started).status()).toBe(200);

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
  // "Wunschrunde jetzt beenden" asks via the browser's confirm()
  page.once('dialog', (dialog) => dialog.accept());
  const closed = page.waitForResponse('**/api/sph_close_wishes');
  await page.locator('#sph_bu_close_wishes').click();
  expect((await closed).status()).toBe(200);

  await page.locator('#sph_bu_generate').click();
  await expect(page.locator('#sph_seats')).toContainText('Max');
  await expect(page.locator('#sph_seats')).toContainText('Mallory');
  const saved = page.waitForResponse('**/api/sph_save_cycle');
  await page.locator('#sph_bu_save').click();
  expect((await saved).status()).toBe(200);

  // the student view shows the saved plan
  await student.goto(`/sitzplananzeige/${KLASSE}/${RAUM}`);
  // (on phones the collapsed navbar also contains "Max Mustermann")
  for (const name of ['Max', 'Elli', 'Mallory']) {
    await expect(student.getByText(name).filter({ visible: true }).first()).toBeVisible();
  }
});
