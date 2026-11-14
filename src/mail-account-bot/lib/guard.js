'use strict';
// Safeguards shared by all steps. The rule: after every action the page must
// be in one of the states the step expects – anything else stops the bot.
//
//   Stop         pause the bot: something on the IONOS page is not as
//                recorded (layout changed, captcha, security check, error,
//                another address than expected). No further logins until
//                the maintainer looked at it and runs `bot.js resume`.
//   CaseProblem  only this case fails (e.g. the mailbox is not in the list);
//                the page itself looked as expected.
//   Postpone     not now (the bot was paused meanwhile); cases stay approved.

class Stop extends Error {
    constructor(message, details = {}) { super(message); this.name = 'Stop'; this.details = details; }
}
class CaseProblem extends Error {
    constructor(message) { super(message); this.name = 'CaseProblem'; }
}
class Postpone extends Error {
    constructor(message) { super(message); this.name = 'Postpone'; }
}

const EMAIL_RE = /[a-z0-9._%+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}/gi;

function emailsIn(text) {
    return [...new Set((String(text).match(EMAIL_RE) || []).map((s) => s.toLowerCase()))];
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// pauses and typing speed of a person; factor 0 in tests
function makePacer(factor, random = Math.random) {
    return {
        pause: (minMs, maxMs) => sleep((minMs + random() * (maxMs - minMs)) * factor),
        typingDelay: () => (factor ? 60 + random() * 110 : 0),
    };
}

// Watches the browser: main frame navigations only to the allowed hosts over
// https, no new windows. check() throws once something happened.
function watchNavigation(context, page, allowedHosts) {
    const guard = {
        violation: null,
        check() { if (this.violation) throw new Stop(this.violation); },
    };
    const watch = (p) => p.on('framenavigated', (frame) => {
        if (frame !== p.mainFrame()) return;
        const url = frame.url();
        if (url === 'about:blank') return;
        let host = '?';
        let ok = false;
        try {
            const u = new URL(url);
            host = u.hostname;
            ok = u.protocol === 'https:' && allowedHosts.includes(u.hostname);
        } catch (err) { /* not a URL */ }
        if (!ok && !guard.violation) guard.violation = `Weiterleitung auf eine nicht vorgesehene Adresse (${host})`;
    });
    watch(page);
    context.on('page', (p) => {
        if (!guard.violation) guard.violation = 'Ein neues Fenster oder Tab wurde geöffnet';
        watch(p);
    });
    return guard;
}

// Waits until exactly one of the expected states is reached. states:
// {name: async (page) => boolean}. Throws Stop on timeout.
async function waitForState(page, states, { guard, timeoutMs, what }) {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
        guard.check();
        const reached = [];
        for (const [name, test] of Object.entries(states)) {
            let yes = false;
            try { yes = await test(page); } catch (err) { yes = false; }
            if (yes) reached.push(name);
        }
        if (reached.length === 1) return reached[0];
        if (reached.length > 1) throw new Stop(`${what}: Seite ist nicht eindeutig (${reached.join(', ')})`);
        if (Date.now() > deadline) throw new Stop(`${what}: unerwartete Seite (erwartet: ${Object.keys(states).join(' / ')})`);
        await sleep(250);
    }
}

module.exports = { Stop, CaseProblem, Postpone, emailsIn, sleep, makePacer, watchNavigation, waitForState };
