import { test, expect, TEST_OTP_SECRET } from './fixtures';
import type { Browser } from '@playwright/test';
import fs from 'fs';
import net from 'net';
import os from 'os';
import path from 'path';
import { fakeIonos, FakeIonos, FakeMailbox, FakeVariant } from './fake-ionos';

// The mailbox password bot (src/mail-account-bot, mounted at
// /mail-account-bot by ./test.sh) against a fake IONOS control panel. What
// matters most: it changes exactly the mailbox of the case and nothing else,
// and it stops (and stays stopped) at the first page that doesn't look as
// recorded, without trying again – a locked IONOS account would lock the
// school out of all mailboxes.

const BOT = '/mail-account-bot/lib';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { run, caseProblem } = require(`${BOT}/run.js`);
const { validateConfig } = require(`${BOT}/config.js`);
const { State } = require(`${BOT}/state.js`);
const { parseTotpSecret, totpAt } = require(`${BOT}/totp.js`);
const { imapLoginWorks } = require(`${BOT}/imap.js`);
const { dashboardClient } = require(`${BOT}/dashboard.js`);
const ionos = require(`${BOT}/ionos.js`);
const { record } = require(`${BOT}/record.js`);

const DOMAIN = 'mail.beispielschule.de';
const ANNA = `anna.bot@${DOMAIN}`;
const ANNA_PARENTS = `eltern.anna.bot@${DOMAIN}`;
const BEN = `ben.bot@${DOMAIN}`;
const TEACHER = 'lehrkraft@beispielschule.de';
const MAILBOXES: FakeMailbox[] = [
  { address: ANNA_PARENTS },
  { address: ANNA },
  { address: `anna.bot2@${DOMAIN}` },
  { address: BEN },
  { address: `weiterleitung.bot@${DOMAIN}`, kind: 'forward' },
  { address: TEACHER },
];
const PASSWORD = 'Abc-def-Ghi-23';
const PASSWORD_2 = 'Xyz-uvw-Rst-45';

test.describe.configure({ mode: 'serial' });
test.beforeEach(({}, testInfo) => {
  test.skip(testInfo.project.name !== 'desktop', 'Node-side bot, one browser project is enough');
});

function botConfig(overrides: Record<string, unknown> = {}) {
  const config = validateConfig(
    {
      host: 'testrechner',
      dashboard_url: 'https://dashboard.test.invalid',
      dashboard_token: 't'.repeat(40),
      ionos_login: 'schule-test',
      ionos_password: 'nur-ein-test',
      totp_secret: TEST_OTP_SECRET,
      allowed_mailboxes: `^(eltern\\.)?[a-z0-9.-]+@${DOMAIN.replace(/\./g, '\\.')}$`,
    },
    { hostname: 'testrechner' },
  );
  return Object.assign(config, { pace: 0, timeout_ms: 4000, verify_delays_s: [0], linger_minutes: 0, totp_min_remaining_s: 0 }, overrides);
}

type Case = { id: string | null; mailboxes: { mailbox: string; kind?: string | null; password: string }[] };

// the dashboard's bot interface, with the shared state (pause, run lock,
// logins of all machines) as in mail_password_reset.rb
type Create = { id: string; mailbox: string; kind: string | null; password: string };

function fakeDashboard(cases: Case[], { maxLogins = 3, create = [] as Create[], listWanted = false } = {}) {
  const reports: { id: string; ok: boolean; message: string }[] = [];
  const d = {
    reports,
    create,
    listWanted,
    uploads: [] as { address: string; type: string }[][],
    createResults: [] as { id: string; ok: boolean; message: string }[],
    async creation() {
      const open = d.create.filter((c) => !d.createResults.some((r) => r.id === c.id));
      return { create: d.paused ? [] : open, address_list: { ts: null, wanted: !d.paused && (d.listWanted || open.length > 0) }, paused: !!d.paused };
    },
    async uploadAddressList(rows: { address: string; type: string }[]) { d.uploads.push(rows); d.listWanted = false; return { result: 'ok' }; },
    async createResult(id: string, ok: boolean, message: string) { d.createResults.push({ id, ok, message }); return { result: 'ok' }; },
    paused: null as null | { reason: string; host: string },
    runHost: null as null | string,
    logins: 0,
    claims: [] as string[],
    async pending() {
      return { cases: d.paused ? [] : cases.filter((c) => !reports.some((r) => r.id === c.id)), paused: d.paused };
    },
    async report(id: string, ok: boolean, message: string) { reports.push({ id, ok, message }); return 'ok'; },
    activities: [] as string[],
    async claim(host: string, activity = 'working') {
      d.claims.push(host);
      d.activities.push(activity);
      if (d.paused) return { result: 'paused', reason: d.paused.reason };
      if (d.runHost && d.runHost !== host) return { result: 'busy', host: d.runHost };
      d.runHost = host;
      return { result: 'ok' };
    },
    async release(host: string) { if (d.runHost === host) d.runHost = null; return { result: 'ok' }; },
    async pause(host: string, reason: string) { if (!d.paused) d.paused = { reason, host }; return { result: 'ok' }; },
    async loginAttempt() {
      if (d.paused) return { result: 'paused' };
      if (d.logins >= maxLogins) return { result: 'limit' };
      d.logins += 1;
      return { result: 'ok' };
    },
  };
  return d;
}

