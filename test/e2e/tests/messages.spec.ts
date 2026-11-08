import { test, expect, login, ACCOUNTS } from './fixtures';

test('Lehrkraft schreibt eine Nachricht, Schüler:in findet sie im Posteingang', async ({ page, newUserPage }) => {
  const text = `Bitte denkt an das Heft – ${Date.now().toString(36)}`;

  // teacher writes to Max Mustermann
  await login(page, ACCOUNTS.teacher);
  await page.goto('/messages');
  await page.locator('.bu-compose-message').click();
  await expect(page.locator('#composeModal')).toBeVisible();
  await page.locator('#ti_recipients').pressSequentially('Max Mustermann');
  await page.locator('#ti_recipients').press('Enter');
  await expect(page.locator('#composeModal .recipients_list')).toContainText('Max');
  await page.locator('#composeModal .note-editable').click();
  await page.keyboard.type(text);
  await expect(page.locator('#bu_send_message')).toBeEnabled();
  const sent = page.waitForResponse('**/api/send_message');
  await page.locator('#bu_send_message').click();
  expect((await sent).status()).toBe(200);

  // shows up in the teacher's outbox
  await page.goto('/messages');
  await page.locator('#bu-outbox').click();
  await expect(page.locator('.messages-container-outbox')).toContainText(text);

  // student: inbox is rewritten in the background
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await expect(async () => {
    await student.goto('/messages');
    await expect(student.locator('.messages-container-inbox')).toContainText(text, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
});
