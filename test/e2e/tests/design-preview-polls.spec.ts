import { test, expect, login, ACCOUNTS, dashboardDialog, listAction } from './fixtures';

// Neues Design (Vorschau): polls – the list with actions (rows, runs as
// sub-rows, "•••" menu or sheet, preview.js pv_list), the editor's entries as cards, the run dialog's choices as cards, the answer
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

    // ---------- the list: a row, no runs yet ----------
    const card = page.locator('.pv-poll', { hasText: title });
    const pollRow = card.locator('.pv-poll-row');
    await expect(card).toBeVisible();
    await expect(pollRow.locator('.pv-lrow-facts')).toContainText('2 Einträge, noch nicht durchgeführt');
    // today's list is not drawn in the new design
    await expect(page.locator('.poll-div')).toHaveCount(0);

    // ---------- running: the choices as cards ----------
    await listAction(page, pollRow, 'Neue Durchführung');
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
    await expect(runModal).toBeHidden();
    // closing went back over the dialog's history entry (pv_back): let it settle
    await page.waitForFunction(() => !(history.state && history.state.pvLayer));

    await page.goto('/polls');
    const run = page.locator('.pv-poll', { hasText: title }).locator('.pv-run');
    await expect(run).toHaveCount(1);
    await expect(run).toHaveClass(/pv-run-running/);
    await expect(run).toHaveClass(/pv-lrow-sub/);
    await expect(run.locator('.pv-lchip')).toHaveText('läuft');
    await expect(run.locator('.pv-lrow-facts')).toHaveText('2 Teilnehmer, mit Namen');
    await expect(run.locator('.pv-run-count')).toHaveText('0 von 2 beantwortet (0 %)');

    // ---------- taking part: "Zu erledigen" on the start page, the answer sheet ----------
    await page.goto('/');
    const todoFold = page.locator('#pv_todo .pv-todo-fold');
    if (await todoFold.count() > 0 && (await todoFold.getAttribute('aria-expanded')) === 'false') await todoFold.click();
    await page.locator('#pv_todo .pv-todo-row', { hasText: title }).getByRole('button', { name: 'Teilnehmen' }).click();
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
    if (testInfo.project.name === 'mobile') {
      // phones: the row itself opens the results (with the arrow at its end)
      await expect(run.locator('.pv-lrow-chev')).toBeVisible();
      await expect(run.locator('.pv-lact')).toHaveCount(2);
      await expect(run.locator('.pv-lact').first()).toBeHidden();
      await run.locator('.pv-lrow-title').click();
    } else {
      await expect(run.locator('.pv-lrow-chev')).toBeHidden();
      await listAction(page, run, 'Ergebnisse');
    }
    const results = page.locator('#pollRunResultsModal');
    await expect(results).toBeVisible();
    await expect(results).toContainText('Tegeler See');
    await expect(results).toContainText('Es fehlen Antworten von');
    await results.locator('#bu_close_show_poll_run_results_modal').evaluate((b: HTMLElement) => b.click());
    await expect(results).toBeHidden();

    // ---------- stopping: red only in the confirmation ----------
    await listAction(page, run, 'Stoppen');
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('button', { name: 'Stoppen' })).toHaveClass(/btn-danger/);
    await dialog.getByRole('button', { name: 'Stoppen' }).click();
    await expect(dialog).toBeHidden();
    // finished runs are folded
    const fold = card.locator('.pv-lfold');
    await expect(fold).toHaveText('1 beendete Durchführung anzeigen');
    await expect(fold).toHaveAttribute('aria-expanded', 'false');
    await expect(run).toBeHidden();
    await fold.click();
    await expect(fold).toHaveAttribute('aria-expanded', 'true');
    await expect(run).toBeVisible();
    await expect(run).toHaveClass(/pv-run-complete/);
    await expect(run.locator('.pv-lchip')).toHaveText('beendet');

    // ---------- the "•••" menu: beside the button, a sheet on phones ----------
    const more = pollRow.locator(':scope > .pv-lrow-actions > .pv-lmore');
    await expect(more).toHaveAttribute('aria-haspopup', 'menu');
    await expect(more).toHaveAttribute('aria-expanded', 'false');
    await more.click();
    const menu = page.locator('.pv-amenu');
    await expect(menu).toBeVisible();
    await expect(more).toHaveAttribute('aria-expanded', 'true');
    await expect(menu).toHaveAttribute('aria-label', title);
    const items = menu.getByRole('menuitem');
    if (testInfo.project.name === 'mobile') {
      // all actions, the item's title at the top, delete at the end
      await expect(menu).toHaveClass(/pv-amenu-sheet/);
      await expect(menu.locator('.pv-amenu-title')).toHaveText(title);
      await expect(items).toHaveText(['Neue Durchführung', 'Bearbeiten', 'Löschen']);
      const box = (await menu.boundingBox())!;
      expect(box.y + box.height).toBeGreaterThan(page.viewportSize()!.height - 2);
    } else {
      // only what is not in the row, next to the button
      await expect(menu).not.toHaveClass(/pv-amenu-sheet/);
      await expect(items).toHaveText(['Löschen']);
      const b = (await more.boundingBox())!, m = (await menu.boundingBox())!;
      expect(Math.abs(m.y - (b.y + b.height))).toBeLessThan(12);
    }
    await expect(items.last()).toHaveClass(/pv-amenu-danger/);
    if (testInfo.project.name === 'mobile') {
      // back (button or swipe) closes the sheet and stays on the page
      const url = page.url();
      await page.goBack();
      await expect(menu).toHaveCount(0);
      expect(page.url()).toBe(url);
      await expect(page.locator('.pv-amenu-veil')).toHaveCount(0);
      await more.click();
      await expect(menu).toBeVisible();
    }
    // Escape closes it and gives the focus back
    await page.keyboard.press('Escape');
    await expect(menu).toHaveCount(0);
    await expect(more).toBeFocused();
    await expect(more).toHaveAttribute('aria-expanded', 'false');
    // from the keyboard: the first entry has the focus, the arrow keys move it
    await page.keyboard.press('Enter');
    await expect(menu).toBeVisible();
    await expect(items.first()).toBeFocused();
    await page.keyboard.press('End');
    await expect(items.last()).toBeFocused();
    await page.keyboard.press('ArrowDown');
    await expect(items.first()).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(menu).toHaveCount(0);

    // ---------- deleting: in the menu, confirmed ----------
    await listAction(page, pollRow, 'Löschen');
    await expect(dialog).toBeVisible();
    await expect(dialog).toContainText(title);
    await expect(dialog.getByRole('button', { name: 'Löschen' })).toHaveClass(/btn-danger/);
    await expect(dialog.getByRole('button', { name: 'Abbrechen' })).toBeFocused();
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
    await listAction(page, page.locator('.pv-poll', { hasText: title }).locator('.pv-poll-row'), 'Bearbeiten');
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

