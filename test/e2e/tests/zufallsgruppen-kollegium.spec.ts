import type { Page } from '@playwright/test';
import { test, expect, login, openProfileMenu, ACCOUNTS } from './fixtures';

// Gruppenbildung for the staff (/zufallsgruppen/kollegium): admins may always
// use it, other teachers only once an admin has added them to the list on
// that page. The list carries over between runs, so every test starts by
// emptying it.

const PAGE = '/zufallsgruppen/kollegium';
const MENU_LABEL = 'Gruppenbildung Kollegium';

async function openAccessList(page: Page) {
  await page.goto(PAGE);
  const access = page.locator('#zg_access');
  await expect(access).toBeVisible();
  if (!(await access.evaluate((el) => (el as HTMLDetailsElement).open))) {
    await access.locator('summary').click();
  }
  return access;
}

async function clearAccessList(page: Page) {
  const access = await openAccessList(page);
  const remove = access.locator('#zg_access_list .zg-person button');
  while (await remove.count() > 0) {
    const before = await remove.count();
    await remove.first().click();
    await expect(remove).toHaveCount(before - 1);
  }
  await expect(page.locator('#zg_access_count')).toHaveText('(nur Admins)');
}

async function expectMenuEntry(page: Page, visible: boolean) {
  await page.goto('/');
  await openProfileMenu(page);
  const entry = page.locator('[aria-labelledby="navbarDropdownProfile"] a', { hasText: MENU_LABEL });
  await expect(entry).toHaveCount(visible ? 1 : 0);
}

test('Gruppenbildung Kollegium: Admin mischt das Kollegium und gibt eine Lehrkraft frei', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  await clearAccessList(page);

  // admin: menu entry next to the polls, groups from the whole staff
  await expectMenuEntry(page, true);
  await page.locator('[aria-labelledby="navbarDropdownProfile"] a', { hasText: MENU_LABEL }).click();
  await expect(page).toHaveURL(new RegExp(`${PAGE}$`));
  await expect(page.locator('h1')).toHaveText('Gruppenbildung Kollegium');
  // no rules besides size and remainder for the staff
  await expect(page.locator('#zg_gender_row')).toHaveCount(0);
  await expect(page.locator('#zg_distribution_row')).toBeHidden();
  await expect(page.locator('#zg_presence .zg-chip', { hasText: 'Torstenson' }).first()).toBeVisible();
  await page.locator('#zg_bu_mix').click();
  await expect(page.locator('#zg_groups')).toContainText('Gruppe 1');
  await expect(page.locator('#zg_groups')).toContainText('Clarke');

  // a teacher who is not on the list gets neither the entry nor the page
  const teacher = await newUserPage();
  await login(teacher, ACCOUNTS.teacher);
  await expectMenuEntry(teacher, false);
  await teacher.goto(PAGE);
  await expect(teacher).not.toHaveURL(new RegExp(PAGE));

  // the admin adds the teacher from the staff list
  const access = await openAccessList(page);
  await page.locator('#zg_access_add').selectOption(ACCOUNTS.teacher);
  await expect(access.locator('#zg_access_list .zg-person')).toHaveCount(1);
  await expect(access.locator('#zg_access_list')).toContainText('Torstenson');

  // now the teacher can mix, but does not see or change the list
  await expectMenuEntry(teacher, true);
  await teacher.goto(PAGE);
  await expect(teacher.locator('h1')).toHaveText('Gruppenbildung Kollegium');
  await expect(teacher.locator('#zg_access')).toBeHidden();
  await teacher.locator('#zg_bu_mix').click();
  await expect(teacher.locator('#zg_groups')).toContainText('Gruppe 1');

  // removing the entry takes the access away again
  await clearAccessList(page);
  await teacher.goto(PAGE);
  await expect(teacher).not.toHaveURL(new RegExp(PAGE));
});
