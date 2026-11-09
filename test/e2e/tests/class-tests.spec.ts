import { test, expect, login, ACCOUNTS, isoDate } from './fixtures';
import type { Page } from '@playwright/test';
import zlib from 'zlib';

function isoWeek(d: Date) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-${String(Math.ceil(((t.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)).padStart(2, '0')}`;
}

// the student's timetable file of the week of `day`, as text
async function weekFile(student: Page, id: string, day: Date) {
  const r = await student.request.get(`/gen/w/${id}/${isoWeek(day)}.json.gz`);
  return r.status() === 200 ? zlib.gunzipSync(await r.body()).toString('utf8') : '';
}

// A class test moved to another class disappears from the old class's
// timetables (before, it stayed there until the timetable service restarted).
test('Klassenarbeit verschwindet aus der alten Klasse, wenn die Klasse geändert wird', async ({ page, newUserPage }) => {
  // the timetable shows class tests as "<typ> (<fach>)"
  const typ = `KA-${Date.now().toString(36)}`;
  const marker = `"title":"${typ} (Ma)"`;
  const day = new Date(Date.now() + 2 * 86400000);
  const data = {
    klasse: '5a', datum: isoDate(day), end_datum: isoDate(day), fach: 'Ma',
    kommentar: 'Bruchrechnung', typ, public_for_klasse: 'yes',
  };
  await login(page, ACCOUNTS.admin);
  const saved = await page.request.post('/api/save_test', { data });
  expect(saved.status()).toBe(200);
  const id = (await saved.json()).test.tid as string;

  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler); // 5a
  await student.goto('/');
  const timetableId = await student.evaluate(() => (window as any).timetable_id as string);
  await expect.poll(() => weekFile(student, timetableId, day), { timeout: 30_000 }).toContain(marker);

  const updated = await page.request.post('/api/update_test', { data: { ...data, id, klasse: '5b' } });
  expect(updated.status()).toBe(200);
  await expect.poll(() => weekFile(student, timetableId, day), { timeout: 30_000 }).not.toContain(marker);
});
