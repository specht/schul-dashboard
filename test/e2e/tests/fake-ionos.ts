import type { BrowserContext, Route } from '@playwright/test';
import { totp, TEST_OTP_SECRET } from './fixtures';

// A stand-in for the IONOS login and control panel, served through
// context.route() – the bot's browser never reaches the real IONOS (every
// other host is aborted). Its structure follows the recording with the
// maintainer (2026-11-14, see src/mail-account-bot/lib/ionos.js): ids,
// data-testids, URLs and the order of the pages. Variants make the pages
// differ the way a changed or suspicious IONOS page might.

export type FakeMailbox = { address: string; kind?: 'mailbox' | 'forward' };

export type FakeVariant = {
  consentBanner?: boolean;
  captchaAfterUsername?: boolean;
  rejectPassword?: boolean;
  noOtpStep?: boolean;
  redirectAfterLogin?: string; // full URL
  dialogShows?: string; // the edit-password page shows another address
  rowLinksTo?: string; // the row's mailbox link (and menu) lead to this address's number
  duplicate?: string; // this address twice in the list
  rowsWithoutTestIds?: boolean; // changed layout
  noSuccessMessage?: boolean;
  errorOnSubmit?: boolean;
  popupOnList?: boolean;
  // address list export and creating mailboxes
  exportHeader?: string; // other columns
  exportRows?: number; // fewer rows than real
  businessFirst?: boolean; // Mail Business card where Mail Basic was
  basicHeadline?: string; // the Basic card is called something else
  domains?: string[]; // offered domains (default: the school's student domain once)
  extraPrechecked?: 'virusProtection' | 'orderMailArchiving' | 'ai-checkbox';
  forwardPrefilled?: boolean;
  createExistsError?: boolean; // IONOS: the address exists already
  createdShows?: string; // the details page after saving shows another address
};

export type FakeIonos = {
  loggedIn: boolean;
  passwords: Map<string, string>;
  resets: { address: string; password: string }[];
  deletes: string[];
  created: { address: string; password: string; extras: string[]; forward: string }[];
  exports: number;
  logins: { username?: string; password?: boolean; otp?: boolean }[];
  pagesServed: string[];
  install(context: BrowserContext): Promise<void>;
};

const CONTRACT = '100200';
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
const html = (title: string, body: string) =>
  `<!doctype html><html lang="de"><head><meta charset="utf-8"><title>${esc(title)}</title></head><body>${body}</body></html>`;
const redirect = (to: string) => html('Weiterleitung', `<script>location.replace(${JSON.stringify(to)})</script>`);
const breadcrumb = (address?: string, id?: string) =>
  `<nav aria-label="Navigation" class="breadcrumb">
     <a href="https://mein.ionos.de/home/products" data-testid="link--bc-home" class="breadcrumb__item">Home</a>
     <a href="/email/" data-testid="link--bc-email-portfolio" class="breadcrumb__item">E-Mail-Portfolio</a>
     <a href="/email/${CONTRACT}/email-overview" data-testid="link--bc-overview" class="breadcrumb__item">E-Mail-Übersicht</a>
     ${address ? `<a href="/email/${CONTRACT}/mailbox/${id}/details" data-testid="link-bc-current-email" class="breadcrumb__item">${esc(address)}</a>` : ''}
   </nav>`;

function loginForm(action: string, field: string, label: string, opts: { error?: string; consent?: boolean } = {}) {
  const type = field === 'password' ? 'password' : field === 'username' ? 'email' : 'text';
  const extra = field === 'passcode' ? 'name="passcode" autocomplete="one-time-code"' : field === 'username' ? 'name="identifier" autocomplete="username"' : 'name="password" autocomplete="current-password"';
  return html(
    'Login – Zugang zu Ihrem Kundenkonto',
    `${opts.consent ? '<div id="consent"><button id="confirmSelection" data-testid="confirm-selection" onclick="this.parentNode.remove()">Ablehnen</button></div>' : ''}
     <h1>Anmelden</h1>${opts.error ? `<div role="alert">${esc(opts.error)}</div>` : ''}
     <form method="post" action="${action}" novalidate>
       <label for="${field}">${esc(label)}</label>
       <input id="${field}" type="${type}" ${extra} class="input-text">
       <button id="button--with-loader" type="submit" class="button button--primary">Weiter</button>
     </form>`,
  );
}

