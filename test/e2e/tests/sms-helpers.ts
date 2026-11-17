import { expect } from './fixtures';
import type { Page } from '@playwright/test';

// A fake SMS gateway for the test stack (it connects to /ws_sms like the
// real one) and helpers around it.

// src/ruby/test/credentials.rb
export const SMS_GATEWAY_SECRET = 'test-sms-gateway-secret';

export type Sms = { telephone_number: string; message: string };

// A gateway like the real one: connects, authenticates, receives the SMS.
export async function fakeSmsGateway(baseURL: string) {
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

export const codeIn = (sms: Sms) => /(\d{6})/.exec(sms.message)![1];

// a number via the profile API: one SMS with the code, one confirmation
export async function addTelephoneNumber(page: Page, gateway: Awaited<ReturnType<typeof fakeSmsGateway>>) {
  const saved = await page.request.post('/api/save_telephone_number', { data: { telephone_number: '0151 23456789' } });
  expect(saved.status()).toBe(200);
  const { tag } = await saved.json();
  const confirmed = await page.request.post('/api/confirm_telephone_number', { data: { tag, code: codeIn(await gateway.next()) } });
  expect(confirmed.status()).toBe(200);
  expect((await gateway.next()).message).toContain('aktiviert');
}
