import { test, expect, login, apiLogin, ACCOUNTS } from './fixtures';
import { request as playwrightRequest, type Page, type APIRequestContext } from '@playwright/test';

// Neues Design (Vorschau), start page: "Zu erledigen" – open polls and the
// other tasks of the start page in one place, never as a column of their own
// beside the timetable (preview/start.js, include/start_todo.rb) – with a
// badge on "Stundenplan" / "Heute"; and the Datentresor hotline as a bar on
// every page for admins with the hotline role (preview/hotline.js). The
// admin (also a teacher, hotline role in test/prepare_example_data.rb) is the
// participant; the preview is for admins only on the test stack.

// times as the server sees them
const fmt = (d: Date) => [d.toLocaleDateString('sv-SE', { timeZone: 'Europe/Berlin' }),
  d.toLocaleTimeString('de-DE', { timeZone: 'Europe/Berlin', hour: '2-digit', minute: '2-digit' })];

// a poll run for the admin, open from a minute ago
async function pollFor(request: APIRequestContext, title: string, minutes: number) {
  const saved = await request.post('/api/save_poll', { data: { title, items: '[]' } });
  expect(saved.status()).toBe(200);
  const pid = (await saved.json()).poll.pid as string;
  const [startDate, startTime] = fmt(new Date(Date.now() - 60_000));
  const [endDate, endTime] = fmt(new Date(Date.now() + minutes * 60_000));
  const run = await request.post('/api/save_poll_run', { data: {
    pid, anonymous: 'false', visible: 'yes', recipients: [ACCOUNTS.admin],
    start_date: startDate, start_time: startTime, end_date: endDate, end_time: endTime } });
  expect(run.status()).toBe(200);
  return { pid, prid: (await run.json()).poll_run.prid as string };
}

// the open tasks as the start page counts them
async function openCount(request: APIRequestContext) {
  const r = await request.post('/api/refresh_start_page', { data: {} });
  return (await r.json()).todo.count as number;
}

// on phones the list may be folded (more than two rows)
async function unfold(page: Page) {
  const fold = page.locator('#pv_todo .pv-todo-fold');
  if (await fold.count() > 0 && (await fold.getAttribute('aria-expanded')) === 'false') await fold.click();
}

