import {
  test, expect, login, ACCOUNTS, displayedSchoolWeek, isoDate, showDayInTimetable,
} from './fixtures';

test('Lehrkraft lädt Klasse 5a zu einem Termin ein, er erscheint im Stundenplan', async ({ page, newUserPage }) => {
  const title = `Elternabend-Probe ${Date.now().toString(36)}`;
  const day = displayedSchoolWeek()[2]; // Wednesday of the week the timetable shows first

  await login(page, ACCOUNTS.teacher);
  await page.goto('/events');
  await page.locator('.bu-new-event').click();
  const modal = page.locator('#composeModal');
  await expect(modal).toBeVisible();
  await page.locator('#ti_title').fill(title);
  await page.locator('#ti_date').fill(isoDate(day));
  await page.locator('#ti_start_time').fill('15:00');
  await page.locator('#ti_end_time').fill('16:00');
  await modal.locator('#ti_recipients').pressSequentially('Klasse 5a');
  await modal.locator('.recipient-input-dropdown').getByText(/^Klasse 5a \(\d+\)$/).click();
  await expect(modal.locator('.recipients_list')).toContainText('Klasse 5a');
  await modal.locator('.note-editable').click();
  await page.keyboard.type('Bitte pünktlich sein.');

  const saved = page.waitForResponse('**/api/save_event');
  await page.locator('#bu_save_event').click();
  expect((await saved).status()).toBe(200);

  // student: the appointment shows up on that day (timetable files are
  // rewritten in the background)
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await expect(async () => {
    await student.reload();
    await showDayInTimetable(student, day);
    await expect(
      student.locator(`td.fc-timegrid-col[data-date="${isoDate(day)}"] .fc-event`, { hasText: title }),
    ).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
});
