import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ACCOUNTS, apiLogin } from './fixtures';

// Lab 8/9 pages of other people (linked from the overview) exist only for
// real accounts; anything else in the URL is refused.
test('Lab-8/9-Seite nur für existierende Konten', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ACCOUNTS.teacher);
  for (const lab of ['lab8', 'lab9']) {
    const ok = await request.get(`/${lab}/${ACCOUNTS.schueler}`, { maxRedirects: 0 });
    expect(ok.status(), `${lab} existing account`).toBe(200);
    const bad = await request.get(`/${lab}/x');alert(1);('`, { maxRedirects: 0 });
    expect(bad.status(), `${lab} unknown`).not.toBe(200);
    expect(await bad.text()).not.toContain("alert(1)");
  }
  await request.dispose();
});

// Students may look at other projects (read-only, linked from the overview),
// but not at their history or invitations.
test('Lab-8/9-Seite anderer: ohne Historie und Einladungen', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ACCOUNTS.schueler); // 5a, takes part in the test stack
  for (const lab of ['lab8', 'lab9']) {
    const own = await request.get(`/${lab}`, { maxRedirects: 0 });
    expect(own.status(), `${lab} own page`).toBe(200);
    const other = await request.get(`/${lab}/elli.mustermann@mail.beispielschule.de`, { maxRedirects: 0 });
    expect(other.status(), `${lab} other page`).toBe(200);
    expect(await other.text()).toContain("<div id='div_history'></div>");
  }
  await request.dispose();
});
