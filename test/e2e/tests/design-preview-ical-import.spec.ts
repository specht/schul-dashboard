import { test, expect, login, ACCOUNTS, dashboardDialog, displayedSchoolWeek, isoDate, showDayInTimetable } from './fixtures';
import type { Page } from '@playwright/test';

// An external calendar in one's own timetable (ical_import.rb,
// include/ical_import.rb, preview/ical_import.js): for people with the role
// can_import_ical (in the test stack the admin), in the new design only. The
// fake Nextcloud serves the feed (/cal/<name>.ics, allowed as a host in the
// test stack only); the timetable service fetches it right after saving.
// Imported appointments are only in the person's private week file – never
// in the public one, which colleagues see.

const NEXTCLOUD = 'http://localhost:8127';

function feed(tag: string, day: Date, extra: string[] = []) {
  const d = isoDate(day).replace(/-/g, '');
  return [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//test//DE', 'X-WR-CALNAME:Test-Kalender',
    'BEGIN:VEVENT', `UID:${tag}-1@test`,
    `DTSTART;TZID=Europe/Berlin:${d}T153000`, `DTEND;TZID=Europe/Berlin:${d}T163000`,
    `SUMMARY:UB ${tag} <b>fett</b>`, 'LOCATION:Gymnasium Beispiel\\, Hauptstraße 1',
    'DESCRIPTION:Termin der Fachbegleitung.', 'STATUS:CONFIRMED', 'END:VEVENT',
    'BEGIN:VEVENT', `UID:${tag}-2@test`,
    `DTSTART;TZID=Europe/Berlin:${d}T170000`, `DTEND;TZID=Europe/Berlin:${d}T180000`,
    `SUMMARY:Abgesagt: ${tag}`, 'STATUS:CANCELLED', 'END:VEVENT',
    ...extra,
    'END:VCALENDAR',
  ].join('\r\n') + '\r\n';
}

async function serveFeed(page: Page, name: string, text: string) {
  const r = await page.request.post(`${NEXTCLOUD}/_ical?name=${name}`, { data: text, headers: { 'content-type': 'text/calendar' } });
  expect(r.status()).toBe(200);
}

async function state(page: Page) {
  return (await page.request.post('/api/ical_import_state', { data: {} })).json();
}

