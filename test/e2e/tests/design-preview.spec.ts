import { chromium, type Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS, displayedSchoolWeek } from './fixtures';

// Neues Design (Vorschau): switched on in the profile – for now by admins only
// (UI_PREVIEW_FOR in include/design_preview.rb). Then the template loads the
// colour tokens from the colour scheme and the preview styles, and a button
// collects feedback (admins see it on /design_feedback).

const toggle = '.toggle:has(#ui_preview_switch)';

test('Neues Design: Admin schaltet die Vorschau ein, gibt Feedback, schaltet sie wieder aus', async ({ page }, testInfo) => {
  const marker = `Vorschau-Test ${testInfo.project.name} ${Date.now()}`;
  await login(page, ACCOUNTS.admin);
  // a leftover from an earlier run must not get in the way
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });

  await page.goto('/profil');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('#bu_design_feedback')).toHaveCount(0);
  await page.locator(toggle).click();
  await page.waitForLoadState('load');
  await expect(page.locator('body')).toHaveClass(/ui-preview/);
  // colours computed from the colour scheme
  expect(await page.locator('#design_tokens').textContent()).toMatch(/--acc: #[0-9a-f]{6};.*--subj-ma: #[0-9a-f]{6};/);

  // feedback, with the wish to be contacted – from the profile; the floating
  // button is hidden for now
  await expect(page.locator('#bu_design_feedback')).toBeHidden();
  await page.locator('#bu_profile_design_feedback').click();
  const dialog = page.locator('#designFeedbackModal');
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('#ti_design_feedback')).toHaveAttribute('placeholder', /gefällt dir/);
  // nothing is sent without text
  await dialog.locator('#bu_send_design_feedback').click();
  await expect(dialog.locator('.design-feedback-thanks')).toBeHidden();
  await dialog.locator('#ti_design_feedback').fill(marker);
  await dialog.locator('#ti_design_feedback_contact').check();
  await dialog.locator('#bu_send_design_feedback').click();
  await expect(dialog.locator('.design-feedback-thanks')).toBeVisible();
  // (phones: a sheet without »Schließen« – back closes it like every sheet;
  // the page puts its entry back at once, so no goBack, which would wait)
  if (testInfo.project.name === 'mobile') await page.evaluate(() => history.back());
  else await dialog.getByRole('button', { name: 'Schließen' }).click();
  await expect(dialog).toBeHidden();
  expect((await page.request.post('/api/design_feedback', { data: { text: 'x', page: '/', device: 'tablet' } })).status()).not.toBe(200);

  // switching back takes effect at once, without a question
  await page.goto('/profil');
  await page.locator(toggle).click();
  await page.waitForLoadState('load');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('#design_tokens')).toHaveCount(0);
  await expect(page.locator('#bu_design_feedback')).toHaveCount(0);

  // the feedback page lists it
  await page.goto('/design_feedback');
  const row = page.locator('.design-feedback-table tr', { hasText: marker });
  await expect(row).toContainText('Lehrkraft');
  await expect(row).toContainText('/profil');
  await expect(row).toContainText(ACCOUNTS.admin);
  await expect(page.locator('.design-feedback-counts')).toContainText('ausprobiert und wieder abgeschaltet');
});

test('Neues Design: vorerst nur für Admins', async ({ page, newUserPage }) => {
  for (const [who, account] of [['Lehrkraft', ACCOUNTS.teacher], ['Schüler', ACCOUNTS.schueler]]) {
    const user = who === 'Lehrkraft' ? page : await newUserPage();
    await login(user, account);
    await user.goto('/profil');
    await expect(user.locator('#ui_preview_switch')).toBeHidden();
    expect((await user.request.post('/api/set_ui_preview', { data: { mode: 'on' } })).status()).not.toBe(200);
    expect((await user.request.post('/api/design_feedback', { data: { text: 'x', page: '/', device: 'phone' } })).status()).not.toBe(200);
    // switching off is always possible
    expect((await user.request.post('/api/set_ui_preview', { data: { mode: 'off' } })).status()).toBe(200);
    await user.goto('/');
    await expect(user.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(user.locator('#bu_design_feedback')).toHaveCount(0);
    await user.goto('/design_feedback');
    await expect(user).not.toHaveURL(/design_feedback/);
  }
});

// Admins give the new design to single persons for testing (/design_feedback,
// »Testpersonen«): switched on at once, the person may switch it on and off
// like an admin; taking it back switches it off. Only admins may do that.
test('Neues Design: Admins geben es einzelnen Personen zum Testen', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  const student = await newUserPage();
  await login(student, ACCOUNTS.schueler);
  // not for students themselves
  expect((await student.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'on' } })).status()).not.toBe(200);
  try {
    await page.goto('/design_feedback');
    await page.locator('#ti_preview_tester').fill(ACCOUNTS.schueler);
    await page.locator('#bu_add_tester').click();
    await expect(page.locator('#pv_testers li', { hasText: 'eingeschaltet' })).toHaveCount(1);
    await student.goto('/');
    await expect(student.locator('body')).toHaveClass(/ui-preview/);
    // the person may switch it off and on again
    expect((await student.request.post('/api/set_ui_preview', { data: { mode: 'off' } })).status()).toBe(200);
    await student.goto('/');
    await expect(student.locator('body')).not.toHaveClass(/ui-preview/);
    expect((await student.request.post('/api/set_ui_preview', { data: { mode: 'on' } })).status()).toBe(200);
    await student.goto('/profil');
    await expect(student.locator('body')).toHaveClass(/ui-preview/);
    // taken back: off, and not to be switched on again
    await page.goto('/design_feedback');
    await page.locator('#pv_testers .bu-remove-tester').first().click();
    await page.locator('.modal.show').getByRole('button', { name: 'Entfernen' }).click();
    await expect(page.locator('#pv_testers_empty')).toBeVisible();
    await student.goto('/');
    await expect(student.locator('body')).not.toHaveClass(/ui-preview/);
    expect((await student.request.post('/api/set_ui_preview', { data: { mode: 'on' } })).status()).not.toBe(200);
  } finally {
    await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'off' } });
  }
});

// The colour sliders (Farbton, Sepia, Analog …) lay a filter over the whole
// page. The new design computes readable colours per scheme; a filter would
// undo that, so the preview shows the page without them.
test('Neues Design: ohne die Farbfilter aus den Farbeinstellungen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const reset = { hue: 0, saturation: 1.0, brightness: 1.0, contrast: 1.0, sepia: 0.0, analog: 0 };
  const filtered = { hue: 40, saturation: 1.4, brightness: 1.0, contrast: 0.8, sepia: 0.3, analog: 0.5 };
  expect((await page.request.post('/api/set_color_options', { data: filtered })).status()).toBe(200);
  try {
    const look = () => page.evaluate(() => ({
      filter: getComputedStyle(document.documentElement).filter,
      grain: getComputedStyle(document.documentElement).getPropertyValue('--analog-opacity').trim(),
    }));
    // today's design: the grain on every page (the other sliders only take
    // effect on the profile page while they are being moved)
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.goto('/');
    expect((await look()).grain).toBe('0.5');
    // the preview: no filter, no grain
    await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
    await page.goto('/');
    expect(await look()).toEqual({ filter: 'none', grain: '0' });
    await page.goto('/profil');
    // the sliders are left out entirely
    await expect(page.locator('#ti_hue')).toBeHidden();
    await expect(page.locator('h2', { hasText: 'Farbeinstellungen' })).toBeHidden();
    expect(await look()).toEqual({ filter: 'none', grain: '0' });
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.request.post('/api/set_color_options', { data: reset });
  }
});

