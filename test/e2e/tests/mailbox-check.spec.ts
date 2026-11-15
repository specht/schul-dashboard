import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, Page } from '@playwright/test';

// Checking one mailbox on /postfaecher (src/ruby/include/mailbox_check.rb):
// the provider's address list, an IMAP login with the original password and
// an overview without content, then a reply to the person who asked. The IMAP
// server is the stand-in of the test stack (src/ruby/test/fake_imap.ru), which
// only accepts the original password from the E-Mail-Brief.

const TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';
const IMAP_URL = process.env.IMAP_URL || 'http://localhost:8128';
const MAX = ACCOUNTS.schueler; // 5a
const ALICE = ACCOUNTS.schueler_oberstufe; // 11

const daysAgo = (n: number) => new Date(Date.now() - n * 24 * 3600 * 1000).toISOString();
const filler = (n: number) => Array.from({ length: n }, (_, i) => `fueller${i}@andere-domain.example.org`);

type Folder = { name: string; dates: string[] };
async function fakeMailbox(user: string, accept: 'original' | 'never', folders: Folder[] = [], quota: object | null = null) {
  const r = await fetch(`${IMAP_URL}/_mailbox`, { method: 'POST', body: JSON.stringify({ user, accept, folders, quota }) });
  expect(r.status).toBe(200);
}
async function imapLog(): Promise<{ user: string; command: string; args: string[] }[]> {
  return (await fetch(`${IMAP_URL}/_log`)).json();
}

test.beforeEach(async ({ baseURL }) => {
  await fetch(`${IMAP_URL}/_mailboxes`, { method: 'DELETE' });
  // the provider's list: Max has a mailbox, Alice only a forwarding, Max's
  // parents nothing
  const bot = await playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });
  const addresses = [MAX, ALICE, ...filler(100)];
  const types = addresses.map((a) => (a === ALICE ? 'Weiterleitung' : 'Mail Basic'));
  expect((await bot.post('/api/mail_account_bot/address_list', { data: { addresses, types } })).status()).toBe(200);
});

async function openCheck(page: Page, search: string, name: string) {
  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  await page.locator('#ti_letter_search').fill(search);
  await page.locator('.letter-result', { hasText: name }).locator('.bu_check_mailbox').click();
  const modal = page.locator('#mailboxCheckModal');
  await expect(modal).toBeVisible();
  return modal;
}

