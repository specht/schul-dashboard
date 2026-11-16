import { test, expect, login, ACCOUNTS } from './fixtures';

// The search in the navigation bar: teachers find students (with their
// class), teachers, classes, courses and the pages of their own menu.
// Example data: Max, Elli and Mallory Mustermann are in 5a (class teacher
// Clarke, Cl), Alice in 11; Torstenson (Ts) teaches but leads no class.

test('Lehrkraft findet die Klasse einer Schülerin und landet bei ihr in der Klassenliste', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  await page.locator('#bu_quick_search').click();
  const input = page.locator('#ti_quick_search');
  await expect(input).toBeFocused();
  await input.fill('mallo');
  const result = page.locator('.quick-search-row', { hasText: 'Mallory Mustermann' });
  await expect(result).toContainText('Klasse 5a');
  // nobody else matches
  await expect(page.locator('.quick-search-row')).toHaveCount(1);
  await result.locator('.quick-search-main').click();
  await page.waitForURL(/\/directory\/5a#quick=/);
  const row = page.locator('tr.user_row.quick-search-highlight');
  await expect(row).toHaveCount(1);
  await expect(row).toContainText('Mallory');
  await expect(row).toBeInViewport();
});

test('Suche mit der Tastatur: Klassen, Kürzel und Namensanfänge', async ({ page, isMobile }) => {
  test.skip(isMobile, 'keyboard shortcut');
  await login(page, ACCOUNTS.teacher);
  await page.keyboard.press('/');
  const input = page.locator('#ti_quick_search');
  await expect(input).toBeFocused();
  const rows = page.locator('.quick-search-row');
  // the panel tells about the key
  await expect(page.locator('.quick-search-tip kbd')).toHaveText('/');
  await expect(page.locator('.quick-search-keys kbd', { hasText: '/' })).toBeVisible();

  // a class comes before its students
  await input.fill('5a');
  await expect(rows.first()).toContainText('Klasse 5a');
  await expect(rows.first()).toContainText('Klassenleitung Cl');

  // an exact Kürzel comes first; teachers link to their timetable
  await input.fill('cl');
  await expect(rows.first()).toContainText('Clarke');
  await expect(rows.first().locator('.quick-search-main')).toHaveAttribute('href', /^\/timetable\//);

  // the beginnings of several words, case and umlauts don't matter
  await input.fill('MUS ALÍ');
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('Alice Mustermann');
  await expect(rows.first()).toContainText('Klasse 11');

  // arrow keys choose, Enter opens, Escape closes
  await input.fill('muster');
  await expect(rows.first()).toHaveClass(/active/);
  await input.press('ArrowDown');
  await expect(rows.nth(1)).toHaveClass(/active/);
  await input.press('Escape');
  await expect(page.locator('#quick_search_panel')).toBeHidden();
  await page.keyboard.press('/');
  await input.fill('alice');
  await input.press('Enter');
  await page.waitForURL(/\/directory\/11#quick=/);
  await expect(page.locator('tr.quick-search-highlight')).toContainText('Alice');

});

test('Die Suche findet auch die Seiten aus dem eigenen Menü', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  await page.locator('#bu_quick_search').click();
  await page.locator('#ti_quick_search').fill('live anm');
  const result = page.locator('.quick-search-row', { hasText: 'Live-Anmeldungen' });
  await expect(result).toContainText('Administration');
  await result.locator('.quick-search-main').click();
  await page.waitForURL(/\/show_all_login_codes/);

  // a teacher without the admin menu doesn't get the admin pages
  const teacher = await newUserPage();
  await login(teacher, ACCOUNTS.teacher);
  await teacher.locator('#bu_quick_search').click();
  await teacher.locator('#ti_quick_search').fill('live anm');
  await expect(teacher.locator('.quick-search-empty')).toBeVisible();
  await expect(teacher.locator('.quick-search-row')).toHaveCount(0);
});

test('Schüler:innen haben keine Personensuche', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  await expect(page.locator('#navbarDropdownProfile')).toBeAttached();
  await expect(page.locator('#bu_quick_search')).toHaveCount(0);
  expect((await page.request.get('/api/quick_search_index')).status()).not.toBe(200);
});

// Phones: the search shows its icon only. With a wide font (Riffic, one
// of the fonts users can choose) the menu button wrapped into a second row.
// Riffic isn't in the repository (commercial), so longer school names stand
// in for the wider text: then the name next to the logo goes.
test('Auf dem Handy bleiben Logo, Suche und Menü-Knopf in einer Zeile', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  const toggler = page.locator('.navbar-toggler');
  const search = page.locator('#bu_quick_search');
  const label = page.locator('.nav-quick-search-label');
  const brand = page.locator('.brand-brand');
  const setup = async (width: number, name: string) => {
    await page.setViewportSize({ width, height: 800 });
    await brand.evaluate((el, n) => { el.innerHTML = '&nbsp;&nbsp;' + n; window.dispatchEvent(new Event('resize')); }, name);
    const t = (await toggler.boundingBox())!;
    const s = (await search.boundingBox())!;
    expect(t.x + t.width).toBeLessThanOrEqual(width);
    // menu button and search in the same row
    expect(Math.abs((t.y + t.height / 2) - (s.y + s.height / 2))).toBeLessThan(t.height / 2);
  };
  // the icon only
  await setup(412, 'Beispielschule');
  await expect(label).toBeHidden();
  await expect(search).toHaveAttribute('title', /.+/);
  await expect(brand).toBeVisible();
  await setup(412, 'Gymnasium am Stadtpark');
  await expect(label).toBeHidden();
  await expect(brand).toBeVisible();
  // far too long: the logo alone
  await setup(320, 'Sehr lange Beispielschule am Stadtpark');
  await expect(label).toBeHidden();
  await expect(brand).toBeHidden();
  // back to a wider phone: the name again
  await setup(600, 'Beispielschule');
  await expect(label).toBeHidden();
  await expect(brand).toBeVisible();
  // larger screens: with the label
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.evaluate(() => window.dispatchEvent(new Event('resize')));
  await expect(label).toBeVisible();
});
