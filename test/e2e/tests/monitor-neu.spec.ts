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

// the names of DesignTokens::CURATED (design_tokens.rb)
const CURATED_NAMES = ['Sky', 'Zoomer', 'Ravenclaw', 'Unter dem Meer', '20.000 Meilen unter dem Meer', 'Thylakoid',
  'Orangensaft', 'Gryffindor', 'Blutroter Sommer', 'BOOMBAYAH', 'Ice cream', 'Amethyst', 'Purple Valley', 'Dreamy',
  'ソフトクリーム', 'Sunset'];

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
  if (art === 0) {
    e.lehrer_neu = [KUERZEL[(i + 3) % KUERZEL.length]]; e.raum_neu = RAEUME[i % RAEUME.length];
    // now and then another subject too: »Ku statt D, Hb statt Se, 108«
    if (klasse === '5b' && i === 0) e.fach_neu = 'Ku';
  }
  if (art === 1) { e.vertretungs_text = klasse === '12' ? 'entfällt; verlegt auf 6. Std.' : 'entfällt'; delete e.fach_neu; }
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

// waits (in steps of a second) until the tile scrolls in that phase; returns the seconds
async function bisPhase(page: Page, klasse: string, phase: string, hoechstens = 120) {
  const k = page.locator(`.mn-kachel[data-klasse="${klasse}"]`);
  for (let s = 0; s <= hoechstens; s++) {
    if ((await k.getAttribute('data-rollt')) === phase) return s;
    await page.clock.runFor(1000);
  }
  throw new Error(`Die Kachel ${klasse} kommt nicht nach »${phase}«.`);
}

// how far a tile has scrolled (px)
async function versatz(page: Page, klasse: string) {
  return page.locator(`.mn-kachel[data-klasse="${klasse}"] .mn-liste`).evaluate((e) => {
    const t = getComputedStyle(e).transform;
    return Math.abs(t === 'none' ? 0 : new DOMMatrixReadOnly(t).m42);
  });
}

