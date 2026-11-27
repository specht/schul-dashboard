import { test, expect, login, ACCOUNTS } from './fixtures';
import { untisZip, type Lesson } from './untis-zip';

// The timetable on /datenpflege: the Untis export (teacher and class
// timetables as a ZIP) uploaded with the day it applies from, compared with
// the timetable valid until then, applied as stundenplan/<day>.zip and, as a
// plan still to come, deleted again. The example timetable (5a, 11, 12 with
// Clarke, Nawi with Fr – test/prepare_example_data.rb) with a few changes.

const L = (klasse: string, lehrer: string, fach: string, raum: string, dow: number, stunde: number): Lesson =>
  ({ klasse, lehrer, fach, raum, dow, stunde });

const EXAMPLE: Lesson[] = [
  ...[[2, 4], [2, 5], [3, 6], [4, 1], [5, 1]].map(([d, s]) => L('5a', 'Cl', 'Ma', '108', d, s)),
  L('5a', 'Cl', 'Nawi', '317', 2, 6), L('5a', 'Cl', 'Nawi', '317', 2, 7),
  L('5a', 'Cl', 'Nawi', '323', 4, 2), L('5a', 'Cl', 'Nawi', '323', 4, 3),
  ...[[1, 2], [1, 3], [3, 2], [3, 3], [5, 8]].flatMap(([d, s]) => [L('11', 'Cl', 'LA-L108', '129', d, s), L('12', 'Cl', 'LA-L108', '129', d, s)]),
  L('5a', 'Fr', 'Nawi', '317', 1, 3),
];

// a far day: nothing else in the test stack sees the plan before it goes again
const DAY = '2099-01-05';

test('Datenpflege: Stundenplan aus Untis hochladen, vergleichen, übernehmen, als geplanten löschen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'one data repository for everybody');
  test.setTimeout(90_000);
  await login(page, ACCOUNTS.admin);
  await page.goto('/datenpflege');
  const section = page.locator('.dp-stundenplan');
  await expect(section.locator('h4')).toHaveText('Stundenplan');

  // not a ZIP: said, nothing to apply
  await section.locator('#ti_sp_file').setInputFiles({ name: 'plan.txt', mimeType: 'text/plain', buffer: Buffer.from('kein zip') });
  await expect(section.locator('#dp_sp_message')).toContainText('keine ZIP-Datei');
  await expect(section.locator('#dp_sp_apply')).toBeHidden();

  // the example with a room changed, a lesson gone, two new (one by a
  // teacher the dashboard doesn't know) and a break duty
  const changed = EXAMPLE
    .filter((l) => !(l.fach === 'Nawi' && l.dow === 4 && l.stunde === 3))
    .map((l) => (l.fach === 'Ma' && l.dow === 2 && l.stunde === 4 ? { ...l, raum: '109' } : l))
    .concat([L('5a', 'Fr', 'Ku', '205', 1, 5), L('5a', 'Xy', 'Mu', '210', 5, 6)]);
  await section.locator('#ti_sp_date').fill(DAY);
  await section.locator('#ti_sp_file').setInputFiles({
    name: 'untis.zip', mimeType: 'application/zip',
    buffer: untisZip(changed, [{ where: 'Haupteingang', lehrer: 'Cl', dow: 1, stunde: 1 }, { where: 'Hof', lehrer: 'Fr', dow: 2, stunde: 3 }]),
  });
  const preview = section.locator('#dp_sp_preview');
  await expect(preview.locator('.dp-sp-changes')).toContainText('1 geändert, 2 neu, 1 entfallen');
  await expect(preview.locator('.dp-sp-unknown')).toContainText('Xy');
  const klasse = preview.locator('.dp-sp-klasse[data-klasse="5a"]');
  await expect(klasse.locator('summary')).toContainText('4');
  await klasse.locator('summary').click();
  await expect(klasse.locator('tr', { hasText: 'Di 4.' })).toContainText('108');
  await expect(klasse.locator('tr', { hasText: 'Di 4.' })).toContainText('109');
  await expect(klasse.locator('tr', { hasText: 'Do 3.' })).toContainText('entfällt');
  await expect(klasse.locator('tr', { hasText: 'Mo 5.' })).toContainText('Ku Fr 205');
  // 11 and 12 as they were
  await expect(preview.locator('.dp-sp-klasse[data-klasse="11"], .dp-sp-klasse[data-klasse="12"]')).toHaveCount(0);
  await expect(preview.locator('.dp-sp-aufsichten')).toContainText('Hof');

  // applied: a plan for that day, then deleted before it applies
  let deleted = false;
  try {
    await section.locator('#bu_sp_apply').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Übernehmen' }).click();
    const plan = page.locator('.dp-sp-plans tr[data-date="' + DAY + '"]');
    await expect(plan).toContainText('geplant');
    await expect(plan).toContainText(`${DAY}.zip`);
    await page.locator('.dp-sp-plans summary').click();
    await plan.locator('.bu_sp_delete').click();
    await page.locator('.modal.show').getByRole('button', { name: 'Löschen' }).click();
    await expect(page.locator('.dp-sp-plans tr[data-date="' + DAY + '"]')).toHaveCount(0);
    deleted = true;
  } finally {
    if (!deleted) await page.request.post('/api/datenpflege/stundenplan/delete', { data: { date: DAY } });
  }
});

test('Stundenplan hochladen nur mit der Rolle', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  const r = await page.request.post('/api/datenpflege/stundenplan/upload', { data: { filename: 'x.zip', content: '', date: DAY } });
  expect(r.ok()).toBe(false);
  const d = await page.request.post('/api/datenpflege/stundenplan/delete', { data: { date: DAY } });
  expect(d.ok()).toBe(false);
});
