import { test, expect } from '@playwright/test';

// Every page links /site.webmanifest (_template.html). Browsers ignore a
// manifest that comes with an error status – before, it was sent with 404.
test('Web-App-Manifest wird ausgeliefert', async ({ request }) => {
  const res = await request.get('/site.webmanifest');
  expect(res.status()).toBe(200);
  expect(res.headers()['content-type']).toContain('application/manifest+json');
  const manifest = await res.json();
  expect(manifest.name).toMatch(/^Dashboard /);
  expect(manifest.start_url).toBe('/');
  expect(manifest.icons.length).toBeGreaterThan(0);
});