// nothing is cut off: no tile wider than its place, and a tile with more
// lines than fit scrolls
async function nichtsAbgeschnitten(page: Page) {
  const cut = await page.evaluate(() => Array.from(document.querySelectorAll('.mn-kachel')).filter((k) => {
    const box = k.querySelector('.mn-zeilen')!;
    const liste = k.querySelector('.mn-liste')!;
    if (k.scrollHeight > k.clientHeight + 1 || k.scrollWidth > k.clientWidth + 1) return true;
    if (liste.scrollWidth > box.clientWidth + 1) return true;
    return liste.scrollHeight > box.clientHeight + 1 && !(k as HTMLElement).dataset.rollt;
  }).map((k) => (k as HTMLElement).dataset.klasse));
  expect(cut, 'abgeschnittene Kacheln').toEqual([]);
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
  // a mark only for Entfall: the other changes show as »neu ~~alt~~«
  await expect(k5a.locator('.mn-marke')).toHaveCount(1);
  await expect(k5a.locator('.mn-marke')).toHaveText('Entfall');
  // compact as on the old monitor: one entry, one line in columns
  const vertretung = k5a.locator('.mn-zeile').first();
  await expect(vertretung.locator('.mn-st')).toHaveText('1.');
  await expect(vertretung.locator('.mn-fach')).toHaveText('D');
  await expect(vertretung.locator('.mn-wer b')).toHaveText(/^\S+$/);
  await expect(vertretung.locator('.mn-wer s.mn-alt')).toHaveText('Se');
  await expect(vertretung.locator('.mn-raum')).toHaveText('108');
  const zeile = await vertretung.evaluate((z) => Array.from(z.children).map((c) => {
    const r = c.getBoundingClientRect();
    return { top: Math.round(r.top), lines: r.height / parseFloat(getComputedStyle(c).lineHeight) };
  }));
  expect(new Set(zeile.map((c) => c.top)).size, 'eine Zeile').toBe(1);
  for (const c of zeile) expect(c.lines).toBeLessThan(1.5);
  // the old value quieter than the new one, struck through
  const ink = await vertretung.locator('.mn-wer b').evaluate((e) => getComputedStyle(e).color);
  const alt = vertretung.locator('.mn-wer .mn-alt');
  expect(await alt.evaluate((e) => getComputedStyle(e).color)).not.toBe(ink);
  expect(await alt.evaluate((e) => getComputedStyle(e).textDecorationLine)).toContain('line-through');
  // a new room: the new one, the old one struck through
  const raum = k5a.locator('.mn-zeile').nth(2).locator('.mn-raum');
  await expect(raum.locator('b')).toHaveText('317');
  await expect(raum.locator('s')).toHaveText('204');
  // the columns line up across tiles: hour, subject, teacher at the same x
  const spalten = await page.locator('.mn-kachel:not(.mn-still)').evaluateAll((ks) => ks.map((k) => {
    const z = k.querySelector('.mn-zeile')!;
    const x0 = k.getBoundingClientRect().left;
    return ['.mn-st', '.mn-fach', '.mn-wer'].map((s) => Math.round(z.querySelector(s)!.getBoundingClientRect().left - x0)).join(',');
  }));
  expect(new Set(spalten).size, spalten.join(' | ')).toBe(1);
  // another subject, another teacher
  const k5b = page.locator('.mn-kachel[data-klasse="5b"] .mn-zeile').first();
  await expect(k5b.locator('.mn-fach b')).toHaveText('Ku');
  await expect(k5b.locator('.mn-fach s')).toHaveText('D');
  // the mark says »Entfall«: the text below does not repeat it
  const entfall = page.locator('.mn-kachel[data-klasse="12"] .mn-zeile', { has: page.locator('.mn-marke', { hasText: 'Entfall' }) }).first();
  await expect(entfall.locator('.mn-text')).toHaveText('verlegt auf 6. Std.');
  await expect(entfall).not.toContainText('entfällt');
  // notes in a line below, in the columns after the hour, still readable (18 px)
  const k11 = page.locator('.mn-kachel[data-klasse="11"]');
  expect(await k11.locator('.mn-text').first().evaluate((e) => parseFloat(getComputedStyle(e).fontSize))).toBeGreaterThanOrEqual(18);
  const hinweis = k11.locator('.mn-zeile').filter({ has: page.locator('.mn-text') }).first();
  const [st, text] = await Promise.all([hinweis.locator('.mn-st').boundingBox(), hinweis.locator('.mn-text').boundingBox()]);
  expect(text!.y).toBeGreaterThan(st!.y + st!.height - 2);
  expect(text!.x).toBeGreaterThan(st!.x + st!.width - 1);
  // every class has its tile, also without changes (then only the name)
  const k5c = page.locator('.mn-kachel[data-klasse="5c"]');
  await expect(k5c).toHaveClass(/mn-still/);
  await expect(k5c).toHaveText('5c');
  // … and quiet: no white box like the tiles with changes
  expect(await k5c.evaluate((e) => getComputedStyle(e).backgroundColor)).not.toBe('rgb(255, 255, 255)');
  await expect(page.locator('.mn-kachel[data-klasse="11"] .mn-zeile').first()).toContainText('1.');
  // the message of "Monitore verwalten" in the foot, the scheme of the day
  await expect(page.locator('.mn-nachricht')).toContainText('Elternsprechtag');
  // a running ticker as on the old monitor: one line, endless, right to left
  const lauf = await page.locator('.mn-band').evaluate((b) => b.getAnimations().map((a) => [a.playState, a.effect!.getTiming().iterations]));
  expect(lauf).toEqual([['running', Infinity]]);
  await expect(page.locator('.mn-band .mn-abschnitt')).toHaveCount(2);
  await expect(page.locator('.mn-meldung .ti-speakerphone').first()).toBeAttached();
  await expect(page.locator('.mn-schema')).toContainText('Farbschema');
  // only the curated schemes of the new design (DesignTokens::CURATED)
  const schema = /»(.+)«/.exec(await page.locator('.mn-schema').innerText())![1];
  expect(CURATED_NAMES).toContain(schema);
  // the old monitor's type (1.05vw, 20 px), readable in the hallway: at least 20 px on a full HD monitor
  for (const sel of ['.mn-kachel[data-klasse="5a"] .mn-fach', '.mn-kachel[data-klasse="11"] .mn-wer']) {
    const size = await page.locator(sel).first().evaluate((e) => parseFloat(getComputedStyle(e).fontSize));
    expect(size, sel).toBeGreaterThanOrEqual(20);
  }
  // opaque boxes
  const bg = await k5a.evaluate((e) => getComputedStyle(e).backgroundColor);
  expect(bg).toBe('rgb(255, 255, 255)');
  await nichtsAbgeschnitten(page);
  // no "·" anywhere (doc/Gestaltung.md)
  expect(await page.locator('#mn').innerText()).not.toContain('·');
});

