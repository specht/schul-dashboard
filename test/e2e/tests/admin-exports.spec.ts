import { test, expect, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest } from '@playwright/test';

// Exports on the admin page (include/admin.rb).

// "LDC: Alle SuS": one line per student for LoGoDidact,
// Nachname;Vorname;Klasse;Geschlecht;Geburtstag (TT.MM.JJJJ). Students whose
// birthday is missing in the student list (new 5th graders, until the data is
// complete) are exported too, with an empty birthday.
test('LoGoDidact-Export: alle SuS, auch ohne Geburtstag', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.admin);
  const response = await api.get('/api/all_sus_logo_didact');
  expect(response.status()).toBe(200);
  const lines = (await response.text()).split('\n').filter((line) => line.length > 0);
  expect(lines).toContain('Postfachtest;Anna;11;w;01.01.2010');
  expect(lines).toContain('Ohnegeburtstag;Gina;11;w;');
  // every line has the five fields
  for (const line of lines) expect(line.split(';'), line).toHaveLength(5);
});

test('LoGoDidact-Export nur für die Administration', async ({ baseURL }) => {
  const api = await playwrightRequest.newContext({ baseURL });
  await apiLogin(api, ACCOUNTS.teacher);
  const response = await api.get('/api/all_sus_logo_didact');
  expect(response.ok()).toBe(false);
});
