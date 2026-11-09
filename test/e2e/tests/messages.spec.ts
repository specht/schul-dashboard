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

// Removing a recipient from a message takes it out of their inbox (before,
// removed recipients kept seeing it until the timetable service restarted).
test('Entfernte Empfänger:innen sehen die Nachricht nicht mehr', async ({ page, newUserPage }) => {
  const text = `Nur noch für Max – ${Date.now().toString(36)}`;
  const max = ACCOUNTS.schueler;
  const elli = 'elli.mustermann@mail.beispielschule.de';
  await login(page, ACCOUNTS.teacher);
  const sent = await page.request.post('/api/send_message', { data: { recipients: [max, elli], message: `<p>${text}</p>` } });
  expect(sent.status()).toBe(200);
  const mid = (await sent.json()).message.mid as string;

  const student = await newUserPage();
  // inbox files may be cached for 60 s – with a route, Playwright bypasses the cache
  await student.route('**/gen/**', (route) => route.continue());
  await login(student, elli);
  const inbox = student.locator('.messages-container-inbox');
  await expect(async () => {
    await student.goto('/messages');
    await expect(inbox).toContainText(text, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });

  // the teacher removes Elli
  const updated = await page.request.post('/api/update_message', { data: { mid, recipients: [max], message: `<p>${text}</p>` } });
  expect(updated.status()).toBe(200);
  await expect(async () => {
    await student.goto('/messages');
    await expect(student.locator('.messages-container-inbox')).toBeVisible();
    await expect(inbox).not.toContainText(text, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
});