// The new frame: the same navigation as a sidebar on larger screens, a tab
// bar with "Mehr" for the full menu on phones. Without the preview: as today.
test('Neues Design: Seitenleiste am Desktop, Tab-Leiste am Handy', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/messages');
  await expect(page.locator('.pv-tabbar')).toHaveCount(0);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/messages');
    const nav = page.locator('nav.navbar');
    if (!phone) {
      // a column along the left edge, the whole height, the page next to it
      const box = (await nav.boundingBox())!;
      const viewport = page.viewportSize()!;
      expect(box.x).toBe(0);
      expect(box.height).toBeGreaterThanOrEqual(viewport.height - 1);
      expect(box.width).toBeLessThan(300);
      const main = (await page.locator('#main_container').boundingBox())!;
      expect(main.x).toBeGreaterThanOrEqual(box.width - 1);
      // the page's panel keeps a margin to the window's edge (Bootstrap sizes it by the window)
      const panel = (await page.locator('#main_container .container').first().boundingBox())!;
      expect(panel.x + panel.width).toBeLessThanOrEqual(viewport.width - 16);
      await expect(page.locator('.pv-tabbar')).toBeHidden();
      // the current page is marked, the profile sits at the bottom
      await expect(nav.locator('.nav-link.pv-active')).toContainText('Nachrichten');
      const profile = (await page.locator('#navbarDropdownProfile').boundingBox())!;
      expect(profile.y).toBeGreaterThan(viewport.height / 2);
      // the search right above the profile
      const search = (await page.locator('#bu_quick_search').boundingBox())!;
      expect(search.y).toBeGreaterThan(viewport.height / 2);
      expect(search.y).toBeLessThan(profile.y);
      expect(profile.y - (search.y + search.height)).toBeLessThan(30);
      // the profile menu opens upwards, its bottom level with the sidebar's
      await page.locator('#navbarDropdownProfile').click();
      const profileMenu = nav.locator('[aria-labelledby="navbarDropdownProfile"]');
      await expect(profileMenu).toBeVisible();
      await page.waitForTimeout(100);
      const pm = (await profileMenu.boundingBox())!;
      expect(pm.x).toBeGreaterThanOrEqual(box.width - 1);
      expect(Math.abs(viewport.height - (pm.y + pm.height) - 8)).toBeLessThan(3);
      // its icons and one's picture at full strength (only the long lists of
      // courses and groups have quieter icons)
      expect(await profileMenu.locator('.dropdown-item .icon').evaluateAll((els) => els.map((el) => getComputedStyle(el).opacity))).not.toContain('0.6');
      await page.keyboard.press('Escape');
      await expect(profileMenu).toBeHidden();
      // the old admin menu is gone: its tools sit in the "Verwaltung" section,
      // one entry that opens as a panel beside the sidebar, like the menus
      await expect(page.locator('#navbarDropdownAdmin')).toBeHidden();
      const verwaltung = nav.locator('.pv-nav-section[data-section="verwaltung"]');
      await expect(verwaltung.locator('.pv-nav-body')).toBeHidden();
      await verwaltung.locator('button.pv-nav-heading').click();
      await expect(verwaltung.locator('a.pv-nav-entry[href="/admin"]')).toBeVisible();
      const vp = (await verwaltung.locator('.pv-nav-body').boundingBox())!;
      expect(vp.x).toBeGreaterThanOrEqual(box.width - 1);
      expect(vp.y + vp.height).toBeLessThanOrEqual(viewport.height);
      await page.keyboard.press('Escape');
      await expect(verwaltung.locator('.pv-nav-body')).toBeHidden();
      // menus open as a panel next to the sidebar, inside the window above
      // the footer (in columns, or scrolling where even that is too long);
      // the sidebar itself never scrolls
      // (the old footer is hidden in the new design; its line is in the sidebar)
      const footHeight = (await page.locator('.foot').boundingBox())?.height ?? 0;
      const groupsMenu = nav.locator('[aria-labelledby="navbarDropdownKlassen"]');
      for (const height of [viewport.height, 420]) {
        await page.setViewportSize({ width: viewport.width, height });
        await page.locator('#navbarDropdownKlassen').click();
        await expect(groupsMenu).toBeVisible();
        await page.waitForTimeout(100);
        const panel = (await groupsMenu.boundingBox())!;
        expect(panel.x).toBeGreaterThanOrEqual(box.width - 1);
        expect(panel.y).toBeGreaterThanOrEqual(0);
        expect(panel.y + panel.height).toBeLessThanOrEqual(height - footHeight + 1);
        expect(await groupsMenu.evaluate((el) => el.scrollHeight <= el.clientHeight + 1 || ['auto', 'scroll'].includes(getComputedStyle(el).overflowY))).toBe(true);
        if (height === 420) break;
        expect(await nav.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
        await page.keyboard.press('Escape');
        await expect(groupsMenu).toBeHidden();
      }
      // long names wrap instead of being cut off
      expect(await groupsMenu.locator('.dropdown-item').evaluateAll((els) => els.every((el) => el.scrollWidth <= el.clientWidth + 1))).toBe(true);
    } else {
      const tabs = page.locator('.pv-tabbar');
      await expect(tabs).toBeVisible();
      await expect(tabs.locator('.pv-tab.pv-active')).toContainText('Nachrichten');
      await expect(page.locator('.navbar-toggler')).toBeHidden();
      // "Mehr" opens the whole menu and closes it again
      const menu = page.locator('#navbarTogglerDemo02');
      await expect(menu).toBeHidden();
      await tabs.locator('#bu_pv_more').click();
      await expect(menu).toHaveClass(/\bshow\b/);
      await expect(menu).toContainText('Administration');
      await tabs.locator('#bu_pv_more').click();
      await expect(menu).toBeHidden();
      // like the lesson sheet: a veil behind it; pulled down, it closes
      await tabs.locator('#bu_pv_more').click();
      await expect(menu).toHaveClass(/\bshow\b/);
      await expect(page.locator('.pv-menu-veil')).toBeVisible();
      const sheet = (await menu.boundingBox())!;
      // the sheet lies above the veil, not under it
      await page.waitForTimeout(350);
      expect(await page.evaluate(([x, y]) => !!document.elementFromPoint(x, y)!.closest('#navbarTogglerDemo02'), [sheet.x + sheet.width / 2, sheet.y + 30])).toBe(true);
      const cdp = await page.context().newCDPSession(page);
      const x = sheet.x + sheet.width / 2, y = sheet.y + 8;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      for (let i = 1; i <= 8; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y + i * 25 }] });
        await page.waitForTimeout(30);
      }
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await expect(menu).toBeHidden();
      await expect(page.locator('.pv-menu-veil')).toBeHidden();
      // teachers: Heute, Woche, Nachrichten, Unterricht, Mehr (as in the mockups)
      await expect(tabs.locator('.pv-tab')).toHaveText(['Heute', 'Woche', 'Nachrichten', 'Unterricht', 'Mehr']);
      // the search: at the top of "Mehr" (no icon in the top bar)
      await expect(page.locator('.nav-quick-search-nav .nav-quick-search')).toBeHidden();
      await tabs.locator('#bu_pv_more').click();
      await page.locator('.pv-more-search').click();
      await expect(page.locator('#ti_quick_search')).toBeVisible();
      await page.locator('#ti_quick_search').press('Escape');
      // "Unterricht": one's courses (Kursbuch) and the class lists as a sheet
      await tabs.locator('#bu_pv_courses').click();
      const courses = page.locator('.pv-link-sheet');
      await expect(courses.locator('.pv-plan-group')).toContainText(['Mein Unterricht', 'Meine Lerngruppen']);
      await expect(courses.locator('a[href^="/lessons/"]').first()).toBeVisible();
      // the other groups folded, open on a tap
      const fold = courses.locator('.pv-sheet-fold');
      await expect(fold).toHaveText(/^Weitere Lerngruppen \(\d+\)$/);
      await expect(fold).toHaveAttribute('aria-expanded', 'false');
      await expect(courses.locator('a[href="/directory/11"]')).toBeHidden();
      await fold.click();
      await expect(courses.locator('a[href="/directory/11"]')).toBeVisible();
      // in the school's order: the years 11 and 12 after the classes
      const others = await courses.locator('.pv-sheet-links').last().locator('a').evaluateAll((els) => els.map((el) => el.getAttribute('href')));
      expect(others.indexOf('/directory/5b')).toBeGreaterThanOrEqual(0);
      expect(others.indexOf('/directory/11')).toBeGreaterThan(others.indexOf('/directory/5b'));
      expect(others.indexOf('/directory/12')).toBeGreaterThan(others.indexOf('/directory/11'));
      await page.locator('.pv-plan-veil').click({ position: { x: 20, y: 20 } });
      await expect(courses).toHaveCount(0);
      // "Woche": the days of the week one below the other
      await tabs.getByText('Woche').click();
      await expect(page).toHaveURL(/\/#woche$/);
      await expect(page.locator('#pv_agenda .pv-week-day')).toHaveCount(5);
      await expect(page.locator('.pv-tabbar .pv-tab.pv-active')).toContainText('Woche');
      // on the start page the search sits in the header
      await page.locator('#pv_day_band .pv-band-search').click();
      await expect(page.locator('#ti_quick_search')).toBeVisible();
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The sidebar's sections: Unterricht, Lerngruppen, Schule and Verwaltung are
// one entry each and open as a panel to the right, like the menus (on
// tablets the sidebar is an icon rail, the panels the same). Klassenarbeiten
// belong to Schule; the entry of the current page's section is marked.
for (const [name, width, height] of [['Desktop', 1280, 900], ['Tablet', 820, 1180]] as const) {
  test(`Neues Design: Abschnitte der Seitenleiste als Menüs nach rechts (${name})`, async ({ page }, testInfo) => {
    test.skip(testInfo.project.name === 'mobile', 'sidebar widths');
    await page.setViewportSize({ width, height });
    await login(page, ACCOUNTS.admin);
    await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
    try {
      await page.goto('/tests');
      const nav = page.locator('nav.navbar');
      const side = (await nav.boundingBox())!;
      if (name === 'Tablet') {
        expect(side.width).toBeLessThan(100);
        // no text sticks out of the rail or is cut off in it
        expect(await nav.evaluate((navEl) => {
          const right = navEl.getBoundingClientRect().right;
          return [...navEl.querySelectorAll('*')].filter((el) => {
            const r = el.getBoundingClientRect();
            const text = [...el.childNodes].some((c) => c.nodeType === 3 && c.textContent!.trim());
            return text && r.width > 0 && r.height > 0 && (r.right > right + 1 || el.scrollWidth > el.clientWidth + 1);
          }).length;
        })).toBe(0);
      }
      // one entry each, in this order, below the pages
      const order = await nav.locator('.navbar-nav > .pv-nav-section, .navbar-nav > .pv-nav-groups').evaluateAll((els) =>
        els.map((el) => (el as HTMLElement).dataset.section || 'lerngruppen'));
      expect(order).toEqual(['unterricht', 'lerngruppen', 'schule', 'verwaltung']);
      if (name === 'Desktop') {
        await expect(nav.locator('.navbar-nav > .pv-nav-section > button.pv-nav-heading')).toHaveText(['Unterricht', 'Schule', 'Verwaltung']);
        await expect(nav.locator('#navbarDropdownKlassen')).toHaveText('Lerngruppen');
      }
      // the bodies stay closed until one opens them
      for (const key of ['unterricht', 'schule', 'verwaltung']) {
        await expect(nav.locator(`.pv-nav-section[data-section="${key}"] .pv-nav-body`)).toBeHidden();
      }
      const unterricht = nav.locator('.pv-nav-section[data-section="unterricht"]');
      const schule = nav.locator('.pv-nav-section[data-section="schule"]');
      // Klassenarbeiten: in Schule, not in Unterricht; the page lies in Schule
      await expect(unterricht.locator('a[href="/tests"]')).toHaveCount(0);
      await expect(schule.locator('button.pv-nav-heading')).toHaveClass(/pv-here/);
      await expect(unterricht.locator('button.pv-nav-heading')).not.toHaveClass(/pv-here/);
      // Unterricht: the courses, as a panel to the right, level with its entry
      const ubutton = unterricht.locator('button.pv-nav-heading');
      await ubutton.click();
      const ubody = unterricht.locator('.pv-nav-body');
      await expect(ubody).toBeVisible();
      await expect(ubody.locator('a.pv-nav-entry[href^="/lessons/"]').first()).toBeVisible();
      const ub = (await ubody.boundingBox())!, uh = (await ubutton.boundingBox())!;
      expect(ub.x).toBeGreaterThanOrEqual(side.width - 1);
      expect(Math.abs(ub.y - uh.y)).toBeLessThan(20);
      // one panel at a time
      await schule.locator('button.pv-nav-heading').click();
      await expect(ubody).toBeHidden();
      const sbody = schule.locator('.pv-nav-body');
      await expect(sbody.locator('a.pv-nav-entry[href="/tests"]')).toBeVisible();
      await expect(sbody.locator('a.pv-nav-entry[href="/tests"]')).toHaveClass(/pv-active/);
      const sb = (await sbody.boundingBox())!;
      expect(sb.y + sb.height).toBeLessThanOrEqual(height);
      // Lerngruppen closes it and opens its own menu to the right
      await page.locator('#navbarDropdownKlassen').click();
      await expect(sbody).toBeHidden();
      const groups = nav.locator('[aria-labelledby="navbarDropdownKlassen"]');
      await expect(groups).toBeVisible();
      expect((await groups.boundingBox())!.x).toBeGreaterThanOrEqual(side.width - 1);
      // and the other way round: a panel closes the open menu
      await schule.locator('button.pv-nav-heading').click();
      await expect(sbody).toBeVisible();
      await expect(groups).toBeHidden();
      // the groups of a section: lines across the whole panel
      const line = sbody.locator('.pv-nav-sub:visible').first();
      if (await line.count()) {
        const l = (await line.boundingBox())!, p = (await sbody.boundingBox())!;
        expect(l.height).toBeLessThanOrEqual(2);
        expect(l.width).toBeGreaterThanOrEqual(p.width - 4);
      }
      await page.keyboard.press('Escape');
      await expect(sbody).toBeHidden();
      // Escape and a click elsewhere close a panel
      await ubutton.click();
      await expect(ubody).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(ubody).toBeHidden();
      await ubutton.click();
      await expect(ubody).toBeVisible();
      await page.mouse.click(width - 40, height - 40);
      await expect(ubody).toBeHidden();
      // a link in the panel leads there
      await ubutton.click();
      await ubody.locator('a.pv-nav-entry[href^="/lessons/"]').first().click();
      await expect(page).toHaveURL(/\/lessons\//);
      await expect(nav.locator('.pv-nav-section[data-section="unterricht"] button.pv-nav-heading')).toHaveClass(/pv-here/);
    } finally {
      await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    }
  });
}

// A section longer than the window stands in columns; a line between groups
// that lands at the top of a column separates nothing there and is left out.
test('Neues Design: keine Trennlinie oben in einer Spalte der Seitenleiste', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the panels beside the sidebar');
  await page.setViewportSize({ width: 1280, height: 480 });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    const sec = page.locator('nav.navbar .pv-nav-section[data-section="verwaltung"]');
    await sec.locator('button.pv-nav-heading').click();
    const body = sec.locator('.pv-nav-body');
    await expect(body).toBeVisible();
    const r = await body.evaluate((panel) => {
      const top = panel.getBoundingClientRect().top + (parseFloat(getComputedStyle(panel).paddingTop) || 0);
      const lines = [...panel.querySelectorAll('.pv-nav-sub, .dropdown-divider')].filter((l) => (l as HTMLElement).offsetParent);
      return {
        columns: parseInt(getComputedStyle(panel).columnCount) || 1,
        lines: lines.length,
        at_top: lines.filter((l) => l.getBoundingClientRect().top - top < 12).length,
      };
    });
    expect(r.columns).toBeGreaterThan(1);
    expect(r.lines).toBeGreaterThan(0);
    expect(r.at_top).toBe(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Profile pictures come from Nextcloud. The new design shows them larger and
// on phones with three pixels per point: 64 px looked blurred, so it asks for
// 128 px; the old design keeps 64.
test('Neues Design: Profilbilder in 128 px', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const avatar = page.locator('.nav_avatar .avatar-md');
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/profil');
  expect(await avatar.getAttribute('style')).toMatch(/\/index\.php\/avatar\/[^/)]+\/64\)/);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    expect(await avatar.getAttribute('style')).toMatch(/\/index\.php\/avatar\/[^/)]+\/128\)/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// A scheme outside the curated set stays one's own scheme of three colours;
// the profile says so and names the closest scheme of the set.
test('Neues Design: eigenes Farbschema bleibt, mit Hinweis im Profil', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.goto('/profil');
  const before = await page.evaluate(() => (window as any).color_scheme as string);
  try {
    await page.request.post('/api/set_color_scheme', { data: { scheme: 'l1122334455667788990' } });
    await page.goto('/profil');
    const note = page.locator('.pv-scheme-note');
    await expect(note).toContainText('Dein eigenes Farbschema besteht aus drei Farben, du kannst sie unten anpassen.');
    await expect(note).toContainText('Ähnlich in der Auswahl:');
    await expect(note).not.toContainText('gehört nicht');
  } finally {
    await page.request.post('/api/set_color_scheme', { data: { scheme: before } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Icons: in the preview Tabler instead of Fork Awesome, without changing the
// pages – also for icons created later and when a page swaps an icon.
test('Neues Design: Tabler-Icons statt Fork Awesome', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/messages');
  await expect(page.locator('.ti')).toHaveCount(0);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/messages');
    const admin = page.locator('#navbarDropdownAdmin .fa');
    await expect(admin).toHaveClass(/\bti ti-tool\b/);
    // the old class stays (pages check it), the Tabler font draws the glyph
    await expect(admin).toHaveClass(/\bfa-wrench\b/);
    expect(await admin.evaluate((el) => getComputedStyle(el).fontFamily)).toContain('tabler-icons');
    // an icon a page adds later, and one it swaps
    const swapped = await page.evaluate(async () => {
      const i = document.createElement('i');
      i.className = 'fa fa-eye';
      document.body.appendChild(i);
      await new Promise((r) => setTimeout(r, 50));
      const added = i.className;
      i.classList.remove('fa-eye');
      i.classList.add('fa-eye-slash');
      await new Promise((r) => setTimeout(r, 50));
      return { added, swapped: i.className };
    });
    expect(swapped.added).toMatch(/\bti-eye\b/);
    expect(swapped.swapped).toMatch(/\bti-eye-off\b/);
    expect(swapped.swapped).not.toMatch(/\bti-eye\b(?!-)/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Fonts: the new design's own, self-hosted fonts instead of the font choice
test('Neues Design: eigene Schriften', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/profil');
  expect(await page.evaluate(() => getComputedStyle(document.body).fontFamily)).not.toContain('Atkinson');
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    expect(await page.evaluate(() => getComputedStyle(document.body).fontFamily)).toContain('Atkinson Hyperlegible Next');
    expect(await page.locator('h2').first().evaluate((el) => getComputedStyle(el).fontFamily)).toContain('Bricolage Grotesque');
    // really loaded, from the dashboard itself
    await page.evaluate(() => document.fonts.ready);
    const loaded = await page.evaluate(() => [...document.fonts].filter((f) => f.status === 'loaded').map((f) => f.family.replace(/"/g, '')));
    expect(loaded).toContain('Atkinson Hyperlegible Next');
    expect(loaded).toContain('Bricolage Grotesque');
    // no font choice in the new design (it has its own type)
    await expect(page.locator('.bu_set_font').first()).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Six font pairs in the profile ("Schrift"), all with accents and modern
// Greek (with tonos) in the pair's own fonts; Atkinson and Bricolage have no
// Greek, Fira Sans fills in behind them. Polytonic Greek is a plus: where a
// pair lacks it, Fira Sans fills in, never a system font. The
// names as Chrome reports the fonts drawing the text (it may add its
// renderer or the variable font's default instance, e.g. "Inter
// (Fontations)", "Manrope ExtraLight (Fontations)")
const FONT_PAIRS = [
  { key: 'klar', text: 'Atkinson Hyperlegible Next', display: 'Bricolage Grotesque', greekText: /^Fira Sans( \(|$)/, greekDisplay: /^Fira Sans( \(|$)/ },
  { key: 'sachlich', text: 'Inter', display: 'Inter Tight', greekText: /^Inter( \(|$)/, greekDisplay: /^Inter Tight( \(|$)/ },
  { key: 'buch', text: 'Literata', display: 'Literata', greekText: /^Literata( \(|$)/, greekDisplay: /^Literata( \(|$)/ },
  { key: 'freundlich', text: 'Manrope', display: 'M PLUS Rounded 1c', greekText: /^Manrope( |$)/, greekDisplay: /Mplus/i },
  { key: 'feder', text: 'Alegreya Sans', display: 'Alegreya', greekText: /^Alegreya Sans( \(|$)/, greekDisplay: /^Alegreya( \(|$)/ },
  { key: 'verspielt', text: 'Playpen Sans', display: 'Comfortaa', greekText: /^Playpen Sans( |$)/, greekDisplay: /^Comfortaa( |$)/ },
];

test('Neues Design: Schrift wählen, mit Akzenten und Griechisch', async ({ page, serverErrors }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_font', { data: { font: 'klar' } });
  // only the known keys
  for (const font of ['comic', '', 'klar; DROP', 'Inter']) {
    expect((await page.request.post('/api/set_ui_font', { data: { font } })).status()).not.toBe(200);
  }
  serverErrors.splice(0, serverErrors.length, ...serverErrors.filter((e) => !e.includes('/api/set_ui_font')));
  // the old design: no tiles, its own fonts, whatever the choice
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  expect((await page.request.post('/api/set_ui_font', { data: { font: 'sachlich' } })).status()).toBe(200);
  await page.goto('/profil');
  await expect(page.locator('.pv-font-tile')).toHaveCount(0);
  expect(await page.evaluate(() => document.body.className)).not.toMatch(/pv-font-/);
  expect(await page.evaluate(() => getComputedStyle(document.body).fontFamily)).not.toMatch(/Inter|Atkinson/);
  await page.request.post('/api/set_ui_font', { data: { font: 'klar' } });

  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    const tiles = page.locator('.pv-font-tile');
    await expect(tiles).toHaveCount(FONT_PAIRS.length);
    await expect(page.locator(".pv-font-tile[aria-checked='true']")).toHaveAttribute('data-font', 'klar');
    await expect(page.locator('body')).toHaveClass(/\bpv-font-klar\b/);
    // every tile in its own fonts, with Greek
    for (const pair of FONT_PAIRS) {
      const tile = page.locator(`.pv-font-tile[data-font='${pair.key}']`);
      await expect(tile.locator('.pv-font-sample')).toContainText('Ελληνικά');
      expect(await tile.locator('.pv-font-sample').evaluate((el) => getComputedStyle(el).fontFamily)).toContain(pair.text);
      expect(await tile.locator('.pv-font-name').evaluate((el) => getComputedStyle(el).fontFamily)).toContain(pair.display);
    }
    // the fonts that really draw the Greek (Chrome's DevTools protocol)
    const cdp = await page.context().newCDPSession(page);
    const used = async (selector: string) => {
      await cdp.send('DOM.enable');
      await cdp.send('CSS.enable');
      const { root } = await cdp.send('DOM.getDocument', { depth: 0 });
      const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector });
      const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
      return fonts.filter((f: { isCustomFont: boolean }) => f.isCustomFont).map((f: { familyName: string }) => f.familyName);
    };
    const system = async (selector: string) => {
      const { root } = await cdp.send('DOM.getDocument', { depth: 0 });
      const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector });
      const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
      return fonts.filter((f: { isCustomFont: boolean }) => !f.isCustomFont).map((f: { familyName: string }) => f.familyName);
    };
    const bodyFont = () => page.evaluate(() => getComputedStyle(document.body).fontFamily);
    const headingFont = () => page.locator('h2').first().evaluate((el) => getComputedStyle(el).fontFamily);
    for (const pair of [...FONT_PAIRS.slice(1), FONT_PAIRS[0]]) {
      // at once, without loading the page again
      await page.locator(`.pv-font-tile[data-font='${pair.key}']`).click();
      await expect(page.locator(".pv-font-tile[aria-checked='true']")).toHaveAttribute('data-font', pair.key);
      await expect(page.locator('body')).toHaveClass(new RegExp(`\\bpv-font-${pair.key}\\b`));
      await expect.poll(bodyFont).toMatch(new RegExp(`^"?${pair.text}"?,`));
      await expect.poll(headingFont).toMatch(new RegExp(`^"?${pair.display}"?,`));
      // Greek text in the page (a message, a Kursbuch entry …): in the pair's fonts
      await page.evaluate(() => {
        document.querySelectorAll('.pv-greek-probe').forEach((el) => el.remove());
        const p = document.createElement('p');
        p.id = 'pv_greek_probe_text';
        p.className = 'pv-greek-probe';
        // Greek letters only: spaces and commas come from the Latin font
        p.textContent = 'ΕλληνικάΑθήνααρετήΆΈΉΊΌΎΏϊϋΐΰ';
        const h = document.createElement('h2');
        h.id = 'pv_greek_probe_heading';
        h.className = 'pv-greek-probe';
        h.textContent = 'ΑρετήΑθήνα';
        const poly = document.createElement('p');
        poly.id = 'pv_greek_probe_poly';
        poly.className = 'pv-greek-probe';
        poly.textContent = 'ἀρετήῥῆμαᾠδή';
        // next to the tiles (in view), outside them (they have fonts of their own)
        document.querySelector('.pv-fonts')!.append(h, p, poly);
      });
      await page.evaluate(() => document.fonts.ready);
      await expect.poll(() => used('#pv_greek_probe_text')).toEqual([expect.stringMatching(pair.greekText)]);
      await expect.poll(() => used('#pv_greek_probe_heading')).toEqual([expect.stringMatching(pair.greekDisplay)]);
      await expect.poll(() => used('#pv_greek_probe_poly')).not.toEqual([]);
      expect(await system('#pv_greek_probe_poly')).toEqual([]);
      // kept for the next page
      if (pair.key !== 'klar') {
        await page.reload();
        await expect(page.locator(".pv-font-tile[aria-checked='true']")).toHaveAttribute('data-font', pair.key);
        await expect(page.locator('body')).toHaveClass(new RegExp(`\\bpv-font-${pair.key}\\b`));
        expect(await bodyFont()).toMatch(new RegExp(`^"?${pair.text}"?,`));
      }
    }
  } finally {
    await page.request.post('/api/set_ui_font', { data: { font: 'klar' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Timetable: each subject in its colour from the colour scheme
test('Neues Design: Fächer im Stundenplan in ihren Farben', async ({ page }, testInfo) => {
  // the week shows Mathematik and Latein side by side; the day view on phones
  // uses the same colours (timetable_event_color)
  test.skip(testInfo.project.name === 'mobile', 'Wochenansicht nur am Desktop');
  await login(page, ACCOUNTS.admin);
  const colours = async () => {
    await page.goto('/');
    const ma = page.locator('.fc-event', { hasText: 'Mathematik' }).first();
    const la = page.locator('.fc-event', { hasText: 'Latein' }).first();
    await expect(ma).toBeVisible();
    await expect(la).toBeVisible();
    const bg = (l: typeof ma) => l.evaluate((el) => getComputedStyle(el).backgroundColor);
    return { ma: await bg(ma), la: await bg(la) };
  };
  const hex2rgb = (h: string) => `rgb(${[1, 3, 5].map((i) => parseInt(h.trim().slice(i, i + 2), 16)).join(', ')})`;
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const before = await colours();
  expect(before.ma).toBe(before.la);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    const after = await colours();
    expect(after.ma).not.toBe(after.la);
    const tokens = await page.evaluate(() => ({
      ma: getComputedStyle(document.documentElement).getPropertyValue('--subj-ma'),
      la: getComputedStyle(document.documentElement).getPropertyValue('--subj-la'),
    }));
    expect(after.ma).toBe(hex2rgb(tokens.ma));
    expect(after.la).toBe(hex2rgb(tokens.la));
    // readable: white text on the subject colours in light mode (they are
    // computed for it), not the scheme's text colour
    const text = await page.locator('.fc-event', { hasText: 'Mathematik' }).first().locator('.fc-event-main')
      .evaluate((el) => getComputedStyle(el).color);
    const ink = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--subj-ma-ink').trim());
    expect(text).toBe(hex2rgb(ink));
    // a substitution takes the colour of the subject that takes place
    const swapped = await page.evaluate(() => {
      const w = window as unknown as { preview_subject_color: (e: object) => string | null };
      return {
        ma: w.preview_subject_color({ lesson: true, label_short: '<s><b>La</b></s> <b>Ma</b> (9c)' }),
        la: w.preview_subject_color({ lesson: true, label_short: '<s><b>Ma</b></s> <b>La</b> (9c)' }),
      };
    });
    expect(swapped.ma).toBe(tokens.ma.trim());
    expect(swapped.la).toBe(tokens.la.trim());
    // codes of the subject list, and a subject without its own colour gets
    // the accent (grey would look cancelled); cancelled lessons stay as today
    const others = await page.evaluate(() => {
      const w = window as unknown as { preview_subject_color: (e: object) => string | null };
      const root = getComputedStyle(document.documentElement);
      return {
        ph: w.preview_subject_color({ lesson: true, label_short: '<b>Ph</b> (9c)' }), phToken: root.getPropertyValue('--subj-ph').trim(),
        unknown: w.preview_subject_color({ lesson: true, label_short: '<b>Xyz</b> (9c)' }), acc: root.getPropertyValue('--acc').trim(),
        entfall: w.preview_subject_color({ lesson: true, entfall: true, label_short: '<b>Ma</b> (9c)' }),
      };
    });
    expect(others.ph).toBe(others.phToken);
    expect(others.ph).not.toBe('');
    expect(others.unknown).toBe(others.acc);
    expect(others.entfall).toBeNull();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Timetable: the grid shows the school day instead of 7:00 to 22:00
test('Neues Design: Stundenplan zeigt nur den Schultag', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'am Handy zeigt die Vorschau den Tag als Agenda');
  await login(page, ACCOUNTS.admin);
  const grid = async () => {
    await page.goto('/');
    await expect(page.locator('.fc-event').first()).toBeVisible();
    await page.waitForTimeout(300);
    return page.evaluate(() => {
      const labels = [...document.querySelectorAll('.fc-timegrid-slot-label[data-time]')].map((el) => el.getAttribute('data-time')!);
      return { first: labels[0], last: labels[labels.length - 1], height: document.getElementById('calendar')!.offsetHeight };
    });
  };
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const before = await grid();
  expect(before.first).toBe('07:00:00');
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    const after = await grid();
    expect(after.first > '07:00:00').toBe(true);
    expect(after.last < '21:30:00').toBe(true);
    expect(after.height).toBeLessThan(before.height * 0.8);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Quick switch for admins who want it: one button in both designs
test('Neues Design: Schnellumschalter für Admins', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.request.post('/api/set_ui_preview_quick', { data: { mode: 'off' } });
  await page.goto('/profil');
  await expect(page.locator('#bu_design_quick_toggle')).toHaveCount(0);
  await page.locator('.toggle:has(#ui_preview_quick_switch)').click();
  await page.waitForLoadState('load');
  try {
    const quick = page.locator('#bu_design_quick_toggle');
    await expect(quick).toHaveAttribute('aria-label', 'Zum neuen Design wechseln');
    await quick.click();
    await page.waitForLoadState('load');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    await expect(quick).toHaveAttribute('aria-label', 'Zum bisherigen Design wechseln');
    await quick.click();
    await page.waitForLoadState('load');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    await expect(quick).toHaveAttribute('aria-label', 'Zum neuen Design wechseln');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.request.post('/api/set_ui_preview_quick', { data: { mode: 'off' } });
  }
  // others get neither the setting nor the button
  const teacher = await newUserPage();
  await login(teacher, ACCOUNTS.teacher);
  expect((await teacher.request.post('/api/set_ui_preview_quick', { data: { mode: 'on' } })).status()).not.toBe(200);
  await teacher.goto('/profil');
  await expect(teacher.locator('#ui_preview_quick_switch')).toBeHidden();
  await expect(teacher.locator('#bu_design_quick_toggle')).toHaveCount(0);
});

// Phones: the day as an agenda – lessons as cards, the grid hidden; tapping a
// card opens the same lesson dialog. Today's design keeps the grid.
test('Neues Design: Tag als Agenda am Handy', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Agenda nur am Handy');
  await login(page, ACCOUNTS.admin);
  // a weekday of the shown week with lessons
  const day_with_lessons = async () => {
    for (let i = 0; i < 5; i++) {
      const found = await page.evaluate(async (i) => {
        const w = window as unknown as { calendar: { view: { currentStart: Date }; gotoDate: (d: Date) => void; getEvents: () => { start: Date; allDay: boolean }[] } };
        const monday = new Date(w.calendar.view.currentStart);
        while (monday.getDay() !== 1) monday.setDate(monday.getDate() + (monday.getDay() === 0 ? 1 : -1));
        const d = new Date(monday);
        d.setDate(d.getDate() + i);
        w.calendar.gotoDate(d);
        await new Promise((r) => setTimeout(r, 400));
        return w.calendar.getEvents().some((e) => !e.allDay && e.start.toDateString() === d.toDateString());
      }, i);
      if (found) return;
    }
    throw new Error('no weekday with lessons');
  };
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/');
  await expect(page.locator('.fc-view-harness')).toBeVisible();
  await expect(page.locator('#pv_agenda')).toBeHidden();
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/pv-agenda-on/);
    await expect(page.locator('.fc-view-harness')).toBeHidden();
    await day_with_lessons();
    const card = page.locator('#pv_agenda .pv-ag-card').first();
    await expect(card).toBeVisible();
    await expect(card.locator('.pv-ag-subj')).not.toHaveText('');
    // in the subject's colour: chip and the bar on the left
    const colours = await page.evaluate(() => {
      const card = [...document.querySelectorAll('#pv_agenda .pv-ag-card')].find((el) => /Mathematik|Latein|Naturwiss/.test(el.textContent || '')) as HTMLElement;
      const key = /Mathematik/.test(card.textContent!) ? 'ma' : /Latein/.test(card.textContent!) ? 'la' : 'nawi';
      const hex = getComputedStyle(document.documentElement).getPropertyValue('--subj-' + key).trim();
      const rgb = `rgb(${[1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16)).join(', ')})`;
      return { rgb, chip: getComputedStyle(card.querySelector('.pv-ag-subj')!).backgroundColor, bar: getComputedStyle(card).borderLeftColor };
    });
    expect(colours.chip).toBe(colours.rgb);
    expect(colours.bar).toBe(colours.rgb);
    await expect(page.locator('#pv_agenda .pv-ag-when').first()).toHaveText(/\d:\d\d/);
    // long texts (a topic, a long note) wrap inside the panel
    await page.evaluate(() => {
      const w = window as any;
      const d = w.calendar.getDate().toDateString();
      const ev = w.calendar.getEvents().find((e: any) => !e.allDay && e.start.toDateString() === d && !e.extendedProps.pausenaufsicht);
      ev.setExtendedProp('data', { ...(ev.extendedProps.data || {}), stundenthema_text: 'Probeklausur (75 Minuten, kann zu Hause oder am Donnerstag in der Schule geschrieben werden), bitte Taschenrechner mitbringen' });
      ev.setExtendedProp('vertretungs_text', 'Ein sehr langer Hinweis ohne Leerzeichen: Donaudampfschifffahrtsgesellschaftskapitänsmütze');
    });
    await expect(page.locator('#pv_agenda .pv-ag-topic').first()).toBeVisible();
    const overflow = await page.evaluate(() => {
      const panel = document.getElementById('pv_agenda')!.getBoundingClientRect();
      return [...document.querySelectorAll('#pv_agenda .pv-ag-card, #pv_agenda .pv-ag-mark, #pv_agenda .pv-ag-note')]
        .filter((el) => el.getBoundingClientRect().right > panel.right + 1).length;
    });
    expect(overflow).toBe(0);
    // a break duty says where, without opening it
    await page.evaluate(() => {
      const w = window as any;
      const d = new Date(w.calendar.getDate());
      d.setHours(7, 30, 0, 0);
      w.calendar.addEvent({ start: d, end: new Date(d.getTime() + 15 * 60000),
        extendedProps: { lesson: true, pausenaufsicht: true, raum: 'Hof Nord', label: 'Pausenaufsicht' } });
    });
    const duty = page.locator('#pv_agenda .pv-ag-duty');
    await expect(duty).toContainText('Hof Nord');
    await expect(duty).toContainText('7:30–7:45');
    // a changed room as a notice in the card; changes of the coming days below the day
    await page.evaluate(() => {
      const w = window as any;
      const d = new Date(w.calendar.getDate());
      const lesson = w.calendar.getEvents().find((e: any) => !e.allDay && e.extendedProps.lesson && !e.extendedProps.pausenaufsicht);
      const a = new Date(d); a.setHours(16, 0, 0, 0);
      w.calendar.addEvent({ start: a, end: new Date(a.getTime() + 45 * 60000), extendedProps: { ...lesson.extendedProps, raum: '<s>108</s> 211' } });
      const b = new Date(d); b.setDate(b.getDate() + 1); b.setHours(16, 0, 0, 0);
      w.calendar.addEvent({ start: b, end: new Date(b.getTime() + 45 * 60000), extendedProps: { ...lesson.extendedProps, entfall: true } });
    });
    await expect(page.locator('#pv_agenda .pv-ag-change').first()).toHaveText('Raum 211 statt 108');
    // no notices of coming days below the day (the next day is a swipe away)
    await expect(page.locator('#pv_agenda .pv-ag-notice')).toHaveCount(0);
    const cardColour = await card.evaluate((el) => getComputedStyle(el).borderLeftColor);
    await card.click();
    await expect(page.locator('#lessonModal')).toBeVisible();
    await expect(page.locator('#lessonModal .lesson-label')).not.toBeEmpty();
    // the dialog: a band in the lesson's colour, a sheet from the bottom on phones
    await page.waitForTimeout(400);
    const dialog = await page.evaluate(() => {
      const header = document.querySelector('#lessonModal .modal-header')!;
      const content = document.querySelector('#lessonModal .modal-content')!.getBoundingClientRect();
      return { band: getComputedStyle(header).borderTopColor, bottom: content.bottom, height: window.innerHeight };
    });
    expect(dialog.band).toBe(cardColour);
    expect(Math.abs(dialog.bottom - dialog.height)).toBeLessThan(2);
    // nothing lies on top of the sheet, not even the tab bar
    expect(await page.evaluate(() => !!document.elementFromPoint(window.innerWidth / 2, window.innerHeight - 20)!.closest('#lessonModal'))).toBe(true);
    // pulled down by its header, the sheet closes
    const header = (await page.locator('#lessonModal .modal-header').boundingBox())!;
    const cdp = await page.context().newCDPSession(page);
    const hx = header.x + header.width / 2, hy = header.y + 20;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: hx, y: hy }] });
    for (let i = 1; i <= 8; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: hx, y: hy + i * 20 }] });
      await page.waitForTimeout(30);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(page.locator('#lessonModal')).toBeHidden();
    // also when pulled down on the veil above it
    await card.click();
    await expect(page.locator('#lessonModal')).toBeVisible();
    await page.waitForTimeout(400);
    const top = (await page.locator('#lessonModal .modal-content').boundingBox())!.y;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: hx, y: top / 2 }] });
    for (let i = 1; i <= 8; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: hx, y: top / 2 + i * 20 }] });
      await page.waitForTimeout(30);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(page.locator('#lessonModal')).toBeHidden();
    // swiping left: the next school day, its date as the heading
    const day = () => page.evaluate(() => (window as any).moment((window as any).calendar.getDate()).format('YYYY-MM-DD'));
    const before = await day();
    const box = (await page.locator('#pv_agenda').boundingBox())!;
    expect(box.height).toBeGreaterThanOrEqual(Math.min(320, page.viewportSize()!.height * 0.5));
    const y = box.y + Math.min(box.height / 2, 120);
    const client = await page.context().newCDPSession(page);
    await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x + box.width * 0.85, y }] });
    for (let i = 1; i <= 10; i++) {
      await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: box.x + box.width * (0.85 - 0.07 * i), y }] });
      await page.waitForTimeout(20);
    }
    await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect.poll(day).not.toBe(before);
    const after = await day();
    expect(after > before).toBe(true);
    const heading = await page.evaluate(() => {
      const d = (window as any).calendar.getDate();
      return ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'][d.getDay()] + ', ' + d.getDate() + '.';
    });
    await expect(page.locator('#pv_day_band h1')).toContainText(heading);
    // the day strip marks the shown day
    await expect(page.locator('#pv_day_strip .pv-strip-active')).toContainText(String(await page.evaluate(() => (window as any).calendar.getDate().getDate())));
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The sidebar's badge for unread messages on »Nachrichten« stands at the right,
// level with the name (it was the old orange dot right after the name); at
// »Stundenplan« no badge: »Zu erledigen« is on the page itself
test('Neues Design: Zähler im Menü rechtsbündig, keiner an »Stundenplan«', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'die Seitenleiste nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/messages');
    await page.evaluate(() => {
      (window as unknown as { update_new_messages_indicators: (ids: number[]) => void }).update_new_messages_indicators([1]);
    });
    await expect(page.locator(".navbar .nav-link[href='/']").first()).toHaveText('Stundenplan');
    await expect(page.locator(".navbar .nav-link[href='/'] > span, .pv-todo-badge")).toHaveCount(0);
    const shape = (sel: string) => page.locator(sel).first().evaluate((el) => {
      const r = el.getBoundingClientRect();
      const link = (el.closest('.nav-link') as HTMLElement).getBoundingClientRect();
      // level with the name (its text, not the icon's box)
      const label = [...el.closest('.nav-link')!.childNodes].find((n) => n.nodeType === Node.TEXT_NODE && n.textContent!.trim())!;
      const range = document.createRange();
      range.selectNodeContents(label);
      const text = range.getBoundingClientRect();
      return { right: Math.round(link.right - r.right), middle: Math.round((r.top + r.bottom) / 2 - (text.top + text.bottom) / 2) };
    });
    const messages = await shape('.navbar .nav-link > .new-messages-indicator');
    expect(Math.abs(messages.middle)).toBeLessThanOrEqual(1);
    expect(messages.right).toBeLessThan(24);
    // the tablet rail (names hidden): at the icon's corner
    await page.setViewportSize({ width: 1000, height: 800 });
    const corner = await page.locator('.navbar .nav-link > .new-messages-indicator').first().evaluate((el) => {
      const r = el.getBoundingClientRect();
      const icon = (el.closest('.nav-link')!.querySelector('.icon') as HTMLElement).getBoundingClientRect();
      return { dx: r.left - icon.right, dy: r.top - icon.top };
    });
    expect(Math.abs(corner.dx)).toBeLessThan(16);
    expect(Math.abs(corner.dy)).toBeLessThan(16);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Styles and scripts of the preview carry a version: after a change browsers
