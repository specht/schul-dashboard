import { test, expect, request as playwrightRequest } from '@playwright/test';

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';

// Public sign-up (no login; test event from test/prepare_example_data.rb):
// it sends a confirmation from the school's address to the given address –
// so only a few per address and hour.
test('Öffentliche Anmeldung: Bestätigung per Mail, begrenzt pro Adresse', async ({ baseURL }) => {
  const email = `gast-${Date.now().toString(36)}@example.org`;
  const request = await playwrightRequest.newContext({ baseURL });
  const signUp = () => request.post('/api/sign_up_for_public_event', {
    data: { event_key: 'tag-der-offenen-tuer', entry_key: 'vormittag', name: 'Gabi Gast {6*7}', email },
  });
  const results: string[] = [];
  for (let i = 0; i < 4; i++) {
    const data = await (await signUp()).json();
    results.push(data.error || (data.ok ? 'ok' : 'other'));
  }
  expect(results).toEqual(['ok', 'ok', 'ok', 'too_many_sign_ups']);

  const query = encodeURIComponent(`to:"${email}"`);
  await expect.poll(async () => ((await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json()).messages || []).length)
    .toBe(3);
  const { messages } = await (await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`)).json();
  const message = await (await fetch(`${MAILPIT_URL}/api/v1/message/${messages[0].ID}`)).json();
  expect(message.HTML).toContain('Sie sind angemeldet: Samstag, 10:00 Uhr.');
  await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`, { method: 'DELETE' });
  await request.dispose();
});
