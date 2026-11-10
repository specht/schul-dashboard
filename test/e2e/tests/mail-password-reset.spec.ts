import { test, expect, login, apiLogin, dashboardDialog, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, type APIRequestContext, type TestInfo } from '@playwright/test';

// Resetting a school mailbox password (include/mail_password_reset.rb):
// students request it for their own mailbox, the Klassenleitung for the
// students of their class, the admin also for parents' mailboxes. A bot
// does the actual change at the mail provider and reports back – played
// here through the bot interface with the token of the test credentials.
//
// Test students (test/prepare_example_data.rb): the Postfachtest students of
// class 11; desktop and mobile each use their own three. Torsta Torstensonin
// leads class 11 and is no admin. Requests are limited per mailbox and day,
// so the tests expect a fresh test stack (./test.sh up).

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';
const BOT_TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const KLASSENLEITUNG = 'torstensonin@beispielschule.de';
const FIRST_NAMES = ['Anna', 'Ben', 'Cem', 'Dana', 'Emil', 'Fiona'];

function students(testInfo: TestInfo) {
  const offset = testInfo.project.name === 'mobile' ? 3 : 0;
  return FIRST_NAMES.slice(offset, offset + 3).map((first) => ({
    name: `${first} Postfachtest`,
    email: `${first.toLowerCase()}.postfachtest@mail.beispielschule.de`,
  }));
}

async function apiAs(email: string, baseURL: string | undefined) {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, email);
  return api;
}

async function requestReset(api: APIRequestContext, mailbox: string) {
  const response = await api.post('/api/request_mail_password_reset', { data: { mailbox } });
  return response;
}

