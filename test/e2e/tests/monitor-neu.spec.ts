import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// New design of the hallway monitors (include/monitor_neu.rb,
// preview/monitor/monitor.css and .js): only with ?design=neu or
// ?design=neu-dunkel in the monitor's address, or for someone whose account
// has the new design switched on (the previews in manage_monitor). Without
// that the monitors stay exactly as they are; the screens log in with the
// monitor account, which never has the new design.
//
// The test stack has no substitution plan, so the tests answer /ws_monitor
// themselves with a full school day (the same messages the server sends)
// and fix the clock at 11:05.

const FAECHER = ['D', 'Ma', 'En', 'Bio', 'Ch', 'Phy', 'Ge', 'Geo', 'Ku', 'Mu', 'Frz', 'La', 'Eth', 'Sp'];
const KUERZEL = ['Se', 'Pe', 'Kw', 'Hb', 'Ei', 'Zw', 'Cl', 'Mk', 'Rh', 'Gr', 'Ta', 'Ts'];
const RAEUME = ['108', '129', '204', '211', '317', '323', 'A102', 'B014', 'Aula', 'Halle'];

function eintrag(klasse: string, i: number) {
  const stunde = 1 + (i % 8);
  const fach = FAECHER[i % FAECHER.length];
  const art = i % 5;
  const e: Record<string, unknown> = {
    stunde, stunde_label: `${stunde}.`, klassen_alt: [klasse], klassen_neu: [klasse],
    fach_alt: fach, fach_neu: fach, lehrer_alt: [KUERZEL[i % KUERZEL.length]],
  };
  if (art === 0) { e.lehrer_neu = [KUERZEL[(i + 3) % KUERZEL.length]]; e.raum_neu = RAEUME[i % RAEUME.length]; }
  if (art === 1) { e.vertretungs_text = 'entfällt'; delete e.fach_neu; }
  if (art === 2) { e.raum_alt = RAEUME[i % RAEUME.length]; e.raum_neu = RAEUME[(i + 2) % RAEUME.length]; e.lehrer_neu = e.lehrer_alt; }
  if (art === 3) { e.vertretungs_text = 'Klausur'; e.lehrer_neu = e.lehrer_alt; e.raum_neu = RAEUME[(i + 5) % RAEUME.length]; }
  if (art === 4) { e.vertretungs_text = 'Aufgaben im Sekretariat abholen'; e.lehrer_neu = e.lehrer_alt; }
  return e;
}

// a school day as /vplan/monitor/monitor.json has it (timetable.rb)
function schultag(heute: string, anzahl: Record<string, number>, uhr = '07:12') {
  const klassen: Record<string, unknown[]> = {};
  for (const [k, n] of Object.entries(anzahl)) {
    if (n > 0) klassen[k] = Array.from({ length: n }, (_, i) => eintrag(k, i));
  }
  const stand = `${heute}T${uhr}:00`;
  return {
    today: heute, tomorrow: heute, timestamp: stand, vplan_timestamp: stand,
    data: { [heute]: { klassen, lehrer: {}, timestamp: stand, vplan_timestamp: stand } },
  };
}

// The test stack has only 5a to 5c, 11 and 12. A full school as the
// hallway monitors show it: KLASSEN_ORDER replaced in the page (test only).
const KLASSEN_TESTSTACK = ['5a', '5b', '5c', '11', '12'];
const KLASSEN_SCHULE = ['5a', '5b', '5c', '5d', '6a', '6b', '6c', '6d', '7a', '7b', '7c', '7d',
  '8a', '8b', '8c', '8d', '8o', '9a', '9b', '9c', '9d', '10a', '10b', '10c', '10d', '11', '12'];
async function ganzeSchule(page: Page) {
  await page.route(/\/monitor(\?|$)/, async (route) => {
    const r = await route.fetch();
    const html = await r.text();
    const vorher = JSON.stringify(KLASSEN_TESTSTACK);
    expect(html).toContain(vorher);
    await route.fulfill({ response: r, body: html.split(vorher).join(JSON.stringify(KLASSEN_SCHULE)) });
  });
}

