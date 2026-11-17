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