test('Neues Design: Umfragen nach Schuljahr, frühere gefaltet, Seite höchstens 980 px breit', async ({ page }, testInfo) => {
  const title = `Aktuell ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const items = [{ type: 'radio', title: 'Frage', answers: ['Ja', 'Nein'] }];
  const pid = (await (await page.request.post('/api/save_poll', { data: { title, items: JSON.stringify(items) } })).json()).poll.pid;
  try {
    await page.goto('/polls');
    // this school year first, open
    const current = page.locator('.pv-polls-current');
    await expect(current.locator('.pv-lgroup-head')).toContainText('Aktuell');
    await expect(current.locator('.pv-poll', { hasText: title })).toBeVisible();
    // the seeded poll of 2023/24 (test/e2e/seed.cypher): folded under its school year
    const year = page.locator('.pv-polls-year[data-school-year="2023"]');
    const toggle = year.locator('.pv-lgroup-toggle');
    await expect(toggle).toContainText('Schuljahr 2023/24');
    await expect(toggle).toContainText('1 Umfrage');
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    const archived = year.locator('.pv-poll', { hasText: 'Archiv-Umfrage Schuljahr 2023/24' });
    await expect(archived).toHaveCount(0);
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    await expect(archived).toBeVisible();
    await expect(current.locator('.pv-poll', { hasText: 'Archiv-Umfrage' })).toHaveCount(0);
    // the main action beside the title: short on phones
    const main = page.locator('.pv-lhead .bu-new-poll');
    await expect(main).toBeVisible();
    if (testInfo.project.name === 'mobile') {
      await expect(main).toHaveText('Neu', { useInnerText: true });
    } else {
      await expect(main).toHaveText('Neue Umfrage', { useInnerText: true });
      // a list page: at most about 980 px wide
      const width = await page.locator('#main_container > .container').evaluate((el) => el.getBoundingClientRect().width);
      expect(width).toBeLessThanOrEqual(981);
    }
  } finally {
    await page.request.post('/api/delete_poll', { data: { pid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