async function monitorMitTag(page: Page, url: string, anzahl: Record<string, number>,
  nachrichten: string[] = ['Elternsprechtag am Mittwoch ab 16 Uhr']) {
  // 11:05 and today's date in the browser's time zone (Europe/Berlin)
  const [zeit, heute] = await page.evaluate(() => {
    const d = new Date();
    d.setHours(11, 5, 0, 0);
    const z = (n: number) => String(n).padStart(2, '0');
    return [d.getTime(), `${d.getFullYear()}-${z(d.getMonth() + 1)}-${z(d.getDate())}`];
  }) as [number, string];
  const jetzt = new Date(zeit);
  await page.clock.install({ time: jetzt });
  let verbindung: { send: (m: string) => void } | null = null;
  await page.routeWebSocket(/\/ws_monitor$/, (ws) => {
    verbindung = ws;
    ws.onMessage(() => {});
    ws.send(JSON.stringify({ command: 'update_time', time: Math.floor(jetzt.getTime() / 1000) }));
    ws.send(JSON.stringify({ command: 'update_monitor_messages', data: { messages: nachrichten, images: [] } }));
    ws.send(JSON.stringify({ command: 'update_vplan', data: schultag(heute, anzahl) }));
  });
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.goto(url);
  if (url.includes('design=alt')) {
    await expect(page.locator('.main .klasse').first()).toBeVisible();
  } else {
    await expect(page.getByTestId('monitor-neu')).toBeVisible();
    await expect(page.locator('.mn-kachel, .mn-zk').first()).toBeVisible();
  }
  // a new plan from the server (as when the substitution plan changes)
  return (neu: Record<string, number>, uhr: string) =>
    verbindung!.send(JSON.stringify({ command: 'update_vplan', data: schultag(heute, neu, uhr) }));
}

// where every class tile is, by class
async function kachelOrte(page: Page) {
  return page.evaluate(() => Object.fromEntries(Array.from(document.querySelectorAll('.mn-kachel'))
    .map((e) => {
      const r = e.getBoundingClientRect();
      return [(e as HTMLElement).dataset.klasse, [r.x, r.y, r.width, r.height].map(Math.round).join(',')];
    })));
}

// from here on time only moves when the test says so
async function anhalten(page: Page) {
  const t = await page.evaluate(() => Date.now());
  await page.clock.pauseAt(t + 500);
}

// waits (in steps of a second) for the next page; returns the seconds
async function blaettern(page: Page) {
  const mn = page.getByTestId('monitor-neu');
  const vorher = await mn.getAttribute('data-seite');
  for (let s = 1; s <= 20; s++) {
    await page.clock.runFor(1000);
    if ((await mn.getAttribute('data-seite')) !== vorher) return s;
  }
  throw new Error('Der Monitor blättert nicht weiter.');
}

// nothing is cut off: every tile shows all lines of its current page
async function nichtsAbgeschnitten(page: Page) {
  const cut = await page.evaluate(() => Array.from(document.querySelectorAll('.mn-kachel, .mn-kachel .mn-zeilen'))
    .filter((e) => e.scrollHeight > e.clientHeight + 1).length);
  expect(cut, 'abgeschnittene Kacheln').toBe(0);
}