test('E-Mails kommen an, werden aber nicht abgerufen: Prüfung ohne Inhalte, Antwort mit Hilfe-Link und E-Mail-Brief', async ({ page }) => {
  await fakeMailbox(MAX, 'original', [
    { name: 'INBOX', dates: [daysAgo(60), daysAgo(5), daysAgo(1)] },
    { name: 'Spam', dates: [daysAgo(40)] },
  ], { used_kb: 512000, limit_kb: 1048576 });
  const modal = await openCheck(page, 'Max Muster', 'Max');

  await expect(modal.locator('[data-key="mail_arrives"]')).toBeVisible();
  await expect(modal.locator('[data-fact="list"]')).toContainText('Postfach (Mail Basic)');
  await expect(modal.locator('[data-fact="login"]')).toHaveText('klappt');
  await expect(modal.locator('[data-fact="quota"]')).toContainText('49 %');
  const inbox = modal.locator('tr[data-folder="INBOX"]');
  await expect(inbox).toContainText('Posteingang');
  await expect(inbox.locator('td').nth(1)).toHaveText('3');
  await expect(inbox.locator('td').nth(2)).toHaveText('2');

  // read-only and without content: never SELECT, nothing fetched but the
  // arrival time of the newest mail
  const log = (await imapLog()).filter((x) => x.user === MAX);
  expect(log.some((x) => x.command === 'LOGIN')).toBe(true);
  for (const entry of log) {
    expect(['CAPABILITY', 'LOGIN', 'LIST', 'STATUS', 'EXAMINE', 'SEARCH', 'FETCH', 'GETQUOTAROOT', 'LOGOUT'], JSON.stringify(entry)).toContain(entry.command);
    if (entry.command === 'FETCH') expect(entry.args.join(' ').replace(/[()]/g, '').toUpperCase()).toBe('* INTERNALDATE');
  }

  // the reply: help page and webmail, the E-Mail-Brief only when ticked
  await modal.locator('#bu_mailbox_check_reply').click();
  const reply = page.locator('#mailCaseReplyModal');
  await expect(reply).toBeVisible();
  await expect(page.locator('#ti_reply_subject')).toHaveValue('Dein schulisches E-Mail-Postfach');
  const body = await page.locator('#ta_reply_body').inputValue();
  expect(body).toContain('Hallo Max,');
  // says how it was checked: automatically, no mail opened
  expect(body).toContain('mit einem automatisierten Verfahren geprüft');
  expect(body).toContain('weder Inhalte noch Betreffzeilen oder Absender');
  expect(body).toContain('/hilfe#email-programm');
  expect(body).toContain('Gmail');
  await expect(page.locator('#reply_check_attachment')).toBeVisible();
  await expect(page.locator('#reply_case_attachment')).toBeHidden();
  const to = `max.privat.${Date.now()}@example.com`;
  await page.locator('#ti_reply_to').fill(to);
  await page.locator('#cb_reply_attach_letter').check();
  const sent = page.waitForResponse('**/api/send_mailbox_check_reply');
  await page.locator('#bu_send_mail_case_reply').click();
  expect((await sent).status()).toBe(200);
  await expect(reply).toBeHidden();

  // the log: who checked when, whether the login worked, the reply – nothing found
  await page.locator('#mailbox_check_log_box summary').click();
  const logRow = page.locator('#mailbox_check_log tbody tr').first();
  await expect(logRow).toContainText(MAX);
  await expect(logRow).toContainText('klappt');
  await expect(logRow).toContainText(`an ${to}`);
  await expect(logRow).toContainText('mit E-Mail-Brief');
  await expect(page.locator('#mailbox_check_log')).not.toContainText('Posteingang');

  let message: any = null;
  await expect(async () => {
    const query = encodeURIComponent(`to:"${to}"`);
    const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
    expect(messages.length).toBe(1);
    message = await (await fetch(`${MAILPIT_URL}/api/v1/message/${messages[0].ID}`)).json();
  }).toPass({ timeout: 15000 });
  expect(message.Subject).toBe('Dein schulisches E-Mail-Postfach');
  expect(message.Text).toContain('/hilfe#email-programm');
  expect(message.Attachments.length).toBe(1);
  expect(message.Attachments[0].FileName).toContain('E-Mail-Brief');
});

test('Nur eine Weiterleitung, fehlendes Eltern-Postfach', async ({ page }) => {
  await fakeMailbox(MAX, 'original', [{ name: 'INBOX', dates: [daysAgo(2)] }]);
  const modal = await openCheck(page, 'Alice', 'Alice');
  await expect(modal.locator('[data-key="forward"]')).toBeVisible();
  await expect(modal.locator('[data-fact="list"]')).toContainText('nur Weiterleitung');
  // no mailbox behind the address: the login fails
  await expect(modal.locator('[data-fact="login"]')).toContainText('abgelehnt');
  await modal.locator('[data-dismiss="modal"]').click();
  await expect(modal).toBeHidden();

  await page.locator('#ti_letter_search').fill('Max Muster');
  await page.locator('.letter-result', { hasText: 'Max' }).locator('.bu_check_mailbox').click();
  await expect(modal.locator('[data-key="mail_arrives"]')).toBeVisible();
  await modal.locator('#bu_check_parents').click();
  await expect(modal.locator('[data-key="missing"]')).toBeVisible();
  await expect(modal.locator('.mailbox-check-head')).toContainText(`eltern.${MAX}`);
  // parents are addressed with "Sie"
  await modal.locator('#bu_mailbox_check_reply').click();
  const parentsBody = await page.locator('#ta_reply_body').inputValue();
  expect(parentsBody).toContain('Sehr geehrte');
  expect(parentsBody).toContain('Dabei wurde keine E-Mail geöffnet');
  await expect(page.locator('#ti_reply_subject')).toHaveValue('Ihr schulisches E-Mail-Postfach');
});

