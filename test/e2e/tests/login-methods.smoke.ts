import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ACCOUNTS, apiLogin } from './fixtures';

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';

async function mailsTo(email: string, subject: string) {
  const query = encodeURIComponent(`to:"${email}" subject:"${subject}"`);
  return (await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json()).messages || [];
}

async function deleteMailsTo(email: string, subject: string) {
  const query = encodeURIComponent(`to:"${email}" subject:"${subject}"`);
  await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`, { method: 'DELETE' });
}

// Adding and removing a login method is announced by mail, so that a change
// made by someone else does not go unnoticed.
test('OTP aktivieren und entfernen wird per Mail mitgeteilt', async ({ baseURL }) => {
  const email = ACCOUNTS.schueler_oberstufe;
  await deleteMailsTo(email, 'OTP-Anmeldung');
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, email);
  expect((await request.post('/api/regenerate_otp_token', { data: {} })).status()).toBe(200);
  await expect.poll(async () => (await mailsTo(email, 'OTP-Anmeldung aktiviert')).length).toBe(1);
  expect((await request.post('/api/delete_otp_token', { data: {} })).status()).toBe(200);
  await expect.poll(async () => (await mailsTo(email, 'OTP-Anmeldung deaktiviert')).length).toBe(1);
  await deleteMailsTo(email, 'OTP-Anmeldung');
  await request.dispose();
});

test('Telefonnummer bestätigen nur angemeldet', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  const r = await request.post('/api/confirm_telephone_number', { data: { tag: 'x', code: '123456' } });
  expect(r.status()).not.toBe(200);
  await request.dispose();
});
