import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// Neues Design: the Jitsi room page (/jitsi/…, jitsi.html, preview/jitsi.css;
// the middle part from gen_jitsi_data in include/jitsi.rb). One surface: the
// notes and the tips in line with the text, the consent as plain text, the
// tips as a list with bullets, no dividers. The texts keep »Sie« on purpose
// (parents and external guests are invited too). The old design stays as it
// was.

async function layout(page: Page) {
  return page.evaluate(() => {
    const col = document.querySelector('#main_container .col-md-12') as HTMLElement;
    const left = (sel: string) => {
      const e = col.querySelector(sel) as HTMLElement | null;
      return e ? Math.round(e.getBoundingClientRect().left) : null;
    };
    const consent = col.querySelector('.alert-secondary') as HTMLElement;
    return {
      text: left(':scope > p'),
      warning: left('.alert-warning'),
      consent: left('.alert-secondary'),
      tips: left('.alert-success'),
      bullets: getComputedStyle(col.querySelector('.alert-success li') as HTMLElement).listStyleType,
      consentBorder: getComputedStyle(consent).borderTopWidth,
      consentBackground: getComputedStyle(consent).backgroundColor,
      dividers: Array.from(col.querySelectorAll('hr')).filter((h) => (h as HTMLElement).offsetHeight > 0).length,
      overflow: document.documentElement.scrollWidth > window.innerWidth,
    };
  });
}

test('Neues Design: Jitsi-Raum als eine Fläche, Hinweise bündig, Tipps als Liste', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/jitsi/Lehrerzimmer');
    await expect(page.locator('.container.pv-jitsi')).toHaveCount(1);
    await expect(page.locator('.go_div .btn').first()).toBeVisible();
    const l = await layout(page);
    // every box in line with the text, none to the panel's edge
    expect(l.warning).toBe(l.text);
    expect(l.consent).toBe(l.text);
    expect(l.tips).toBe(l.text);
    expect(l.bullets).toBe('disc');
    expect(l.consentBorder).toBe('0px');
    expect(l.consentBackground).toBe('rgba(0, 0, 0, 0)');
    expect(l.dividers).toBe(0);
    expect(l.overflow).toBe(false);
    // »Sie« stays (guests and parents are invited too)
    await expect(page.locator('.pv-jitsi .alert-warning')).toContainText('Wenn Sie das Lehrerzimmer betreten');
    await expect(page.locator('.pv-jitsi .alert-success')).toContainText('Stellen Sie bitte Ihr Mikrofon stumm');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Jitsi-Raum ohne Vorschau: wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/jitsi/Lehrerzimmer');
  await expect(page.locator('.go_div .btn').first()).toBeVisible();
  await expect(page.locator('.pv-jitsi')).toHaveCount(0);
  expect((await layout(page)).dividers).toBe(2);
});
