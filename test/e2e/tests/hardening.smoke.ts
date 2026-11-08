import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ACCOUNTS, apiLogin, clearLoginMails, totp } from './fixtures';

// 1×1 PNG
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  'base64',
);

test('Zweiter Faktor allein ergibt keine Anmeldung', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await clearLoginMails(ACCOUNTS.teacher);
  const login = await request.post('/api/login', { data: { email: ACCOUNTS.teacher } });
  const { tag } = await login.json();

  const second = await request.post('/api/confirm_forced_2fa_login', {
    data: { tag, code: '', code2: totp() },
  });
  expect(second.status()).not.toBe(200);

  // still anonymous: the start page is the login page
  const start = await request.get('/');
  expect(await start.text()).toContain("id='email'");
  await request.dispose();
});

test('Bild-Upload nimmt nur Bilddateien an', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ACCOUNTS.schueler);

  const upload = (name: string) => request.post('/api/upload_poll_image', {
    multipart: { file: { name, mimeType: 'image/png', buffer: PNG } },
  });

  const ok = await upload('foto.PNG');
  expect(ok.status(), 'regular image').toBe(200);
  expect((await ok.json()).stored_path).toMatch(/^poll-[0-9a-f]{16}$/);

  for (const name of ['foto.$(id)', 'foto.html', 'foto']) {
    expect((await upload(name)).status(), name).not.toBe(200);
  }
  await request.dispose();
});