// the bot: fetch open requests, report the result for one mailbox
async function bot(baseURL: string | undefined, token = BOT_TOKEN) {
  return playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${token}` } });
}

async function botFinishes(baseURL: string | undefined, mailbox: string, ok: boolean, message = '') {
  const api = await bot(baseURL);
  const pending = await api.get('/api/mail_password_reset_bot/pending');
  expect(pending.status()).toBe(200);
  const { requests } = await pending.json();
  const open = requests.filter((r: { mailbox: string }) => r.mailbox === mailbox);
  expect(open, `exactly one open request for ${mailbox}`).toHaveLength(1);
  expect(open[0].password).toMatch(/^[A-Za-z0-9-]{8,}$/);
  const result = await api.post('/api/mail_password_reset_bot/result', { data: { id: open[0].id, ok, message } });
  expect(result.status()).toBe(200);
  expect((await result.json()).result).toBe('ok');
  return open[0].password as string;
}

async function mails(to: string, subject: string) {
  const query = encodeURIComponent(`to:"${to}" subject:"${subject}"`);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  return (messages || []) as { Subject: string }[];
}

const PARENT_NOTICE = 'Passwort des schulischen E-Mail-Postfachs Ihres Kindes zurückgesetzt';
// WEBSITE_MAINTAINER_EMAIL of credentials.template.rb
const ADMIN_MAIL = 'mueller@beispielschule.de';
const FAILURE_NOTICE = 'E-Mail-Passwort konnte nicht zurückgesetzt werden';

test('Schüler:in setzt das eigene E-Mail-Passwort zurück, die Eltern bekommen Bescheid', async ({ page, baseURL }, testInfo) => {
  const [student] = students(testInfo);
  await login(page, student.email);
  await page.goto('/mail_passwort');
  const row = page.locator(`.mail-reset-row[data-mailbox="${student.email}"]`);
  await expect(row).toBeVisible();
  // only the own mailbox
  await expect(page.locator('.mail-reset-row')).toHaveCount(1);
  // fully on screen, also on phones
  await expect(row.locator('.bu_request_mail_reset')).toBeInViewport({ ratio: 1 });

  await row.locator('.bu_request_mail_reset').click();
  const dialog = dashboardDialog(page);
  await expect(dialog).toContainText('Deine Eltern bekommen eine kurze Nachricht');
  await dialog.getByRole('button', { name: 'Zurücksetzen' }).click();
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'pending');
  await expect(row.locator('.bu_request_mail_reset')).toBeDisabled();

  const password = await botFinishes(baseURL, student.email, true);
  await page.reload();
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'done');
  await row.locator('.bu_show_mail_password').click();
  await expect(row.locator('.mail-reset-password')).toHaveText(password);
  await expect(row.locator('.bu_request_mail_reset')).toBeInViewport({ ratio: 1 });

  await expect.poll(async () => (await mails(`eltern.${student.email}`, PARENT_NOTICE)).length).toBe(1);
});

test('Klassenleitung setzt ein Passwort zurück; Fehler des Bots landen bei der Administration', async ({ baseURL }, testInfo) => {
  const [, student] = students(testInfo);
  const kl = await apiAs(KLASSENLEITUNG, baseURL);

  const failuresBefore = (await mails(ADMIN_MAIL, FAILURE_NOTICE)).length;
  expect((await (await requestReset(kl, student.email)).json()).result).toBe('requested');
  // a second request while the first one is open
  expect((await (await requestReset(kl, student.email)).json()).result).toBe('pending');

  await botFinishes(baseURL, student.email, false, 'Testfehler');
  await expect.poll(async () => (await mails(ADMIN_MAIL, FAILURE_NOTICE)).length).toBe(failuresBefore + 1);
  let status = await (await kl.post('/api/mail_password_reset_status', { data: {} })).json();
  let latest = status.requests.find((r: { mailbox: string; latest: boolean }) => r.mailbox === student.email && r.latest);
  expect(latest.state).toBe('failed');
  expect(latest.password).toBeUndefined();
  // the bot's message is for the admin only
  expect(latest.message).toBeUndefined();

  expect((await (await requestReset(kl, student.email)).json()).result).toBe('requested');
  const password = await botFinishes(baseURL, student.email, true);
  status = await (await kl.post('/api/mail_password_reset_status', { data: {} })).json();
  latest = status.requests.find((r: { mailbox: string; latest: boolean }) => r.mailbox === student.email && r.latest);
  expect(latest.state).toBe('done');
  expect(latest.password).toBe(password);

  // requested by the Klassenleitung: no notice to the parents
  expect(await mails(`eltern.${student.email}`, PARENT_NOTICE)).toHaveLength(0);
});

test('Wer darf was: fremde Postfächer, Eltern-Postfächer, Grenzen, Bot ohne Token', async ({ baseURL }, testInfo) => {
  const [a, , c] = students(testInfo);
  const studentApi = await apiAs(c.email, baseURL);
  const kl = await apiAs(KLASSENLEITUNG, baseURL);
  const teacher = await apiAs(ACCOUNTS.teacher, baseURL);

  // students: only their own mailbox, not their parents' one
  expect((await requestReset(studentApi, a.email)).ok()).toBe(false);
  expect((await requestReset(studentApi, `eltern.${c.email}`)).ok()).toBe(false);
  // Klassenleitung: students of their class only, no parents' mailboxes
  expect((await requestReset(kl, ACCOUNTS.schueler)).ok()).toBe(false);
  expect((await requestReset(kl, `eltern.${c.email}`)).ok()).toBe(false);
  // other teachers: nothing
  expect((await requestReset(teacher, c.email)).ok()).toBe(false);
  // nobody sees requests they may not make
  const others = await (await teacher.post('/api/mail_password_reset_status', { data: {} })).json();
  expect(others.requests).toEqual([]);

  // a few resets per mailbox and day, then no more
  const results: string[] = [];
  for (let i = 0; i < 4; i++) {
    const result = (await (await requestReset(studentApi, c.email)).json()).result;
    results.push(result);
    if (result === 'limit') break;
    expect(result).toBe('requested');
    await botFinishes(baseURL, c.email, true);
  }
  expect(results).toEqual(['requested', 'requested', 'requested', 'limit']);

  // the bot interface wants the token
  const noToken = await playwrightRequest.newContext({ baseURL });
  expect((await noToken.get('/api/mail_password_reset_bot/pending')).status()).toBe(401);
  const wrongToken = await bot(baseURL, 'x'.repeat(BOT_TOKEN.length));
  expect((await wrongToken.get('/api/mail_password_reset_bot/pending')).status()).toBe(401);
  expect((await wrongToken.post('/api/mail_password_reset_bot/result', { data: { id: 'x', ok: true } })).status()).toBe(401);
});

test('Administration: Eltern-Postfach zurücksetzen und von Hand als erledigt markieren', async ({ page }, testInfo) => {
  const [a] = students(testInfo);
  const parents = `eltern.${a.email}`;
  const noticesBefore = (await mails(parents, PARENT_NOTICE)).length;
  await login(page, ACCOUNTS.admin);
  await page.goto('/mail_passwort');
  await expect(page.locator('#mail_reset_bot_state')).toContainText('Bot zuletzt aktiv');

  await page.locator('#ti_mail_reset_mailbox').fill(parents);
  await page.locator('#bu_request_mail_reset_mailbox').click();
  await dashboardDialog(page).getByRole('button', { name: 'Zurücksetzen' }).click();

  const row = page.locator('#mail_reset_requests tbody tr').filter({ hasText: parents }).first();
  await expect(row).toContainText('Eltern von');
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'pending');
  await row.locator('.bu_mail_reset_done').click();
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'done');
  // requested by the admin: no notice (only students' own requests send one)
  expect((await mails(parents, PARENT_NOTICE)).length).toBe(noticesBefore);
});
