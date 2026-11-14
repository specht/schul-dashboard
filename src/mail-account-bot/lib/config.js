'use strict';
// The bot's configuration: a JSON file outside the repository, readable only
// by its owner, on the one machine named in it. Without it the bot does not
// start – that is what keeps anybody else (or a copy of the checkout) from
// running it.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseTotpSecret } = require('./totp');

// in ~/.ssh, which the maintainer keeps (backed up) – the TOTP secret must not get lost
const CONFIG_DIR = path.join(os.homedir(), '.ssh', 'gyst-mail-account-bot');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');
const STATE_DIR = path.join(os.homedir(), '.local', 'state', 'gyst-mail-account-bot');

const DEFAULTS = {
    imap_host: 'imap.ionos.de',
    imap_port: 993,
    // this machine's own limit; the dashboard counts all machines together
    // (10 a day, the admin can reset that count on the page)
    max_logins_per_day: 5,
    linger_minutes: 20,
    poll_minutes: 3,
    // background mode: besides the websocket wake-up, ask this often
    fallback_poll_minutes: 15,
    // a question in the terminal before every sitting
    confirm: true,
    // after a reset: check the new password by IMAP after these delays
    // (IONOS: "takes effect within a few minutes")
    verify_delays_s: [60, 120, 240],
    // human pace; 0 only in tests
    pace: 1,
    timeout_ms: 30000,
    totp_min_remaining_s: 8,
    chrome_channel: 'chrome',
};

const REQUIRED = ['dashboard_url', 'dashboard_token', 'ionos_login', 'ionos_password', 'allowed_mailboxes'];

function checkFileIsPrivate(file, what) {
    const st = fs.statSync(file);
    if (st.uid !== process.getuid()) throw new Error(`${what} gehört nicht dem aktuellen Benutzer: ${file}`);
    if (st.mode & 0o077) throw new Error(`${what} ist für andere lesbar (chmod ${st.isDirectory() ? '700' : '600'} ${file})`);
}

// checks that don't need the file system; also used by the tests
// "host": "home-pc" or "hosts": ["home-pc", "laptop"] – the machines it may run on
function checkHost(config, hostname) {
    const hosts = Array.isArray(config.hosts) ? config.hosts : (config.host ? [config.host] : []);
    if (hosts.length === 0) throw new Error('Konfiguration: hosts fehlt (Namen der Rechner, auf denen der Bot laufen darf)');
    if (!hosts.every((h) => /^[A-Za-z0-9._-]{1,64}$/.test(String(h)))) throw new Error('Konfiguration: ungültiger Rechnername in hosts');
    if (!hosts.includes(hostname)) throw new Error(`Dieser Bot läuft nur auf ${hosts.map((h) => `„${h}“`).join(', ')}, nicht auf „${hostname}“.`);
    config.hosts = hosts;
    config.host = hostname;
}

function validateConfig(raw, { hostname = os.hostname(), recordingOnly = false } = {}) {
    const config = { ...DEFAULTS, ...raw };
    if (recordingOnly) {
        checkHost(config, hostname);
        if (config.test_mailbox !== undefined) config.test_mailbox = String(config.test_mailbox).toLowerCase();
        return config;
    }
    for (const key of REQUIRED) {
        if (config[key] === undefined || config[key] === null || config[key] === '') throw new Error(`Konfiguration: ${key} fehlt`);
    }
    checkHost(config, hostname);
    // the local dev instance only for test runs (it holds a copy of real cases)
    config.dashboard_is_local = /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(config.dashboard_url);
    if (!config.dashboard_is_local && !/^https:\/\/[^/]+$/.test(config.dashboard_url)) throw new Error('Konfiguration: dashboard_url muss https://host sein (ohne / am Ende) oder die lokale Entwicklungsinstanz');
    if (String(config.dashboard_token).length < 32) throw new Error('Konfiguration: dashboard_token ist zu kurz');
    const pattern = String(config.allowed_mailboxes);
    if (!pattern.startsWith('^') || !pattern.endsWith('$') || !pattern.includes('@')) {
        throw new Error('Konfiguration: allowed_mailboxes muss ein verankerter Ausdruck mit Domain sein (^…@…$)');
    }
    config.allowed_mailboxes_re = new RegExp(pattern);
    // the IONOS login with a second factor – false only while it isn't set up
    // yet; then the bot stops if IONOS asks for a code after all
    if (config.ionos_2fa === undefined) config.ionos_2fa = true;
    if (typeof config.ionos_2fa !== 'boolean') throw new Error('Konfiguration: ionos_2fa muss true oder false sein');
    if (config.ionos_2fa) {
        if (!config.totp_secret) throw new Error('Konfiguration: totp_secret fehlt');
        config.totp = parseTotpSecret(config.totp_secret);
    }
    if (config.test_mailbox !== undefined) {
        if (!config.allowed_mailboxes_re.test(config.test_mailbox)) throw new Error('Konfiguration: test_mailbox passt nicht zu allowed_mailboxes');
        const passwords = config.test_mailbox_passwords;
        if (!Array.isArray(passwords) || passwords.length !== 2 || passwords[0] === passwords[1] ||
            !passwords.every((pw) => /^[A-Za-z0-9-]{12,64}$/.test(String(pw)))) {
            throw new Error('Konfiguration: test_mailbox_passwords muss zwei verschiedene Passwörter haben (12–64 Zeichen A-Z, a-z, 0-9, -)');
        }
    }
    if (config.pace !== 1) throw new Error('Konfiguration: pace ist nur in Tests veränderbar');
    // limits can be lowered, not raised beyond what a careful person would do
    const within = (key, min, max) => {
        if (!(Number.isInteger(config[key]) && config[key] >= min && config[key] <= max)) throw new Error(`Konfiguration: ${key} muss zwischen ${min} und ${max} liegen`);
    };
    within('max_logins_per_day', 1, 10);
    within('fallback_poll_minutes', 5, 60);
    if (typeof config.confirm !== 'boolean') throw new Error('Konfiguration: confirm muss true oder false sein');
    within('linger_minutes', 0, 60);
    within('poll_minutes', 2, 30);
    within('timeout_ms', 10000, 120000);
    within('totp_min_remaining_s', 5, 20);
    if (!Array.isArray(config.verify_delays_s) || config.verify_delays_s.length < 1 || config.verify_delays_s.length > 5 ||
        !config.verify_delays_s.every((d) => Number.isInteger(d) && d >= 30 && d <= 600)) {
        throw new Error('Konfiguration: verify_delays_s: 1–5 Wartezeiten zwischen 30 und 600 s');
    }
    if (config.imap_port !== 993) throw new Error('Konfiguration: IMAP nur über TLS (Port 993)');
    return config;
}

function loadConfig({ recordingOnly = false } = {}) {
    if (!fs.existsSync(CONFIG_FILE)) {
        throw new Error(`Keine Konfiguration (${CONFIG_FILE}). Dieser Bot läuft nur auf dem Rechner des Maintainers – siehe README.md.`);
    }
    checkFileIsPrivate(CONFIG_DIR, 'Das Konfigurationsverzeichnis');
    checkFileIsPrivate(CONFIG_FILE, 'Die Konfiguration');
    let raw;
    try {
        raw = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
    } catch (err) {
        throw new Error('Die Konfiguration ist kein gültiges JSON');
    }
    return validateConfig(raw, { recordingOnly });
}

module.exports = { CONFIG_DIR, CONFIG_FILE, STATE_DIR, DEFAULTS, validateConfig, loadConfig, checkFileIsPrivate };