function tmpState() {
  return new State(fs.mkdtempSync(path.join(os.tmpdir(), 'mail-account-bot-')));
}

async function runBot(browser: Browser, fake: FakeIonos, cases: Case[], opts: Record<string, unknown> = {}) {
  const state = (opts.state as any) || tmpState();
  const dashboard = (opts.dashboard as any) || fakeDashboard(cases);
  let contexts = 0;
  const summary = await run({
    config: (opts.config as any) || botConfig(),
    state,
    dashboard,
    imapLoginWorks: (opts.imap as any) || (async (user: string, password: string) => fake.passwords.get(user) === password),
    openContext: async () => {
      contexts += 1;
      const context = await browser.newContext();
      await fake.install(context);
      return context;
    },
    testing: true,
    print: () => {},
    dryRun: !!opts.dryRun,
    confirm: (opts.confirm as any) || (async () => true),
    waitForWork: opts.waitForWork as any,
    shouldStop: opts.shouldStop as any,
  });
  return { summary, state, dashboard, contexts };
}

// login attempts (a username was sent), not just the login page shown
const attempts = (fake: FakeIonos) => fake.logins.filter((l) => l.username !== undefined).length;

const kindOf = (mailbox: string) => (mailbox.startsWith('eltern.') ? 'parents' : 'student');
const one = (mailbox: string, id = 'case-1', password = PASSWORD, kind: string | null = kindOf(mailbox.trim().toLowerCase())): Case =>
  ({ id, mailboxes: [{ mailbox, kind, password }] });

test('Bot: meldet sich einmal an, setzt genau das eine Postfach zurück, prüft und meldet es', async ({ browser }) => {
  // a fresh browser profile: the cookie banner comes first
  const fake = fakeIonos(MAILBOXES, { consentBanner: true });
  const { summary, dashboard, state } = await runBot(browser, fake, [one(ANNA)]);
  expect(summary.status, summary.reason).toBe('ok');
  expect(fake.resets).toEqual([{ address: ANNA, password: PASSWORD }]);
  expect(fake.deletes).toHaveLength(0);
  expect(fake.logins).toHaveLength(1);
  expect(fake.logins[0]).toEqual({ username: 'schule-test', password: true, otp: true });
  expect(dashboard.reports).toEqual([{ id: 'case-1', ok: true, message: expect.stringContaining('zurückgesetzt') }]);
  expect(state.counters()).toMatchObject({ logins: 1 });
  expect(dashboard.logins).toBe(1);
  expect(dashboard.paused).toBeNull();
  // the run lock was taken by this machine and given back
  expect(dashboard.claims[0]).toBe('testrechner');
  expect(dashboard.runHost).toBeNull();
});

test('Bot: Eltern-Postfach und ähnliche Adressen – nur die exakte Adresse', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const { summary } = await runBot(browser, fake, [one(ANNA_PARENTS, 'p'), one(ANNA, 'a', PASSWORD_2)]);
  expect(summary.status, summary.reason).toBe('ok');
  expect(fake.resets).toEqual([
    { address: ANNA_PARENTS, password: PASSWORD },
    { address: ANNA, password: PASSWORD_2 },
  ]);
  // the session was still valid: no login at all
  expect(fake.logins).toHaveLength(0);
});

test('Bot: Probelauf ändert nichts und meldet nichts', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const { summary, dashboard } = await runBot(browser, fake, [one(ANNA)], { dryRun: true });
  expect(summary.status, summary.reason).toBe('ok');
  expect(summary.dryRun).toEqual(['case-1']);
  expect(fake.resets).toHaveLength(0);
  expect(dashboard.reports).toHaveLength(0);
});

test('Bot: schon das ursprüngliche Passwort – IONOS wird gar nicht geöffnet', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES);
  fake.passwords.set(ANNA, PASSWORD);
  const { summary, contexts, dashboard } = await runBot(browser, fake, [one(ANNA)]);
  expect(summary.done).toHaveLength(1);
  expect(contexts).toBe(0);
  expect(dashboard.reports[0]).toMatchObject({ ok: true, message: expect.stringContaining('schon das ursprüngliche') });
});

