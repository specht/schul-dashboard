import zlib from 'zlib';
import { test, expect, login, apiLogin, ACCOUNTS, dashboardDialog } from './fixtures';
import type { Page } from '@playwright/test';

// Neues Design (Vorschau), messages (/messages): the inbox as cards with
// sender, time and a "Neu" marker, the outbox as a list, the compose dialog
// with the recipients as chips in one field (a sheet on phones). The preview
// is for admins only on the test stack (UI_PREVIEW_FOR); today's design must
// stay as it is (last test).

const PREVIEW_ON = { data: { mode: 'on' } };
const PREVIEW_OFF = { data: { mode: 'off' } };

// the address of one's inbox file, taken from the page
async function inboxFile(page: Page) {
  const html = await (await page.request.get('/messages')).text();
  return html.match(/\/gen\/w\/[^/'"]+\/messages\.json\.gz/)![0];
}

// waits until the background service has written a message into the inbox
// file – without opening /messages (that marks everything as seen)
async function waitForInbox(page: Page, file: string, text: string) {
  await expect(async () => {
    const response = await page.request.get(`${file}?${Date.now()}`);
    expect(response.status()).toBe(200);
    const body = await response.body();
    let json = '';
    try { json = zlib.gunzipSync(body).toString('utf8'); } catch { json = body.toString('utf8'); }
    expect(json).toContain(text);
  }).toPass({ timeout: 40_000 });
}

test('Neues Design: Posteingang mit Absender, Uhrzeit und »Neu«', async ({ page, newUserPage }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_ON);
  try {
    const file = await inboxFile(page);
    // a teacher writes, with the fonts and colours of where it was copied from
    const marker = `Bitte an die Konferenz denken ${Date.now().toString(36)}`;
    const teacher = await newUserPage();
    await apiLogin(teacher.request, ACCOUNTS.teacher);
    const sent = await teacher.request.post('/api/send_message', {
      data: { recipients: [ACCOUNTS.admin], message: `<p style="font-family: 'Comic Sans MS'; font-size: 28px; color: rgb(255, 0, 0)">${marker}</p>` },
    });
    expect(sent.status()).toBe(200);
    const mid = (await sent.json()).message.mid as string;
    // the message id is in the inbox file once it has been written
    await waitForInbox(page, file, mid);

    await page.goto('/messages');
    const card = page.locator('.messages-container-inbox .pv-msg', { hasText: marker });
    await expect(card).toBeVisible();
    await expect(card).toHaveClass(/pv-unread/);
    await expect(card.locator('.pv-msg-new')).toHaveText('Neu');
    await expect(card.locator('.pv-msg-name')).toHaveText(/\S/);
    await expect(card.locator('.pv-msg-time')).toHaveText(/^\d\d:\d\d$/);
    await expect(card.locator('.pv-msg-avatar')).toHaveCount(1);
    await expect(card.locator('.pv-msg-reply')).toBeVisible();
    await expect(page.locator('.messages-container-inbox .pv-msg-day').first()).toHaveText('Heute');
    // the picture sits at the top, level with the name (not centred)
    const avatar = (await card.locator('.pv-msg-avatar').boundingBox())!;
    const name = (await card.locator('.pv-msg-name').boundingBox())!;
    expect(Math.abs(avatar.y - name.y)).toBeLessThan(6);
    // shown in the design's own type, whatever was pasted
    const p = card.locator('.message p').first();
    expect(await p.evaluate((el) => getComputedStyle(el).fontSize)).toBe('16px');
    expect(await p.evaluate((el) => getComputedStyle(el).color)).not.toBe('rgb(255, 0, 0)');

    // seen now: no longer new on the next visit
    await page.goto('/messages');
    const again = page.locator('.messages-container-inbox .pv-msg', { hasText: marker });
    await expect(again).toBeVisible();
    await expect(again).not.toHaveClass(/pv-unread/);
    await expect(again.locator('.pv-msg-new')).toHaveCount(0);

    // "Antworten": the dialog for the sender, titled as a reply
    await again.locator('.pv-msg-reply').click();
    const modal = page.locator('#composeModal');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h5.modal-title')).toHaveText('Antworten');
    await expect(modal.locator('.pv-rcpt-field .recipient')).toHaveCount(1);
    await modal.locator('#bu_discard_message').click();
    await expect(modal).toBeHidden();
  } finally {
    await page.request.post('/api/set_ui_preview', PREVIEW_OFF);
  }
});

test('Neues Design: Nachricht schreiben mit Empfänger-Chips, bearbeiten und löschen', async ({ page }, testInfo) => {
  const phone = testInfo.project.name === 'mobile';
  const text = `Morgen fällt die erste Stunde aus ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', PREVIEW_ON);
  try {
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
    // the remove button is a button for the keyboard too
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

    // send: the main action, solid accent
    const send = modal.locator('#bu_send_message');
    await expect(send).toBeEnabled();
    await expect(send).toHaveClass(/btn-success/);
    const sent = page.waitForResponse('**/api/send_message');
    await send.click();
    expect((await sent).status()).toBe(200);
    await expect(modal).toBeHidden();

    // the outbox: a card with the recipient and the start of the text
    const row = page.locator('.messages-container-outbox tbody tr', { hasText: text });
    await expect(row).toBeVisible();
    await expect(row.locator('.recipient')).toContainText('Max');
    await expect(row.locator('.pv-out-date')).toHaveText('Heute');
    // opened with the keyboard: editing, with short labels and a calm delete button
    await row.focus();
    await page.keyboard.press('Enter');
    await expect(modal).toBeVisible();
    await expect(modal.locator('h5.modal-title')).toHaveText('Nachricht bearbeiten');
    await expect(modal.locator('#bu_send_message')).toContainText('Speichern');
    const del = modal.locator('#bu_delete_message');
    await expect(del).toHaveText(/Löschen/);
    // red type on a calm button – solid red only in the confirmation
    const surface = await del.evaluate((el) => getComputedStyle(el.closest('.modal-content')!).backgroundColor);
    await expect.poll(() => del.evaluate((el) => getComputedStyle(el).backgroundColor)).toBe(surface);
    // the footer stays in one row
    const ys = await modal.locator('.modal-footer .btn').evaluateAll((els) => els
      .filter((el) => (el as HTMLElement).offsetWidth > 2)
      .map((el) => { const r = el.getBoundingClientRect(); return `${el.id || el.className}: ${Math.round(r.top + r.height / 2)}`; }));
    expect(ys.length).toBeGreaterThanOrEqual(3);
    const centres = ys.map((y) => Number(y.split(': ')[1]));
    expect(Math.max(...centres) - Math.min(...centres), ys.join(', ')).toBeLessThan(6);
    await del.click();
    await expect(confirm).toBeVisible();
    const deleted = page.waitForResponse('**/api/delete_message');
    await confirm.locator('.btn-danger').click();
    expect((await deleted).status()).toBe(200);
    await expect(modal).toBeHidden();
    await expect(page.locator('.messages-container-outbox tbody tr', { hasText: text })).toHaveCount(0);
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
  await expect(page.locator('.pv-msg-top, .pv-rcpt-field, .pv-msg')).toHaveCount(0);
  await expect(page.locator('#composeModal')).not.toHaveClass(/pv-sheet/);
  await page.locator('.bu-compose-message').click();
  const modal = page.locator('#composeModal');
  await expect(modal).toBeVisible();
  await expect(modal.locator('.note-fontname')).toHaveCount(1);
  await expect(modal.locator('#ti_recipients')).toHaveAttribute('placeholder', 'Empfänger suchen…');
  await expect(modal.locator('.note-placeholder')).toHaveText('Bitte geben Sie Ihre Nachricht ein');
  await modal.locator('#bu_close_message_modal').click();
  await expect(modal).toBeHidden();
});
