import zlib from 'zlib';
import { test, expect, login, apiLogin, ACCOUNTS, dashboardDialog } from './fixtures';
import type { Page, BrowserContext } from '@playwright/test';

// Neues Design (Vorschau), messages (/messages) as an inbox like a mail app:
// rows with picture, sender, the first line of the text, the time and a dot
// when unread; on desktop the opened message beside the list, on phones as a
// full screen with a back arrow (browser back and Escape close it too). 50
// rows at a time, a search over the list, the sent messages in the same list,
// the compose dialog with the recipients as chips (a sheet on phones). The
// preview is for admins only on the test stack (UI_PREVIEW_FOR); today's
// design must stay as it is (last test).

const PREVIEW_ON = { data: { mode: 'on' } };
const PREVIEW_OFF = { data: { mode: 'off' } };

function gunzipText(body: Buffer) {
  try { return zlib.gunzipSync(body).toString('utf8'); } catch { return body.toString('utf8'); }
}

// the address of one's inbox file, taken from the page (opening /messages
// marks everything there as seen)
async function inboxFile(page: Page) {
  const html = await (await page.request.get('/messages')).text();
  return html.match(/\/gen\/w\/[^/'"]+\/messages\.json\.gz/)![0];
}

// waits until the background service has written the messages into the
// inbox file – without opening /messages
async function waitForInbox(page: Page, file: string, texts: string[]) {
  await expect(async () => {
    const response = await page.request.get(`${file}?${Date.now()}`);
    expect(response.status()).toBe(200);
    const json = gunzipText(await response.body());
    for (const text of texts) expect(json).toContain(text);
  }).toPass({ timeout: 60_000 });
}

// a text and an audio comment from the lessons in the inbox file (the
// admin teaches; comments go to students), and a short sound for the player
async function addComments(context: BrowserContext | Page, from: { from: string; from_email: string }) {
  await context.route('**/gen/w/*/messages.json.gz*', async (route) => {
    const response = await route.fetch();
    const list = JSON.parse(gunzipText(await response.body())) as any[];
    // right after the newest messages, so that they are among the first rows
    const newest = Math.max(...list.map((m) => m.timestamp));
    list.push({ text_comment: '<p>Sehr schöne Präsentation, weiter so!</p>', from: from.from, from_email: from.from_email, timestamp: newest - 10, id: 'pvtesttext1', lesson_key: 'Ma_5a' });
    list.push({ audio_comment_tag: 'pvtestaudio12345', duration: 1000, from: from.from, from_email: from.from_email, timestamp: newest - 20, id: 'pvtestaudio1', lesson_key: 'Ma_5a' });
    list.sort((a, b) => b.timestamp - a.timestamp);
    await route.fulfill({ status: 200, headers: { 'content-type': 'application/octet-stream' }, body: zlib.gzipSync(Buffer.from(JSON.stringify(list))) });
  });
  await context.route('**/raw/uploads/audio_comment/**', (route) => route.fulfill({ status: 200, headers: { 'content-type': 'audio/wav' }, body: silentWav(1) }));
}

function silentWav(seconds: number) {
  const rate = 8000, n = rate * seconds;
  const b = Buffer.alloc(44 + n);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate, 28); b.writeUInt16LE(1, 32); b.writeUInt16LE(8, 34); b.write('data', 36); b.writeUInt32LE(n, 40);
  b.fill(128, 44);
  return b;
}

test('Neues Design: Posteingang als Liste, Nachricht öffnen und schließen', async ({ page, newUserPage }, testInfo) => {
  test.setTimeout(90_000);
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_ON);
  try {
    const file = await inboxFile(page);
    // a teacher writes twice, with the fonts and colours of where it was copied from
    const stamp = Date.now().toString(36);
    const first = `Bitte an die Konferenz denken ${stamp}`;
    const second = `Der Raum 108 ist morgen gesperrt ${stamp}`;
    const teacher = await newUserPage();
    await apiLogin(teacher.request, ACCOUNTS.teacher);
    const mids: string[] = [];
    for (const text of [first, second]) {
      const sent = await teacher.request.post('/api/send_message', {
        data: { recipients: [ACCOUNTS.admin], message: `<p style="font-family: 'Comic Sans MS'; font-size: 28px; color: rgb(255, 0, 0)">${text}</p><p>Viele Grüße</p>` },
      });
      expect(sent.status()).toBe(200);
      mids.push((await sent.json()).message.mid as string);
      // one second apart, so that their order is certain
      await page.waitForTimeout(1100);
    }
    await waitForInbox(page, file, mids);
    const json = JSON.parse(gunzipText(await (await page.request.get(`${file}?${Date.now()}`)).body())) as any[];
    const sender = json.find((m) => m.mid === mids[0]);
    await addComments(page, sender);

    await page.goto('/messages');
    const inbox = page.locator('.messages-container-inbox');
    const rowOf = (text: string) => inbox.locator('.pv-mrow', { hasText: text });
    // the rows: picture, sender, time, the first line, a dot when unread
    const row = rowOf(second);
    await expect(row).toBeVisible();
    await expect(row).toHaveClass(/pv-unread/);
    await expect(rowOf(first)).toHaveClass(/pv-unread/);
    await expect(row.locator('.pv-mrow-name')).toContainText(sender.from);
    await expect(row.locator('.pv-mrow-time')).toHaveText(/^\d{1,2}:\d\d$/);
    await expect(row.locator('.pv-mrow-preview')).toHaveText(`${second} Viele Grüße`);
    await expect(row.locator('.pv-msg-avatar')).toHaveCount(1);
    expect(await row.locator('.pv-mrow-dot').evaluate((el) => getComputedStyle(el).backgroundColor)).not.toBe('rgba(0, 0, 0, 0)');
    // (Gestern only when the test runs at midnight)
    await expect(inbox.locator('.pv-mgroup').first()).toHaveText(/^(Heute|Gestern)$/);
    await expect(page.locator('#bu-inbox')).toHaveText(/^Eingang, \d+ neu$/);
    const unreadBefore = Number((await page.locator('#bu-inbox').textContent())!.match(/(\d+) neu/)![1]);
    // rows divided by hairlines, no cards; one line of preview
    const preview = row.locator('.pv-mrow-preview');
    expect(await preview.evaluate((el) => getComputedStyle(el).whiteSpace)).toBe('nowrap');
    expect(await row.evaluate((el) => getComputedStyle(el).borderBottomStyle)).toBe('solid');
    // the picture sits at the top, level with the name (not centred)
    const avatar = (await row.locator('.pv-msg-avatar').boundingBox())!;
    const name = (await row.locator('.pv-mrow-name').boundingBox())!;
    expect(Math.abs(avatar.y - name.y)).toBeLessThan(8);
    // no "·" anywhere
    expect(await page.locator('#main_container').innerText()).not.toContain('·');

    const reader = page.locator('.pv-mail-reader');
    if (!phone) {
      // side by side: nothing opened yet, a calm hint
      await expect(reader.locator('.pv-read-hint')).toHaveText('Keine Nachricht ausgewählt');
      const list = (await page.locator('.pv-mail-list').boundingBox())!;
      const right = (await reader.boundingBox())!;
      expect(right.x).toBeGreaterThan(list.x + list.width - 1);
      expect(Math.abs(right.y - list.y)).toBeLessThan(4);
    } else {
      await expect(reader).toBeHidden();
    }

    // open: sender, "an mich", date and time, the text in the design's own type
    await row.click();
    await expect(page).toHaveURL(new RegExp(`#nachricht/${mids[1]}$`));
    await expect(reader.locator('.pv-read-name')).toHaveText(sender.from);
    await expect(reader.locator('.pv-read-to')).toHaveText('an mich');
    await expect(reader.locator('.pv-read-time')).toHaveText(/^(Mo|Di|Mi|Do|Fr|Sa|So), \d{1,2}\.\d{1,2}\., \d{1,2}:\d\d Uhr$/);
    const p = reader.locator('.message p').first();
    await expect(p).toHaveText(second);
    expect(await p.evaluate((el) => getComputedStyle(el).fontSize)).toBe('16px');
    expect(await p.evaluate((el) => getComputedStyle(el).color)).not.toBe('rgb(255, 0, 0)');
    // read now: no dot, one fewer new
    await expect(row).not.toHaveClass(/pv-unread/);
    await expect(page.locator('#bu-inbox')).toHaveText(unreadBefore > 1 ? `Eingang, ${unreadBefore - 1} neu` : 'Eingang');
    if (phone) {
      // a full screen above the list and the tab bar, "Antworten" at the bottom
      await page.waitForTimeout(300);
      const box = (await reader.boundingBox())!;
      const viewport = page.viewportSize()!;
      expect(box.y).toBeLessThanOrEqual(1);
      expect(box.height).toBeGreaterThanOrEqual(viewport.height - 2);
      const reply = (await reader.locator('.pv-read-reply').boundingBox())!;
      expect(reply.y + reply.height).toBeGreaterThan(viewport.height - 80);
      // the browser's back button closes it
      await page.goBack();
      await expect(reader).toBeHidden();
      await expect(row).toBeVisible();
      expect(new URL(page.url()).hash).toBe('');
      // Escape too
      await row.click();
      await expect(reader.locator('.pv-read-name')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(reader).toBeHidden();
      // and the back arrow
      await row.click();
      await reader.locator('.pv-read-back').click();
      await expect(reader).toBeHidden();
      await row.click();
    } else {
      await expect(row).toHaveClass(/pv-selected/);
      await expect(reader.locator('.pv-read-back')).toBeHidden();
      // the keyboard: arrow down opens the next row, Enter opens the focused one
      await row.focus();
      await page.keyboard.press('ArrowDown');
      await expect(rowOf(first)).toBeFocused();
      await expect(reader.locator('.message p').first()).toHaveText(first);
      await page.keyboard.press('ArrowUp');
      await expect(row).toBeFocused();
      await expect(reader.locator('.message p').first()).toHaveText(second);
    }

    // a reload keeps the opened message
    await page.reload();
    await expect(reader.locator('.message p').first()).toHaveText(second);
    // "Antworten": the dialog for the sender, titled as a reply
    await reader.locator('.pv-read-reply').click();
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h5.modal-title')).toHaveText('Antworten');
    await expect(modal.locator('.pv-rcpt-field .recipient')).toHaveCount(1);
    await modal.locator('#bu_discard_message').click();
    await expect(modal).toBeHidden();
    if (phone) await reader.locator('.pv-read-back').click();

    // a comment from the lessons, and an audio comment one can play
    await rowOf('Sehr schöne Präsentation').click();
    await expect(reader.locator('.pv-read-to')).toHaveText('Rückmeldung aus dem Unterricht');
    await expect(reader.locator('.message')).toHaveText('Sehr schöne Präsentation, weiter so!');
    await expect(reader.locator('.pv-read-reply')).toHaveCount(0);
    if (phone) await reader.locator('.pv-read-back').click();
    const audioRow = rowOf('Audio-Rückmeldung');
    await expect(audioRow.locator('.pv-mrow-preview')).toHaveText('Audio-Rückmeldung, 0:01');
    await audioRow.click();
    const player = reader.locator('.audio-player');
    await expect(player).toBeVisible();
    await expect(player.locator('a[href$=".mp3"]')).toBeVisible();
    await player.locator('.player-button').click();
    await expect(player.locator('.player-button .fa')).toHaveClass(/fa-pause|fa-play/);
    await expect.poll(() => page.evaluate(() => (window as any).pb_url as string | null)).toContain('/raw/uploads/audio_comment/pv/');
  } finally {
    await page.request.post('/api/set_ui_preview', PREVIEW_OFF);
  }
});

test('Neues Design: 50 Zeilen, weitere beim Scrollen, Suche', async ({ page, newUserPage }) => {
  test.setTimeout(120_000);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_ON);
  try {
    const file = await inboxFile(page);
    const stamp = Date.now().toString(36);
    const teacher = await newUserPage();
    await apiLogin(teacher.request, ACCOUNTS.teacher);
    const mids: string[] = [];
    for (let i = 0; i < 56; i++) {
      const sent = await teacher.request.post('/api/send_message', {
        data: { recipients: [ACCOUNTS.admin], message: `<p>Seitentest ${stamp} Nummer ${i} Code ${stamp}-${i}-ende</p>` },
      });
      expect(sent.status()).toBe(200);
      mids.push((await sent.json()).message.mid as string);
    }
    await waitForInbox(page, file, [mids[0], mids[55]]);

    // only the rows one sees load their text
    const bodies: string[] = [];
    page.on('request', (r) => { if (r.url().includes('/gen/m/')) bodies.push(r.url()); });
    await page.goto('/messages');
    const inbox = page.locator('.messages-container-inbox');
    const rows = inbox.locator('.pv-mrow');
    await expect(rows).toHaveCount(50);
    await expect(rows.first().locator('.pv-mrow-preview')).toHaveText(/Seitentest/);
    const total = await page.evaluate(() => (window as any).pv.items.in.length as number);
    expect(total).toBeGreaterThan(55);
    expect(bodies.length).toBeLessThan(40);
    // scrolling down shows the next ones
    await rows.last().scrollIntoViewIfNeeded();
    await expect(rows).toHaveCount(Math.min(total, 100));
    // the button as a fallback
    if (total > 100) {
      await page.evaluate(() => (document.querySelector('.messages-container-inbox .bu_pv_more') as HTMLElement).click());
      await expect(rows).toHaveCount(Math.min(total, 150));
    }

    // the search filters the whole list
    await page.evaluate(() => window.scrollTo(0, 0));
    const search = page.locator('#ti_pv_search');
    const newest = (await rows.first().locator('.pv-mrow-preview').textContent())!;
    const code = newest.match(/^Seitentest \w+ Nummer \d+ Code (\S+)$/)![1];
    // case does not matter; one word of the text is enough
    await search.fill(code.toUpperCase());
    await expect(rows).toHaveCount(1);
    await expect(rows.first()).toContainText(newest);
    await search.fill('Torstenson');
    await expect(rows).toHaveCount(50);
    await search.fill('xyzkeinetreffer');
    await expect(rows).toHaveCount(0);
    await expect(inbox.locator('.pv-mail-empty-title')).toHaveText('Keine Treffer');
    await search.fill('');
    await expect(rows).toHaveCount(50);
  } finally {
    await page.request.post('/api/set_ui_preview', PREVIEW_OFF);
  }
});

