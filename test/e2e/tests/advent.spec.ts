import { test, expect, login, showDayInTimetable, ACCOUNTS } from './fixtures';

// "Mathe im Advent": SuS of grades 5–9 get a daily link in December of the
// current school year (it was fixed to 2025 before).
test('Mathe im Advent erscheint im Dezember des laufenden Schuljahres', async ({ page }) => {
  // the browser lives on 3 December (the server keeps its own date)
  const now = new Date();
  const year = now.getMonth() >= 7 ? now.getFullYear() : now.getFullYear() - 1;
  const day = new Date(`${year}-12-03T10:00:00`);
  await page.clock.setFixedTime(day);
  await login(page, ACCOUNTS.schueler); // 5a
  await page.goto('/');
  // the timetable starts on the server's date – go to 3 December
  await showDayInTimetable(page, day);
  const entries = page.locator('.fc-event', { hasText: 'Mathe im Advent' });
  await expect(entries.first()).toBeVisible({ timeout: 15_000 });
});

// The same in the new design (everyone has it from 1 December): the student
// gets it as a test person here – in the week's all-day row on wide screens,
// at the top of the day on phones; a tap opens that day's task.
test('Mathe im Advent im neuen Design', async ({ page, browser, baseURL }, testInfo) => {
  const mobile = testInfo.project.name === 'mobile';
  const admin = await (await browser.newContext({ baseURL })).newPage();
  await login(admin, ACCOUNTS.admin);
  expect((await admin.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'on' } })).status()).toBe(200);
  try {
    const now = new Date();
    const year = now.getMonth() >= 7 ? now.getFullYear() : now.getFullYear() - 1;
    const day = new Date(`${year}-12-03T10:00:00`);
    await page.clock.setFixedTime(day);
    await login(page, ACCOUNTS.schueler); // 5a
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    await showDayInTimetable(page, day);
    const entry = mobile
      ? page.locator('.pv-ag-allday', { hasText: 'Mathe im Advent' })
      : page.locator('.fc-event', { hasText: 'Mathe im Advent' });
    await expect(entry.first()).toBeVisible({ timeout: 15_000 });
    // the task of the day, in a new tab
    await page.evaluate(() => { window.open = ((url: string) => { (window as unknown as { opened: string }).opened = url; return null; }) as typeof window.open; });
    await entry.first().click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { opened?: string }).opened)).toBe('https://www.mathe-im-advent.de/de/kalender/4-6/3/');
  } finally {
    await admin.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'off' } });
    await admin.context().close();
  }
});
