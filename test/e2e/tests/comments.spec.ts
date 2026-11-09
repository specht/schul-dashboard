import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';
import zlib from 'zlib';

const LESSON = 'Ma_5a';

function isoWeek(d: Date) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t.getTime() - yearStart.getTime()) / 86400000 + 1) / 7);
  return `${t.getUTCFullYear()}-${String(week).padStart(2, '0')}`;
}

// The lessons of LESSON in the student's timetable files of the next weeks:
// offset → text comments for the student (as the timetable shows them).
async function lessonComments(student: Page, id: string) {
  const result = new Map<number, string[]>();
  for (let w = 0; w < 3; w++) {
    const yw = isoWeek(new Date(Date.now() + w * 7 * 86400000));
    const r = await student.request.get(`/gen/w/${id}/${yw}.json.gz`);
    if (r.status() !== 200) continue;
    const data = JSON.parse(zlib.gunzipSync(await r.body()).toString('utf8'));
    for (const e of data.events) {
      if (e.lesson_key !== LESSON || typeof e.lesson_offset !== 'number') continue;
      const comments = ((e.per_user || {}).text_comments || []).map((c: { comment: string }) => c.comment);
      result.set(e.lesson_offset, comments);
    }
  }
  return result;
}

// Inserting a lesson in the course planning moves everything after it – the
// comments to students too (before, they stayed at their old place and ended
// up at another lesson).
test('Kommentar wandert mit, wenn davor eine Stunde eingefügt wird', async ({ page, newUserPage }) => {
  const text = `Gut gemacht ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin); // teaches Ma 5a
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  await student.goto('/');
  const id = await student.evaluate(() => (window as any).timetable_id as string);

  const offsets = [...(await lessonComments(student, id)).keys()].sort((a, b) => a - b);
  const k = offsets.find((o) => offsets.includes(o + 1));
  expect(k, 'two consecutive lessons in the next weeks').toBeDefined();

  const published = await page.request.post('/api/publish_text_comment', {
    data: { lesson_key: LESSON, schueler: ACCOUNTS.schueler, lesson_offset: k, comment: text },
  });
  expect(published.status()).toBe(200);
  await expect.poll(async () => (await lessonComments(student, id)).get(k!), { timeout: 30_000 }).toContain(text);

  const inserted = await page.request.post('/api/insert_lesson', { data: { lesson_key: LESSON, offset: k, shift: 1 } });
  expect(inserted.status()).toBe(200);
  await expect.poll(async () => {
    const c = await lessonComments(student, id);
    return [c.get(k!)?.includes(text), c.get(k! + 1)?.includes(text)];
  }, { timeout: 30_000 }).toEqual([false, true]);

  // undo: delete the inserted (empty) lesson – the comment moves back
  const deleted = await page.request.post('/api/delete_lessons', { data: { lesson_key: LESSON, offsets: [k] } });
  expect(deleted.status()).toBe(200);
  await expect.poll(async () => (await lessonComments(student, id)).get(k!), { timeout: 30_000 }).toContain(text);
});
