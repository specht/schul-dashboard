import { test, expect, login, ACCOUNTS, dashboardDialog } from './fixtures';

// Neues Design (Vorschau): polls – the list as cards with their runs, the
// editor's entries as cards, the run dialog's choices as cards, the answer
// dialog as a sheet with large choices (src/static/preview/polls.css). The
// preview is for admins only on the test stack: the admin (also a teacher)
// creates a poll, runs it for himself and a student and answers it himself.

test('Neues Design: Umfrage anlegen, durchführen, beantworten, auswerten', async ({ page }, testInfo) => {
  const title = `Wandertag ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/polls');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);

    // ---------- creating: the entries as cards ----------
    await page.locator('.bu-new-poll').click();
    const editor = page.locator('#composeModal');
    await expect(editor).toBeVisible();
    await page.locator('#ti_title').fill(title);
    await editor.getByRole('button', { name: 'Eintrag hinzufügen' }).click();
    await page.locator('.bu-poll-add-radio').click();
    await editor.getByRole('button', { name: 'Eintrag hinzufügen' }).click();
    await page.locator('.bu-poll-add-paragraph').click();
    const entries = editor.locator('.pv-poll-entry');
    await expect(entries).toHaveCount(2);
    await expect(entries.nth(0).locator('.pv-entry-kind')).toContainText('Auswahl');
    await expect(entries.nth(1).locator('.pv-entry-kind')).toContainText('Text');
    // no dividers between the cards
    await expect(editor.locator('hr.poll-entry-divider')).toHaveCount(0);
    // the text goes first: moved up with the calm button in its card
    await expect(entries.nth(0).getByRole('button', { name: 'Eintrag nach oben verschieben' })).toBeDisabled();
    await entries.nth(1).getByRole('button', { name: 'Eintrag nach oben verschieben' }).click();
    await expect(entries.nth(0).locator('.pv-entry-kind')).toContainText('Text');
    await expect(entries.nth(1).locator('.pv-entry-kind')).toContainText('Auswahl');
    const question = entries.nth(1).locator('input[placeholder="Bitte geben Sie eine Frage ein"]');
    await question.fill('Wohin soll es gehen?');
    await question.press('Tab');
    await entries.nth(1).getByRole('button', { name: 'Antwortmöglichkeit hinzufügen' }).click();
    const answers = entries.nth(1).locator('input[placeholder="Bitte geben Sie eine Antwortmöglichkeit ein"]');
    await answers.last().fill('Grunewald;Tegeler See');
    await answers.last().press('Tab');
    await expect(answers).toHaveCount(2);
    // "Verwerfen" only while there is something to discard
    await expect(page.locator('#bu_discard_poll')).toBeVisible();
    const saved = page.waitForResponse('**/api/save_poll');
    await page.locator('#bu_save_poll').click();
    expect((await saved).status()).toBe(200);
    await expect(page.locator('#bu_discard_poll')).toBeHidden();
    await page.locator('#bu_close_poll_modal').evaluate((b: HTMLElement) => b.click());
    await expect(editor).toBeHidden();

    // ---------- the list: a card, no runs yet ----------
    const card = page.locator('.pv-poll', { hasText: title });
    await expect(card).toBeVisible();
    await expect(card.locator('.pv-poll-meta')).toContainText('2 Einträge');
    await expect(card.locator('.pv-runs-empty')).toBeVisible();
    // today's list is not drawn in the new design
    await expect(page.locator('.poll-div')).toHaveCount(0);

    // ---------- running: the choices as cards ----------
    await card.locator('.pv-bu-new-run').click();
    const runModal = page.locator('#pollRunModal');
    await expect(runModal).toBeVisible();
    await expect(page.locator('#bu_poll_run_anonymous')).toContainText('Anonym');
    await expect(page.locator('#bu_poll_run_non_anonymous')).toContainText('Mit Namen');
    await expect(runModal.locator('.anonymous_hint')).toBeVisible();
    await page.locator('#bu_poll_run_non_anonymous').click();
    await expect(page.locator('#bu_poll_run_non_anonymous')).toHaveClass(/btn-primary/);
    await expect(runModal.locator('.anonymous_hint')).toBeHidden();
    for (const name of ['Scott Clarke', 'Max Mustermann']) {
      await runModal.locator('#ti_recipients').pressSequentially(name);
      await runModal.locator('.recipient-input-dropdown').getByText(name, { exact: true }).click();
    }
    await expect(runModal.locator('#recipient_count')).toHaveText('2 Teilnehmer');
    await runModal.locator('.bu-poll-run-spontaneous-dropdown').click();
    await runModal.locator('.bu-poll-run-spontaneous[data-minutes="60"]').click();
    const runSaved = page.waitForResponse('**/api/save_poll_run');
    await page.locator('#bu_save_poll_run').click();
    expect((await runSaved).status()).toBe(200);
    await page.locator('#bu_close_poll_run_modal').evaluate((b: HTMLElement) => b.click());

    await page.goto('/polls');
    const run = page.locator('.pv-poll', { hasText: title }).locator('.pv-run');
    await expect(run).toHaveCount(1);
    await expect(run).toHaveClass(/pv-run-running/);
    await expect(run.locator('.pv-run-status')).toHaveText('läuft');
    await expect(run.locator('.pv-run-tags')).toContainText('2 Teilnehmer');
    await expect(run.locator('.pv-run-tags')).toContainText('mit Namen');
    await expect(run.locator('.pv-run-count')).toHaveText('0 von 2 beantwortet (0 %)');

    // ---------- taking part: the hint on the start page, the answer sheet ----------
    await page.goto('/');
    await page.locator('.hint_poll', { hasText: title }).locator('.bu-launch-poll').click();
    const answer = page.locator('#pollResponseModal');
    await expect(answer).toBeVisible();
    await expect(answer).toHaveClass(/pv-sheet/);
    await expect(answer.locator('.poll-title')).toHaveText(title);
    const choice = answer.locator('.poll_radio_buttons p', { hasText: 'Tegeler See' });
    // large enough to tap
    expect((await choice.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    // "Senden" is in view from the start, usable once something is chosen
    const send = page.locator('#bu_submit_poll_results');
    await expect(send).toBeVisible();
    await expect(send).toBeDisabled();
    await expect(page.locator('#bu_discard_poll_results')).toBeHidden();
    await choice.click();
    await expect(choice).toHaveClass(/selected/);
    await expect(send).toBeEnabled();
    await expect(answer.locator('.poll-run-progress-label')).toHaveText('1 von 1 Frage beantwortet');
    const submitted = page.waitForResponse('**/api/submit_poll_run');
    await send.click();
    expect((await submitted).status()).toBe(200);
    await expect(answer.locator('.poll_submit_success')).toBeVisible();

    // ---------- results ----------
    await page.goto('/polls');
    await expect(run.locator('.pv-run-count')).toHaveText('1 von 2 beantwortet (50 %)');
    await run.locator('.pv-bu-results').click();
    const results = page.locator('#pollRunResultsModal');
    await expect(results).toBeVisible();
    await expect(results).toContainText('Tegeler See');
    await expect(results).toContainText('Es fehlen Antworten von');
    await results.locator('#bu_close_show_poll_run_results_modal').evaluate((b: HTMLElement) => b.click());
    await expect(results).toBeHidden();

    // ---------- stopping and deleting: red only in the confirmation ----------
    await run.locator('.pv-bu-stop-run').click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Stoppen' })).toHaveClass(/btn-danger/);
    await dialog.getByRole('button', { name: 'Stoppen' }).click();
    await expect(run).toHaveClass(/pv-run-complete/);
    await expect(run.locator('.pv-run-status')).toHaveText('beendet');

    await page.locator('.pv-poll', { hasText: title }).locator('.pv-bu-delete-poll').click();
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(title);
    const deleted = page.waitForResponse('**/api/delete_poll');
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    expect((await deleted).status()).toBe(200);
    await expect(page.locator('.pv-poll', { hasText: title })).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Umfragen in den Farben des Designs, auch dunkel', async ({ page }, testInfo) => {
  const title = `Farben ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'dark' } });
  let pid = '';
  try {
    const items = [{ type: 'radio', title: 'Frage', answers: ['Ja', 'Nein'] }];
    pid = (await (await page.request.post('/api/save_poll', { data: { title, items: JSON.stringify(items) } })).json()).poll.pid;
    await page.goto('/polls');
    await expect(page.locator('body')).toHaveClass(/dark/);
    await expect(page.locator('.pv-poll', { hasText: title })).toBeVisible();
    // the editor's dialog on the design's surface (dark.css would paint it #222)
    await page.locator('.pv-poll', { hasText: title }).locator('.pv-bu-edit-poll').click();
    const content = page.locator('#composeModal .modal-content');
    await expect(content).toBeVisible();
    const [surface, background] = await content.evaluate((el) => [
      getComputedStyle(document.body).getPropertyValue('--pv-surface').trim(),
      getComputedStyle(el).backgroundColor,
    ]);
    expect(background).not.toBe('rgb(34, 34, 34)');
    expect(surface.length).toBeGreaterThan(0);
  } finally {
    if (pid) await page.request.post('/api/delete_poll', { data: { pid } });
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Umfragen ohne Vorschau: die Liste und der Dialog wie bisher', async ({ page }, testInfo) => {
  const title = `Wie bisher ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const items = [{ type: 'radio', title: 'Frage', answers: ['Ja', 'Nein'] }];
  const pid = (await (await page.request.post('/api/save_poll', { data: { title, items: JSON.stringify(items) } })).json()).poll.pid;
  try {
    await page.goto('/polls');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(page.locator('.poll-div', { hasText: title })).toBeVisible();
    await expect(page.locator('.pv-poll')).toHaveCount(0);
    await page.locator('.poll-div', { hasText: title }).getByRole('button', { name: 'Bearbeiten' }).click();
    await expect(page.locator('#composeModal .pv-poll-entry')).toHaveCount(0);
    await expect(page.locator('#composeModal hr.poll-entry-divider')).toHaveCount(1);
    await page.locator('#bu_close_poll_modal').click();
    await page.locator('.poll-div', { hasText: title }).getByText('Neue Durchführung').click();
    await expect(page.locator('#bu_poll_run_anonymous')).toHaveText(/Anonyme Erfassung der\s+Umfrageergebnisse/);
  } finally {
    await page.request.post('/api/delete_poll', { data: { pid } });
  }
});
