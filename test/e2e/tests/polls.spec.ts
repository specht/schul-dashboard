import { test, expect, login, ACCOUNTS } from './fixtures';

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