export function fakeIonos(mailboxes: FakeMailbox[], variant: FakeVariant = {}, { loggedIn = false } = {}): FakeIonos {
  const ids = new Map<string, string>();
  mailboxes.forEach((m, i) => ids.set(m.address, String(50000000500 + i)));
  const byId = (id: string) => [...ids.entries()].find(([, v]) => v === id)?.[0];
  const fake: FakeIonos = {
    loggedIn,
    passwords: new Map(mailboxes.map((m) => [m.address, `alt-${m.address.length}-geaendert`])),
    resets: [],
    deletes: [],
    created: [],
    exports: 0,
    logins: [],
    pagesServed: [],
    async install(context: BrowserContext) {
      await context.route('**/*', (route) => handle(route));
    },
  };
  let flash: string | null = null;
  let createdFlash: string | null = null;
  const page = (route: Route, body: string, status = 200) =>
    route.fulfill({ status, contentType: 'text/html; charset=utf-8', body });

  function listPage(search: string) {
    const rows = mailboxes.filter((m) => !search || m.address.includes(search));
    if (variant.duplicate && (!search || variant.duplicate.includes(search))) rows.push({ address: variant.duplicate });
    const tid = variant.rowsWithoutTestIds ? 'data-qa' : 'data-testid';
    const trs = rows.map((r) => {
      const id = ids.get(r.address)!;
      const target = variant.rowLinksTo ? ids.get(variant.rowLinksTo)! : id;
      const link = r.kind === 'forward'
        ? `<a href="/email/${CONTRACT}/FORWARD/${id}/details" data-testid="link-email-forward" class="link">${esc(r.address)}</a>`
        : `<a aria-label="Mail Basic ${esc(r.address)}" href="/email/${CONTRACT}/MAILBOX/${target}/details" data-testid="link-email-mailbox" class="link tooltip">${esc(r.address)}</a>`;
      return `<tr ${tid}="tr-${esc(r.address)}" class="table__row table__row--has-flyout">
        <td>${r.kind === 'forward' ? 'Weiterleitung' : 'Mail Basic'}</td><td>${link}</td>
        <td><div class="context-menu"><span role="button" aria-label="Einstellungen" data-testid="button-context-menu-trigger" class="context-menu__trigger">…</span>
          <ul role="menu" class="context-menu__list" hidden>
            <li role="none"><a role="menuitem" href="/email/${CONTRACT}/mailbox/${id}/details" data-testid="link-mailbox-settings">Einstellungen</a></li>
            <li role="none"><a role="menuitem" href="/email/${CONTRACT}/mailbox/${target}/edit-password" data-tooltip="Passwort ändern" data-testid="link-mailbox-change-password">Passwort ändern</a></li>
            <li role="none"><a role="menuitem" aria-label="Löschen ${esc(r.address)}" href="/email/${CONTRACT}/mailbox/${id}/delete" data-testid="link-mailbox-delete">Löschen</a></li>
          </ul></div></td></tr>`;
    });
    return html(
      'IONOS - E-Mail-Adressen',
      `<main id="main-content" role="main">${breadcrumb()}
       <h1 class="page-header__headline">E-Mail-Adressen</h1>
       <a href="/email/${CONTRACT}/email-package-selection" data-testid="button-create-another-mailbox" class="button button--primary">Weitere E-Mail-Adresse anlegen</a>
       <a href="/email/${CONTRACT}/email-overview/export?search=${encodeURIComponent(search)}&sort=email-asc" data-testid="link-export-emails" data-base-url="/email/${CONTRACT}/email-overview/export" class="link link--action">E-Mail-Adressen exportieren</a>
       <form id="js-table-util-form" role="search" data-testid="form-email-search" method="get" action="/email/${CONTRACT}/email-overview">
         <input id="email-search" name="search" type="text" aria-label="Suchen" data-testid="input-email-search" value="${esc(search)}">
         <a role="button" aria-label="Suchen" data-testid="button-search-submit" href="#" onclick="this.closest('form').submit(); return false;">Suchen</a>
       </form>
       <table id="table-emails" data-testid="table-emails" class="table"><tr class="table__header"><th>TYP</th><th>E-MAIL-ADRESSE</th><th>AKTIONEN</th></tr>${trs.join('')}</table>
       </main>
       <script>
         ${variant.popupOnList ? "setTimeout(() => window.open('https://mein.ionos.de/werbung', '_blank'), 300);" : ''}
         for (const t of document.querySelectorAll('[data-testid=button-context-menu-trigger]')) {
           t.addEventListener('click', () => {
             for (const m of document.querySelectorAll('.context-menu__list')) m.hidden = true;
             t.parentNode.querySelector('.context-menu__list').hidden = false;
           });
         }
       </script>`,
    );
  }

  function editPage(id: string, error = '') {
    const address = byId(id)!;
    const shown = variant.dialogShows || address;
    return html(
      'IONOS - E-Mail-Passwort ändern',
      `<main id="main-content" role="main">${breadcrumb(shown, id)}
       <h1 class="page-header__headline">E-Mail-Passwort ändern</h1>
       ${error ? `<div data-testid="pageMessage-EMAIL_PASSWORD_ERROR" class="message message--error">${esc(error)}</div>` : ''}
       <form method="post" action="/email/${CONTRACT}/mailbox/${id}/edit-password">
         <section><label for="password" class="label">Neues Passwort</label>
         <input id="password" name="password" type="password" autocomplete="new-password" class="input-text oao-pwi-input">
         <ul><li><button type="submit" class="button button--primary submit-btn">Passwort ändern</button></li>
         <li><a href="/email/${CONTRACT}/mailbox/${id}/details" class="button">Abbrechen</a></li></ul></section>
       </form></main>`,
    );
  }

  function detailsPage(id: string, success: boolean) {
    const address = byId(id)!;
    return html(
      'IONOS - E-Mail-Details',
      `<main id="main-content" role="main">${breadcrumb()}
       <h1 class="page-header__headline">${esc(address)}</h1>
       ${success ? '<div data-testid="pageMessage-EMAIL_PASSWORD_SUCCESS" class="message message--success"><h4>Ihr E-Mail-Passwort wurde geändert</h4></div>' : ''}
       <h2>Postfach einrichten</h2></main>`,
    );
  }

  const STUDENT_DOMAIN = 'mail.beispielschule.de';
  const all = () => [...mailboxes.map((m) => m.address), ...fake.created.map((c) => c.address)];

  function exportCsv() {
    const header = variant.exportHeader || 'E-Mail-Adresse;Kontotyp;Vertragsnummer';
    const fillerCount = variant.exportRows !== undefined ? variant.exportRows : 120;
    const rows = [...all().map((a) => `${a};Mail Basic;${CONTRACT}`),
      ...Array.from({ length: fillerCount }, (_, i) => `fueller${i}@andere-domain.example.org;Mail Basic;${CONTRACT}`)];
    return '\uFEFF' + [header, ...rows].join('\r\n') + '\r\n';
  }

  function selectionPage() {
    const card = (testid: string, headline: string, form: string) =>
      `<div data-testid="${testid}" class="grid-col"><h3 class="card__preheadline">…</h3><h3 class="card__headline">${esc(headline)}</h3>
       <form data-testid="${form}" method="post" action="/email/${CONTRACT}/email-package-selection/${form}"><button type="submit" class="button">Anlegen</button></form></div>`;
    const basic = variant.businessFirst
      ? card('card-col-mail-basic', 'Mail Business | 50 GB', 'form-create-basic')
      : card('card-col-mail-basic', variant.basicHeadline || 'Mail Basic', 'form-create-basic');
    return html('IONOS - Neue E-Mail-Adresse anlegen: Wählen Sie den Typ aus',
      `<main id="main-content" role="main">${breadcrumb()}<h1 class="page-header__headline">Neue E-Mail-Adresse anlegen: Wählen Sie den Typ aus</h1>
       <div data-testid="email-package-card-grid">${basic}${card('card-col-mail-business', 'Mail Business | 50 GB', 'form-create-business')}
       <div data-testid="card-col-ms-exchange"><h3 class="card__headline">Microsoft® Exchange</h3></div>
       ${card('card-col-forwards', 'E-Mail-Weiterleitung', 'form-create-forward')}</div></main>`);
  }

  function createPage(error = '') {
    const domains = variant.domains || [STUDENT_DOMAIN];
    const options = ['gymnasium.example.org', ...domains].map((d) => `<option value="${esc(d)}">@${esc(d)}</option>`).join('');
    const box = (id: string, name: string, label: string) =>
      `<input id="${id}" name="${name}" type="checkbox" class="input-checkbox" ${variant.extraPrechecked === id ? 'checked' : ''}><label for="${id}">${esc(label)}</label>`;
    return html('IONOS - Neue E-Mail-Adresse anlegen: Mail Basic',
      `<main id="main-content" role="main">${breadcrumb()}<h1 class="page-header__headline">Neue E-Mail-Adresse anlegen: Mail Basic</h1>
       ${error ? `<div data-testid="pageMessage-EMAIL_CREATE_ERROR" class="message message--error">${esc(error)}</div>` : ''}
       <form method="post" action="/email/${CONTRACT}/create-basic-email" novalidate>
         <label for="localPart">E-Mail</label><input id="localPart" name="localPart" type="text" data-testid="input-local-part" class="input-text">
         <select id="domain-select" name="domain" aria-label="Verfügbare Domain auswählen">${options}</select>
         <label for="password">Passwort</label><input id="password" name="password" type="password" class="input-text oao-pwi-input">
         <input id="forwardTarget" name="forwardTarget" type="text" value="${variant.forwardPrefilled ? 'jemand@example.org' : ''}" ${variant.forwardPrefilled ? '' : 'hidden'}>
         <section id="js-security-section">${box('virusProtection', 'virusProtection', 'Virenschutz - 2,50 €/Monat')}${box('orderMailArchiving', 'orderMailArchiving', 'E-Mail-Archivierung kaufen — 2,50 €/Monat')}</section>
         <section id="js-ai-section">${box('ai-checkbox', 'webMailAIActive', 'Aktivieren')}</section>
         <a href="/email/${CONTRACT}/email-overview" data-testid="btn-cancel" class="button">Abbrechen</a>
         <button id="btn-submit" type="submit" data-testid="btn-save" class="button button--primary">Speichern</button>
       </form></main>`);
  }

  async function handle(route: Route) {
    const request = route.request();
    const url = new URL(request.url());
    const form = new URLSearchParams(request.postData() || '');
    fake.pagesServed.push(`${request.method()} ${url.host}${url.pathname}`);
    const current = () => fake.logins[fake.logins.length - 1];

    if (url.host === 'login.ionos.de') {
      if (request.method() === 'GET' && url.pathname === '/') {
        fake.logins.push({});
        return page(route, loginForm('/password', 'username', 'E-Mail-Adresse oder Kundennummer', { consent: variant.consentBanner }));
      }
      if (url.pathname === '/password') {
        current().username = form.get('identifier') || '';
        if (variant.captchaAfterUsername) {
          return page(route, html('Sicherheitsprüfung', '<h1>Sicherheitsprüfung</h1><div class="captcha-box">Bitte bestätigen Sie, dass Sie kein Roboter sind.</div>'));
        }
        return page(route, loginForm('/totp-check', 'password', 'Passwort'));
      }
      if (url.pathname === '/totp-check') {
        current().password = true;
        if (variant.rejectPassword) return page(route, loginForm('/totp-check', 'password', 'Passwort', { error: 'Benutzername oder Passwort ist falsch.' }));
        if (variant.noOtpStep) {
          fake.loggedIn = true;
          return page(route, redirect('https://mein.ionos.de/home/products'));
        }
        // like IONOS: on to /totp, "Login bestätigen"
        return page(route, redirect('https://login.ionos.de/totp'));
      }
      if (url.pathname === '/totp' && request.method() === 'GET') {
        return page(route, loginForm('/done', 'passcode', 'Code'));
      }
      if (url.pathname === '/done') {
        const code = form.get('passcode') || '';
        const now = Date.now();
        if (![now - 30_000, now, now + 30_000].some((t) => totp(TEST_OTP_SECRET, t) === code)) {
          return page(route, loginForm('/done', 'passcode', 'Code', { error: 'Der Code ist ungültig.' }));
        }
        current().otp = true;
        fake.loggedIn = true;
        return page(route, redirect(variant.redirectAfterLogin || 'https://mein.ionos.de/home/products'));
      }
      return page(route, html('Nicht gefunden', 'Nicht gefunden'), 404);
    }
    if (url.host === 'mein.ionos.de') {
      if (!fake.loggedIn) return page(route, redirect('https://login.ionos.de/'));
      if (url.pathname === '/home/products') return page(route, html('IONOS - Produktübersicht', '<h1>Produkte</h1><a href="https://mein.ionos.de/email/">E-Mail</a>'));
      if (url.pathname === '/email/') return page(route, redirect(`https://mein.ionos.de/email/${CONTRACT}/email-overview`));
      if (url.pathname === `/email/${CONTRACT}/email-overview`) return page(route, listPage((url.searchParams.get('search') || '').trim()));
      if (url.pathname === `/email/${CONTRACT}/email-overview/export`) {
        fake.exports += 1;
        // the bot fetches the whole list, never a filtered one
        if (url.search) return route.fulfill({ status: 200, contentType: 'text/csv; charset=utf-8', body: 'E-Mail-Adresse;Kontotyp;Vertragsnummer\r\nnur@gefiltert.example.org;Mail Basic;1\r\n' });
        return route.fulfill({ status: 200, contentType: 'text/csv; charset=utf-8', body: exportCsv() });
      }
      if (url.pathname === `/email/${CONTRACT}/email-package-selection`) return page(route, selectionPage());
      if (url.pathname.startsWith(`/email/${CONTRACT}/email-package-selection/`)) {
        const which = url.pathname.split('/').pop();
        if (which !== 'form-create-basic') return page(route, html('Falsches Paket', `<h1>${esc(which || '')}</h1>`));
        return page(route, redirect(`https://mein.ionos.de/email/${CONTRACT}/create-basic-email`));
      }
      if (url.pathname === `/email/${CONTRACT}/create-basic-email`) {
        if (request.method() === 'GET') return page(route, createPage());
        const address = `${form.get('localPart')}@${form.get('domain')}`.toLowerCase();
        if (variant.createExistsError || all().includes(address)) return page(route, createPage('Diese E-Mail-Adresse ist bereits vergeben.'));
        const extras = ['virusProtection', 'orderMailArchiving', 'webMailAIActive'].filter((x) => form.get(x));
        fake.created.push({ address, password: form.get('password') || '', extras, forward: form.get('forwardTarget') || '' });
        fake.passwords.set(address, form.get('password') || '');
        const id = String(60000000000 + fake.created.length);
        ids.set(variant.createdShows || address, id);
        createdFlash = id;
        return page(route, redirect(`https://mein.ionos.de/email/${CONTRACT}/MAILBOX/${id}/details`));
      }
      const m = /^\/email\/\d+\/mailbox\/(\d+)\/(edit-password|details|delete)$/i.exec(url.pathname);
      if (m && createdFlash === m[1] && m[2] === 'details') {
        createdFlash = null;
        return page(route, html('IONOS - E-Mail-Details', `<main id="main-content" role="main">${breadcrumb()}
          <h1 class="page-header__headline">${esc(byId(m[1])!)}</h1>
          <div role="status" class="message message--success"><h3>Sie können Ihre neue E-Mail-Adresse jetzt verwenden</h3></div></main>`));
      }
      if (m && byId(m[1])) {
        const [, id, what] = m;
        if (what === 'delete') { fake.deletes.push(byId(id)!); return page(route, html('Löschen', '<h1>Löschen</h1>')); }
        if (what === 'details') {
          const success = flash === id;
          flash = null;
          return page(route, detailsPage(id, success));
        }
        if (request.method() === 'GET') return page(route, editPage(id));
        const password = form.get('password') || '';
        if (variant.errorOnSubmit) return page(route, editPage(id, 'Das hat leider nicht geklappt.'));
        fake.resets.push({ address: byId(id)!, password });
        fake.passwords.set(byId(id)!, password);
        // like IONOS: on to the details page, with the message once
        if (!variant.noSuccessMessage) flash = id;
        return page(route, redirect(`https://mein.ionos.de/email/${CONTRACT}/mailbox/${id}/details`));
      }
      return page(route, html('Werbung', '<h1>Angebot</h1>'));
    }
    if (url.host === 'andere-seite.example') {
      return page(route, html('Anmelden', '<h1>Anmelden</h1><input id="username">'));
    }
    return route.abort();
  }

  return fake;
}