test('Flurmonitor, neues Design: Uhr, laufende Stunde, Kästen und Marken', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu', { '5a': 3, '5b': 1, '11': 25, '12': 26 });
  // the old layout is switched off, the new one is there
  await expect(page.locator('.main .klasse')).toHaveCount(0);
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.getByTestId('monitor-uhr')).toHaveText('11:05');
  await expect(page.getByTestId('monitor-stunde')).toContainText('4. Stunde läuft');
  await expect(page.getByTestId('monitor-stunde')).toContainText('Pause ab');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:12 Uhr');
  const k5a = page.locator('.mn-kachel[data-klasse="5a"]');
  await expect(k5a.locator('.mn-marke', { hasText: 'Vertretung' })).toHaveCount(1);
  await expect(k5a.locator('.mn-marke', { hasText: 'Entfall' })).toHaveCount(1);
  await expect(k5a.locator('.mn-marke', { hasText: 'Raum' })).toHaveCount(1);
  // every class has its tile, also without changes (then only the name)
  const k5c = page.locator('.mn-kachel[data-klasse="5c"]');
  await expect(k5c).toHaveClass(/mn-still/);
  await expect(k5c).toHaveText('5c');
  await expect(page.locator('.mn-kachel[data-klasse="11"] .mn-zeile').first()).toContainText('1.');
  // the message of "Monitore verwalten" in the foot, the scheme of the day
  await expect(page.locator('.mn-nachricht')).toContainText('Elternsprechtag');
  await expect(page.locator('.mn-schema')).toContainText('Farbschema');
  // larger type than today (1.05vw, 20 px): at least 22 px on a full HD monitor
  for (const sel of ['.mn-kachel[data-klasse="5a"] .mn-was', '.mn-kachel[data-klasse="11"] .mn-was']) {
    const size = await page.locator(sel).first().evaluate((e) => parseFloat(getComputedStyle(e).fontSize));
    expect(size, sel).toBeGreaterThanOrEqual(22);
  }
  // opaque boxes
  const bg = await k5a.evaluate((e) => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(255, 255, 255)');
  await nichtsAbgeschnitten(page);
  // no "·" anywhere (doc/Gestaltung.md)
  expect(await page.locator('#mn').innerText()).not.toContain('·');
});

test('Flurmonitor, neues Design: blättert statt zu scrollen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu', { '5a': 40, '5b': 12, '5c': 2, '11': 25, '12': 26 });
  const mn = page.getByTestId('monitor-neu');
  await expect(mn).toHaveAttribute('data-seite', '1');
  const seiten = parseInt((await mn.getAttribute('data-seiten'))!, 10);
  expect(seiten).toBeGreaterThan(1);
  await expect(page.locator('.mn-seite')).toHaveText(`Seite 1 von ${seiten}`);
  // a tile with more than fits pages inside itself, the tiles stay where they are
  const k11 = page.locator('.mn-kachel[data-klasse="11"]');
  const k5a = page.locator('.mn-kachel[data-klasse="5a"]');
  // the tile's page: dots (the current one marked), with many pages a number
  const an = (k: typeof k11) => k.locator('.mn-punkte').evaluate((p) => {
    const m = /^(\d+) von \d+$/.exec(p.textContent || '');
    return m ? parseInt(m[1], 10) - 1 : Array.from(p.children).findIndex((x) => x.classList.contains('mn-an'));
  });
  expect(await an(k11)).toBe(0);
  // many pages: the page as a number instead of dots
  await expect(k5a.locator('.mn-punkte')).toHaveText(/^1 von \d+$/);
  await expect(page.locator('.mn-kachel[data-klasse="5b"] .mn-punkte i.mn-an')).toHaveCount(1);
  await nichtsAbgeschnitten(page);
  const orte = await kachelOrte(page);
  const vorher11 = await k11.locator('.mn-zeilen').innerText();
  const vorher5a = await k5a.locator('.mn-zeilen').innerText();
  await anhalten(page);
  await blaettern(page);
  await expect(mn).toHaveAttribute('data-seite', '2');
  await expect(page.locator('.mn-seite')).toHaveText(`Seite 2 von ${seiten}`);
  expect(await an(k11)).toBe(1);
  await expect(k5a.locator('.mn-punkte')).toHaveText(/^2 von \d+$/);
  expect(await k11.locator('.mn-zeilen').innerText()).not.toBe(vorher11);
  expect(await k5a.locator('.mn-zeilen').innerText()).not.toBe(vorher5a);
  await nichtsAbgeschnitten(page);
  expect(await kachelOrte(page)).toEqual(orte);
  // every page stands 15 seconds (the bar in the foot shows it)
  const sekunden = await blaettern(page);
  expect(sekunden).toBeGreaterThanOrEqual(14);
  expect(sekunden).toBeLessThanOrEqual(16);
  // and every page comes round again
  for (let i = 0; i < seiten && (await mn.getAttribute('data-seite')) !== '1'; i++) await blaettern(page);
  await expect(mn).toHaveAttribute('data-seite', '1');
  expect(await kachelOrte(page)).toEqual(orte);
});

