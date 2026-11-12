import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page, CDPSession } from '@playwright/test';

// Timetable on phones (day view): swiping left/right goes to the next /
// previous school day (timetable.html, install_calendar_day_swipe). Real
// touch events through the DevTools protocol, as a finger would make them.

async function currentDay(page: Page) {
  return page.evaluate(() => (window as any).moment((window as any).calendar.getDate()).format('YYYY-MM-DD'));
}

async function schoolDay(page: Page, from: string, direction: 1 | -1) {
  return page.evaluate(([from, direction]) => {
    const d = (window as any).moment(from as string);
    do { d.add(direction as number, 'days'); } while (d.day() === 0 || d.day() === 6);
    return d.format('YYYY-MM-DD');
  }, [from, direction]);
}

async function drag(client: CDPSession, page: Page, from: { x: number; y: number }, to: { x: number; y: number }, ms: number) {
  const steps = 10;
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: from.x, y: from.y }] });
  for (let i = 1; i <= steps; i++) {
    await client.send('Input.dispatchTouchEvent', {
      type: 'touchMove',
      touchPoints: [{ x: from.x + ((to.x - from.x) * i) / steps, y: from.y + ((to.y - from.y) * i) / steps }],
    });
    await page.waitForTimeout(ms / steps);
  }
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}

test('Stundenplan: Tage wischen auf dem Handy', async ({ page }, testInfo) => {
  test.skip(testInfo.project.name !== 'mobile', 'day view and touch only on phones');
  await login(page, ACCOUNTS.schueler);
  const weeks = new Set<string>();
  page.on('request', (request) => {
    const m = request.url().match(/\/gen\/w\/[^/]+\/(\d{4}-\d{2})\.json\.gz/);
    if (m) weeks.add(m[1]);
  });
  await page.goto('/');
  await page.waitForFunction(() => (window as any).calendar && (window as any).calendar.view.type === 'timeGridDay');
  // the calendar on screen (cards above it, e.g. polls, push it down), touch
  // points measured fresh before each gesture
  let box: { x: number; y: number; width: number; height: number };
  let y = 0;
  let left = { x: 0, y: 0 };
  let right = { x: 0, y: 0 };
  const onScreen = async () => {
    await page.locator('#calendar .fc-view-harness').evaluate((el) => el.scrollIntoView({ block: 'start' }));
    await page.waitForTimeout(200);
    box = (await page.locator('#calendar .fc-view-harness').boundingBox())!;
    y = box.y + 200;
    left = { x: box.x + box.width * 0.85, y };
    right = { x: box.x + box.width * 0.15, y };
  };
  await onScreen();
  const client = await page.context().newCDPSession(page);

  const today = await currentDay(page);
  const tomorrow = await schoolDay(page, today, 1);
  // the weeks before and after are loaded in advance
  await expect.poll(() => weeks.size).toBe(3);

  // while the finger is still down, the next day is already coming in
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [left] });
  // slowly and less than a quarter of the width: a look, not a swipe
  for (let i = 1; i <= 4; i++) {
    await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: left.x - i * 20, y }] });
    await page.waitForTimeout(100);
  }
  const neighbour = page.locator('.calendar-swipe-neighbour');
  await expect(neighbour).toHaveCount(1);
  await expect(neighbour.locator(`.fc-col-header-cell[data-date="${tomorrow}"]`)).toHaveCount(1);
  await expect(neighbour).toBeInViewport();
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  // not far enough: back to today, the neighbour is gone
  await expect(neighbour).toHaveCount(0);
  expect(await currentDay(page)).toBe(today);

  // swipe to the left: the next school day
  await drag(client, page, left, right, 200);
  await expect.poll(() => currentDay(page)).toBe(tomorrow);
  await expect(neighbour).toHaveCount(0);
  // the page did not get wider than the screen, the menu button is still there
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expect(page.locator('.navbar-toggler')).toBeInViewport({ ratio: 1 });
  // and back
  await drag(client, page, right, left, 200);
  await expect.poll(() => currentDay(page)).toBe(today);

  // quick swipes one after the other all count
  await drag(client, page, left, right, 150);
  await page.waitForTimeout(250);
  await drag(client, page, left, right, 150);
  await expect.poll(() => currentDay(page)).toBe(await schoolDay(page, tomorrow, 1));
  await page.waitForTimeout(250);
  await drag(client, page, right, left, 150);
  await page.waitForTimeout(250);
  await drag(client, page, right, left, 150);
  await expect.poll(() => currentDay(page)).toBe(today);
  await expect(neighbour).toHaveCount(0);

  // scrolling up and down does not change the day
  await onScreen();
  await drag(client, page, { x: box.x + box.width / 2, y }, { x: box.x + box.width / 2 + 15, y: y - 150 }, 200);
  await page.waitForTimeout(500);
  expect(await currentDay(page)).toBe(today);
  // a short, slow sideways move snaps back
  await onScreen();
  await drag(client, page, { x: box.x + box.width / 2, y }, { x: box.x + box.width / 2 - 40, y }, 800);
  await page.waitForTimeout(500);
  expect(await currentDay(page)).toBe(today);
  // across the weekend the neighbour comes from the preloaded week: from next
  // week's Monday, a look back at this week's Friday (which has lessons in
  // the example data)
  const friday = await page.evaluate((d) => (window as any).moment(d).day(5).format('YYYY-MM-DD'), today);
  const monday = await schoolDay(page, friday, 1);
  await page.evaluate((d) => (window as any).calendar.gotoDate(d), monday);
  await expect.poll(() => currentDay(page)).toBe(monday);
  await page.waitForTimeout(300);
  await onScreen();
  await client.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [right] });
  for (let i = 1; i <= 4; i++) {
    await client.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: right.x + i * 20, y }] });
    await page.waitForTimeout(100);
  }
  await expect(neighbour.locator(`.fc-col-header-cell[data-date="${friday}"]`)).toHaveCount(1);
  expect(await neighbour.locator('.fc-event').count()).toBeGreaterThan(0);
  await client.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  await expect(neighbour).toHaveCount(0);
  await page.evaluate((d) => (window as any).calendar.gotoDate(d), today);
  await expect(page.locator('.calendar-swipe-ghost')).toHaveCount(0);

  // and the day is back in place
  await expect.poll(async () => page.locator('#calendar .fc-view-harness').evaluate((el) => (el as HTMLElement).style.transform)).toBe('');
});
