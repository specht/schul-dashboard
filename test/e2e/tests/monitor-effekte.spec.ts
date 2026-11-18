import { test, expect, login, ACCOUNTS } from './fixtures';

// Wetter- und Festeffekte auf den Monitoren (src/static/monitor_effekte.js).
// The test stack never asks the Deutscher Wetterdienst (MONITOR_DWD_WARNCELL
// is nil in test/credentials.rb), so every effect is checked through the
// preview parameter ?effekt=… – the same one "Monitore verwalten" uses.

const EFFEKTE = ['schnee', 'regen', 'gewitter', 'hitze', 'sturm', 'glatteis', 'frost',
  'weihnachten', 'nikolaus', 'ostern', 'valentinstag', 'fasching', 'sommerferien', 'schulanfang',
  'adventskonzert', 'forschertag', 'rundgang'];

for (const effekt of EFFEKTE) {
  test(`Monitor-Effekt ${effekt}: läuft hinter den Kästen, die Einträge bleiben lesbar`, async ({ page }) => {
    await login(page, ACCOUNTS.admin);
    await page.setViewportSize({ width: 1280, height: 720 });
    await page.goto(`/monitor?effekt=${effekt}`);
    const card = page.locator('.main .klasse').first();
    await expect(card).toBeVisible();
    // both layers exist; the front one never takes clicks
    await expect(page.locator('canvas.fx-hinten-ebene')).toHaveCount(1);
    await expect(page.locator('canvas.fx-vorne-ebene')).toHaveCount(1);
    for (const sel of ['canvas.fx-vorne-ebene', 'div.fx-vorne-ebene']) {
      expect(await page.locator(sel).evaluate((e) => getComputedStyle(e).pointerEvents)).toBe('none');
    }
    // in the middle of a card there is the card, not an effect
    const b = (await card.boundingBox())!;
    const hit = await page.evaluate(([x, y]) => {
      const e = document.elementFromPoint(x, y);
      return e ? !!e.closest('.klasse') : false;
    }, [b.x + b.width / 2, b.y + b.height / 2]);
    expect(hit, 'Kasten verdeckt').toBe(true);
    // the class name pebble stays on top of snow caps, drips and boots
    const pebble = (await card.locator('h3').boundingBox())!;
    const onPebble = await page.evaluate(([x, y]) => document.elementFromPoint(x, y)?.closest('h3') !== null,
      [pebble.x + pebble.width / 2, pebble.y + pebble.height * 0.7]);
    expect(onPebble, 'Kiesel verdeckt').toBe(true);
    // the ticker band at the bottom always stays above every effect
    const z = await page.locator('.ticker').evaluate((e) => parseInt(getComputedStyle(e).zIndex || '0', 10));
    expect(z).toBeGreaterThan(60);
    // no extra hint text on the monitor
    await expect(page.locator('.fx-hinweis')).toHaveCount(0);
    // let the effect run a little (runs into the error check of the fixtures)
    await page.waitForTimeout(2500);
  });
}

test('Monitor-Effekte: Weihnachtsmann fliegt, Osterhase versteckt Eier', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.setViewportSize({ width: 1280, height: 720 });
  await page.goto('/monitor?effekt=weihnachten');
  await expect(page.locator('.fx-schlitten-flug')).toHaveCount(1, { timeout: 10000 });
  await page.goto('/monitor?effekt=ostern');
  await expect(page.locator('.fx-hase')).toHaveCount(1, { timeout: 10000 });
  await expect(page.locator('.fx-ei').first()).toBeAttached({ timeout: 20000 });
});