// The maintainer's rule: every class always in the same place, whichever
// classes have changes today – people find their class without searching.
// A full school, as on the hallway monitors.
test('Flurmonitor, neues Design: jede Klasse immer am selben Platz', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await ganzeSchule(page);
  const senden = await monitorMitTag(page, '/monitor?design=neu', { '5a': 3, '5b': 1, '7d': 6, '11': 25 });
  const k5c = page.locator('.mn-kachel[data-klasse="5c"]');
  await expect(k5c).toHaveClass(/mn-still/);
  const orte = await kachelOrte(page);
  // every class of KLASSEN_ORDER has a tile, in its order, and there is
  // nothing else: no empty tiles for classes that don't exist
  expect(await page.locator('.mn-kachel').evaluateAll((e) => e.map((x) => (x as HTMLElement).dataset.klasse)))
    .toEqual(KLASSEN_SCHULE);
  await expect(page.locator('.mn-raster .mn-kasten')).toHaveCount(KLASSEN_SCHULE.length);
  for (const k of KLASSEN_SCHULE) {
    await expect(page.locator(`.mn-kachel[data-klasse="${k}"] h2`)).toHaveText(k === '8o' ? /^8[oω]$/ : k);
  }
  await nichtsAbgeschnitten(page);
  // another day: other classes with changes, 5a and 11 without
  senden({ '5c': 4, '8o': 2, '12': 20 }, '07:30');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:30 Uhr');
  await expect(k5c).not.toHaveClass(/mn-still/);
  await expect(page.locator('.mn-kachel[data-klasse="5a"]')).toHaveClass(/mn-still/);
  await expect(page.locator('.mn-kachel[data-klasse="5a"]')).toHaveText('5a');
  await expect(page.locator('.mn-kachel[data-klasse="11"]')).toHaveText('11');
  expect(await kachelOrte(page)).toEqual(orte);
  // and a day without any change: every tile still there, only the name
  senden({}, '07:45');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:45 Uhr');
  await expect(page.locator('.mn-kachel.mn-still')).toHaveCount(KLASSEN_SCHULE.length);
  expect(await kachelOrte(page)).toEqual(orte);
});

// The distribution of the tiles is the old monitor's (monitor.html, built
// on purpose): KLASSEN_ORDER top to bottom in columns of seven, four columns,
// 11 and 12 taller. Compared tile by tile with today's monitor.
async function anordnung(page: Page, sel: string) {
  const kacheln = await page.locator(sel).evaluateAll((e) => e.map((x) => {
    const r = x.getBoundingClientRect();
    const klasse = (x as HTMLElement).dataset.klasse || /(?:^| )k(\d\S*)/.exec(x.className)![1];
    return { klasse, x: r.x, y: r.y, w: r.width, h: r.height };
  }));
  const xs: number[] = [];
  for (const k of [...kacheln].sort((a, b) => a.x - b.x)) {
    if (!xs.length || k.x - xs[xs.length - 1] > 5) xs.push(k.x);
  }
  const spalte = (k: { x: number }) => xs.findIndex((x) => Math.abs(k.x - x) <= 5);
  const normal = kacheln.find((k) => k.klasse === '5a')!;
  return Object.fromEntries(kacheln.map((k) => {
    const reihe = kacheln.filter((o) => spalte(o) === spalte(k) && o.y < k.y - 1).length;
    // position and size relative to a normal tile
    return [k.klasse, { spalte: spalte(k), reihe, hoehe: Math.round((k.h / normal.h) * 10) / 10,
      oben: Math.round(((k.y - normal.y) / normal.h) * 10) / 10, breite: Math.round((k.w / normal.w) * 100) / 100 }];
  }));
}

