import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, type Page } from '@playwright/test';

// The start page refreshes its side panels (polls …), the unread messages
// badge and the timetable every few minutes while it stays open – teachers
// often leave it open for hours and saw polls that were long over.

const day = (offset: number) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return d.toISOString().slice(0, 10);
};

// fake browser time: 5½ minutes later, the refresh timer has fired
async function waitForRefresh(page: Page) {
  const refreshed = page.waitForResponse('**/api/refresh_start_page');
  await page.clock.fastForward('05:30');
  expect((await refreshed).status()).toBe(200);
}

test('Startseite aktualisiert Umfragen und ungelesene Nachrichten ohne Neuladen', async ({ page, baseURL }) => {
  const title = `Live ${Date.now().toString(36)}`;
  const teacher = await playwrightRequest.newContext({ baseURL });
  await apiLogin(teacher, ACCOUNTS.teacher);

  // the student's start page is open, without that poll
  await page.clock.install({ time: new Date() });
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#calendar')).toBeVisible();
  await expect(page.locator('.hint_poll', { hasText: title })).toHaveCount(0);

  // meanwhile the teacher starts a poll for the student and writes a message
  const poll = await teacher.post('/api/save_poll', { data: { title, items: '[]' } });
  expect(poll.status()).toBe(200);
  const pid = (await poll.json()).poll.pid;
  const run = await teacher.post('/api/save_poll_run', {
    data: {
      pid, anonymous: 'false', visible: 'yes', recipients: [ACCOUNTS.schueler],
      start_date: day(-1), start_time: '00:00', end_date: day(1), end_time: '23:59',
    },
  });
  expect(run.status()).toBe(200);
  const prid = (await run.json()).poll_run.prid;
  const message = await teacher.post('/api/send_message', {
    data: { recipients: [ACCOUNTS.schueler], message: '<p>Live-Test</p>' },
  });
  expect(message.status()).toBe(200);
  // unread messages only count once they are a moment old (MESSAGE_DELAY)
  await new Promise((r) => setTimeout(r, 2_000));

  // after a while it shows up – and the button works in the new panel
  await waitForRefresh(page);
  const hint = page.locator('.hint_poll', { hasText: title });
  await expect(hint).toBeVisible();
  await expect(page.locator('.new-messages-indicator, .new-messages-indicator-mini').filter({ visible: true }).first()).not.toHaveText('');
  await hint.locator('.bu-launch-poll').click();
  await expect(page.locator('#pollResponseModal .poll-title')).toHaveText(title);
  await page.locator('#bu_close_poll_response_modal').click();
  await expect(page.locator('#pollResponseModal')).toBeHidden();

  // the teacher deletes the run: it disappears again
  expect((await teacher.post('/api/delete_poll_run', { data: { prid } })).status()).toBe(200);
  await waitForRefresh(page);
  await expect(page.locator('.hint_poll', { hasText: title })).toHaveCount(0);
  await teacher.dispose();
});

test('Startseite aktualisiert nicht, solange ein Dialog offen ist', async ({ page }) => {
  await page.clock.install({ time: new Date() });
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#calendar')).toBeVisible();
  const requests: string[] = [];
  page.on('request', (r) => { if (r.url().includes('/api/refresh_start_page')) requests.push(r.url()); });

  await page.evaluate(() => (window as any).dashboardAlert('Bitte lesen', 'Hinweis'));
  await expect(page.locator('.modal.show')).toBeVisible();
  await page.clock.fastForward('05:30');
  await page.waitForTimeout(500);
  expect(requests).toHaveLength(0);

  // closed again: the next timer tick refreshes
  await page.locator('.modal.show').getByRole('button', { name: 'OK' }).click();
  await expect(page.locator('.modal.show')).toHaveCount(0);
  await waitForRefresh(page);
});
