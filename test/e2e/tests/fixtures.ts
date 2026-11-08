import { test as base, expect, Page } from '@playwright/test';

// In the test stack (DEVELOPMENT mode, example data only) every login code is fixed.
export const DEV_LOGIN_CODE = '123456';

export const ACCOUNTS = {
  // teacher + admin in src/example-data
  admin: 'clarke@beispielschule.de',
  teacher: 'torstenson@beispielschule.de',
};

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
