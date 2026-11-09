import { test, expect } from '@playwright/test';
import fs from 'fs';
import path from 'path';
import { ACCOUNTS, ROLE_ACCOUNTS, login, watchPage } from './fixtures';

// UI tour: full-page screenshots of the main pages per role, on desktop and
// phone, for UI/UX reviews. Not a test in the strict sense – it only fails
// if a page cannot be opened. Example data only (test stack).
//
//   ./test.sh up
//   E2E_ARGS="--project=screens" ./test.sh e2e-run
//   → test/e2e/test-results/ui-tour/<role>/<viewport>-<page>.png

const OUT = path.join(__dirname, '..', 'test-results', 'ui-tour');

const TOUR: Record<string, { email: string | null; pages: string[] }> = {
  anonym: { email: null, pages: ['/', '/hilfe', '/impressum'] },
  schueler: {
    email: ACCOUNTS.schueler,
    pages: ['/', '/messages', '/profil', '/hilfe', '/bibliothek', '/sitzplananzeige/5a/108'],
  },
  lehrkraft: {
    email: ACCOUNTS.admin,
    pages: ['/', '/lessons/Ma_5a', '/messages', '/polls', '/events', '/directory/5a', '/groups',
      '/profil', '/admin', '/sitzplanhelfer/5a/108', '/tests'],
  },
};

// The further role accounts get their pages from their own navigation
// menu: '/' plus every menu link (so the tour follows menu changes).
for (const [role, email] of Object.entries(ROLE_ACCOUNTS)) {
  TOUR[role] = { email, pages: [] };
}
const MAX_MENU_PAGES = 15;

const VIEWPORTS = {
  desktop: { width: 1280, height: 800, isMobile: false },
  phone: { width: 390, height: 844, isMobile: true },
};

for (const [role, { email, pages }] of Object.entries(TOUR)) {
  for (const [viewportName, viewport] of Object.entries(VIEWPORTS)) {
    test(`UI-Tour ${role} ${viewportName}`, async ({ browser }) => {
      test.setTimeout(5 * 60_000);
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
        isMobile: viewport.isMobile, hasTouch: viewport.isMobile,
        deviceScaleFactor: 1, locale: 'de-DE', timezoneId: 'Europe/Berlin',
      });
      const page = await context.newPage();
      const watched = watchPage(page);
      if (email) await login(page, email);
      const dir = path.join(OUT, role);
      fs.mkdirSync(dir, { recursive: true });
      const notes: string[] = [];
      let urls = pages;
      if (urls.length === 0) {
        await page.goto('/');
        const links = await page.locator('nav a[href^="/"]').evaluateAll((as) =>
          // pages only – never follow API links (downloads, actions)
          [...new Set(as.map((a) => a.getAttribute('href')!)
            .filter((h) => h !== '/' && !h.startsWith('/#') && !h.startsWith('/api/')))]);
        urls = ['/', ...links.slice(0, MAX_MENU_PAGES)];
      }
      for (const url of urls) {
        const response = await page.goto(url);
        await page.waitForTimeout(1500);
        const name = url === '/' ? 'start' : url.replace(/^\//, '').replace(/[^a-z0-9]+/gi, '_');
        await page.screenshot({ path: path.join(dir, `${viewportName}-${name}.png`), fullPage: true });
        notes.push(`${url}: HTTP ${response?.status()} → ${new URL(page.url()).pathname}`);
      }
      fs.writeFileSync(path.join(dir, `${viewportName}-notes.txt`),
        [...notes, '', 'Serverfehler:', ...watched.serverErrors, '', 'JS-Fehler:', ...watched.pageErrors,
          '', 'Konsolenfehler:', ...watched.consoleErrors].join('\n'));
      await context.close();
      expect(notes.length).toBe(urls.length);
    });
  }
}
