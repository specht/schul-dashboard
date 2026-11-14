import { test, expect, login, ACCOUNTS, apiLogin, dashboardDialog } from './fixtures';
import { request as playwrightRequest, APIRequestContext } from '@playwright/test';

// Missing mailboxes (src/ruby/include/mail_account_creation.rb): the bot
// uploads the mail provider's address list, the dashboard lists missing
// student and parents' mailboxes – never anything else –, the admin approves
// them on /postfaecher, the bot creates them and reports back.

const TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';
const ADMIN_MAIL = 'mueller@beispielschule.de';
const DOMAIN = 'mail.beispielschule.de';

test.describe.configure({ mode: 'serial' });
test.beforeEach(({}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'shared server state, one project is enough');
});

async function bot(baseURL: string | undefined) {
  return playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${TOKEN}` } });
}
async function admin(baseURL: string | undefined) {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.admin);
  return api;
}
async function status(api: APIRequestContext) {
  return (await api.post('/api/mail_account_creation_status', { data: {} })).json();
}
async function work(api: APIRequestContext) {
  return (await api.get('/api/mail_account_bot/creation')).json();
}
const filler = (n: number) => Array.from({ length: n }, (_, i) => `fueller${i}@andere-domain.example.org`);
async function upload(api: APIRequestContext, addresses: string[]) {
  return api.post('/api/mail_account_bot/address_list', { data: { addresses, types: addresses.map(() => 'Mail Basic') } });
}
async function mails(subject: string) {
  const query = encodeURIComponent(`to:"${ADMIN_MAIL}" subject:"${subject}"`);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  return (messages || []).length as number;
}

test('Fehlende Postfächer: nur Schüler- und Eltern-Postfächer, abgeglichen mit der hochgeladenen Adressliste', async ({ baseURL }) => {
  const a = await admin(baseURL);
  const b = await bot(baseURL);
  const before = await status(a);
  // only student and parents' mailboxes on the student domain
  for (const m of before.missing) {
    expect(m.mailbox.endsWith(`@${DOMAIN}`), m.mailbox).toBe(true);
    expect(['student', 'parents']).toContain(m.kind);
    if (m.kind === 'parents') expect(m.mailbox.startsWith('eltern.')).toBe(true);
  }
  expect(before.missing.some((m: any) => m.mailbox === ACCOUNTS.admin)).toBe(false);
  // the bot uploads the list: Max and his parents exist, the rest is filler
  const max = ACCOUNTS.schueler;
  const res = await upload(b, [max, `eltern.${max}`, '*@verteiler.beispielschule.de', ...filler(100)]);
  expect(res.status()).toBe(200);
  const after = await status(a);
  expect(after.list.source).toBe('ionos');
  expect(after.list.count).toBe(103);
  expect(after.missing.map((m: any) => m.mailbox)).not.toContain(max);
  expect(after.missing.map((m: any) => m.mailbox)).not.toContain(`eltern.${max}`);
  // an implausibly small or broken list is refused
  expect((await upload(b, filler(10))).status()).not.toBe(200);
  expect((await upload(b, [...filler(100), 'kein gültiger eintrag'])).status()).not.toBe(200);
  expect((await status(a)).list.count).toBe(103);
});

test('Fehlende Postfächer: freigeben auf der Seite, der Bot legt an und meldet zurück', async ({ page, baseURL }) => {
  const a = await admin(baseURL);
  const b = await bot(baseURL);
  const before = await status(a);
  const after_count = before.list.count;
  const missing = before.missing;
  const student = missing.find((m: any) => m.kind === 'student');
  const parents = missing.find((m: any) => m.kind === 'parents' && m.mailbox !== `eltern.${student.mailbox}`);
  expect(student && parents).toBeTruthy();

  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  await expect(page.locator('#mail_address_list_state')).toContainText('Adressliste vom Mail-Anbieter');
  for (const m of [student, parents]) {
    await page.locator(`.mail-missing-row[data-mailbox="${m.mailbox}"] .cb_missing`).check();
  }
  await expect(page.locator('#bu_approve_creation')).toHaveText('Anlegen freigeben (2)');
  await page.locator('#bu_approve_creation').click();
  await dashboardDialog(page).getByRole('button', { name: 'Anlegen' }).click();
  await expect(page.locator(`.mail-creation[data-mailbox="${student.mailbox}"]`).first()).toHaveAttribute('data-state', 'approved');
  // no longer offered as missing
  await expect(page.locator(`.mail-missing-row[data-mailbox="${student.mailbox}"]`)).toHaveCount(0);

  // the bot sees them, with kind and the letter's password, and the list is wanted
  const w = await work(b);
  expect(w.address_list.wanted).toBe(true);
  const ours = w.create.filter((c: any) => [student.mailbox, parents.mailbox].includes(c.mailbox));
  expect(ours.map((c: any) => c.kind).sort()).toEqual(['parents', 'student']);
  for (const c of ours) expect(c.password).toMatch(/^[A-Za-z0-9-]{8,}$/);

  // one created, one failed: the admin gets a mail and can retry or give up
  const failuresBefore = await mails('Postfach konnte nicht angelegt werden');
  const done = ours.find((c: any) => c.kind === 'student');
  const failed = ours.find((c: any) => c.kind === 'parents');
  expect((await (await b.post('/api/mail_account_bot/create_result', { data: { id: done.id, ok: true, message: 'angelegt' } })).json()).result).toBe('ok');
  expect((await (await b.post('/api/mail_account_bot/create_result', { data: { id: failed.id, ok: false, message: 'Testfehler' } })).json()).result).toBe('ok');
  await expect.poll(() => mails('Postfach konnte nicht angelegt werden')).toBe(failuresBefore + 1);
  // created: in the stored list right away, no longer offered as missing
  const afterCreate = await status(a);
  expect(afterCreate.missing.map((m: any) => m.mailbox)).not.toContain(student.mailbox);
  expect(afterCreate.list.count).toBe(after_count + 1);
  await page.reload();
  await expect(page.locator(`.mail-creation[data-mailbox="${student.mailbox}"]`).first()).toHaveAttribute('data-state', 'done');
  // newest first (a repeated run on the same test stack leaves older entries)
  const failedRow = page.locator(`.mail-creation[data-mailbox="${parents.mailbox}"]`).first();
  await expect(failedRow).toHaveAttribute('data-state', 'failed');
  await failedRow.locator('.bu_creation_action[data-action="retry"]').click();
  await expect(failedRow).toHaveAttribute('data-state', 'approved');
  // a fresh list that already has it: done as "existed"
  await upload(b, [ACCOUNTS.schueler, `eltern.${ACCOUNTS.schueler}`, parents.mailbox, student.mailbox, ...filler(100)]);
  await page.reload();
  await expect(failedRow).toHaveAttribute('data-state', 'exists');
});

test('Fehlende Postfächer: nichts anderes freigeben, Abgleich anfordern', async ({ page, baseURL }) => {
  const a = await admin(baseURL);
  const b = await bot(baseURL);
  // a teacher, an unknown address, an existing mailbox: refused
  for (const mailbox of [ACCOUNTS.admin, `fremd@${DOMAIN}`, ACCOUNTS.schueler]) {
    const res = await a.post('/api/approve_mail_account_creation', { data: { mailboxes: [mailbox] } });
    expect(res.ok(), mailbox).toBe(false);
  }
  // only the admin
  const student = await playwrightRequest.newContext({ baseURL });
  await apiLogin(student, ACCOUNTS.schueler);
  expect((await student.post('/api/mail_account_creation_status', { data: {} })).ok()).toBe(false);
  // and only with the token
  const anonymous = await playwrightRequest.newContext({ baseURL });
  expect((await anonymous.get('/api/mail_account_bot/creation')).status()).toBe(401);

  // asking for a fresh list
  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  await page.locator('#bu_request_address_list').click();
  await expect(page.locator('#mail_address_list_state')).toContainText('angefordert');
  expect((await work(b)).address_list.wanted).toBe(true);
});
