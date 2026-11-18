import { test, expect, request as playwrightRequest, APIRequestContext } from '@playwright/test';
import { ACCOUNTS, ROLE_ACCOUNTS, apiLogin } from './fixtures';

// Neues Design: read-only archives for long lists (doc/Gestaltung.md, 6a).
// /api/get_events_archive returns exactly what /events shows its organizer
// for a school year – nobody else's events; /api/get_news with a year gives
// that year's part of the full list, without a year it answers as always.

async function createEvent(request: APIRequestContext, title: string, date: string) {
  const r = await request.post('/api/save_event', {
    data: { title, jitsi: 'no', date, start_time: '09:00', end_time: '10:00', recipients: [ACCOUNTS.schueler], description: '<p>x</p>' },
  });
  expect(r.status()).toBe(200);
  return (await r.json()).event.eid as string;
}

test('Termin-Archiv: nur die eigenen Termine des Schuljahres, mit denselben Daten wie die Seite', async ({ baseURL }) => {
  const tag = Date.now().toString(36);
  const admin = await playwrightRequest.newContext({ baseURL });
  const other = await playwrightRequest.newContext({ baseURL });
  const student = await playwrightRequest.newContext({ baseURL });
  await apiLogin(admin, ACCOUNTS.admin);
  await apiLogin(other, ROLE_ACCOUNTS.technikteam); // can create events
  await apiLogin(student, ACCOUNTS.schueler);
  const mine = [
    await createEvent(admin, `Archiv eigen A ${tag}`, '2010-08-01'),
    await createEvent(admin, `Archiv eigen B ${tag}`, '2011-07-31'),
    // the next school year
    await createEvent(admin, `Archiv eigen C ${tag}`, '2011-08-01'),
  ];
  const theirs = await createEvent(other, `Archiv fremd ${tag}`, '2010-10-01');
  try {
    const r = await admin.post('/api/get_events_archive', { data: { school_year: 2010 } });
    expect(r.status()).toBe(200);
    const events = (await r.json()).events as any[];
    const titles = events.map((e) => e.info.title);
    expect(titles).toContain(`Archiv eigen A ${tag}`);
    expect(titles).toContain(`Archiv eigen B ${tag}`);
    expect(titles).not.toContain(`Archiv eigen C ${tag}`);
    expect(titles).not.toContain(`Archiv fremd ${tag}`);
    // newest first, as on the page
    expect(titles.indexOf(`Archiv eigen B ${tag}`)).toBeLessThan(titles.indexOf(`Archiv eigen A ${tag}`));
    // the same entries the page of today's design embeds
    const a = events.find((e) => e.eid === mine[0]);
    expect(Object.keys(a).sort()).toEqual(['dow', 'eid', 'info', 'recipients']);
    expect(a.recipients).toEqual([ACCOUNTS.schueler]);
    expect(a.info.start_time).toBe('09:00');
    const page = await (await admin.get('/events')).text();
    const embedded = JSON.parse(page.match(/var stored_events = (.*);\n/)![1]) as any[];
    expect(embedded.find((e) => e.eid === mine[0])).toEqual(a);

    // one event by its id: only one's own
    const byId = await admin.post('/api/get_events_archive', { data: { eid: mine[1] } });
    expect((await byId.json()).events.map((e: any) => e.eid)).toEqual([mine[1]]);
    const foreign = await admin.post('/api/get_events_archive', { data: { eid: theirs } });
    expect(foreign.status()).toBe(200);
    expect((await foreign.json()).events).toEqual([]);
    // the other organizer sees theirs, not the admin's
    const otherYear = ((await (await other.post('/api/get_events_archive', { data: { school_year: 2010 } })).json()).events as any[]).map((e) => e.eid);
    expect(otherYear).toContain(theirs);
    expect(otherYear).not.toContain(mine[0]);

    // only for people who may create events; parameters are checked
    expect((await student.post('/api/get_events_archive', { data: { school_year: 2010 } })).status()).not.toBe(200);
    expect((await admin.post('/api/get_events_archive', { data: { school_year: '2010' } })).status()).not.toBe(200);
    expect((await admin.post('/api/get_events_archive', { data: { school_year: 1 } })).status()).not.toBe(200);
    expect((await admin.post('/api/get_events_archive', { data: {} })).status()).not.toBe(200);
  } finally {
    for (const eid of mine) await admin.post('/api/delete_event', { data: { eid } });
    await other.post('/api/delete_event', { data: { eid: theirs } });
    await admin.dispose();
    await other.dispose();
    await student.dispose();
  }
});

test('News nach Jahren: ohne Jahr wie bisher, die Jahre ergeben zusammen die ganze Liste', async ({ baseURL }) => {
  const news = await playwrightRequest.newContext({ baseURL });
  const student = await playwrightRequest.newContext({ baseURL });
  await apiLogin(news, ROLE_ACCOUNTS.technikteam); // can manage news
  await apiLogin(student, ACCOUNTS.schueler);
  try {
    const all = await news.post('/api/get_news', { data: {} });
    expect(all.status()).toBe(200);
    const allJson = await all.json();
    // today's answer: only the list
    expect(Object.keys(allJson)).toEqual(['news']);

    const r2019 = await (await news.post('/api/get_news', { data: { year: 2019 } })).json();
    expect(r2019.year).toBe(2019);
    expect(r2019.news.map((n: any) => n.title)).toEqual(['Archiv-Beitrag 2019 Nr. 3', 'Archiv-Beitrag 2019 Nr. 2', 'Archiv-Beitrag 2019 Nr. 1']);
    expect(r2019.years).toContainEqual({ year: 2019, count: 3 });
    expect(r2019.years).toContainEqual({ year: 2018, count: 1 });
    // all years together: exactly the list without a year, in the same order
    let joined: any[] = [];
    for (const { year } of r2019.years)
      joined = joined.concat((await (await news.post('/api/get_news', { data: { year } })).json()).news);
    expect(joined).toEqual(allJson.news);

    expect((await student.post('/api/get_news', { data: { year: 2019 } })).status()).not.toBe(200);
    expect((await student.post('/api/get_news', { data: {} })).status()).not.toBe(200);
    expect((await news.post('/api/get_news', { data: { year: '2019' } })).status()).not.toBe(200);
  } finally {
    await news.dispose();
    await student.dispose();
  }
});
