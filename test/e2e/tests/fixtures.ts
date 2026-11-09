import { test as base, expect, Page, APIRequestContext } from '@playwright/test';
import crypto from 'crypto';

// The test stack runs in production mode: login codes are random and sent by
// mail to the Mailpit container, teachers need a second factor. See
// doc/Tests.md and test/e2e/seed.cypher.

const MAILPIT_URL = process.env.MAILPIT_URL || 'http://localhost:8126';

// must match test/e2e/seed.cypher
export const TEST_OTP_SECRET = 'JBSWY3DPEHPK3PXP';

// Accounts from src/example-data. Parents have no accounts of their own
// (they only appear as mailing list recipients).
export const ACCOUNTS = {
  // teacher, admin and class teacher of 5a; logs in with the OTP app
  admin: 'clarke@beispielschule.de',
  // teacher with forced two-factor login (email code, then OTP)
  teacher: 'torstenson@beispielschule.de',
  // students: 5a (lower school) and 11 (upper school), email code
  schueler: 'max.mustermann@mail.beispielschule.de',
  schueler_oberstufe: 'alice.mustermann@mail.beispielschule.de',
};

type Factor = 'email' | 'otp';
const LOGIN_FACTORS: Record<string, { first: Factor; second?: Factor }> = {
  [ACCOUNTS.admin]: { first: 'otp' },
  [ACCOUNTS.teacher]: { first: 'email', second: 'otp' },
  [ACCOUNTS.schueler]: { first: 'email' },
  [ACCOUNTS.schueler_oberstufe]: { first: 'email' },
};

// Collects server errors (5xx), uncaught JavaScript errors and console
// errors of a page.
export function watchPage(page: Page) {
  const watched = {
    serverErrors: [] as string[], pageErrors: [] as string[], consoleErrors: [] as string[],
    nativeDialogs: [] as string[],
  };
  // Native alert()/confirm()/prompt() are not allowed (AGENTS.md) – use
  // dashboardAlert()/dashboardConfirm() from _template.html.
  page.on('dialog', async (dialog) => {
    watched.nativeDialogs.push(`${dialog.type()}: ${dialog.message().slice(0, 80)}`);
    await dialog.dismiss();
  });
  page.on('response', (response) => {
    if (response.status() >= 500) watched.serverErrors.push(`${response.status()} ${response.url()}`);
  });
  page.on('pageerror', (error) => {
    // message plus the first stack frames, so the report shows where it happened
    const frames = (error.stack || '').split('\n').filter((l) => l.trim().startsWith('at ')).slice(0, 3);
    watched.pageErrors.push([error.message, ...frames.map((l) => l.trim())].join(' | '));
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error') watched.consoleErrors.push(msg.text());
  });
  return watched;
}

// Every test fails if the server answers with a 5xx or the page throws an
// uncaught JavaScript error – for the default `page` and for every page
// opened with `newUserPage`. Console errors are attached to the report.
// Tests that expect a 5xx (see TODO.md) remove it from `serverErrors`.
export const test = base.extend<{
  serverErrors: string[];
  newUserPage: () => Promise<Page>;
}>({
  serverErrors: [async ({ page }, use, testInfo) => {
    const watched = watchPage(page);
    await use(watched.serverErrors);
    await checkWatched(watched, testInfo, 'page');
  }, { auto: true }],

  // A page in a separate browser context, e.g. for a second user.
  newUserPage: async ({ browser }, use, testInfo) => {
    const opened: { watched: ReturnType<typeof watchPage>; close: () => Promise<void> }[] = [];
    await use(async () => {
      const context = await browser.newContext();
      const page = await context.newPage();
      opened.push({ watched: watchPage(page), close: () => context.close() });
      return page;
    });
    for (const [i, { watched, close }] of opened.entries()) {
      await close();
      await checkWatched(watched, testInfo, `user page ${i + 1}`);
    }
  },
});

async function checkWatched(watched: ReturnType<typeof watchPage>, testInfo: any, label: string) {
  if (watched.consoleErrors.length > 0) {
    await testInfo.attach(`console-errors (${label})`, { body: watched.consoleErrors.join('\n'), contentType: 'text/plain' });
  }
  expect(watched.serverErrors, `server errors (HTTP 5xx) – ${label}`).toEqual([]);
  expect(watched.pageErrors, `uncaught JavaScript errors – ${label}`).toEqual([]);
  expect(watched.nativeDialogs, `native browser dialogs – ${label}`).toEqual([]);
}

// The dialog of dashboardAlert()/dashboardConfirm() (#__template_modal).
export function dashboardDialog(page: Page) {
  return page.locator('#__template_modal');
}

// The week the timetable shows first: the current one, or the next one on
// weekends (same rule as the timetable page).
export function displayedSchoolWeek(now = new Date()) {
  const monday = new Date(now);
  const day = (now.getDay() + 6) % 7; // 0 = Monday
  monday.setDate(now.getDate() - day + (day >= 5 ? 7 : 0));
  return [0, 1, 2, 3, 4].map((i) => {
    const d = new Date(monday);
    d.setDate(monday.getDate() + i);
    return d;
  });
}

// Navigates the timetable ("<" / ">") until `day` is shown – a single day on
// phones, a week on larger screens.
export async function showDayInTimetable(page: Page, day: Date) {
  const target = isoDate(day);
  const column = page.locator(`td.fc-timegrid-col[data-date="${target}"]`);
  const shown = page.locator('td.fc-timegrid-col[data-date]');
  await expect(shown.first()).toBeVisible();
  for (let i = 0; i < 14 && (await column.count()) === 0; i++) {
    const first = await shown.first().getAttribute('data-date');
    await page.locator(target < first! ? '.fc-prev-button' : '.fc-next-button').click();
  }
  await expect(column).toBeVisible();
}

