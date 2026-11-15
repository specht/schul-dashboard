import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ACCOUNTS, ROLE_ACCOUNTS, apiLogin, clearLoginMails, totp } from './fixtures';

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

test('Unterstufenparty-Upload nimmt nur Bilddateien an', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  // a student with the "unterstufenparty" role
  await apiLogin(request, ROLE_ACCOUNTS.sv);

  const upload = (name: string, buffer: Buffer = PNG) => request.post('/api/up_upload_image', {
    multipart: { card: { name, mimeType: 'image/jpeg', buffer } },
  });

  // the page always sends "card.jpg"
  expect((await upload('card.jpg')).status(), 'regular image').toBe(200);
  for (const name of ['card.html', 'card.svg', 'card']) {
    expect((await upload(name, Buffer.from(`<p>${name}</p>`))).status(), name).not.toBe(200);
  }
  await request.dispose();
});

test('Hochgeladene Dateien laufen nie als Seite des Dashboards', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ACCOUNTS.admin);
  const suffix = Date.now().toString(36);
  const names = {
    html: `seite-${suffix}.html`,
    svg: `bild-${suffix}.svg`,
    png: `bild-${suffix}.png`,
    unknown: `daten-${suffix}.xyz`,
  };
  const contents: Record<string, Buffer> = {
    html: Buffer.from('<!doctype html><p>Seite</p>'),
    svg: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"><text>x</text></svg>'),
    png: PNG,
    unknown: Buffer.from('<p>kein Typ</p>'),
  };
  for (const [kind, filename] of Object.entries(names)) {
    const upload = await request.post('/api/upload_file', {
      multipart: { filename, file: { name: filename, mimeType: 'application/octet-stream', buffer: contents[kind] } },
    });
    expect(upload.status(), filename).toBe(200);
  }

  try {
    for (const prefix of ['/f/', '/raw/uploads/files/']) {
      // HTML and SVG: download only, and even then without scripts or the site's origin
      for (const filename of [names.html, names.svg]) {
        const response = await request.get(prefix + filename);
        expect(response.status(), prefix + filename).toBe(200);
        const headers = response.headers();
        expect(headers['content-disposition'], prefix + filename).toBe('attachment');
        expect(headers['content-security-policy'], prefix + filename).toBe('sandbox');
        expect(headers['x-content-type-options'], prefix + filename).toBe('nosniff');
      }
      // images still show in the browser
      const png = await request.get(prefix + names.png);
      expect(png.status()).toBe(200);
      expect(png.headers()['content-type']).toBe('image/png');
      expect(png.headers()['content-disposition']).toBeUndefined();
      expect(png.headers()['x-content-type-options']).toBe('nosniff');
      // unknown types are never guessed to be HTML
      const unknown = await request.get(prefix + names.unknown);
      expect(unknown.headers()['content-type']).not.toContain('html');
      expect(unknown.headers()['x-content-type-options']).toBe('nosniff');
    }
  } finally {
    for (const filename of Object.values(names)) {
      await request.post('/api/delete_file', { data: { filename } });
    }
  }
  await request.dispose();
});

test('Datei per URL holen erreicht keine internen Dienste', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ACCOUNTS.admin);
  for (const uri of [
    'http://neo4j:7474/',
    'http://ruby:3000/api/ping',
    'http://127.0.0.1:3000/api/ping',
    'http://localhost:3000/api/ping',
    'http://[::1]:3000/api/ping',
    'http://169.254.169.254/latest/meta-data/',
    'file:///etc/passwd',
    'gopher://neo4j:7687/',
    // the Nextcloud branch only checked whether the address contains the Nextcloud URL
    'http://neo4j:7474/?http://localhost:8024',
  ]) {
    const response = await request.post('/api/upload_file_via_uri', { data: { uri } });
    expect(response.status(), uri).not.toBe(200);
    expect(await response.text(), uri).not.toContain('"body"');
  }
  await request.dispose();
});