test('Bot: Lehrkraft-Postfach, ungültige Daten – abgelehnt, ohne IONOS zu öffnen', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES);
  const cases: Case[] = [
    one(TEACHER, 't'), one(` ${ANNA}`, 'space'), one(ANNA, 'pw', 'kurz'), one(ANNA.toUpperCase(), 'upper'),
    // what the dashboard says it is must match the address
    one(ANNA, 'kind', PASSWORD, 'parents'), one(ANNA_PARENTS, 'kind2', PASSWORD, 'student'), one(BEN, 'nokind', PASSWORD, null),
  ];
  const { summary, contexts, dashboard } = await runBot(browser, fake, cases);
  expect(contexts).toBe(0);
  expect(fake.resets).toHaveLength(0);
  expect(summary.failed.map((f: any) => f.id)).toEqual(['t', 'space', 'pw', 'upper', 'kind', 'kind2', 'nokind']);
  expect(dashboard.reports.every((r) => !r.ok)).toBe(true);
  expect(caseProblem(one(BEN), botConfig())).toBeNull();
});

test('Bot: Weiterleitung oder fehlende Adresse – nur dieser Fall scheitert', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const cases = [one(`weiterleitung.bot@${DOMAIN}`, 'fw'), one(`gibtsnicht.bot@${DOMAIN}`, 'missing'), one(BEN, 'ben')];
  const { summary, dashboard } = await runBot(browser, fake, cases);
  expect(summary.status, summary.reason).toBe('ok');
  expect(summary.failed.map((f: any) => f.id)).toEqual(['fw', 'missing']);
  expect(fake.resets).toEqual([{ address: BEN, password: PASSWORD }]);
  expect(dashboard.paused).toBeNull();
});

// every one of these: no reset, bot paused, the case reported as failed,
// and the next run doesn't even open the browser
const STOPS: [string, FakeVariant, RegExp, boolean][] = [
  ['Seite „Passwort ändern“ zeigt eine andere Adresse', { dialogShows: BEN }, /zeigt nicht genau/, true],
  ['Zeile verweist auf ein anderes Postfach', { rowLinksTo: BEN }, /zeigt nicht genau/, true],
  ['Adresse doppelt in der Liste', { duplicate: ANNA }, /mehrfach/, true],
  ['Liste in unbekanntem Format', { rowsWithoutTestIds: true }, /bekannten Format/, true],
  ['Fehlermeldung beim Ändern', { errorOnSubmit: true }, /Fehler/, true],
  ['keine Bestätigung nach dem Ändern', { noSuccessMessage: true }, /Bestätigung/, true],
  ['neues Fenster aus der Liste', { popupOnList: true }, /neues Fenster/, true],
  ['Captcha bei der Anmeldung', { captchaAfterUsername: true }, /Sicherheitsabfrage/, false],
  ['Passwort abgelehnt', { rejectPassword: true }, /lehnt das Passwort ab/, false],
  ['kein zweiter Faktor gefragt', { noOtpStep: true }, /zweiten Faktor/, false],
  ['Weiterleitung auf fremde Seite', { redirectAfterLogin: 'https://andere-seite.example/' }, /nicht vorgesehene Adresse/, false],
];

for (const [name, variant, reason, loggedIn] of STOPS) {
  test(`Bot hält an: ${name}`, async ({ browser }) => {
    const fake = fakeIonos(MAILBOXES, variant, { loggedIn });
    const { summary, state, dashboard } = await runBot(browser, fake, [one(ANNA), one(BEN, 'case-2')]);
    expect(summary.status).toBe('stopped');
    expect(summary.reason).toMatch(reason);
    // nothing changed – except where IONOS itself reported an error / no confirmation
    if (!variant.noSuccessMessage) expect(fake.resets).toHaveLength(0);
    expect(fake.deletes).toHaveLength(0);
    // at most one login attempt, never a second one
    expect(attempts(fake)).toBeLessThanOrEqual(1);
    // paused on the dashboard, for every machine
    expect(dashboard.paused).toMatchObject({ reason: expect.stringMatching(reason), host: 'testrechner' });
    expect(state.lastStop()).toMatchObject({ reason: expect.stringMatching(reason) });
    expect(dashboard.reports).toEqual([{ id: 'case-1', ok: false, message: expect.stringContaining('angehalten') }]);
    // case-2 was not touched and stays approved for the admin
    const again = await runBot(browser, fake, [one(ANNA), one(BEN, 'case-2')], { state, dashboard });
    expect(again.summary.status).toBe('paused');
    expect(again.contexts).toBe(0);
    expect(attempts(fake)).toBeLessThanOrEqual(1);
  });
}

test('Bot: neues Passwort klappt danach nicht – angehalten', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const { summary, dashboard, state } = await runBot(browser, fake, [one(ANNA)], { imap: async () => false });
  expect(summary.status).toBe('stopped');
  expect(dashboard.reports).toEqual([{ id: 'case-1', ok: false, message: expect.stringContaining('nimmt das neue Passwort nicht an') }]);
  expect(dashboard.paused).not.toBeNull();
});

