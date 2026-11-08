import { test, expect, request as playwrightRequest } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { ACCOUNTS, apiLogin } from './fixtures';

// Page smoke test: every page in src/static is requested once per role,
// without a browser. A page may render (200) or redirect (3xx) – a server
// error (5xx) is only acceptable if it is listed in known-page-errors.json.
//
// The list is a baseline of the current state, not a goal: the test also
// fails when a listed page no longer errors, so that fixes get recorded.
// Update it with UPDATE_KNOWN_PAGE_ERRORS=1 (see doc/Tests.md).

const STATIC_DIR = process.env.STATIC_DIR || '/static';
const KNOWN_ERRORS_FILE = path.join(__dirname, 'known-page-errors.json');

// Same rule as the page route in main.rb: no leading '_', no further dots.
const pages = fs.readdirSync(STATIC_DIR)
  .filter((f) => f.endsWith('.html'))
  .map((f) => f.slice(0, -'.html'.length))
  .filter((name) => !name.startsWith('_') && !name.includes('.'))
  .sort();

const roles: Record<string, string | null> = {
  anonym: null,
  schueler: ACCOUNTS.schueler,
  schueler_oberstufe: ACCOUNTS.schueler_oberstufe,
  lehrkraft: ACCOUNTS.teacher,
  admin: ACCOUNTS.admin,
};

const known: Record<string, Record<string, string>> =
  fs.existsSync(KNOWN_ERRORS_FILE) ? JSON.parse(fs.readFileSync(KNOWN_ERRORS_FILE, 'utf8')) : {};
const observed: Record<string, Record<string, string>> = {};
const updating = process.env.UPDATE_KNOWN_PAGE_ERRORS === '1';

test.afterAll(() => {
  if (!updating) return;
  const merged = { ...known, ...observed };
  // keep explanations that were written by hand
  for (const role of Object.keys(observed)) {
    for (const page of Object.keys(observed[role])) {
      const previous = known[role]?.[page];
      if (previous && !previous.startsWith('HTTP ')) merged[role][page] = previous;
    }
  }
  fs.writeFileSync(KNOWN_ERRORS_FILE, JSON.stringify(merged, null, 2) + '\n');
});

for (const [role, email] of Object.entries(roles)) {
  test(`alle Seiten ohne Serverfehler: ${role}`, async ({ baseURL }) => {
    test.setTimeout(10 * 60_000);
    const request = await playwrightRequest.newContext({ baseURL });
    if (email) await apiLogin(request, email);

    const errors: Record<string, string> = {};
    for (const page of pages) {
      const response = await request.get(`/${page}`, { maxRedirects: 0, timeout: 60_000 });
      if (response.status() >= 500) errors[page] = `HTTP ${response.status()}`;
    }
    await request.dispose();
    observed[role] = errors;
    if (updating) return;

    const expected = Object.keys(known[role] || {}).sort();
    const actual = Object.keys(errors).sort();
    const newErrors = actual.filter((p) => !expected.includes(p));
    const fixed = expected.filter((p) => !actual.includes(p));
    expect.soft(newErrors, `neue Serverfehler (${role})`).toEqual([]);
    expect.soft(fixed, `behoben – aus known-page-errors.json entfernen (${role})`).toEqual([]);
  });
}
