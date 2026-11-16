import { test, expect, login, typeEmail, clearLoginMails, waitForMailedCode, ACCOUNTS, ROLE_ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// SMS codes go through a gateway that connects to /ws_sms. Every SMS is
// recorded with recipient and purpose (no number, no text), and
// /sms_anmeldung shows admins who still uses SMS – to move them to OTP.

// src/ruby/test/credentials.rb
const SMS_GATEWAY_SECRET = 'test-sms-gateway-secret';

type Sms = { telephone_number: string; message: string };

// A gateway like the real one: connects, authenticates, receives the SMS.
async function fakeSmsGateway(baseURL: string) {
  const ws = new WebSocket(baseURL.replace(/^http/, 'ws') + '/ws_sms');
  const inbox: Sms[] = [];
  ws.addEventListener('message', (e) => {
    const data = JSON.parse(String(e.data));
    if (data.command !== 'hello') inbox.push(data);
  });
  await new Promise((resolve, reject) => {
    ws.addEventListener('open', resolve);
    ws.addEventListener('error', reject);
  });
  ws.send(JSON.stringify({ hello: SMS_GATEWAY_SECRET }));
  let read = 0;
  return {
    async next(): Promise<Sms> {
      await expect.poll(() => inbox.length, { message: 'waiting for an SMS' }).toBeGreaterThan(read);
      return inbox[read++];
    },
    close: () => ws.close(),
  };
}

const codeIn = (sms: Sms) => /(\d{6})/.exec(sms.message)![1];

// the admin page, once it reports the gateway as online
async function openUsagePage(admin: Page) {
  await expect.poll(async () => {
    await admin.goto('/sms_anmeldung');
    return admin.locator('#sms_gateway_status').innerText();
  }).toContain('online');
}

async function smsCount(admin: Page, email: string) {
  const row = admin.locator(`tr.sms-usage-row[data-email="${email}"]`);
  return (await row.count()) ? Number(await row.getAttribute('data-sms90')) : 0;
}

// a number via the profile API: one SMS with the code, one confirmation
async function addTelephoneNumber(page: Page, gateway: Awaited<ReturnType<typeof fakeSmsGateway>>) {
  const saved = await page.request.post('/api/save_telephone_number', { data: { telephone_number: '0151 23456789' } });
  expect(saved.status()).toBe(200);
  const { tag } = await saved.json();
  const confirmed = await page.request.post('/api/confirm_telephone_number', { data: { tag, code: codeIn(await gateway.next()) } });
  expect(confirmed.status()).toBe(200);
  expect((await gateway.next()).message).toContain('aktiviert');
}

test('SMS-Anmeldung: Admin sieht, wer SMS-Codes bekommt und wofür', async ({ page, newUserPage, baseURL }) => {
  const person = ROLE_ACCOUNTS.technikteam; // no OTP
  const gateway = await fakeSmsGateway(baseURL!);
  const user = await newUserPage();
  try {
    await login(page, ACCOUNTS.admin);
    await openUsagePage(page);
    const before = await smsCount(page, person);

    await login(user, person);
    await addTelephoneNumber(user, gateway);
    expect((await user.request.post('/api/set_preferred_login_method', { data: { method: 'sms' } })).status()).toBe(200);
    // logging in again, now with the code from the SMS
    const again = await newUserPage();
    await again.goto('/');
    await typeEmail(again, person);
    await again.locator('#submit').click();
    await again.waitForURL(/\/c\//);
    await again.locator('#code').fill(codeIn(await gateway.next()));
    await again.locator('#submit').click();
    await again.waitForURL((url) => !url.pathname.startsWith('/c/'));

    await page.goto('/sms_anmeldung');
    const row = page.locator(`tr.sms-usage-row[data-email="${person}"]`);
    await expect(row).toHaveAttribute('data-sms90', String(before + 3));
    await expect(row.locator('.sms-usage-otp')).toContainText('nein');
    await expect(row).toContainText('bevorzugt');
    await expect(row).toContainText(/\d+\sSitzung/);
    await expect(row.locator('.sms-usage-purposes')).toContainText('Nummer bestätigen');
    await expect(row.locator('.sms-usage-purposes')).toContainText('Anmeldung');
    await expect(page.locator('#bu_copy_sms_addresses')).toHaveAttribute('data-addresses', new RegExp(person.replace('.', '\\.')));
    // neither the number nor a code on the page
    await expect(page.locator('body')).not.toContainText('23456789');
  } finally {
    await user.request.post('/api/delete_telephone_number', { data: {} });
    gateway.close();
  }
});

test('SMS als zweiter Faktor wird mitgezählt, Personen ohne OTP stehen oben', async ({ page, newUserPage, baseURL }) => {
  const person = ACCOUNTS.teacher; // email code, then OTP – or now an SMS
  const gateway = await fakeSmsGateway(baseURL!);
  const user = await newUserPage();
  try {
    await login(page, ACCOUNTS.admin);
    await openUsagePage(page);
    const before = await smsCount(page, person);

    await login(user, person);
    await addTelephoneNumber(user, gateway);
    await clearLoginMails(person);
    const again = await newUserPage();
    await again.goto('/');
    await typeEmail(again, person);
    await again.locator('#submit').click();
    await again.waitForURL(/\/c\//);
    await again.locator('#code').fill(await waitForMailedCode(person));
    await again.locator('#submit').click();
    await again.locator('#bu_force_2fa_sms').click();
    await again.locator('#code2').fill(codeIn(await gateway.next()));
    await again.locator('#submit2').click();
    await again.waitForURL((url) => !url.pathname.startsWith('/c/'));

    await page.goto('/sms_anmeldung');
    const row = page.locator(`tr.sms-usage-row[data-email="${person}"]`);
    await expect(row).toHaveAttribute('data-sms90', String(before + 3));
    await expect(row.locator('.sms-usage-otp')).toContainText('ja');
    await expect(row.locator('.sms-usage-purposes')).toContainText('2. Faktor');
    // everyone without OTP before everyone with OTP
    const otp = (await page.locator('.sms-usage-otp').allInnerTexts()).map((t) => t.includes('ja'));
    expect(otp).toEqual([...otp].sort((a, b) => Number(a) - Number(b)));
  } finally {
    await user.request.post('/api/delete_telephone_number', { data: {} });
    gateway.close();
  }
});
