import { test, expect, login, ACCOUNTS, ROLE_ACCOUNTS } from './fixtures';

test('Lehrkraft erstellt eine Umfrage für 5a, Schüler:in beantwortet sie', async ({ page, newUserPage }) => {
  const title = `Feedback ${Date.now().toString(36)}`;
  const modal = page.locator('#composeModal');

  // teacher creates a poll with one single-choice question
  await login(page, ACCOUNTS.teacher);
  await page.goto('/polls');
  await page.locator('.bu-new-poll').click();
  await expect(modal).toBeVisible();
  await page.locator('#ti_title').fill(title);
  await modal.getByRole('button', { name: 'Eintrag hinzufügen' }).click();
  await page.locator('.bu-poll-add-radio').click();
  const question = modal.locator('input[placeholder="Bitte geben Sie eine Frage ein"]').last();
  await question.fill('Wie war die Stunde?');
  await question.press('Tab');
  // several answers at once, separated by semicolons (as the hint says)
  await modal.getByRole('button', { name: 'Antwortmöglichkeit hinzufügen' }).click();
  const answers = modal.locator('input[placeholder="Bitte geben Sie eine Antwortmöglichkeit ein"]');
  await answers.last().fill('Gut;Mittel;Schlecht');
  await answers.last().press('Tab');
  await expect(answers).toHaveCount(3);

  const saved = page.waitForResponse('**/api/save_poll');
  await page.locator('#bu_save_poll').click();
  expect((await saved).status()).toBe(200);
  await page.locator('#bu_close_poll_modal').click();

  // start a run for class 5a, open for the next hour
  await page.locator('.poll-div', { hasText: title }).getByText('Neue Durchführung').click();
  const runModal = page.locator('#pollRunModal');
  await expect(runModal).toBeVisible();
  // required choice, cannot be changed later
  await page.locator('#bu_poll_run_anonymous').click();
  // "Klasse 5a" matches several groups (parents, teachers) – pick it from the list
  await runModal.locator('#ti_recipients').pressSequentially('Klasse 5a');
  await runModal.locator('.recipient-input-dropdown').getByText(/^Klasse 5a \(\d+\)$/).click();
  await expect(runModal.locator('.recipients_list')).toContainText('Klasse 5a');
  await runModal.locator('.bu-poll-run-spontaneous-dropdown').click();
  await runModal.locator('.bu-poll-run-spontaneous[data-minutes="60"]').click();
  const runSaved = page.waitForResponse('**/api/save_poll_run');
  await page.locator('#bu_save_poll_run').click();
  expect((await runSaved).status()).toBe(200);

  // student sees it next to the timetable and answers
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await student.locator('.hint_poll', { hasText: title }).locator('.bu-launch-poll').click();
  const responseModal = student.locator('#pollResponseModal');
  await expect(responseModal).toBeVisible();
  await expect(responseModal.locator('.poll-title')).toHaveText(title);
  await responseModal.locator('.poll-items').getByText('Mittel', { exact: true }).click();
  await expect(student.locator('#bu_submit_poll_results')).toBeEnabled();
  const submitted = student.waitForResponse('**/api/submit_poll_run');
  await student.locator('#bu_submit_poll_results').click();
  expect((await submitted).status()).toBe(200);
  await expect(responseModal.locator('.poll_submit_success')).toBeVisible();

  // teacher: one of three students in 5a has answered
  await page.goto('/polls');
  const run = page.locator('.poll-div', { hasText: title })
    .locator('xpath=following-sibling::div[contains(@class, "poll-run-div")][1]');
  await expect(run.getByRole('button', { name: /Ergebnisse/ })).toContainText('33% beantwortet');
});