// load them again instead of keeping an old copy (nginx serves them as files)
test('Neues Design: Dateien mit Version, damit Änderungen ankommen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    for (const selector of ['link[href^="/preview.css"]', 'script[src^="/preview.js"]', 'link[href^="/include/fonts-v2/fonts.css"]',
      'link[href^="/include/tabler/tabler-icons.css"]', 'script[src^="/include/tabler/fa-to-tabler.js"]']) {
      const url = await page.locator(selector).first().evaluate((el) => el.getAttribute('href') || el.getAttribute('src'));
      expect(url, selector).toMatch(/\?v=\d{9,}$/);
      expect((await page.request.get(url!)).status(), selector).toBe(200);
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Monitors keep their own layout, also for an admin with the preview (the
// monitor admin page embeds them with the admin's session)
test('Neues Design: Monitore bleiben unverändert', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    for (const path of ['/monitor', '/monitor/lz', '/monitor/sek', '/monitor?design=neu', '/monitor?design=alt']) {
      const html = await (await page.request.get(path)).text();
      expect(html, path).not.toContain('ui-preview');
      expect(html, path).not.toContain('pv-tabbar');
      expect(html, path).not.toContain('/preview.css');
      // the monitors in their own new design (monitor-neu.spec.ts): with
      // ?design=neu, or for someone with the new design switched on (the
      // previews in manage_monitor) – not with ?design=alt
      const neu = !path.includes('design=alt');
      if (neu) expect(html, path).toContain('/preview/monitor/');
      else expect(html, path).not.toContain('/preview/monitor/');
    }
    // without the new design switched on: today's monitor
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    expect(await (await page.request.get('/monitor')).text()).not.toContain('/preview/monitor/');
    await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: swiping the agenda to the next day, the day chips above follow the
// finger – the highlight slides in full colour from the shown day to the
// next one as far as the agenda has moved, only on the chips (not in the
// gaps), instead of jumping when the swipe ends (install_preview_agenda_swipe)
test('Neues Design: Tageschips folgen dem Wischen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Wischen nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/pv-agenda-on/);
    // a Tuesday: Monday before it and Wednesday after it in the same week
    const zeigen = (tag: number) => page.evaluate(async (tag) => {
      const w = window as unknown as { calendar: { view: { currentStart: Date }; gotoDate: (d: Date) => void }; render_preview_agenda: () => void };
      const d = new Date(w.calendar.view.currentStart);
      while (d.getDay() !== 1) d.setDate(d.getDate() + (d.getDay() === 0 ? 1 : -1));
      d.setDate(d.getDate() + tag);
      w.calendar.gotoDate(d);
      w.render_preview_agenda();
      await new Promise((r) => setTimeout(r, 300));
    }, tag);
    await zeigen(1);
    const chips = page.locator('#pv_day_strip .pv-strip-day');
    await expect(chips).toHaveCount(5);
    await expect(chips.nth(1)).toHaveClass(/pv-strip-active/);
    const agenda = page.locator('#pv_agenda');
    await agenda.evaluate((el) => el.scrollIntoView({ block: 'center' }));
    const box = (await agenda.boundingBox())!;
    const y = box.y + Math.min(box.height / 2, 200);
    const cdp = await page.context().newCDPSession(page);
    // how much of each chip the highlight covers (data-lit of its lit copy)
    const an = () => chips.evaluateAll((cs) => cs.map((c) => {
      const lit = c.querySelector('.pv-strip-lit') as HTMLElement | null;
      return lit ? parseFloat(lit.dataset.lit || 'NaN') : NaN;
    }));
    // half way to the left (the next day): both chips half lit
    const halb = async (richtung: 1 | -1) => {
      const x0 = box.x + box.width / 2 + richtung * box.width * 0.3;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y }] });
      for (let i = 1; i <= 10; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 - richtung * (box.width * 0.5 * i) / 10, y }] });
        await page.waitForTimeout(16);
      }
    };
    await halb(1);
    let on = await an();
    expect(on[1]).toBeGreaterThan(0.3);
    expect(on[1]).toBeLessThan(0.65);
    expect(on[2]).toBeGreaterThan(0.3);
    expect(on[2]).toBeLessThan(0.65);
    expect(on[0]).toBe(0);
    expect(on[3]).toBe(0);
    // nothing of the highlight in the gap between Tuesday and Wednesday
    const imSpalt = await page.evaluate(() => {
      const cs = [...document.querySelectorAll('#pv_day_strip .pv-strip-day')].map((c) => c.getBoundingClientRect());
      const el = document.elementFromPoint((cs[1].right + cs[2].left) / 2, cs[1].top + cs[1].height / 2);
      return el ? (el.closest('.pv-strip-lit') ? 'lit' : el.className) : '';
    });
    expect(imSpalt).not.toBe('lit');
    // the lit copy above the plain chip, in the full accent
    const lit = chips.nth(2).locator('.pv-strip-lit');
    const akzent = await page.evaluate(() => getComputedStyle(document.body).getPropertyValue('--acc-text').trim());
    expect(akzent).not.toBe('');
    expect(await lit.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    // above the chip's own text (positioned, painted later), its edge
    // through the middle of »Mi«: the left part lit, the right part plain
    const schnitt = await page.evaluate(() => {
      const c = document.querySelectorAll('#pv_day_strip .pv-strip-day')[2] as HTMLElement;
      const lit = c.querySelector('.pv-strip-lit') as HTMLElement;
      const m = /inset\(0(?:px)? ([\d.]+)px/.exec(lit.style.clipPath)!;
      const kante = c.getBoundingClientRect().right - parseFloat(m[1]);
      const b = c.querySelector(':scope > b')!.getBoundingClientRect();
      return { position: getComputedStyle(lit).position, links: b.left < kante, rechts: b.right > kante };
    });
    expect(schnitt).toEqual({ position: 'absolute', links: true, rechts: true });
    // back to the start and let go: the swipe is cancelled, all as before
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: box.x + box.width / 2 + box.width * 0.3, y }] });
    on = await an();
    expect(on[1]).toBe(1);
    expect(on[2]).toBe(0);
    const pill = page.locator('#pv_day_strip .pv-strip-lit');
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(chips.nth(1)).toHaveClass(/pv-strip-active/);
    await expect(page.locator('#pv_day_strip .pv-strip-sliding')).toHaveCount(0);
    await expect(pill).toHaveCount(0);
    // all the way: Wednesday is shown, its chip lit
    await halb(1);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(chips.nth(2)).toHaveClass(/pv-strip-active/);
    await expect(page.locator('#pv_day_strip .pv-strip-sliding')).toHaveCount(0);
    await expect(page.locator('#pv_day_strip .pv-strip-lit')).toHaveCount(0);
    // to the right from Monday: the week before – the highlight moves half a step and fades
    await zeigen(0);
    await halb(-1);
    const deckkraft = parseFloat(await chips.nth(0).locator('.pv-strip-lit').evaluate((el) => el.style.opacity));
    expect(deckkraft).toBeLessThan(0.7);
    expect(deckkraft).toBeGreaterThan(0.3);
    on = await an();
    expect(on[0]).toBeLessThan(0.8);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(chips.nth(4)).toHaveClass(/pv-strip-active/);
    await expect(page.locator('#pv_day_strip .pv-strip-lit')).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: swiping the day with the page scrolled down, nothing jumps when the
