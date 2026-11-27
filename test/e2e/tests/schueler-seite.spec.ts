import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// A student's page for teachers (/schueler/<id>, include/schueler_seite.rb):
// the search leads there. What the class list shows teachers, in one place,
// and the lessons with teachers and hours. Example data: Mallory Mustermann
// in 5a (class teacher Clarke), Alice Mustermann in 11.

async function open(page: Page, query: string, name: string) {
  // phones in the new design: the search at the top of »Mehr«
  if (await page.locator('#bu_quick_search').isVisible()) await page.locator('#bu_quick_search').click();
  else {
    await page.locator('#bu_pv_more').click();
    await page.locator('.pv-more-search').click();
  }
  await page.locator('#ti_quick_search').fill(query);
  const result = page.locator('.quick-search-row', { hasText: name });
  await expect(result.locator('.quick-search-main')).toHaveAttribute('href', /^\/schueler\/[a-z0-9]+$/);
  await result.locator('.quick-search-main').click();
  await page.waitForURL(/\/schueler\/[a-z0-9]+$/);
}

for (const preview of [false, true]) {
  test(`Schülerseite für Lehrkräfte${preview ? ' (neues Design)' : ''}: Angaben und Unterricht`, async ({ page }) => {
    // the new design: an account that may switch it on before 1 December
    await login(page, preview ? ACCOUNTS.admin : ACCOUNTS.teacher);
    if (preview) {
      await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
    }
    try {
      await page.goto('/');
      await expect(page.locator('body')).toHaveClass(preview ? /ui-preview/ : /^(?!.*ui-preview)/);
      await open(page, 'mallo', 'Mallory Mustermann');
      await expect(page.locator('.sp-head h2')).toHaveText('Mallory Mustermann');
      await expect(page.locator('.sp-sub')).toContainText('Klasse 5a');
      await expect(page.locator('.sp-sub')).toContainText('Klassenleitung');
      await expect(page.locator('.sp-facts dt')).toHaveText(['Geburtsdatum', 'Geschlecht', 'Bildungsgang', 'Stufe', 'E-Mail', 'E-Mail der Eltern', 'Alle Lehrkräfte', 'Letzter Zugriff']);
      if (preview) {
        // the new design's copy fields, the subjects as chips in their colour
        await expect(page.locator('.sp-facts .pv-copy')).toHaveCount(3);
        await expect(page.locator('.sp-facts .pv-copy').nth(1)).toContainText(/^eltern\./);
        await expect(page.locator('.sp-facts input')).toHaveCount(0);
        await expect(page.locator('.sp-lessons tbody tr .pv-dir-lk')).toHaveCount(await page.locator('.sp-lessons tbody tr').count());
      } else {
        await expect(page.locator('.sp-facts dd input').first()).toHaveValue(/^[^@\s]+@/);
        await expect(page.locator('.sp-facts dd input').nth(1)).toHaveValue(/^eltern\./);
        await expect(page.locator('.pv-dir-lk')).toHaveCount(0);
      }
      // the lessons: subject, teacher (to the teacher's timetable), hours
      const rows = page.locator('.sp-lessons tbody tr');
      expect(await rows.count()).toBeGreaterThan(0);
      await expect(rows.first().locator('td')).toHaveCount(4);
      await expect(page.locator('.sp-lessons tbody a[href^="/timetable/"]').first()).toBeVisible();
      // the lessons of the whole class lead to the class list, a course's to its own
      await expect(page.locator('.sp-lessons tbody td:nth-child(4) a').first()).toHaveAttribute('href', /^\/directory\//);
      // below 11: the list of the class's teachers
      const teachers = page.locator('.sp-facts dd').filter({ has: page.locator('.sp-hint') });
      await expect(teachers.locator('.sp-hint')).toHaveText(/^Verteiler an (die Lehrkraft|alle \d+ Lehrkräfte) der Klasse 5a$/);
      if (preview) await expect(teachers.locator('.pv-copy')).toContainText(/^lehrer\.5a@/);
      else await expect(teachers.locator('input')).toHaveValue(/^lehrer\.5a@/);
      // the lessons by lessons per week, most first
      const hours = (await page.locator('.sp-lessons tbody td.sp-num').allTextContents()).map((t) => parseInt(t, 10) || 0);
      expect(hours).toEqual([...hours].sort((a, b) => b - a));
      // the ways on: the timetable, the class list with the row marked
      const id = page.url().split('/').pop();
      await expect(page.locator('#bu_sp_timetable')).toHaveAttribute('href', `/timetable/${id}`);
      await page.locator('#bu_sp_klasse').click();
      await page.waitForURL(/\/directory\/5a#quick=/);
      await expect(page.locator('tr.quick-search-highlight')).toContainText('Mallory');
      // no horizontal scrolling of the page
      await page.goBack();
      await page.waitForURL(/\/schueler\//);
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      if (preview) {
        // the new class list: the student's dialog leads to the page
        await page.goto('/directory/5a');
        await page.locator('.pv-dir-row', { hasText: 'Mallory' }).locator('.pv-dir-name').click();
        await page.locator('#bu_dir_student_page').click();
        await page.waitForURL(new RegExp(`/schueler/${id}$`));
        await expect(page.locator('.sp-head h2')).toHaveText('Mallory Mustermann');
      }
    } finally {
      if (preview) await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    }
  });
}

test('Schülerseite in der Oberstufe: Leistungskurse, Tutor:in, Kurslisten', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  await page.goto('/');
  await open(page, 'alice', 'Alice Mustermann');
  await expect(page.locator('.sp-sub')).toContainText('Klasse 11');
  await expect(page.locator('.sp-facts dt')).toContainText(['Leistungskurse', 'Tutor:in', 'Alle Lehrkräfte']);
  // a list to everyone who teaches her: the address, how many it reaches
  const list = page.locator('.sp-facts dd').filter({ has: page.locator('.sp-hint') });
  await expect(list.locator('input')).toHaveValue(/^lehrer\.alice\.mustermann@/);
  await expect(list.locator('.sp-hint')).toHaveText(/^Verteiler an (die Lehrkraft, die Alice unterrichtet|die \d+ Lehrkräfte, die Alice unterrichten)/);
  const address = await list.locator('input').inputValue();
  // not in the overview of all lists
  await page.goto('/mailing_lists');
  await expect(page.locator('body')).not.toContainText(address);
  await page.goBack();
  // in 11 every lesson is a course with its own list
  const groups = page.locator('.sp-lessons tbody tr td:nth-child(4) a');
  expect(await groups.count()).toBeGreaterThan(0);
  await expect(groups.first()).toHaveAttribute('href', /^\/directory\//);
});

test('Schülerseite nur für Lehrkräfte: Schüler:innen und Abgemeldete bekommen nichts zu sehen', async ({ page, browser }) => {
  await login(page, ACCOUNTS.teacher);
  await page.goto('/schueler/doesnotexist');
  await expect(page.locator('.sp-page')).toContainText('Diese Seite gibt es nicht');
  // a teacher's id is no student's page
  await page.goto('/');
  await page.locator('#bu_quick_search').click();
  await page.locator('#ti_quick_search').fill('cl');
  const href = await page.locator('.quick-search-row', { hasText: 'Clarke' }).first().locator('.quick-search-main').getAttribute('href');
  await page.goto(href!.replace('/timetable/', '/schueler/'));
  await expect(page.locator('.sp-page')).toContainText('Diese Seite gibt es nicht');

  // a real student's page: the id of Mallory (5a) and of Alice (11)
  const ids: Record<string, string> = {};
  for (const [q, name] of [['mallo', 'Mallory Mustermann'], ['alice', 'Alice Mustermann']]) {
    await page.goto('/');
    await page.locator('#bu_quick_search').click();
    await page.locator('#ti_quick_search').fill(q);
    const h = await page.locator('.quick-search-row', { hasText: name }).locator('.quick-search-main').getAttribute('href');
    ids[name] = h!.split('/').pop()!;
  }

  // students: redirected before anything is shown, neither a classmate's
  // page nor their own, nor someone's from another year
  const context = await browser.newContext();
  const student = await context.newPage();
  await login(student, ACCOUNTS.schueler); // Max, 5a
  await student.goto('/');
  const own = await student.evaluate(() => (window as any).timetable_id as string);
  expect(own).toMatch(/^[a-z0-9]+$/);
  expect(Object.values(ids)).not.toContain(own);
  for (const id of [ids['Mallory Mustermann'], ids['Alice Mustermann'], own, 'doesnotexist']) {
    const r = await student.request.get(`/schueler/${id}`, { maxRedirects: 0 });
    expect(r.status(), id).toBe(303);
    const body = await r.text();
    for (const leak of ['Mustermann', 'Geburtsdatum', 'eltern.', 'sp-facts', 'Unterricht']) {
      expect(body, `${id}: ${leak}`).not.toContain(leak);
    }
    await student.goto(`/schueler/${id}`);
    await expect(student).not.toHaveURL(/\/schueler\//);
    await expect(student.locator('.sp-page')).toHaveCount(0);
  }
  await context.close();

  // not logged in at all: the same
  const anonymous = await browser.newContext();
  const r = await anonymous.request.get(`/schueler/${ids['Alice Mustermann']}`, { maxRedirects: 0 });
  expect([302, 303]).toContain(r.status());
  expect(await r.text()).not.toContain('Mustermann');
  await anonymous.close();
});
