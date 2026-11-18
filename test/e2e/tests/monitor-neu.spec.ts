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
  await expect(page.getByTestId('monitor-neu')).toBeVisible();
  await expect(page.locator('.mn-sek, .mn-zk').first()).toBeVisible();
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
  const k5a = page.locator('.mn-sek .mn-kachel[data-klasse="5a"]');
  await expect(k5a.locator('.mn-marke', { hasText: 'Vertretung' })).toHaveCount(1);
  await expect(k5a.locator('.mn-marke', { hasText: 'Entfall' })).toHaveCount(1);
  await expect(k5a.locator('.mn-marke', { hasText: 'Raum' })).toHaveCount(1);
  // every class has its tile, also without changes (then only the name)
  const k5c = page.locator('.mn-sek .mn-kachel[data-klasse="5c"]');
  await expect(k5c).toHaveClass(/mn-still/);
  await expect(k5c).toHaveText('5c');
  await expect(page.locator('.mn-os .mn-kachel[data-klasse="11"] .mn-anzahl')).toContainText('25 Änderungen');
  // the message of "Monitore verwalten" in the foot, the scheme of the day
  await expect(page.locator('.mn-nachricht')).toContainText('Elternsprechtag');
  await expect(page.locator('.mn-schema')).toContainText('Farbschema');
  // larger type than today (1.05vw, 20 px): at least 22 px on a full HD monitor
  for (const sel of ['.mn-sek .mn-was', '.mn-os .mn-was']) {
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
  const k11 = page.locator('.mn-os .mn-kachel[data-klasse="11"]');
  const k5a = page.locator('.mn-sek .mn-kachel[data-klasse="5a"]');
  await expect(k11.locator('.mn-anzahl')).toContainText('Seite 1 von');
  await expect(k5a.locator('.mn-punkte i.mn-an')).toHaveCount(1);
  await nichtsAbgeschnitten(page);
  const orte = await kachelOrte(page);
  const vorher11 = await k11.locator('.mn-zeilen').innerText();
  const vorher5a = await k5a.locator('.mn-zeilen').innerText();
  await anhalten(page);
  await blaettern(page);
  await expect(mn).toHaveAttribute('data-seite', '2');
  await expect(page.locator('.mn-seite')).toHaveText(`Seite 2 von ${seiten}`);
  await expect(k11.locator('.mn-anzahl')).toContainText('Seite 2 von');
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
test('Flurmonitor, neues Design: jede Klasse immer am selben Platz', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const senden = await monitorMitTag(page, '/monitor?design=neu', { '5a': 3, '5b': 1, '11': 25 });
  const k5c = page.locator('.mn-kachel[data-klasse="5c"]');
  await expect(k5c).toHaveClass(/mn-still/);
  const orte = await kachelOrte(page);
  // every class of KLASSEN_ORDER has a tile
  expect(Object.keys(orte).sort()).toEqual(['11', '12', '5a', '5b', '5c']);
  // another day: other classes with changes, 5a and 11 without
  senden({ '5c': 4, '12': 20 }, '07:30');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:30 Uhr');
  await expect(k5c).not.toHaveClass(/mn-still/);
  await expect(page.locator('.mn-kachel[data-klasse="5a"]')).toHaveClass(/mn-still/);
  await expect(page.locator('.mn-kachel[data-klasse="5a"]')).toHaveText('5a');
  await expect(page.locator('.mn-kachel[data-klasse="11"] .mn-anzahl')).toHaveText('keine Änderungen');
  expect(await kachelOrte(page)).toEqual(orte);
  // and a day without any change
  senden({}, '07:45');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:45 Uhr');
  await expect(page.locator('.mn-kachel.mn-still')).toHaveCount(5);
  expect(await kachelOrte(page)).toEqual(orte);
});

test('Flurmonitor, neues Design: dunkel', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu-dunkel', { '5a': 3, '11': 4 });
  await expect(page.getByTestId('monitor-neu')).toHaveClass(/mn-dunkel/);
  const bg = await page.locator('.mn-sek .mn-kachel').first().evaluate((e) => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(22, 29, 39)');
});

test('Flurmonitor, neues Design: Effekte laufen hinter den Kästen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await monitorMitTag(page, '/monitor?design=neu&effekt=schnee', { '5a': 3, '11': 4 });
  await expect(page.locator('canvas.fx-hinten-ebene')).toHaveCount(1);
  const card = page.locator('.mn-sek .mn-kachel').first();
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
