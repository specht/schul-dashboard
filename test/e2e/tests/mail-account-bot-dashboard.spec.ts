import { test, expect, login, ACCOUNTS, apiLogin, dashboardDialog } from './fixtures';
import { request as playwrightRequest, APIRequestContext } from '@playwright/test';
import WebSocket from 'ws';

// The dashboard's side of the IONOS bot, shared by every machine the bot runs
// on: one run at a time (lease), a pause that only the admin lifts, the
// IONOS logins of the day, and the websocket that wakes the bot when the
// admin approves a case (src/ruby/include/mail_password_reset.rb).

const TOKEN = 'test-mail-password-reset-bot-token-0123456789';
const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';
const ADMIN_MAIL = 'mueller@beispielschule.de';

test.describe.configure({ mode: 'serial' });
test.beforeEach(({}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'shared server state, one project is enough');
});

async function bot(baseURL: string | undefined, token = TOKEN) {
  return playwrightRequest.newContext({ baseURL, extraHTTPHeaders: { Authorization: `Bearer ${token}` } });
}

async function post(api: APIRequestContext, path: string, data: object) {
  const response = await api.post(path, { data });
  expect(response.status(), path).toBe(200);
  return response.json();
}

async function mails(subject: string) {
  const query = encodeURIComponent(`to:"${ADMIN_MAIL}" subject:"${subject}"`);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  return (messages || []).length as number;
}

async function resume(baseURL: string | undefined) {
  const admin = await playwrightRequest.newContext({ baseURL });
  await apiLogin(admin, ACCOUNTS.admin);
  expect((await admin.post('/api/resume_mail_account_bot', { data: {} })).status()).toBe(200);
}

test('Bot-Zustand: nur ein Rechner zur Zeit, die Sperre wird freigegeben', async ({ baseURL }) => {
  const api = await bot(baseURL);
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-a' });
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-b' });
  expect((await post(api, '/api/mail_account_bot/claim', { host: 'rechner-a' })).result).toBe('ok');
  // the same machine may renew
  expect((await post(api, '/api/mail_account_bot/claim', { host: 'rechner-a' })).result).toBe('ok');
  expect(await post(api, '/api/mail_account_bot/claim', { host: 'rechner-b' })).toMatchObject({ result: 'busy', host: 'rechner-a' });
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-b' }); // not the holder: no effect
  expect((await post(api, '/api/mail_account_bot/claim', { host: 'rechner-b' })).result).toBe('busy');
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-a' });
  expect((await post(api, '/api/mail_account_bot/claim', { host: 'rechner-b' })).result).toBe('ok');
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-b' });
  // host names are checked
  expect((await api.post('/api/mail_account_bot/claim', { data: { host: '../x y' } })).status()).not.toBe(200);
});

test('Bot-Zustand: höchstens zehn IONOS-Anmeldungen am Tag für alle Rechner, die Administration setzt den Zähler zurück', async ({ page, baseURL }) => {
  const api = await bot(baseURL);
  const attempt = async (i: number) => (await post(api, '/api/mail_account_bot/login_attempt', { host: i % 2 ? 'rechner-a' : 'rechner-b' })).result;
  const results: string[] = [];
  for (let i = 0; i < 12; i++) results.push(await attempt(i));
  // earlier runs today may have used some already
  const oks = results.filter((r) => r === 'ok').length;
  expect(oks).toBeLessThanOrEqual(10);
  expect(results.slice(-2)).toEqual(['limit', 'limit']);
  expect(results.indexOf('limit')).toBe(oks);

  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  await expect(page.locator('#mail_bot_logins')).toContainText('10 von 10');
  await page.locator('#bu_reset_mail_bot_logins').click();
  await dashboardDialog(page).getByRole('button', { name: 'Zurücksetzen' }).click();
  await expect(page.locator('#bu_reset_mail_bot_logins')).toHaveCount(0);
  expect(await attempt(0)).toBe('ok');
});

test('Bot angehalten: keine Fälle, keine Sperre, Mail an die Administration, Freigabe auf der Seite', async ({ page, baseURL }) => {
  const api = await bot(baseURL);
  const before = await mails('Postfach-Bot angehalten');
  // a long reason (as long as the bot sends them, umlauts count twice)
  const reason = 'Testgrund: Captcha – ' + 'Sicherheitsabfrage für Anmeldung ä ö ü '.repeat(15).slice(0, 470);
  await post(api, '/api/mail_account_bot/pause', { host: 'rechner-a', reason });
  // a second pause keeps the first reason and sends no second mail
  await post(api, '/api/mail_account_bot/pause', { host: 'rechner-b', reason: 'zweiter Grund' });
  await expect.poll(() => mails('Postfach-Bot angehalten')).toBe(before + 1);
  const pending = await (await api.get('/api/mail_account_bot/pending')).json();
  expect(pending.cases).toEqual([]);
  expect(pending.paused).toMatchObject({ reason });
  expect(await post(api, '/api/mail_account_bot/claim', { host: 'rechner-a' })).toMatchObject({ result: 'paused' });
  expect((await post(api, '/api/mail_account_bot/login_attempt', { host: 'rechner-a' })).result).toBe('paused');

  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  const state = page.locator('#mail_reset_bot_state');
  await expect(state).toHaveAttribute('data-state', 'paused');
  await expect(state).toContainText('Testgrund: Captcha');
  await expect(state).toContainText('rechner-a');
  await page.locator('#bu_resume_mail_bot').click();
  await dashboardDialog(page).getByRole('button', { name: 'Freigeben' }).click();
  await expect(state).not.toHaveAttribute('data-state', 'paused');
  expect((await (await api.get('/api/mail_account_bot/pending')).json()).paused).toBeNull();
  expect((await post(api, '/api/mail_account_bot/claim', { host: 'rechner-a' })).result).toBe('ok');
  await post(api, '/api/mail_account_bot/release', { host: 'rechner-a' });
});