test('Bot: Anmeldungen begrenzt – auf dem Dashboard für alle Rechner, hier zusätzlich pro Rechner', async ({ browser }) => {
  // the dashboard has no login left today: nothing is attempted, the case waits
  const fake = fakeIonos(MAILBOXES);
  const dashboard = fakeDashboard([one(ANNA, 'a')], { maxLogins: 0 });
  const first = await runBot(browser, fake, [one(ANNA, 'a')], { dashboard });
  expect(first.summary.status).toBe('ok');
  expect(first.summary.postponed).toEqual(['a']);
  expect(attempts(fake)).toBe(0);
  expect(dashboard.reports).toHaveLength(0);
  expect(dashboard.paused).toBeNull();
  // this machine's own limit
  const state = tmpState();
  const config = botConfig({ max_logins_per_day: 1 });
  const ok = await runBot(browser, fake, [one(ANNA, 'a'), one(BEN, 'b')], { state, config });
  expect(ok.summary.done.map((d: any) => d.id)).toEqual(['a', 'b']);
  expect(attempts(fake)).toBe(1);
  fake.loggedIn = false;
  const second = await runBot(browser, fake, [one(ANNA_PARENTS, 'p')], { state, config });
  expect(second.summary.postponed).toEqual(['p']);
  expect(attempts(fake)).toBe(1);
});

test('Bot: ein Rechner zur Zeit, angehalten heißt angehalten', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([one(ANNA)]);
  dashboard.runHost = 'laptop';
  const busy = await runBot(browser, fake, [one(ANNA)], { dashboard });
  expect(busy.summary.status).toBe('busy');
  expect(busy.contexts).toBe(0);
  dashboard.runHost = null;
  dashboard.paused = { reason: 'vom Laptop angehalten', host: 'laptop' };
  const paused = await runBot(browser, fake, [one(ANNA)], { dashboard });
  expect(paused.summary.status).toBe('paused');
  expect(paused.contexts).toBe(0);
  expect(fake.resets).toHaveLength(0);
});

test('Bot: ohne Bestätigung am Rechner geschieht nichts', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  let asked: string[] = [];
  const { summary, contexts, dashboard } = await runBot(browser, fake, [one(ANNA), one(ANNA_PARENTS, 'p')], {
    confirm: async (lines: string[]) => { asked = lines; return false; },
  });
  expect(asked.slice(1)).toEqual([ANNA, ANNA_PARENTS]);
  expect(summary.status).toBe('not_confirmed');
  expect(contexts).toBe(0);
  expect(fake.resets).toHaveLength(0);
  expect(dashboard.reports).toHaveLength(0);
  expect(dashboard.runHost).toBeNull();
});

test('Bot: echte Fälle erst, wenn der IONOS-Ablauf bestätigt ist', async ({ browser }) => {
  // watched by the maintainer on 2026-11-14; any change to lib/ionos.js sets it back to 'recorded'
  expect(ionos.FLOW_STATUS).toBe('verified');
  const dashboard = fakeDashboard([]);
  const summary = await run({
    config: botConfig(), state: tmpState(), dashboard, imapLoginWorks: async () => false,
    openContext: async () => browser.newContext(), print: () => {},
  });
  expect(summary.status).toBe('ok');
  expect(dashboard.claims).toEqual(['testrechner']);
});

test('Bot: Konfiguration nur für diesen Rechner, ohne Lücken', async () => {
  const base = {
    host: 'testrechner', dashboard_url: 'https://dashboard.test.invalid', dashboard_token: 't'.repeat(40),
    ionos_login: 'x', ionos_password: 'y', totp_secret: TEST_OTP_SECRET, allowed_mailboxes: `^[a-z.]+@${DOMAIN}$`,
  };
  expect(() => validateConfig(base, { hostname: 'anderer-rechner' })).toThrow(/nur auf „testrechner“/);
  // several machines (home, laptop)
  const { host, ...noHost } = base;
  expect(validateConfig({ ...noHost, hosts: ['testrechner', 'laptop'] }, { hostname: 'laptop' }).host).toBe('laptop');
  expect(() => validateConfig({ ...noHost, hosts: ['testrechner', 'laptop'] }, { hostname: 'fremd' })).toThrow(/nicht auf „fremd“/);
  expect(() => validateConfig(noHost, { hostname: 'testrechner' })).toThrow(/hosts fehlt/);
  expect(() => validateConfig({ ...noHost, hosts: ['a b'] }, { hostname: 'a b' })).toThrow(/ungültiger Rechnername/);
  expect(() => validateConfig({ ...base, dashboard_url: 'http://dashboard.test.invalid' }, { hostname: 'testrechner' })).toThrow(/https/);
  expect(() => validateConfig({ ...base, allowed_mailboxes: '.*' }, { hostname: 'testrechner' })).toThrow(/verankert/);
  expect(() => validateConfig({ ...base, dashboard_token: 'kurz' }, { hostname: 'testrechner' })).toThrow(/zu kurz/);
  expect(() => validateConfig({ ...base, pace: 0 }, { hostname: 'testrechner' })).toThrow(/pace/);
  expect(() => validateConfig({ ...base, ionos_password: '' }, { hostname: 'testrechner' })).toThrow(/ionos_password/);
  expect(() => validateConfig({ ...base, test_mailbox: TEACHER, test_mailbox_passwords: [PASSWORD, PASSWORD_2] }, { hostname: 'testrechner' })).toThrow(/test_mailbox/);
  expect(() => validateConfig({ ...base, test_mailbox: ANNA, test_mailbox_passwords: [PASSWORD, PASSWORD] }, { hostname: 'testrechner' })).toThrow(/zwei verschiedene/);
  expect(validateConfig(base, { hostname: 'testrechner' }).pace).toBe(1);
});