// swipe ends – the neighbouring day slides in exactly where it then stays:
// scrolled into the agenda, the new day starts with its first lesson at the
// top; a shorter day at the page's end slides in where the page can still
// scroll to (install_preview_agenda_swipe, landing)
test('Neues Design: Wischen springt bei gescrollter Seite nicht', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Wischen nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/pv-agenda-on/);
    const zeigen = (tag: number) => page.evaluate(async (tag) => {
      const w = window as unknown as { calendar: { view: { currentStart: Date }; gotoDate: (d: Date) => void }; render_preview_agenda: () => void };
      const d = new Date(w.calendar.view.currentStart);
      while (d.getDay() !== 1) d.setDate(d.getDate() + (d.getDay() === 0 ? 1 : -1));
      d.setDate(d.getDate() + tag);
      w.calendar.gotoDate(d);
      w.render_preview_agenda();
      await new Promise((r) => setTimeout(r, 300));
    }, tag);
    const chips = page.locator('#pv_day_strip .pv-strip-day');
    const cdp = await page.context().newCDPSession(page);
    const lage = () => page.evaluate(() => {
      const ghost = document.querySelector('.pv-agenda-ghost') as HTMLElement | null;
      return {
        oben: document.getElementById('pv_agenda')!.getBoundingClientRect().top,
        geist: ghost ? ghost.getBoundingClientRect().top : null,
        scroll: window.scrollY,
        max: document.documentElement.scrollHeight - window.innerHeight,
      };
    });
    // half way to the left, where the finger sits on the agenda; returns
    // where the next day slides in, then lets go: the next day is shown
    const wischen = async () => {
      const r = await page.evaluate(() => {
        const b = document.getElementById('pv_agenda')!.getBoundingClientRect();
        const top = Math.max(b.top, 0), bottom = Math.min(b.bottom, window.innerHeight);
        return { x: b.left, w: b.width, y: (top + bottom) / 2 };
      });
      const x0 = r.x + r.w * 0.8;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: x0, y: r.y }] });
      for (let i = 1; i <= 10; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x0 - (r.w * 0.5 * i) / 10, y: r.y }] });
        await page.waitForTimeout(16);
      }
      const mitten = await lage();
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      await expect(page.locator('.pv-agenda-ghost')).toHaveCount(0);
      return mitten;
    };
    // at the top: the page stays where it is
    await zeigen(1);
    await page.evaluate(() => window.scrollTo(0, 0));
    let vorher = await lage();
    let mitten = await wischen();
    await expect(chips.nth(2)).toHaveClass(/pv-strip-active/);
    let nachher = await lage();
    expect(mitten.geist).toBeCloseTo(vorher.oben, 0);
    expect(nachher.scroll).toBe(0);
    expect(nachher.oben).toBeCloseTo(vorher.oben, 0);
    // scrolled into the agenda (room below: the page as long as on a full
    // day): the next day slides in with its start at the top and stays there
    await zeigen(1);
    await page.evaluate(() => {
      const platz = document.createElement('div');
      platz.id = 'test_platz';
      platz.style.height = '2000px';
      document.body.appendChild(platz);
      const a = document.getElementById('pv_agenda')!;
      window.scrollTo(0, a.getBoundingClientRect().top + window.scrollY + 120);
    });
    vorher = await lage();
    expect(vorher.oben).toBeLessThan(-100);
    mitten = await wischen();
    await expect(chips.nth(2)).toHaveClass(/pv-strip-active/);
    nachher = await lage();
    expect(mitten.geist).toBeCloseTo(8, 0);
    expect(Math.abs(nachher.oben - mitten.geist!)).toBeLessThan(1.5);
    // a shorter day at the page's end: the page gets shorter – the next day
    // slides in where the page can still scroll to, nothing moves at the end
    await zeigen(1);
    await page.evaluate(() => {
      document.getElementById('test_platz')!.remove();
      const lang = document.createElement('div');
      lang.style.height = '1500px';
      document.getElementById('pv_agenda')!.appendChild(lang);
      window.scrollTo(0, document.documentElement.scrollHeight);
    });
    vorher = await lage();
    mitten = await wischen();
    await expect(chips.nth(2)).toHaveClass(/pv-strip-active/);
    nachher = await lage();
    expect(mitten.geist!).toBeGreaterThan(vorher.oben + 1000);
    expect(Math.abs(nachher.oben - mitten.geist!)).toBeLessThan(1.5);
    expect(nachher.scroll).toBeLessThanOrEqual(nachher.max + 1);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: other plans (Kürzel, classes, rooms) through a "Plan" button in the
