import { test, expect, login, ACCOUNTS, displayedSchoolWeek, isoDate } from './fixtures';
import type { CDPSession, Page } from '@playwright/test';

// Neues Design: Terminfinder (/terminfinder, include/terminfinder.rb,
// preview/terminfinder.js). A teacher adds people, classes or groups and
// sees per day when all of them are free for the chosen duration; only
// lessons count, the server answers with busy times only. A time becomes a
// new event on /events with date, time and participants. Only in the new
// design for now: the old design has neither the page nor the menu entry.
// The lessons are those of the example data in the shown week, so the
// checks compare the suggestions with the server's busy times.

const minutes = (s: string) => {
  const [h, m] = s.split(':').map(Number);
  return h * 60 + m;
};

type Answer = { people: Record<string, Record<string, [string, string][]>>; missing: string[] };

// every suggestion for everyone free: long enough, and nobody busy in it
async function checkSlots(page: Page, answer: Answer, duration: number) {
  const slots = await page.locator('.pv-tf-day').evaluateAll((days) =>
    days.flatMap((d) => Array.from(d.querySelectorAll('.pv-tf-slot:not(.pv-tf-slot-near) .pv-tf-slot-time'))
      .map((s) => ({ date: (d as HTMLElement).dataset.date!, text: s.textContent! }))));
  for (const slot of slots) {
    const m = slot.text.match(/^(\d{1,2}:\d{2}) bis (\d{1,2}:\d{2})$/);
    expect(m, slot.text).not.toBeNull();
    const from = minutes(m![1]), to = minutes(m![2]);
    expect(to - from, slot.text).toBeGreaterThanOrEqual(duration);
    for (const [email, days] of Object.entries(answer.people)) {
      for (const [a, b] of days[slot.date] || []) {
        expect(minutes(b) <= from || minutes(a) >= to, `${email} busy ${a}–${b} in ${slot.date} ${slot.text}`).toBe(true);
      }
    }
  }
  return slots.length;
}

async function add(page: Page, text: string) {
  const search = page.locator('#ti_tf_search');
  await search.fill(text);
  await expect(page.locator('.pv-tf-result').first()).toBeVisible();
  await search.press('Enter');
  await expect(search).toHaveValue('');
}