test('Bot: Anmeldung ohne zweiten Faktor nur ausdrücklich (ionos_2fa: false)', async ({ browser }) => {
  // set up without 2FA: logs in right after the password
  const fake = fakeIonos(MAILBOXES, { noOtpStep: true });
  const config = botConfig({ ionos_2fa: false });
  const { summary } = await runBot(browser, fake, [one(ANNA)], { config });
  expect(summary.status, summary.reason).toBe('ok');
  expect(fake.resets).toEqual([{ address: ANNA, password: PASSWORD }]);
  // but if IONOS asks for a code after all: stop
  const asks = fakeIonos(MAILBOXES);
  const stopped = await runBot(browser, asks, [one(ANNA)], { config: botConfig({ ionos_2fa: false }) });
  expect(stopped.summary.status).toBe('stopped');
  expect(stopped.summary.reason).toMatch(/fragt nach einem Code/);
  expect(asks.resets).toHaveLength(0);
  // without 2FA no TOTP secret is needed; with it, it is
  const { totp_secret, ...noSecret } = { host: 'testrechner', dashboard_url: 'https://d.test.invalid', dashboard_token: 't'.repeat(40),
    ionos_login: 'x', ionos_password: 'y', totp_secret: TEST_OTP_SECRET, allowed_mailboxes: `^[a-z.]+@${DOMAIN}$` };
  expect(validateConfig({ ...noSecret, ionos_2fa: false }, { hostname: 'testrechner' }).totp).toBeUndefined();
  expect(() => validateConfig(noSecret, { hostname: 'testrechner' })).toThrow(/totp_secret fehlt/);
});

test('Bot: lokale Entwicklungsinstanz als Dashboard nur für das Test-Postfach', async ({ browser }) => {
  const config = botConfig({ dashboard_is_local: true });
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  await expect(runBot(browser, fake, [one(ANNA)], { config })).rejects.toThrow(/nur --test-mailbox/);
  expect(fake.resets).toHaveLength(0);
  const base = { host: 'testrechner', dashboard_token: 't'.repeat(40), ionos_login: 'x', ionos_password: 'y', ionos_2fa: false, allowed_mailboxes: `^[a-z.]+@${DOMAIN}$` };
  expect(validateConfig({ ...base, dashboard_url: 'http://localhost:8025' }, { hostname: 'testrechner' }).dashboard_is_local).toBe(true);
  expect(() => validateConfig({ ...base, dashboard_url: 'http://dashboard.example.org' }, { hostname: 'testrechner' })).toThrow(/https/);
});

