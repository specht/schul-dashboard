import { test, expect, login, typeEmail, clearLoginMails, waitForMailedCode, ACCOUNTS, ROLE_ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';
import { SMS_GATEWAY_SECRET, fakeSmsGateway, codeIn, addTelephoneNumber } from './sms-helpers';
import net from 'node:net';
import crypto from 'node:crypto';

// SMS codes go through a gateway that connects to /ws_sms. Every SMS is
// recorded with recipient and purpose (no number, no text), and
// /sms_anmeldung shows admins who still uses SMS – to move them to OTP.

// A gateway whose connection is gone without the server noticing (e.g. its
// internet is down): it connects and authenticates, then never answers the
// server's pings. A normal client answers them by itself, so this one speaks
// the websocket protocol on a plain socket.
async function silentSmsGateway(baseURL: string) {
  const url = new URL(baseURL);
  const socket = net.connect(Number(url.port || 80), url.hostname);
  await new Promise((resolve, reject) => { socket.once('connect', resolve); socket.once('error', reject); });
  socket.write(`GET /ws_sms HTTP/1.1\r\nHost: ${url.host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
    `Sec-WebSocket-Key: ${crypto.randomBytes(16).toString('base64')}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  await new Promise<void>((resolve) => {
    let received = '';
    socket.on('data', (d) => { received += d.toString('latin1'); if (received.includes('\r\n\r\n')) resolve(); });
  });
  // one masked text frame with the secret, then silence
  const payload = Buffer.from(JSON.stringify({ hello: SMS_GATEWAY_SECRET }));
  const mask = crypto.randomBytes(4);
  const masked = Buffer.from(payload.map((b, i) => b ^ mask[i % 4]));
  socket.write(Buffer.concat([Buffer.from([0x81, 0x80 | payload.length]), mask, masked]));
  return { close: () => socket.destroy() };
}


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

// src/ruby/test/credentials.rb: ping every second, offline after 3 seconds
// without an answer (production: 20 and 60 seconds)
test('SMS-Gateway: ohne Antwort auf den Ping gilt es als offline, mit Antwort bleibt es online', async ({ page, baseURL }) => {
  await login(page, ACCOUNTS.admin);
  const status = page.locator('#sms_gateway_status');
  const silent = await silentSmsGateway(baseURL!);
  try {
    await openUsagePage(page);
    // codes would go into the void – the dashboard notices and uses email
    await expect.poll(async () => { await page.goto('/sms_anmeldung'); return status.innerText(); }, { timeout: 15_000 }).toContain('offline');
  } finally {
    silent.close();
  }
  const gateway = await fakeSmsGateway(baseURL!);
  try {
    await openUsagePage(page);
    // well past the 3 seconds: still there
    await page.waitForTimeout(6_000);
    await page.goto('/sms_anmeldung');
    await expect(status).toContainText('online');
  } finally {
    gateway.close();
  }
});