// Like the old monitor (monitor.html, »elevator«): a tile with more than
// fits stands 5 s at the top, scrolls down slowly (1 vw a second), stands
// 2 s at the bottom and goes back up quickly; the tiles stay where they are.
test('Flurmonitor, neues Design: rollt wie bisher', async ({ page }) => {
  test.setTimeout(120000);
  await login(page, ACCOUNTS.admin);
  const senden = await monitorMitTag(page, '/monitor?design=neu', { '5a': 40, '5b': 12, '5c': 2, '11': 25, '12': 26 });
  const k5a = page.locator('.mn-kachel[data-klasse="5a"]');
  await expect(k5a).toHaveAttribute('data-rollt', 'oben');
  await expect(page.locator('.mn-kachel[data-klasse="11"]')).toHaveAttribute('data-rollt', 'oben');
  // two entries fit: no scrolling
  await expect(page.locator('.mn-kachel[data-klasse="5c"]')).not.toHaveAttribute('data-rollt', /./);
  // no pages any more
  await expect(page.locator('.mn-seite, .mn-balken, .mn-kseite')).toHaveCount(0);
  await nichtsAbgeschnitten(page);
  const orte = await kachelOrte(page);
  // from a new plan on (time stands still): 5 seconds at the top
  await anhalten(page);
  senden({ '5a': 40, '5b': 12, '5c': 2, '11': 25, '12': 26 }, '07:20');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:20 Uhr');
  await page.clock.runFor(4000);
  expect(await versatz(page, '5a')).toBe(0);
  await expect(k5a).toHaveAttribute('data-rollt', 'oben');
  await bisPhase(page, '5a', 'runter', 3);
  // slowly down: 1 vw a second (19.2 px on full HD)
  const a = await versatz(page, '5a');
  await page.clock.runFor(4000);
  const b = await versatz(page, '5a');
  expect((b - a) / 4).toBeGreaterThan(17);
  expect((b - a) / 4).toBeLessThan(21.5);
  expect(await kachelOrte(page)).toEqual(orte);
  // at the bottom the last entry is in view
  await bisPhase(page, '5a', 'unten');
  const [box, letzte] = await Promise.all([k5a.locator('.mn-zeilen').boundingBox(), k5a.locator('.mn-zeile').last().locator('> *').last().boundingBox()]);
  expect(letzte!.y + letzte!.height).toBeLessThanOrEqual(box!.y + box!.height + 1);
  // a short stop, then quickly back up
  expect(await bisPhase(page, '5a', 'hoch', 4)).toBeGreaterThanOrEqual(1);
  expect(await bisPhase(page, '5a', 'oben', 12)).toBeLessThanOrEqual(10);
  expect(await versatz(page, '5a')).toBe(0);
  expect(await kachelOrte(page)).toEqual(orte);
  // a new plan starts again at the top
  await bisPhase(page, '5a', 'runter', 7);
  await page.clock.runFor(3000);
  expect(await versatz(page, '5a')).toBeGreaterThan(0);
  senden({ '5a': 40, '11': 3 }, '07:40');
  await expect(page.locator('.mn-datum')).toContainText('Stand 7:40 Uhr');
  expect(await versatz(page, '5a')).toBe(0);
  await expect(k5a).toHaveAttribute('data-rollt', 'oben');
  await expect(page.locator('.mn-kachel[data-klasse="11"]')).not.toHaveAttribute('data-rollt', /./);
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
  // every class name the same size and weight, with or without changes
  const namen = await page.locator('.mn-kachel h2').evaluateAll((e) => e.map((x) => `${getComputedStyle(x).fontSize} ${getComputedStyle(x).fontWeight}`));
  expect(new Set(namen).size, namen.join(', ')).toBe(1);
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
  // walking figures stand on the footer's top edge: it is an opaque box here
  // (on the old monitor the ticker is text, the figures walk on its line) –
  // the front layer ends exactly there. (The effects took the old page's
  // empty ticker, still in the page, and walked under the box.)
  await page.clock.resume();
  await expect.poll(() => page.evaluate(() => (document.querySelector('canvas.fx-vorne-ebene') as HTMLElement).style.clipPath)).not.toBe('');
  const boden = await page.evaluate(() => {
    const mn = document.querySelector('#mn')!.getBoundingClientRect();
    const fuss = document.querySelector('.mn-fuss')!.getBoundingClientRect();
    const clip = (document.querySelector('canvas.fx-vorne-ebene') as HTMLElement).style.clipPath;
    // inset(top right bottom left), the browser may shorten it
    const m = /inset\(([^)]*)\)/.exec(clip);
    const teile = m ? m[1].trim().split(/\s+/).map((x) => parseFloat(x)) : [];
    return { schnitt: teile.length >= 3 ? teile[2] : null, erwartet: mn.bottom - fuss.top };
  });
  expect(boden.schnitt).not.toBeNull();
  expect(Math.abs(boden.schnitt! - boden.erwartet)).toBeLessThan(1.5);
});

