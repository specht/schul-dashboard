import { test, expect, login, dashboardDialog, showDayInTimetable, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// /unterrichtsmails: admins change the texts teachers send to parents from a
// lesson (timetable → Mail), with placeholders and a preview that renders
// exactly like the mail bot (src/ruby/lesson_mail_templates.rb). Teachers
// see the mail before sending it. The mail bot itself is not part of the
// test stack; its texts are checked in
// src/ruby/test/unit/lesson_mail_templates_test.rb.
// Example data: Clarke teaches Mathematik in 5a (Ma_5a), Max Mustermann is in 5a.

test.describe.configure({ mode: 'serial' });

const NEW_BODY = 'Liebe Eltern,\n\n{Name} aus der Klasse {Klasse} hat {seine|ihre} Sachen vergessen{Notiz}.\n\nViele Grüße\n{Lehrkraft}';

// desktop and mobile run at the same time on the same database: each
// changes a text of its own
const CASES = {
  desktop: {
    reason: 'homework', label: 'Hausaufgaben fehlen', note: 'S. 23, Nr. 4',
    subject: 'Fehlende Hausaufgaben im Fach Mathematik', defaultSubject: 'Fehlende Hausaufgaben im Fach {Fach}',
    sentence: 'Ihr Sohn Max hat heute im Fach Mathematik die Hausaufgaben nicht oder nicht vollständig vorlegen können (S. 23, Nr. 4).',
  },
  mobile: {
    reason: 'material', label: 'Material fehlt', note: 'Zirkel fehlt',
    subject: 'Fehlendes Arbeitsmaterial im Fach Mathematik', defaultSubject: 'Fehlendes Arbeitsmaterial im Fach {Fach}',
    sentence: 'Ihr Sohn Max hat heute im Fach Mathematik das Arbeitsmaterial nicht oder nicht vollständig dabei gehabt (Zirkel fehlt).',
  },
};

test('Mails aus dem Unterricht: Admin ändert einen Text mit Vorschau', async ({ page }, testInfo) => {
  const c = CASES[testInfo.project.name as keyof typeof CASES] ?? CASES.desktop;
  await login(page, ACCOUNTS.admin);
  // a clean start, also after an earlier run on the same stack
  expect((await page.request.post('/api/reset_lesson_mail_template', { data: { reason: c.reason } })).status()).toBe(200);
  await page.goto('/unterrichtsmails');

  const reason = page.locator('#ti_lesson_mail_reason');
  const subject = page.locator('#ti_lesson_mail_subject');
  const body = page.locator('#ti_lesson_mail_body');
  const status = page.locator('#lesson_mail_status');
  const previewSubject = page.locator('#lesson_mail_preview_subject');
  const previewBody = page.locator('#lesson_mail_preview_body');
  const save = page.locator('#bu_save_lesson_mail');

  await reason.selectOption(c.reason);
  await expect(status).toHaveText('Standardtext');
  await expect(previewSubject).toHaveText(c.subject);
  // the mock student, the example note and the admin as teacher
  await expect(previewBody).toContainText(c.sentence);
  await expect(previewBody.locator('p').last()).toContainText('Clarke');
  await expect(save).toBeDisabled();

  await page.locator('#ti_lesson_mail_preview_student').selectOption('w');
  await expect(previewBody).toContainText('Ihre Tochter Erika hat heute');

  await body.fill(NEW_BODY);
  await expect(previewBody).toContainText(`Erika Mustermann aus der Klasse 5a hat ihre Sachen vergessen (${c.note}).`);
  await expect(previewBody.locator('p')).toHaveCount(3);
  await page.locator('#ti_lesson_mail_preview_note').fill('');
  await expect(previewBody).toContainText('hat ihre Sachen vergessen.');
  await expect(status).toContainText('nicht gespeichert');

  // unknown placeholder: shown, nothing can be saved
  await subject.fill('Nachricht für {Vornam}');
  await expect(page.locator('#lesson_mail_errors')).toContainText('Den Platzhalter {Vornam} gibt es nicht.');
  await expect(save).toBeDisabled();
  // the placeholder buttons insert at the cursor
  await subject.fill('Nachricht – ');
  await subject.press('End');
  await page.locator('.bu-insert-placeholder[data-placeholder="{Vorname}"]').click();
  await expect(subject).toHaveValue('Nachricht – {Vorname}');
  await expect(page.locator('#lesson_mail_errors')).toBeHidden();
  await expect(previewSubject).toHaveText('Nachricht – Erika');

  // switching to another text with unsaved changes asks first
  await reason.selectOption('praise');
  await expect(dashboardDialog(page)).toContainText('noch nicht gespeichert');
  await dashboardDialog(page).getByRole('button', { name: 'Abbrechen' }).click();
  await expect(reason).toHaveValue(c.reason);
  await expect(body).toHaveValue(NEW_BODY);

  await save.click();
  await expect(status).toContainText('Angepasst am');
  await expect(status).not.toContainText('nicht gespeichert');

  await page.reload();
  await reason.selectOption(c.reason);
  await page.locator('#ti_lesson_mail_preview_student').selectOption('m');
  await expect(subject).toHaveValue('Nachricht – {Vorname}');
  await expect(body).toHaveValue(NEW_BODY);
  await expect(previewBody).toContainText(`Max Mustermann aus der Klasse 5a hat seine Sachen vergessen (${c.note}).`);

  // back to the default text
  await page.locator('#bu_reset_lesson_mail').click();
  await expect(dashboardDialog(page)).toContainText(c.label);
  await dashboardDialog(page).getByRole('button', { name: 'Wiederherstellen' }).click();
  await expect(status).toHaveText('Standardtext');
  await expect(subject).toHaveValue(c.defaultSubject);
  await expect(previewBody).toContainText(c.sentence);
  await expect(page.locator('#bu_reset_lesson_mail')).toBeDisabled();
});

test('Mails aus dem Unterricht: Texte ändern nur Admins', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  const data = { reason: 'praise', subject: 'Lob', body: 'Hallo' };
  expect((await page.request.post('/api/save_lesson_mail_template', { data })).status()).not.toBe(200);
  expect((await page.request.post('/api/preview_lesson_mail_template', { data })).status()).not.toBe(200);
  expect((await page.request.post('/api/reset_lesson_mail_template', { data: { reason: 'praise' } })).status()).not.toBe(200);
});