test('Neues Design: Nachricht schreiben mit Empfänger-Chips, Gesendet, bearbeiten und löschen', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  const stamp = Date.now().toString(36);
  const text = `Morgen fällt die erste Stunde aus ${stamp}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_ON);
  try {
    // a message to several people: "an … und 2 weitere"
    const many = await page.request.post('/api/send_message', {
      data: { recipients: [ACCOUNTS.schueler, ACCOUNTS.schueler_oberstufe, ACCOUNTS.teacher], message: `<p>An mehrere ${stamp}</p>` },
    });
    expect(many.status()).toBe(200);
    await page.goto('/messages');
    // "Neue Nachricht" next to the title
    const top = page.locator('.pv-msg-top');
    await expect(top.locator('h2')).toHaveText('Nachrichten');
    await top.locator('.bu-compose-message').click();
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h5.modal-title')).toHaveText('Neue Nachricht');
    if (phone) {
      // a sheet from the bottom edge
      await expect(modal).toHaveClass(/pv-sheet/);
      await page.waitForTimeout(400);
      const box = (await modal.locator('.modal-content').boundingBox())!;
      expect(box.y + box.height).toBeGreaterThanOrEqual(page.viewportSize()!.height - 2);
    }
    // only the tools that survive the design's own type
    await expect(modal.locator('.note-btn-bold')).toBeVisible();
    await expect(modal.locator('.note-fontname, .note-fontsize, .note-color')).toHaveCount(0);

    // recipients: suggestions, arrow keys and Enter, chips in the field
    const input = modal.locator('#ti_recipients');
    const field = modal.locator('.pv-rcpt-field');
    const dropdown = modal.locator('.recipient-input-dropdown');
    await input.pressSequentially('Klasse 5');
    await expect(dropdown).toBeVisible();
    expect(await dropdown.locator('.recipient').count()).toBeGreaterThan(0);
    await input.press('ArrowDown');
    await expect(dropdown.locator('.recipient.pv-active')).toHaveCount(1);
    const chosen = (await dropdown.locator('.recipient.pv-active').textContent())!.trim();
    await input.press('Enter');
    await expect(field.locator('.recipient')).toHaveCount(1);
    await expect(field.locator('.recipient')).toContainText(chosen.replace(/\s*\(\d+\)$/, ''));
    await expect(dropdown).toBeHidden();
    // Backspace in the empty field takes the last one out again
    await input.press('Backspace');
    await expect(field.locator('.recipient')).toHaveCount(0);
    await input.pressSequentially('Max Mustermann');
    await input.press('Enter');
    await expect(field.locator('.recipient')).toHaveCount(1);
    await expect(modal.locator('#recipient_count')).toHaveText('1 Empfänger');
    // Escape closes the suggestions, not the dialog
    await input.pressSequentially('Klasse');
    await expect(dropdown).toBeVisible();
    await input.press('Escape');
    await expect(dropdown).toBeHidden();
    await expect(modal).toBeVisible();
    await expect(field.locator('.recipient .rm')).toHaveAttribute('role', 'button');
    await input.fill('');

    // pasted text keeps its structure, not its look
    const editor = modal.locator('.note-editable');
    await editor.click();
    await editor.evaluate((el, t) => {
      const data = new DataTransfer();
      data.setData('text/html', `<p style="font-family: Arial; font-size: 30px; color: red">${t} <span style="font-weight: bold">wichtig</span></p>`);
      data.setData('text/plain', t);
      el.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
    }, text);
    await expect(editor).toContainText(text);
    expect(await editor.innerHTML()).not.toMatch(/style=|font-family|30px/);
    expect(await editor.locator('b').count()).toBeGreaterThan(0);

    // the link dialog opens on its own (not nested in the sheet) and closes again
    await modal.locator('.note-toolbar .note-insert button').first().click();
    const linkDialog = page.locator('body > .note-modal', { hasText: 'Link einfügen' });
    await expect(linkDialog).toBeVisible();
    await linkDialog.locator('.close').click();
    await expect(linkDialog).toBeHidden();
    await expect(modal).toBeVisible();

    // closing with changes asks first; "Weiter bearbeiten" keeps it
    await modal.locator('.modal-header').click();
    await page.keyboard.press('Escape');
    const confirm = dashboardDialog(page);
    await expect(confirm).toBeVisible();
    await expect(confirm.locator('.modal-title')).toHaveText('Nachricht verwerfen?');
    await confirm.getByRole('button', { name: 'Weiter bearbeiten' }).click();
    await expect(confirm).toBeHidden();
    await expect(modal).toBeVisible();
    await expect(editor).toContainText(text);

    // send: the main action; afterwards the sent messages
    const send = modal.locator('#bu_send_message');
    await expect(send).toBeEnabled();
    await expect(send).toHaveClass(/btn-success/);
    const sent = page.waitForResponse('**/api/send_message');
    await send.click();
    expect((await sent).status()).toBe(200);
    await expect(modal).toBeHidden();
    await expect(page.locator('#bu-outbox')).toHaveAttribute('aria-pressed', 'true');
    await expect(page).toHaveURL(/#gesendet$/);

    // the same list: recipients instead of the sender, the time, the first line
    const outbox = page.locator('.messages-container-outbox');
    const row = outbox.locator('.pv-mrow', { hasText: text });
    await expect(row).toBeVisible();
    await expect(row.locator('.pv-mrow-name')).toHaveText(/^an Max Mustermann$/);
    await expect(row.locator('.pv-mrow-time')).toHaveText(/^\d{1,2}:\d\d$/);
    await expect(outbox.locator('.pv-mrow', { hasText: `An mehrere ${stamp}` }).locator('.pv-mrow-name')).toHaveText(/^an .+ und 2 weitere$/);

    // opened with the keyboard: recipients, text, "Bearbeiten" and a calm "Löschen"
    const reader = page.locator('.pv-mail-reader');
    await row.focus();
    await page.keyboard.press('Enter');
    await expect(page).toHaveURL(/#gesendet\/\w+$/);
    await expect(reader.locator('.pv-read-name')).toHaveText('an Max Mustermann');
    await expect(reader.locator('.message')).toContainText(text);
    const del = reader.locator('#bu_pv_delete');
    await expect(del).toHaveText('Löschen');
    const surface = await page.locator('.container').first().evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(await del.evaluate((el) => getComputedStyle(el).backgroundColor)).toBe(surface);

    // edit: the dialog as today, with short labels; saved, the message shows the new text
    await reader.locator('#bu_pv_edit').click();
    await expect(modal).toBeVisible();
    await expect(modal.locator('h5.modal-title')).toHaveText('Nachricht bearbeiten');
    await expect(modal.locator('#bu_send_message')).toContainText('Speichern');
    await expect(modal.locator('#bu_delete_message')).toHaveText(/Löschen/);
    // the footer stays in one row
    const centres = await modal.locator('.modal-footer .btn').evaluateAll((els) => els
      .filter((el) => (el as HTMLElement).offsetWidth > 2)
      .map((el) => { const r = el.getBoundingClientRect(); return Math.round(r.top + r.height / 2); }));
    expect(centres.length).toBeGreaterThanOrEqual(3);
    expect(Math.max(...centres) - Math.min(...centres)).toBeLessThan(6);
    await editor.click();
    await page.keyboard.press('End');
    await page.keyboard.type(' geändert');
    const updated = page.waitForResponse('**/api/update_message');
    await modal.locator('#bu_send_message').click();
    expect((await updated).status()).toBe(200);
    await expect(modal).toBeHidden();
    await expect(reader.locator('.message')).toContainText('geändert');
    await expect(row.locator('.pv-mrow-preview')).toContainText('geändert');

    // delete: asked first, solid red only there
    await del.click();
    await expect(confirm).toBeVisible();
    await expect(confirm.locator('.modal-title')).toHaveText('Nachricht löschen?');
    const deleted = page.waitForResponse('**/api/delete_message');
    await confirm.locator('.btn-danger', { hasText: 'Löschen' }).click();
    expect((await deleted).status()).toBe(200);
    await expect(outbox.locator('.pv-mrow', { hasText: text })).toHaveCount(0);
    if (phone) await expect(reader).toBeHidden();
    else await expect(reader.locator('.pv-read-hint')).toBeVisible();
    await expect(page).toHaveURL(/#gesendet$/);
  } finally {
    await page.request.post('/api/set_ui_preview', PREVIEW_OFF);
  }
});

// Without the preview the page stays as it is (it serves everyone).
test('Nachrichten ohne Vorschau: unverändert', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_OFF);
  await page.goto('/messages');
  await expect(page.locator('body')).not.toHaveClass(/pv-messages-page/);
  await expect(page.locator('.pv-msg-top, .pv-rcpt-field, .pv-mail, .pv-mrow, #ti_pv_search')).toHaveCount(0);
  await expect(page.locator('#composeModal')).not.toHaveClass(/pv-sheet/);
  await expect(page.locator('#bu-inbox')).toHaveText(/Posteingang/);
  await expect(page.locator('.messages-container-outbox table thead')).toHaveCount(1);
  await page.locator('.bu-compose-message').click();
  const modal = page.locator('#composeModal');
  await expect(modal).toBeVisible();
  await expect(modal.locator('.note-fontname')).toHaveCount(1);
  await expect(modal.locator('#ti_recipients')).toHaveAttribute('placeholder', 'Empfänger suchen…');
  await expect(modal.locator('.note-placeholder')).toHaveText('Bitte geben Sie Ihre Nachricht ein');
  await modal.locator('#bu_close_message_modal').click();
  await expect(modal).toBeHidden();
  // the server hands over no times for the new design
  const html = await (await page.request.get('/messages')).text();
  expect(html).not.toMatch(/var sent_messages = \[[^\n]*"timestamp"/);
});
