import type { Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, displayedSchoolWeek } from './fixtures';

// Neues Design: the course book (/lessons/<course>) and the
// Klassenarbeitskalender (/tests, include/tests.rb) together. A lesson on a
// day with a test of the course's class shows it – the course's own subject
// in the accent, the class's other subjects quietly – and the pane of a
// lesson enters a new test for that day, which lands in the calendar. The
// admin (Clarke) teaches Mathematik and Naturwissenschaften in 5a.

function weekRow(page: Page) {
  const week = displayedSchoolWeek();
  const short = week.map((d) => `${d.getDate()}.${d.getMonth() + 1}.`);
  return page.locator('tr.lesson').filter({
    has: page.locator('.pv-kb-day', { hasText: new RegExp(`(${short.map((s) => s.replace(/\./g, '\\.')).join('|')})$`) }),
  }).first();
}

type Event = { title: string; extendedProps: { type: string; test?: { id: string; kommentar: string; public_for_klasse: string; datum: string } } };

async function testsOf(page: Page, datum: string) {
  const start = new Date(new Date(datum + 'T12:00:00').getTime() - 7 * 86400000).toISOString().slice(0, 10);
  const r = await page.request.post('/api/get_tests', { data: { start_date: start, klasse: '5a' } });
  return ((await r.json()).events as Event[]).filter((e) => e.extendedProps.type === 'test');
}

test('Neues Design: Kursbuch zeigt Klassenarbeiten und trägt sie in den Kalender ein', async ({ page }) => {
  test.setTimeout(90_000);
  const stamp = Date.now().toString(36);
  const comment = `Brüche ${stamp}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  let datum = '';
  try {
    await page.goto('/lessons/Ma_5a');
    const row = weekRow(page);
    await expect(row).toBeVisible();
    datum = await row.evaluate((tr) => (window as any).time_span_for_lesson_offset[(window as any).$(tr).data('lesson_offset')].datum as string);
    expect(datum).toMatch(/^\d{4}-\d{2}-\d{2}$/);

    // another subject's test in the class that day: quiet, with subject and who
    const other = await page.request.post('/api/save_test', {
      data: { klasse: '5a', datum, end_datum: datum, fach: 'Nawi', kommentar: '', typ: 'LEK', public_for_klasse: 'no' },
    });
    expect(other.status()).toBe(200);
    await page.reload();
    await expect(weekRow(page).locator('.pv-kb-test-other')).toHaveText('In der Klasse: LEK Naturwissenschaften (Cl)');
    await expect(weekRow(page).locator('.pv-kb-test')).toHaveCount(0);

    // the lesson's pane: the day's tests and »Klassenarbeit eintragen«
    await weekRow(page).locator('.pv-kb-day').click();
    const box = page.locator('.pv-kb-tests-pane');
    await expect(box).toBeVisible();
    await expect(box.locator('.pv-kb-tests-row')).toHaveCount(1);
    await expect(box.locator('.pv-kb-tests-row')).toContainText('LEK Naturwissenschaften (Cl)');
    await expect(box.locator('.pv-kb-tests-link')).toHaveAttribute('href', '/tests/5a');
    await box.locator('#bu_kb_test_add').click();
    const modal = page.locator('#kbTestModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('#ti_kb_test_typ')).toHaveValue('KA');
    // one class: no choice of class
    await expect(modal.locator('#ti_kb_test_klasse')).toBeHidden();
    await modal.locator('#ti_kb_test_comment').fill(comment);
    await modal.locator('#ti_kb_test_public').check();
    await modal.locator('#bu_kb_test_save').click();
    await expect(modal).toBeHidden();

    // the row and the pane show it at once, in the accent
    await expect(weekRow(page).locator('.pv-kb-test')).toHaveText(`Klassenarbeit: ${comment}`);
    await expect(box.locator('.pv-kb-tests-own')).toContainText(`Klassenarbeit: ${comment}`);

    // and it is in the calendar: the course's subject, the day, visible for the class
    const tests = await testsOf(page, datum);
    const mine = tests.find((e) => e.extendedProps.test?.kommentar === comment);
    expect(mine, JSON.stringify(tests.map((e) => e.title))).toBeTruthy();
    expect(mine!.title).toBe(`KA Ma (Cl) – ${comment}`);
    expect(mine!.extendedProps.test!.datum).toBe(datum);
    expect(mine!.extendedProps.test!.public_for_klasse).toBe('yes');

    // after a reload as well
    await page.reload();
    await expect(weekRow(page).locator('.pv-kb-test')).toHaveText(`Klassenarbeit: ${comment}`);
  } finally {
    if (datum) {
      for (const e of await testsOf(page, datum)) {
        const t = e.extendedProps.test!;
        if (t.datum === datum && (t.kommentar === comment || e.title.startsWith('LEK Nawi'))) {
          await page.request.post('/api/delete_test', { data: { id: t.id } });
        }
      }
    }
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Kursbuch: die Klassenarbeiten des Kurses nur für die, die das Kursbuch führen', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  const r = await page.request.post('/api/lesson_tests', { data: { lesson_key: 'Ma_5a' } });
  expect(r.status()).not.toBe(200);
});
