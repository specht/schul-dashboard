import { test, expect, login, ACCOUNTS } from './fixtures';

// Neues Design: Admin (/admin, preview/admin.js). People by their full names
// (the shorthand quietly beside a teacher's name), one search above the
// lists of teachers, students and external users. The old design keeps its
// columns. Names are those of the example data.

test('Neues Design: Admin mit vollen Namen und Suche', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/admin');
    const teachers = page.locator('#teachers + div table');
    const students = page.locator('#sus + div table');
    // one name column: »Scott Clarke« with »Cl«, no Kürzel/Vorname columns
    const clarke = teachers.locator('tr.user_row', { hasText: 'Scott Clarke' });
    await expect(clarke.locator('td').first().locator('.pv-adm-name')).toHaveText('Scott Clarke');
    await expect(clarke.locator('td').first().locator('.pv-adm-short')).toHaveText('Cl');
    const heads = await teachers.locator('thead th').allTextContents();
    expect(heads[0]).toBe('Name');
    expect(heads).not.toContain('Vorname');
    expect(heads).not.toContain('Kürzel');
    await expect(students.locator('tr.user_row td .pv-adm-name', { hasText: 'Max Mustermann' })).toHaveCount(1);
    if (phone) {
      // list rows: the full name is the row's title
      expect(await clarke.locator('td').first().evaluate((td) => getComputedStyle(td).flexBasis)).toBe('100%');
      await expect(teachers.locator('thead')).toBeHidden();
    }
    // »Anmelden« calm, not yellow
    const bg = await clarke.locator('.btn-impersonate').evaluate((b) => getComputedStyle(b).backgroundColor);
    expect(bg).not.toBe('rgb(255, 193, 7)');

    // the search: name, over all lists
    const search = page.locator('#ti_admin_search');
    await expect(search).toBeVisible();
    await search.fill('clarke');
    await expect(teachers.locator('tr.user_row:visible')).toHaveCount(1);
    await expect(page.locator('#teachers .pv-adm-count')).toHaveText(/^1 von \d+$/);
    await expect(students.locator('tr.user_row:visible')).toHaveCount(0);
    await expect(page.locator('#sus ~ .pv-adm-none').first()).toBeVisible();
    // a class: its students, the other classes' headings gone
    await search.fill('klasse 5a');
    await expect(students.locator('tr.pv-adm-klasse:visible')).toHaveText(['Klasse 5a']);
    await expect(students.locator('tr.user_row:visible', { hasText: 'Max Mustermann' })).toHaveCount(1);
    await expect(teachers.locator('tr.user_row:visible')).toHaveCount(0);
    // the search stays reachable while scrolling down the long lists
    await page.locator('#external_users').scrollIntoViewIfNeeded();
    await expect(search).toBeInViewport();
    // Escape clears it: everyone again
    await search.press('Escape');
    await expect(search).toHaveValue('');
    expect(await students.locator('tr.user_row:visible').count()).toBeGreaterThan(5);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Admin ohne Vorschau: Kürzel, Name und Vorname wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/admin');
  await expect(page.locator('#ti_admin_search')).toHaveCount(0);
  const heads = await page.locator('#teachers + div table thead th').allTextContents();
  expect(heads.slice(0, 3)).toEqual(['Kürzel', 'Name', 'Vorname']);
});