// The Otium sends the mail for a lesson it did not teach: signed by the
// sender, the text names the lesson's teacher.
test('Mails aus dem Unterricht: Vorschau einer Otium-Mail nennt Absender und Lehrkraft der Stunde', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  const response = await page.request.post('/api/preview_lesson_mail', {
    data: { email: ACCOUNTS.schueler, reason: 'disturbance_otium', details: 'Lärm', lesson_key: 'Ma_5a' },
  });
  expect(response.status()).toBe(200);
  const { subject, html } = await response.json();
  expect(subject).toBe('Störverhalten (Otium)');
  expect(html).toContain('Ihr Sohn Max zeigte heute im Fach Mathematik ein derart ausgeprägtes Störverhalten (Lärm), dass Herr Clarke ihn');
  const signature = html.split('Mit freundlichen Grüßen')[1];
  expect(signature).toContain('Torstenson');
  expect(signature).not.toContain('Clarke');
  // only for students
  expect((await page.request.post('/api/preview_lesson_mail', {
    data: { email: ACCOUNTS.teacher, reason: 'praise', details: '', lesson_key: 'Ma_5a' },
  })).status()).not.toBe(200);
});

// Opens the mail dialog of one of Clarke's lessons today (mails can only be
// sent for today's own lessons); skips the test on days without one.
async function openMailDialog(page: Page) {
  await page.goto('/');
  // the server's today (the browser here runs on UTC)
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' });
  await showDayInTimetable(page, new Date(`${today}T12:00:00`)).catch(() => {});
  const lessons = page.locator(`td.fc-timegrid-col[data-date="${today}"] .fc-event`);
  let found = false;
  for (let i = 0; i < (await lessons.count()) && !found; i++) {
    await lessons.nth(i).click();
    await expect(page.locator('#lessonModal')).toBeVisible();
    await page.waitForTimeout(500);
    found = await page.locator('#lessonModal .bu-mail').isVisible();
    if (!found) {
      await page.locator('#lessonModal').getByRole('button', { name: 'Schließen' }).click();
      await expect(page.locator('#lessonModal')).toBeHidden();
    }
  }
  test.skip(!found, 'Clarke has no lesson today (weekend or holiday)');
  await page.locator('#lessonModal .bu-mail').click();
  const modal = page.locator('#mailModal');
  await expect(modal).toBeVisible();
  return modal;
}