test('Begrenzte Plätze: volle Antworten sind gesperrt, die Auswertung zeigt die Reihenfolge', async ({ page, newUserPage }) => {
  const title = `Studientag ${Date.now().toString(36)}`;
  const modal = page.locator('#composeModal');

  // teacher creates a poll with one single-choice question
  await login(page, ACCOUNTS.teacher);
  await page.goto('/polls');
  await page.locator('.bu-new-poll').click();
  await expect(modal).toBeVisible();
  await page.locator('#ti_title').fill(title);
  await modal.getByRole('button', { name: 'Eintrag hinzufügen' }).click();
  await page.locator('.bu-poll-add-radio').click();
  const question = modal.locator('input[placeholder="Bitte geben Sie eine Frage ein"]').last();
  await question.fill('Welcher Workshop?');
  await question.press('Tab');
  await modal.getByRole('button', { name: 'Antwortmöglichkeit hinzufügen' }).click();
  const answers = modal.locator('input[placeholder="Bitte geben Sie eine Antwortmöglichkeit ein"]');
  await answers.last().fill('Töpfern;Theater');
  await answers.last().press('Tab');
  await expect(answers).toHaveCount(2);
  const saved = page.waitForResponse('**/api/save_poll');
  await page.locator('#bu_save_poll').click();
  expect((await saved).status()).toBe(200);
  await page.locator('#bu_close_poll_modal').click();

  // run for 5a: the option only exists for runs with names
  await page.locator('.poll-div', { hasText: title }).getByText('Neue Durchführung').click();
  const runModal = page.locator('#pollRunModal');
  await expect(runModal).toBeVisible();
  await expect(page.locator('#bu_poll_run_limited_places')).toBeHidden();
  await page.locator('#bu_poll_run_anonymous').click();
  await expect(page.locator('#bu_poll_run_limited_places')).toBeHidden();
  await page.locator('#bu_poll_run_non_anonymous').click();
  await page.locator('#bu_poll_run_limited_places').click();
  // one place for "Töpfern", "Theater" stays unlimited
  const limit = runModal.locator('.ti_place_limit[data-item-index="0"][data-answer-index="0"]');
  await expect(limit).toBeVisible();
  await expect(runModal.locator('.limited_places_hint')).toBeVisible();
  await limit.fill('1');
  await limit.press('Tab');
  await expect(runModal.locator('.limited_places_hint')).toBeHidden();
  await runModal.locator('#ti_recipients').pressSequentially('Klasse 5a');
  await runModal.locator('.recipient-input-dropdown').getByText(/^Klasse 5a \(\d+\)$/).click();
  await runModal.locator('.bu-poll-run-spontaneous-dropdown').click();
  await runModal.locator('.bu-poll-run-spontaneous[data-minutes="60"]').click();
  const runSaved = page.waitForResponse('**/api/save_poll_run');
  await page.locator('#bu_save_poll_run').click();
  expect((await runSaved).status()).toBe(200);
  // whether places are limited can't be changed afterwards
  await expect(page.locator('#bu_poll_run_limited_places')).toBeDisabled();

  async function openPoll(email: string) {
    const student = await newUserPage();
    await login(student, email);
    await student.locator('.hint_poll', { hasText: title }).locator('.bu-launch-poll').click();
    const responseModal = student.locator('#pollResponseModal');
    await expect(responseModal.locator('.poll-title')).toHaveText(title);
    await expect(responseModal.locator('.poll-run-limited-places')).toBeVisible();
    return { student, responseModal };
  }

  // Elli opens the poll while the place is still free and picks it ...
  const elli = await openPoll(ROLE_ACCOUNTS.sv);
  const elliPottery = elli.responseModal.locator('.poll-items p', { hasText: 'Töpfern' });
  await expect(elliPottery).toContainText('noch 1 von 1 Platz frei');
  await elliPottery.click();
  await expect(elliPottery).toHaveClass(/selected/);

  // ... but Max sends first and gets it
  const max = await openPoll(ACCOUNTS.schueler);
  await max.responseModal.locator('.poll-items p', { hasText: 'Töpfern' }).click();
  const maxSubmitted = max.student.waitForResponse('**/api/submit_poll_run');
  await max.student.locator('#bu_submit_poll_results').click();
  expect((await maxSubmitted).status()).toBe(200);
  await expect(max.responseModal.locator('.poll_submit_success')).toBeVisible();
  await expect(max.responseModal.locator('.poll-items p', { hasText: 'Töpfern' })).toContainText('gebucht');

  // Elli's answer is refused, the place now shows as full and can't be picked
  await elli.student.locator('#bu_submit_poll_results').click();
  await expect(elli.responseModal.locator('.poll_submit_error')).toContainText('„Töpfern“ ist inzwischen ausgebucht');
  await expect(elliPottery).toContainText('ausgebucht');
  await expect(elliPottery).not.toHaveClass(/selected/);
  await elliPottery.click();
  await expect(elliPottery).not.toHaveClass(/selected/);
  await elli.responseModal.locator('.poll-items p', { hasText: 'Theater' }).click();
  const elliSubmitted = elli.student.waitForResponse('**/api/submit_poll_run');
  await elli.student.locator('#bu_submit_poll_results').click();
  expect((await elliSubmitted).status()).toBe(200);
  await expect(elli.responseModal.locator('.poll_submit_success')).toBeVisible();

  // participants only see how many places are left – never who booked
  await max.student.reload();
  const pollData = max.student.waitForResponse('**/api/get_poll_run');
  await max.student.locator('.hint_poll', { hasText: title }).locator('.bu-launch-poll').click();
  const pollJson = JSON.stringify(await (await pollData).json());
  expect(pollJson).toContain('taken_by_others');
  expect(pollJson.toLowerCase()).not.toContain('elli');
  expect(pollJson).not.toContain('Elisabeth');
  expect(pollJson).not.toContain('booked_at');
  await expect(max.responseModal.locator('.poll-items p', { hasText: 'Töpfern' })).toContainText('gebucht, noch 0 von 1 Platz frei');
  await expect(max.responseModal).not.toContainText(/Elli|Elisabeth/);

  // teacher: places and booking order in the results
  await page.goto('/polls');
  const run = page.locator('.poll-div', { hasText: title })
    .locator('xpath=following-sibling::div[contains(@class, "poll-run-div")][1]');
  await expect(run).toContainText('begrenzte Plätze');
  await run.getByRole('button', { name: /Ergebnisse/ }).click();
  const results = page.locator('#pollRunResultsModal');
  await expect(results).toBeVisible();
  await expect(results).toContainText('Reihenfolge der Buchung');
  await expect(results.locator('td', { hasText: /1\s\/\s1\sPlätze/ })).toContainText('ausgebucht');
  const orders = results.locator('ol.poll-booking-order');
  await expect(orders).toHaveCount(2);
  await expect(orders.nth(0).locator('li')).toHaveCount(1);
  await expect(orders.nth(0)).toContainText('Max');
  await expect(orders.nth(1)).toContainText(/Elli|Elisabeth/);
});
