import { test, expect, login, apiLogin, ACCOUNTS, ROLE_ACCOUNTS, dashboardDialog, listAction } from './fixtures';
import type { Page, BrowserContext, Browser } from '@playwright/test';
import { fakeBib, stationLogin, FakeBib } from './fake-bib';

// Neues Design (Vorschau): the library pages (bibliothek.html, bib_*.html),
// drawn by src/static/preview/bib.js and preview/bib.css. The test stack has
// no library service: fake-bib.ts answers every request to it with made-up
// books and loans of example accounts. The preview is for admins only on the
// test stack; the student and the library's staff get it as test persons
// (/api/set_ui_preview_tester). The staff work at a library station
// (stationLogin) – only there may a member of staff who is no teacher manage
// the library. The last test checks that the old design stays as it was.

const STAFF = ROLE_ACCOUNTS.bibliothek;

async function preview(browser: Browser, email: string, mode: 'on' | 'off') {
  const admin = await browser.newContext();
  await apiLogin(admin.request, ACCOUNTS.admin);
  if (email === ACCOUNTS.admin) await admin.request.post('/api/set_ui_preview', { data: { mode } });
  else await admin.request.post('/api/set_ui_preview_tester', { data: { email, mode } });
  await admin.close();
}

async function withBib(page: Page) {
  const bib = fakeBib();
  await bib.install(page.context());
  return bib;
}

async function atStation(page: Page, browser: Browser, device = 'bib-station') {
  const staff = await browser.newContext();
  await apiLogin(staff.request, STAFF);
  await stationLogin(page, staff.request, device);
  await staff.close();
}

function called(bib: FakeBib, path: string) {
  return bib.calls.filter((c) => c.path === path);
}

// scanning with the widget's field (no camera in the test browser; at a
// station there is never a camera): the code, then Enter like a scanner
async function scan(page: Page, code: string) {
  const input = page.locator('._barcode_widget input');
  await expect(input).toBeVisible();
  await input.fill(code);
  await input.press('Enter');
}

test('Neues Design: Meine Bücher und Bücher bestätigen (Schüler)', async ({ page, browser }) => {
  await preview(browser, ACCOUNTS.schueler, 'on');
  try {
    const bib = await withBib(page);
    await login(page, ACCOUNTS.schueler);
    await page.goto('/bibliothek');
    await expect(page.locator('body')).toHaveClass(/pv-bib-bibliothek/);
    const head = page.locator('.pv-bib-head');
    await expect(head.locator('h2')).toHaveText('Meine Bücher');
    await expect(head.locator('.pv-bib-facts')).toHaveText('4 Bücher ausgeliehen, 2 noch nicht bestätigt, 1 Buch soll zurück in die Bibliothek');
    // one main action: to the confirmation
    await expect(head.locator('#bu_pv_confirm')).toHaveText('Bücher bestätigen');
    await expect(page.locator('#unconfirmed_div')).toBeHidden();
    // students have no tabs (the library has one page for them)
    await expect(page.locator('.pv-bib-nav')).toHaveCount(0);
    // the books as rows: the one to bring back first, with its chip
    const rows = page.locator('#book_list .pv-book');
    await expect(rows).toHaveCount(4);
    await expect(rows.first().locator('.pv-book-title')).toContainText('Geschichte und Geschehen');
    await expect(rows.first().locator('.pv-bib-chip-warn')).toHaveText('Bitte zurückbringen');
    await expect(rows.filter({ hasText: 'Deutschbuch 5' }).locator('.pv-bib-chip')).toHaveText('Noch nicht bestätigt');
    await expect(rows.filter({ hasText: 'Deutschbuch 5' }).locator('.pv-book-sig')).toContainText('Signatur 1202-7, ausgeliehen am ');
    expect(await page.locator('.pv-bib-list').innerText()).not.toContain('·');
    expect(await page.locator('.pv-bib-list').innerText()).not.toMatch(/\bSie\b|\bIhre?\b/);

    // a book opens its page
    await rows.filter({ hasText: 'Deutschbuch 5' }).click();
    await expect(page).toHaveURL(/\/bib_book\/1202$/);
    await expect(page.locator('#book_title')).toHaveText('Deutschbuch 5');
    await expect(page.locator('#book_details .pv-bib-facts')).toHaveText('Cornelsen 2019, 312 Seiten, ISBN 9783060627235, 26,50 EUR, Signatur 1202');
    await expect(page.locator('#checked_out_user h3')).toHaveText('Dein Exemplar');
    await expect(page.locator('#checked_out_user .pv-bib-link')).toHaveText('Jetzt bestätigen');
    // no ordering for students
    await expect(page.locator('#bu_order_overview')).toBeHidden();

    // ---------- confirming: scan the barcode of each book ----------
    await page.goto('/bibliothek');
    await page.locator('#bu_pv_confirm').click();
    await expect(page).toHaveURL(/\/bib_confirm$/);
    await expect(page.locator('.pv-bib-head h2')).toHaveText('Bücher bestätigen');
    const open = page.locator('#book_list .pv-book:visible');
    await expect(open).toHaveCount(2);
    await expect(page.locator('#books_left')).toContainText('2');
    // another person's book: an error, nothing confirmed
    await scan(page, '1201-5');
    await expect(page.locator('#main_container > .api_messages')).toContainText('nicht auf deinen Namen ausgeliehen');
    await expect(open).toHaveCount(2);
    // one's own: gone from the list, one left
    await scan(page, '1202-7');
    await expect(open).toHaveCount(1);
    expect(called(bib, '/jwt/confirm_checked_out_book').map((c) => c.body)).toEqual([{ stem: 1201, bnr: 5 }, { stem: 1202, bnr: 7 }]);
    await scan(page, '1203-11');
    await expect(open).toHaveCount(0);
    await expect(page.locator('#no_books_left_div')).toBeVisible();
    await expect(page.locator('h3.pv-bib-section', { hasText: 'Noch nicht bestätigt' })).toBeHidden();
    // the scanner field keeps the focus for the next book
    await expect(page.locator('._barcode_widget input')).toBeFocused();
  } finally {
    await preview(browser, ACCOUNTS.schueler, 'off');
  }
});

