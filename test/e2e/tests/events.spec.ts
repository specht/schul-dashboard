import type { Page } from '@playwright/test';
import {
  test, expect, login, ACCOUNTS, displayedSchoolWeek, isoDate, showDayInTimetable, fridayAndFollowingMonday,
} from './fixtures';

async function createEventFor5a(page: Page, title: string, day: Date) {
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
}

// the event in the timetable column of `day` (shows that day first on phones)
async function eventOnDay(student: Page, day: Date, title: string) {
  await showDayInTimetable(student, day);
  return student.locator(`td.fc-timegrid-col[data-date="${isoDate(day)}"] .fc-event`, { hasText: title });
}

test('Lehrkraft lädt Klasse 5a zu einem Termin ein, er erscheint im Stundenplan', async ({ page, newUserPage }) => {
  const title = `Elternabend-Probe ${Date.now().toString(36)}`;
  const day = displayedSchoolWeek()[2]; // Wednesday of the week the timetable shows first

  await login(page, ACCOUNTS.teacher);
  await createEventFor5a(page, title, day);

  // student: timetable files are rewritten in the background
  const student = await newUserPage();
  // timetable files may be cached for 60 s (max-age) – the student's first
  // load can come just before the file is rewritten; with a route, Playwright
  // bypasses the browser cache
  await student.route('**/gen/**', (route) => route.continue());
  await login(student, ACCOUNTS.schueler);
  await expect(async () => {
    await student.reload();
    await expect(await eventOnDay(student, day, title)).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });
});

test('Verschobener Termin verschwindet aus der alten Woche (kein Geister-Termin)', async ({ page, newUserPage }) => {
  const title = `Verschoben ${Date.now().toString(36)}`;
  // Friday -> following Monday: another week, both visible for students
  const { friday: oldDay, monday: newDay } = fridayAndFollowingMonday();

  await login(page, ACCOUNTS.teacher);
  await createEventFor5a(page, title, oldDay);

  const student = await newUserPage();
  // timetable files may be cached for 60 s (max-age) – the student's first
  // load can come just before the file is rewritten; with a route, Playwright
  // bypasses the browser cache
  await student.route('**/gen/**', (route) => route.continue());
  await login(student, ACCOUNTS.schueler);
  await expect(async () => {
    await student.reload();
    await expect(await eventOnDay(student, oldDay, title)).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 30_000 });

  // teacher moves the appointment to the following Monday
  await page.goto('/events');
  await page.locator('.events-here tr', { hasText: title }).click();
  await expect(page.locator('#composeModal')).toBeVisible();
  await page.locator('#ti_date').fill(isoDate(newDay));
  const updated = page.waitForResponse('**/api/update_event');
  await page.locator('#bu_save_event').click();
  expect((await updated).status()).toBe(200);

  // student: shown in the new week, gone from the old one. Week files are
  // cached for 60 s in the browser (students load them without a
  // cache-busting parameter), hence the longer wait.
  test.setTimeout(240_000);
  await expect(async () => {
    await student.reload();
    await expect(await eventOnDay(student, newDay, title)).toBeVisible({ timeout: 2_000 });
  }).toPass({ timeout: 90_000 });
  await expect(async () => {
    await student.reload();
    await expect(await eventOnDay(student, oldDay, title)).toHaveCount(0, { timeout: 2_000 });
  }).toPass({ timeout: 90_000 });
});
