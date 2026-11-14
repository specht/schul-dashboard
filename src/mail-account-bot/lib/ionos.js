'use strict';
// The path through the IONOS control panel, as recorded with the maintainer
// on 2026-11-14 (bot.js record):
//
//   login.ionos.de              user name (#username), "Weiter", password
//                               (#password), "Weiter", code (/totp,
//                               #passcode), "Weiter", then mein.ionos.de
//   mein.ionos.de/email/        leads to /email/<contract>/email-overview:
//                               table #table-emails, one row per address,
//                               tr[data-testid="tr-<address>"]; search field
//                               plus search button (reloads the page)
//   row menu (…)                its item "Passwort ändern" goes to
//                               /email/<contract>/mailbox/<id>/edit-password;
//                               the bot goes there directly with the id from
//                               the row and never opens the menu ("Löschen"
//                               is in it, right next to it).
//   edit-password page          breadcrumb shows the address
//                               (link-bc-current-email), one password field
//                               (#password), "Passwort ändern" / "Abbrechen"
//   after saving                /email/<contract>/mailbox/<id>/details with
//                               pageMessage-EMAIL_PASSWORD_SUCCESS
//
// The mailbox id from the row is carried through: the page URL, the
// breadcrumb, the cancel link and the page after saving must all name the
// same mailbox – and the page must show exactly this address.
//
// FLOW_STATUS
//   'provisional'  not recorded yet – the bot refuses every real run
//   'recorded'     adapted to a recording with the maintainer: dry runs and
//                  the test mailbox only
//   'verified'     a dry run and a reset of the test mailbox went through
//                  with the maintainer watching: real cases
// Every change to this file (IONOS changed its pages) sets it back to
// 'recorded' until the maintainer watched a dry run again.
const { Stop, CaseProblem, Postpone, emailsIn, waitForState, sleep } = require('./guard');
const { totpAt } = require('./totp');

// verified 2026-11-14: dry runs and a reset of the test mailbox, a dry run on
// a real case with the 2FA login – watched by the maintainer
const FLOW_STATUS = 'verified';

const HOSTS = ['login.ionos.de', 'mein.ionos.de'];

const URLS = {
    email: 'https://mein.ionos.de/email/',
};

const S = {
    consent: '#confirmSelection[data-testid="confirm-selection"]',
    username: 'input#username',
    password: 'input#password[type="password"]',
    // second factor (recorded 2026-11-14): login.ionos.de/totp, "Login bestätigen"
    otp: 'input#passcode[name="passcode"][autocomplete="one-time-code"]',
    loginNext: 'button#button--with-loader[type="submit"]',
    loginError: '[role="alert"], .notification--error, .message--error, .form-error',
    captcha: 'iframe[src*="captcha" i], [class*="captcha" i], [id*="captcha" i]',
    table: 'table#table-emails[data-testid="table-emails"]',
    search: 'input#email-search[data-testid="input-email-search"]',
    searchSubmit: '[data-testid="button-search-submit"]',
    row: 'table#table-emails tr[data-testid^="tr-"]',
    rowMailboxLink: 'a[data-testid="link-email-mailbox"]',
    headline: 'h1.page-header__headline',
    breadcrumbAddress: 'a[data-testid="link-bc-current-email"]',
    main: 'main#main-content',
    submit: 'main#main-content form button[type="submit"].submit-btn',
    cancel: 'main#main-content form a.button',
    success: '[data-testid="pageMessage-EMAIL_PASSWORD_SUCCESS"]',
    pageMessage: '[data-testid^="pageMessage-"]',
};