// Only for the hallway, and only with ?design=neu or the account's new
// design: on the monitors of Sekretariat and Lehrerzimmer, with ?design=alt
// (or any other value), and without the account's new design nothing of it
// is loaded.
test('Monitore, neues Design: nur mit ?design=neu (oder dem neuen Design im Konto)', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  // without the new design in the account (as the monitors' accounts): today's monitors
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  for (const path of ['/monitor', '/monitor/lz', '/monitor/sek', '/monitor/silentium']) {
    const html = await (await page.request.get(path)).text();
    expect(html, path).not.toContain('/preview/monitor/');
    expect(html, path).not.toContain("media='not all'");
  }
  await page.goto('/monitor/lz');
  await expect(page.locator('.main_lz')).toBeVisible();
  await expect(page.getByTestId('monitor-neu')).toHaveCount(0);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    // with it: the new monitors in the previews (manage_monitor's iframes)
    for (const path of ['/monitor', '/monitor/lz', '/monitor/sek']) {
      expect(await (await page.request.get(path)).text(), path).toContain('/preview/monitor/monitor.js');
    }
    expect(await (await page.request.get('/monitor/silentium')).text()).toContain('/preview/monitor/buchungen.css');
    for (const path of ['/monitor?design=alt', '/monitor?design=', '/monitor?design[]=neu', '/monitor/lz?design=alt']) {
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

// ---------- Lehrerzimmer, Silentium, Sekretariat ----------

// the shorthands the page has (the school's order), from its own data
async function kuerzelDerSeite(page: Page, url: string) {
  const html = await (await page.request.get(url)).text();
  const m = /id='monitor_neu_daten'>([\s\S]*?)<\/script>/.exec(html)!;
  return (JSON.parse(m[1].replace(/<\\\//g, '</')).kuerzel as string[]).filter((k) => !k.startsWith('_'));
}

function lkEintrag(k: string, i: number) {
  return { stunde_label: String((i % 8) + 1), klassen_neu: ['5a'], fach_neu: ['Ma', 'De', 'En'][i % 3], fach_alt: ['Ma', 'De', 'En'][i % 3],
    lehrer_neu: [k], lehrer_alt: [k], raum_neu: '108', raum_alt: '108', vertretungs_text: i % 2 ? 'Aufgaben im Raum' : '' };
}

// a monitor with a plan of its own: today and tomorrow, classes and teachers
async function monitorMitPlan(page: Page, url: string, heuteLehrer: Record<string, number>,
  morgenLehrer: Record<string, number>, klassenAnzahl: Record<string, number> = {}) {
  const [zeit, heute, morgen] = await page.evaluate(() => {
    const d = new Date();
    d.setHours(11, 5, 0, 0);
    const z = (n: number) => String(n).padStart(2, '0');
    const iso = (x: Date) => `${x.getFullYear()}-${z(x.getMonth() + 1)}-${z(x.getDate())}`;
    const m = new Date(d); m.setDate(m.getDate() + 1);
    return [d.getTime(), iso(d), iso(m)];
  }) as [number, string, string];
  const lehrer = (anzahl: Record<string, number>) =>
    Object.fromEntries(Object.entries(anzahl).map(([k, n]) => [k, Array.from({ length: n }, (_, i) => lkEintrag(k, i))]));
  const klassen: Record<string, unknown[]> = {};
  for (const [k, n] of Object.entries(klassenAnzahl)) klassen[k] = Array.from({ length: n }, (_, i) => eintrag(k, i));
  const stand = `${heute}T07:12:00`;
  const paket = { today: heute, tomorrow: morgen, timestamp: stand, vplan_timestamp: stand,
    data: { [heute]: { klassen, lehrer: lehrer(heuteLehrer), vplan_timestamp: stand },
            [morgen]: { klassen: {}, lehrer: lehrer(morgenLehrer), vplan_timestamp: stand } } };
  await page.clock.install({ time: new Date(zeit) });
  await page.routeWebSocket(/\/ws_monitor$/, (ws) => {
    ws.onMessage(() => {});
    ws.send(JSON.stringify({ command: 'update_time', time: Math.floor(zeit / 1000) }));
    ws.send(JSON.stringify({ command: 'update_monitor_messages', data: { messages: ['Konferenz um 15 Uhr'], images: [] } }));
    ws.send(JSON.stringify({ command: 'update_vplan', data: paket }));
  });
  await page.setViewportSize({ width: 1920, height: 1080 });
  await page.goto(url);
  await expect(page.getByTestId('monitor-neu')).toBeVisible();
}

// The Lehrerzimmer: today and tomorrow side by side, the teachers' cards run
// on without an end as before; the shorthands above each day: only the ones
// with entries take a tap – to the nearest card, highlighted for 5 s, the
// column stands still for 5 s, then runs on. No weather or feasts here.
test('Lehrerzimmer, neues Design: heute und morgen, Kürzel antippen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const url = '/monitor/lz?design=neu';
  const kuerzel = await kuerzelDerSeite(page, url);
  expect(kuerzel.length).toBeGreaterThanOrEqual(2);
  const [a, b] = kuerzel;
  // enough entries that the column runs on without an end
  await monitorMitPlan(page, url, { [a]: 12, [b]: 12 }, { [a]: 2 });
  const mn = page.getByTestId('monitor-neu');
  await expect(mn).toHaveClass(/mn-lehrerzimmer/);
  const spalten = page.locator('.mn-spalte2');
  await expect(spalten).toHaveCount(2);
  await expect(spalten.nth(0).locator('h2')).toHaveText('Heute');
  await expect(spalten.nth(1).locator('h2')).toHaveText('Morgen');
  const heute = spalten.nth(0);
  // every shorthand to see, only the ones with entries to tap
  await expect(heute.locator('.mn-chip')).toHaveCount(kuerzel.length);
  await expect(heute.locator('button.mn-chip')).toHaveCount(2);
  await expect(spalten.nth(1).locator('button.mn-chip')).toHaveCount(1);
  await expect(heute.locator('.mn-lauf')).toHaveAttribute('data-endlos', '1');
  // no effects in the Lehrerzimmer
  await expect(page.locator('canvas.fx-hinten-ebene')).toHaveCount(0);

  // tapped: to the nearest card of b, highlighted, the column still
  await page.clock.runFor(8000);
  await heute.locator(`button.mn-chip[data-kuerzel="${b}"]`).click();
  const markiert = heute.locator('.mn-karte.mn-markiert');
  await expect(markiert).toHaveCount(1);
  await expect(markiert).toHaveAttribute('data-kuerzel', b);
  await page.clock.runFor(1500);
  const lauf = heute.locator('.mn-lauf');
  const nah = await page.evaluate(() => {
    const l = document.querySelector('.mn-spalte2 .mn-lauf')!.getBoundingClientRect();
    const k = document.querySelector('.mn-spalte2 .mn-karte.mn-markiert')!.getBoundingClientRect();
    return k.top - l.top;
  });
  expect(Math.abs(nah)).toBeLessThan(40);
  const still = await lauf.evaluate((e) => e.scrollTop);
  await page.clock.runFor(2000);
  expect(await lauf.evaluate((e) => e.scrollTop)).toBe(still);
  // after 5 s: no longer highlighted, the column runs on
  await page.clock.runFor(3500);
  await expect(markiert).toHaveCount(0);
  await page.clock.runFor(2000);
  expect(await lauf.evaluate((e) => e.scrollTop)).not.toBe(still);
});

// The Sekretariat: the classes with changes on the left, the teachers on the right
test('Sekretariat, neues Design: Klassen links, Lehrkräfte rechts', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const url = '/monitor/sek?design=neu';
  const [a] = await kuerzelDerSeite(page, url);
  await monitorMitPlan(page, url, { [a]: 3 }, {}, { '5a': 2 });
  await expect(page.getByTestId('monitor-neu')).toHaveClass(/mn-sekretariat/);
  const spalten = page.locator('.mn-spalte2');
  await expect(spalten.nth(0).locator('h2')).toHaveText('Klassen');
  await expect(spalten.nth(1).locator('h2')).toHaveText('Lehrkräfte');
  await expect(spalten.nth(0).locator('.mn-karte-name').first()).toHaveText('5a');
  await expect(spalten.nth(1).locator(`.mn-karte[data-kuerzel="${a}"] .mn-zeile`)).toHaveCount(3);
  // no shorthands to tap here
  await expect(page.locator('.mn-chip')).toHaveCount(0);
});

// The Silentium's bookings monitor: its new styles only with the opt-in
test('Buchungsmonitor, neues Design: nur mit ?design=neu', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/monitor/silentium');
  await expect(page.locator('.bm-wrapper')).toBeVisible();
  await expect(page.locator('body')).not.toHaveClass(/mn-buchungen/);
  await page.goto('/monitor/silentium?design=neu');
  await expect(page.locator('body')).toHaveClass(/mn-buchungen/);
  await expect(page.locator('.bm-header')).toBeVisible();
  // opaque boxes over the scheme's picture
  expect(await page.locator('.bm-header').evaluate((e) => getComputedStyle(e).backgroundColor)).toBe('rgb(255, 255, 255)');
});
