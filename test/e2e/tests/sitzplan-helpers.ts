import type { Page } from '@playwright/test';
import { expect } from './fixtures';

// Shared by sitzplan.spec.ts and sitzplan-fachraum.spec.ts.

// Opens the »Vorgaben« box. A new plan closes it again (sitzplanhelfer.html)
// – sometimes just after a click opened it, so check that it stays open.
export async function openVorgaben(page: Page) {
  const box = page.locator('#sph_vorgaben');
  const isOpen = () => box.evaluate((d) => (d as HTMLDetailsElement).open);
  await expect(async () => {
    if (!(await isOpen())) await box.locator('> summary').click();
    await page.waitForTimeout(300);
    expect(await isOpen()).toBe(true);
  }).toPass({ timeout: 10_000 });
}
