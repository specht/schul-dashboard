import type { Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, dashboardDialog, isoDate } from './fixtures';

// Neues Design (Vorschau): Klassenarbeiten (/tests, preview/tests.js). One
// panel with the month, the class as a menu, »Heute«, back and forth and
// »Eintragen«; desktop and tablet show the month as a grid, phones as an
// agenda. The preview is for admins only on the test stack; the teacher
// gets it as a tester for the role check.

const MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

// a weekday two or more days ahead
function aheadWeekday() {
  const d = new Date(Date.now() + 2 * 86400000);
  while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
  return d;
}

async function saveTest(page: Page, data: Record<string, string>) {
  const r = await page.request.post('/api/save_test', { data });
  expect(r.status()).toBe(200);
  return (await r.json()).test.tid as string;
}

// shows the month of `day`
async function showMonthOf(page: Page, day: Date) {
  const want = `${MONTHS[day.getMonth()]} ${day.getFullYear()}`;
  for (let i = 0; i < 3 && (await page.locator('#pv_tests_title').textContent()) !== want; i++) {
    await page.locator('#bu_pv_tests_next').click();
  }
  await expect(page.locator('#pv_tests_title')).toHaveText(want);
}

test('Neues Design: Klassenarbeiten als ruhiger Monat, am Handy als Agenda', async ({ page }, testInfo) => {
  test.setTimeout(180_000);
  const phone = testInfo.project.name === 'mobile';
  const tag = `${testInfo.project.name}-${Date.now().toString(36)}`;
  const day = aheadWeekday();
  const next = new Date(day.getTime() + 86400000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const ids: string[] = [];
  try {
    ids.push(await saveTest(page, {
      klasse: '5a', datum: isoDate(day), end_datum: isoDate(day), fach: 'Ma',
      kommentar: `Brüche ${tag}`, typ: 'KA', public_for_klasse: 'yes',
    }));
    ids.push(await saveTest(page, {
      klasse: '5a', datum: isoDate(day), end_datum: isoDate(next), fach: '',
      kommentar: `Museum ${tag}`, typ: 'Exkursion', public_for_klasse: 'no',
    }));
    await page.goto('/tests/5a');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    await expect(page.locator('body')).toHaveClass(/pv-tests-page/);
    const panel = page.locator('.pv-tests');
    await expect(panel).toBeVisible();
    // the header replaces FullCalendar's toolbar and the chip cloud
    await expect(page.locator('.fc-header-toolbar')).toHaveCount(0);
    await expect(page.locator('.ttc[data-klasse]').first()).toBeHidden();
    await expect(page.locator('#pv_tests_title')).toHaveText(/^(Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember) \d{4}$/);
    await expect(page.locator('#bu_pv_tests_klasse')).toHaveText('Klasse 5a');
    await expect(page.locator('#bu_pv_tests_add')).toBeVisible();
    await expect(page.locator(phone ? '#bu_pv_tests_add .pv-tests-add-short' : '#bu_pv_tests_add .pv-tests-add-long')).toBeVisible();
    await expect(page.locator(phone ? '#bu_pv_tests_add .pv-tests-add-long' : '#bu_pv_tests_add .pv-tests-add-short')).toBeHidden();
    await expect(page.locator('#bu_pv_tests_manage')).toHaveAttribute('href', '/manage_test_calendar');
    await showMonthOf(page, day);

    let exam;
    if (phone) {
      await expect(page.locator('#calendar .fc-view-harness')).toBeHidden();
      exam = page.locator('#pv_tests_agenda .pv-ta-row', { hasText: `Brüche ${tag}` });
      await expect(exam).toBeVisible();
      await expect(exam.locator('b')).toHaveText('Klassenarbeit Mathematik');
      await expect(exam.locator('.pv-ta-mark')).toHaveText('Ma');
      const other = page.locator('#pv_tests_agenda .pv-ta-row.pv-ta-other', { hasText: `Museum ${tag}` });
      await expect(other).toBeVisible();
      await expect(other.locator('small')).toContainText('bis ');
    } else {
      await expect(page.locator('#pv_tests_agenda')).toBeHidden();
      exam = page.locator('#calendar .fc-event.pv-t-exam', { hasText: `Brüche ${tag}` });
      await expect(exam).toBeVisible();
      await expect(page.locator('#calendar .fc-event.pv-t-other', { hasText: `Museum ${tag}` }).first()).toBeVisible();
      await expect(page.locator('#bu_pv_tests_manage')).toBeVisible();
    }
    // the test in the subject's colour, its text in the colour made for it
    const colours = await exam.evaluate((el: HTMLElement) => {
      const probe = document.createElement('div');
      probe.style.background = 'var(--subj-ma)';
      probe.style.color = 'var(--subj-ma-ink)';
      document.body.appendChild(probe);
      const want = getComputedStyle(probe);
      const target = el.classList.contains('pv-ta-row') ? el.querySelector('.pv-ta-mark')! : el.querySelector('.fc-event-main')!;
      const bg = getComputedStyle(el.classList.contains('pv-ta-row') ? target : el).backgroundColor;
      const result = { bg, ink: getComputedStyle(target).color, want_bg: want.backgroundColor, want_ink: want.color };
      probe.remove();
      return result;
    });
    expect(colours.bg).toBe(colours.want_bg);
    expect(colours.ink).toBe(colours.want_ink);

    // one's own entry opens the form
    await exam.click();
    const form = page.locator('#testModal');
    await expect(form).toBeVisible();
    await expect(form).toHaveClass(/pv-sheet/);
    await expect(form.locator('.modal-title')).toHaveText('Eintrag bearbeiten');
    await expect(page.locator('#ti_comment')).toHaveValue(`Brüche ${tag}`);
    // (on phones »Schließen« is only there for keyboards: the sheet is pulled down)
    await page.locator('#bu_close_test').evaluate((b: HTMLElement) => b.click());
    await expect(form).toBeHidden();

    // deleting asks in the dashboard's dialog
    const other = phone
      ? page.locator('#pv_tests_agenda .pv-ta-row', { hasText: `Museum ${tag}` })
      : page.locator('#calendar .fc-event', { hasText: `Museum ${tag}` }).first();
    await other.click();
    await expect(form).toBeVisible();
    await page.locator('#bu_delete_test').click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('.modal-body')).toHaveText('Möchtest du diesen Eintrag löschen?');
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    await expect(form).toBeHidden();
    await expect(page.locator(`text=Museum ${tag}`)).toHaveCount(0);
    ids.pop();

    // a new entry: the form with a date
    await page.locator('#bu_pv_tests_add').click();
    await expect(form).toBeVisible();
    await expect(form.locator('.modal-title')).toHaveText('Eintrag hinzufügen');
    await expect(page.locator('#ti_datum')).toHaveValue(/^\d{4}-\d\d-\d\d$/);
    await page.locator('#bu_discard_test').evaluate((b: HTMLElement) => b.click());
    await expect(form).toBeHidden();

    // back and forth, »Heute«
    const shown = await page.locator('#pv_tests_title').textContent();
    await page.locator('#bu_pv_tests_next').click();
    await expect(page.locator('#pv_tests_title')).not.toHaveText(shown!);
    await expect(page.locator('#bu_pv_tests_today')).toBeEnabled();
    await page.locator('#bu_pv_tests_prev').click();
    await expect(page.locator('#pv_tests_title')).toHaveText(shown!);

    // the class as a menu (a sheet on phones)
    await page.locator('#bu_pv_tests_klasse').click();
    const menu = page.locator('.pv-tests-menu');
    await expect(menu).toBeVisible();
    await expect(menu.locator('a.active')).toHaveText('5a');
    await expect(menu.locator('a', { hasText: '5b' })).toHaveAttribute('href', '/tests/5b');
    if (!phone) {
      await page.keyboard.press('Escape');
      await expect(menu).toHaveCount(0);
      await page.locator('#bu_pv_tests_klasse').click();
    }
    await menu.locator('a', { hasText: '5b' }).click();
    await page.waitForURL(/\/tests\/5b$/);
    await expect(page.locator('#bu_pv_tests_klasse')).toHaveText('Klasse 5b');
    await showMonthOf(page, day);
    await expect(page.locator(`text=Brüche ${tag}`)).toHaveCount(0);
  } finally {
    for (const id of ids) await page.request.post('/api/delete_test', { data: { id } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Someone who doesn't teach in the class sees the entries, but can't add
// any; someone else's entry opens as details, not as the form.
test('Neues Design: Klassenarbeiten für eine Lehrkraft ohne Unterricht in der Klasse', async ({ page, newUserPage }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the role check needs no second layout');
  test.setTimeout(120_000);
  const tag = Date.now().toString(36);
  const day = aheadWeekday();
  await login(page, ACCOUNTS.admin);
  const id = await saveTest(page, {
    klasse: '5a', datum: isoDate(day), end_datum: isoDate(day), fach: 'Nawi',
    kommentar: `Zellen ${tag}`, typ: 'LEK', public_for_klasse: 'no',
  });
  expect((await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'on' } })).status()).toBe(200);
  try {
    const teacher = await newUserPage();
    await login(teacher, ACCOUNTS.teacher);
    await teacher.goto('/tests/5a');
    await expect(teacher.locator('.pv-tests')).toBeVisible();
    await expect(teacher.locator('#bu_pv_tests_add')).toHaveCount(0);
    await expect(teacher.locator('#bu_pv_tests_manage')).toHaveCount(0);
    await showMonthOf(teacher, day);
    const entry = teacher.locator('#calendar .fc-event.pv-t-exam', { hasText: `Zellen ${tag}` });
    await entry.click();
    const details = teacher.locator('#showTestModal');
    await expect(details).toBeVisible();
    await expect(details.locator('.modal-title')).toHaveText('LEK Naturwissenschaften (5a)');
    await expect(details.locator('.pv-tests-fact')).toContainText([/Eingetragen von/, `Zellen ${tag}`, 'Nur für Lehrkräfte sichtbar']);
    await details.getByRole('button', { name: 'Schließen' }).click();
    await expect(details).toBeHidden();
    // a day: the dashboard's dialog explains why nothing can be added
    await teacher.locator('#calendar .fc-daygrid-day:not(.fc-day-other)').first().click({ position: { x: 20, y: 60 } });
    const dialog = dashboardDialog(teacher);
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('.modal-title')).toHaveText('Keine Berechtigung');
    await expect(dialog.locator('.modal-body')).toContainText('Du unterrichtest nicht in der Klasse 5a');
  } finally {
    await page.request.post('/api/delete_test', { data: { id } });
    await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'off' } });
  }
});