test('Bot: TOTP nach RFC 6238 und otpauth-URI', async () => {
  // RFC 6238 test secret "12345678901234567890" (SHA1)
  const cfg = parseTotpSecret('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
  expect(totpAt(cfg, 59_000).code).toBe('287082');
  expect(totpAt(cfg, 1_111_111_109_000).code).toBe('081804');
  expect(totpAt({ ...cfg, digits: 8 }, 1_234_567_890_000).code).toBe('89005924');
  const uri = parseTotpSecret('otpauth://totp/IONOS:schule?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=IONOS&digits=6&period=30');
  expect(totpAt(uri, 59_000).code).toBe('287082');
  expect(() => parseTotpSecret('kein base32!')).toThrow();
});

test('Bot: Zustand – Sperre gegen zweite Instanz auf diesem Rechner, letzter Halt', async () => {
  const state = tmpState();
  state.lock();
  fs.writeFileSync(state.file('lock'), '1'); // PID 1 is alive (init)
  expect(() => state.lock()).toThrow(/läuft schon/);
  state.unlock();
  state.recordStop('Test', { screenshot: '/x.png' });
  expect(state.lastStop()).toMatchObject({ reason: 'Test', screenshot: '/x.png' });
  expect((fs.statSync(state.dir).mode & 0o777).toString(8)).toBe('700');
});

test('Bot: IMAP-Anmeldeprüfung', async () => {
  const server = net.createServer((socket) => {
    socket.write('* OK fake\r\n');
    socket.on('data', (data) => {
      const line = data.toString();
      if (line.startsWith('a1 LOGIN')) socket.write(line.includes('"richtig"') ? 'a1 OK angemeldet\r\n' : 'a1 NO falsch\r\n');
      if (line.startsWith('a2 LOGOUT')) { socket.write('* BYE\r\na2 OK\r\n'); socket.end(); }
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = (server.address() as net.AddressInfo).port;
  const opts = { host: '127.0.0.1', port, tls: false, timeoutMs: 3000 };
  expect(await imapLoginWorks(opts, ANNA, 'richtig')).toBe(true);
  expect(await imapLoginWorks(opts, ANNA, 'falsch')).toBe(false);
  await expect(imapLoginWorks(opts, ANNA, 'mit\r\nzeilenumbruch')).rejects.toThrow();
  server.close();
});

test('Bot: Dashboard-Schnittstelle mit dem Token', async ({ baseURL }) => {
  const good = dashboardClient({ url: baseURL, token: 'test-mail-password-reset-bot-token-0123456789' });
  const pending = await good.pending();
  expect(Array.isArray(pending.cases)).toBe(true);
  expect(pending.paused).toBeNull();
  // shared state through the client
  expect((await good.claim('testrechner')).result).toBe('ok');
  expect((await good.release('testrechner')).result).toBe('ok');
  const bad = dashboardClient({ url: baseURL, token: 'x'.repeat(45) });
  await expect(bad.pending()).rejects.toThrow(/401/);
});

test('Bot: Dashboard nicht erreichbar – hält trotzdem an', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, { dialogShows: BEN }, { loggedIn: true });
  const dashboard = fakeDashboard([one(ANNA)]);
  dashboard.report = async () => { throw new Error('offline'); };
  const { summary, state } = await runBot(browser, fake, [one(ANNA)], { dashboard });
  expect(summary.status).toBe('stopped');
  expect(summary.unreported).toBe(1);
  expect(dashboard.paused).not.toBeNull();
  expect(fake.resets).toHaveLength(0);
});

test('Bot: Aufnahme speichert Aufbau, aber keine Eingaben und keine Adressen', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: false });
  const context = await browser.newContext();
  await fake.install(context);
  const state = tmpState();
  const recording = record({ context, state, testMailbox: ANNA, print: () => {} });
  await expect.poll(() => context.pages().length).toBe(1);
  const page = context.pages()[0];
  await page.waitForSelector('#username');
  // the maintainer logs in by hand and clicks through, as on 2026-11-14
  await page.fill('#username', 'kundennummer-geheim');
  await page.click('#button--with-loader');
  await page.fill('#password', 'passwort-geheim');
  await page.click('#button--with-loader');
  await page.waitForURL('https://login.ionos.de/totp');
  await page.fill('#passcode', totpAt(parseTotpSecret(TEST_OTP_SECRET)).code);
  await page.click('#button--with-loader');
  await page.waitForURL('https://mein.ionos.de/home/products');
  await page.goto('https://mein.ionos.de/email/');
  await page.fill('[data-testid=input-email-search]', ANNA);
  await page.click('[data-testid=button-search-submit]');
  await page.waitForURL(/search=/);
  const row = page.locator(`tr[data-testid="tr-${ANNA}"]`);
  await row.locator('[data-testid=button-context-menu-trigger]').click();
  await row.locator('[data-testid=link-mailbox-change-password]').click();
  await page.locator('#password').fill('neues-passwort-geheim');
  await page.waitForTimeout(2000);
  await context.close();
  const file = await recording;
  const text = fs.readFileSync(file, 'utf8');
  const events = text.trim().split('\n').map((l) => JSON.parse(l));
  expect(events.filter((e) => e.event === 'page').length).toBeGreaterThan(3);
  expect(events.some((e) => e.event === 'click')).toBe(true);
  expect(text).toContain('#username');
  expect(text).toContain('change-password');
  expect(text).toContain('<test-mailbox>');
  // no typed values, no addresses other than as placeholders
  for (const secret of ['kundennummer-geheim', 'passwort-geheim', 'neues-passwort-geheim', DOMAIN, '@']) {
    expect(text, secret).not.toContain(secret);
  }
  expect((fs.statSync(file).mode & 0o777).toString(8)).toBe('600');
});

// ---- creating mailboxes ----

const NEW = `neu.bot@${DOMAIN}`;
const NEW_PARENTS = `eltern.neu.bot@${DOMAIN}`;
const createJob = (mailbox: string, id = 'n1', kind: string | null = kindOf(mailbox), password = PASSWORD): Create => ({ id, mailbox, kind, password });