test('Neues Design: »Zu erledigen« zeigt Umfragen am richtigen Ort, »Teilnehmen« öffnet sie, der Zähler stimmt', async ({ page }, testInfo) => {
  const mobile = testInfo.project.name === 'mobile';
  const title = `Zu erledigen ${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const pids: string[] = [];
  try {
    const { pid, prid } = await pollFor(page.request, title, 3 * 24 * 60);
    pids.push(pid);
    await page.goto('/');
    await expect(page.locator('body')).toHaveClass(/ui-preview/);
    const todo = page.locator('#pv_todo');
    await expect(todo).toBeVisible();
    // the place: the column beside the week (desktop), the top of the day (phone)
    if (mobile) {
      await expect(page.locator('#pv_agenda > #pv_todo')).toHaveCount(1);
      expect(await page.locator('#pv_agenda').evaluate((a) => a.firstElementChild?.id)).toBe('pv_todo');
    } else {
      await expect(page.locator('#pv_side > #pv_todo')).toHaveCount(1);
      expect(await page.locator('#pv_side').evaluate((a) => a.firstElementChild?.id)).toBe('pv_todo');
      await expect(page.locator('#pv_side h3', { hasText: 'Geändert diese Woche' })).toBeVisible();
    }
    // no boxes of today's design, no column of their own
    await expect(page.locator('.hint_poll')).toHaveCount(0);
    await expect(page.locator('#start_page_panels > *')).toHaveCount(0);
    await unfold(page);
    const row = todo.locator('.pv-todo-row', { hasText: title });
    await expect(row).toBeVisible();
    await expect(row.locator('.pv-todo-facts')).toContainText(/Herr Clarke, bis \S+ \d{1,2}:\d\d/);
    await expect(row.locator('.pv-todo-avatar')).toBeVisible();

    // the timetable keeps its width without the tasks
    const box = mobile ? page.locator('#pv_agenda') : page.locator('#calendar');
    const width = (await box.boundingBox())!.width;
    await page.evaluate(() => {
      (window as any).pv_todo.update({ items: [], count: 0 });
      (window as any).render_preview_week_head();
    });
    await expect(todo).toHaveCount(0);
    expect(Math.abs((await box.boundingBox())!.width - width)).toBeLessThan(2);
    await page.reload();
    await unfold(page);

    // »Teilnehmen« opens the poll
    await todo.locator('.pv-todo-row', { hasText: title }).getByRole('button', { name: 'Teilnehmen' }).click();
    await expect(page.locator('#pollResponseModal .poll-title')).toHaveText(title);
    // (on phones the sheet has no visible »Schließen«: it is pulled down)
    await page.locator('#bu_close_poll_response_modal').evaluate((b: HTMLElement) => b.click());
    await expect(page.locator('#pollResponseModal')).toBeHidden();

    // the badge: what is open, also on other pages
    const count = await openCount(page.request);
    expect(count).toBeGreaterThan(0);
    await page.goto('/polls');
    const badge = mobile ? page.locator(".pv-tabbar a.pv-tab[href='/'] .pv-badge")
      : page.locator(".navbar .nav-link[href='/'] .pv-todo-badge");
    await expect(badge).toBeVisible();
    await expect(badge).toContainText(String(count));
    // answered: still listed (it may change), no longer counted
    expect((await page.request.post('/api/submit_poll_run', { data: { prid, response: '{}' } })).status()).toBe(200);
    expect(await openCount(page.request)).toBe(count - 1);
    await page.goto('/');
    await unfold(page);
    const answered = todo.locator('.pv-todo-row', { hasText: title });
    await expect(answered).toContainText('beantwortet');
    await expect(answered.getByRole('button', { name: 'Ändern' })).toBeVisible();
    if (count - 1 > 0) await expect(badge).toContainText(String(count - 1));
    else await expect(page.locator(".navbar .nav-link[href='/'] .pv-todo-badge, .pv-tabbar a.pv-tab[href='/'] .pv-badge").filter({ visible: true })).toHaveCount(0);
  } finally {
    for (const pid of pids) await page.request.post('/api/delete_poll', { data: { pid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

// Everything hidden: no box and no heading, only a quiet pill to show the
// hidden polls again
test('Neues Design: nur Ausgeblendetes zeigt eine leise Zeile statt der Box', async ({ page }, testInfo) => {
  const stamp = `${testInfo.project.name} ${Date.now().toString(36)}`;
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  let pid = '';
  try {
    const run = await pollFor(page.request, `Leise ${stamp}`, 24 * 60);
    pid = run.pid;
    expect((await page.request.post('/api/hide_poll_run', { data: { prid: run.prid } })).status()).toBe(200);
    await page.goto('/');
    const todo = page.locator('#pv_todo');
    await expect(todo).toBeVisible();
    // only the hidden poll (whatever else the account has open)
    await page.evaluate(() => {
      const w = window as any;
      const items = w.pv_todo_data.items.filter((i: { hidden?: boolean }) => i.hidden);
      w.pv_todo.update({ items, count: items.length });
    });
    const pill = todo.getByRole('button', { name: /^\d+ ausgeblendete Umfragen? anzeigen$/ });
    await expect(pill).toBeVisible();
    await expect(pill.locator('i.ti.ti-eye')).toBeVisible();
    await expect(todo).toHaveClass(/pv-todo-quiet/);
    await expect(todo).not.toHaveClass(/pv-side-box/);
    await expect(todo.locator('.pv-todo-head, .pv-todo-fold')).toHaveCount(0);
    // small: about one line high
    expect((await todo.boundingBox())!.height).toBeLessThan(40);
    await pill.click();
    await expect(todo.locator('.pv-todo-row', { hasText: `Leise ${stamp}` })).toContainText('ausgeblendet');
  } finally {
    if (pid) await page.request.post('/api/delete_poll', { data: { pid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: mehr als zwei Aufgaben falten sich am Handy und Tablet zu einer Zeile', async ({ page }, testInfo) => {
  const mobile = testInfo.project.name === 'mobile';
  const stamp = `${testInfo.project.name} ${Date.now().toString(36)}`;
  // desktop project: a tablet (the tasks above the week)
  if (!mobile) await page.setViewportSize({ width: 820, height: 1100 });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  const runs: { pid: string, prid: string }[] = [];
  try {
    for (const n of [1, 2, 3, 4]) runs.push(await pollFor(page.request, `Falten ${n} ${stamp}`, 24 * 60 + n));
    // the fourth is hidden: not counted, behind a quiet line
    expect((await page.request.post('/api/hide_poll_run', { data: { prid: runs[3].prid } })).status()).toBe(200);
    const open = await openCount(page.request);
    await page.goto('/');
    const todo = page.locator('#pv_todo');
    await expect(todo).toBeVisible();
    await expect(page.locator(mobile ? '#pv_agenda > #pv_todo' : '#pv_week_head + #pv_todo')).toHaveCount(1);
    const fold = todo.locator('.pv-todo-fold');
    await expect(fold).toBeVisible();
    await expect(fold).toHaveAttribute('aria-expanded', 'false');
    await expect(fold).toContainText(`Zu erledigen (${open})`);
    await expect(fold.locator('i.ti.ti-chevron-down')).toBeVisible();
    await expect(todo.locator('.pv-todo-row').first()).toBeHidden();
    await fold.click();
    await expect(fold).toHaveAttribute('aria-expanded', 'true');
    for (const n of [1, 2, 3]) await expect(todo.locator('.pv-todo-row', { hasText: `Falten ${n} ${stamp}` })).toBeVisible();
    await expect(todo.locator('.pv-todo-row', { hasText: `Falten 4 ${stamp}` })).toHaveCount(0);
    await todo.getByRole('button', { name: /ausgeblendete Umfragen? anzeigen/ }).click();
    const hidden = todo.locator('.pv-todo-row', { hasText: `Falten 4 ${stamp}` });
    await expect(hidden).toBeVisible();
    await expect(hidden).toContainText('ausgeblendet');
    // stays open when the page draws the day again (every minute)
    await page.evaluate(() => (window as any).render_preview_agenda());
    await expect(todo.locator('.pv-todo-fold')).toHaveAttribute('aria-expanded', 'true');
    // the countdown close to the end
    await page.evaluate(() => {
      const items = (window as any).pv_todo_data.items.slice();
      const end = new Date(Date.now() + 50 * 60_000);
      const iso = `${end.getFullYear()}-${String(end.getMonth() + 1).padStart(2, '0')}-${String(end.getDate()).padStart(2, '0')}T${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}:00`;
      items.unshift({ kind: 'deadline', key: 'noteneingabe', end: iso });
      (window as any).pv_todo.update({ items, count: items.length });
    });
    await expect(todo.locator('.pv-todo-row', { hasText: 'Noteneingabe im Datentresor' }).locator('.pv-todo-soon')).toHaveText(/^noch \d+ min$/);
  } finally {
    for (const { pid } of runs) await page.request.post('/api/delete_poll', { data: { pid } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: die Datentresor-Hotline steht als Leiste auf jeder Seite und führt zum Dialog', async ({ page, newUserPage, baseURL }) => {
  // a teacher asks for an ad-hoc login in the Datentresor
  const teacher = await playwrightRequest.newContext({ baseURL });
  await apiLogin(teacher, ACCOUNTS.teacher);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    expect((await teacher.post('/api/create_ad_hoc_2fa_request', { data: {} })).status()).toBe(200);
    // on another page: the bar, with the name and the waiting time
    await page.goto('/polls');
    const bar = page.locator('#pv_hotline');
    await expect(bar).toBeVisible();
    const row = bar.locator('.pv-hotline-row', { hasText: 'Torsten' });
    await expect(row).toContainText('Datentresor-Hotline');
    await expect(row.locator('.pv-hotline-wait')).toHaveText(/^wartet seit (eben|\d+ min)$/);
    await expect(row.locator('i.ti.ti-phone')).toBeVisible();
    // the bar stays in view while the page scrolls
    await page.evaluate(() => window.scrollTo(0, 400));
    expect((await bar.boundingBox())!.y).toBeLessThan(60);
    // »Freigeben …« leads to the start page and opens the dialog there
    await row.getByRole('link', { name: /freigeben/ }).click();
    await page.waitForURL((url) => url.pathname === '/');
    const dialog = page.locator('#adHoc2FaRequestModal');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('#ad_hoc_login_email_here')).toHaveText(ACCOUNTS.teacher);
    await expect(dialog).toContainText('Du kannst nun den Zugang');
    await expect(dialog.locator('#bu_perform_ad_hoc_signin')).toBeVisible();
    await dialog.getByRole('button', { name: 'Anmeldung ablehnen' }).click();
    await expect(dialog).toBeHidden();
    // on the start page the bar opens it directly
    await page.locator('#pv_hotline .pv-hotline-row', { hasText: 'Torsten' }).getByRole('button', { name: /freigeben/ }).click();
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('#ad_hoc_login_email_here')).toHaveText(ACCOUNTS.teacher);
    await dialog.getByRole('button', { name: 'Anmeldung ablehnen' }).click();
    await expect(dialog).toBeHidden();
    // the old panel is not drawn in the new design
    await expect(page.locator('.side-panel .bu_open_ad_hoc_2fa_request')).toHaveCount(0);

    // not for others: a teacher who tries the new design
    const other = await newUserPage();
    await login(other, ACCOUNTS.teacher);
    await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'on' } });
    try {
      await other.goto('/polls');
      await expect(other.locator('body')).toHaveClass(/ui-preview/);
      await expect(other.locator('#pv_hotline')).toHaveCount(0);
      expect((await other.request.post('/api/hotline_requests', { data: {} })).status()).not.toBe(200);
    } finally {
      await page.request.post('/api/set_ui_preview_tester', { data: { email: ACCOUNTS.teacher, mode: 'off' } });
    }

    // handled (here: withdrawn): the bar goes at the next look
    await page.goto('/polls');
    await expect(page.locator('#pv_hotline')).toBeVisible();
    expect((await teacher.post('/api/clear_ad_hoc_2fa_request', { data: {} })).status()).toBe(200);
    await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
    await expect(page.locator('#pv_hotline')).toBeHidden();
    // and a link to a request that is over says so
    await page.goto('/#hotline=' + encodeURIComponent(ACCOUNTS.teacher));
    await expect(page.locator('#__template_modal')).toContainText('schon erledigt oder abgelaufen');
  } finally {
    await teacher.post('/api/clear_ad_hoc_2fa_request', { data: {} });
    await teacher.dispose();
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: im bisherigen Design bleibt die Startseite, wie sie war', async ({ page, baseURL }, testInfo) => {
  const title = `Bisher ${testInfo.project.name} ${Date.now().toString(36)}`;
  const teacher = await playwrightRequest.newContext({ baseURL });
  await apiLogin(teacher, ACCOUNTS.teacher);
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const { pid } = await pollFor(page.request, title, 24 * 60);
  try {
    expect((await teacher.post('/api/create_ad_hoc_2fa_request', { data: {} })).status()).toBe(200);
    await page.goto('/');
    await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
    // the boxes in their column, with the texts as before
    const hint = page.locator('.side-panel .hint_poll', { hasText: title });
    await expect(hint).toBeVisible();
    await expect(hint).toContainText('hat Sie zu einer Umfrage eingeladen');
    await expect(hint.locator('.bu-launch-poll')).toContainText('Zur Umfrage');
    await expect(page.locator('.side-panel .bu_open_ad_hoc_2fa_request', { hasText: 'Torsten' })).toBeVisible();
    await expect(page.locator('#adHoc2FaRequestModal')).toContainText('Sie können nun den Zugang');
    // nothing of the new design
    await expect(page.locator('#pv_todo, #pv_hotline, .pv-todo-badge, .pv-badge')).toHaveCount(0);
    expect(await page.evaluate(() => typeof (window as any).pv_todo)).toBe('undefined');
    await page.goto('/polls');
    await expect(page.locator('#pv_hotline, .pv-todo-badge')).toHaveCount(0);
    await expect(page.locator(".navbar .nav-link[href='/']").first()).toHaveText('Stundenplan');
  } finally {
    await teacher.post('/api/clear_ad_hoc_2fa_request', { data: {} });
    await teacher.dispose();
    await page.request.post('/api/delete_poll', { data: { pid } });
  }
});
