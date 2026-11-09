import { test, expect, login, ACCOUNTS } from './fixtures';

// Text from the database (here: a poll title) is inserted into pages as it
// is – the page renderer never evaluates it as a template expression.
test('Umfragetitel mit #{…} erscheint als Text, nicht ausgewertet', async ({ page, newUserPage }) => {
  const marker = Date.now().toString(36);
  const title = `Umfrage #{6*7} ${marker}`;
  const modal = page.locator('#composeModal');

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
  await modal.getByRole('button', { name: 'Antwortmöglichkeit hinzufügen' }).click();
  const answers = modal.locator('input[placeholder="Bitte geben Sie eine Antwortmöglichkeit ein"]');
  await answers.last().fill('Gut;Schlecht');
  await answers.last().press('Tab');
  const saved = page.waitForResponse('**/api/save_poll');
  await page.locator('#bu_save_poll').click();
  expect((await saved).status()).toBe(200);
  await page.locator('#bu_close_poll_modal').click();

  await page.locator('.poll-div', { hasText: marker }).getByText('Neue Durchführung').click();
  const runModal = page.locator('#pollRunModal');
  await expect(runModal).toBeVisible();
  await page.locator('#bu_poll_run_anonymous').click();
  await runModal.locator('#ti_recipients').pressSequentially('Klasse 5a');
  await runModal.locator('.recipient-input-dropdown').getByText(/^Klasse 5a \(\d+\)$/).click();
  await runModal.locator('.bu-poll-run-spontaneous-dropdown').click();
  await runModal.locator('.bu-poll-run-spontaneous[data-minutes="60"]').click();
  const runSaved = page.waitForResponse('**/api/save_poll_run');
  await page.locator('#bu_save_poll_run').click();
  expect((await runSaved).status()).toBe(200);

  // the invited student's start page shows the title literally
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  const hint = student.locator('.hint_poll', { hasText: marker });
  await expect(hint).toBeVisible();
  await expect(hint).toContainText(`Umfrage #{6*7} ${marker}`);
  await expect(hint).not.toContainText(`Umfrage 42 ${marker}`);
});

// Free-text answers are shown as text in the results, never as HTML.
test('Freitext-Antworten erscheinen in der Auswertung als Text', async ({ page, newUserPage }) => {
  const marker = Date.now().toString(36);
  const title = `Rückmeldung ${marker}`;
  const answer = `<b>fett</b> & <i>kursiv</i> ${marker}`;
  const modal = page.locator('#composeModal');

  await login(page, ACCOUNTS.teacher);
  await page.goto('/polls');
  await page.locator('.bu-new-poll').click();
  await expect(modal).toBeVisible();
  await page.locator('#ti_title').fill(title);
  await modal.getByRole('button', { name: 'Eintrag hinzufügen' }).click();
  await page.locator('.bu-poll-add-textarea').click();
  const question = modal.locator('input[placeholder="Bitte geben Sie eine Frage ein"]').last();
  await question.fill('Was möchtest du sagen?');
  await question.press('Tab');
  const saved = page.waitForResponse('**/api/save_poll');
  await page.locator('#bu_save_poll').click();
  expect((await saved).status()).toBe(200);
  await page.locator('#bu_close_poll_modal').click();

  await page.locator('.poll-div', { hasText: marker }).getByText('Neue Durchführung').click();
  const runModal = page.locator('#pollRunModal');
  await expect(runModal).toBeVisible();
  await page.locator('#bu_poll_run_anonymous').click();
  await runModal.locator('#ti_recipients').pressSequentially('Klasse 5a');
  await runModal.locator('.recipient-input-dropdown').getByText(/^Klasse 5a \(\d+\)$/).click();
  await runModal.locator('.bu-poll-run-spontaneous-dropdown').click();
  await runModal.locator('.bu-poll-run-spontaneous[data-minutes="60"]').click();
  const runSaved = page.waitForResponse('**/api/save_poll_run');
  await page.locator('#bu_save_poll_run').click();
  expect((await runSaved).status()).toBe(200);

  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await student.locator('.hint_poll', { hasText: marker }).locator('.bu-launch-poll').click();
  const responseModal = student.locator('#pollResponseModal');
  await expect(responseModal).toBeVisible();
  // the answer is only taken over when the field loses focus (change event)
  const textarea = responseModal.locator('textarea').first();
  await textarea.fill(answer);
  await textarea.press('Tab');
  await expect(student.locator('#bu_submit_poll_results')).toBeEnabled();
  const submitted = student.waitForResponse('**/api/submit_poll_run');
  await student.locator('#bu_submit_poll_results').click();
  expect((await submitted).status()).toBe(200);

  // teacher opens the results
  await page.goto('/polls');
  const run = page.locator('.poll-div', { hasText: marker })
    .locator('xpath=following-sibling::div[contains(@class, "poll-run-div")][1]');
  await run.getByRole('button', { name: /Ergebnisse/ }).click();
  const results = page.locator('#pollRunResultsModal .poll-run-results-here');
  await expect(results).toContainText(answer);
  await expect(results.locator('b', { hasText: 'fett' })).toHaveCount(0);
});