test('Bot-Websocket: nur mit Token, Weckruf bei Freigabe, Status auf der Seite', async ({ page, baseURL }) => {
  const wsBase = baseURL!.replace(/^http/, 'ws');
  // without the token: refused
  const refused = await new Promise<number>((resolve) => {
    const ws = new WebSocket(`${wsBase}/ws_mail_account_bot?host=rechner-a`);
    ws.on('unexpected-response', (_req, res) => resolve(res.statusCode || 0));
    ws.on('open', () => { ws.close(); resolve(101); });
    ws.on('error', () => resolve(-1));
  });
  expect(refused).toBe(401);

  const messages: string[] = [];
  const ws = new WebSocket(`${wsBase}/ws_mail_account_bot?host=rechner-ws`, { headers: { Authorization: `Bearer ${TOKEN}` } });
  ws.on('message', (data) => messages.push(JSON.parse(String(data)).command));
  await new Promise<void>((resolve, reject) => { ws.on('open', () => resolve()); ws.on('error', reject); });
  await expect.poll(() => messages.length).toBeGreaterThan(0);
  expect(['hello', 'wake']).toContain(messages[0]);

  await login(page, ACCOUNTS.admin);
  await page.goto('/postfaecher');
  const state = page.locator('#mail_reset_bot_state');
  await expect(state).toHaveAttribute('data-state', 'connected');
  await expect(state).toContainText('rechner-ws');

  // the admin approves a case: the bot is woken (and fetches the cases itself)
  const admin = await playwrightRequest.newContext({ baseURL });
  await apiLogin(admin, ACCOUNTS.admin);
  const mailbox = 'max.mustermann@mail.beispielschule.de';
  const created = await (await admin.post('/api/create_mail_password_case', { data: { mailboxes: [mailbox], note: 'Websocket-Test' } })).json();
  const id = created.id || (await (await admin.post('/api/mail_password_reset_status', { data: {} })).json()).cases.find((c: any) => c.state === 'open' && c.mailboxes.some((m: any) => m.mailbox === mailbox)).id;
  const wakesBefore = messages.filter((m) => m === 'wake').length;
  expect((await (await admin.post('/api/update_mail_password_case', { data: { id, action: 'approve' } })).json()).result).toBe('ok');
  await expect.poll(() => messages.filter((m) => m === 'wake').length).toBe(wakesBefore + 1);
  // the case tells the bot what kind of mailbox it is
  const api = await bot(baseURL);
  const pending = (await (await api.get('/api/mail_account_bot/pending')).json()).cases;
  const ours = pending.find((c: any) => c.id === id);
  expect(ours.mailboxes).toEqual([{ mailbox, kind: 'student', password: expect.stringMatching(/^[A-Za-z0-9-]{8,}$/) }]);
  // clean up: the admin marks it done by hand
  expect((await (await admin.post('/api/update_mail_password_case', { data: { id, action: 'done' } })).json()).result).toBe('ok');

  ws.close();
  await page.reload();
  await expect(state).not.toHaveAttribute('data-state', 'connected');
});

test('Bot im Hintergrund: läuft an, wenn die Administration freigibt', async ({ baseURL }) => {
  const { serve } = require('/mail-account-bot/lib/serve.js');
  let runs = 0;
  const config = { dashboard_url: baseURL, dashboard_token: TOKEN, host: 'rechner-serve', fallback_poll_minutes: 60 };
  const bg = serve({ config, runOnce: async () => { runs += 1; return { status: 'ok' }; }, log: () => {} });
  try {
    // one run right at the start, then only when woken
    await expect.poll(() => runs).toBe(1);
    await expect.poll(() => bg.connected()).toBe(true);
    const admin = await playwrightRequest.newContext({ baseURL });
    await apiLogin(admin, ACCOUNTS.admin);
    const mailbox = 'eltern.max.mustermann@mail.beispielschule.de';
    await admin.post('/api/create_mail_password_case', { data: { mailboxes: [mailbox], note: 'Hintergrund-Test' } });
    const id = (await (await admin.post('/api/mail_password_reset_status', { data: {} })).json()).cases
      .find((c: any) => c.state === 'open' && c.mailboxes.some((m: any) => m.mailbox === mailbox)).id;
    // only the approval wakes the bot, not the new open case
    await new Promise((r) => setTimeout(r, 1000));
    expect(runs).toBe(1);
    expect((await (await admin.post('/api/update_mail_password_case', { data: { id, action: 'approve' } })).json()).result).toBe('ok');
    await expect.poll(() => runs).toBe(2);
    await admin.post('/api/update_mail_password_case', { data: { id, action: 'done' } });
  } finally {
    bg.stop();
  }
});

test.afterAll(async ({ baseURL }) => {
  // never leave the bot paused for the other tests
  await resume(baseURL);
});
