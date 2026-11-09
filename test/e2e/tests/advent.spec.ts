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
