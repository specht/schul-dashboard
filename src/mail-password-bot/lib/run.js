'use strict';
// One run of the bot: take the run lock on the dashboard (one machine at a
// time), fetch the approved cases, check them, skip mailboxes whose password
// already is the original one (IMAP), ask the maintainer once (desktop
// question), reset the others in one sitting in the control panel, prove each
// reset by IMAP, report back. Then stay a while (same session) in case the
// admin approves more. At the first surprise: stop and pause the bot on the
// dashboard – for every machine, until the admin lifts it there.
const path = require('path');
const ionos = require('./ionos');
const { Stop, CaseProblem, Postpone, makePacer, watchNavigation, sleep } = require('./guard');

// The bot's own check, independent of the dashboard: only a student's
// mailbox or the parents' eltern.<student> mailbox on the allowed domain,
// and the dashboard must say which of the two it is.
function caseProblem(c, config) {
    if (!c || (typeof c.id !== 'string' && c.id !== null) || !Array.isArray(c.mailboxes) || c.mailboxes.length === 0) return 'Unvollständiger Fall vom Dashboard';
    for (const m of c.mailboxes) {
        if (typeof m.mailbox !== 'string' || m.mailbox !== m.mailbox.trim().toLowerCase()) return 'Ungültige Adresse vom Dashboard';
        if (!config.allowed_mailboxes_re.test(m.mailbox)) return `${m.mailbox}: der Bot setzt nur Schüler- und Eltern-Postfächer zurück`;
        const parents = m.mailbox.startsWith('eltern.');
        if (m.kind !== (parents ? 'parents' : 'student')) return `${m.mailbox}: laut Dashboard kein ${parents ? 'Eltern' : 'Schüler'}-Postfach`;
        if (typeof m.password !== 'string' || !/^[A-Za-z0-9-]{8,64}$/.test(m.password)) return 'Ungeeignetes Passwort vom Dashboard';
    }
    return null;
}

