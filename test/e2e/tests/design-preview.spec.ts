import { test, expect, login, ACCOUNTS } from './fixtures';

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
  await dialog.getByRole('button', { name: 'Schließen' }).click();
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
      await page.keyboard.press('Escape');
      await expect(profileMenu).toBeHidden();
      // the old admin menu is gone: its tools sit in the "Verwaltung" section,
      // folded (unless the current page is one of them), and it remembers
      await expect(page.locator('#navbarDropdownAdmin')).toBeHidden();
      const verwaltung = nav.locator('.pv-nav-section[data-section="verwaltung"]');
      await expect(verwaltung.locator('.pv-nav-body')).toBeHidden();
      await verwaltung.locator('button.pv-nav-heading').click();
      await expect(verwaltung.locator('a.pv-nav-entry[href="/admin"]')).toBeVisible();
      await page.reload();
      await expect(verwaltung.locator('a.pv-nav-entry[href="/admin"]')).toBeVisible();
      await verwaltung.locator('button.pv-nav-heading').click();
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
      // teachers: Heute · Woche · Nachrichten · Kurse · Mehr (as in the mockups)
      await expect(tabs.locator('.pv-tab')).toHaveText(['Heute', 'Woche', 'Nachrichten', 'Kurse', 'Mehr']);
      // the search: at the top of "Mehr" (no icon in the top bar)
      await expect(page.locator('.nav-quick-search-nav .nav-quick-search')).toBeHidden();
      await tabs.locator('#bu_pv_more').click();
      await page.locator('.pv-more-search').click();
      await expect(page.locator('#ti_quick_search')).toBeVisible();
      await page.locator('#ti_quick_search').press('Escape');
      // "Kurse": Kursbuch and class lists as a sheet
      await tabs.locator('#bu_pv_courses').click();
      const courses = page.locator('.pv-link-sheet');
      await expect(courses).toContainText('Kursbuch');
      await expect(courses.locator('a[href^="/lessons/"]').first()).toBeVisible();
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

// Tablets: the sidebar as an icon rail. The sections (Unterricht, Schule,
// Verwaltung) are one icon each and open as a panel beside the rail, without
// changing the folds the full sidebar remembers.
test('Neues Design: Abschnitte in der Symbolleiste am Tablet', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'tablet width');
  await page.setViewportSize({ width: 820, height: 1180 });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/messages');
    const nav = page.locator('nav.navbar');
    const rail = (await nav.boundingBox())!;
    expect(rail.width).toBeLessThan(100);
    // no text sticks out of the rail or is cut off in it
    expect(await nav.evaluate((navEl) => {
      const right = navEl.getBoundingClientRect().right;
      return [...navEl.querySelectorAll('*')].filter((el) => {
        const r = el.getBoundingClientRect();
        const text = [...el.childNodes].some((c) => c.nodeType === 3 && c.textContent!.trim());
        return text && r.width > 0 && r.height > 0 && (r.right > right + 1 || el.scrollWidth > el.clientWidth + 1);
      }).length;
    })).toBe(0);
    const verwaltung = nav.locator('.pv-nav-section[data-section="verwaltung"]');
    const heading = verwaltung.locator('button.pv-nav-heading');
    const body = verwaltung.locator('.pv-nav-body');
    await expect(body).toBeHidden();
    await heading.click();
    await expect(body).toBeVisible();
    const panel = (await body.boundingBox())!;
    expect(panel.x).toBeGreaterThanOrEqual(rail.width - 1);
    expect(panel.y + panel.height).toBeLessThanOrEqual(1180);
    await expect(body.locator('a.pv-nav-entry[href="/admin"]')).toBeVisible();
    // one panel at a time; Escape and a click elsewhere close it
    await nav.locator('.pv-nav-section[data-section="unterricht"] button.pv-nav-heading').click();
    await expect(body).toBeHidden();
    // Lerngruppen opens beside the panel, not over it
    const unterricht = nav.locator('.pv-nav-section[data-section="unterricht"] .pv-nav-body');
    await page.locator('#navbarDropdownKlassen').click();
    const groups = nav.locator('[aria-labelledby="navbarDropdownKlassen"]');
    await expect(groups).toBeVisible();
    const u = (await unterricht.boundingBox())!;
    expect((await groups.boundingBox())!.x).toBeGreaterThanOrEqual(u.x + u.width - 1);
    await page.keyboard.press('Escape');
    await page.keyboard.press('Escape');
    await expect(unterricht).toBeHidden();
    await heading.click();
    await expect(body).toBeVisible();
    await page.mouse.click(600, 900);
    await expect(body).toBeHidden();
    // the full sidebar keeps its own folds
    await page.setViewportSize({ width: 1280, height: 900 });
    await expect(body).toBeHidden();
    await expect(nav.locator('.pv-nav-section[data-section="unterricht"] .pv-nav-body')).toBeVisible();
    await expect(heading).toContainText('Verwaltung');
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
      // the hallway monitor in its own new design (monitor-neu.spec.ts):
      // with ?design=neu, or for someone with the new design switched on
      // (the previews in manage_monitor) – not with ?design=alt, never on the
      // Lehrerzimmer and Sekretariat monitors
      const neu = path === '/monitor' || path.includes('design=neu');
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
    await page.locator('.toggle:has(#dark_css_switch)').click();
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
    await page.locator('.nav-dark').click();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
    await expect.poll(tokens).not.toBe(before);
    await expect(page.locator('link[href="/dark.css"]')).toHaveCount(1);
    await open();
    await expect(page.locator('.nav-light .label')).toHaveText('Hell');
    await expect(page.locator('.nav-dark')).toHaveCount(0);
    await page.locator('.nav-light').click();
    await expect(page.locator('body')).not.toHaveClass(/\bdark\b/);
    await expect.poll(tokens).toBe(before);
    await expect(page.locator('link[href="/dark.css"]')).toHaveCount(0);
    expect(loads).toBe(0);
    // stored: a reload keeps it
    await open();
    await page.locator('.nav-dark').click();
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
    const sw = page.locator('#dark_css_switch');
    await expect(sw).not.toBeChecked();
    if (phone) await page.locator('#bu_pv_more').click();
    else await page.locator('#navbarDropdownProfile').click();
    await page.locator('.nav-dark').click();
    await expect(page.locator('body')).toHaveClass(/\bdark\b/);
    await expect(sw).toBeChecked();
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
      return { plan: left('.pv-band-plan'), pill: left('.pv-band-text'), tiles: left('.pv-strip-day'), planText: text('.pv-band-plan span'), title: text('.pv-band-text h1') };
    });
    expect(Math.abs(x.pill - x.plan)).toBeLessThanOrEqual(1);
    expect(Math.abs(x.pill - x.tiles)).toBeLessThanOrEqual(1);
    expect(Math.abs(x.title - x.planText)).toBeLessThanOrEqual(1);
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
