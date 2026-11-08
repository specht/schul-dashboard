import { defineConfig, devices } from '@playwright/test';

// Runs against the isolated test stack started by ./test.sh (example data only).
export default defineConfig({
  testDir: './tests',
  // The tests share one database, so keep them sequential for now.
  workers: 1,
  fullyParallel: false,
  retries: 0,
  timeout: 30_000,
  expect: { timeout: 10_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:8125',
    locale: 'de-DE',
    timezoneId: 'Europe/Berlin',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    // browser tests (*.spec.ts) on desktop and phone
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
    // request-only checks (*.smoke.ts), no browser, run once
    { name: 'smoke', testMatch: /.*\.smoke\.ts/ },
  ],
});