const RE = {
    overview: /^https:\/\/mein\.ionos\.de\/email\/(\d+)\/email-overview(?:[?#].*)?$/,
    mailboxLink: /^\/email\/(\d+)\/mailbox\/(\d+)\/details$/i,
};

const visible = (selector) => async (page) => page.locator(selector).first().isVisible();
const onHost = (host) => (page) => new URL(page.url()).hostname === host;
const urlMatches = (re) => (page) => re.test(page.url());
const all = (...tests) => async (page) => {
    for (const t of tests) if (!(await t(page))) return false;
    return true;
};
const none = (...tests) => async (page) => {
    for (const t of tests) if (await t(page)) return false;
    return true;
};

class IonosSession {
    constructor({ page, config, state, dashboard, pacer, guard, log, now = () => Date.now() }) {
        Object.assign(this, { page, config, state, dashboard, pacer, guard, log, now });
        this.timeoutMs = config.timeout_ms;
        this.contract = null;
    }

    wait(states, what, timeoutMs = this.timeoutMs) {
        return waitForState(this.page, states, { guard: this.guard, timeoutMs, what });
    }

    async type(locator, text) {
        await locator.click();
        await this.pacer.pause(200, 600);
        await locator.pressSequentially(text, { delay: this.pacer.typingDelay() });
    }

    async click(locator) {
        await locator.hover();
        await this.pacer.pause(300, 900);
        await locator.click();
    }

    async one(selector, what, scope = this.page) {
        const locator = scope.locator(selector);
        if ((await locator.count()) !== 1) throw new Stop(`${what} nicht (eindeutig) gefunden`);
        return locator;
    }

    // the list of addresses, logged in if the session expired
    async openMailboxList() {
        await this.page.goto(URLS.email);
        const listReady = all(urlMatches(RE.overview), visible(S.table));
        const reached = await this.wait({
            list: listReady,
            login: all(onHost('login.ionos.de'), visible(S.username), none(visible(S.captcha))),
            captcha: visible(S.captcha),
        }, 'Adressliste öffnen');
        if (reached === 'captcha') throw new Stop('IONOS zeigt eine Sicherheitsabfrage (Captcha)');
        if (reached === 'login') {
            await this.login();
            await this.pacer.pause(2000, 5000);
            await this.page.goto(URLS.email);
            await this.wait({ list: listReady }, 'Adressliste nach der Anmeldung');
        }
        this.contract = RE.overview.exec(this.page.url())[1];
        this.log('Adressliste ist offen');
    }

    async login() {
        if (this.state.loginsLeft(this.config.max_logins_per_day) < 1) {
            throw new Postpone(`Heute schon ${this.config.max_logins_per_day} Anmeldungen bei IONOS von diesem Rechner – der Rest wartet bis morgen`);
        }
        // counted before the first keystroke (an attempt is an attempt), here
        // and on the dashboard for all machines together
        const allowed = await this.dashboard.loginAttempt(this.config.host);
        if (allowed.result === 'limit') throw new Postpone('Heute keine Anmeldung bei IONOS mehr übrig (alle Rechner zusammen) – der Rest wartet bis morgen oder bis der Zähler auf der Seite „Passwörter“ zurückgesetzt wird');
        if (allowed.result !== 'ok') throw new Postpone('Der Bot ist inzwischen angehalten');
        this.state.count('logins');
        this.log('Anmeldung bei IONOS');
        const loginFailed = all(onHost('login.ionos.de'), visible(S.loginError));
        const captcha = visible(S.captcha);
        const stopFor = (reached, step) => {
            if (reached === 'captcha') return new Stop('IONOS zeigt bei der Anmeldung eine Sicherheitsabfrage');
            return new Stop(`IONOS lehnt ${step} ab`);
        };

        await this.pacer.pause(1000, 2500);
        // cookie banner (a fresh browser profile): decline, as recorded
        if (await this.page.locator(S.consent).isVisible()) {
            await this.click(this.page.locator(S.consent));
            await this.pacer.pause(500, 1200);
        }
        await this.type(await this.one(S.username, 'Anmeldung: Feld für den Benutzernamen'), this.config.ionos_login);
        await this.pacer.pause(500, 1500);
        await this.click(await this.one(S.loginNext, 'Anmeldung: „Weiter“'));
        let reached = await this.wait({
            password: all(onHost('login.ionos.de'), visible(S.password), none(loginFailed, captcha)),
            failed: loginFailed, captcha,
        }, 'Anmeldung: Passwortfeld');
        if (reached !== 'password') throw stopFor(reached, 'den Benutzernamen');

        await this.pacer.pause(800, 2000);
        await this.type(await this.one(S.password, 'Anmeldung: Passwortfeld'), this.config.ionos_password);
        await this.pacer.pause(500, 1500);
        await this.click(await this.one(S.loginNext, 'Anmeldung: „Weiter“'));
        reached = await this.wait({
            otp: all(onHost('login.ionos.de'), (p) => new URL(p.url()).pathname === '/totp', visible(S.otp), none(loginFailed, captcha)),
            failed: loginFailed, captcha,
            loggedInWithoutOtp: onHost('mein.ionos.de'),
        }, 'Anmeldung: zweiter Faktor');
        if (!this.config.ionos_2fa) {
            // not set up yet (configuration): logged in right after the password, as recorded
            if (reached === 'otp') throw new Stop('IONOS fragt nach einem Code, aber die Konfiguration sagt ionos_2fa: false');
            if (reached !== 'loggedInWithoutOtp') throw stopFor(reached, 'das Passwort');
            this.log('Angemeldet (ohne zweiten Faktor)');
            return;
        }
        if (reached === 'loggedInWithoutOtp') throw new Stop('IONOS hat nicht nach dem zweiten Faktor gefragt – das passt nicht zum erwarteten Ablauf');
        if (reached !== 'otp') throw stopFor(reached, 'das Passwort');

        const code = await this.freshTotp();
        await this.type(await this.one(S.otp, 'Anmeldung: Feld für den Code'), code);
        await this.pacer.pause(400, 1200);
        await this.click(await this.one(S.loginNext, 'Anmeldung: „Weiter“'));
        reached = await this.wait({
            loggedIn: onHost('mein.ionos.de'),
            failed: loginFailed, captcha,
        }, 'Anmeldung: Abschluss');
        if (reached !== 'loggedIn') throw stopFor(reached, 'den Code des zweiten Faktors');
        this.log('Angemeldet');
    }

    // a code from a time step not used before, with enough time left to type it
    async freshTotp() {
        for (;;) {
            const t = totpAt(this.config.totp, this.now());
            if (t.counter > this.state.lastTotpCounter && t.remaining >= this.config.totp_min_remaining_s) {
                this.state.lastTotpCounter = t.counter;
                return t.code;
            }
            await sleep((t.remaining + 1) * 1000);
        }
    }

    // rows of the list with the address each one names (data-testid "tr-<address>")
    async rows() {
        const rows = this.page.locator(S.row);
        const out = [];
        const count = await rows.count();
        for (let i = 0; i < count; i++) {
            const testid = (await rows.nth(i).getAttribute('data-testid')) || '';
            out.push({ row: rows.nth(i), address: testid.slice(3).trim().toLowerCase() });
        }
        return out;
    }

    // the one row of this mailbox – exactly one, exactly this address, a
    // mailbox (not a forwarding); returns the row and the mailbox id
    async findRow(mailbox) {
        await this.wait({ list: all(urlMatches(RE.overview), visible(S.table)) }, 'Adressliste');
        // still the result of the previous search: back to the whole list first
        if ((await this.page.locator(S.search).inputValue().catch(() => '')) !== '') await this.openList();
        // the list must show rows in the recorded form before searching –
        // otherwise a changed layout would look like "not found"
        const before = await this.rows();
        if (before.length === 0) throw new Stop('Adressliste: keine Zeilen im bekannten Format');
        if (!before.slice(0, 5).every((r) => /@/.test(r.address))) throw new Stop('Adressliste: Zeilen ohne erkennbare Adresse');

        const search = await this.one(S.search, 'Adressliste: Suchfeld');
        if ((await search.inputValue()) !== '') await search.fill('');
        await this.type(search, mailbox);
        await this.pacer.pause(500, 1500);
        await this.click(await this.one(S.searchSubmit, 'Adressliste: Suchen-Schaltfläche'));
        await sleep(500);
        await this.wait({
            searched: all(urlMatches(RE.overview), visible(S.table), async (p) => (await p.locator(S.search).inputValue().catch(() => '')) === mailbox),
        }, 'Adressliste: Suchergebnis');
        await this.pacer.pause(1000, 2000);

        const matches = (await this.rows()).filter((r) => r.address === mailbox);
        if (matches.length > 1) throw new Stop(`${mailbox} steht mehrfach in der Adressliste`);
        if (matches.length === 0) throw new CaseProblem(`${mailbox} steht nicht in der IONOS-Adressliste`);
        const row = matches[0].row;
        const others = emailsIn(await row.innerText()).filter((e) => e !== mailbox);
        if (others.length) throw new Stop(`Die Zeile von ${mailbox} enthält weitere Adressen`);
        const link = row.locator(S.rowMailboxLink);
        if ((await link.count()) !== 1) throw new CaseProblem(`${mailbox} ist bei IONOS kein Postfach (z. B. nur eine Weiterleitung)`);
        if ((await link.innerText()).trim().toLowerCase() !== mailbox) throw new Stop(`Die Zeile von ${mailbox} verlinkt ein anderes Postfach`);
        const m = RE.mailboxLink.exec((await link.getAttribute('href')) || '');
        if (!m || m[1] !== this.contract) throw new Stop(`Die Zeile von ${mailbox}: Postfach-Verweis in unbekannter Form`);
        return { row, id: m[2] };
    }

    mailboxPath(id, what) {
        return `/email/${this.contract}/mailbox/${id}/${what}`;
    }

    // the edit-password page of exactly this mailbox
    async checkEditPage(mailbox, id) {
        const page = this.page;
        if (page.url() !== `https://mein.ionos.de${this.mailboxPath(id, 'edit-password')}`) throw new Stop('„Passwort ändern“: Seite eines anderen Postfachs');
        const headline = await this.one(S.headline, '„Passwort ändern“: Überschrift');
        if ((await headline.innerText()).trim() !== 'E-Mail-Passwort ändern') throw new Stop('„Passwort ändern“: unbekannte Überschrift');
        const crumb = await this.one(S.breadcrumbAddress, '„Passwort ändern“: Adresse in der Navigation');
        const crumbHref = ((await crumb.getAttribute('href')) || '').toLowerCase();
        const addresses = emailsIn(await (await this.one(S.main, '„Passwort ändern“: Hauptbereich')).innerText());
        if ((await crumb.innerText()).trim().toLowerCase() !== mailbox || crumbHref !== this.mailboxPath(id, 'details') ||
            addresses.length !== 1 || addresses[0] !== mailbox) {
            throw new Stop(`Die Seite „Passwort ändern“ zeigt nicht genau ${mailbox}`);
        }
    }

    async resetPassword(mailbox, password, { dryRun = false } = {}) {
        if (!/^[A-Za-z0-9-]{8,64}$/.test(password)) throw new CaseProblem('Ungeeignetes Passwort vom Dashboard');
        this.log(`${dryRun ? 'Probelauf' : 'Zurücksetzen'}: ${mailbox}`);
        const page = this.page;
        const { id } = await this.findRow(mailbox);

        // straight to this mailbox's "Passwort ändern" page with the number from
        // its row – the row menu (with "Löschen" right next to it) stays closed
        await this.pacer.pause(800, 2000);
        await this.page.goto(`https://mein.ionos.de${this.mailboxPath(id, 'edit-password')}`);
        await this.wait({ edit: all(visible(S.password), visible(S.breadcrumbAddress), (p) => p.url().endsWith('/edit-password')) }, 'Seite „Passwort ändern“');
        await this.checkEditPage(mailbox, id);
        const input = await this.one(`${S.main} input[type="password"]`, '„Passwort ändern“: genau ein Passwortfeld');
        if ((await input.getAttribute('id')) !== 'password') throw new Stop('„Passwort ändern“: unbekanntes Passwortfeld');
        await this.pacer.pause(500, 1200);
        await this.type(input, password);
        if ((await input.inputValue()) !== password) throw new Stop('„Passwort ändern“: Passwort kam nicht richtig an');
        const submit = await this.one(S.submit, '„Passwort ändern“: Schaltfläche');
        if ((await submit.innerText()).trim() !== 'Passwort ändern') throw new Stop('„Passwort ändern“: Schaltfläche heißt anders');
        const cancel = await this.one(S.cancel, '„Passwort ändern“: „Abbrechen“');
        if ((await cancel.innerText()).trim() !== 'Abbrechen' || ((await cancel.getAttribute('href')) || '').toLowerCase() !== this.mailboxPath(id, 'details')) {
            throw new Stop('„Passwort ändern“: „Abbrechen“ in unbekannter Form');
        }
        // once more right before the click: still the same mailbox
        await this.checkEditPage(mailbox, id);
        this.guard.check();
        await this.pacer.pause(800, 2000);

        const detailsUrl = `https://mein.ionos.de${this.mailboxPath(id, 'details')}`;
        if (dryRun) {
            await this.click(cancel);
            await this.wait({ details: (p) => p.url() === detailsUrl }, 'Abbrechen');
            this.log(`Probelauf ok, nichts geändert: ${mailbox}`);
            await this.pacer.pause(1000, 2000);
            await this.openList();
            return;
        }

        await this.click(submit);
        const reached = await this.wait({
            success: async (p) => p.url() === detailsUrl && (await p.locator(S.success).first().isVisible()),
            // an error message on the page, or still on the form with an error shown
            error: async (p) => ((await p.locator(S.pageMessage).count()) > 0 && (await p.locator(S.success).count()) === 0) ||
                (p.url().endsWith('/edit-password') && (await p.locator(S.loginError).first().isVisible())),
        }, 'Bestätigung nach „Passwort ändern“');
        if (reached !== 'success') throw new Stop(`IONOS meldet einen Fehler beim Ändern des Passworts von ${mailbox}`);
        const message = await page.locator(S.success).first().innerText();
        if (!/passwort wurde geändert/i.test(message)) throw new Stop('Bestätigung in unbekannter Form');
        const headline = (await (await this.one(S.headline, 'Postfach-Details: Überschrift')).innerText()).trim().toLowerCase();
        if (headline !== mailbox) throw new Stop(`Nach dem Ändern zeigt IONOS ein anderes Postfach als ${mailbox}`);
        this.log(`IONOS bestätigt: ${mailbox}`);
        await this.pacer.pause(1500, 3000);
        await this.openList();
    }

    // back to the list via the breadcrumb, as recorded
    async openList() {
        const crumb = this.page.locator('a[data-testid="link--bc-overview"]');
        if ((await crumb.count()) === 1) await this.click(crumb);
        else await this.page.goto(URLS.email);
        await this.wait({ list: all(urlMatches(RE.overview), visible(S.table)) }, 'Zurück zur Adressliste');
    }
}

module.exports = { FLOW_STATUS, HOSTS, URLS, IonosSession };