test('Neues Design: Terminfinder findet gemeinsame freie Zeiten', async ({ page }) => {
  test.setTimeout(90_000);
  // Monday morning of the shown week: no day is over yet
  const monday = displayedSchoolWeek()[0];
  monday.setHours(7, 0, 0, 0);
  await page.clock.install({ time: monday });
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/terminfinder');
    await expect(page.locator('.pv-tf h2')).toHaveText('Terminfinder');
    // oneself is there from the start
    await expect(page.locator('.pv-tf-chip')).toHaveText(['Scott Clarke (du)']);
    await expect(page.locator('.pv-tf-day')).toHaveCount(5);
    await expect(page.locator('.pv-tf-day').first()).toHaveAttribute('data-date', isoDate(displayedSchoolWeek()[0]));
    await expect(page.locator('#bu_tf_today')).toBeDisabled();

    // a teacher: found by part of the name, as a teacher
    await page.locator('#ti_tf_search').fill('torst');
    await expect(page.locator('.pv-tf-result').first()).toContainText('Torstenson');
    await expect(page.locator('.pv-tf-result').first().locator('.pv-tf-result-sub')).toHaveText('Lehrkraft');
    await page.locator('#ti_tf_search').press('Enter');
    // a class: one chip with its size, its students counted one by one
    const answered = page.waitForResponse((r) => r.url().endsWith('/api/terminfinder_week') && r.request().postDataJSON().emails.length > 2);
    await add(page, 'klasse 5a');
    const response = await answered;
    expect(response.status()).toBe(200);
    const answer = (await response.json()) as Answer & Record<string, unknown>;
    await expect(page.locator('.pv-tf-chip')).toHaveCount(3);
    await expect(page.locator('.pv-tf-chip').nth(2)).toHaveText(/^Klasse 5a \(\d+\)$/);
    await expect(page.locator('.pv-tf-facts')).toHaveText(/^\d+ Personen/);

    // busy times only: dates with [from, to], nothing about the lessons
    expect(Object.keys(answer).sort()).toEqual(['days', 'missing', 'people', 'week']);
    for (const days of Object.values(answer.people)) {
      for (const [date, list] of Object.entries(days)) {
        expect(date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
        for (const pair of list) {
          expect(pair).toHaveLength(2);
          pair.forEach((t) => expect(t).toMatch(/^\d{2}:\d{2}$/));
        }
      }
    }
    expect(Object.keys(answer.people).length).toBeGreaterThan(2);

    // the suggestions fit the busy times, for one hour and for two
    await expect(page.locator('.pv-tf-duration[aria-checked="true"]')).toHaveText('1 Std.');
    expect(await checkSlots(page, answer, 60)).toBeGreaterThan(0);
    await page.locator('.pv-tf-duration', { hasText: '2 Std.' }).click();
    await expect(page.locator('.pv-tf-duration[aria-checked="true"]')).toHaveText('2 Std.');
    await checkSlots(page, answer, 120);
    await page.locator('.pv-tf-duration', { hasText: '1 Std.' }).click();

    // removing a chip asks again without that person
    await page.locator('.pv-tf-chip').nth(1).getByRole('button', { name: /entfernen$/ }).click();
    await expect(page.locator('.pv-tf-chip')).toHaveCount(2);

    // the next week and back
    const label = await page.locator('.pv-tf-week-label').textContent();
    await page.locator('#bu_tf_next').click();
    await expect(page.locator('.pv-tf-week-label')).not.toHaveText(label!);
    await expect(page.locator('#bu_tf_today')).toBeEnabled();
    await page.locator('#bu_tf_today').click();
    await expect(page.locator('.pv-tf-week-label')).toHaveText(label!);

    // a time: the dialog, then »Termin anlegen« fills a new event
    const slot = page.locator('.pv-tf-slot:not(.pv-tf-slot-near)').first();
    const date = await slot.evaluate((s) => (s.closest('.pv-tf-day') as HTMLElement).dataset.date!);
    const from = (await slot.locator('.pv-tf-slot-time').textContent())!.split(' bis ')[0];
    await slot.click();
    await expect(page.locator('#tfSlotModal')).toBeVisible();
    await expect(page.locator('#tfSlotModal .pv-tf-slot-who')).toContainText(`Frei von ${from} bis`);
    await expect(page.locator('#ti_tf_slot_start option').first()).toHaveText(`${from} Uhr`);
    await page.locator('#bu_tf_create_event').click();
    await expect(page).toHaveURL(/\/events$/);
    await expect(page.locator('#composeModal')).toBeVisible();
    await expect(page.locator('#ti_date')).toHaveValue(date);
    await expect(page.locator('#ti_start_time')).toHaveValue(from.padStart(5, '0'));
    await expect(page.locator('#ti_end_time')).toHaveValue(`${String(Math.floor(minutes(from) / 60) + 1).padStart(2, '0')}:${from.split(':')[1]}`);
    await expect(page.locator('#composeModal .recipients_list .recipient')).toHaveText([/^Klasse 5a/]);
    // only once: reloading /events opens no event
    expect(await page.evaluate(() => sessionStorage.getItem('pv_terminfinder'))).toBeNull();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

async function drag(client: CDPSession, page: Page, from: { x: number; y: number }, to: { x: number; y: number }, ms: number) {
  const steps = 10;
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [from] });
  for (let i = 1; i <= steps; i++) {
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [{ x: from.x + ((to.x - from.x) * i) / steps, y: from.y + ((to.y - from.y) * i) / steps }],
    });
    await page.waitForTimeout(ms / steps);
  }
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

test('Neues Design: Terminfinder am Handy Woche für Woche wischbar', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'touch only on phones');
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/terminfinder');
    await expect(page.locator('.pv-tf-chip')).toHaveCount(1);
    const label = page.locator('.pv-tf-week-label');
    const first = (await label.textContent())!;
    // the durations in one row
    const tops = await page.locator('.pv-tf-duration').evaluateAll((bs) => bs.map((b) => Math.round(b.getBoundingClientRect().top)));
    expect(new Set(tops).size).toBe(1);
    const box = (await page.locator('.pv-tf-days').boundingBox())!;
    const y = box.y + 60;
    const right = { x: box.x + box.width - 30, y };
    const left = { x: box.x + 30, y };
    const client = await page.context().newCDPSession(page);
    await drag(client, page, right, left, 200);
    await expect(label).not.toHaveText(first);
    await expect(page.locator('#bu_tf_today')).toBeEnabled();
    await drag(client, page, left, right, 200);
    await expect(label).toHaveText(first);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Terminfinder: nur im neuen Design und nur für Lehrkräfte', async ({ page, browser }) => {
  await login(page, ACCOUNTS.admin);
  // old design: no menu entry, the page leads to the start page
  await page.goto('/');
  await expect(page.locator('a[href="/terminfinder"]')).toHaveCount(0);
  await page.goto('/terminfinder');
  await expect(page).toHaveURL(/\/$/);
  // the new design has the entry
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/');
    await expect(page.locator('a.pv-nav-entry[href="/terminfinder"]').first()).toBeAttached();
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
  // students may not ask
  const context = await browser.newContext();
  const student = await context.newPage();
  await login(student, ACCOUNTS.schueler);
  const r = await student.request.post('/api/terminfinder_week', { data: { week: '2026-47', emails: [ACCOUNTS.admin] } });
  expect(r.status()).not.toBe(200);
  await context.close();
});