test('Flurmonitor, neues Design: Kacheln verteilt wie auf dem bisherigen Monitor', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await ganzeSchule(page);
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.goto('/monitor?design=alt');
  await expect(page.locator('.main .klasse')).toHaveCount(KLASSEN_SCHULE.length);
  const alt = await anordnung(page, '.main .klasse');
  await monitorMitTag(page, '/monitor?design=neu', { '5a': 2, '9c': 3, '12': 4 });
  const neu = await anordnung(page, '.mn-kachel');
  expect(Object.keys(neu).sort()).toEqual([...KLASSEN_SCHULE].sort());
  // same column and row for every class
  for (const k of KLASSEN_SCHULE) {
    expect([neu[k].spalte, neu[k].reihe], k).toEqual([alt[k].spalte, alt[k].reihe]);
  }
  expect(KLASSEN_SCHULE.map((k) => neu[k].spalte)).toEqual(KLASSEN_SCHULE.map((_, i) => Math.floor(i / 7)));
  // same relative sizes and heights (11 and 12 taller, the columns as high as each other)
  for (const k of KLASSEN_SCHULE) {
    expect(Math.abs(neu[k].hoehe - alt[k].hoehe), k).toBeLessThanOrEqual(0.1);
    expect(Math.abs(neu[k].oben - alt[k].oben), k).toBeLessThanOrEqual(0.15);
    expect(neu[k].breite, k).toBe(1);
  }
  expect(neu['11'].hoehe).toBeGreaterThan(1.4);
});

test('Flurmonitor, neues Design: dunkel', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu-dunkel', { '5a': 3, '11': 4 });
  await expect(page.getByTestId('monitor-neu')).toHaveClass(/mn-dunkel/);
  const bg = await page.locator('.mn-kachel').first().evaluate((e) => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(22, 29, 39)');
});

test('Flurmonitor, neues Design: Effekte laufen hinter den Kästen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu&effekt=schnee', { '5a': 3, '11': 4 });
  await expect(page.locator('canvas.fx-hinten-ebene')).toHaveCount(1);
  const card = page.locator('.mn-kachel').first();
  const b = (await card.boundingBox())!;
  const hit = await page.evaluate(([x, y]) => !!document.elementFromPoint(x, y)?.closest('.mn-kasten'),
    [b.x + b.width / 2, b.y + b.height / 2]);
  expect(hit, 'Kasten verdeckt').toBe(true);
  await anhalten(page);
  await page.clock.runFor(2500);
});

// Only for the hallway, and only with ?design=neu or the account's new
// design: on the monitors of Sekretariat and Lehrerzimmer, with ?design=alt
// (or any other value), and without the account's new design nothing of it
// is loaded.
test('Flurmonitor, neues Design: nur mit ?design=neu und nur im Flur', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  // without the new design in the account: today's monitor
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  expect(await (await page.request.get('/monitor')).text()).not.toContain('/preview/monitor/');
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    // with it: the new monitor in the previews (manage_monitor's iframe)
    expect(await (await page.request.get('/monitor')).text()).toContain('/preview/monitor/monitor.js');
    for (const path of ['/monitor?design=alt', '/monitor?design=', '/monitor?design[]=neu',
      '/monitor/lz?design=neu', '/monitor/sek?design=neu', '/monitor/lz', '/monitor/sek']) {
      const html = await (await page.request.get(path)).text();
      expect(html, path).not.toContain('monitor_neu');
      expect(html, path).not.toContain('/preview/monitor/');
      expect(html, path).not.toContain("media='not all'");
      expect(html, path).not.toContain('ui-preview');
    }
    const html = await (await page.request.get('/monitor?design=neu')).text();
    expect(html).toContain('/preview/monitor/monitor.js');
    expect(html).not.toContain('ui-preview');
    expect(html).not.toContain('pv-tabbar');
    expect(html).not.toContain('/preview.css');
    await page.goto('/monitor/lz?design=neu');
    await expect(page.locator('.main_lz')).toBeVisible();
    await expect(page.getByTestId('monitor-neu')).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Flurmonitor, neues Design: Zeugniskonferenzen statt Vertretungsplan', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const an = async () => (await (await page.request.post('/api/get_monitor_zeugniskonferenzen')).json()).result.flur;
  const umschalten = () => page.request.post('/api/toggle_monitor_zeugniskonferenzen', { data: { key: 'flur' } });
  expect(await an()).toBe(false);
  await umschalten();
  try {
    await monitorMitTag(page, '/monitor?design=neu', { '5a': 3 });
    await expect(page.locator('.mn-kopf h1')).toHaveText('Zeugniskonferenzen');
    await expect(page.locator('.mn-zk')).toHaveCount(1);
    await expect(page.locator('.mn-kachel')).toHaveCount(0);
  } finally {
    if (await an()) await umschalten();
  }
});
