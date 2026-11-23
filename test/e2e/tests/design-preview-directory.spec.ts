import { test, expect, login, ACCOUNTS, dashboardDialog } from './fixtures';

// Neues Design (Vorschau): the class directory (/directory/<klasse>) as a
// table page – on wide screens a table with the addresses as copy fields,
// where it is narrow list rows that open the student in a dialog (a sheet on
// phones). src/static/preview/directory.js and .css, data from
// directory_preview_html (include/directory.rb). The preview is for admins
// only on the test stack: the admin is a teacher and class teacher of 5a
// (Max, Elli and Mallory Mustermann), not of 11. Today's page stays as it
// was (last test).

const LIST_DOMAIN = 'verteiler.beispielschule.de';

test('Neues Design: Klassenliste der eigenen Klasse', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/directory/5a');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);

    // ---------- the head: title, how many, the class teacher ----------
    await expect(page.locator('.pv-dir-head h2')).toHaveText('Klasse 5a');
    await expect(page.locator('.pv-dir-head .pv-dir-facts')).toHaveText('3 Schülerinnen und Schüler, Klassenleitung Scott Clarke');
    // today's table is not there
    await expect(page.locator('.klassen_table')).toHaveCount(0);
    expect(await page.locator('.pv-dir').innerText()).not.toContain('·');

    // ---------- one row per student, by last name and first name ----------
    const rows = page.locator('.pv-dir-row');
    await expect(rows).toHaveCount(3);
    await expect(rows.locator('.pv-dir-name')).toHaveText(['Mustermann, Elli', 'Mustermann, Mallory', 'Mustermann, Max']);
    const max = rows.filter({ hasText: 'Mustermann, Max' });
    const email = ACCOUNTS.schueler;
    await expect(max.locator('.pv-dir-facts')).toContainText(/\d\d\.\d\d\.\d{4}, männlich/);
    // the columns on wide screens, a list row with »›« on phones
    await expect(page.locator('.pv-dir-table thead')).toBeVisible({ visible: !phone });
    await expect(max.locator('.pv-dir-mail .pv-copy')).toBeVisible({ visible: !phone });
    await expect(max.locator('.pv-dir-chev')).toBeVisible({ visible: phone });
    // the class teacher's actions sit behind »•••« (only on wide screens)
    await expect(max.locator('.pv-dir-more')).toBeVisible({ visible: !phone });

    if (!phone) {
      // ---------- wide: copy in the row, switch the group in the row ----------
      const field = max.locator('.pv-dir-mail .pv-copy');
      await expect(field).toHaveText(email);
      await field.click();
      await expect(field).toHaveClass(/pv-copied/);
      await expect(field.locator('.pv-copy-ok')).toBeVisible();
      await expect(field.locator('.pv-copy-icon')).toBeHidden();
      expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(email);
      // copying opens nothing
      await expect(page.locator('#directoryStudentModal')).toHaveCount(0);
      await expect(field).not.toHaveClass(/pv-copied/, { timeout: 5000 });
      await max.locator('.pv-dir-parents .pv-copy').click();
      expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`eltern.${email}`);

      const group = max.locator('button.pv-dir-group');
      await expect(group).toHaveText('A');
      let toggled = page.waitForResponse('**/api/toggle_group2_for_user');
      await group.click();
      expect((await toggled).status()).toBe(200);
      await expect(group).toHaveText('B');
      toggled = page.waitForResponse('**/api/toggle_group2_for_user');
      await group.click();
      expect((await toggled).status()).toBe(200);
      await expect(group).toHaveText('A');

      // »•••«: E-Mail-Brief and the Dashboard-Amt
      await max.locator('.pv-dir-more').click();
      const menu = page.locator('.pv-amenu');
      await expect(menu.getByRole('menuitem')).toHaveText(['E-Mail-Brief (Zugangsdaten)', 'Dashboard-Amt vergeben']);
      await page.keyboard.press('Escape');
      await expect(menu).toHaveCount(0);
    }

    // ---------- the student in a dialog (a sheet on phones) ----------
    await max.locator('.pv-dir-name').click();
    const modal = page.locator('#directoryStudentModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('.modal-title')).toHaveText('Max Mustermann');
    const dl = modal.locator('.pv-dir-dl');
    await expect(dl.locator('dt')).toContainText(['E-Mail', 'Eltern', 'Geburtsdatum', 'Geschlecht', 'Bildungsgang', 'Letzter Zugriff', 'Gruppe', 'Dashboard-Amt']);
    const parents = dl.locator('.pv-dir-dl-row', { hasText: 'Eltern' }).locator('.pv-copy');
    await expect(parents).toHaveText(`eltern.${email}`);
    await parents.click();
    await expect(parents).toHaveClass(/pv-copied/);
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`eltern.${email}`);
    // the group, switched here as well (and back)
    const group_row = dl.locator('.pv-dir-dl-row', { hasText: 'Gruppe' });
    await expect(group_row.locator('dd span')).toHaveText('A');
    await group_row.getByRole('button', { name: 'Wechseln' }).click();
    await expect(group_row.locator('dd span')).toHaveText('B');
    if (!phone) await expect(max.locator('button.pv-dir-group')).toHaveText('B');
    await group_row.getByRole('button', { name: 'Wechseln' }).click();
    await expect(group_row.locator('dd span')).toHaveText('A');

    // the E-Mail-Brief: a PDF in a new tab
    const letter = page.waitForResponse('**/api/print_email_letters');
    const popup = page.waitForEvent('popup');
    await modal.locator('#bu_dir_letter').click();
    const response = await letter;
    expect(response.status()).toBe(200);
    expect(response.headers()['content-type']).toContain('application/pdf');
    await (await popup).close();

    // the Dashboard-Amt: the dialog closes, the confirmation asks first
    const amt_row = dl.locator('.pv-dir-dl-row', { hasText: 'Dashboard-Amt' });
    await expect(amt_row.locator('dd span')).toHaveText('nein');
    await amt_row.getByRole('button', { name: 'Vergeben' }).click();
    const confirm = dashboardDialog(page);
    await expect(confirm).toBeVisible();
    await expect(modal).toBeHidden();
    await expect(confirm).toContainText('Möchtest du das Dashboard-Amt an Max Mustermann vergeben?');
    await confirm.getByRole('button', { name: 'Vergeben' }).click();
    await expect(max.locator('.pv-dir-amt')).toBeVisible();
    // and taken back
    await max.locator('.pv-dir-name').click();
    await expect(modal).toBeVisible();
    await expect(amt_row.locator('dd span')).toHaveText('ja');
    await amt_row.getByRole('button', { name: 'Entziehen' }).click();
    await expect(confirm).toBeVisible();
    await expect(confirm).toContainText('Möchtest du Max Mustermann das Dashboard-Amt entziehen?');
    await confirm.getByRole('button', { name: 'Entziehen' }).click();
    await expect(max.locator('.pv-dir-amt')).toBeHidden();

    // back closes the dialog and stays on the page
    await max.locator('.pv-dir-name').click();
    await expect(modal).toBeVisible();
    await page.goBack();
    await expect(modal).toBeHidden();
    await expect(page).toHaveURL(/\/directory\/5a$/);

    // ---------- sections: mailing lists, Unterricht, lists, teachers ----------
    const lists = page.locator('.pv-dir-list');
    await expect(lists.locator('.pv-dir-list-label')).toHaveText(['Schülerinnen und Schüler', 'Eltern', 'Lehrkräfte']);
    await expect(lists.locator('.pv-copy')).toHaveText([`klasse.5a@${LIST_DOMAIN}`, `eltern.5a@${LIST_DOMAIN}`, `lehrer.5a@${LIST_DOMAIN}`]);
    await lists.nth(1).locator('.pv-copy').click();
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`eltern.5a@${LIST_DOMAIN}`);

    const tools = page.locator('.pv-dir-tools-sec');
    await expect(tools.locator('.pv-dir-link', { hasText: 'Gruppen bilden' })).toHaveAttribute('href', '/zufallsgruppen/5a');
    await expect(tools.locator('.pv-dir-link', { hasText: 'Live-Anmeldungen der Klasse' })).toHaveAttribute('href', '/show_login_codes/5a');
    await expect(tools.locator('.pv-dir-link', { hasText: 'Bisherige E-Mails aus dem Unterricht' })).toHaveAttribute('href', '/email_overview/5a');
    // the Sitzplan from today's page script, as a link here
    await expect(tools.locator('.pv-dir-link', { hasText: /^Sitzplan Raum / })).not.toHaveCount(0);
    await expect(page.locator('#additional_teacher_content')).toBeHidden();

    const downloads = page.locator('.pv-dir-downloads-sec .pv-dir-link');
    await expect(downloads).toHaveText(['Excel-Tabelle', 'Kursbuch-PDF', 'Timetex-PDF', 'Timetex-PDF nach Vornamen', 'JSON',
      'Klassensatz Stundenpläne (3 Seiten)', 'Alle E-Mail-Briefe (Zugangsdaten)']);
    await expect(downloads.first()).toHaveAttribute('href', '/api/directory_xlsx/5a');
    const xlsx = await page.request.get('/api/directory_xlsx/5a');
    expect(xlsx.status()).toBe(200);

    const teachers = page.locator('.pv-dir-teachers-sec .pv-dir-trow');
    await expect(teachers.first()).toContainText('Scott Clarke');
    await expect(teachers.first().locator('.pv-lchip')).toHaveText('Klassenleitung');
    await expect(teachers.first().locator('.pv-copy')).toHaveText('clarke@beispielschule.de');

    // ---------- the quick search marks the person ----------
    const id = await max.getAttribute('data-user-id');
    await page.goto(`/directory/5a#quick=${id}`);
    await expect(page.locator(`.pv-dir-row[data-user-id="${id}"]`)).toHaveClass(/quick-search-highlight/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Another class (not the admin's own) and a course: the Antikenfahrt in 11,
// no class teacher's actions; a course without the class sections.
test('Neues Design: Klasse 11 und ein Kurs', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/directory/11');
    await expect(page.locator('.pv-dir-head h2')).toHaveText('Klasse 11');
    const alice = page.locator('.pv-dir-row', { hasText: 'Mustermann, Alice' });
    await expect(alice).toHaveCount(1);
    await expect(page.locator('.pv-dir-table th', { hasText: 'Antikenfahrt' })).toBeVisible({ visible: !phone });
    await expect(alice.locator('.pv-dir-af')).toHaveText('nicht eingeteilt');
    // not the class teacher: no Dashboard-Amt to give, but the E-Mail-Brief (admin)
    if (!phone) {
      await alice.locator('.pv-dir-more').click();
      await expect(page.locator('.pv-amenu').getByRole('menuitem')).toHaveText(['E-Mail-Brief (Zugangsdaten)']);
      await page.keyboard.press('Escape');
    }
    await alice.locator('.pv-dir-name').click();
    const modal = page.locator('#directoryStudentModal');
    await expect(modal.locator('.pv-dir-dl dt')).toContainText(['Tutor:in', 'Letzter Zugriff', 'Gruppe', 'Antikenfahrt']);
    await expect(modal.locator('.pv-dir-dl dt', { hasText: 'Dashboard-Amt' })).toHaveCount(0);
    await page.keyboard.press('Escape');
    await expect(modal).toBeHidden();
    // a student without a birthday
    await expect(page.locator('.pv-dir-row', { hasText: 'Ohnegeburtstag, Gina' }).locator('.pv-dir-facts')).not.toContainText('–');

    // a course (Alice from 11 and Bob from 12, test/prepare_example_data.rb):
    // its students, the course's mailing lists, no class sections
    await page.goto('/directory/LA-L108_11~12');
    await expect(page.locator('.pv-dir-head h2')).toHaveText('Latein LK (11, 12)');
    await expect(page.locator('.pv-dir-row', { hasText: 'Mustermann, Alice' })).toHaveCount(1);
    await expect(page.locator('.pv-dir-row', { hasText: 'Mustermann, Bob' })).toHaveCount(1);
    await expect(page.locator('.pv-dir-list-label')).toHaveText(['Schülerinnen und Schüler', 'Eltern']);
    await expect(page.locator('.pv-dir-tools-sec')).toHaveCount(0);
    await expect(page.locator('.pv-dir-teachers-sec')).toHaveCount(0);

    // a class without students: an empty state (today's table fails there,
    // TODO.md)
    const empty = await page.goto('/directory/5b');
    expect(empty!.status()).toBe(200);
    await expect(page.locator('.pv-dir-head h2')).toHaveText('Klasse 5b');
    await expect(page.locator('.pv-dir-students .pv-lempty')).toHaveText('In dieser Klasse ist zurzeit niemand eingetragen.');
    await expect(page.locator('.pv-dir-list-label')).toHaveText(['Schülerinnen und Schüler', 'Eltern', 'Lehrkräfte']);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Today's page is untouched: the table with its columns, buttons and the
// Sitzplan from the page script.
test('Klassenliste im bisherigen Design', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/directory/5a');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('.pv-dir')).toHaveCount(0);
  const table = page.locator('.klassen_table');
  await expect(table.locator('thead th')).toContainText(['Nr.', 'Name', 'Vorname', 'Geburtsdatum', 'E-Mail-Adresse', 'Dashboard-Amt', 'A/B', 'Letzter Zugriff', 'Eltern-E-Mail-Adresse', 'E-Mail-Brief']);
  await expect(table.locator('tr.user_row[data-email]')).toHaveCount(3);
  await expect(table.locator('.bu_print_email_letter')).toHaveCount(3);
  await expect(page.locator('.bu-email-letters')).toBeVisible();
  await expect(page.locator('#additional_teacher_content h3', { hasText: 'Gruppenbildung' })).toBeVisible();
  await expect(page.locator('h3', { hasText: 'Lehrkräfte der Klasse 5a' })).toBeVisible();
});