// header – a sheet with search, the shown plan in the accent; no chip panel
// Back (button or swipe from the edge) closes what opened like a screen –
// "Mehr", the plan menu – and stays on the page; closing one in the page
// leaves no extra history entry behind (preview.js, pv_back).
test('Neues Design: Zurück schließt Sheets am Handy', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Sheets nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/messages');
    await page.goto('/');
    const more = page.locator('#navbarTogglerDemo02');
    await page.locator('#bu_pv_more').click();
    await expect(more).toHaveClass(/\bshow\b/);
    await page.goBack({ waitUntil: 'commit' });
    await expect(more).toBeHidden();
    expect(new URL(page.url()).pathname).toBe('/');
    const plan = page.locator('#pv_day_band .pv-band-plan');
    await plan.click();
    await expect(page.locator('.pv-plan-menu')).toBeVisible();
    await page.goBack({ waitUntil: 'commit' });
    await expect(page.locator('.pv-plan-menu')).toHaveCount(0);
    expect(new URL(page.url()).pathname).toBe('/');
    // closed in the page: the next back leaves the page as usual
    await page.locator('#bu_pv_more').click();
    await expect(more).toHaveClass(/\bshow\b/);
    await page.locator('#bu_pv_more').click();
    await expect(more).toBeHidden();
    await page.goBack();
    await expect(page).toHaveURL(/\/messages$/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The tab "Woche" lives in the address: a reload stays on it.
test('Neues Design: Woche bleibt nach dem Neuladen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Tabs nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    // load the page with the preview first (a bare hash change doesn't reload)
    await page.goto('/');
    await page.goto('/#woche');
    await expect(page.locator('#pv_agenda.pv-agenda-week')).toBeVisible();
    await page.reload();
    await expect(page).toHaveURL(/#woche$/);
    await expect(page.locator('#pv_agenda.pv-agenda-week')).toBeVisible();
    await expect(page.locator('.pv-tabbar .pv-tab.pv-active')).toContainText('Woche');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Behind an open sheet the page stands still and is back at the same place
// when it closes (preview.js).
test('Neues Design: Seite steht hinter offenem Sheet still', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Sheets nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/hilfe');
    await page.evaluate(() => window.scrollTo(0, 300));
    await expect.poll(() => page.evaluate(() => Math.round(window.scrollY))).toBe(300);
    const top = await page.evaluate(() => Math.round(document.querySelector('#main_container')!.getBoundingClientRect().top));
    await page.locator('#bu_pv_more').click();
    await expect(page.locator('#navbarTogglerDemo02')).toHaveClass(/\bshow\b/);
    // the page behind keeps its place, scrolling moves nothing
    await page.evaluate(() => window.scrollBy(0, 400));
    expect(await page.evaluate(() => Math.round(document.querySelector('#main_container')!.getBoundingClientRect().top))).toBe(top);
    await page.locator('.pv-menu-veil').click({ position: { x: 20, y: 20 } });
    await expect(page.locator('#navbarTogglerDemo02')).toBeHidden();
    await expect.poll(() => page.evaluate(() => Math.round(window.scrollY))).toBe(300);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Plan wählen am Handy', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'am Desktop das Menü im Kopf (eigener Test)');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const button = page.locator('#pv_day_band .pv-band-plan');
    await expect(button).toContainText('Plan');
    await expect(page.locator('.timetable_chooser .ttc').first()).toBeHidden();
    await button.click();
    const menu = page.locator('.pv-plan-menu');
    await expect(menu).toBeVisible();
    const look = await menu.locator('.pv-plan-chip.active').evaluate((el) => {
      const acc = getComputedStyle(document.documentElement).getPropertyValue('--acc').trim();
      return { bg: getComputedStyle(el).backgroundColor, acc: `rgb(${[1, 3, 5].map((i) => parseInt(acc.slice(i, i + 2), 16)).join(', ')})` };
    });
    expect(look.bg).toBe(look.acc);
    // the menu lies above the tab bar, at the bottom (after sliding up)
    await page.waitForTimeout(400);
    const box = (await menu.boundingBox())!;
    expect(Math.abs(box.y + box.height - page.viewportSize()!.height)).toBeLessThan(2);
    // like every sheet: a veil behind it; tapping it or pulling the sheet down closes it
    await expect(page.locator('.pv-plan-veil')).toBeVisible();
    await page.locator('.pv-plan-veil').click({ position: { x: 20, y: 20 } });
    await expect(menu).toHaveCount(0);
    await button.click();
    await expect(menu).toBeVisible();
    await page.waitForTimeout(400);
    const top = (await menu.boundingBox())!;
    const cdp = await page.context().newCDPSession(page);
    const x = top.x + top.width / 2, y = top.y + 10;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    for (let i = 1; i <= 8; i++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y + i * 25 }] });
      await page.waitForTimeout(30);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await expect(menu).toHaveCount(0);
    await expect(page.locator('.pv-plan-veil')).toHaveCount(0);
    await button.click();
    await menu.locator('.pv-plan-chip', { hasText: /^5a$/ }).click();
    await expect(menu).toHaveCount(0);
    await expect(page.locator('#pv_day_band .pv-band-plan')).toContainText('Plan 5a');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop: a header above the timetable – week and calendar week, Tag/Woche,
// the plan as a menu instead of the chips, Heute and arrows
test('Neues Design: Kopf über dem Stundenplan am Desktop', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'am Handy der Kopf mit Datum und Tagesleiste');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const head = page.locator('#pv_week_head');
    await expect(head.locator('h2')).toHaveText(/\d+\.(–\d+\.)? \S+|\d+\. \S+ – \d+\. \S+/);
    await expect(head).toContainText('Kalenderwoche');
    await expect(page.locator('.fc-header-toolbar')).toBeHidden();
    await expect(page.locator('.timetable_chooser .ttc').first()).toBeHidden();
    // the week only (a single day is the phone's agenda)
    await expect(head.getByRole('button', { name: 'Tag', exact: true })).toHaveCount(0);
    // the plan menu: search and pick a class
    await page.locator('.pv-plan-button').click();
    await page.locator('.pv-plan-menu input').fill('5a');
    await page.locator('.pv-plan-menu .pv-plan-chip', { hasText: /^5a$/ }).click();
    await expect(page.locator('.pv-plan-menu')).toHaveCount(0);
    await expect(page.locator('#pv_week_head')).toContainText('Plan 5a');
    // the arrows move the week, Heute comes back
    const before = await page.locator('#pv_week_head h2').textContent();
    await page.locator('#pv_week_head').getByRole('button', { name: 'Weiter' }).click();
    await expect(page.locator('#pv_week_head h2')).not.toHaveText(before!);
    await page.locator('#pv_week_head').getByRole('button', { name: 'Heute' }).click();
    await expect(page.locator('#pv_week_head h2')).toHaveText(before!);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// One switch: in the new design the backdrop follows light / dark mode
// (today a separate "Hintergrund" setting picks its variant)
test('Neues Design: der Hintergrund folgt hell und dunkel', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_color_scheme', { data: { scheme: 'da2c6e80d60aea2c6e80' } });
  try {
    const backdrop = () => page.evaluate(() => getComputedStyle(document.body).backgroundImage);
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.goto('/');
    expect(await backdrop()).toContain('bg-la2c6e8');
    await page.request.post('/api/set_dark_css', { data: { mode: 'dark' } });
    await page.goto('/');
    expect(await backdrop()).toContain('bg-da2c6e8');
    // the separate setting is not offered in the new design
    await page.goto('/profil');
    await expect(page.locator('.toggle:has(#dark_switch)')).toBeHidden();
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_color_scheme', { data: { scheme: 'la2c6e80d60aea2c6e80' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Choosing a scheme or the Farbigkeit in the profile: the colours change at
// once, without loading the page again (the server computes them)
test('Neues Design: Farbschema und Farbigkeit wirken sofort', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Desktop reicht');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_color_scheme', { data: { scheme: 'la2c6e80d60aea2c6e80' } });
  try {
    await page.goto('/profil');
    let loads = 0;
    page.on('load', () => loads++);
    const tok = (k: string) => page.evaluate((k) => getComputedStyle(document.documentElement).getPropertyValue(k).trim(), k);
    const de = await tok('--subj-de');
    const slider = page.locator('#ti_ui_vividness');
    await slider.fill('0');
    await slider.dispatchEvent('input');
    await slider.dispatchEvent('change');
    await expect.poll(() => tok('--subj-de')).not.toBe(de);
    const acc = await tok('--acc');
    await page.locator('.swatches .swatch', { hasText: 'Gryffindor' }).click();
    await expect.poll(() => tok('--acc')).not.toBe(acc);
    expect(loads).toBe(0);
    // saved: a new page has the calm colours too
    await page.reload();
    expect(await tok('--subj-de')).not.toBe(de);
  } finally {
    await page.request.post('/api/set_ui_vividness', { data: { value: 100 } });
    await page.request.post('/api/set_color_scheme', { data: { scheme: 'la2c6e80d60aea2c6e80' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Light / dark in the profile: switched in place, the tiles show the
// backdrops of the new mode
test('Neues Design: hell und dunkel im Profil ohne Neuladen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Desktop reicht');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
  try {
    await page.goto('/profil');
    await page.waitForLoadState('load');
    let loads = 0;
    page.on('load', () => loads++);
    const tileBg = () => page.locator('.swatches .swatch').first().evaluate((el) => getComputedStyle(el).getPropertyValue('--pv-bg'));
    // Hell / Auto / Dunkel instead of the old switch
    await expect(page.locator('.toggle:has(#dark_css_switch)')).toBeHidden();
    await page.locator('.pv-mode-field button[data-mode="dark"]').click();
    await expect(page.locator('.pv-mode-field button[data-mode="dark"]')).toHaveAttribute('aria-pressed', 'true');
    await expect(page.locator('body')).toHaveClass(/dark/);
    await expect.poll(tileBg).toContain('/bg-d');
    expect(loads).toBe(0);
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// »Dunkel« / »Hell« in the menu (desktop: the own menu, phones: a tile in
// »Mehr«) switches in place too: colours from the server, the entry turns
// into the other one, the timetable draws its lessons again in the new
// colours. The old design still loads the page again.
test('Neues Design: hell und dunkel aus dem Menü ohne Neuladen', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
  const open = async () => {
    if (phone) {
      if (!(await page.locator('#navbarTogglerDemo02.show').count())) await page.locator('#bu_pv_more').click();
    } else if (!(await page.locator('[aria-labelledby="navbarDropdownProfile"].show').count())) {
      await page.locator('#navbarDropdownProfile').click();
    }
  };
  try {
    await page.goto('/');
    await page.waitForLoadState('load');
    let loads = 0;
    page.on('load', () => loads++);
    const tokens = () => page.locator('#design_tokens').evaluate((el) => el.textContent);
    const before = await tokens();
    await open();
    // Hell / Auto / Dunkel, the current one pressed; the old toggle is gone
    const choice = (mode: string) => page.locator(`.pv-mode-row button[data-mode="${mode}"]`);
    await expect(page.locator('.nav-dark, .nav-light')).toHaveCount(0);
    await expect(choice('light')).toHaveAttribute('aria-pressed', 'true');
    await choice('dark').click();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
    await expect.poll(tokens).not.toBe(before);
    await expect(page.locator('link[href="/dark.css"]')).toHaveCount(1);
    await open();
    await expect(choice('dark')).toHaveAttribute('aria-pressed', 'true');
    await expect(choice('light')).toHaveAttribute('aria-pressed', 'false');
    await choice('light').click();
    await expect(page.locator('body')).not.toHaveClass(/\bdark\b/);
    await expect.poll(tokens).toBe(before);
    await expect(page.locator('link[href="/dark.css"]')).toHaveCount(0);
    expect(loads).toBe(0);
    // stored: a reload keeps it
    await open();
    await choice('dark').click();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
    await page.reload();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// One's own scheme: three colours to select, the Cling palette (as in the
// Hackschule sprite editor) and HSL sliders for the selected one, in view at
// once – no system colour dialog.
test('Neues Design: eigenes Farbschema mit Palette und HSL-Reglern', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.goto('/profil');
  const before = await page.evaluate(() => (window as any).color_scheme as string);
  try {
    const own = page.locator('.pv-scheme-own');
    await expect(own.locator('input[type="color"]')).toHaveCount(0);
    await expect(own.locator('.pv-cling-colour')).toHaveCount(42);
    await expect(own.locator('.pv-cling-colour').first()).toBeVisible();
    await expect(own.locator('#ti_hsl_h')).toBeVisible();
    // the middle one is selected at first; select the left one
    await expect(own.locator('.pv-scheme-slot[data-slot="main"]')).toHaveAttribute('aria-checked', 'true');
    await own.locator('.pv-scheme-slot[data-slot="left"]').click();
    await expect(own.locator('.pv-scheme-slot[data-slot="left"]')).toHaveAttribute('aria-checked', 'true');
    // a colour of the palette
    await own.locator('.pv-cling-colour[data-hex="#4aa03f"]').click();
    await expect(own.locator('#ti_scheme_left')).toHaveValue('#4aa03f');
    await expect(own.locator('.pv-cling-colour[data-hex="#4aa03f"]')).toHaveAttribute('aria-pressed', 'true');
    await expect(own.locator('#ti_scheme_hex')).toHaveValue('#4aa03f');
    expect(await own.locator('.pv-scheme-slot[data-slot="left"] .pv-scheme-chip').evaluate((el) => getComputedStyle(el).backgroundColor)).toBe('rgb(74, 160, 63)');
    // the sliders follow it and change it
    expect(Number(await own.locator('#ti_hsl_h').inputValue())).toBeGreaterThan(100);
    await own.locator('#ti_hsl_h').fill('0');
    expect(await own.locator('#ti_scheme_left').inputValue()).not.toBe('#4aa03f');
    await expect(own.locator('.pv-cling-colour[data-hex="#4aa03f"]')).toHaveAttribute('aria-pressed', 'false');
    // a code typed in
    await own.locator('#ti_scheme_hex').fill('#0d60ae');
    await expect(own.locator('#ti_scheme_left')).toHaveValue('#0d60ae');
    // saved: the page's scheme starts with the three colours
    await own.locator('#bu_apply_own_scheme').click();
    await expect.poll(() => page.evaluate(() => (window as any).color_scheme as string)).toMatch(/^[ld]0d60ae/);
    // changed again, then a preset chosen: everything shows the preset
    await own.locator('.pv-cling-colour[data-hex="#4aa03f"]').click();
    await page.locator('.swatches .swatch:not(.active)').first().click();
    await expect.poll(() => page.evaluate(() => (window as any).color_scheme as string)).not.toMatch(/^[ld]0d60ae/);
    const preset = '#' + (await page.evaluate(() => (window as any).color_scheme as string)).substring(1, 7);
    await expect(own.locator('#ti_scheme_left')).toHaveValue(preset);
    await expect(own.locator('#ti_scheme_hex')).toHaveValue(preset);
    const rgb = 'rgb(' + [1, 3, 5].map((i) => parseInt(preset.substring(i, i + 2), 16)).join(', ') + ')';
    await expect.poll(() => own.locator('.pv-scheme-slot[data-slot="left"] .pv-scheme-chip').evaluate((el) => getComputedStyle(el).backgroundColor)).toBe(rgb);
    await expect(own.locator('.pv-cling-colour[data-hex="#4aa03f"]')).toHaveAttribute('aria-pressed', 'false');
  } finally {
    await page.request.post('/api/set_color_scheme', { data: { scheme: before } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The search with the sidebar (tablet rail, desktop): it opened below the
// navigation – with the sidebar that is the bottom edge of the window, so it
// was open but out of sight. Now in view, results included.
test('Neues Design: Suche am Tablet und Desktop sichtbar', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Seitenleiste');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    for (const [w, h] of [[820, 1180], [1024, 768], [1280, 900]]) {
      await page.setViewportSize({ width: w, height: h });
      await page.goto('/');
      await page.locator('#bu_quick_search').click();
      const input = page.locator('#ti_quick_search');
      await input.fill('Mathe');
      const panel = page.locator('#quick_search_panel');
      await expect(panel.locator('.quick-search-row').first()).toBeVisible();
      const box = (await panel.boundingBox())!;
      expect(box.y, `${w}`).toBeGreaterThanOrEqual(0);
      expect(box.y + box.height, `${w}`).toBeLessThanOrEqual(h);
      expect(box.x + box.width, `${w}`).toBeLessThanOrEqual(w);
      // nothing lies over the input
      const i = (await input.boundingBox())!;
      expect(await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.id, [i.x + 10, i.y + i.height / 2])).toBe('ti_quick_search');
      await page.keyboard.press('Escape');
      await expect(panel).toBeHidden();
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The profile's own switch follows when light/dark is changed from the menu.
test('Neues Design: Schalter im Profil folgt hell und dunkel aus dem Menü', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
  try {
    await page.goto('/profil');
    const sw = page.locator('.pv-mode-field button[data-mode="dark"]');
    await expect(sw).toHaveAttribute('aria-pressed', 'false');
    if (phone) await page.locator('#bu_pv_more').click();
    else await page.locator('#navbarDropdownProfile').click();
    await page.locator('.pv-mode-row button[data-mode="dark"]').click();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
    await expect(sw).toHaveAttribute('aria-pressed', 'true');
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Termine in the day's agenda (phones): they have a title of their own
// (event_title) and no subject. They showed as empty cards with a dot; now
// the title, the room and a calendar icon in the chip – no text glyph.
test('Neues Design: Termine in der Agenda mit Titel und Symbol', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Agenda am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  // the day the agenda shows first: today, on weekends the next Monday
  const day = new Date();
  while (day.getDay() === 0 || day.getDay() === 6) day.setDate(day.getDate() + 1);
  const date = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
  const title = `Sprechstunde Probe ${Date.now().toString(36)}`;
  const saved = await page.request.post('/api/save_event', {
    data: { title, jitsi: 'no', date, start_time: '15:00', end_time: '15:45', recipients: [ACCOUNTS.admin], description: '' },
  });
  expect(saved.status()).toBe(200);
  const eid = (await saved.json()).event.eid;
  try {
    await page.route('**/gen/**', (route) => route.continue());
    const card = page.locator('#pv_agenda .pv-ag-card', { hasText: title });
    await expect(async () => {
      await page.goto('/');
      await expect(card).toBeVisible({ timeout: 2_000 });
    }).toPass({ timeout: 30_000 });
    await expect(card.locator('.pv-ag-subj .ti-calendar-event')).toHaveCount(1);
    expect(await page.locator('#pv_agenda').innerText()).not.toMatch(/[•·]/);
  } finally {
    await page.request.post('/api/delete_event', { data: { eid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Dark mode: dark.css paints every .active grey (!important). The current or
// chosen element of the new design keeps the accent (the class in the
// Klassenarbeiten menu) or its own colour (the chosen palette colour).
test('Neues Design: Gewähltes bleibt dunkel sichtbar', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Klassenmenü als Sheet');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'dark' } });
  try {
    await page.goto('/tests/5a');
    await page.locator('.pv-tests-klasse').first().click();
    const active = page.locator('.pv-tests-menu-klasse.active');
    await expect(active).toBeVisible();
    const [bg, acc] = await active.evaluate((el) => {
      const probe = document.createElement('span');
      probe.style.color = getComputedStyle(el).getPropertyValue('--acc');
      document.body.appendChild(probe);
      const c = getComputedStyle(probe).color;
      probe.remove();
      return [getComputedStyle(el).backgroundColor, c];
    });
    expect(bg).toBe(acc);
    await page.goto('/profil');
    await page.locator('.pv-cling-colour[data-hex="#faaa21"]').click();
    expect(await page.locator('.pv-cling-colour.active').evaluate((el) => getComputedStyle(el).backgroundColor)).toBe('rgb(250, 170, 33)');
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: the shade behind the day's title only (the backdrop keeps its
// colours), its edge level with the plan button and the day tiles, the date
// level with the button's text.
test('Neues Design: Tageskopf am Handy bündig', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Tageskopf am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.pv-band-text h1')).toBeVisible();
    const x = await page.evaluate(() => {
      const left = (s: string) => Math.round(document.querySelector(s)!.getBoundingClientRect().x);
      const text = (s: string) => { const r = document.createRange(); r.selectNodeContents(document.querySelector(s)!); return Math.round(r.getBoundingClientRect().x); };
      const shade = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--band-scrim-a')) || 0;
      return { plan: left('.pv-band-plan'), pill: left('.pv-band-text'), tiles: left('.pv-strip-day'), planText: text('.pv-band-plan span'), title: text('.pv-band-text h1'), shade };
    });
    expect(Math.abs(x.pill - x.plan)).toBeLessThanOrEqual(1);
    expect(Math.abs(x.pill - x.tiles)).toBeLessThanOrEqual(1);
    // with a shade the title is inset like the button's text; without one
    // it stands at the edge itself (see "Tagestitel bündig mit und ohne Schatten")
    if (x.shade > 0) expect(Math.abs(x.title - x.planText)).toBeLessThanOrEqual(1);
    else expect(Math.abs(x.title - x.plan)).toBeLessThanOrEqual(1);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: "Mehr" slides up once. Bootstrap marks it .collapsing for a frame
// before .show; without the slide on that frame it stood there fully open,
// then jumped down and slid in – a flicker. Its top edge only ever rises,
// and the veil behind it fades in instead of popping up.
test('Neues Design: Mehr öffnet ohne Flackern', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Mehr am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await page.evaluate(() => {
      const m = document.getElementById('navbarTogglerDemo02')!;
      const tops: number[] = [];
      const veils: number[] = [];
      (window as any).pv_tops = tops;
      (window as any).pv_veils = veils;
      const t0 = performance.now();
      const tick = () => {
        if (getComputedStyle(m).display !== 'none') tops.push(Math.round(m.getBoundingClientRect().top));
        const v = document.querySelector('.pv-menu-veil:not([hidden])');
        if (v) veils.push(parseFloat(getComputedStyle(v).opacity));
        if (performance.now() - t0 < 500) requestAnimationFrame(tick);
      };
      document.getElementById('bu_pv_more')!.addEventListener('click', () => requestAnimationFrame(tick), { once: true, capture: true });
    });
    await page.locator('#bu_pv_more').click();
    await expect(page.locator('#navbarTogglerDemo02')).toHaveClass(/\bshow\b/);
    await page.waitForTimeout(600);
    const tops = await page.evaluate(() => (window as any).pv_tops as number[]);
    expect(tops.length).toBeGreaterThan(3);
    for (let i = 1; i < tops.length; i++) expect(tops[i], `frame ${i}: ${tops.join(', ')}`).toBeLessThanOrEqual(tops[i - 1] + 1);
    // the veil fades in with it (it popped up at full strength in one frame)
    const veils = await page.evaluate(() => (window as any).pv_veils as number[]);
    expect(veils.length).toBeGreaterThan(3);
    expect(veils[0], veils.join(', ')).toBeLessThan(0.6);
    for (let i = 1; i < veils.length; i++) expect(veils[i], veils.join(', ')).toBeGreaterThanOrEqual(veils[i - 1] - 0.01);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Waiting for the server: the old design shows "Einen Moment bitte" in the
// page after half a second (and pushes the page down); the new design a thin
// bar along the top edge instead, gone when the answer is there.
test('Neues Design: Warten als Leiste oben statt Kasten', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.route('**/api/pv_slow_probe', async (route) => {
    await new Promise((r) => setTimeout(r, 1500));
    await route.fulfill({ json: { ok: true } });
  });
  const call = () => page.evaluate(() => { (window as any).api_call('/api/pv_slow_probe', {}, () => { (window as any).pv_probe_done = true; }); });
  // the old design: the box, as before
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  await page.goto('/profil');
  await call();
  await expect(page.locator('.api_messages').first()).toContainText('Einen Moment bitte');
  await expect(page.locator('.pv-busy')).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => (window as any).pv_probe_done === true)).toBe(true);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/profil');
    const bar = page.locator('.pv-busy');
    await expect(bar).toBeHidden();
    await call();
    await expect(bar).toBeVisible();
    const box = (await bar.boundingBox())!;
    expect(box.y).toBe(0);
    expect(box.height).toBeLessThanOrEqual(4);
    // on its own opaque track: an accent bar on a see-through track vanished
    // on a backdrop of the accent's colour (only visible behind the sheet's
    // dimming)
    const alpha = await bar.evaluate((el) => {
      const ctx = document.createElement('canvas').getContext('2d')!;
      ctx.fillStyle = getComputedStyle(el).backgroundColor;
      ctx.fillRect(0, 0, 1, 1);
      return ctx.getImageData(0, 0, 1, 1).data[3];
    });
    expect(alpha).toBe(255);
    // no box in the page
    await expect(page.locator('.api_messages').first()).toBeHidden();
    await expect.poll(() => page.evaluate(() => (window as any).pv_probe_done === true)).toBe(true);
    await expect(bar).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// A lesson cancelled for oneself but taught by someone else (a swap): the
// server marks the old parts itself (<s>Mathematik</s> Latein (9c)
// <s>Sp</s>). Only those are crossed out, the replacement stays readable; a
// plainly cancelled lesson is crossed out as a whole.
test('Neues Design: Tausch durchgestrichen nur im Alten', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'agenda and week list on phones');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    const add = async () => page.evaluate(() => {
      const w = window as any;
      const d = new Date(w.calendar.getDate());
      while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
      const a = new Date(d); a.setHours(17, 0, 0, 0);
      const b = new Date(d); b.setHours(18, 0, 0, 0);
      w.calendar.addEvent({ start: a, end: new Date(a.getTime() + 45 * 60000),
        extendedProps: { lesson: true, entfall: true, label: '<s>Mathematik</s> <b>Latein</b> (9c) <s>Sp</s> Xy', label_short: '<b>La</b>', raum: '216', pv_probe: 'swap' } });
      w.calendar.addEvent({ start: b, end: new Date(b.getTime() + 45 * 60000),
        extendedProps: { lesson: true, entfall: true, label: '<b>Mathematik</b> (9c)', label_short: '<b>Ma</b>', raum: '216', pv_probe: 'off' } });
    });
    const deco = (el: Element) => getComputedStyle(el).textDecorationLine;
    // the day
    await page.goto('/');
    await expect(page.locator('#pv_agenda')).toBeVisible();
    await add();
    const swapDay = page.locator('#pv_agenda .pv-ag-card.pv-ag-off', { hasText: 'Latein' }).locator('.pv-ag-title b').first();
    const offDay = page.locator('#pv_agenda .pv-ag-card.pv-ag-off', { hasText: 'Mathematik (9c)' }).filter({ hasNotText: 'Latein' }).locator('.pv-ag-title b').first();
    await expect(swapDay).toBeVisible();
    expect(await swapDay.evaluate(deco)).not.toContain('line-through');
    expect(await swapDay.locator('s').first().evaluate(deco)).toContain('line-through');
    // the new subject (the label's own <b>) stays readable
    expect(await swapDay.locator('b', { hasText: 'Latein' }).evaluate(deco)).not.toContain('line-through');
    expect(await offDay.evaluate(deco)).toContain('line-through');
    // the week
    await page.goto('/#woche');
    await expect(page.locator('#pv_agenda .pv-week-day').first()).toBeVisible();
    await add();
    const swapWeek = page.locator('.pv-week-row.pv-ag-off .pv-week-title', { hasText: 'Latein' }).first();
    const offWeek = page.locator('.pv-week-row.pv-ag-off .pv-week-title', { hasText: 'Mathematik (9c)' }).filter({ hasNotText: 'Latein' }).first();
    await expect(swapWeek).toBeVisible();
    expect(await swapWeek.evaluate(deco)).not.toContain('line-through');
    expect(await offWeek.evaluate(deco)).toContain('line-through');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The day's title on phones: with a shade behind it, the shade's edge is
// level with the plan button and the day tiles; without one, the text itself.
test('Neues Design: Tagestitel bündig mit und ohne Schatten', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'the day band on phones');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('#pv_day_band .pv-band-text')).toBeVisible();
    const measure = (alpha: string) => page.evaluate((a) => {
      document.documentElement.style.setProperty('--band-scrim-a', a);
      const left = (s: string) => document.querySelector(s)!.getBoundingClientRect().left;
      const range = document.createRange();
      range.selectNodeContents(document.querySelector('#pv_day_band h1')!);
      return { pill: left('#pv_day_band .pv-band-text'), text: range.getBoundingClientRect().left, plan: left('#pv_day_band .pv-band-top > *'), tile: left('.pv-day-strip > *') };
    }, alpha);
    const plain = await measure('0.00');
    expect(Math.abs(plain.text - plain.plan)).toBeLessThan(1.5);
    expect(Math.abs(plain.text - plain.tile)).toBeLessThan(1.5);
    const shaded = await measure('0.35');
    expect(Math.abs(shaded.pill - shaded.plan)).toBeLessThan(1.5);
    expect(shaded.text - shaded.pill).toBeGreaterThan(6);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The line of the current time: as wide as the lessons of its day, not across
// the whole column (it reached into the next day's edge).
test('Neues Design: Zeitlinie so breit wie die Stunden', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the week grid');
  const wednesday = displayedSchoolWeek()[2];
  wednesday.setHours(10, 0, 0, 0);
  await page.clock.install({ time: wednesday });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const line = page.locator('.fc-timegrid-now-indicator-line');
    await expect(line).toBeVisible();
    const r = await line.evaluate((el) => {
      const events = el.closest('.fc-timegrid-col')!.querySelector('.fc-timegrid-col-events')!.getBoundingClientRect();
      const b = el.getBoundingClientRect();
      return { left: b.left, right: b.right, eventsLeft: events.left, eventsRight: events.right };
    });
    expect(Math.abs(r.left - (r.eventsLeft + 2))).toBeLessThanOrEqual(1.5);
    expect(Math.abs(r.right - (r.eventsRight - 2))).toBeLessThanOrEqual(1.5);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// One's own lesson now or next: its planning and Mail without opening the
// dialog. The button says »Planung« (»Unterricht« would not fit, »Kursbuch«
// is the old word) and leads to the lesson in the Kursbuch.
test('Neues Design: eigene Stunde mit »Planung« und »Mail«', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the side column »Jetzt / Als Nächstes«');
  const time = displayedSchoolWeek()[2];
  time.setHours(8, 5, 0, 0);
  await page.clock.install({ time });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const actions = page.locator('.pv-side-box .pv-ag-action');
    await expect(actions).toHaveText(['Planung', 'Mail']);
    await expect(actions.first()).toHaveAttribute('href', /^\/lessons\/[^#]+#\d+$/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Schleier folgt dem Sheet beim Ziehen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Sheets nur am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const cdp = await page.context().newCDPSession(page);
    const opacity = (sel: string) => page.locator(sel).evaluate((el) => parseFloat(getComputedStyle(el).opacity));
    // pulls the sheet down by dy (from 10 px below its top) and holds it there
    const pull = async (sel: string, dy: number) => {
      const box = (await page.locator(sel).boundingBox())!;
      const x = box.x + box.width / 2, y = box.y + 10;
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
      for (let i = 1; i <= 5; i++) {
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y: y + (dy * i) / 5 }] });
        await page.waitForTimeout(30);
      }
      // held a moment: a slow pull, not a flick
      await page.waitForTimeout(300);
      return box.height;
    };
    const release = () => cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    for (const s of [
      { name: 'Mehr', open: () => page.locator('#bu_pv_more').click(), sheet: '#navbarTogglerDemo02', veil: '.pv-menu-veil:not(.pv-plan-veil)' },
      { name: 'Plan', open: () => page.locator('#pv_day_band .pv-band-plan').click(), sheet: '.pv-plan-menu', veil: '.pv-plan-veil' },
    ]) {
      await s.open();
      await expect(page.locator(s.sheet)).toBeVisible();
      await page.waitForTimeout(400);
      expect(await opacity(s.veil), s.name).toBeCloseTo(1, 2);
      // a grab handle at the top, like every sheet that can be pulled down
      expect(await page.locator(s.sheet).evaluate((el) => {
        const h = getComputedStyle(el, '::before');
        return h.content !== 'none' && h.height === '4px' && h.width === '40px';
      }), s.name).toBe(true);
      // a short pull: the veil as strong as the part of the sheet still showing
      const h = await pull(s.sheet, 60);
      expect(await opacity(s.veil), s.name).toBeCloseTo(1 - 60 / h, 1);
      expect(await opacity(s.veil), s.name).toBeLessThan(0.97);
      // let go: the sheet springs back, the veil comes back with it
      await release();
      await expect.poll(() => opacity(s.veil), { message: s.name }).toBeCloseTo(1, 2);
      // pulled far: the sheet closes, the veil fades out with it
      await pull(s.sheet, 200);
      expect(await opacity(s.veil), s.name).toBeLessThan(0.9);
      await release();
      await expect(page.locator(s.sheet), s.name).toBeHidden();
      await expect(page.locator(`${s.veil}:visible`), s.name).toHaveCount(0);
    }
    // the next time "Mehr" opens, its veil is at full strength again
    await page.locator('#bu_pv_more').click();
    await page.waitForTimeout(400);
    expect(await opacity('.pv-menu-veil:not(.pv-plan-veil)')).toBeCloseTo(1, 2);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The week (desktop): entries that follow each other directly keep a little
// air between them; a break duty shows what it is on its first line, time
// and place below – at 35 minutes both lines fit, at 20 the title still does.
test('Neues Design: Woche, Luft zwischen Einträgen, Aufsicht lesbar', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'die Woche als Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    await page.evaluate(() => {
      const w = window as any;
      const lesson = w.calendar.getEvents().find((e: any) => !e.allDay && e.extendedProps.lesson && !e.extendedProps.pausenaufsicht);
      const day = new Date(w.calendar.view.currentStart);
      day.setDate(day.getDate() + 1);
      const at = (h: number, m: number) => { const d = new Date(day); d.setHours(h, m, 0, 0); return d; };
      const copy = (start: Date, end: Date, cls: string) => w.calendar.addEvent({
        start, end, backgroundColor: lesson.backgroundColor, textColor: lesson.textColor,
        classNames: [...lesson.classNames, cls], extendedProps: { ...lesson.extendedProps },
      });
      const duty = (start: Date, end: Date, cls: string) => {
        const flat: any = { lesson: true, pausenaufsicht: true, raum: 'Hof Brunnen', label: 'Pausenaufsicht', label_short: 'Pausenaufsicht' };
        w.preview_text_color(flat);
        w.calendar.addEvent({ start, end, textColor: flat.textColor, classNames: [...flat.classNames, cls], extendedProps: flat });
      };
      copy(at(12, 20), at(13, 5), 'zz-a');
      duty(at(13, 5), at(13, 40), 'zz-duty');
      copy(at(13, 40), at(14, 25), 'zz-b');
      duty(at(14, 35), at(14, 55), 'zz-short');
    });
    await expect(page.locator('.zz-short')).toBeVisible();
    const m = await page.evaluate(() => {
      const r = (sel: string) => document.querySelector(sel)!.getBoundingClientRect();
      const a = r('.zz-a'), d = r('.zz-duty'), b = r('.zz-b'), s = r('.zz-short');
      return {
        duty_class: document.querySelector('.zz-duty')!.classList.contains('pv-duty'),
        gap1: d.top - a.bottom, gap2: b.top - d.bottom,
        title: document.querySelector('.zz-duty .pv-ev-title')!.textContent!.trim(),
        title_in: r('.zz-duty .pv-ev-title').bottom <= d.bottom + 0.5,
        meta_in: r('.zz-duty .pv-ev-meta').bottom <= d.bottom + 0.5,
        title_first: r('.zz-duty .pv-ev-title').top < r('.zz-duty .pv-ev-meta').top,
        short_title_in: r('.zz-short .pv-ev-title').bottom <= s.bottom + 0.5,
        // nothing lies over the title (the second row is cut, not pushed up)
        short_apart: r('.zz-short .pv-ev-meta').top >= r('.zz-short .pv-ev-title').bottom - 0.5,
        short_title_height: r('.zz-short .pv-ev-title').height,
        title_height: r('.zz-duty .pv-ev-title').height,
      };
    });
    expect(m.duty_class).toBe(true);
    expect(m.gap1).toBeGreaterThanOrEqual(2);
    expect(m.gap2).toBeGreaterThanOrEqual(2);
    expect(m.title).toBe('Pausenaufsicht');
    expect(m.title_first).toBe(true);
    expect(m.title_in).toBe(true);
    expect(m.meta_in).toBe(true);
    expect(m.short_title_in).toBe(true);
    expect(m.short_apart).toBe(true);
    expect(m.short_title_height).toBeCloseTo(m.title_height, 0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Hell / Auto / Dunkel: »Auto« follows the device – in place when it
// switches while the page is open, on the next page through a cookie the
// browser keeps (Main.effective_dark), also when the device switched while
// no page was open (the head loads the page once more). The old design
// keeps its entry and follows »Auto« too.
test('Neues Design: Darstellung hell, automatisch oder dunkel', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
  const open = async () => {
    if (phone) {
      if (!(await page.locator('#navbarTogglerDemo02.show').count())) await page.locator('#bu_pv_more').click();
    } else if (!(await page.locator('[aria-labelledby="navbarDropdownProfile"].show').count())) {
      await page.locator('#navbarDropdownProfile').click();
    }
  };
  const choice = (mode: string) => page.locator(`.pv-mode-row button[data-mode="${mode}"]`);
  const dark = () => page.locator('body').evaluate((b) => b.classList.contains('dark'));
  try {
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.goto('/');
    await page.waitForLoadState('load');
    let loads = 0;
    page.on('load', () => loads++);
    expect(await dark()).toBe(false);
    // Auto on a dark device: dark at once
    await open();
    await expect(choice('auto')).toBeVisible();
    await choice('auto').click();
    await expect(choice('auto')).toHaveAttribute('aria-pressed', 'true');
    await expect.poll(dark).toBe(true);
    // the device switches while the page is open: it follows, no reload
    await page.emulateMedia({ colorScheme: 'light' });
    await expect.poll(dark).toBe(false);
    await page.emulateMedia({ colorScheme: 'dark' });
    await expect.poll(dark).toBe(true);
    expect(loads).toBe(0);
    // the next page comes dark from the server (the cookie)
    await page.reload();
    expect(await dark()).toBe(true);
    // the device switched while no page was open: the page comes right anyway
    await page.emulateMedia({ colorScheme: 'light' });
    await page.goto('/profil');
    await expect.poll(dark).toBe(false);
    await expect(page.locator('.pv-mode-field button[data-mode="auto"]')).toHaveAttribute('aria-pressed', 'true');
    // Hell stays light on a dark device
    await page.emulateMedia({ colorScheme: 'dark' });
    await page.locator('.pv-mode-field button[data-mode="light"]').click();
    await expect(page.locator('.pv-mode-field button[data-mode="light"]')).toHaveAttribute('aria-pressed', 'true');
    await expect.poll(dark).toBe(false);
    await page.reload();
    expect(await dark()).toBe(false);
    // the old design: its own entry as before, and »Auto« set elsewhere works there too
    await page.request.post('/api/set_dark_css', { data: { mode: 'auto' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await page.goto('/');
    await expect.poll(dark).toBe(true);
    await expect(page.locator('.pv-mode-row')).toHaveCount(0);
    await expect(page.locator('.nav-light')).toHaveCount(1);
  } finally {
    await page.emulateMedia({ colorScheme: null });
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: a block whose text doesn't fit is cut after the last whole
// line (with …), never in the middle of a line; one-line titles end with …
// (timetable.html, preview_fit_event). Long homework, topics and titles are
// put into the lessons on screen through the calendar.
test('Neues Design: Stundenplan schneidet Text nur nach ganzen Zeilen ab', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const changed = await page.evaluate(() => {
      type Ev = { allDay: boolean; extendedProps: Record<string, unknown>; setExtendedProp: (k: string, v: unknown) => void };
      const w = window as unknown as { calendar: { getEvents: () => Ev[] } };
      const lessons = w.calendar.getEvents().filter((e) => !e.allDay && e.extendedProps.lesson);
      const long = 'Arbeitsblatt 2, Nummer 5, 6 und 7; dazu im Buch Seite 42 bis 45 lesen und die Fragen 1 bis 9 schriftlich beantworten';
      for (const e of lessons) {
        e.setExtendedProp('data', { ...(e.extendedProps.data as object || {}), hausaufgaben_text: long, stundenthema_text: long });
        e.setExtendedProp('label', 'Informationstechnischer Grundkurs Mathematik (6a) Hübbenet, von Specht');
      }
      return lessons.length;
    });
    expect(changed).toBeGreaterThan(0);
    await page.waitForTimeout(800);
    const result = await page.evaluate(() => {
      const cut: string[] = [];
      let fitted = 0;
      for (const main of Array.from(document.querySelectorAll<HTMLElement>('.fc-timegrid-event .fc-event-main'))) {
        const box = main.getBoundingClientRect();
        if (box.height === 0) continue;
        const limit = box.bottom - (parseFloat(getComputedStyle(main).paddingBottom) || 0) + 1;
        for (const l of Array.from(main.querySelectorAll<HTMLElement>('.pv-ev-title, .line2, .pv-ev-label, .pv-ev-desc, .pv-ev-fit, .hide-br'))) {
          if (l.classList.contains('pv-fit-hidden') || l.querySelector('.pv-fit-clamp') || l.classList.contains('pv-fit-clamp')) { fitted += 1; }
          if (l.classList.contains('pv-fit-hidden') || getComputedStyle(l).display === 'none') continue;
          const r = l.getBoundingClientRect();
          if (r.height > 0 && r.bottom > limit) cut.push(`${l.className}: ${Math.round(r.bottom - limit)}px`);
        }
        for (const t of Array.from(main.querySelectorAll<HTMLElement>('.pv-ev-title > div'))) {
          if (t.scrollWidth > t.clientWidth + 1 && getComputedStyle(t).textOverflow !== 'ellipsis') cut.push('title without …');
        }
      }
      return { cut, fitted };
    });
    expect(result.cut).toEqual([]);
    expect(result.fitted).toBeGreaterThan(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week, a double lesson with a long topic and homework: the homework
// shows (its label and at least its first line), the topic gives way – an
// »HA« chip without the homework to read looks like no homework
// (timetable.html, preview_fit_event)
test('Neues Design: Stundenplan zeigt die Hausaufgaben vor dem Thema', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const changed = await page.evaluate(() => {
      type Ev = { allDay: boolean; extendedProps: Record<string, unknown>; setExtendedProp: (k: string, v: unknown) => void };
      const w = window as unknown as { calendar: { getEvents: () => Ev[] } };
      const doubles = w.calendar.getEvents().filter((e) => !e.allDay && e.extendedProps.lesson && (e.extendedProps.count as number) > 1);
      const topic = 'Wiederholung der Satzglieder, dann Übersetzung des zweiten Abschnitts mit Vokabelarbeit und einer kurzen Besprechung der Hausaufgabe von letzter Woche';
      for (const e of doubles) e.setExtendedProp('data', { ...(e.extendedProps.data as object || {}), hausaufgaben_text: 'Vokabeln lernen', stundenthema_text: topic });
      return doubles.length;
    });
    expect(changed).toBeGreaterThan(0);
    await page.waitForTimeout(800);
    const blocks = await page.evaluate(() => Array.from(document.querySelectorAll<HTMLElement>('.fc-timegrid-event .fc-event-main'))
      .filter((main) => main.querySelector('.pv-ev-topic') && main.querySelector('.pv-ev-homework'))
      .map((main) => {
        const hw = main.querySelector<HTMLElement>('.pv-ev-homework')!;
        const box = main.getBoundingClientRect();
        const limit = box.bottom - (parseFloat(getComputedStyle(main).paddingBottom) || 0) + 1;
        // room below the title for a line (the markers sit beside the first
        // detail line, no row of their own)
        const row = main.querySelector<HTMLElement>('.pv-ev-title')!.getBoundingClientRect();
        return { room: Math.round(limit - row.bottom), homework: !hw.classList.contains('pv-fit-hidden'),
                 inside: hw.getBoundingClientRect().bottom <= limit, text: hw.textContent,
                 label: main.querySelectorAll('.pv-ev-label').length,
                 // the markers: no row of their own, level with the first detail line
                 row: main.querySelectorAll('.line2').length,
                 chip: (() => {
                   const chip = main.querySelector<HTMLElement>('.pv-ev-float');
                   const first = main.querySelector<HTMLElement>('.pv-ev-desc');
                   if (!chip || !first) return 'missing';
                   const c = chip.getBoundingClientRect(), f = first.getBoundingClientRect();
                   const lh = parseFloat(getComputedStyle(first).lineHeight);
                   return c.height > 0 && c.height <= lh + 1 && Math.abs(c.top - f.top) <= 2 ? 'beside' : `off ${Math.round(c.top - f.top)} ${Math.round(c.height)}/${lh}`;
                 })() };
      }));
    // no row of its own for the label: the text starts with »HA:«
    expect(blocks.length).toBeGreaterThan(0);
    for (const b of blocks) expect(b.label).toBe(0);
    // where there is room for a line, the homework shows (the topic gives way)
    const roomy = blocks.filter((b) => b.room >= 24);
    expect(roomy.length).toBeGreaterThan(0);
    for (const b of roomy) expect(b).toEqual({ room: b.room, homework: true, inside: true, text: 'HA: Vokabeln lernen', label: 0, row: 0, chip: 'beside' });
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: appointments, duties and other blocks without a subject
// colour sit on the card's surface with a hairline – a grey fill clashed
// with today's tinted column (preview.css, .pv-quiet)
test('Neues Design: Stundenplan, ruhige Blöcke auf heller Fläche, auch heute', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const today = page.locator('.fc-timegrid-col.fc-day-today');
    test.skip(await today.count() === 0, 'heute ist kein Schultag in der Woche');
    await page.evaluate(() => {
      const w = window as any;
      const start = new Date(); start.setHours(15, 0, 0, 0);
      const end = new Date(); end.setHours(16, 0, 0, 0);
      const ev: Record<string, unknown> = { is_event: true, event_title: 'Probe ruhig', organized_by: 'Test', start, end, eid: 'probe-ruhig' };
      ev.color = w.timetable_event_color(ev);
      w.preview_text_color(ev);
      w.calendar.addEvent(ev);
    });
    const block = today.locator('.fc-timegrid-event.pv-quiet', { hasText: 'Probe ruhig' });
    await expect(block).toBeVisible();
    const look = await block.evaluate((el) => {
      const probe = document.createElement('div');
      probe.style.background = 'var(--pv-surface)';
      document.body.appendChild(probe);
      const surface = getComputedStyle(probe).backgroundColor;
      probe.remove();
      const col = getComputedStyle(el.closest('.fc-timegrid-col')!).backgroundColor;
      const cs = getComputedStyle(el);
      return { surface: cs.backgroundColor === surface, notColumn: cs.backgroundColor !== col, hairline: /inset 0px 0px 0px 1px/.test(cs.boxShadow) || /0px 0px 0px 1px .*inset/.test(cs.boxShadow) };
    });
    expect(look).toEqual({ surface: true, notColumn: true, hairline: true });
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: every half hour has the same height in every week – a late
// Termin makes the grid longer, it doesn't squeeze the lessons – and the
// page keeps its width when a longer week brings a scrollbar.
test('Neues Design: Stundenplan, gleiche Stundenhöhe und Breite in jeder Woche', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const measure = () => page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('.fc-timegrid-slots tr'));
      return { rows: rows.length, row: rows[0].getBoundingClientRect().height,
               width: document.querySelector('.fc-view-harness')!.getBoundingClientRect().width };
    });
    const before = await measure();
    // an Elternabend until 20:30, as in a week with one
    await page.evaluate(() => (window as any).preview_time_range([{ is_event: true, start: '2026-11-23T19:00:00', end: '2026-11-23T20:30:00' }]));
    await expect.poll(async () => (await measure()).rows).toBeGreaterThan(before.rows);
    const after = await measure();
    expect(after.row).toBeCloseTo(before.row, 0);
    expect(after.width).toBeCloseTo(before.width, 0);
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).scrollbarGutter)).toBe('stable');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: everything below a block's title (a lesson's topic and
// homework, a Termin's calendar line and description) has one size, the same
// in lessons, Termine and events from an external calendar; the time and the
// markers (HA …) are no details. Termine had their details as large as the
// title, lessons smaller (doc/Gestaltung.md, »Blöcke im Stundenplan«).
test('Neues Design: Stundenplan, Details in allen Blöcken gleich groß', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    await page.evaluate(() => {
      type Ev = { allDay: boolean; extendedProps: Record<string, unknown>; setExtendedProp: (k: string, v: unknown) => void };
      const w = window as unknown as { calendar: { getEvents: () => Ev[]; addEvent: (e: object) => void; view: { activeStart: Date } } };
      for (const e of w.calendar.getEvents().filter((e) => !e.allDay && e.extendedProps.lesson)) {
        e.setExtendedProp('data', { ...(e.extendedProps.data as object || {}), hausaufgaben_text: 'AB 4 beenden', stundenthema_text: 'Brüche' });
      }
      const at = (days: number, h: number) => { const d = new Date(w.calendar.view.activeStart); d.setDate(d.getDate() + days); d.setHours(h, 0, 0, 0); return d; };
      const termin = { is_event: true, organized_by: 'Fachbegleitung', description: 'Ort: Aula<br />Bitte pünktlich' };
      w.calendar.addEvent({ ...termin, event_title: 'Probe Termin', start: at(2, 13), end: at(2, 15), eid: 'probe-termin' });
      w.calendar.addEvent({ ...termin, event_title: 'Probe Kalender', source: 'ical', classNames: ['pv-ical'], start: at(3, 13), end: at(3, 15), eid: 'probe-ical' });
    });
    await page.waitForTimeout(800);
    const sizes = await page.evaluate(() => {
      const px = (el: Element) => getComputedStyle(el).fontSize;
      const found: Record<string, string[]> = {};
      const add = (key: string, el: Element | null) => { if (el) (found[key] ??= []).push(px(el)); };
      for (const main of Array.from(document.querySelectorAll('.fc-timegrid-event .fc-event-main'))) {
        add('title', main.querySelector('.pv-ev-title b'));
        main.querySelectorAll('.pv-ev-label').forEach((el) => add('lesson label', el));
        main.querySelectorAll('.pv-ev-desc').forEach((el) => add('lesson text', el));
        main.querySelectorAll('.pv-ev-hw-tag').forEach((el) => add('homework tag', el));
        main.querySelectorAll('.pv-ev-inline-topic').forEach((el) => add('lesson topic', el));
        main.querySelectorAll('.line2:not(.pv-ev-row) > span:not(.cem)').forEach((el) => add('termin line', el));
        main.querySelectorAll('.pv-ev-fit').forEach((el) => add('termin text', el));
      }
      return found;
    });
    // (homework in double lessons: no label row, the text starts with »HA:«)
    const details = ['homework tag', 'lesson text', 'termin line', 'termin text'];
    for (const key of details) expect(sizes[key]?.length, key).toBeGreaterThan(key.startsWith('termin') ? 1 : 0);
    const all = new Set(Object.entries(sizes).filter(([k]) => k !== 'title').flatMap(([, v]) => v));
    expect([...all], JSON.stringify(sizes)).toHaveLength(1);
    expect(parseFloat([...all][0])).toBeLessThan(parseFloat(sizes.title[0]));
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: entries below the visible part get a chip at the bottom of
// their day's column – only from 16:00 on (an Elternabend); the afternoon's
// lessons below the fold are expected and get none.
test('Neues Design: Stundenplan, Hinweis unten nur für Einträge ab 16 Uhr', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1280, height: 600 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    await page.evaluate(() => {
      const w = window as unknown as { calendar: { addEvent: (e: object) => void; view: { activeStart: Date } } };
      const at = (days: number, h: number, m = 0) => { const d = new Date(w.calendar.view.activeStart); d.setDate(d.getDate() + days); d.setHours(h, m, 0, 0); return d; };
      const termin = { is_event: true, organized_by: 'Probe', description: '' };
      w.calendar.addEvent({ ...termin, event_title: 'Probe Nachmittag', start: at(1, 13, 40), end: at(1, 15), eid: 'probe-nachmittag' });
      w.calendar.addEvent({ ...termin, event_title: 'Probe Abend', start: at(2, 19), end: at(2, 20), eid: 'probe-abend' });
    });
    // the grid reaches as far as the week's entries (preview_time_range)
    await page.evaluate(() => (window as any).preview_time_range([{ is_event: true, start: '2026-11-23T19:00:00', end: '2026-11-23T20:00:00' }]));
    await expect(page.locator('.fc-timegrid-event', { hasText: 'Probe Abend' })).toHaveCount(1);
    await page.evaluate(() => { window.scrollTo(0, 0); (window as any).preview_below_hints(); });
    // the afternoon entry is below the fold, but gets no chip
    const afternoon = page.locator('.fc-timegrid-event', { hasText: 'Probe Nachmittag' });
    expect(await afternoon.evaluate((el) => el.getBoundingClientRect().top)).toBeGreaterThan(600);
    const chips = page.locator('.pv-below');
    await expect(chips.filter({ hasText: 'Probe Abend' })).toHaveCount(1);
    await expect(chips.filter({ hasText: 'Nachmittag' })).toHaveCount(0);
    for (const text of await chips.locator('.pv-below-text').allTextContents()) {
      expect(text.match(/^(\d+):/)?.[1] ?? '99', text).toMatch(/^(1[6-9]|2\d|99)$/);
    }
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: a Termin straight from the timetable for everyone who may
// create Termine – a click on a free spot marks an hour, dragging marks the
// time dragged over, a right click marks an hour too; a small popover leads
// on to /events with date and time filled in. Students get nothing.
async function freeSpot(page: Page, below = 0) {
  return page.evaluate((below) => {
    const lanes = Array.from(document.querySelectorAll<HTMLElement>('#calendar .fc-timegrid-slot-lane[data-time]'));
    for (const col of Array.from(document.querySelectorAll<HTMLElement>('#calendar .fc-timegrid-col[data-date]'))) {
      const c = col.getBoundingClientRect();
      for (let i = 0; i + below < lanes.length; i++) {
        const spots = [0, below].map((k) => {
          const r = lanes[i + k].getBoundingClientRect();
          return { x: c.left + c.width / 2, y: r.top + r.height / 2 };
        });
        const free = spots.every((p) => p.y > 0 && p.y < window.innerHeight - 30 &&
          !document.elementsFromPoint(p.x, p.y).some((el) => el.closest('.fc-timegrid-event-harness, .fc-event, .pv-below')));
        if (free && lanes[i].dataset.time! >= '08:00:00') return { ...spots[0], to: spots[1], date: col.dataset.date!, time: lanes[i].dataset.time!.slice(0, 5) };
      }
    }
    return null;
  }, below);
}

const plusMinutes = (hhmm: string, m: number) => {
  const t = Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3)) + m;
  return `${String(Math.floor(t / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};
const short = (hhmm: string) => hhmm.replace(/^0/, '');

test('Neues Design: Termin aus dem Stundenplan anlegen (Klick, Ziehen, Rechtsklick)', async ({ page, newUserPage }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    // low enough that the page scrolls
    await page.setViewportSize({ width: 1440, height: 700 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const pop = page.locator('.pv-create-pop');
    await expect(pop).toHaveCount(0);

    // a click: an hour, the time marked in the grid
    const spot = (await freeSpot(page))!;
    expect(spot).not.toBeNull();
    // the page stays where it is (it jumped to the popover before it was placed)
    const scrolled = await page.evaluate(() => window.scrollY);
    await page.mouse.click(spot.x, spot.y);
    await expect(pop).toBeVisible();
    await page.waitForTimeout(300);
    expect(await page.evaluate(() => window.scrollY)).toBe(scrolled);
    await expect(pop.getByRole('button', { name: 'Termin erstellen…' })).toBeFocused();
    // the close button level with the title, its X in its middle
    const level = await pop.evaluate((el) => {
      const mid = (r: DOMRect) => r.top + r.height / 2;
      const title = mid(el.querySelector('.pv-create-title')!.getBoundingClientRect());
      const button = mid(el.querySelector('.pv-create-close')!.getBoundingClientRect());
      const glyph = el.querySelector('.pv-create-close i')!.getBoundingClientRect();
      return { button: button - title, glyph: mid(glyph) - button, size: glyph.height };
    });
    expect(Math.abs(level.button), JSON.stringify(level)).toBeLessThan(2);
    expect(Math.abs(level.glyph), JSON.stringify(level)).toBeLessThan(2);
    await expect(pop.locator('.pv-create-when')).toContainText(`${short(spot.time)} bis ${short(plusMinutes(spot.time, 60))} Uhr`);
    await expect(page.locator('#calendar .fc-event-mirror')).toHaveCount(1);
    await page.keyboard.press('Escape');
    await expect(pop).toHaveCount(0);
    await expect(page.locator('#calendar .fc-event-mirror')).toHaveCount(0);

    // a right click: the same
    await page.mouse.click(spot.x, spot.y, { button: 'right' });
    await expect(pop.locator('.pv-create-when')).toContainText(`${short(spot.time)} bis ${short(plusMinutes(spot.time, 60))} Uhr`);
    await pop.locator('.pv-create-close').click();
    await expect(pop).toHaveCount(0);

    // dragging over free time: just that time
    const drag = (await freeSpot(page, 2))!;
    expect(drag).not.toBeNull();
    await page.mouse.move(drag.x, drag.y);
    await page.mouse.down();
    await page.mouse.move(drag.to.x, drag.to.y, { steps: 8 });
    await page.mouse.up();
    await expect(pop.locator('.pv-create-when')).toContainText(`${short(drag.time)} bis ${short(plusMinutes(drag.time, 90))} Uhr`);

    // on to /events: date and time filled in
    await pop.getByRole('button', { name: 'Termin erstellen…' }).click();
    await expect(page).toHaveURL(/\/events$/);
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    await expect(page.locator('#ti_date')).toHaveValue(drag.date);
    await expect(page.locator('#ti_start_time')).toHaveValue(drag.time);
    await expect(page.locator('#ti_end_time')).toHaveValue(plusMinutes(drag.time, 90));

    // students can't create Termine: a click does nothing
    expect((await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'on' } })).status()).toBe(200);
    const student = await newUserPage();
    await login(student, ACCOUNTS.schueler);
    await student.setViewportSize({ width: 1440, height: 1000 });
    await student.goto('/');
    await expect(student.locator('.fc-timegrid-event').first()).toBeVisible();
    const free = (await freeSpot(student))!;
    await student.mouse.click(free.x, free.y);
    await student.mouse.click(free.x, free.y, { button: 'right' });
    await student.waitForTimeout(300);
    await expect(student.locator('.pv-create-pop')).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.schueler, mode: 'off' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop week: the school's dates right in the all-day row for those who
// manage them – a click on a free day adds one, a click on one edits it,
// »Löschen« asks first. Others still see the details.
test('Neues Design: Termine der Schule im Stundenplan anlegen, ändern, löschen', async ({ page, newUserPage }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  test.setTimeout(120_000);
  const tag = Date.now().toString(36);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  let id = '';
  try {
    await page.setViewportSize({ width: 1440, height: 1000 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    // a free spot in the all-day row: Friday of the week shown (never in the
    // past – past dates are cleared when the dates are read)
    const day = page.locator('#calendar .fc-daygrid-body .fc-daygrid-day').nth(4);
    const date = (await day.getAttribute('data-date'))!;
    const box = (await day.boundingBox())!;
    await page.mouse.click(box.x + box.width / 2, box.y + box.height - 6);
    const pop = page.locator('.pv-school-pop');
    await expect(pop).toBeVisible();
    await expect(pop.locator('.pv-create-title')).toHaveText('Neuer Termin der Schule');
    await expect(page.locator('#ti_school_date_from')).toHaveValue(date);
    await expect(page.locator('#ti_school_date_to')).toHaveValue(date);
    await expect(page.locator('#ti_school_date_title')).toBeFocused();
    await expect(pop.getByRole('button', { name: 'Eintragen' })).toBeDisabled();
    // the date fields inside the popover
    const inside = await pop.evaluate((p) => {
      const r = p.getBoundingClientRect();
      return Array.from(p.querySelectorAll('input')).every((i) => i.getBoundingClientRect().right <= r.right - 8);
    });
    expect(inside).toBe(true);
    await page.locator('#ti_school_date_title').fill(`16.30 Uhr Probe ${tag}`);
    const saved = page.waitForResponse('**/api/save_website_event');
    await pop.getByRole('button', { name: 'Eintragen' }).click();
    id = (await (await saved).json()).id;
    expect(id).toBeTruthy();
    await expect(pop).toHaveCount(0);
    const chip = page.locator('#calendar .fc-daygrid-event', { hasText: `Probe ${tag}` });
    await expect(chip).toHaveCount(1);

    // a click on it: edit
    await chip.click();
    await expect(pop.locator('.pv-create-title')).toHaveText('Termin der Schule');
    await expect(page.locator('#ti_school_date_title')).toHaveValue(`16.30 Uhr Probe ${tag}`);
    await page.locator('#ti_school_date_title').fill(`17.00 Uhr Probe ${tag}`);
    await pop.getByRole('button', { name: 'Speichern' }).click();
    await expect(page.locator('#calendar .fc-daygrid-event', { hasText: `17.00 Uhr Probe ${tag}` })).toHaveCount(1);
    const stored = (await (await page.request.post('/api/get_website_events', { data: {} })).json()).events.find((e: { id: string }) => e.id === id);
    expect(stored.title).toBe(`17.00 Uhr Probe ${tag}`);
    expect(stored.date).toBe(date);

    // others see the details, not the form
    expect((await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'on' } })).status()).toBe(200);
    const teacher = await newUserPage();
    await login(teacher, ACCOUNTS.teacher);
    expect((await teacher.request.post('/api/save_website_event', { data: { id, title: 'nein', date } })).ok()).toBe(false);
    await teacher.setViewportSize({ width: 1440, height: 1000 });
    const theirs = teacher.locator('#calendar .fc-daygrid-event', { hasText: `Probe ${tag}` });
    // the timetable is written again after the change
    await expect(async () => {
      await teacher.goto('/');
      await expect(theirs).toHaveCount(1, { timeout: 3_000 });
    }).toPass({ timeout: 60_000 });
    await theirs.click();
    await expect(teacher.locator('.pv-school-pop')).toHaveCount(0);
    await expect(teacher.locator('.modal.show')).toContainText(`Probe ${tag}`);

    // deleting asks first
    await page.locator('#calendar .fc-daygrid-event', { hasText: `Probe ${tag}` }).click();
    await pop.getByRole('button', { name: 'Löschen' }).click();
    const confirm = page.locator('.modal.show');
    await expect(confirm).toContainText('löschen?');
    await confirm.getByRole('button', { name: 'Löschen' }).click();
    await expect(page.locator('#calendar .fc-daygrid-event', { hasText: `Probe ${tag}` })).toHaveCount(0);
    const left = (await (await page.request.post('/api/get_website_events', { data: {} })).json()).events.filter((e: { id: string }) => e.id === id);
    expect(left).toHaveLength(0);
    id = '';
  } finally {
    if (id) await page.request.post('/api/delete_website_event', { data: { id } });
    await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'off' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones, »Mehr«: the tiles fill their rows – no tile alone in a row unless
// it takes the whole width (also around the Hell / Auto / Dunkel row) – and
// the menu's groups follow the plan; nothing out of season shows.
test('Neues Design: Mehr am Handy, Kacheln gut verteilt, Menü nach Themen', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'Kacheln am Handy');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await page.locator('#bu_pv_more').click();
    const menu = page.locator('#navbarTogglerDemo02');
    await expect(menu).toHaveClass(/\bshow\b/);
    await page.waitForTimeout(400);
    const lonely = await menu.evaluate((m) => {
      const tiles = Array.from(m.querySelectorAll<HTMLElement>('.nav-item, .dropdown-item, .pv-nav-entry')).filter((el) => {
        const r = el.getBoundingClientRect();
        return el.offsetParent && r.width > 40 && r.height > 60 && !el.closest('.pv-mode-row') && !el.classList.contains('pv-mode-row');
      });
      const rows = new Map<string, HTMLElement[]>();
      for (const t of tiles) {
        const key = `${t.parentElement === null ? '' : t.parentElement.className}|${Math.round(t.getBoundingClientRect().top)}`;
        rows.set(key, [...(rows.get(key) || []), t]);
      }
      const out: string[] = [];
      rows.forEach((list) => {
        if (list.length !== 1) return;
        const t = list[0];
        const parent = t.parentElement!.getBoundingClientRect();
        if (t.getBoundingClientRect().width < parent.width * 0.8) out.push((t.textContent || '').trim());
      });
      return out;
    });
    expect(lonely).toEqual([]);
    // nothing out of season visible
    await expect(menu.locator('[data-pv-off]:visible')).toHaveCount(0);
    // Verwaltung: groups by topic, the new labels
    const verwaltung = menu.locator('.pv-nav-section[data-section="verwaltung"]');
    await expect(verwaltung.locator('.pv-nav-entry', { hasText: 'Schulkalender' })).toHaveCount(1);
    await expect(verwaltung.locator('.pv-nav-entry', { hasText: 'Datenpflege' })).toHaveCount(1);
    await expect(verwaltung.locator('.pv-nav-entry', { hasText: 'Termine verwalten' })).toHaveCount(0);
    // every page in one place only (one highlight): the library in Schule
    const hrefs = await menu.locator('.pv-nav-section .pv-nav-entry').evaluateAll((list) => list.map((a) => a.getAttribute('href')));
    expect(hrefs.filter((h, i) => hrefs.indexOf(h) !== i)).toEqual([]);
    await expect(menu.locator('.pv-nav-section[data-section="schule"] .pv-nav-entry[href="/bibliothek"]')).toHaveCount(1);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Desktop: the window made wider or narrower – the column beside the week
// appears or goes as at the start, and the timetable takes the room (it kept
// the layout it was loaded with: no column after going wide, an empty strip
// after going narrow).
test('Neues Design: Stundenplan folgt der Fensterbreite (Spalte daneben)', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Raster nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    const layout = () => page.evaluate(() => {
      const cal = document.querySelector('#calendar .fc-view-harness')!.getBoundingClientRect();
      const side = document.getElementById('pv_side')!;
      const s = side.getBoundingClientRect();
      return { side: !side.hidden && s.width > 0, calRight: Math.round(cal.right), sideLeft: Math.round(s.left), width: window.innerWidth };
    });
    await page.setViewportSize({ width: 1100, height: 900 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    const narrow = await layout();
    expect(narrow.side).toBe(false);
    // wider: the column appears, the timetable ends before it
    await page.setViewportSize({ width: 1440, height: 900 });
    await expect.poll(async () => (await layout()).side).toBe(true);
    const wide = await layout();
    expect(wide.calRight).toBeLessThanOrEqual(wide.sideLeft);
    // narrower again: the column goes, no empty strip beside the timetable
    await page.setViewportSize({ width: 1100, height: 900 });
    await expect.poll(async () => (await layout()).side).toBe(false);
    await expect.poll(async () => (await layout()).calRight).toBeGreaterThan(narrow.calRight - 3);
    expect((await layout()).calRight).toBeGreaterThan(1100 - 80);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The column beside the week: a change of an entry without a class (a team
// meeting) shows its name without empty parentheses.
test('Neues Design: Änderungen der Woche ohne leere Klammern', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Spalte nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    await page.evaluate(() => {
      const w = window as any;
      const d = new Date(w.calendar.view.activeStart); d.setDate(d.getDate() + 1); d.setHours(12, 20, 0, 0);
      w.calendar.addEvent({ start: d, end: new Date(d.getTime() + 45 * 60000),
        extendedProps: { lesson: true, entfall: true, label: '<b>Team6</b> ()', label_short: '<b>Team6</b> ()' } });
      w.render_preview_side();
    });
    const change = page.locator('#pv_side .pv-side-change', { hasText: 'Team6' });
    await expect(change.locator('b')).toHaveText('Team6');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The column beside the week: two lessons of one's own exchanged on one day
// (Ma and AGr in 9c) are one change, »Tausch«, with the new time – not a
// cancelled lesson.
test('Neues Design: Änderungen der Woche, Tausch statt Entfall', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'Spalte nur am Desktop');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto('/');
    await expect(page.locator('.fc-timegrid-event').first()).toBeVisible();
    await page.evaluate(() => {
      const w = window as any;
      const at = (h: number, m: number) => { const d = new Date(w.calendar.view.activeStart); d.setDate(d.getDate() + 2); d.setHours(h, m, 0, 0); return d; };
      w.calendar.addEvent({ start: at(10, 40), end: at(11, 25), extendedProps: { lesson: true, entfall: true, klassen: [[], ['9c']],
        label: '<s>Mathematik</s> <b>Altgriechisch</b> (9c) <s>Sp</s> Ksw', label_short: '<s>Ma</s> <b>AGr</b> (9c) <s>Sp</s> Ksw' } });
      w.calendar.addEvent({ start: at(13, 40), end: at(14, 25), extendedProps: { lesson: true, klassen: [[], ['9c']],
        label: '<s>Altgriechisch</s> <b>Mathematik</b> (9c) <s>Ksw</s> Sp', label_short: '<s>AGr</s> <b>Ma</b> (9c) <s>Ksw</s> Sp' } });
      w.render_preview_side();
    });
    const swap = page.locator('#pv_side .pv-side-swap');
    await expect(swap).toHaveCount(1);
    await expect(swap.locator('.pv-side-tag')).toHaveText('Tausch');
    await expect(swap.locator('b')).toContainText('Ma (9c)');
    await expect(swap.locator('small')).toContainText('13:40 statt 10:40');
    await expect(page.locator('#pv_side .pv-side-change', { hasText: 'AGr (9c)' })).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// The week keeps the scrollbar's room (scrollbar-gutter): a dialog must not
// make up for the scrollbar as well – Bootstrap added its width as padding
// to the page and the sidebar, and the week jumped to the left when a
// lesson was opened. (Headless browsers hide scrollbars: one with them.)
test('Neues Design, Woche: ein Dialog verschiebt die Seite nicht', async ({ baseURL }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the week on the desktop');
  const browser = await chromium.launch({ ignoreDefaultArgs: ['--hide-scrollbars'] });
  const page = await browser.newPage({ baseURL, viewport: { width: 1600, height: 900 } });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('.fc-view-harness')).toBeVisible();
    for (let i = 0; i < 6; i++) {
      if (await page.locator('.fc-timegrid-event').count() > 0) break;
      await page.evaluate(() => (window as any).calendar.next());
      await page.waitForTimeout(400);
    }
    const where = async () => page.evaluate(() => ({
      harness: document.querySelector('.fc-view-harness')!.getBoundingClientRect().right,
      body: getComputedStyle(document.body).paddingRight,
      navbar: getComputedStyle(document.querySelector('.navbar')!).paddingRight,
    }));
    const before = await where();
    await page.locator('.fc-timegrid-event').first().click();
    await expect(page.locator('#lessonModal')).toBeVisible();
    await page.waitForTimeout(400);
    const after = await where();
    expect(after).toEqual(before);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    await browser.close();
  }
});

// A button of the week's head keeps the focus after a click: Bootstrap's
// ring then drew a dark frame inside the arrows' group. Clicked: no ring;
// from the keyboard: a ring of the design.
test('Neues Design, Woche: kein dunkler Rahmen um geklickte Knöpfe', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'the head of the week');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    const weiter = page.getByRole('button', { name: 'Weiter' });
    await expect(weiter).toBeVisible();
    await weiter.click();
    // (the head is drawn anew for the next week: the new button, focused by
    // a click as it was)
    await page.getByRole('button', { name: 'Weiter' }).click();
    const geklickt = await page.getByRole('button', { name: 'Weiter' }).evaluate((b) => {
      (b as HTMLElement).focus();
      return getComputedStyle(b).outlineStyle;
    });
    expect(geklickt).toBe('none');
    // from the keyboard: a visible ring
    await page.keyboard.press('Shift+Tab');
    await page.keyboard.press('Tab');
    const tastatur = await page.evaluate(() => {
      const b = document.activeElement as HTMLElement;
      return { label: b.getAttribute('aria-label'), outline: getComputedStyle(b).outlineStyle };
    });
    if (tastatur.label === 'Weiter') expect(tastatur.outline).toBe('solid');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