test('Bot legt an: Adressliste zuerst, dann genau das freigegebene Postfach als Mail Basic, ohne Extras, geprüft', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [createJob(NEW), createJob(NEW_PARENTS, 'n2', 'parents', PASSWORD_2)] });
  const { summary } = await runBot(browser, fake, [], { dashboard });
  expect(summary.status, summary.reason).toBe('ok');
  // the list before and – with the new mailboxes – after the work
  expect(fake.exports).toBe(2);
  expect(dashboard.uploads).toHaveLength(2);
  expect(dashboard.uploads[0].map((r) => r.address)).toContain(ANNA);
  expect(dashboard.uploads[0].map((r) => r.address)).not.toContain(NEW);
  expect(dashboard.uploads[1].map((r) => r.address)).toEqual(expect.arrayContaining([NEW, NEW_PARENTS]));
  expect(fake.created).toEqual([
    { address: NEW, password: PASSWORD, extras: [], forward: '' },
    { address: NEW_PARENTS, password: PASSWORD_2, extras: [], forward: '' },
  ]);
  expect(dashboard.createResults.map((r) => [r.id, r.ok])).toEqual([['n1', true], ['n2', true]]);
  expect(fake.resets).toHaveLength(0);
  expect(fake.deletes).toHaveLength(0);
});

test('Bot legt an: was es laut frischer Adressliste schon gibt, wird nicht angelegt', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [createJob(ANNA, 'n1'), createJob(NEW, 'n2')] });
  const { summary } = await runBot(browser, fake, [], { dashboard });
  expect(summary.status, summary.reason).toBe('ok');
  expect(fake.created.map((c) => c.address)).toEqual([NEW]);
  // the dashboard marks the existing one itself when the list arrives
  expect(dashboard.createResults.map((r) => r.id)).toEqual(['n2']);
});

test('Bot legt an: Probelauf legt nichts an und lädt nichts hoch; nur die Adressliste geht auch', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [createJob(NEW)] });
  const dry = await runBot(browser, fake, [], { dashboard, dryRun: true });
  expect(dry.summary.status, dry.summary.reason).toBe('ok');
  expect(dry.summary.dryRun).toEqual(['n1']);
  expect(fake.created).toHaveLength(0);
  expect(dashboard.uploads).toHaveLength(0);
  expect(dashboard.createResults).toHaveLength(0);
  // nothing to create, the list is wanted: export and upload only
  const listOnly = fakeDashboard([], { listWanted: true });
  const res = await runBot(browser, fake, [], { dashboard: listOnly });
  expect(res.summary.status).toBe('ok');
  expect(listOnly.uploads).toHaveLength(1);
  expect(fake.created).toHaveLength(0);
});

test('Bot legt an: Lehrkraft, falsche Art, falsche Domain – abgelehnt, nichts angelegt', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [
    createJob(TEACHER, 't'), createJob(NEW, 'k', 'parents'), createJob(`neu@andere-schule.example.org`, 'd', 'student'), createJob(NEW, 'p', 'student', 'kurz'),
  ] });
  const { summary } = await runBot(browser, fake, [], { dashboard });
  expect(summary.status).toBe('ok');
  // the address list may be fetched (read-only), nothing is created
  expect(fake.created).toHaveLength(0);
  expect(dashboard.createResults.map((r) => [r.id, r.ok])).toEqual([['t', false], ['k', false], ['d', false], ['p', false]]);
});

const CREATE_STOPS: [string, FakeVariant, RegExp][] = [
  ['Mail Business statt Mail Basic', { businessFirst: true }, /heißt nicht „Mail Basic“/],
  ['Karte heißt anders', { basicHeadline: 'Mail Basic Plus' }, /heißt nicht „Mail Basic“/],
  ['Domain fehlt', { domains: [] }, /nicht genau einmal angeboten/],
  ['Domain doppelt', { domains: ['mail.beispielschule.de', 'mail.beispielschule.de'] }, /nicht genau einmal angeboten/],
  ['Virenschutz vorausgewählt', { extraPrechecked: 'virusProtection' }, /Zusatzoption ist angehakt/],
  ['Archivierung vorausgewählt', { extraPrechecked: 'orderMailArchiving' }, /Zusatzoption ist angehakt/],
  ['KI vorausgewählt', { extraPrechecked: 'ai-checkbox' }, /Zusatzoption ist angehakt/],
  ['Weiterleitung eingetragen', { forwardPrefilled: true }, /Weiterleitungsziel/],
  ['IONOS: Adresse gibt es schon', { createExistsError: true }, /Fehler beim Anlegen/],
  ['Export mit anderen Spalten', { exportHeader: 'Adresse;Typ' }, /unbekannte Spalten/],
  ['Export viel zu kurz', { exportRows: 0 }, /kann nicht stimmen/],
];