// options: config, state, dashboard, imapLoginWorks(user, password),
// openContext() -> BrowserContext, confirm(lines) -> bool, dryRun,
// testMailbox, testing, notify(text), print(line)
async function run(options) {
    const { config, state, dashboard, imapLoginWorks, openContext, dryRun = false, testMailbox = false, testing = false } = options;
    const notify = options.notify || (() => {});
    const print = options.print || ((line) => console.log(line));
    const confirm = options.confirm || (async () => true);
    const log = (message) => { state.log(message); print(message); };
    const summary = { status: 'ok', done: [], failed: [], postponed: [], dryRun: [] };

    if (!testing) {
        if (ionos.FLOW_STATUS === 'provisional') throw new Error('Der Ablauf auf der IONOS-Seite ist noch nicht mit dem Maintainer aufgenommen (lib/ionos.js, FLOW_STATUS). Erst `bot.js record`.');
        if (ionos.FLOW_STATUS === 'recorded' && !dryRun && !testMailbox) throw new Error('Der Ablauf ist aufgenommen, aber noch nicht bestätigt: nur --dry-run oder --test-mailbox.');
    }
    if (testMailbox && !config.test_mailbox) throw new Error('Kein test_mailbox in der Konfiguration');

    const claim = await dashboard.claim(config.host);
    if (claim.result === 'paused') {
        log(`Der Bot ist angehalten: ${claim.reason}. Freigeben auf der Seite „Passwörter“ im Dashboard.`);
        return { ...summary, status: 'paused', reason: claim.reason };
    }
    if (claim.result === 'busy') {
        log(`Der Bot läuft gerade auf dem Rechner ${claim.host}.`);
        return { ...summary, status: 'busy' };
    }

    state.lock();
    const pacer = makePacer(config.pace);
    const handled = new Set();
    let context = null, session = null, page = null;
    const report = async (c, ok, message) => {
        handled.add(c.id);
        (ok ? summary.done : summary.failed).push({ id: c.id, mailboxes: c.mailboxes.map((m) => m.mailbox), message });
        log(`${ok ? 'Erledigt' : 'Nicht erledigt'}: ${c.mailboxes.map((m) => m.mailbox).join(', ')} – ${message}`);
        if (c.id === null || dryRun) return;
        try {
            const result = await dashboard.report(c.id, ok, message);
            if (result !== 'ok') log(`Dashboard: Fall war nicht mehr freigegeben (${result})`);
        } catch (err) {
            // keep going (and stopping, if that's what happens): the log has it
            summary.unreported = (summary.unreported || 0) + 1;
            log(`Dashboard nicht erreichbar, Ergebnis nicht gemeldet: ${err.message}`);
            notify('Passwort-Bot: Ergebnis konnte nicht ans Dashboard gemeldet werden – siehe Log');
        }
    };

    const openSession = async () => {
        context = await openContext();
        page = context.pages()[0] || await context.newPage();
        const guard = watchNavigation(context, page, ionos.HOSTS);
        session = new ionos.IonosSession({ page, config, state, dashboard, pacer, guard, log: (m) => log(m) });
        await session.openMailboxList();
    };

    const verify = async (c) => {
        for (const m of c.toReset) {
            let works = false;
            for (const delay of config.verify_delays_s) {
                await sleep(delay * 1000 * config.pace);
                works = await imapLoginWorks(m.mailbox, m.password).catch(() => false);
                if (works) break;
            }
            if (!works) return m.mailbox;
        }
        return null;
    };

    // one batch of cases; returns false if the bot stopped
    const processCases = async (cases) => {
        const work = [];
        for (const c of cases) {
            if (handled.has(c.id)) continue;
            const problem = caseProblem(c, config);
            if (problem) { await report(c, false, problem); continue; }
            c.toReset = [];
            for (const m of c.mailboxes) {
                const already = !dryRun && await imapLoginWorks(m.mailbox, m.password).catch(() => false);
                if (!already) c.toReset.push(m);
            }
            if (c.toReset.length === 0) {
                await report(c, true, 'Das Passwort war schon das ursprüngliche (Anmeldung per IMAP geprüft), bei IONOS nichts geändert.');
                continue;
            }
            work.push(c);
        }
        if (work.length === 0) return true;

        // the maintainer's last word, on his own machine
        const mailboxes = work.flatMap((c) => c.toReset.map((m) => m.mailbox));
        if (!(await confirm([`${dryRun ? 'Probelauf (nichts wird geändert)' : 'Bei IONOS zurücksetzen'}: ${mailboxes.length} Postfach/Postfächer`, ...mailboxes]))) {
            log('Nicht bestätigt – die Fälle bleiben freigegeben');
            for (const c of work) { handled.add(c.id); summary.postponed.push(c.id); }
            summary.status = 'not_confirmed';
            return false;
        }

        const toVerify = [];
        let stop = null, stoppedCase = null;
        try {
            // a stop while logging in is reported on the first case, so the admin gets a mail
            stoppedCase = work[0];
            if (session) await session.openMailboxList(); else await openSession();
            for (const c of work) {
                stoppedCase = c;
                try {
                    for (const m of c.toReset) {
                        await session.resetPassword(m.mailbox, m.password, { dryRun });
                    }
                } catch (err) {
                    if (!(err instanceof CaseProblem)) throw err;
                    await report(c, false, err.message);
                    continue;
                }
                if (dryRun) { handled.add(c.id); summary.dryRun.push(c.id); continue; }
                toVerify.push(c);
                // the lock lasts 10 minutes; renew it while working
                await dashboard.claim(config.host).catch(() => {});
            }
            stoppedCase = null;
        } catch (err) {
            if (err instanceof Postpone) {
                log(err.message);
                for (const c of work) if (!handled.has(c.id) && !toVerify.includes(c)) { summary.postponed.push(c.id); handled.add(c.id); }
            } else {
                stop = err instanceof Stop ? err : new Stop(`Unerwarteter Fehler: ${err.message}`);
            }
        }

        // resets IONOS confirmed: prove them (IMAP doesn't touch the control panel)
        for (const c of toVerify) {
            const failed = await verify(c);
            if (failed) {
                await report(c, false, `IONOS hat die Änderung bestätigt, aber ${failed} nimmt das neue Passwort nicht an. Bitte von Hand prüfen.`);
                stop = stop || new Stop(`Nach dem Zurücksetzen nimmt ${failed} das neue Passwort nicht an`);
            } else {
                await report(c, true, 'Bei IONOS zurückgesetzt, Anmeldung mit dem ursprünglichen Passwort geprüft.');
            }
        }

        if (stop) {
            let screenshot = null;
            if (page) {
                screenshot = path.join(state.screenshotsDir, `${new Date().toISOString().replace(/[:.]/g, '-')}.png`);
                await page.screenshot({ path: screenshot, fullPage: true }).catch(() => { screenshot = null; });
            }
            state.recordStop(stop.message, { screenshot });
            summary.status = 'stopped';
            summary.reason = stop.message;
            log(`ANGEHALTEN: ${stop.message}${screenshot ? ` (Bildschirmfoto: ${screenshot})` : ''}`);
            try {
                await dashboard.pause(config.host, stop.message);
            } catch (err) {
                log(`Dashboard nicht erreichbar, Anhalten nicht gemeldet: ${err.message}`);
            }
            if (stoppedCase && !handled.has(stoppedCase.id)) {
                await report(stoppedCase, false, `Der Bot hat angehalten: ${stop.message}. Bitte von Hand zurücksetzen.`);
            }
            notify(`Passwort-Bot angehalten: ${stop.message}`);
            return false;
        }
        return true;
    };

    try {
        let cases;
        if (testMailbox) {
            // two passwords take turns, so every test run really changes something
            const [a, b] = config.test_mailbox_passwords;
            const password = (await imapLoginWorks(config.test_mailbox, a).catch(() => false)) ? b : a;
            const kind = config.test_mailbox.startsWith('eltern.') ? 'parents' : 'student';
            cases = [{ id: null, mailboxes: [{ mailbox: config.test_mailbox, kind, password }] }];
        } else {
            const pending = await dashboard.pending();
            if (pending.paused) {
                log(`Der Bot ist angehalten: ${pending.paused.reason}`);
                return { ...summary, status: 'paused', reason: pending.paused.reason };
            }
            cases = pending.cases;
        }
        log(`${cases.length} freigegebene(r) Fall/Fälle${dryRun ? ' (Probelauf, nichts wird geändert)' : ''}`);
        let going = await processCases(cases);
        // stay a while with the open session, in case the admin approves more
        const until = Date.now() + config.linger_minutes * 60 * 1000;
        while (going && session && !dryRun && !testMailbox && Date.now() < until) {
            await sleep(config.poll_minutes * 60 * 1000);
            await dashboard.claim(config.host).catch(() => {});
            const pending = await dashboard.pending();
            if (pending.paused) break;
            cases = pending.cases.filter((c) => !handled.has(c.id));
            if (cases.length === 0) continue;
            log(`${cases.length} weitere(r) Fall/Fälle`);
            going = await processCases(cases);
        }
        return summary;
    } finally {
        if (context) await context.close().catch(() => {});
        await dashboard.release(config.host).catch(() => {});
        state.unlock();
    }
}

module.exports = { run, caseProblem };
