import type { BrowserContext, Page, Route } from '@playwright/test';
import { ACCOUNTS, apiLogin } from './fixtures';

// A stand-in for the library service (gyst-bib), served through route() –
// the test stack has no library of its own, and its pages would otherwise
// call the production library (BIB_HOST in production mode). Every request
// to BIB_HOST is answered here: the /jwt/... endpoints the dashboard's
// library pages use, with the answers' shapes as in gyst-bib's main.rb, and
// the cover images as small SVGs. Example data only: the books are made up,
// the borrowers are accounts of src/example-data.
//
// The JWT of the dashboard (/api/get_bib_jwt_token) is decoded – not
// checked – for the role (teacher, can_manage_bib) and the person, so that
// get_book answers like the real service for each role. Errors come with
// HTTP 400 and {error}, like the service's asserts (which answer 500 there:
// the E2E tests fail on every 5xx).

export const BIB_HOST = 'https://gyst-bib.nhcham.org';

type Book = {
  stem: number; title: string; subtitle?: string; author?: string; verlag?: string; published?: number;
  page_count?: number; isbn?: string; preis?: number; waehrung?: string; has_cover?: boolean;
  description?: string; bib_entry?: string; labels: string[]; locations?: string[]; ts_discarded?: number;
};
type Loan = {
  email: string; ts_checked_out: number; ts_confirmed?: number; ts_summoned?: number;
  teacher?: string; fach?: string; ts_returned?: number;
};
type Order = {
  id: string; stem: number; email: string; ts_order_placed: number; lesson_key?: string;
  fach?: string; plus_teacher?: boolean; count?: number; complete?: boolean; paused?: boolean; f_count: number;
};

const DAY = 24 * 3600;
const now = () => Math.floor(Date.now() / 1000);

export type FakeBib = {
  books: Map<number, Book>;
  exemplare: Map<number, number[]>; // stem -> bnr
  loans: Map<string, Loan>; // "stem-bnr" -> current loan
  history: { sig: string; loan: Loan }[];
  orders: Order[];
  calls: { path: string; body: any; email: string }[];
  install(target: Page | BrowserContext): Promise<void>;
};

