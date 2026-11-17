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
  await expect(dialog.locator('#ti_design_feedback')).toHaveAttribute('placeholder', /Ihnen/);
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
      // menus open as a panel next to the sidebar, at full length (in columns
      // if needed), above the footer; the sidebar itself never scrolls
      await page.locator('#navbarDropdownProfile').click();
      await expect(nav.locator('[aria-labelledby="navbarDropdownProfile"]')).toBeVisible();
      const foot = (await page.locator('.foot').boundingBox())!;
      for (const height of [viewport.height, 420]) {
        await page.setViewportSize({ width: viewport.width, height });
        await page.locator('#navbarDropdownAdmin').click();
        const adminMenu = nav.locator('[aria-labelledby="navbarDropdownAdmin"]');
        await expect(adminMenu).toBeVisible();
        await page.waitForTimeout(100);
        const panel = (await adminMenu.boundingBox())!;
        expect(panel.x).toBeGreaterThanOrEqual(box.width - 1);
        expect(panel.y).toBeGreaterThanOrEqual(0);
        expect(panel.y + panel.height).toBeLessThanOrEqual(height - foot.height + 1);
        expect(await adminMenu.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
        if (height === 420) break;
        expect(await nav.evaluate((el) => el.scrollHeight <= el.clientHeight + 1)).toBe(true);
        await page.keyboard.press('Escape');
        await expect(adminMenu).toBeHidden();
      }
      const adminMenu = nav.locator('[aria-labelledby="navbarDropdownAdmin"]');
      // long names wrap instead of being cut off
      expect(await adminMenu.locator('.dropdown-item').evaluateAll((els) => els.every((el) => el.scrollWidth <= el.clientWidth + 1))).toBe(true);
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
      // "Suchen" opens the search
      await tabs.locator('#bu_pv_search').click();
      await expect(page.locator('#ti_quick_search')).toBeVisible();
      await expect(page.locator('#ti_quick_search')).toBeFocused();
      await page.locator('#ti_quick_search').press('Escape');
      // the tabs lead where they say
      await tabs.getByText('Profil').click();
      await expect(page).toHaveURL(/\/profil$/);
      await expect(page.locator('.pv-tabbar .pv-tab.pv-active')).toContainText('Profil');
    }
  } finally {
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
    await expect(page.locator('#font_preview_note')).toBeVisible();
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
    await expect(page.locator('#pv_agenda .pv-ag-notice').first()).toContainText('Morgen 16:00');
    await expect(page.locator('#pv_agenda .pv-ag-notice').first()).toContainText('entfällt');
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
    for (const path of ['/monitor', '/monitor/lz']) {
      const html = await (await page.request.get(path)).text();
      expect(html, path).not.toContain('ui-preview');
      expect(html, path).not.toContain('pv-tabbar');
      expect(html, path).not.toContain('/preview.css');
    }
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Phones: other plans (Kürzel, classes, rooms) through a "Plan" button in the
// header – a sheet with search, the shown plan in the accent; no chip panel
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
