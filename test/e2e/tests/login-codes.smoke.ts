import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ACCOUNTS, clearLoginMails, waitForMailedCode } from './fixtures';

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';

// A login code mail goes to the person who asked for it – and nobody else.
test('Anmeldecode-Mail ohne Kopie an weitere Empfänger', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await clearLoginMails(ACCOUNTS.schueler);
  const r = await request.post('/api/login', { data: { email: ACCOUNTS.schueler } });
  expect(r.status()).toBe(200);
  await waitForMailedCode(ACCOUNTS.schueler);
  const query = encodeURIComponent(`to:"${ACCOUNTS.schueler}" subject:"Anmeldecode"`);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  expect(messages.length).toBeGreaterThan(0);
  const m = messages[0];
  expect((m.To || []).map((x: { Address: string }) => x.Address)).toEqual([ACCOUNTS.schueler]);
  expect(m.Cc || []).toEqual([]);
  expect(m.Bcc || []).toEqual([]);
  await clearLoginMails(ACCOUNTS.schueler);
  await request.dispose();
});

// Requesting codes again and again (for someone else's address) is limited:
// at most a few open login attempts per person at a time.
test('Anmeldecodes nur begrenzt anforderbar', async ({ baseURL }) => {
  // own account (test/prepare_example_data.rb): the open attempts stay for ten
  // minutes and would block other tests' logins
  const email = 'anmeldelimit@beispielschule.de';
  const request = await playwrightRequest.newContext({ baseURL });
  const results: string[] = [];
  for (let i = 0; i < 7; i++) {
    const r = await request.post('/api/login', { data: { email } });
    const data = await r.json();
    results.push(data.error || (data.tag ? 'ok' : 'other'));
  }
  expect(results.slice(0, 5)).toEqual(['ok', 'ok', 'ok', 'ok', 'ok']);
  expect(results.slice(5)).toEqual(['too_many_login_attempts', 'too_many_login_attempts']);
  await clearLoginMails(email);
  await request.dispose();
});

// The second code is only sent after the first factor was confirmed.
test('Zweiter Code nur nach bestätigtem ersten Faktor', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await clearLoginMails(ACCOUNTS.teacher);
  const { tag } = await (await request.post('/api/login', { data: { email: ACCOUNTS.teacher } })).json();
  const r = await request.post('/api/send_forced_code2', { data: { tag, method: 'email' } });
  expect(r.status()).not.toBe(200);
  await clearLoginMails(ACCOUNTS.teacher);
  await request.dispose();
});
