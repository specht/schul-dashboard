import { test, expect, login, typeEmail, clearLoginMails, waitForMailedCode, ACCOUNTS } from './fixtures';
import { fakeSmsGateway, codeIn, addTelephoneNumber } from './sms-helpers';

// Moving teachers from SMS codes to a code app (OTP): /otp explains it, the
// login page suggests it while someone waits for an SMS or when the SMS
// gateway is offline, the start page reminds those who still use SMS.
// The SMS teachers come from test/e2e/seed.cypher (SMS preferred, no code
// app, no first-login grace period) – one per project, because "Später"
// is stored for 30 days.

const smsTeacher = (project: string) =>
  project === 'mobile' ? 'sms.zwei@beispielschule.de' : 'sms.eins@beispielschule.de';

test('Authenticator-App: Erklärseite ohne Anmeldung, mit Apps und Einrichtung', async ({ page }, testInfo) => {
  await page.goto('/otp');
  await expect(page.getByRole('heading', { name: 'Anmelden mit einer Authenticator-App' })).toBeVisible();
  await expect(page.locator('body')).toContainText('Dabei wird nichts übertragen.');
  await expect(page.locator('body')).toContainText('RFC 6238');
  const apps = page.locator('.otp-app');
  await expect(apps).toHaveCount(4);
  await expect(apps.first().locator('a[href^="https://play.google.com/"]')).toHaveCount(1);
  await expect(apps.first().locator('a[href^="https://apps.apple.com/"]')).toHaveCount(1);
  // QR codes for the store links on larger screens, buttons only on phones
  const qr = page.locator('.otp-app-qr svg').first();
  if (testInfo.project.name === 'mobile') await expect(qr).toBeHidden();
  else await expect(qr).toBeVisible();
  // the setup link only for people who are logged in
  await expect(page.locator('#bu_otp_setup')).toBeHidden();
  // how many teachers use a code app is internal: not on the public page
  await expect(page.locator('.otp-stats')).toHaveCount(0);
  expect(await page.content()).not.toMatch(/von \d+ Lehrkräften/);
  await login(page, ACCOUNTS.teacher);
  await page.goto('/otp');
  await expect(page.locator('#bu_otp_setup')).toBeVisible();
  await expect(page.locator('.otp-stats')).toContainText(/Schon \d+ von \d+ Lehrkräften/);
});

test('Authenticator-App: Hinweis beim Warten auf die SMS und auf der Startseite', async ({ page, baseURL }, testInfo) => {
  const person = smsTeacher(testInfo.project.name);
  const gateway = await fakeSmsGateway(baseURL!);
  try {
    await clearLoginMails(person);
    await page.goto('/');
    // the gateway answers: no notice on the login page
    await expect(page.locator('#sms_gateway_notice')).toBeHidden();
    await typeEmail(page, person);
    await page.locator('#submit').click();
    await page.waitForURL(/\/c\//);
    // not at once: only once the SMS keeps you waiting
    const hint = page.locator('#login_hint');
    await expect(hint).toBeHidden();
    await expect(hint).toBeVisible({ timeout: 8_000 });
    await expect(hint).toContainText('Warten auf die SMS?');
    // not logged in yet: no internal numbers
    await expect(hint).not.toContainText(/von \d+ Lehrkräften/);
    await expect(hint.locator('a[href="/otp"]')).toBeVisible();

    await page.locator('#code').fill(codeIn(await gateway.next()));
    await page.locator('#submit').click();
    // second factor by e-mail: nothing to wait for by SMS any more
    await expect(page.locator('#span_sent')).toContainText('E-Mail');
    await expect(hint).toBeHidden();
    await page.locator('#code2').fill(await waitForMailedCode(person));
    await page.locator('#submit2').click();
    await page.waitForURL((url) => !url.pathname.startsWith('/c/'));

    // start page: a reminder that can wait
    const panel = page.locator('.otp-nudge-panel');
    await expect(panel).toContainText('Anmelden ohne SMS');
    await expect(panel).toContainText(/Schon \d+ von \d+ Lehrkräften/);
    await expect(panel.locator('a[href="/profil#anmeldung"]')).toBeVisible();
    await expect(panel.locator('a[href="/otp"]')).toBeVisible();
    await panel.locator('.bu-otp-nudge-snooze').click();
    await expect(panel).toHaveCount(0);
    await page.reload();
    await expect(page.locator('#start_page_panels')).toBeAttached();
    await expect(panel).toHaveCount(0);
  } finally {
    gateway.close();
  }
});

// The gateway is offline (no gateway connected): the code comes by e-mail,
// and a second factor by SMS is impossible – say so instead of "no second
// factor".
test('Authenticator-App: Hinweis, wenn der SMS-Versand nicht erreichbar ist', async ({ page }, testInfo) => {
  const person = smsTeacher(testInfo.project.name);
  await clearLoginMails(person);
  // the login page says so (test stack: after 2 seconds without a gateway,
  // production: 2 minutes, so a restart doesn't show it)
  const notice = page.locator('#sms_gateway_notice');
  await expect.poll(async () => { await page.goto('/'); return notice.isVisible(); }, { timeout: 15_000 }).toBe(true);
  await expect(notice).toContainText('Der SMS-Versand ist gerade gestört.');
  await expect(notice.locator('a[href="/otp"]')).toBeVisible();
  await typeEmail(page, person);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await expect(page.locator('body')).toContainText('Code per E-Mail');
  const hint = page.locator('#login_hint');
  await expect(hint).toContainText('Der SMS-Versand ist gerade nicht erreichbar');
  await expect(hint).toContainText('diesmal per E-Mail');
  await expect(hint).not.toContainText(/von \d+ Lehrkräften/);

  await page.locator('#code').fill(await waitForMailedCode(person));
  await page.locator('#submit').click();
  await expect(page.locator('#div_forced_2fa')).toBeVisible();
  await expect(hint).toContainText('keinen zweiten Code schicken');
  await expect(hint).not.toContainText(/von \d+ Lehrkräften/);
  await expect(hint.locator('a[href="/otp"]')).toBeVisible();
  await expect(page.locator('#div_forced_2fa')).not.toContainText('keinen zweiten Faktor hinterlegt');
});

// A code app and still SMS as default: one click switches to e-mail first,
// code app second.
test('Authenticator-App: wer sie hat, aber SMS bevorzugt, kann umstellen', async ({ page, baseURL }) => {
  const gateway = await fakeSmsGateway(baseURL!);
  await login(page, ACCOUNTS.teacher);
  try {
    await addTelephoneNumber(page, gateway);
    expect((await page.request.post('/api/set_preferred_login_method', { data: { method: 'sms' } })).status()).toBe(200);
    await page.goto('/');
    const panel = page.locator('.otp-nudge-panel');
    await expect(panel).toContainText('Deine Authenticator-App kann mehr');
    await panel.locator('.bu-otp-nudge-switch').click();
    await expect(panel).toContainText('Umgestellt');
    await page.reload();
    await expect(page.locator('#start_page_panels')).toBeAttached();
    await expect(panel).toHaveCount(0);
    await page.goto('/profil');
    await expect(page.locator('#bu_prefer_email')).toHaveClass(/(^|\s)btn-success(\s|$)/);
  } finally {
    await page.request.post('/api/delete_telephone_number', { data: {} });
    await page.request.post('/api/set_preferred_login_method', { data: { method: 'email' } });
    gateway.close();
  }
});