test('Mails aus dem Unterricht: Lehrkraft sieht die Mail vor dem Senden', async ({ page }, testInfo) => {
  await login(page, ACCOUNTS.admin);
  const modal = await openMailDialog(page);
  await modal.locator('#ti_mail_reason').selectOption('homework');
  const preview = modal.getByTestId('mail-preview');
  // folded on phones (one line, the send buttons stay close), open on
  // larger screens; the choice is remembered
  const section = modal.locator('#mail_preview_section');
  const phone = testInfo.project.name === 'mobile';
  await expect(section).toBeVisible();
  if (phone) {
    await expect(preview).toBeHidden();
    await section.locator('summary').click();
  }
  await expect(preview).toBeVisible();
  await expect(modal.locator('#mail_preview_subject')).toContainText('Fehlende Hausaufgaben im Fach');
  await modal.locator('#ti_mail_details').fill('S. 12');
  await expect(preview).toContainText('(S. 12).');
  await expect(modal.locator('#mail_preview_body p').last()).toContainText('Scott Clarke');
  // another student of the lesson
  const students = modal.locator('#ti_mail_preview_sus option');
  if ((await students.count()) > 1) {
    const second = await students.nth(1).textContent();
    await modal.locator('#ti_mail_preview_sus').selectOption({ index: 1 });
    await expect(preview).toContainText(second!.split(' ')[0]);
  }
  await modal.locator('#ti_mail_reason').selectOption('');
  await expect(section).toBeHidden();
  if (phone) {
    // opened once, it stays open
    await page.reload();
    expect(await page.evaluate(() => localStorage.getItem('mail_preview_open'))).toBe('true');
  }
});

// Sending queues the mail (the mail bot sends it 10 minutes later, it is not
// part of the test stack); until then the teacher can cancel it.
test('Mails aus dem Unterricht: Lehrkraft schickt eine Mail und bricht sie ab', async ({ page }, testInfo) => {
  // desktop and mobile run at the same time: each with a reason of its own
  const [reason, label] = testInfo.project.name === 'mobile' ? ['late', 'Verspätung'] : ['praise', 'Besonderes Lob'];
  await login(page, ACCOUNTS.admin);
  const modal = await openMailDialog(page);
  const table = modal.locator('#div_email_sus_table');
  const send = table.locator('tr').first().getByRole('button', { name: 'E-Mail senden' });
  // without a reason nothing can be sent
  await expect(send).toBeDisabled();
  await modal.locator('#ti_mail_reason').selectOption(reason);
  await expect(send).toBeEnabled();
  await modal.locator('#ti_mail_details').fill('Test');
  await send.click();
  const pending = table.locator('tr', { hasText: `»${label}«` });
  await expect(pending).toContainText('wird um');
  // one mail per reason and student
  await expect(send).toBeDisabled();
  await pending.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(pending).toHaveCount(0);
  await expect(send).toBeEnabled();
});

