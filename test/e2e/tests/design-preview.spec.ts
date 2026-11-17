import { test, expect, login, ACCOUNTS } from './fixtures';

// Neues Design (Vorschau): switched on in the profile – for now by admins only
// (UI_PREVIEW_FOR in include/design_preview.rb). Then the template loads the
// colour tokens from the colour scheme and the preview styles, and a button
// collects feedback. Switching back asks one optional question. Admins see the
// feedback on /design_feedback.

const toggle = '.toggle:has(#ui_preview_switch)';

test('Neues Design: Admin schaltet die Vorschau ein, gibt Feedback, wechselt zurück', async ({ page }, testInfo) => {
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

  // feedback, with the wish to be contacted
  await page.locator('#bu_design_feedback').click();
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

  // switching off, then thinking better of it: stays on
  await page.goto('/profil');
  await page.locator(toggle).click();
  const leave = page.locator('#uiPreviewLeaveModal');
  await expect(leave).toBeVisible();
  await leave.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(leave).toBeHidden();
  await expect(page.locator('#ui_preview_switch')).toBeChecked();
  await page.reload();
  await expect(page.locator('body')).toHaveClass(/ui-preview/);

  // switching back, with a reason
  await page.locator(toggle).click();
  await expect(leave).toBeVisible();
  await leave.locator('#ti_ui_preview_reason').fill(`${marker} – zurück`);
  await leave.getByRole('button', { name: 'Zurückwechseln' }).click();
  await page.waitForLoadState('load');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('#design_tokens')).toHaveCount(0);
  await expect(page.locator('#bu_design_feedback')).toHaveCount(0);

  // the feedback page lists both
  await page.goto('/design_feedback');
  const row = page.locator('.design-feedback-table tr', { hasText: marker }).filter({ hasNotText: 'zurück' });
  await expect(row).toContainText('Lehrkraft');
  await expect(row).toContainText('/profil');
  await expect(row).toContainText(ACCOUNTS.admin);
  await expect(page.locator('.design-feedback-table tr', { hasText: `${marker} – zurück` })).toContainText('Zurück zum alten Design');
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
    await expect(page.locator('#color_options_preview_note')).toBeVisible();
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
      // menus open in place
      await page.locator('#navbarDropdownProfile').click();
      await expect(nav.locator('[aria-labelledby="navbarDropdownProfile"]')).toBeVisible();
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
