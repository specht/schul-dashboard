import { test, expect, request as playwrightRequest } from '@playwright/test';
import crypto from 'crypto';
import { ACCOUNTS, apiLogin } from './fixtures';

// Access checks of API routes: who may read or create what. Request-only.
// Example data: Clarke (admin) is class teacher of 5a, Torstenson is not.

// JWT_APPKEY_BIB from credentials.template.rb (test stack only)
const BIB_APPKEY = 'ein_langer_langer_richtig_langer_app_key';

function hs256(payload: object) {
  const b64 = (x: object) => Buffer.from(JSON.stringify(x)).toString('base64url');
  const unsigned = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(payload)}`;
  const sig = crypto.createHmac('sha256', BIB_APPKEY).update(unsigned).digest('base64url');
  return `${unsigned}.${sig}`;
}

async function contextFor(baseURL: string | undefined, email: string | null) {
  const request = await playwrightRequest.newContext({ baseURL });
  if (email) await apiLogin(request, email);
  return request;
}

const ZEUGNIS_DATA = (schueler: string[]) => ({
  format: 'xlsx', schueler,
  paths_fach: [], values_fach: [], paths_fehltage: [], values_fehltage: [], paths_ab: [], values_ab: [],
});

test('Unterrichtsdaten nur über die Seiten, nicht anonym per API', async ({ baseURL }) => {
  for (const email of [null, ACCOUNTS.schueler]) {
    const request = await contextFor(baseURL, email);
    const r = await request.post('/api/get_lesson_data', { data: { lesson_key: 'Ma_5a' } });
    expect(r.status(), `get_lesson_data als ${email || 'anonym'}`).not.toBe(200);
    await request.dispose();
  }
});

test('Bibliotheks-Dump nur für den Bibliotheksserver und ohne Passwörter', async ({ baseURL }) => {
  // a user's own bib token (needed for the library pages) does not open the dump
  const student = await contextFor(baseURL, ACCOUNTS.schueler);
  const token = (await (await student.post('/api/get_bib_jwt_token', { data: {} })).json()).token;
  expect(token).toBeTruthy();
  for (const path of ['/api/get_bib_dump', '/api/get_bib_dump_etag']) {
    const r = await student.get(path, { headers: { 'X-JWT': token } });
    expect(r.status(), `${path} mit Nutzer-Token`).not.toBe(200);
  }
  await student.dispose();

  // anonymous visitors don't get a bib token at all
  const anon = await contextFor(baseURL, null);
  expect((await anon.post('/api/get_bib_jwt_token', { data: {} })).status()).not.toBe(200);

  // the library server (token without user) gets what it needs – nothing more
  const server = hs256({ exp: Math.floor(Date.now() / 1000) + 60 });
  const etag = await anon.get('/api/get_bib_dump_etag', { headers: { 'X-JWT': server } });
  expect(etag.status()).toBe(200);
  const dump = await anon.get('/api/get_bib_dump', { headers: { 'X-JWT': server } });
  expect(dump.status()).toBe(200);
  const data = await dump.json();
  const users = Object.values(data.user_info) as Record<string, unknown>[];
  expect(users.length).toBeGreaterThan(0);
  for (const u of users) {
    expect(Object.keys(u).sort()).toEqual(expect.arrayContaining(['display_name']));
    for (const key of Object.keys(u)) {
      expect(['display_name', 'shorthand'], `Feld ${key} im Dump`).toContain(key);
    }
  }
  const lesson = Object.values(data.lessons.lesson_keys)[0] as Record<string, unknown>;
  expect(Object.keys(lesson)).toEqual(['pretty_folder_name']);
  await anon.dispose();
});

test('Zeugnisse drucken nur Klassenleitung und Zeugnis-Admins', async ({ baseURL }) => {
  for (const email of [null, ACCOUNTS.schueler, ACCOUNTS.teacher]) {
    const request = await contextFor(baseURL, email);
    const who = email || 'anonym';
    for (const schueler of [[], ['5a/max.mustermann@mail.beispielschule.de']]) {
      const z = await request.post('/api/print_zeugnis', { data: ZEUGNIS_DATA(schueler) });
      expect(z.status(), `print_zeugnis ${schueler} als ${who}`).not.toBe(200);
    }
    const s = await request.post('/api/print_sozialzeugnis', {
      data: { klasse: '5a', paths: [], values: [] },
    });
    expect(s.status(), `print_sozialzeugnis als ${who}`).not.toBe(200);
    await request.dispose();
  }
});

test('Kein Chat-Login mehr', async ({ baseURL }) => {
  const request = await contextFor(baseURL, null);
  const r = await request.post('/api/confirm_chat_login', {
    data: { user: { id: '@someone:example.com', password: 'x/y' } },
  });
  expect(r.status()).toBe(404);
  const login = await request.post('/api/login', { data: { email: ACCOUNTS.schueler, purpose: 'chat' } });
  expect(await login.text()).not.toContain('chat_handle');
  await request.dispose();
});
