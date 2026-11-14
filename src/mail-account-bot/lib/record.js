'use strict';
// Recording the path through the control panel with the maintainer: he logs
// in and clicks through by hand in the bot's browser profile, the recorder
// writes down the structure of every page and every click – element types,
// ids, names, roles, labels, button texts. It does NOT write down input
// values, cookies, screenshots or table contents; e-mail addresses in
// texts become <mail> (the test mailbox becomes <test-mailbox>).
const fs = require('fs');
const path = require('path');

// runs in the page
function outline({ testMailbox, target }) {
    const EMAIL = /[a-z0-9._%+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}/gi;
    const mask = (text) => String(text || '').replace(EMAIL, (m) => (testMailbox && m.toLowerCase() === testMailbox ? '<test-mailbox>' : '<mail>')).replace(/\s+/g, ' ').trim().slice(0, 100);
    const TEXT_TAGS = new Set(['BUTTON', 'A', 'LABEL', 'H1', 'H2', 'H3', 'H4', 'H5', 'TH', 'LEGEND', 'OPTION', 'SUMMARY']);
    const TEXT_ROLES = new Set(['button', 'menuitem', 'tab', 'link', 'heading', 'alert', 'status', 'dialog', 'columnheader', 'option']);
    const describe = (el) => {
        const d = { tag: el.tagName.toLowerCase() };
        for (const attr of ['id', 'name', 'type', 'role', 'aria-label', 'aria-labelledby', 'placeholder', 'title', 'href', 'for', 'autocomplete']) {
            const v = el.getAttribute(attr);
            if (v) d[attr] = attr === 'href' ? mask(v.split('?')[0]) : mask(v);
        }
        const data = {};
        for (const a of el.attributes) if (a.name.startsWith('data-')) data[a.name] = mask(a.value).slice(0, 40);
        if (Object.keys(data).length) d.data = data;
        if (el.classList.length) d.cls = [...el.classList].slice(0, 5).join(' ');
        const role = el.getAttribute('role');
        const own = mask(el.innerText);
        if (TEXT_TAGS.has(el.tagName) || TEXT_ROLES.has(role)) d.text = own;
        else if (own.includes('<test-mailbox>')) d.text = own; // the test mailbox's row and dialog
        if (el.closest('[role=dialog], dialog')) d.inDialog = true;
        if (el.closest('table, [role=table], [role=grid]')) d.inTable = true;
        d.path = (() => {
            const parts = [];
            for (let e = el; e && e.nodeType === 1 && parts.length < 5; e = e.parentElement) {
                parts.unshift(e.id ? `${e.tagName.toLowerCase()}#${e.id}` : e.tagName.toLowerCase());
                if (e.id) break;
            }
            return parts.join(' > ');
        })();
        return d;
    };
    if (target) return describe(target);
    const selector = 'h1,h2,h3,h4,button,a,input,select,textarea,label,th,table,tr,dialog,[role],[aria-label],[data-testid],iframe';
    const visible = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const elements = [...document.querySelectorAll(selector)].filter(visible).slice(0, 600).map(describe);
    const rows = document.querySelectorAll('tr, [role=row]').length;
    return { title: mask(document.title), rows, elements, iframes: [...document.querySelectorAll('iframe')].map((f) => mask((f.src || '').split('?')[0])) };
}

async function record({ context, state, testMailbox, print = console.log }) {
    const dir = path.join(state.recordingsDir, new Date().toISOString().replace(/[:.]/g, '-'));
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const file = path.join(dir, 'events.jsonl');
    const mask = (text) => String(text).replace(/[a-z0-9._%+-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}/gi, (m) => (testMailbox && m.toLowerCase() === testMailbox ? '<test-mailbox>' : '<mail>'));
    const write = (event) => fs.appendFileSync(file, JSON.stringify({ ts: new Date().toISOString(), ...event }) + '\n', { mode: 0o600 });
    const url = (u) => { try { const x = new URL(u); return mask(`${x.protocol}//${x.host}${x.pathname}`); } catch (e) { return '?'; } };
    const snapshot = async (page, why) => {
        try {
            write({ event: 'page', why, url: url(page.url()), ...(await page.evaluate(outline, { testMailbox })) });
        } catch (err) { /* page navigated meanwhile */ }
    };

    await context.exposeBinding('__recordClick', async ({ page }, info) => {
        write({ event: 'click', url: url(page.url()), element: info });
        setTimeout(() => snapshot(page, 'after-click'), 1500);
    });
    await context.addInitScript(`(() => {
        const outline = ${outline.toString()};
        document.addEventListener('click', (e) => {
            const el = e.target.closest('button, a, [role], input, label, li, td, tr') || e.target;
            try { window.__recordClick(outline({ testMailbox: ${JSON.stringify(testMailbox || null)}, target: el })); } catch (err) {}
        }, true);
    })();`);
    const watch = (page) => {
        page.on('load', () => snapshot(page, 'load'));
        page.on('framenavigated', (frame) => { if (frame === page.mainFrame()) write({ event: 'navigated', url: url(frame.url()) }); });
        page.on('response', (response) => {
            const type = response.request().resourceType();
            if (type === 'xhr' || type === 'fetch') write({ event: 'api', method: response.request().method(), url: url(response.url()), status: response.status() });
        });
    };
    context.pages().forEach(watch);
    context.on('page', (page) => { write({ event: 'new-page' }); watch(page); });

    const page = context.pages()[0] || await context.newPage();
    await page.goto('https://login.ionos.de/');
    print(`Aufnahme läuft: ${file}`);
    print('Bitte von Hand anmelden, zur Adressliste gehen und für das Test-Postfach „Passwort ändern“ einmal abbrechen und einmal wirklich ändern,');
    print('dann das Browserfenster schließen.');
    await new Promise((resolve) => context.on('close', resolve));
    print(`Aufnahme beendet: ${file}`);
    return file;
}

module.exports = { record, outline };
