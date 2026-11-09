import {
  test, expect, login, ACCOUNTS, displayedSchoolWeek, isoDate, germanDate, showDayInTimetable,
} from './fixtures';

// Lesson topics (from the course planning) are shown as text in the timetable.
test('Stundenthema erscheint im Stundenplan als Text', async ({ page, newUserPage }) => {
  const stamp = Date.now().toString(36);
  const topic = `<b>Bruchrechnung</b> ${stamp}`;
  await login(page, ACCOUNTS.admin);
  await page.goto('/lessons/Ma_5a');
  const week = displayedSchoolWeek();
  const row = page.locator('tr.lesson').filter({
    hasText: new RegExp(week.map(germanDate).map((d) => d.replace(/\./g, '\\.')).join('|')),
  }).first();
  const rowText = await row.innerText();
  const day = week.find((d) => rowText.includes(germanDate(d)))!;
  await row.click();
  // the page enables saving on key presses (fill() sends none)
  await page.locator('#ti_stundenthema_text').pressSequentially(topic);
  const saved = page.waitForResponse('**/api/save_lesson_data');
  await page.locator('.bu-save-changes').first().click();
  expect((await saved).status()).toBe(200);

  const student = await newUserPage();
  await student.route('**/gen/**', (route) => route.continue()); // no 60 s cache
  await login(student, ACCOUNTS.schueler);
  const lesson = student.locator(`td.fc-timegrid-col[data-date="${isoDate(day)}"] .fc-event`)
    .filter({ hasText: 'Mathematik' }).first();
  const modal = student.locator('#lessonModal');
  await expect(async () => {
    await student.reload();
    await showDayInTimetable(student, day);
    await lesson.click();
    await expect(modal).toContainText(topic, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await expect(modal.locator('b', { hasText: 'Bruchrechnung' })).toHaveCount(0);
});

// Problem reports from the technology duty are shown as text to the admins.
test('Technik-Problemmeldung erscheint als Text', async ({ page }) => {
  const stamp = Date.now().toString(36);
  const problem = `<i>Beamer flackert</i> ${stamp}`;
  await login(page, ACCOUNTS.admin);
  const reported = await page.request.post('/api/report_tech_problem', {
    data: { problem, device: 'Beamer 108', date: isoDate(new Date()) },
  });
  expect(reported.status()).toBe(200);
  await page.goto('/techpostadmin');
  await page.locator('tr', { hasText: stamp }).first().click();
  const modal = page.locator('#__template_modal');
  await expect(modal.locator('.modal-title')).toHaveText(problem);
  await expect(modal.locator('.modal-body')).toContainText(problem);
  await expect(modal.locator('i', { hasText: 'Beamer flackert' })).toHaveCount(0);
});