test('Geändertes Passwort: Hinweis auf Webmail, Zurücksetzen über eine Anfrage', async ({ page }) => {
  await fakeMailbox(MAX, 'never');
  const modal = await openCheck(page, 'Max Muster', 'Max');
  await expect(modal.locator('[data-key="password_changed"]')).toBeVisible();
  await expect(modal.locator('.mailbox-check-folders')).toHaveCount(0);
  await modal.locator('#bu_mailbox_check_reset').click();
  await expect(modal).toBeHidden();
  await expect(page.locator('#mail_case_mailboxes')).toContainText(MAX);
});

test('Neue E-Mails nur in einem anderen Ordner oder gar nicht: Filter oder Weiterleitung', async ({ page }) => {
  await fakeMailbox(MAX, 'original', [
    { name: 'INBOX', dates: [daysAgo(70), daysAgo(50)] },
    { name: 'Schule', dates: [daysAgo(3)] },
  ]);
  const modal = await openCheck(page, 'Max Muster', 'Max');
  await expect(modal.locator('[data-key="filter"]')).toContainText('„Schule“');

  await fakeMailbox(MAX, 'original', [{ name: 'INBOX', dates: [daysAgo(70), daysAgo(50)] }], { used_kb: 1000000, limit_kb: 1048576 });
  await modal.locator('#bu_check_student').click();
  await expect(modal.locator('[data-key="nothing_new"]')).toBeVisible();
  await expect(modal.locator('[data-key="full"]')).toContainText('95 %');
});

test('Nur Admins, nur Schüler- und Eltern-Postfächer', async ({ page, baseURL }) => {
  const teacher = await playwrightRequest.newContext({ baseURL });
  await apiLogin(teacher, ACCOUNTS.teacher);
  expect((await teacher.post('/api/check_mailbox', { data: { mailbox: MAX } })).status()).not.toBe(200);

  await login(page, ACCOUNTS.admin);
  for (const mailbox of [ACCOUNTS.admin, 'jemand@example.com', `eltern.${ACCOUNTS.teacher}`]) {
    expect((await page.request.post('/api/check_mailbox', { data: { mailbox } })).status(), mailbox).not.toBe(200);
  }
  expect((await imapLog()).length).toBe(0);
});

test('Fehler bei der Prüfung erscheinen im Dialog, mit „Noch einmal prüfen“', async ({ page }) => {
  await fakeMailbox(MAX, 'original', [{ name: 'INBOX', dates: [daysAgo(1)] }]);
  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  await page.route('**/api/check_mailbox', (route) => route.abort());
  await page.locator('#ti_letter_search').fill('Max Muster');
  await page.locator('.letter-result', { hasText: 'Max' }).locator('.bu_check_mailbox').click();
  const modal = page.locator('#mailboxCheckModal');
  await expect(modal.locator('#mailbox_check_title_name')).toContainText('Max Mustermann (5a)');
  await expect(modal.locator('.mailbox-check-error')).toContainText('nicht geklappt');
  await expect(modal.locator('#bu_mailbox_check_reply')).toBeDisabled();
  await page.unroute('**/api/check_mailbox');
  await modal.getByRole('button', { name: 'Noch einmal prüfen' }).click();
  await expect(modal.locator('[data-key="mail_arrives"]')).toBeVisible();
  await expect(modal.locator('#bu_mailbox_check_reply')).toBeEnabled();
});
