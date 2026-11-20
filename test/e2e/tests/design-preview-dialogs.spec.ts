import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Locator, Page } from '@playwright/test';

// Neues Design: one layout for every dialog (doc/Gestaltung.md, 8, »Aufbau
// eines Dialogs«; preview.css »One layout for every dialog«, preview.js).
// The footer in a fixed order – what removes at the start, the way out, the
// main action last –, »Verwerfen« only with unsaved changes and »Schließen«
// only without, the way out quiet grey; a question stays a narrow card in
// the middle, every other dialog is a sheet on phones.

const phone = (page: Page) => (page.viewportSize()?.width ?? 0) < 768;

// the visible footer buttons, left to right (on phones: in reading order)
async function footer(modal: Locator) {
  return modal.locator('.modal-footer .btn').evaluateAll((els) => els
    .filter((el) => {
      const r = el.getBoundingClientRect();
      return r.width > 2 && r.height > 2 && getComputedStyle(el).visibility !== 'hidden';
    })
    .map((el) => ({ x: el.getBoundingClientRect().left, text: (el.textContent || '').trim() }))
    .sort((a, b) => a.x - b.x)
    .map((b) => b.text));
}

test('Neues Design: Dialoge, Bestätigung schmal, Aktion zuletzt, Abbrechen ruhig', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await page.evaluate(() => (window as any).dashboardConfirm('Willst du den Eintrag löschen?', () => {}, { title: 'Eintrag löschen?', confirm: 'Löschen', danger: true }));
    const modal = page.locator('#__template_modal');
    await expect(modal).toBeVisible();
    await page.waitForTimeout(400);
    expect(await footer(modal)).toEqual(['Abbrechen', 'Löschen']);
    // the way out quiet grey (the page's hover tone), not a dark button
    const look = await modal.evaluate((m) => {
      const cancel = Array.from(m.querySelectorAll('.modal-footer .btn')).find((b) => b.textContent!.trim() === 'Abbrechen')!;
      const probe = document.createElement('div');
      probe.style.background = 'var(--pv-hover)';
      document.body.appendChild(probe);
      const hover = getComputedStyle(probe).backgroundColor;
      probe.remove();
      return { cancel: getComputedStyle(cancel).backgroundColor, hover, width: m.querySelector('.modal-dialog')!.getBoundingClientRect().width };
    });
    expect(look.cancel).toBe(look.hover);
    // a question: narrow on the desktop, a card in the middle on phones
    if (!phone(page)) expect(look.width).toBeLessThanOrEqual(480);
    await expect(modal).not.toHaveClass(/pv-sheet/);
    await modal.getByRole('button', { name: 'Abbrechen' }).click();
    await expect(modal).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Dialoge, Editor mit Verwerfen am Anfang und Speichern am Ende', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/events');
    await page.locator('.bu-new-event').first().click();
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    await page.waitForTimeout(400);
    // phones: a sheet like every dialog
    if (phone(page)) await expect(modal).toHaveClass(/pv-sheet/);
    // nothing typed yet: no »Verwerfen«; »Speichern« last (»Schließen« only on
    // the desktop – phones close by pulling the sheet down)
    let buttons = await footer(modal);
    expect(buttons).not.toContain('Verwerfen');
    expect(buttons[buttons.length - 1]).toBe('Speichern');
    if (!phone(page)) expect(buttons).toEqual(['Schließen', 'Speichern']);
    // something typed: »Verwerfen« at the start, no »Schließen«, »Speichern»
    // the one accent at the end
    await page.locator('#ti_title').pressSequentially('Dialogtest');
    await expect(modal.locator('#bu_discard_event')).toBeEnabled();
    buttons = await footer(modal);
    expect(buttons).toEqual(['Verwerfen', 'Speichern']);
    const accent = await modal.evaluate((m) => {
      const probe = document.createElement('div');
      probe.style.background = 'var(--acc)';
      document.body.appendChild(probe);
      const acc = getComputedStyle(probe).backgroundColor;
      probe.remove();
      return { save: getComputedStyle(m.querySelector('#bu_save_event')!).backgroundColor, acc };
    });
    // (without participants the page keeps »Speichern« off, quiet)
    if (await modal.locator('#bu_save_event').isEnabled()) expect(accent.save).toBe(accent.acc);
    // »Verwerfen« closes without saving
    await modal.locator('#bu_discard_event').click();
    await expect(modal).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
