import { test, expect, login, ACCOUNTS } from './fixtures';

// Design ideas (/api/werkstatt): a page that lives only on the server in
// /internal (not in the public repository), for admins only. The test stack
// has a small stand-in (src/ruby/test/create_werkstatt_example.rb).

const MARKER = 'Werkstatt (Beispiel)';

test('Werkstatt: Entwürfe nur für Admins', async ({ page, newUserPage }) => {
  // not logged in
  let response = await page.request.get('/api/werkstatt');
  expect(response.status()).not.toBe(200);
  expect(await response.text()).not.toContain(MARKER);

  // a teacher who is not an admin
  const teacher = await newUserPage();
  await login(teacher, ACCOUNTS.teacher);
  response = await teacher.request.get('/api/werkstatt');
  expect(response.status()).not.toBe(200);
  expect(await response.text()).not.toContain(MARKER);

  // an admin gets the page as it is, without the dashboard around it
  await login(page, ACCOUNTS.admin);
  response = await page.request.get('/api/werkstatt');
  expect(response.status()).toBe(200);
  expect(response.headers()['content-type']).toContain('text/html');
  await page.goto('/api/werkstatt');
  await expect(page).toHaveTitle(MARKER);
  await expect(page.locator('nav')).toHaveCount(0);
});
