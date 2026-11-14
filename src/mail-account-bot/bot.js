#!/usr/bin/env node
'use strict';
// Mail account bot (Postfach-Bot) – runs only on the maintainer's machines (README.md).
//
//   node bot.js check [--imap]         configuration, TOTP code to compare with the app, dashboard token
//   node bot.js record                 open the bot's browser; you log in and click through, the structure is recorded
//   node bot.js run --dry-run          everything up to the form, then "Abbrechen" – nothing is changed
//                                      (Chrome runs invisibly; add --show to watch it)
//   node bot.js run --test-mailbox     reset the test mailbox (two passwords take turns)
//   node bot.js run                    approved cases from the dashboard, once
//   node bot.js serve                  in the background: woken by the dashboard (websocket), asks every 15 minutes too
//   node bot.js status
const { execFile } = require('child_process');
const { loadConfig, STATE_DIR, CONFIG_FILE } = require('./lib/config');
const { State } = require('./lib/state');
const { totpAt } = require('./lib/totp');
const { imapLoginWorks } = require('./lib/imap');
const { dashboardClient } = require('./lib/dashboard');
const ionos = require('./lib/ionos');

function notify(text) {
    execFile('notify-send', ['--urgency=critical', 'Postfach-Bot', text], () => {});
}

// the question in the terminal; without a terminal the answer is no
async function confirmInTerminal(lines) {
    if (!process.stdin.isTTY) return false;
    const readline = require('readline');
    console.log(lines.map((line, i) => (i === 0 ? line : `  ${line}`)).join('\n'));
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const answer = await new Promise((resolve) => rl.question('Ausführen? [j/N] ', resolve));
    rl.close();
    return /^j/i.test(answer.trim());
}

// The same Chrome and profile as when you log in yourself. In the background
// (default) without a window, so nothing takes the focus; --show to watch.
// Invisible Chrome calls itself "HeadlessChrome" – it sends the normal
// identifier of this Chrome version instead, as on your own logins.
function chromeUserAgent() {
    const version = require('child_process').execFileSync('google-chrome', ['--version'], { encoding: 'utf8' });
    const major = (/(\d+)\./.exec(version) || [])[1];
    if (!major) throw new Error('Chrome-Version nicht erkannt');
    return `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${major}.0.0.0 Safari/537.36`;
}

async function openContext(config, state, { show = false } = {}) {
    const { chromium } = require('playwright-core');
    const options = { channel: config.chrome_channel, locale: 'de-DE' };
    if (show) Object.assign(options, { headless: false, viewport: null });
    else Object.assign(options, { headless: true, viewport: { width: 1280, height: 900 }, userAgent: chromeUserAgent() });
    return chromium.launchPersistentContext(state.profileDir, options);
}

async function main() {
    const [command, ...flags] = process.argv.slice(2);
    if (!command || command === 'help' || command === '--help') {
        console.log(require('fs').readFileSync(__filename, 'utf8').split('\n').slice(2, 11).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
        return;
    }
    // recording needs no access data (you type them yourself), only the machine
    const config = loadConfig({ recordingOnly: command === 'record' });
    const state = new State(STATE_DIR);
    if (command === 'record') {
        const { record } = require('./lib/record');
        state.lock();
        try {
            // recording: you click yourself, so always with a window
            const context = await openContext(config, state, { show: true });
            await record({ context, state, testMailbox: config.test_mailbox });
        } finally { state.unlock(); }
        return;
    }
    const imap = (user, password) => imapLoginWorks({ host: config.imap_host, port: config.imap_port }, user, password);
    const dashboard = dashboardClient({ url: config.dashboard_url, token: config.dashboard_token });

    if (command === 'check') {
        console.log(`Konfiguration: ${CONFIG_FILE} – in Ordnung`);
        console.log(`Rechner: ${config.host} (erlaubt: ${config.hosts.join(', ')}), Zustand: ${STATE_DIR}`);
        console.log(`IONOS-Ablauf: ${ionos.FLOW_STATUS}`);
        if (config.ionos_2fa) {
            const t = totpAt(config.totp);
            console.log(`TOTP jetzt: ${t.code} (noch ${t.remaining} s) – stimmt das mit der Authenticator-App überein?`);
        } else {
            console.log('IONOS-Anmeldung ohne zweiten Faktor (ionos_2fa: false) – nur bis 2FA eingerichtet ist');
        }
        if (config.dashboard_is_local) console.log('Dashboard: lokale Entwicklungsinstanz – nur --test-mailbox');
        const pending = await dashboard.pending();
        console.log(`Dashboard: Token gilt, ${pending.cases.length} freigegebene(r) Fall/Fälle${pending.paused ? `, ANGEHALTEN: ${pending.paused.reason}` : ''}`);
        if (config.test_mailbox && flags.includes('--imap')) {
            const works = await Promise.all(config.test_mailbox_passwords.map((pw) => imap(config.test_mailbox, pw).catch((e) => e.message)));
            console.log(`IMAP Test-Postfach: Passwort 1 ${works[0]}, Passwort 2 ${works[1]}`);
        }
        console.log(`Heute auf diesem Rechner: ${JSON.stringify(state.counters())}`);
        return;
    }
    if (command === 'status') {
        const pending = await dashboard.pending();
        console.log(pending.paused ? `ANGEHALTEN seit ${new Date(pending.paused.ts * 1000).toLocaleString('de-DE')}: ${pending.paused.reason}` : 'Nicht angehalten');
        const stop = state.lastStop();
        if (stop) console.log(`Letzter Halt auf diesem Rechner (${stop.ts}): ${stop.reason}${stop.screenshot ? `\nBildschirmfoto: ${stop.screenshot}` : ''}`);
        console.log(`Freigegebene Fälle: ${pending.cases.length}, heute auf diesem Rechner: ${JSON.stringify(state.counters())}, Log: ${state.logFile}`);
        return;
    }
    if (command === 'resume') {
        console.log('Freigeben geht nur im Dashboard, auf der Seite „Passwörter“ (Administration).');
        return;
    }
    const runOnce = (opts = {}) => require('./lib/run').run({
        config, state, dashboard, imapLoginWorks: imap, notify,
        confirm: config.confirm ? confirmInTerminal : undefined,
        openContext: () => openContext(config, state, { show: flags.includes('--show') }), ...opts,
    });
    if (command === 'run') {
        const summary = await runOnce({ dryRun: flags.includes('--dry-run'), testMailbox: flags.includes('--test-mailbox') });
        console.log(JSON.stringify({ status: summary.status, done: summary.done.length, failed: summary.failed.length, postponed: summary.postponed.length, dryRun: summary.dryRun.length }));
        process.exitCode = summary.status === 'ok' ? 0 : 2;
        return;
    }
    if (command === 'serve') {
        const log = (message) => { state.log(message); console.log(`${new Date().toLocaleTimeString('de-DE')} ${message}`); };
        await require('./lib/serve').serve({ config, runOnce: () => runOnce(), log }).loop;
        return;
    }
    throw new Error(`Unbekannter Befehl: ${command}`);
}

main().catch((err) => { console.error(err.message); process.exitCode = 1; });