for (const [name, variant, reason] of CREATE_STOPS) {
  test(`Bot hält beim Anlegen an: ${name}`, async ({ browser }) => {
    const fake = fakeIonos(MAILBOXES, variant, { loggedIn: true });
    const dashboard = fakeDashboard([], { create: [createJob(NEW), createJob(NEW_PARENTS, 'n2')] });
    const { summary } = await runBot(browser, fake, [], { dashboard });
    expect(summary.status).toBe('stopped');
    expect(summary.reason).toMatch(reason);
    expect(fake.created).toHaveLength(0);
    expect(dashboard.paused).toMatchObject({ reason: expect.stringMatching(reason) });
    // the second one was not touched
    expect(dashboard.createResults.map((r) => r.id)).not.toContain('n2');
  });
}

test('Bot hält an: nach dem Anlegen zeigt IONOS ein anderes Postfach', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES, { createdShows: BEN }, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [createJob(NEW), createJob(NEW_PARENTS, 'n2')] });
  const { summary } = await runBot(browser, fake, [], { dashboard });
  expect(summary.status).toBe('stopped');
  expect(summary.reason).toMatch(/anderes Postfach/);
  expect(fake.created.map((c) => c.address)).toEqual([NEW]);
  expect(dashboard.createResults.map((r) => r.id)).not.toContain('n2');
});

test('Bot legt an: echte Postfächer, seit das Anlegen bestätigt ist', async ({ browser }) => {
  // watched by the maintainer on 2026-11-14; any change to the creation steps sets it back to 'recorded'
  expect(ionos.CREATE_FLOW_STATUS).toBe('verified');
  const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
  const dashboard = fakeDashboard([], { create: [createJob(NEW)] });
  const summary = await run({
    config: botConfig(), state: tmpState(), dashboard, print: () => {},
    imapLoginWorks: async (u: string, p: string) => fake.passwords.get(u) === p,
    openContext: async () => { const c = await browser.newContext(); await fake.install(c); return c; },
  });
  expect(summary.status, summary.reason).toBe('ok');
  expect(dashboard.uploads).toHaveLength(2);
  expect(fake.created.map((c) => c.address)).toEqual([NEW]);
  expect(dashboard.createResults.map((r) => [r.id, r.ok])).toEqual([['n1', true]]);
});

test('Bot wartet angemeldet: ein Weckruf holt neue Fälle sofort, ohne neue Anmeldung', async ({ browser }) => {
  const fake = fakeIonos(MAILBOXES);
  const cases: Case[] = [one(ANNA)];
  const dashboard = fakeDashboard(cases);
  let waits = 0;
  let stop = false;
  // the dashboard wakes the bot while it waits: a new case came in
  const waitForWork = async () => {
    waits += 1;
    if (waits === 1) cases.push(one(BEN, 'case-2'));
    else stop = true;
  };
  const { summary } = await runBot(browser, fake, cases, {
    dashboard, config: botConfig({ linger_minutes: 5 }), waitForWork, shouldStop: () => stop,
  });
  expect(summary.status, summary.reason).toBe('ok');
  expect(fake.resets.map((r) => r.address)).toEqual([ANNA, BEN]);
  expect(attempts(fake)).toBe(1);
  // it told the dashboard when it was waiting and when it worked again
  expect(dashboard.activities).toContain('waiting');
  expect(dashboard.activities.lastIndexOf('working')).toBeGreaterThan(dashboard.activities.indexOf('waiting'));
  expect(dashboard.runHost).toBeNull();
});

test('Bot prüft per IMAP: Stichprobe (das erste Postfach), alle oder keins – sofort, nicht erst nach einer Minute', async ({ browser }) => {
  for (const [verify, expected] of [['sample', [NEW]], ['all', [NEW, NEW_PARENTS]], ['none', []]] as const) {
    const fake = fakeIonos(MAILBOXES, {}, { loggedIn: true });
    const dashboard = fakeDashboard([], { create: [createJob(NEW), createJob(NEW_PARENTS, 'n2', 'parents', PASSWORD_2)] });
    const checked: string[] = [];
    const imap = async (user: string, password: string) => { checked.push(user); return fake.passwords.get(user) === password; };
    // long delays: the first try must work right away
    const config = botConfig({ verify, verify_delays_s: [600], pace: 1 });
    const started = Date.now();
    const { summary } = await runBot(browser, fake, [], { dashboard, config: Object.assign(config, { pace: 0 }), imap });
    expect(summary.status, `${verify}: ${summary.reason}`).toBe('ok');
    expect(checked, verify).toEqual(expected);
    expect(Date.now() - started).toBeLessThan(20000);
    expect(dashboard.createResults.map((r) => r.ok)).toEqual([true, true]);
    expect(dashboard.createResults[1].message).toContain(verify === 'all' ? 'geprüft' : 'von IONOS bestätigt');
  }
});
