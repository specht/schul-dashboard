import { test, expect, login, ACCOUNTS } from './fixtures';
import { request as playwrightRequest } from '@playwright/test';

// /anmeldungen (include/public_event.rb, public_events_overview): who signed
// up for the public events. Test events from test/prepare_example_data.rb:
// "Kennenlerngespräch" has a day with 21 slots for one person each and a day
// that is over.

test('Anmeldungen im neuen Design: Termine brechen um, Anmeldungen als Tabelle', async ({ page, baseURL }, testInfo) => {
  // a sign-up from outside
  const name = `Gast ${testInfo.project.name} ${Date.now().toString(36)}`;
  const email = `gast-${testInfo.project.name}-${Date.now().toString(36)}@example.org`;
  const guest = await playwrightRequest.newContext({ baseURL });
  const keys = await (await guest.get('/anmeldung')).text().then((html) =>
    [...html.matchAll(/data-event-key='kennenlernen' data-key='([^']+)'/g)].map((m) => m[1]));
  expect(keys.length).toBeGreaterThan(20);
  // the first free slot (desktop and mobile run side by side)
  let key = '';
  for (const k of keys) {
    const data = await (await guest.post('/api/sign_up_for_public_event', { data: { event_key: 'kennenlernen', entry_key: k, name, email } })).json();
    if (data.ok) { key = k; break; }
  }
  expect(key).not.toBe('');
  await guest.dispose();

  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.setViewportSize(testInfo.project.name === 'mobile' ? { width: 412, height: 839 } : { width: 1440, height: 900 });
    await page.goto('/anmeldungen');
    const event = page.locator('.pe-event[data-event-key="kennenlernen"]');
    await expect(event.locator('h3')).toHaveText('Kennenlerngespräch');
    // no column per slot: the page never scrolls sideways
    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(1);
    const busy = event.locator('.pe-rows').first().locator('.pe-row').filter({ has: page.locator('.pe-slot:nth-child(21)') });
    await expect(busy.locator('.pe-slot')).toHaveCount(21);
    const slot = event.locator('.pe-slot.pe-full', { hasText: key.slice(11, 16) }).first();
    await expect(slot.locator('.pe-count')).toHaveText('1/1');
    // the day that is over is folded away
    const past = event.locator('details.pe-past', { hasText: 'Vergangene Termine' });
    await expect(past).toContainText('(1)');
    await expect(past).not.toHaveAttribute('open', '');
    const row = event.locator('.pe-table tr', { hasText: email });
    await expect(row.locator('td').nth(1)).toHaveText(name);
    // deleting asks first
    await row.locator('.bu-delete-signup').click();
    const dialog = page.locator('.modal.show');
    await expect(dialog).toContainText('Anmeldung löschen');
    await dialog.getByRole('button', { name: 'Löschen' }).click();
    await expect(event.locator('.pe-table tr', { hasText: email })).toHaveCount(0);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
