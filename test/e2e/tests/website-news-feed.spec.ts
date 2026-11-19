import { test, expect } from './fixtures';

// The website reads the published news from the dashboard (website.rb,
// /api/get_frontpage_news_entries/<secret>). Without parameters the latest
// 20 as before; with offset and limit (1..100) one page and the number of all
// published entries, so the website can page through them. The seed has four
// published entries from 2018/2019 (test/e2e/seed.cypher).
const SECRET = 'test-website-read-secret';
const FEED = `/api/get_frontpage_news_entries/${SECRET}`;

test('Website-News: in Seiten abrufbar, mit Gesamtzahl', async ({ request }, testInfo) => {
  test.skip(testInfo.project.name === 'mobile', 'API only');
  const all = await (await request.get(FEED)).json();
  expect(Number.isInteger(all.total)).toBe(true);
  expect(all.total).toBeGreaterThanOrEqual(4);
  expect(all.entries.length).toBe(Math.min(20, all.total));
  for (const e of all.entries) {
    expect(Object.keys(e).sort()).toEqual(['content_html', 'date', 'sticky', 'timestamp', 'title']);
  }
  // newest first, pages in that order without gaps or repeats
  const stamps = all.entries.map((e: { timestamp: number }) => e.timestamp);
  expect([...stamps].sort((a, b) => b - a)).toEqual(stamps);
  const page1 = await (await request.get(`${FEED}?offset=0&limit=2`)).json();
  const page2 = await (await request.get(`${FEED}?offset=2&limit=2`)).json();
  expect(page1.total).toBe(all.total);
  expect([...page1.entries, ...page2.entries].map((e: { timestamp: number }) => e.timestamp)).toEqual(stamps.slice(0, 4));
  // the last one alone; beyond the end: empty
  const last = await (await request.get(`${FEED}?offset=${all.total - 1}&limit=100`)).json();
  expect(last.entries.length).toBe(1);
  expect((await (await request.get(`${FEED}?offset=${all.total}&limit=100`)).json()).entries).toEqual([]);
  // limits clamped to 1..100, nonsense falls back to the defaults
  expect((await (await request.get(`${FEED}?limit=0`)).json()).entries.length).toBe(1);
  expect((await (await request.get(`${FEED}?limit=100000`)).json()).entries.length).toBe(Math.min(20, all.total));
  expect((await (await request.get(`${FEED}?offset=-3&limit=x`)).json()).entries.length).toBe(Math.min(20, all.total));
  // only with the secret
  expect((await request.get('/api/get_frontpage_news_entries/wrong')).status()).toBe(404);
});