// The next Monday after today, and the Friday before it: two school days in
// different weeks that students can both see (they only see appointments up
// to TIMETABLE_ENTRIES_VISIBLE_AHEAD_DAYS = 7 days ahead).
export function fridayAndFollowingMonday(now = new Date()) {
  const monday = new Date(now);
  monday.setHours(12, 0, 0, 0);
  monday.setDate(monday.getDate() + (((8 - monday.getDay()) % 7) || 7));
  const friday = new Date(monday);
  friday.setDate(monday.getDate() - 3);
  return { friday, monday };
}

export const isoDate = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
export const germanDate = (d: Date) =>
  `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`;

export { expect };

// ---- codes ------------------------------------------------------------

function base32Decode(input: string): Buffer {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  let bits = '';
  for (const c of input.replace(/=+$/, '').toUpperCase()) {
    const value = alphabet.indexOf(c);
    if (value < 0) throw new Error(`invalid base32 character ${c}`);
    bits += value.toString(2).padStart(5, '0');
  }
  const bytes: number[] = [];
  for (let i = 0; i + 8 <= bits.length; i += 8) bytes.push(parseInt(bits.slice(i, i + 8), 2));
  return Buffer.from(bytes);
}

// RFC 6238 TOTP as used by ROTP in the app: SHA1, 6 digits, 30 s steps
export function totp(secret = TEST_OTP_SECRET, now = Date.now()): string {
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(now / 1000 / 30)));
  const hmac = crypto.createHmac('sha1', base32Decode(secret)).update(counter).digest();
  const offset = hmac[hmac.length - 1] & 0xf;
  const code = (hmac.readUInt32BE(offset) & 0x7fffffff) % 1_000_000;
  return code.toString().padStart(6, '0');
}

function mailQuery(email: string) {
  return encodeURIComponent(`to:"${email}" subject:"Anmeldecode"`);
}

export async function clearLoginMails(email: string) {
  if (process.env.LOGIN_CODE) return; // fixed code, no test mailbox involved
  await fetch(`${MAILPIT_URL}/api/v1/search?query=${mailQuery(email)}`, { method: 'DELETE' });
}

// Waits for a "Dein Anmeldecode lautet …" mail and returns the code.
export async function waitForMailedCode(email: string, timeoutMs = 15_000): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = await fetch(`${MAILPIT_URL}/api/v1/search?query=${mailQuery(email)}`);
    const { messages } = await response.json();
    const code = messages?.[0]?.Subject?.match(/(\d{6})/)?.[1];
    if (code) return code;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`no login code mail for ${email} within ${timeoutMs} ms`);
}

// Exploratory runs against a development instance (fixed login code there,
// see doc/Tests.md): LOGIN_CODE=123456
const FIXED_LOGIN_CODE = process.env.LOGIN_CODE;

async function codeFor(factor: Factor, email: string) {
  if (FIXED_LOGIN_CODE) return FIXED_LOGIN_CODE;
  if (factor === 'otp') return totp();
  const code = await waitForMailedCode(email);
  await clearLoginMails(email);
  return code;
}

// ---- login --------------------------------------------------------------

// The login page enables its button on keyup/change only, so type like a
// person instead of using fill() (which only fires `input`).
export async function typeEmail(page: Page, email: string) {
  await page.locator('#email').pressSequentially(email);
}

export async function login(page: Page, email: string) {
  const factors = LOGIN_FACTORS[email] || { first: 'email' };
  await clearLoginMails(email);
  await page.goto('/');
  await typeEmail(page, email);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await page.locator('#code').fill(await codeFor(factors.first, email));
  await page.locator('#submit').click();
  if (factors.second) {
    await expect(page.locator('#div_forced_2fa')).toBeVisible();
    await page.locator('#code2').fill(await codeFor(factors.second, email));
    await page.locator('#submit2').click();
  }
  await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
}

// Opens the profile menu in the navbar (on phones the navbar is collapsed
// behind the menu button first).
export async function openProfileMenu(page: Page) {
  const toggler = page.locator('.navbar-toggler');
  if (await toggler.isVisible()) await toggler.click();
  await page.locator('#navbarDropdownProfile').click();
  await expect(page.locator('[aria-labelledby="navbarDropdownProfile"]')).toBeVisible();
}

// Enters email and code on the login pages, without visiting / first –
// for the "Zusätzliche Anmeldung…" flow that starts on /login.
export async function loginOnCurrentPage(page: Page, email: string) {
  const factors = LOGIN_FACTORS[email] || { first: 'email' };
  await clearLoginMails(email);
  await typeEmail(page, email);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await page.locator('#code').fill(await codeFor(factors.first, email));
  await page.locator('#submit').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
}

// Logs an API request context in via the JSON API (no browser needed).
export async function apiLogin(request: APIRequestContext, email: string) {
  const factors = LOGIN_FACTORS[email] || { first: 'email' };
  await clearLoginMails(email);
  const loginResponse = await request.post('/api/login', { data: { email } });
  expect(loginResponse.status(), `login for ${email}`).toBe(200);
  const { tag } = await loginResponse.json();
  const confirm = await request.post('/api/confirm_login', {
    data: { tag, code: await codeFor(factors.first, email) },
  });
  expect(confirm.status(), `confirm_login for ${email}`).toBe(200);
  const confirmed = await confirm.json();
  if (confirmed.force_2fa) {
    expect(factors.second, `unexpected second factor for ${email}`).toBeDefined();
    const second = await request.post('/api/confirm_forced_2fa_login', {
      data: { tag, code: '', code2: await codeFor(factors.second!, email) },
    });
    expect(second.status(), `confirm_forced_2fa_login for ${email}`).toBe(200);
  }
}
