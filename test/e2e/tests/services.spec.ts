import { test, expect, login, ACCOUNTS } from './fixtures';

// /dienste: heartbeats of the services (service_status.rb). In the test stack
// the web service and the timetable service run.
test('Dienste-Übersicht zeigt die laufenden Dienste', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/admin');
  await page.getByRole('link', { name: 'Dienste' }).click();
  await expect(page).toHaveURL(/\/dienste$/);
  const table = page.getByTestId('service-status');
  for (const service of ['ruby', 'timetable']) {
    const row = table.locator(`tr[data-service="${service}"]`);
    await expect(row).toBeVisible();
    await expect(row).toContainText('in Ordnung');
  }
  await expect(table.locator('tr[data-service="timetable"]')).toContainText('worker');
});

test('Dienste-Übersicht nur für die Administration', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  const response = await page.request.get('/dienste', { maxRedirects: 0 });
  expect(response.status()).not.toBe(200);
});
