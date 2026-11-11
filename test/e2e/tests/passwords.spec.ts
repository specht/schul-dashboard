import { test, expect, login, apiLogin, dashboardDialog, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, type APIRequestContext, type TestInfo } from '@playwright/test';

// Resetting school mailbox passwords on /passwoerter
// (include/mail_password_reset.rb): students request it for their own
// mailbox, the Klassenleitung for the students of their class; every request
// is a case the admin approves or rejects. The admin also enters requests that
// came in by mail (also parents' mailboxes) and answers them with the
// E-Mail-Brief attached. A bot does the actual change at the mail provider
// and reports back – played here through the bot interface with the token of
// the test credentials.
//
// Test students (test/prepare_example_data.rb): the Postfachtest students of
// class 11; desktop and mobile each use their own three. Torsta Torstensonin
// leads class 11 and is no admin. Requests are limited per mailbox and day,
// so the tests expect a fresh test stack (./test.sh up).

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';
const BOT_TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const KLASSENLEITUNG = 'torstensonin@beispielschule.de';
const FIRST_NAMES = ['Anna', 'Ben', 'Cem', 'Dana', 'Emil', 'Fiona'];
const PAGE = '/passwoerter';

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
  return api.post('/api/request_mail_password_reset', { data: { mailbox } });
}

type Case = { id: string; state: string; mailboxes: { mailbox: string; latest: boolean; password?: string }[]; message?: string };

async function cases(api: APIRequestContext): Promise<Case[]> {
  return (await (await api.post('/api/mail_password_reset_status', { data: {} })).json()).cases;
}

async function latestCase(api: APIRequestContext, mailbox: string) {
  return (await cases(api)).find((c) => c.mailboxes.some((m) => m.mailbox === mailbox && m.latest));
}

async function decide(admin: APIRequestContext, id: string, decision: 'approve' | 'reject') {
  const response = await admin.post('/api/decide_mail_password_case', { data: { id, decision } });
  expect((await response.json()).result).toBe('ok');
}

