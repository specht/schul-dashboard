import {
  test, expect, login, ACCOUNTS, displayedSchoolWeek, isoDate, germanDate, showDayInTimetable,
} from './fixtures';

// Example data: Clarke teaches Mathematik in 5a, Max Mustermann is in 5a.
test('Lehrkraft trägt Stundenthema und Hausaufgaben ein, Schüler:in sieht sie im Stundenplan', async ({ page, newUserPage }) => {
  const stamp = Date.now().toString(36);
  const internal = `Interne Notiz ${stamp}`;
  const topic = `Bruchrechnung ${stamp}`;
  const homework = `Buch S. 42 Nr. 3 ${stamp}`;

  // teacher: pick the first Mathematik lesson of the displayed week
  await login(page, ACCOUNTS.admin);
  await page.goto('/lessons/Ma_5a');
  const week = displayedSchoolWeek();
  const row = page.locator('tr.lesson').filter({
    hasText: new RegExp(week.map(germanDate).map((d) => d.replace(/\./g, '\\.')).join('|')),
  }).first();
  await expect(row).toBeVisible();
  const rowText = await row.innerText();
  const day = week.find((d) => rowText.includes(germanDate(d)))!;

  await row.click();
  await page.locator('#ti_thema').fill(internal);
  await page.locator('#ti_stundenthema_text').fill(topic);
  await page.locator('#ti_hausaufgaben_text').fill(homework);
  const saved = page.waitForResponse('**/api/save_lesson_data');
  await page.locator('.bu-save-changes').first().click();
  expect((await saved).status()).toBe(200);
  await expect(row).toContainText(topic);

  // student: the lesson in the timetable shows topic and homework, but not
  // the internal note. The timetable files are rewritten in the background.
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  const lesson = student
    .locator(`td.fc-timegrid-col[data-date="${isoDate(day)}"] .fc-event`)
    .filter({ hasText: 'Mathematik' })
    .first();
  const modal = student.locator('#lessonModal');
  await expect(async () => {
    await student.reload();
    await showDayInTimetable(student, day);
    await lesson.click();
    await expect(modal).toContainText(topic, { timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
  await expect(modal).toContainText(homework);
  await expect(modal).not.toContainText(internal);
});