test('Monitor-Effekte: Stand abfragen und auf „Monitore verwalten“ ab- und einschalten', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  const stand = await (await page.request.get('/api/monitor_effekte')).json();
  expect(stand.an).toBe(true);
  expect(stand.wetter).toBeNull();
  expect(stand.bereit).toBe(true);

  await page.goto('/manage_monitor');
  const schalter = page.locator('.ti_monitor_effekte');
  await expect(schalter).toBeEnabled();
  await expect(schalter).toBeChecked();
  await page.locator('label[for="ti_monitor_effekte"]').click();
  await expect(page.getByTestId('monitor-effekte-status')).toContainText('ausgeschaltet');
  await expect(schalter).not.toBeChecked();
  expect((await (await page.request.get('/api/monitor_effekte')).json()).an).toBe(false);
  // switched off, the monitor shows no effect (a preview with ?effekt= still would)
  await page.goto('/monitor');
  await expect(page.locator('.main .klasse').first()).toBeVisible();
  await page.waitForTimeout(1000);
  await expect(page.locator('.fx-deko')).toHaveCount(0);
  await page.goto('/manage_monitor');
  await expect(schalter).toBeEnabled();
  await page.locator('label[for="ti_monitor_effekte"]').click();
  await expect(schalter).toBeChecked();
  await expect(page.getByTestId('monitor-effekte-status')).not.toContainText('ausgeschaltet');

  // the hallway monitor at the top always shows the live picture
  await expect(page.locator('.if_monitor_flur')).toHaveAttribute('src', '/monitor');
  // preview buttons open a second window below, the live one stays untouched
  const vorschau = page.getByTestId('monitor-effekt-vorschau');
  await expect(vorschau).toBeHidden();
  await page.locator('.bu_monitor_effekt_vorschau[data-effekt="gewitter"]').click();
  await expect(vorschau).toBeVisible();
  await expect(page.locator('.if_monitor_vorschau')).toHaveAttribute('src', '/monitor?effekt=gewitter');
  await expect(page.locator('.if_monitor_flur')).toHaveAttribute('src', '/monitor');
  // from the preview, the effect can be shown on the real monitors for a few minutes
  await page.locator('.bu_fx_test_starten').click();
  await expect(page.getByTestId('monitor-effekt-test')).toContainText('Gewitter');
  const mitTest = await (await page.request.get('/api/monitor_effekte')).json();
  expect(mitTest.test.effekt).toBe('gewitter');
  expect(mitTest.wetter.effekt).toBe('gewitter');
  expect(mitTest.test.rest_ms).toBeGreaterThan(4 * 60 * 1000);
  await page.locator('.bu_fx_test_beenden').click();
  await expect(page.getByTestId('monitor-effekt-test')).toBeHidden();
  const ohneTest = await (await page.request.get('/api/monitor_effekte')).json();
  expect(ohneTest.test).toBeUndefined();
  expect(ohneTest.wetter).toBeNull();
  await page.locator('.bu_monitor_effekt_vorschau[data-effekt=""]').click();
  await expect(vorschau).toBeHidden();
});

test('Monitor-Effekte: Schultermin eintragen, Forschertag mit drei Tagen, wieder löschen', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.goto('/manage_monitor');
  const form = page.getByTestId('monitor-schultermin-form');
  await expect(form).toBeVisible();
  await form.locator('.ti_fx_termin_motiv').selectOption('forschertag');
  await form.locator('.ti_fx_termin_datum').fill('2099-06-15');
  // a research day lasts three days: the end date is filled in
  await expect(form.locator('.ti_fx_termin_bis')).toHaveValue('2099-06-17');
  await form.locator('.ti_fx_termin_titel').fill('E2E-Forschertage');
  await form.locator('.bu_fx_termin_eintragen').click();
  const liste = page.getByTestId('monitor-schultermine');
  await expect(liste).toContainText('15.06.2099 – 17.06.2099');
  await expect(liste).toContainText('E2E-Forschertage');
  const stand = await (await page.request.get('/api/monitor_effekte')).json();
  expect(stand.schultermine.some((t: { titel: string, bis: string }) => t.titel === 'E2E-Forschertage' && t.bis === '2099-06-17')).toBe(true);
  await liste.locator('li', { hasText: 'E2E-Forschertage' }).locator('.bu_fx_termin_loeschen').click();
  await expect(liste).not.toContainText('E2E-Forschertage');
});

test('Monitor-Effekte: nur für Monitore und Monitor-Verwaltung', async ({ page }) => {
  await login(page, ACCOUNTS.schueler);
  expect((await page.request.get('/api/monitor_effekte')).status()).not.toBe(200);
  expect((await page.request.post('/api/set_monitor_effekte', { data: { an: 'nein' } })).status()).not.toBe(200);
  expect((await page.request.post('/api/add_monitor_schultermin', { data: { datum: '2099-01-01', motiv: 'adventskonzert' } })).status()).not.toBe(200);
  expect((await page.request.post('/api/delete_monitor_schultermin', { data: { id: 'x' } })).status()).not.toBe(200);
  expect((await page.request.post('/api/monitor_effekte_test', { data: { effekt: 'sturm' } })).status()).not.toBe(200);
});
