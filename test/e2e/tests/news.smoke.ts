import { test, expect, request as playwrightRequest } from '@playwright/test';
import { ROLE_ACCOUNTS, apiLogin } from './fixtures';

// News texts: image{…} and file{…} become HTML, everything else is text –
// the news text is never evaluated as Ruby.
test('News-Vorschau wertet keinen Ruby-Code aus', async ({ baseURL }) => {
  const request = await playwrightRequest.newContext({ baseURL });
  await apiLogin(request, ROLE_ACCOUNTS.technikteam); // can manage news
  const r = await request.post('/api/get_news_preview', {
    data: { markdown: 'Ergebnis: #{6*7}\n\nimage{beispielbild, "Eine Bildunterschrift"}' },
  });
  expect(r.status()).toBe(200);
  const html = (await r.json()).html as string;
  expect(html).toContain('#{6*7}');
  expect(html).not.toContain('Ergebnis: 42');
  // the image include still works
  expect(html).toContain('<div class="image">');
  expect(html).toContain('Eine Bildunterschrift');
  await request.dispose();
});
