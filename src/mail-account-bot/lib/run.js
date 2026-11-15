'use strict';
// One run of the bot: take the run lock on the dashboard (one machine at a
// time), fetch the approved cases, check them, skip mailboxes whose password
// already is the original one (IMAP), ask the maintainer once (in the
// terminal), reset the others in one sitting in the control panel, prove each
// reset by IMAP, report back. Then stay a while (same session) in case the
// admin approves more. At the first surprise: stop and pause the bot on the
// dashboard – for every machine, until the admin lifts it there.
const path = require('path');
const ionos = require('./ionos');
const { Stop, CaseProblem, Postpone, makePacer, watchNavigation, sleep } = require('./guard');

// The bot's own check, independent of the dashboard: only a student's
// mailbox or the parents' eltern.<student> mailbox on the allowed domain,
// the dashboard must say which of the two it is, and it must have been
// approved by one of the approvers in the bot's configuration (the test
// mailbox, id null, comes from the configuration itself).
function caseProblem(c, config) {
    if (!c || (typeof c.id !== 'string' && c.id !== null) || !Array.isArray(c.mailboxes) || c.mailboxes.length === 0) return 'Unvollständiger Fall vom Dashboard';
    if (c.id !== null && !(typeof c.approved_by === 'string' && config.approvers.includes(c.approved_by.toLowerCase()))) {
        return `Freigegeben von ${c.approved_by || 'unbekannt'} – der Bot führt nur Freigaben von ${config.approvers.join(', ')} aus. Zum Ausführen selbst noch einmal freigeben („Erneut versuchen“).`;
    }
    for (const m of c.mailboxes) {
        if (typeof m.mailbox !== 'string' || m.mailbox !== m.mailbox.trim().toLowerCase()) return 'Ungültige Adresse vom Dashboard';
        if (!config.allowed_mailboxes_re.test(m.mailbox)) return `${m.mailbox}: der Bot setzt nur Schüler- und Eltern-Postfächer zurück`;
        const parents = m.mailbox.startsWith('eltern.');
        if (m.kind !== (parents ? 'parents' : 'student')) return `${m.mailbox}: laut Dashboard kein ${parents ? 'Eltern' : 'Schüler'}-Postfach`;
        if (typeof m.password !== 'string' || !/^[A-Za-z0-9-]{8,64}$/.test(m.password)) return 'Ungeeignetes Passwort vom Dashboard';
    }
    return null;
}

// the same check for a mailbox to create
function createProblem(c, config) {
    if (!c || typeof c.id !== 'string') return 'Unvollständiger Auftrag vom Dashboard';
    return caseProblem({ id: c.id, approved_by: c.approved_by, mailboxes: [{ mailbox: c.mailbox, kind: c.kind, password: c.password }] }, config);
}

// "anna@… (freigegeben von x@…, 15.11.2026, 13:05)" for the question in the terminal
function withApproval(mailbox, c) {
    if (c.id === null || !c.approved_by) return mailbox;
    const when = typeof c.approved_at === 'number' ? `, ${new Date(c.approved_at * 1000).toLocaleString('de-DE', { dateStyle: 'medium', timeStyle: 'short' })}` : '';
    return `${mailbox} (freigegeben von ${c.approved_by}${when})`;
}

