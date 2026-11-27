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
      await expect(page.locator('.sp-facts dt')).toHaveText(['Geburtsdatum', 'Geschlecht', 'Bildungsgang', 'Stufe', 'E-Mail', 'E-Mail der Eltern', 'Letzter Zugriff']);
      if (preview) {
        // the new design's copy fields, the subjects as chips in their colour
        await expect(page.locator('.sp-facts .pv-copy')).toHaveCount(2);
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
  await expect(page.locator('.sp-facts dt')).toContainText(['Leistungskurse', 'Tutor:in']);
  // in 11 every lesson is a course with its own list
  const groups = page.locator('.sp-lessons tbody tr td:nth-child(4) a');
  expect(await groups.count()).toBeGreaterThan(0);
  await expect(groups.first()).toHaveAttribute('href', /^\/directory\//);
});

test('Schülerseite nur für Lehrkräfte, unbekannte Seiten sagen es', async ({ page, browser }) => {
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

  const context = await browser.newContext();
  const student = await context.newPage();
  await login(student, ACCOUNTS.schueler);
  await student.goto('/schueler/doesnotexist');
  await expect(student).not.toHaveURL(/\/schueler\//);
  await context.close();
});
