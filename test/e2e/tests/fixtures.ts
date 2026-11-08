import { test as base, expect, Page, APIRequestContext } from '@playwright/test';

// In the test stack (DEVELOPMENT mode, example data only) every login code is fixed.
export const DEV_LOGIN_CODE = '123456';

// Accounts from src/example-data. Parents have no accounts of their own
// (they only appear as mailing list recipients).
export const ACCOUNTS = {
  // teacher, admin and class teacher of 5a
  admin: 'clarke@beispielschule.de',
  teacher: 'torstenson@beispielschule.de',
  // students: 5a (lower school) and 11 (upper school)
  schueler: 'max.mustermann@mail.beispielschule.de',
  schueler_oberstufe: 'alice.mustermann@mail.beispielschule.de',
};

// Logs an API request context in via the JSON API (no browser needed).
export async function apiLogin(request: APIRequestContext, email: string) {
  const loginResponse = await request.post('/api/login', { data: { email } });
  expect(loginResponse.status(), `login for ${email}`).toBe(200);
  const { tag } = await loginResponse.json();
  const confirmResponse = await request.post('/api/confirm_login', { data: { tag, code: DEV_LOGIN_CODE } });
  expect(confirmResponse.status(), `confirm_login for ${email}`).toBe(200);
}

// Every test fails if the server answers with a 5xx or the page throws an
// uncaught JavaScript error. Console errors are attached to the report.
export const test = base.extend<{ serverErrors: string[] }>({
  serverErrors: [async ({ page }, use, testInfo) => {
    const serverErrors: string[] = [];
    const pageErrors: string[] = [];
    const consoleErrors: string[] = [];
    page.on('response', (response) => {
      if (response.status() >= 500) serverErrors.push(`${response.status()} ${response.url()}`);
    });
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (msg) => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await use(serverErrors);

    if (consoleErrors.length > 0) {
      await testInfo.attach('console-errors', { body: consoleErrors.join('\n'), contentType: 'text/plain' });
    }
    expect(serverErrors, 'server errors (HTTP 5xx)').toEqual([]);
    expect(pageErrors, 'uncaught JavaScript errors').toEqual([]);
  }, { auto: true }],
});

export { expect };

// The login page enables its button on keyup/change only, so type like a
// person instead of using fill() (which only fires `input`).
export async function typeEmail(page: Page, email: string) {
  await page.locator('#email').pressSequentially(email);
}

export async function login(page: Page, email: string) {
  await page.goto('/');
  await typeEmail(page, email);
  await page.locator('#submit').click();
  await page.waitForURL(/\/c\//);
  await page.locator('#code').fill(DEV_LOGIN_CODE);
  await page.locator('#submit').click();
  await page.waitForURL((url) => !url.pathname.startsWith('/c/'));
}