test('Neues Design: Katalog, ein Buch bestellen, Bestellungen (Lehrkraft)', async ({ page, browser }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  const bib = await withBib(page);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/bib_browse');
    // the library's tabs: Meine Bücher, Katalog, Bestellungen
    const tabs = page.locator('.pv-bib-nav .pv-bib-tab');
    await expect(tabs).toHaveText(['Meine Bücher', 'Katalog', 'Bestellungen']);
    await expect(page.locator('.pv-bib-tab[aria-current=page]')).toHaveText('Katalog');
    await expect(page.locator('.pv-bib-head h2')).toHaveText('Katalog');
    await expect(page.locator('#ti_search')).toBeFocused();
    await page.locator('#ti_search').fill('Klett');
    await page.locator('#ti_search').press('Enter');
    const rows = page.locator('#book_list .pv-book');
    await expect(rows).toHaveCount(3);
    await expect(page.locator('.pv-bib-count')).toHaveText('3 Bücher');
    await expect(page).toHaveURL(/\/bib_browse\/Klett$/);
    // a subject as a filter chip
    const chip = page.locator('.pv-bib-filters .bu-label', { hasText: 'Mathematik' });
    await chip.click();
    await expect(chip).toHaveAttribute('aria-pressed', 'true');
    await expect(rows).toHaveCount(1);
    await chip.click();
    await expect(chip).toHaveAttribute('aria-pressed', 'false');
    await page.locator('#ti_search').fill('Zauberberg');
    await page.locator('#ti_search').press('Enter');
    await expect(page.locator('#book_list .pv-bib-empty')).toHaveText('Kein Buch passt zu »Zauberberg«. Versuche es mit weniger oder anderen Wörtern.');

    // ---------- a book, ordered for a course in a dialog ----------
    await page.goto('/bib_book/1205');
    await expect(page.locator('#book_title')).toHaveText('Der kleine Prinz');
    await expect(page.locator('.pv-bib-labels .pv-bib-chip')).toHaveText(['Deutsch', 'Lektüre']);
    // the course order from the start of the test is mentioned
    await expect(page.locator('#orders_placed_notice')).toContainText('für deinen Kurs');
    await page.locator('#bu_order_overview').click();
    const dialog = page.locator('#bibOrderModal');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('.modal-title')).toHaveText('Buch bestellen');
    await dialog.locator('#bu_order_kurs').click();
    await dialog.locator('#kurs_list_div tbody tr').first().click();
    await expect(dialog.locator('#order_kurs_div_confirm')).toBeVisible();
    const total = dialog.locator('#order_kurs_div_table tr').last();
    const before = Number(await total.locator('th').last().innerText());
    await dialog.locator('#bu_plus_teacher').click();
    await expect(dialog.locator('#bu_plus_teacher')).toHaveAttribute('aria-pressed', 'true');
    // the teacher has the book already: no extra copy
    await expect(total.locator('th').last()).toHaveText(String(before));
    await dialog.locator('#bu_place_order_kurs').click();
    await expect(dialog.locator('#bu_place_order_kurs_success')).toContainText('Deine Bestellung ist aufgenommen');
    const placed = called(bib, '/jwt/place_order_kurs');
    expect(placed).toHaveLength(1);
    expect(placed[0].body).toMatchObject({ stem: 1205, plus_teacher: 1 });
    if (phone) {
      // back closes the sheet, the page stays
      await page.goBack();
      await expect(dialog).toBeHidden();
      await expect(page).toHaveURL(/\/bib_book\/1205$/);
    } else {
      await dialog.getByRole('button', { name: 'Schließen' }).click();
      await expect(dialog).toBeHidden();
    }

    // ---------- the orders: a list, cancelling behind »•••« ----------
    await page.goto('/bib_orders');
    await expect(page.locator('.pv-bib-tab[aria-current=page]')).toHaveText('Bestellungen');
    const orders = page.locator('.pv-bib-orders .pv-lrow');
    await expect(orders).toHaveCount(3);
    await expect(page.locator('.pv-bib-head .pv-bib-facts')).toHaveText('3 Bestellungen, 2 in Bearbeitung');
    const done = orders.filter({ hasText: 'Lambacher Schweizer' });
    await expect(done.locator('.pv-lchip')).toHaveText('Bereit');
    // what was handed out already can't be cancelled
    await expect(done.locator('.pv-lmore')).toHaveCount(0);
    const fresh = orders.first();
    await expect(fresh.locator('.pv-lrow-title')).toHaveText('Der kleine Prinz');
    await listAction(page, fresh, 'Stornieren');
    await expect(dashboardDialog(page)).toContainText('wird storniert');
    await dashboardDialog(page).getByRole('button', { name: 'Stornieren' }).click();
    await expect(orders).toHaveCount(2);
    expect(called(bib, '/jwt/cancel_order')).toHaveLength(1);
    // a row opens the book
    await orders.first().locator('.pv-lrow-title').click();
    await expect(page).toHaveURL(/\/bib_book\/1205$/);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Nutzer, Ausleihe und Rückgabe an der Bibliotheksstation', async ({ page, browser }, testInfo) => {
  test.setTimeout(60_000);
  await preview(browser, STAFF, 'on');
  try {
    const bib = await withBib(page);
    await atStation(page, browser);
    await expect(page.locator('body')).toHaveClass(/pv-bib-device/);
    // no dashboard navigation at the station, the device's bar instead
    await expect(page.locator('#device_navbar')).toBeVisible();
    await expect(page.locator('.pv-bib-nav .pv-bib-tab')).toHaveText(['Katalog', 'Übersicht', 'Medien', 'Nutzer', 'Alle Bestellungen', 'Scannen', 'Rückgabe', 'Ausmustern']);

    // ---------- people: a table, a search, classes as chips ----------
    await page.locator('.pv-bib-tab', { hasText: 'Nutzer' }).click();
    await expect(page).toHaveURL(/\/bib_users$/);
    await expect(page.locator('.pv-bib-head h2')).toHaveText('Nutzer');
    await page.locator('#ti_search').fill('max mustermann');
    await page.locator('#ti_search').press('Enter');
    const max = page.locator('table.pv-st tbody tr:visible');
    await expect(max).toHaveCount(1);
    await expect(max.locator('td').first()).toHaveText('Mustermann');
    await max.click();
    await expect(page).toHaveURL(/\/bib_user\//);
    await expect(page.locator('.pv-bib-head h2')).toHaveText('Max Mustermann');
    await expect(page.locator('h3.pv-bib-section', { hasText: 'Ausgeliehen' })).toContainText('4');

    // students of the example data are not in the Lehrmittelverein: no
    // lending, said in words
    const lend = page.locator('.pv-bib-head #bu_checkout');
    await expect(lend).toHaveText('Ausleihen');
    await expect(lend).toBeDisabled();
    await expect(page.locator('#hint_no_verein')).toContainText('Max Mustermann ist nicht im Lehrmittelverein');
    await expect(page.locator('.pv-bib-head .pv-bib-facts')).toHaveText(/^Klasse 5a, .*nicht im Lehrmittelverein$/);

    // ---------- lending to a teacher: »Ausleihen«, then scan ----------
    await page.goto(`/bib_user/${encodeURIComponent(ACCOUNTS.teacher)}`);
    await expect(page.locator('h3.pv-bib-section', { hasText: 'Ausgeliehen' })).toContainText('0');
    await expect(page.locator('.pv-bib-empty', { hasText: 'Gerade nichts ausgeliehen.' })).toBeVisible();
    await lend.click();
    await expect(page.locator('#check_out_div')).toBeVisible();
    await page.locator('#ti_order_fach').fill('Deutsch');
    await scan(page, '1206-3');
    await expect(page.locator('#book_table tbody tr', { hasText: 'Biologie heute 1' })).toHaveCount(1);
    await expect(page.locator('.pv-bib-empty', { hasText: 'Gerade nichts ausgeliehen.' })).toHaveCount(0);
    expect(called(bib, '/jwt/checkout_exemplar_for_user').map((c) => c.body)).toEqual([
      { email: ACCOUNTS.teacher, stem: 1206, bnr: 3, order_fach: 'Deutsch' },
    ]);
    await expect(page.locator('._barcode_widget input')).toBeFocused();

    // ---------- returning: first only checking, then for real ----------
    await page.goto('/bib_return');
    await expect(page.locator('.pv-bib-head h2')).toHaveText('Rückgabe');
    const mode = page.locator('#bu_do_return');
    await expect(mode).toHaveAttribute('aria-checked', 'true');
    await mode.click();
    await expect(mode).toHaveAttribute('aria-checked', 'false');
    await expect(mode).toHaveText('Nur prüfen, nicht zurückbuchen');
    await scan(page, '1201-4');
    await expect(page.locator('#book_table tbody tr')).toHaveCount(1);
    expect(called(bib, '/jwt/return_book').at(-1)!.body).toMatchObject({ stem: 1201, bnr: 4, dryrun: 1 });
    expect(bib.loans.has('1201-4')).toBe(true);
    await mode.click();
    await expect(mode).toHaveAttribute('aria-checked', 'true');
    await scan(page, '1201-4');
    await expect(page.locator('#book_table tbody tr')).toHaveCount(2);
    expect(called(bib, '/jwt/return_book').at(-1)!.body.dryrun).toBeUndefined();
    expect(bib.loans.has('1201-4')).toBe(false);

    // ---------- a book with its copies, a copy summoned ----------
    await page.goto('/bib_book/1204');
    await expect(page.locator('#checked_out_all h3')).toContainText('Ausgeliehen');
    const summon = page.locator('#checked_out_all .pv-bib-summon').first();
    await expect(summon).toHaveText('Zurückgefordert');
    await summon.click();
    await expect(summon).toHaveText('Zurückfordern');
    await expect(summon).toHaveAttribute('aria-pressed', 'false');
    expect(called(bib, '/jwt/toggle_summon_exemplar')).toHaveLength(1);
    // the page's own links (Metadaten bearbeiten …) as the second row
    await expect(page.locator('#subsubmenu.pv-bib-subnav a', { hasText: 'Metadaten bearbeiten' })).toBeVisible();
  } finally {
    await preview(browser, STAFF, 'off');
  }
});

test('Altes Design: die Bibliotheksseiten bleiben, wie sie waren', async ({ page }) => {
  await withBib(page);
  await login(page, ACCOUNTS.schueler);
  await page.goto('/bibliothek');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview|pv-bib/);
  await expect(page.locator('#book_list .book')).toHaveCount(4);
  await expect(page.locator('#unconfirmed_div')).toBeVisible();
  await expect(page.locator('.pv-book, .pv-bib-head, .pv-bib-nav')).toHaveCount(0);
  const html = await (await page.request.get('/bibliothek')).text();
  expect(html).not.toContain('preview/bib.js');
  expect(html).not.toContain('PV_BIB');
});