// Own templates: an admin adds a reason. It starts as a test (only admins see
// it, the mail goes to the sender alone), then is switched on for everyone
// and finally hidden again.
test('Mails aus dem Unterricht: eigene Vorlage anlegen, testen, freischalten, ausblenden', async ({ page, newUserPage }, testInfo) => {
  // unique per project and run: desktop and mobile share the database
  const name = `Sportzeug fehlt ${testInfo.project.name} ${Date.now()}`;
  await login(page, ACCOUNTS.admin);
  await page.goto('/unterrichtsmails');
  await page.locator('#bu_new_lesson_mail').click();
  await expect(page.locator('#lesson_mail_status')).toHaveText('Neue Vorlage – noch nicht gespeichert');
  await expect(page.locator('#ti_lesson_mail_status')).toBeDisabled();
  await expect(page.locator('#bu_reset_lesson_mail')).toBeHidden();
  // a name is needed
  await page.locator('#ti_lesson_mail_subject').fill('Sportzeug fehlt im Fach {Fach}');
  await expect(page.locator('#lesson_mail_errors')).toContainText('Der Name ist leer.');
  await expect(page.locator('#bu_save_lesson_mail')).toBeDisabled();
  await page.locator('#ti_lesson_mail_label').fill(name);
  await page.locator('#ti_lesson_mail_note_hint').fill('Turnbeutel');
  await page.locator('#ti_lesson_mail_cc_klassenleitung').check();
  await page.locator('#ti_lesson_mail_body').fill('Liebe Eltern,\n\n{Vorname} hatte heute kein Sportzeug dabei{Notiz}.\n\nViele Grüße\n{Lehrkraft}');
  await expect(page.locator('#lesson_mail_preview_body')).toContainText('Max hatte heute kein Sportzeug dabei');
  await page.locator('#bu_save_lesson_mail').click();
  await expect(page.locator('#lesson_mail_status')).toContainText('Eigene Vorlage, Test');
  const option = page.locator('#ti_lesson_mail_reason option', { hasText: name });
  await expect(option).toHaveText(`${name} (Test)`);
  const reason = (await option.getAttribute('value'))!;
  expect(reason).toMatch(/^eigen_/);

  // names are unique
  const twice = await page.request.post('/api/create_lesson_mail_template', {
    data: { label: name, color: '#204a87', sender: 'teachers', cc_klassenleitung: false, note_hint: '', subject: 'x', body: 'y' },
  });
  expect((await twice.json()).errors).toContain(`Eine Vorlage »${name}« gibt es schon.`);

  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' });
  const mail = { email: ACCOUNTS.schueler, reason, details: '', lesson_key: 'Ma_5a', lesson_offset: 0, datum: today };
  const send = async (p: Page) => p.request.post('/api/send_email', { data: mail });
  const cancel = async (p: Page, tag: string) =>
    expect((await p.request.post('/api/cancel_email', { data: { tag } })).status()).toBe(200);

  // in the test state: an admin's mail is marked as a test …
  let response = await send(page);
  expect(response.status()).toBe(200);
  let entry = (await response.json()).entry;
  expect(entry.test).toBe(true);
  await cancel(page, entry.tag);
  // … other teachers neither see nor send it
  const teacher = await newUserPage();
  await login(teacher, ACCOUNTS.teacher);
  expect((await send(teacher)).status()).not.toBe(200);
  expect((await teacher.request.post('/api/preview_lesson_mail', {
    data: { email: ACCOUNTS.schueler, reason, details: '', lesson_key: 'Ma_5a' },
  })).status()).not.toBe(200);
  await teacher.goto('/');
  await expect(teacher.locator(`#ti_mail_reason option[value="${reason}"]`)).toHaveCount(0);

  // switched on: for everyone, real mails
  await page.locator('#ti_lesson_mail_status').selectOption('active');
  await page.locator('#bu_save_lesson_mail').click();
  await expect(dashboardDialog(page)).toContainText('Ab jetzt sehen alle Lehrkräfte');
  await dashboardDialog(page).getByRole('button', { name: 'Freischalten' }).click();
  await expect(page.locator('#lesson_mail_status')).toContainText('Eigene Vorlage, Aktiv');
  await expect(option).toHaveText(name);
  response = await send(page);
  entry = (await response.json()).entry;
  expect(entry.test).toBe(false);
  await cancel(page, entry.tag);
  response = await send(teacher);
  expect(response.status()).toBe(200);
  await cancel(teacher, (await response.json()).entry.tag);
  await teacher.goto('/');
  await expect(teacher.locator(`#ti_mail_reason option[value="${reason}"]`)).toHaveText(name);
  await expect(teacher.locator(`#ti_mail_reason option[value="${reason}"]`)).toHaveAttribute('data-note-hint', 'Turnbeutel');

  // the rules are in the database: sent by the Otium, teachers see it greyed out
  await page.locator('#ti_lesson_mail_sender').selectOption('otium');
  await page.locator('#bu_save_lesson_mail').click();
  await expect(page.locator('#bu_save_lesson_mail')).toBeDisabled();
  await expect(page.locator('#lesson_mail_status')).not.toContainText('nicht gespeichert');
  expect((await send(teacher)).status()).not.toBe(200);
  await teacher.goto('/');
  await expect(teacher.locator(`#ti_mail_reason option[value="${reason}"]`)).toBeDisabled();
  await expect(teacher.locator(`#ti_mail_reason option[value="${reason}"]`)).toHaveText(`${name} – schickt jetzt das Otium`);
  await page.reload();
  await page.locator('#ti_lesson_mail_reason').selectOption(reason);
  await expect(page.locator('#ti_lesson_mail_sender')).toHaveValue('otium');
  await expect(page.locator('#ti_lesson_mail_cc_klassenleitung')).toBeChecked();

  // hidden: nobody sends it any more
  await page.locator('#ti_lesson_mail_status').selectOption('hidden');
  await page.locator('#bu_save_lesson_mail').click();
  await expect(option).toHaveText(`${name} (Ausgeblendet)`);
  expect((await send(page)).status()).not.toBe(200);
  expect((await send(teacher)).status()).not.toBe(200);
});

