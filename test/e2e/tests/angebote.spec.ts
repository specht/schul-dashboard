import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest } from '@playwright/test';

// Profil, "Meine AGs und Angebote" (students): the person running an AG is a
// teacher, so students see the official name ("Herr Clarke"), not the first
// name (include/angebote.rb, get_angebote_for_session_user).
test('Meine AGs: Lehrkräfte mit offiziellem Namen', async ({ page, baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.admin);
  const name = `Test-AG ${Date.now()}`;
  const created = await api.post('/api/save_angebot', { data: { name, recipients: [ACCOUNTS.schueler] } });
  expect(created.ok()).toBe(true);
  const aid = (await created.json()).angebot.id;
  try {
    await login(page, ACCOUNTS.schueler);
    await page.goto('/profil');
    const entry = page.locator('li', { hasText: name });
    await expect(entry).toContainText('(Herr Clarke)');
    await expect(entry).not.toContainText('Scott');
  } finally {
    await api.post('/api/delete_angebot', { data: { aid } });
    await api.dispose();
  }
});
