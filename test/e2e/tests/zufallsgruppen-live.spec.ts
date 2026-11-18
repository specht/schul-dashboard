import { test, expect, login, ACCOUNTS } from './fixtures';

// Gruppenbildung: besides "Jetzt auslosen" on the page, the groups can be
// drawn live on the projector – all names start in a pool at the bottom and
// move one by one to their place. The groups are decided beforehand (with
// all rules); the draw only shows them.

test('Gruppenbildung: live am Beamer auslosen, Name für Name aus dem Topf', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/zufallsgruppen/5a');
  await expect(page.locator('#zg_bu_mix')).toHaveText(/Jetzt auslosen/);
  await expect(page.locator('#zg_bu_live')).toBeEnabled();
  await page.locator('#zg_live_speed').selectOption('7');

  // the projector opens with every name in the pool and empty places
  await page.locator('#zg_bu_live').click();
  const beamer = page.locator('#zg_beamer');
  await expect(beamer).toBeVisible();
  await expect(beamer).toHaveClass(/zg-live/);
  const pool = page.locator('#zg_live_pool .zg-pool-chip');
  const total = await pool.count();
  expect(total).toBeGreaterThan(10);
  await expect(page.locator('#zg_beamer_groups .zg-name.zg-hidden')).toHaveCount(total);
  // no settings on the projector
  await expect(beamer.locator('input, select')).toHaveCount(0);

  // the draw empties the pool and fills every place
  await page.locator('#zg_bu_live_start').click();
  await expect(page.locator('#zg_bu_live_finish')).toBeVisible();
  await expect(pool).toHaveCount(0, { timeout: 20_000 });
  await expect(beamer).not.toHaveClass(/zg-live/);
  await expect(page.locator('#zg_beamer_groups .zg-name')).toHaveCount(total);
  await expect(page.locator('#zg_beamer_groups .zg-name.zg-hidden')).toHaveCount(0);

  // drawing again, then "Sofort fertig" puts everyone in place at once
  await page.locator('#zg_bu_beamer_mix').click();
  await expect(pool).toHaveCount(total);
  await page.locator('#zg_live_speed').evaluate((el) => { (el as HTMLSelectElement).value = '1'; });
  await page.locator('#zg_bu_live_start').click();
  await page.locator('#zg_bu_live_finish').click();
  await expect(pool).toHaveCount(0);
  await expect(page.locator('#zg_beamer_groups .zg-name.zg-hidden')).toHaveCount(0);
  await expect(page.locator('.zg-fly')).toHaveCount(0);

  // closed: the same groups are on the page and kept for the next visit
  const onBeamer = (await page.locator('#zg_beamer_groups .zg-name').allTextContents()).sort();
  await page.locator('#zg_bu_beamer_close').click();
  await expect(beamer).toBeHidden();
  expect((await page.locator('#zg_groups .zg-name').allTextContents()).sort()).toEqual(onBeamer);
  await page.reload();
  await expect(page.locator('#zg_groups .zg-name')).toHaveCount(total);
});