// the bot: fetch approved cases, report the result for the case of one mailbox
async function bot(baseURL: string | undefined, token = BOT_TOKEN) {
  return playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${token}` } });
}

async function botCases(baseURL: string | undefined, mailbox: string) {
  const api = await bot(baseURL);
  const pending = await api.get('/api/mail_password_reset_bot/pending');
  expect(pending.status()).toBe(200);
  const all: { id: string; mailboxes: { mailbox: string; password: string }[] }[] = (await pending.json()).cases;
  return { api, open: all.filter((c) => c.mailboxes.some((m) => m.mailbox === mailbox)) };
}

async function botFinishes(baseURL: string | undefined, mailbox: string, ok: boolean, message = '') {
  const { api, open } = await botCases(baseURL, mailbox);
  expect(open, `exactly one approved case for ${mailbox}`).toHaveLength(1);
  const password = open[0].mailboxes.find((m) => m.mailbox === mailbox)!.password;
  expect(password).toMatch(/^[A-Za-z0-9-]{8,}$/);
  const result = await api.post('/api/mail_password_reset_bot/result', { data: { id: open[0].id, ok, message } });
  expect(result.status()).toBe(200);
  expect((await result.json()).result).toBe('ok');
  return password;
}

type MailSummary = { ID: string; Subject: string };

async function mails(to: string, subject: string) {
  const query = encodeURIComponent(`to:"${to}" subject:"${subject}"`);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  return (messages || []) as MailSummary[];
}

const PARENT_NOTICE = 'Passwort des schulischen E-Mail-Postfachs Ihres Kindes zurückgesetzt';
// WEBSITE_MAINTAINER_EMAIL of credentials.template.rb
const ADMIN_MAIL = 'mueller@beispielschule.de';
const APPROVAL_NOTICE = 'bitte freigeben';
const FAILURE_NOTICE = 'E-Mail-Passwort konnte nicht zurückgesetzt werden';
const REPLY_SUBJECT = 'Passwort für das schulische E-Mail-Postfach zurückgesetzt';

test('Schüler:in beantragt das Zurücksetzen, die Administration gibt frei, die Eltern bekommen Bescheid', async ({ page, browser, baseURL }, testInfo) => {
  const [student] = students(testInfo);
  const approvalsBefore = (await mails(ADMIN_MAIL, APPROVAL_NOTICE)).length;
  await login(page, student.email);
  await page.goto(PAGE);
  const row = page.locator(`.mail-reset-row[data-mailbox="${student.email}"]`);
  await expect(row).toBeVisible();
  // only the own mailbox
  await expect(page.locator('.mail-reset-row')).toHaveCount(1);
  // fully on screen once scrolled to (no horizontal overflow on phones)
  await row.locator('.bu_request_mail_reset').scrollIntoViewIfNeeded();
  await expect(row.locator('.bu_request_mail_reset')).toBeInViewport({ ratio: 1 });

  await row.locator('.bu_request_mail_reset').click();
  const dialog = dashboardDialog(page);
  await expect(dialog).toContainText('Deine Eltern bekommen eine kurze Nachricht');
  await dialog.getByRole('button', { name: 'Beantragen' }).click();
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'open');
  await expect(row.locator('.bu_request_mail_reset')).toBeDisabled();
  await expect.poll(async () => (await mails(ADMIN_MAIL, APPROVAL_NOTICE)).length).toBe(approvalsBefore + 1);
  // nothing happens before the admin decides
  expect((await botCases(baseURL, student.email)).open).toHaveLength(0);

  // the admin approves on the page
  const adminContext = await browser.newContext();
  const adminPage = await adminContext.newPage();
  await login(adminPage, ACCOUNTS.admin);
  await adminPage.goto(PAGE);
  const caseRow = adminPage.locator('#mail_cases tr.mail-case').filter({ hasText: student.email }).first();
  await expect(caseRow).toHaveAttribute('data-state', 'open');
  await expect(caseRow).toContainText('Dashboard');
  await caseRow.locator('.bu_mail_case_approve').click();
  await expect(caseRow).toHaveAttribute('data-state', 'approved');
  await adminContext.close();

  const password = await botFinishes(baseURL, student.email, true);
  await page.reload();
  await expect(row.locator('.mail-reset-state-label')).toHaveAttribute('data-state', 'done');
  await row.locator('.bu_show_mail_password').click();
  await expect(row.locator('.mail-reset-password')).toHaveText(password);
  await row.locator('.bu_request_mail_reset').scrollIntoViewIfNeeded();
  await expect(row.locator('.bu_request_mail_reset')).toBeInViewport({ ratio: 1 });

  await expect.poll(async () => (await mails(`eltern.${student.email}`, PARENT_NOTICE)).length).toBe(1);
});

test('Klassenleitung beantragt; Ablehnen, Fehler des Bots landen bei der Administration', async ({ baseURL }, testInfo) => {
  const [, student] = students(testInfo);
  const kl = await apiAs(KLASSENLEITUNG, baseURL);
  const admin = await apiAs(ACCOUNTS.admin, baseURL);

  expect((await (await requestReset(kl, student.email)).json()).result).toBe('requested');
  // a second request while the first one is open
  expect((await (await requestReset(kl, student.email)).json()).result).toBe('pending');
  // rejected: nothing changes
  await decide(admin, (await latestCase(admin, student.email))!.id, 'reject');
  let latest = (await latestCase(kl, student.email))!;
  expect(latest.state).toBe('rejected');
  expect((await botCases(baseURL, student.email)).open).toHaveLength(0);

  const failuresBefore = (await mails(ADMIN_MAIL, FAILURE_NOTICE)).length;
  expect((await (await requestReset(kl, student.email)).json()).result).toBe('requested');
  await decide(admin, (await latestCase(admin, student.email))!.id, 'approve');
  await botFinishes(baseURL, student.email, false, 'Testfehler');
  await expect.poll(async () => (await mails(ADMIN_MAIL, FAILURE_NOTICE)).length).toBe(failuresBefore + 1);
  latest = (await latestCase(kl, student.email))!;
  expect(latest.state).toBe('failed');
  expect(latest.mailboxes[0].password).toBeUndefined();
  // the bot's message is for the admin only
  expect(latest.message).toBeUndefined();

  expect((await (await requestReset(kl, student.email)).json()).result).toBe('requested');
  await decide(admin, (await latestCase(admin, student.email))!.id, 'approve');
  const password = await botFinishes(baseURL, student.email, true);
  latest = (await latestCase(kl, student.email))!;
  expect(latest.state).toBe('done');
  expect(latest.mailboxes[0].password).toBe(password);

  // requested by the Klassenleitung: no notice to the parents
  expect(await mails(`eltern.${student.email}`, PARENT_NOTICE)).toHaveLength(0);
});

test('Administration: Anfrage per E-Mail eintragen, von Hand erledigen, mit E-Mail-Brief antworten', async ({ page, baseURL }, testInfo) => {
  const [a] = students(testInfo);
  const parents = `eltern.${a.email}`;
  const family = `familie.${testInfo.project.name}@example.org`;
  const noticesBefore = (await mails(parents, PARENT_NOTICE)).length;
  await login(page, ACCOUNTS.admin);
  await page.goto(PAGE);
  await expect(page.locator('#mail_reset_bot_state')).toContainText('Bot zuletzt aktiv');

  await page.locator('#ti_mail_case_mailbox').fill(parents);
  await page.locator('#bu_add_mail_case_mailbox').click();
  await page.locator('#ti_mail_case_mailbox').fill(a.email);
  await page.locator('#bu_add_mail_case_mailbox').click();
  await expect(page.locator('#mail_case_mailboxes .mail-case-mailbox')).toHaveCount(2);
  await page.locator('#ti_mail_case_reply_to').fill(family);
  await page.locator('#ti_mail_case_note').fill('Mail vom Vater');
  await page.locator('#bu_create_mail_case').click();
  await dashboardDialog(page).getByRole('button', { name: 'Freigeben' }).click();

  const row = page.locator('#mail_cases tr.mail-case').filter({ hasText: family }).first();
  await expect(row).toHaveAttribute('data-state', 'approved');
  await expect(row).toContainText('Eltern von');
  await expect(row).toContainText('Mail vom Vater');
  // what the mailboxes get (passed on with the E-Mail-Brief)
  const { open } = await botCases(baseURL, parents);
  expect(open).toHaveLength(1);
  expect(open[0].mailboxes.map((m) => m.mailbox).sort()).toEqual([a.email, parents].sort());
  const parentsPassword = open[0].mailboxes.find((m) => m.mailbox === parents)!.password;

  await row.locator('.bu_mail_case_done').click();
  await expect(row).toHaveAttribute('data-state', 'done');
  await row.locator(`.mail-case-mailbox-entry[data-mailbox="${parents}"] .bu_show_mail_password`).click();
  await expect(row.locator(`.mail-case-mailbox-entry[data-mailbox="${parents}"] .mail-reset-password`)).toHaveText(parentsPassword);

  await row.locator('.bu_mail_case_reply').click();
  const modal = page.locator('#mailCaseReplyModal');
  await expect(modal).toBeVisible();
  await expect(modal.locator('#ti_reply_to')).toHaveValue(family);
  await expect(modal.locator('#ta_reply_body')).toHaveValue(/^Sehr geehrte Frau \/ Herr/);
  await expect(modal.locator('#ta_reply_body')).toHaveValue(new RegExp(`für das Postfach und das Eltern-Postfach von ${a.name} zurückgesetzt und sende Ihnen die Zugangsdaten im Anhang`));
  await expect(modal.locator('#ta_reply_body')).toHaveValue(/Viele Grüße\n/);
  await expect(modal.locator('#reply_attachment')).toContainText(a.name);
  await modal.locator('#ta_reply_body').fill(`Sehr geehrter Herr Postfachtest,\n\nanbei die Zugangsdaten.\n\nViele Grüße`);
  await modal.locator('#bu_send_mail_case_reply').click();
  await expect(modal).toBeHidden();
  await expect(row.locator('.mail-case-replied')).toContainText(family);

  await expect.poll(async () => (await mails(family, REPLY_SUBJECT)).length).toBe(1);
  const [summary] = await mails(family, REPLY_SUBJECT);
  const message = await (await fetch(`${MAILPIT_URL}/api/v1/message/${summary.ID}`)).json();
  expect(message.Text).toContain('Sehr geehrter Herr Postfachtest');
  expect(message.ReplyTo.map((x: { Address: string }) => x.Address)).toEqual([ACCOUNTS.admin]);
  expect(message.Bcc.map((x: { Address: string }) => x.Address)).toEqual([ACCOUNTS.admin]);
  expect(message.Attachments).toHaveLength(1);
  expect(message.Attachments[0].ContentType).toBe('application/pdf');
  expect(message.Attachments[0].FileName).toContain(a.name);

  // entered by the admin: no notice to the parents
  expect((await mails(parents, PARENT_NOTICE)).length).toBe(noticesBefore);
});

test('Wer darf was: fremde Postfächer, Eltern-Postfächer, Freigabe, Grenzen, Bot ohne Token', async ({ baseURL }, testInfo) => {
  const [a, , c] = students(testInfo);
  const studentApi = await apiAs(c.email, baseURL);
  const kl = await apiAs(KLASSENLEITUNG, baseURL);
  const teacher = await apiAs(ACCOUNTS.teacher, baseURL);
  const admin = await apiAs(ACCOUNTS.admin, baseURL);

  // students: only their own mailbox, not their parents' one
  expect((await requestReset(studentApi, a.email)).ok()).toBe(false);
  expect((await requestReset(studentApi, `eltern.${c.email}`)).ok()).toBe(false);
  // Klassenleitung: students of their class only, no parents' mailboxes
  expect((await requestReset(kl, ACCOUNTS.schueler)).ok()).toBe(false);
  expect((await requestReset(kl, `eltern.${c.email}`)).ok()).toBe(false);
  // other teachers: nothing
  expect((await requestReset(teacher, c.email)).ok()).toBe(false);
  // nobody sees requests they may not make
  expect(await cases(teacher)).toEqual([]);
  // deciding, entering mail requests and answering: only the admin
  for (const api of [studentApi, kl]) {
    expect((await api.post('/api/create_mail_password_case', { data: { mailboxes: [c.email] } })).ok()).toBe(false);
    expect((await api.post('/api/decide_mail_password_case', { data: { id: 'x', decision: 'approve' } })).ok()).toBe(false);
    expect((await api.post('/api/send_mail_password_case_reply', { data: { id: 'x', to: 'a@example.org', subject: 's', body: 'b' } })).ok()).toBe(false);
  }

  // a few resets per mailbox and day, then no more
  const results: string[] = [];
  for (let i = 0; i < 4; i++) {
    const result = (await (await requestReset(studentApi, c.email)).json()).result;
    results.push(result);
    if (result === 'limit') break;
    expect(result).toBe('requested');
    await decide(admin, (await latestCase(admin, c.email))!.id, 'approve');
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

test('Alte Adressen führen zur Seite Passwörter', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  for (const old of ['/login_nc', '/mail_passwort']) {
    await page.goto(old);
    await expect(page).toHaveURL(/\/passwoerter$/);
  }
  // Nextcloud and the own mailbox on one page
  await expect(page.locator('#ti_nc_login')).toBeVisible();
  await expect(page.locator(`.mail-reset-row[data-mailbox="${ACCOUNTS.schueler_oberstufe}"]`)).toBeVisible();
});