// The mail dialog in the timetable: an admin sends a test mail, marked as such.
test('Mails aus dem Unterricht: Testvorlage im Mail-Dialog', async ({ page }, testInfo) => {
  const name = `Probe ${testInfo.project.name} ${Date.now()}`;
  await login(page, ACCOUNTS.admin);
  const created = await page.request.post('/api/create_lesson_mail_template', {
    data: { label: name, color: '#204a87', sender: 'teachers', cc_klassenleitung: false, note_hint: '', subject: 'Probe im Fach {Fach}', body: 'Liebe Eltern,\n\n{Vorname} war heute da.\n\n{Lehrkraft}' },
  });
  const reason = (await created.json()).reason;
  expect(reason).toMatch(/^eigen_/);
  const modal = await openMailDialog(page);
  const notice = modal.getByTestId('mail-test-notice');
  await expect(notice).toBeHidden();
  await modal.locator('#ti_mail_reason').selectOption(reason);
  await expect(notice).toBeVisible();
  await expect(modal.locator('#mail_preview_subject')).toContainText('Probe im Fach');
  const send = modal.locator('#div_email_sus_table tr').first().getByRole('button', { name: 'E-Mail senden' });
  await send.click();
  const pending = modal.locator('#div_email_sus_table tr', { hasText: `»${name}«` });
  await expect(pending).toContainText('Test, nur an dich');
  await pending.getByRole('button', { name: 'Abbrechen' }).click();
  await expect(pending).toHaveCount(0);
  await modal.locator('#ti_mail_reason').selectOption('praise');
  await expect(notice).toBeHidden();
  // tidy up: out of the timetable
  const save = await page.request.post('/api/save_lesson_mail_template', {
    data: { reason, label: name, color: '#204a87', status: 'hidden', sender: 'teachers', cc_klassenleitung: false, note_hint: '', subject: 'Probe', body: 'Probe' },
  });
  expect(save.status()).toBe(200);
});

test('Mails aus dem Unterricht: eigene Vorlagen legen nur Admins an', async ({ page }) => {
  await login(page, ACCOUNTS.teacher);
  expect((await page.request.post('/api/create_lesson_mail_template', {
    data: { label: 'Darf nicht', color: '#204a87', sender: 'teachers', cc_klassenleitung: false, note_hint: '', subject: 'x', body: 'y' },
  })).status()).not.toBe(200);
  // unknown reasons are refused when sending
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' });
  expect((await page.request.post('/api/send_email', {
    data: { email: ACCOUNTS.schueler, reason: 'gibt_es_nicht', details: '', lesson_key: 'Ma_5a', lesson_offset: 0, datum: today },
  })).status()).not.toBe(200);
});