// options: config, state, dashboard, imapLoginWorks(user, password),
// openContext() -> BrowserContext, confirm(lines) -> bool, dryRun,
// testMailbox, testing, notify(text), print(line)
async function run(options) {
    const { config, state, dashboard, imapLoginWorks, openContext, dryRun = false, testMailbox = false, testing = false } = options;
    const notify = options.notify || (() => {});
    const print = options.print || ((line) => console.log(line));
    const confirm = options.confirm || (async () => true);
    // Ctrl+C in background mode: no new work, leave the waiting time early
    const shouldStop = options.shouldStop || (() => false);
    // background mode: resolves early when the dashboard wakes the bot
    const waitForWork = options.waitForWork || ((ms) => sleep(ms));
    const log = (message) => { state.log(message); print(message); };
    const summary = { status: 'ok', done: [], failed: [], postponed: [], dryRun: [], created: [], createFailed: [] };

    if (!testing) {
        if (ionos.FLOW_STATUS === 'provisional') throw new Error('Der Ablauf auf der IONOS-Seite ist noch nicht mit dem Maintainer aufgenommen (lib/ionos.js, FLOW_STATUS). Erst `bot.js record`.');
        if (ionos.FLOW_STATUS === 'recorded' && !dryRun && !testMailbox) throw new Error('Der Ablauf ist aufgenommen, aber noch nicht bestätigt: nur --dry-run oder --test-mailbox.');
    }
    if (testMailbox && !config.test_mailbox) throw new Error('Kein test_mailbox in der Konfiguration');
    if (config.dashboard_is_local && !testMailbox) throw new Error('Mit der lokalen Entwicklungsinstanz als Dashboard nur --test-mailbox (sie enthält eine Kopie echter Fälle).');

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
            notify('Postfach-Bot: Ergebnis konnte nicht ans Dashboard gemeldet werden – siehe Log');
        }
    };

    const openSession = async () => {
        context = await openContext();
        page = context.pages()[0] || await context.newPage();
        const guard = watchNavigation(context, page, ionos.HOSTS);
        session = new ionos.IonosSession({ page, config, state, dashboard, pacer, guard, log: (m) => log(m) });
        try {
            await session.openMailboxList();
        } catch (err) {
            // not logged in after all: no session to keep (a stop keeps the page for the screenshot)
            if (err instanceof Postpone) {
                await context.close().catch(() => {});
                context = session = page = null;
            }
            throw err;
        }
    };

    // at the first surprise: screenshot, pause on the dashboard, tell the admin
    const halt = async (stop, failCurrent) => {
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
        if (failCurrent) await failCurrent(`Der Bot hat angehalten: ${stop.message}`);
        notify(`Postfach-Bot angehalten: ${stop.message}`);
    };

    // IMAP proof for several mailboxes at once: a first try right away, the
    // ones that don't work yet again after each of verify_delays_s.
    // Returns the mailboxes that never worked.
    const verifyMany = async (items) => {
        if (items.length === 0) return [];
        const total = config.verify_delays_s.reduce((a, b) => a + b, 0);
        log(`Prüfe per IMAP: ${items.map((m) => m.mailbox).join(', ')} (falls IONOS noch nicht so weit ist: höchstens ${Math.round(total / 60)} min)`);
        let open = items;
        for (const [i, delay] of [0, ...config.verify_delays_s].entries()) {
            if (delay) await sleep(delay * 1000 * config.pace);
            const results = [];
            for (let k = 0; k < open.length; k += 4) {
                const chunk = open.slice(k, k + 4);
                results.push(...await Promise.all(chunk.map((m) => imapLoginWorks(m.mailbox, m.password).catch(() => false))));
            }
            open = open.filter((_, k) => !results[k]);
            log(`  Versuch ${i + 1}: ${open.length === 0 ? 'Anmeldung klappt' : `noch nicht: ${open.length}`}`);
            if (open.length === 0) break;
        }
        return open.map((m) => m.mailbox);
    };
    // which of the changed mailboxes get the IMAP proof: 'sample' (the first
    // of the sitting), 'all' or 'none'; the others count on IONOS's confirmation
    let sampled = false;
    const pickForVerify = (items) => {
        if (config.verify === 'all') return items;
        if (config.verify === 'none' || sampled || items.length === 0) return [];
        sampled = true;
        return items.slice(0, 1);
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
        const mailboxes = work.flatMap((c) => c.toReset.map((m) => withApproval(m.mailbox, c)));
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
        const checked = pickForVerify(toVerify.flatMap((c) => c.toReset));
        const failedNow = new Set(await verifyMany(checked));
        const checkedSet = new Set(checked.map((m) => m.mailbox));
        for (const c of toVerify) {
            const failed = c.toReset.find((m) => failedNow.has(m.mailbox));
            if (failed) {
                await report(c, false, `IONOS hat die Änderung bestätigt, aber ${failed.mailbox} nimmt das neue Passwort nicht an. Bitte von Hand prüfen.`);
                stop = stop || new Stop(`Nach dem Zurücksetzen nimmt ${failed.mailbox} das neue Passwort nicht an`);
            } else {
                await report(c, true, c.toReset.some((m) => checkedSet.has(m.mailbox))
                    ? 'Bei IONOS zurückgesetzt, Anmeldung mit dem ursprünglichen Passwort geprüft.'
                    : 'Bei IONOS zurückgesetzt (von IONOS bestätigt).');
            }
        }

        if (stop) {
            await halt(stop, stoppedCase && !handled.has(stoppedCase.id)
                ? (text) => report(stoppedCase, false, `${text}. Bitte von Hand zurücksetzen.`) : null);
            return false;
        }
        return true;
    };

    // creating mailboxes: the address list first (fresh from the provider),
    // then only what is still missing; returns false if the bot stopped
    const reportCreate = async (c, ok, message) => {
        handled.add(`create:${c.id}`);
        (ok ? summary.created : summary.createFailed).push({ id: c.id, mailbox: c.mailbox, message });
        log(`${ok ? 'Angelegt' : 'Nicht angelegt'}: ${c.mailbox} – ${message}`);
        if (dryRun) return;
        try {
            await dashboard.createResult(c.id, ok, message);
        } catch (err) {
            summary.unreported = (summary.unreported || 0) + 1;
            log(`Dashboard nicht erreichbar, Ergebnis nicht gemeldet: ${err.message}`);
        }
    };
    let exported = false;
    const processCreation = async () => {
        const work = await dashboard.creation();
        if (work.paused) return false;
        const cases = [];
        for (const c of work.create.filter((x) => !handled.has(`create:${x.id}`))) {
            const problem = createProblem(c, config);
            if (problem) { await reportCreate(c, false, problem); continue; }
            cases.push(c);
        }
        const mayCreate = dryRun || testing || ionos.CREATE_FLOW_STATUS === 'verified';
        if (cases.length > 0 && !mayCreate) {
            log(`${cases.length} Postfach/Postfächer zum Anlegen freigegeben – das Anlegen ist noch nicht bestätigt, erst \`run --dry-run\``);
        }
        // the address list at most once per run
        const listWanted = work.address_list.wanted && !exported;
        if (!listWanted && (cases.length === 0 || !mayCreate)) return true;
        const toCreate = mayCreate ? cases : [];
        if (toCreate.length > 0 && !(await confirm([`${dryRun ? 'Probelauf (nichts wird angelegt)' : 'Bei IONOS anlegen'}: ${toCreate.length} Postfach/Postfächer`, ...toCreate.map((c) => withApproval(c.mailbox, c))]))) {
            log('Nicht bestätigt – die Postfächer bleiben freigegeben');
            for (const c of toCreate) handled.add(`create:${c.id}`);
            summary.status = 'not_confirmed';
            return false;
        }
        let current = null;
        const created = [];
        try {
            if (session) await session.openMailboxList(); else await openSession();
            const rows = await session.exportAddresses();
            exported = true;
            if (!dryRun) {
                await dashboard.uploadAddressList(rows);
                log('Adressliste ans Dashboard geschickt');
            }
            summary.addressList = rows.length;
            const existing = new Set(rows.map((r) => r.address));
            for (const c of toCreate) {
                current = c;
                // the fresh list has it already: the dashboard marked it when the list arrived
                if (existing.has(c.mailbox)) { handled.add(`create:${c.id}`); log(`Gibt es schon: ${c.mailbox}`); continue; }
                await session.createMailbox(c.mailbox, c.password, { dryRun });
                if (dryRun) { handled.add(`create:${c.id}`); summary.dryRun.push(c.id); continue; }
                created.push(c);
                await dashboard.claim(config.host).catch(() => {});
            }
            current = null;
        } catch (err) {
            if (err instanceof Postpone) { log(err.message); return true; }
            const stop = err instanceof Stop ? err : new Stop(`Unerwarteter Fehler: ${err.message}`);
            await verifyCreated(created);
            await halt(stop, current ? (text) => reportCreate(current, false, `${text}. Bitte von Hand prüfen.`) : null);
            return false;
        }
        const ok = await verifyCreated(created);
        if (!ok) {
            await halt(new Stop('Ein neues Postfach nimmt sein Passwort nicht an'), null);
            return false;
        }
        // the provider's list after the work, so the dashboard compares with what is really there
        if (created.length > 0) {
            try {
                const after = await session.exportAddresses();
                const missingNow = created.filter((c) => !after.some((r) => r.address === c.mailbox));
                if (missingNow.length > 0) {
                    await halt(new Stop(`Nach dem Anlegen fehlt ${missingNow[0].mailbox} in der Adressliste`), null);
                    return false;
                }
                await dashboard.uploadAddressList(after);
                log('Aktuelle Adressliste ans Dashboard geschickt');
            } catch (err) {
                if (err instanceof Stop) { await halt(err, null); return false; }
                log(`Aktuelle Adressliste nicht geschickt: ${err.message}`);
            }
        }
        return true;
    };
    // new mailboxes: the chosen ones must accept their password (IMAP);
    // returns false if one doesn't
    const verifyCreated = async (created) => {
        const checked = pickForVerify(created.map((c) => ({ mailbox: c.mailbox, password: c.password })));
        const failed = new Set(await verifyMany(checked));
        const checkedSet = new Set(checked.map((m) => m.mailbox));
        for (const c of created) {
            if (failed.has(c.mailbox)) {
                await reportCreate(c, false, 'IONOS hat das Anlegen bestätigt, aber die Anmeldung mit dem Passwort klappt nicht. Bitte von Hand prüfen.');
            } else {
                await reportCreate(c, true, checkedSet.has(c.mailbox)
                    ? 'Bei IONOS angelegt, Anmeldung mit dem Passwort aus dem E-Mail-Brief geprüft.'
                    : 'Bei IONOS angelegt (von IONOS bestätigt).');
            }
        }
        return failed.size === 0;
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
        // in the background (woken or every few minutes) only when there is something
        if (cases.length > 0 || !options.waitForWork) log(`${cases.length} freigegebene(r) Fall/Fälle${dryRun ? ' (Probelauf, nichts wird geändert)' : ''}`);
        let going = await processCases(cases);
        if (going && !testMailbox) going = await processCreation();
        // stay a while with the open session, in case the admin approves more
        const until = Date.now() + config.linger_minutes * 60 * 1000;
        if (going && session && !dryRun && !testMailbox && config.linger_minutes > 0) {
            log(`Bleibt bis ${new Date(until).toLocaleTimeString('de-DE', { hour: '2-digit', minute: '2-digit' })} angemeldet und wartet auf weitere Aufträge`);
        }
        while (going && session && !dryRun && !testMailbox && Date.now() < until && !shouldStop()) {
            await dashboard.claim(config.host, 'waiting', Math.round(until / 1000)).catch(() => {});
            const next = Math.min(until, Date.now() + config.poll_minutes * 60 * 1000);
            await waitForWork(Math.max(1, next - Date.now()));
            if (shouldStop() || Date.now() >= until) break;
            await dashboard.claim(config.host, 'working').catch(() => {});
            const pending = await dashboard.pending();
            if (pending.paused) break;
            cases = pending.cases.filter((c) => !handled.has(c.id));
            if (cases.length > 0) {
                log(`${cases.length} weitere(r) Fall/Fälle`);
                going = await processCases(cases);
            }
            if (going) going = await processCreation();
        }
        if (session && !dryRun && !testMailbox && config.linger_minutes > 0) log('Wartezeit vorbei, meldet sich bei IONOS ab');
        return summary;
    } finally {
        if (context) await context.close().catch(() => {});
        await dashboard.release(config.host).catch(() => {});
        state.unlock();
    }
}

module.exports = { run, caseProblem, createProblem };