test('Neues Design: ein externer Kalender erscheint im eigenen Stundenplan', async ({ page, browser }, testInfo) => {
  test.setTimeout(150_000);
  const desktop = testInfo.project.name === 'desktop';
  const tag = `k${Date.now().toString(36)}${desktop ? 'd' : 'm'}`;
  const thursday = displayedSchoolWeek()[3];
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await serveFeed(page, tag, feed(tag, thursday, [
      'BEGIN:VEVENT', `UID:${tag}-3@test`, `DTSTART;TZID=Europe/Berlin:20261130T080000`, 'DURATION:PT45M',
      'RRULE:FREQ=WEEKLY;COUNT=3', 'SUMMARY:Serie', 'END:VEVENT',
    ]));
    await page.goto('/profil');
    const box = page.locator('#ical_import');
    await expect(box.locator('h2')).toHaveText('Kalender einbinden');
    await expect(page.locator('#bu_ical_import_delete')).toBeHidden();
    await page.locator('#ti_ical_import_url').fill(`http://nextcloud/cal/${tag}.ics`);
    await page.locator('#bu_ical_import_save').click();
    // fetched right away: the host (never the whole secret address), the count
    await expect(box.locator('.pv-icim-state')).toContainText('Eingebunden: Kalender von nextcloud');
    await expect(box.locator('.pv-icim-state')).toContainText('1 Termin, zuletzt geholt heute', { timeout: 30_000 });
    await expect(box.locator('.pv-icim-state')).toContainText('Eine Terminserie wird noch nicht übernommen.');
    await expect(box).not.toContainText(`/cal/${tag}.ics`);
    await expect(page.locator('#ti_ical_import_url')).toHaveValue('');
    await expect(page.locator('#bu_ical_import_save')).toHaveText('Ersetzen');
    expect((await state(page)).host).toBe('nextcloud');

    if (desktop) {
      // the timetable: the appointment quietly in the week, its title as text
      const title = `UB ${tag} <b>fett</b>`;
      const event = page.locator('.fc-event.pv-ical', { hasText: title });
      await expect(async () => {
        await page.goto('/');
        await showDayInTimetable(page, thursday);
        await expect(event).toBeVisible({ timeout: 3000 });
      }).toPass({ timeout: 45_000 });
      await expect(page.locator('.fc-event', { hasText: `Abgesagt: ${tag}` })).toHaveCount(0);
      await expect(event.locator('b', { hasText: /^fett$/ })).toHaveCount(0);
      await event.click();
      const modal = page.locator('#lessonModal');
      await expect(modal).toBeVisible();
      await expect(modal).toContainText('Aus deinem Kalender »Test-Kalender«');
      await expect(modal).toContainText('Ort: Gymnasium Beispiel, Hauptstraße 1');
      await expect(modal.locator('.bu-edit-lesson')).toBeHidden();
      await page.keyboard.press('Escape');

      // only in the private week file (the one the page loads) …
      const read = (p: Page, id: string, week: string) => p.evaluate(async ([i, w]) => {
        const r = await fetch(`/gen/w/${i}/${w}.json.gz?${Date.now()}`);
        if (r.status !== 200) return '';
        const pako = (window as unknown as { pako: { ungzip: (b: Uint8Array, o: object) => string } }).pako;
        return pako.ungzip(new Uint8Array(await r.arrayBuffer()), { to: 'string' });
      }, [id, week] as const);
      const own = await page.evaluate(() => (window as unknown as { timetable_id: string }).timetable_id);
      expect(await read(page, own, isoWeek(thursday))).toContain('"event_type":"agenda"');
      // … never in the public one, which a colleague loads
      const context = await browser.newContext();
      const colleague = await context.newPage();
      await login(colleague, ACCOUNTS.teacher);
      await colleague.goto('/');
      const id = await colleague.locator('a.ttc-teacher', { hasText: /^Cl$/ }).first().getAttribute('data-id');
      expect(id).toBeTruthy();
      const pub = await read(colleague, id!, isoWeek(thursday));
      expect(pub).toContain('"events"');
      expect(pub).not.toContain('agenda');
      expect(pub).not.toContain(tag);
      await context.close();
    }

    // removing it: asked first, then gone
    await page.goto('/profil');
    await page.locator('#bu_ical_import_delete').click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toContainText('Kalender entfernen?');
    await dialog.getByRole('button', { name: 'Entfernen' }).click();
    await expect(page.locator('#bu_ical_import_delete')).toBeHidden();
    await expect(box.locator('.pv-icim-state')).toBeEmpty();
    expect((await state(page)).active).toBe(false);
  } finally {
    await page.request.post('/api/ical_import_delete', { data: {} });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

function isoWeek(d: Date) {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  return `${t.getUTCFullYear()}-${String(Math.ceil(((+t - +y) / 86400000 + 1) / 7)).padStart(2, '0')}`;
}

test('Kalender einbinden: nur mit der Rolle und nur im neuen Design', async ({ page, browser }) => {
  // the admin in the old design: no section
  await login(page, ACCOUNTS.admin);
  await page.goto('/profil');
  await expect(page.locator('#ical_import')).toHaveCount(0);
  // a teacher without the role, new design: no section, no answer
  const context = await browser.newContext();
  const teacher = await context.newPage();
  await login(teacher, ACCOUNTS.teacher);
  await teacher.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await teacher.goto('/profil');
    await expect(teacher.locator('#ical_import')).toHaveCount(0);
    const r = await teacher.request.post('/api/ical_import_set', { data: { url: 'http://nextcloud/cal/x.ics' } });
    expect(r.status()).not.toBe(200);
  } finally {
    await teacher.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await context.close();
  }
});