export function fakeBib(): FakeBib {
  const t = now();
  const books = new Map<number, Book>();
  const add = (b: Book, count: number) => {
    books.set(b.stem, b);
    exemplare.set(b.stem, Array.from({ length: count }, (_, i) => i + 1));
  };
  const exemplare = new Map<number, number[]>();
  add({ stem: 1201, title: 'Lambacher Schweizer Mathematik 5', subtitle: 'Ausgabe Berlin', author: 'Lambacher, Schweizer', verlag: 'Klett', published: 2016, page_count: 280, isbn: '9783127331501', preis: 2795, waehrung: 'EUR', has_cover: true, labels: ['Mathematik', 'Klasse 5'], locations: ['A3'] }, 30);
  add({ stem: 1202, title: 'Deutschbuch 5', author: 'Cornelsen Redaktion', verlag: 'Cornelsen', published: 2019, page_count: 312, isbn: '9783060627235', preis: 2650, waehrung: 'EUR', has_cover: true, labels: ['Deutsch', 'Klasse 5'], locations: ['B1'] }, 30);
  add({ stem: 1203, title: 'Green Line 1', subtitle: 'Schülerbuch', author: 'Harald Weisshaar', verlag: 'Klett', published: 2014, page_count: 232, isbn: '9783128340106', has_cover: false, labels: ['Englisch', 'Klasse 5'] }, 28);
  add({ stem: 1204, title: 'Geschichte und Geschehen', subtitle: 'Ausgabe für Berlin und Brandenburg, Band 1: Von der Urgeschichte bis zum Ende des Mittelalters', author: 'Michael Sauer, Hans-Jürgen Pandel', verlag: 'Klett', published: 2017, page_count: 264, has_cover: true, labels: ['Geschichte'] }, 12);
  add({ stem: 1205, title: 'Der kleine Prinz', author: 'Antoine de Saint-Exupéry', verlag: 'Karl Rauch', published: 1998, page_count: 96, isbn: '9783792000184', has_cover: true, description: 'Ein kleiner Prinz reist von Planet zu Planet.', labels: ['Deutsch', 'Lektüre'] }, 25);
  add({ stem: 1206, title: 'Biologie heute 1', author: 'Westermann Redaktion', verlag: 'Westermann', published: 2015, has_cover: false, labels: ['Biologie'] }, 8);

  const student = ACCOUNTS.schueler;
  const loans = new Map<string, Loan>();
  loans.set('1201-4', { email: student, ts_checked_out: t - 70 * DAY, ts_confirmed: t - 69 * DAY, teacher: ACCOUNTS.admin, fach: 'Mathematik' });
  loans.set('1202-7', { email: student, ts_checked_out: t - 70 * DAY, teacher: ACCOUNTS.admin, fach: 'Deutsch' });
  loans.set('1204-2', { email: student, ts_checked_out: t - 40 * DAY, ts_confirmed: t - 39 * DAY, ts_summoned: t - 2 * DAY });
  loans.set('1203-11', { email: student, ts_checked_out: t - 70 * DAY });
  loans.set('1201-5', { email: ACCOUNTS.schueler_oberstufe, ts_checked_out: t - 60 * DAY, ts_confirmed: t - 58 * DAY });
  loans.set('1205-1', { email: ACCOUNTS.admin, ts_checked_out: t - 100 * DAY, ts_confirmed: t - 99 * DAY });
  const history = [{ sig: '1205-3', loan: { email: student, ts_checked_out: t - 400 * DAY, ts_returned: t - 320 * DAY } }];
  const orders: Order[] = [
    { id: 'order1', stem: 1205, email: ACCOUNTS.admin, ts_order_placed: t - 5 * DAY, lesson_key: 'Ma_5a', fach: 'Mathematik', plus_teacher: true, f_count: 0 },
    { id: 'order2', stem: 1201, email: ACCOUNTS.admin, ts_order_placed: t - 30 * DAY, count: 1, f_count: 1, complete: true },
  ];
  const calls: FakeBib['calls'] = [];

  const sig = (stem: number, bnr: number) => `${stem}-${bnr}`;
  const pub = (b: Book) => {
    const { labels, locations, ...rest } = b;
    const n = (exemplare.get(b.stem) || []).length;
    const out = [...loans.keys()].filter((k) => k.startsWith(`${b.stem}-`)).length;
    return { ...rest, bib_count: n, bib_available: n - out, ausleih_count: out };
  };
  const exemplar = (stem: number, bnr: number) => ({ bnr });
  const rOf = (l: Loan) => {
    const { email, ...r } = l;
    return r;
  };
  const decode = (token: string | undefined) => {
    try {
      return JSON.parse(Buffer.from((token || '').split('.')[1], 'base64url').toString('utf8'));
    } catch {
      return {};
    }
  };
  const usersWhoHave = (stem: number) => {
    const d: Record<string, number> = {};
    for (const [k, l] of loans) if (k.startsWith(`${stem}-`)) d[l.email] = (d[l.email] || 0) + 1;
    return d;
  };
  const loansOf = (email: string, confirmed?: boolean) =>
    [...loans.entries()]
      .filter(([, l]) => l.email === email && (confirmed === undefined || !!l.ts_confirmed === confirmed))
      .map(([k, l]) => {
        const [stem, bnr] = k.split('-').map(Number);
        return { exemplar: exemplar(stem, bnr), book: pub(books.get(stem)!), r: rOf(l) };
      });

  type Answer = { status?: number; body: any };
  const handlers: Record<string, (d: any, who: any) => Answer> = {
    '/jwt/get_checked_out_books_for_user': (d, who) => {
      const ex = loansOf(who.email).sort((a, b) => (b.r.ts_summoned || 0) - (a.r.ts_summoned || 0) || a.r.ts_checked_out - b.r.ts_checked_out);
      return { body: { exemplare: ex, unconfirmed_count: ex.filter((x) => !x.r.ts_confirmed).length } };
    },
    '/jwt/get_checked_out_books_for_user_unconfirmed': (d, who) => ({ body: { exemplare: loansOf(who.email, false) } }),
    '/jwt/confirm_checked_out_book': (d, who) => {
      const l = loans.get(sig(d.stem, d.bnr));
      if (!l) return { body: { error: 'Dieses Buch ist momentan nicht ausgeliehen. Bringe es bitte in die Bibliothek zurück.' } };
      if (l.email !== who.email) return { body: { error: 'Dieses Buch ist nicht auf deinen Namen ausgeliehen. Bringe es bitte in die Bibliothek zurück.' } };
      if (l.ts_confirmed) return { body: { error: 'Dieses Buch ist bereits bestätigt.' } };
      l.ts_confirmed = now();
      return { body: { yay: 'sure' } };
    },
    '/jwt/get_labels': () => {
      const values = [...new Set([...books.values()].flatMap((b) => b.labels))].sort();
      return { body: { labels: values.map((value) => ({ type: 'fb', value })) } };
    },
    '/jwt/search': (d) => {
      const words = String(d.query || '').toLowerCase().split(/\s+/).filter(Boolean);
      const labels = d.labels ? String(d.labels).split(';') : [];
      if (words.length === 0 && labels.length === 0) return { body: { books: [] } };
      const found = [...books.values()].filter((b) => {
        const text = [b.author, b.title, b.subtitle, b.verlag].join(' ').toLowerCase();
        return words.every((w) => text.includes(w)) && (labels.length === 0 || b.labels.some((l) => labels.includes(l))) && !b.ts_discarded;
      });
      return { body: { books: found.map(pub) } };
    },
    '/jwt/get_books': () => ({ body: { books: [...books.values()].map((b) => ({ ...pub(b), locations: b.locations || [] })) } }),
    '/jwt/get_book': (d, who) => {
      const b = books.get(Number(d.stem));
      if (!b) return { status: 400, body: { error: 'not found' } };
      const res: any = { book: pub(b), server_ts: now(), proposed_isbn: [] };
      res.checked_out_user = [...loans.entries()]
        .filter(([k, l]) => k.startsWith(`${b.stem}-`) && l.email === who.email)
        .map(([k, l]) => ({ e: exemplar(b.stem, Number(k.split('-')[1])), r: rOf(l) }));
      if (who.teacher || who.can_manage_bib) {
        res.labels = b.labels.map((value) => ({ type: 'fb', value }));
        const mine = orders.filter((o) => o.stem === b.stem && o.email === who.email);
        res.orders_placed = mine.reduce((s, o) => s + (o.count || 0), 0);
        res.kurs_orders_placed = mine.filter((o) => o.lesson_key).map((o) => ({ id: o.id, lesson_key: o.lesson_key, plus_teacher: o.plus_teacher }));
        res.users_who_have_this_book = usersWhoHave(b.stem);
        res.logged_in_teacher_has_this_book = who.email in res.users_who_have_this_book;
      }
      if (who.can_manage_bib) {
        const out = [...loans.entries()].filter(([k]) => k.startsWith(`${b.stem}-`));
        res.checked_out_all = out.map(([k, l]) => ({ u: { email: l.email }, e: exemplar(b.stem, Number(k.split('-')[1])), r: rOf(l) }));
        res.in_limbo_all = [];
        const outBnr = new Set(out.map(([k]) => Number(k.split('-')[1])));
        res.in_stock_all = (exemplare.get(b.stem) || []).filter((n) => !outBnr.has(n)).map((n) => ({ 'e.bnr': n, 'e.has_checksum': false, 'e.ts_discarded': null }));
        res.discarded = [];
        if (b.locations) res.locations = b.locations;
      }
      if (d.bnr) {
        const l = loans.get(sig(b.stem, d.bnr));
        res.exemplar = { e: exemplar(b.stem, d.bnr), u: l ? { email: l.email } : null, r: l ? rOf(l) : null };
        res.past_check_outs = history.filter((h) => h.sig === sig(b.stem, d.bnr)).map((h) => ({ u: { email: h.loan.email }, r: rOf(h.loan) }));
      }
      return { body: res };
    },
    '/jwt/my_orders': (d, who) => ({
      body: {
        orders: orders.filter((o) => o.email === who.email).sort((a, b) => a.ts_order_placed - b.ts_order_placed).map((o) => ({
          b: pub(books.get(o.stem)!), o: { id: o.id, count: o.count, lesson_key: o.lesson_key, fach: o.fach, plus_teacher: o.plus_teacher, ts_order_placed: o.ts_order_placed, complete: o.complete },
          u: { email: o.email }, users_who_have_this_book: usersWhoHave(o.stem), f_count: o.f_count,
        })),
      },
    }),
    '/jwt/all_orders': () => ({
      body: {
        orders: orders.slice().sort((a, b) => a.ts_order_placed - b.ts_order_placed).map((o) => ({
          b: pub(books.get(o.stem)!), o: { id: o.id, count: o.count, lesson_key: o.lesson_key, fach: o.fach, plus_teacher: o.plus_teacher, ts_order_placed: o.ts_order_placed, complete: o.complete, paused: o.paused },
          u: { email: o.email }, locations: books.get(o.stem)!.locations || [], users_who_have_this_book: usersWhoHave(o.stem),
        })),
      },
    }),
    '/jwt/cancel_order': (d) => {
      const i = orders.findIndex((o) => o.id === d.oid);
      if (i < 0 || orders[i].f_count > 0) return { status: 400, body: { error: 'order_has_fulfillments' } };
      orders.splice(i, 1);
      return { body: { yay: 'sure' } };
    },
    '/jwt/place_order_private': (d, who) => {
      orders.push({ id: `order${orders.length + 1}${Date.now()}`, stem: d.stem, email: who.email, ts_order_placed: now(), count: 1, f_count: 0 });
      return { body: { yay: 'sure' } };
    },
    '/jwt/place_order_kurs': (d, who) => {
      orders.push({ id: `order${orders.length + 1}${Date.now()}`, stem: d.stem, email: who.email, ts_order_placed: now(), lesson_key: d.lesson_key, fach: d.fach, plus_teacher: !!d.plus_teacher, f_count: 0 });
      return { body: { yay: 'sure' } };
    },
    '/jwt/place_order_kurs_impersonate': (d) => {
      orders.push({ id: `order${orders.length + 1}${Date.now()}`, stem: d.stem, email: d.teacher, ts_order_placed: now(), lesson_key: d.lesson_key, fach: d.fach, plus_teacher: !!d.plus_teacher, f_count: 0 });
      return { body: { yay: 'sure' } };
    },
    '/jwt/get_users': () => {
      const per: Record<string, { ausleih_count: number; confirm_count: number }> = {};
      for (const l of loans.values()) {
        per[l.email] ||= { ausleih_count: 0, confirm_count: 0 };
        per[l.email].ausleih_count += 1;
        if (l.ts_confirmed) per[l.email].confirm_count += 1;
      }
      return { body: { users: Object.keys(per).sort().map((email) => ({ email, ...per[email] })) } };
    },
    '/jwt/get_checked_out_books_for_email': (d) => ({
      body: {
        server_ts: now(),
        exemplare: loansOf(d.email),
        returned_exemplare: history.filter((h) => h.loan.email === d.email).map((h) => {
          const [stem, bnr] = h.sig.split('-').map(Number);
          return { exemplar: exemplar(stem, bnr), book: pub(books.get(stem)!), r: rOf(h.loan) };
        }),
        in_limbo_exemplare: [],
      },
    }),
    '/jwt/verify_scanned_barcode': (d) => {
      if (!books.has(Number(d.stem))) return { status: 400, body: { error: 'unknown_stem' } };
      return { body: { yay: 'sure' } };
    },
    '/jwt/checkout_exemplar_for_user': (d) => {
      const b = books.get(Number(d.stem))!;
      const key = sig(d.stem, d.bnr);
      const old = loans.get(key);
      if (old) history.push({ sig: key, loan: { ...old, ts_returned: now() } });
      const l: Loan = { email: d.email, ts_checked_out: now(), teacher: d.order_teacher, fach: d.order_fach };
      loans.set(key, l);
      return { body: { u: { email: d.email }, b: pub(b), e: exemplar(d.stem, d.bnr), r: rOf(l), server_ts: now() } };
    },
    '/jwt/return_book': (d) => {
      const b = books.get(Number(d.stem));
      if (!b) return { body: { message: 'Stammsignatur nicht gefunden' } };
      const key = sig(d.stem, d.bnr);
      const l = loans.get(key);
      if (!l) return { body: { title: b.title, author: b.author, ts_discarded: null } };
      if (d.dryrun === 1) return { body: { email: l.email, ts_checked_out: l.ts_checked_out, title: b.title, author: b.author } };
      loans.delete(key);
      const ts = now();
      history.push({ sig: key, loan: { ...l, ts_returned: ts } });
      return { body: { email: l.email, ts_checked_out: l.ts_checked_out, ts_returned: ts, title: b.title, author: b.author } };
    },
    '/jwt/toggle_summon_exemplar': (d) => {
      const l = loans.get(sig(d.stem, d.bnr));
      if (!l) return { status: 400, body: { error: 'not_checked_out' } };
      l.ts_summoned = l.ts_summoned ? undefined : now();
      return { body: { ts_summoned: l.ts_summoned || null } };
    },
    '/jwt/scan_book': (d) => {
      const b = books.get(Number(d.stem));
      if (!b) return { status: 400, body: { error: 'unknown_stem' } };
      const list = exemplare.get(b.stem)!;
      const fresh = !list.includes(Number(d.bnr));
      if (fresh) list.push(Number(d.bnr));
      return { body: { book: pub(b), new_exemplar: fresh, proposed_isbn: [], book_photos: [], locations: b.locations || [] } };
    },
    '/jwt/get_shelves': () => ({ body: { shelves: [] } }),
    // the overview's statistics: an empty school year (no charts, no
    // summoned books) – enough for the page to draw itself
    '/jwt/get_stats': () => ({
      body: {
        all_ts_keys: [], ts_checked_out: {}, ts_confirmed: {}, ts_returned: {}, ts_summoned: {}, ts_discarded: {},
        ts_removed_ausleihe: {}, confirmed_count_for_user: {}, ausleihe_count_for_user: {}, books_for_user: {},
        book_details: {}, actions_for_durations: {}, summoned_books: [],
      },
    }),
  };

  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
  };

  async function handle(route: Route) {
    const request = route.request();
    if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
    const url = new URL(request.url());
    const cover = url.pathname.match(/^\/gen\/covers\/(\d+)-\d+\.jpg$/);
    if (cover) {
      const b = books.get(Number(cover[1]));
      if (!b || !b.has_cover) return route.fulfill({ status: 404, headers: cors, body: '' });
      const hue = (b.stem * 47) % 360;
      const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="300" height="420" viewBox="0 0 300 420">` +
        `<rect width="300" height="420" fill="hsl(${hue},45%,42%)"/><rect x="24" y="40" width="252" height="120" fill="hsl(${hue},35%,88%)"/>` +
        `<text x="150" y="112" font-family="sans-serif" font-size="30" text-anchor="middle" fill="hsl(${hue},45%,25%)">${b.stem}</text></svg>`;
      return route.fulfill({ status: 200, headers: { ...cors, 'content-type': 'image/svg+xml' }, body: svg });
    }
    const handler = handlers[url.pathname];
    let body: any = {};
    try { body = JSON.parse(request.postData() || '{}'); } catch { /* not JSON */ }
    const who = decode(request.headers()['x-jwt']);
    calls.push({ path: url.pathname, body, email: who.email });
    if (!handler) return route.fulfill({ status: 404, headers: cors, contentType: 'application/json', body: JSON.stringify({ error: 'not_mocked' }) });
    const answer = handler(body, who);
    return route.fulfill({ status: answer.status || 200, headers: cors, contentType: 'application/json', body: JSON.stringify(answer.body) });
  }

  return {
    books, exemplare, loans, history, orders, calls,
    async install(target) {
      await target.route(`${BIB_HOST}/**`, handle);
    },
  };
}


// The library's staff work at a library device (bib-station, bib-mobile):
// only there (or as teachers) do they manage the library
// (can_manage_bib_logged_in?). An admin turns a browser context into the
// device (/api/login_as_device), the device shows its login page with a QR
// code (/bib_login, over a websocket), the staff member opens its link with
// their own session, and the device signs in as them.
export async function stationLogin(page: Page, staffRequest: { get: (url: string) => Promise<any> }, device = 'bib-station') {
  await apiLogin(page.context().request, ACCOUNTS.admin);
  const asDevice = await page.context().request.post('/api/login_as_device', { data: { device } });
  if (asDevice.status() !== 200) throw new Error(`login_as_device: ${asDevice.status()}`);
  const qr = page.waitForResponse('**/api/get_device_login_qrcode');
  await page.goto('/bib_login');
  const { url } = await (await qr).json();
  const loggedIn = page.waitForURL((u) => /^\/bib_(browse|scan)/.test(u.pathname), { timeout: 15_000 });
  await staffRequest.get(new URL(url).pathname);
  await loggedIn;
}
