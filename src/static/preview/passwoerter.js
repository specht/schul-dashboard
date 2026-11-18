// Neues Design (Vorschau): Passwörter (/passwoerter). The server draws the
// page for the new design (print_password_page_preview in
// include/mail_password_reset.rb); this script makes it work. Loaded only for
// those who see the new design, so that the page and its script stay exactly
// as they were for everyone else (today's script finds none of its elements
// here and does nothing).
//
// Nextcloud: address, login and initial password as copy fields (one tap
// copies, a green check for a moment); the password stays hidden until
// »Anzeigen«. Resetting the own Nextcloud password asks first, the result is
// a quiet line.
// E-Mail: the same requests and states as today's page
// (/api/request_mail_password_reset, /api/mail_password_reset_status, polled
// every 10 seconds while a request is open or being worked on). Students see
// their own mailbox; the Klassenleitung a table of their students with the
// student's and the parents' mailbox, which turns into list rows where it is
// narrow (phones): a row opens a dialog (a sheet on phones) with both
// mailboxes. A reset password is hidden until »Anzeigen«.
(function () {
    var data = window.pv_passwoerter;
    var script = document.currentScript;
    if (!data || !window.pv_copy || !document.body.classList.contains('ui-preview') || !script) return;
    var root = document.querySelector('.pv-pw');
    if (!root) return;

    var STUDENT = !!data.student;
    var MASK = '••••••••';
    var STATES = {
        open: { label: 'Wartet auf Freigabe', icon: 'clock', when: 'beantragt am' },
        approved: { label: 'Wird bearbeitet', icon: 'loader-2', when: 'beantragt am' },
        done: { label: 'Zurückgesetzt', icon: 'circle-check', tone: 'ok' },
        failed: { label: 'Hat nicht geklappt', icon: 'alert-circle', tone: 'err' },
        rejected: { label: 'Abgelehnt', icon: 'circle-x', tone: 'err' },
        cancelled: { label: 'Nicht zurückgesetzt', icon: 'circle-x', tone: 'err' }
    };
    var ACTIVE = ['open', 'approved'];

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }

    function icon(name) {
        var i = el('i', 'ti ti-' + name);
        i.setAttribute('aria-hidden', 'true');
        return i;
    }

    // »Mi, 18.11., 10:05 Uhr«
    var WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
    function fmt_ts(ts) {
        if (!ts) return '';
        var d = new Date(ts * 1000);
        var now = new Date();
        var year = d.getFullYear() === now.getFullYear() ? '' : d.getFullYear();
        var min = d.getMinutes();
        return WEEKDAYS[d.getDay()] + ', ' + d.getDate() + '.' + (d.getMonth() + 1) + '.' + year + ', ' +
            d.getHours() + ':' + (min < 10 ? '0' : '') + min + ' Uhr';
    }

    // ---------- copy fields (pv_copy in preview.js) ----------
    // drawn by the server (.pv-copy with data-copy); a secret one shows dots
    // until »Anzeigen« and never puts the password into its title
    function copy_button(b) {
        b.addEventListener('click', function (e) {
            e.stopPropagation();
            var button = e.currentTarget;
            pv_copy.run(button, button.getAttribute('data-copy'), { what: button.getAttribute('data-what') || 'Text' });
        });
    }

    // shown passwords stay shown when the states are drawn again (polling)
    var revealed = {};

    function secret_field(password, what, key) {
        var box = el('div', 'pv-pw-secret');
        var field = el('button', 'pv-copy pv-pw-copy pv-pw-secret-field');
        field.type = 'button';
        field.setAttribute('data-copy', password);
        field.setAttribute('data-what', what);
        field.setAttribute('title', what + ' kopieren');
        field.setAttribute('aria-label', what + ' kopieren');
        var text = el('span', 'pv-copy-text pv-pw-mask', MASK);
        field.appendChild(text);
        var end = el('span', 'pv-copy-end');
        end.appendChild(pv_copy.icons());
        field.appendChild(end);
        copy_button(field);
        box.appendChild(field);
        var show = el('button', 'pv-pw-act bu_pv_show_password');
        show.type = 'button';
        box.appendChild(show);
        reveal(box, !!(key && revealed[key]));
        show.addEventListener('click', function (e) {
            var on = e.currentTarget.getAttribute('aria-pressed') !== 'true';
            if (key) revealed[key] = on;
            reveal(box, on);
        });
        return box;
    }

    function reveal(box, on) {
        var field = box.querySelector('.pv-pw-secret-field');
        var text = field.querySelector('.pv-copy-text');
        var show = box.querySelector('.bu_pv_show_password');
        text.textContent = on ? field.getAttribute('data-copy') : MASK;
        text.classList.toggle('pv-pw-mask', !on);
        if (on) text.removeAttribute('aria-hidden'); else text.setAttribute('aria-hidden', 'true');
        show.setAttribute('aria-pressed', on ? 'true' : 'false');
        show.textContent = '';
        show.appendChild(icon(on ? 'eye-off' : 'eye'));
        show.appendChild(el('span', null, on ? 'Verbergen' : 'Anzeigen'));
        show.setAttribute('title', on ? 'Passwort verbergen' : 'Passwort anzeigen');
    }

    // ---------- Nextcloud ----------
    function start_nextcloud() {
        var nc = root.querySelector('#pv_pw_nextcloud');
        if (!nc) return;
        nc.querySelectorAll('.pv-pw-copy').forEach(copy_button);
        var slot = nc.querySelector('#pv_nc_password');
        if (slot) {
            var box = secret_field(slot.getAttribute('data-secret'), 'Initialpasswort');
            box.querySelector('.pv-pw-secret-field').id = 'bu_pv_nc_password';
            slot.removeAttribute('data-secret');
            slot.appendChild(box);
        }
        var result = nc.querySelector('#pv_nc_reset_result');
        var reset = nc.querySelector('#bu_pv_reset_nc_password');
        if (!reset) return;
        reset.addEventListener('click', function () {
            dashboardConfirm('Dein Nextcloud-Passwort wird auf dein Initialpasswort zurückgesetzt. Ein selbst gewähltes Passwort funktioniert danach nicht mehr.', function () {
                result.textContent = '';
                result.hidden = true;
                api_call('/api/reset_nc_password', {}, function (answer) {
                    var ok = answer.success && !answer.error;
                    result.textContent = '';
                    result.setAttribute('data-result', ok ? 'ok' : 'error');
                    result.className = 'pv-pw-result ' + (ok ? 'pv-pw-ok' : 'pv-pw-err');
                    result.appendChild(icon(ok ? 'circle-check' : 'alert-circle'));
                    result.appendChild(el('span', null, ok
                        ? 'Dein Nextcloud-Passwort ist wieder dein Initialpasswort.'
                        : 'Dein Nextcloud-Passwort ließ sich leider nicht zurücksetzen. Versuche es später noch einmal oder wende dich an die Administration.'));
                    result.hidden = false;
                });
            }, { title: 'Nextcloud-Passwort zurücksetzen?', confirm: 'Zurücksetzen', danger: true });
        });
    }

    // ---------- E-Mail: states ----------
    var latest = {};        // mailbox -> {entry, item}
    var refresh_timer = null;

    function found(mailbox) {
        return latest[mailbox] || null;
    }

    function active(f) {
        return !!f && ACTIVE.indexOf(f.entry.state) >= 0;
    }

    // the state of one mailbox: label, when, a hint, the password once done
    function state_view(mailbox) {
        var f = found(mailbox);
        var box = el('div', 'pv-pw-state');
        if (!f) return box;
        var entry = f.entry;
        var s = STATES[entry.state] || { label: entry.state, icon: 'info-circle' };
        var line = el('div', 'pv-pw-st' + (s.tone ? ' pv-pw-' + s.tone : ''));
        line.setAttribute('data-state', entry.state);
        var i = icon(s.icon);
        if (entry.state === 'approved') i.classList.add('pv-pw-spin');
        line.appendChild(i);
        var text = el('span', 'pv-pw-st-text');
        text.appendChild(el('span', 'pv-pw-st-label', s.label));
        var ts = fmt_ts(entry.ts_done || entry.ts);
        if (ts) text.appendChild(el('span', 'pv-pw-st-when', (s.when ? ', ' + s.when : ' am') + ' ' + ts));
        line.appendChild(text);
        box.appendChild(line);
        var hint = null;
        if (entry.state === 'open') hint = 'Die Administration schaut sich die Anfrage an.';
        else if (entry.state === 'failed') hint = STUDENT ? 'Die Administration wurde informiert und kümmert sich darum.' : 'Die Administration wurde informiert.';
        else if (entry.state === 'rejected' || entry.state === 'cancelled') hint = 'Bitte wende dich an die Administration.';
        if (hint) box.appendChild(el('div', 'pv-pw-st-hint', hint));
        if (entry.state === 'done' && f.item.password) box.appendChild(secret_field(f.item.password, 'Passwort', mailbox + ' ' + entry.id));
        return box;
    }

    // a short word for the list rows on phones
    function state_word(mailbox) {
        var f = found(mailbox);
        if (!f) return '';
        return (STATES[f.entry.state] || { label: f.entry.state }).label;
    }

    function request_button(mailbox, label, text, cls, o_icon) {
        var b = el('button', cls || 'pv-pw-act bu_pv_request_mail_reset');
        b.type = 'button';
        b.setAttribute('data-mailbox', mailbox);
        if (o_icon !== false) b.appendChild(icon('key'));
        b.appendChild(el('span', null, text));
        b.hidden = active(found(mailbox));
        b.addEventListener('click', function (e) {
            e.stopPropagation();
            request_reset(mailbox, label);
        });
        return b;
    }

    // ---------- E-Mail: one's own mailbox (students) ----------
    function render_own() {
        root.querySelectorAll('.pv-pw-own').forEach(function (row) {
            var mailbox = row.getAttribute('data-mailbox');
            var slot = row.querySelector('.pv-pw-own-state');
            slot.textContent = '';
            slot.appendChild(state_view(mailbox));
            var b = row.querySelector('.bu_pv_request_mail_reset');
            b.hidden = active(found(mailbox));
        });
    }

    function start_own() {
        root.querySelectorAll('.pv-pw-own').forEach(function (row) {
            var mailbox = row.getAttribute('data-mailbox');
            var label = row.getAttribute('data-label');
            row.querySelectorAll('.pv-pw-copy').forEach(copy_button);
            row.querySelector('.pv-pw-own-action').appendChild(
                request_button(mailbox, label, 'Zurücksetzen beantragen', 'btn btn-secondary bu_pv_request_mail_reset'));
        });
    }

    // ---------- E-Mail: the students of a class (Klassenleitung) ----------
    function mailboxes_of(row) {
        return Array.prototype.map.call(row.querySelectorAll('.pv-pw-cell'), function (cell) {
            return {
                mailbox: cell.getAttribute('data-mailbox'),
                label: cell.getAttribute('data-label'),
                title: cell.getAttribute('data-title')
            };
        });
    }

    function render_cell(cell) {
        var mailbox = cell.getAttribute('data-mailbox');
        cell.textContent = '';
        var inner = el('div', 'pv-pw-cell-inner');
        inner.appendChild(state_view(mailbox));
        // many of them in a table: text only
        var b = request_button(mailbox, cell.getAttribute('data-label'), 'Zurücksetzen…', null, false);
        b.setAttribute('title', mailbox);
        b.setAttribute('aria-label', cell.getAttribute('data-title') + ' von ' + cell.closest('tr').getAttribute('data-name') + ' zurücksetzen');
        inner.appendChild(b);
        cell.appendChild(inner);
    }

    // where it is narrow: one quiet line with what is going on
    function render_facts(row) {
        var facts = row.querySelector('.pv-pw-row-facts');
        var parts = [];
        mailboxes_of(row).forEach(function (m) {
            var word = state_word(m.mailbox);
            if (word) parts.push(m.title + ': ' + word);
        });
        facts.textContent = parts.join(', ');
        facts.hidden = parts.length === 0;
    }

    function render_class_rows() {
        root.querySelectorAll('.pv-pw-student').forEach(function (row) {
            row.querySelectorAll('.pv-pw-cell').forEach(render_cell);
            render_facts(row);
        });
        if (open_row) fill_modal(open_row);
    }

    // ---------- a student: dialog, a sheet on phones ----------
    var modal = null;
    var open_row = null;

    function build_modal() {
        modal = el('div', 'modal pv-sheet pv-pw-modal');
        modal.id = 'mailPasswordModal';
        modal.tabIndex = -1;
        modal.setAttribute('role', 'dialog');
        modal.setAttribute('aria-hidden', 'true');
        modal.setAttribute('aria-labelledby', 'pv_pw_modal_title');
        var dialog = el('div', 'modal-dialog modal-dialog-scrollable modal-dialog-centered');
        dialog.setAttribute('role', 'document');
        var content = el('div', 'modal-content');
        var head = el('div', 'modal-header');
        var title = el('h5', 'modal-title');
        title.id = 'pv_pw_modal_title';
        head.appendChild(title);
        var body = el('div', 'modal-body');
        var foot = el('div', 'modal-footer');
        var close = el('button', 'btn btn-secondary', 'Schließen');
        close.type = 'button';
        close.setAttribute('data-dismiss', 'modal');
        foot.appendChild(close);
        content.appendChild(head);
        content.appendChild(body);
        content.appendChild(foot);
        dialog.appendChild(content);
        modal.appendChild(dialog);
        document.body.appendChild(modal);
        $(modal).on('hidden.bs.modal', function () { open_row = null; });
    }

    function fill_modal(row) {
        modal.querySelector('.modal-title').textContent = row.getAttribute('data-name');
        var body = modal.querySelector('.modal-body');
        body.textContent = '';
        mailboxes_of(row).forEach(function (m) {
            var sec = el('section', 'pv-pw-mbox');
            sec.setAttribute('data-mailbox', m.mailbox);
            sec.appendChild(el('h6', 'pv-pw-mbox-title', m.title));
            var copy = pv_copy.field(m.mailbox, { what: 'Adresse', cls: 'pv-pw-addr' });
            sec.appendChild(copy);
            sec.appendChild(state_view(m.mailbox));
            var b = request_button(m.mailbox, m.label, 'Zurücksetzen beantragen');
            sec.appendChild(el('div', 'pv-pw-mbox-action')).appendChild(b);
            body.appendChild(sec);
        });
    }

    // phones: a dialog opens once the sheet before it has gone back over
    // its history entry (pv_back), otherwise it would close at once
    function after_layer(fn) {
        setTimeout(function () {
            if (!(history.state && history.state.pvLayer)) { fn(); return; }
            var done = false;
            var go = function () {
                if (done) return;
                done = true;
                window.removeEventListener('popstate', go);
                fn();
            };
            window.addEventListener('popstate', go);
            setTimeout(go, 400);
        }, 0);
    }

    function open_student(row) {
        if (!modal) build_modal();
        open_row = row;
        fill_modal(row);
        $(modal).modal('show');
    }

    function start_class_rows() {
        root.querySelectorAll('.pv-pw-student').forEach(function (row) {
            var open = row.querySelector('.pv-pw-open');
            open.addEventListener('click', function (e) {
                open_student(e.currentTarget.closest('.pv-pw-student'));
            });
        });
    }

    // ---------- E-Mail: requests ----------
    function request_reset(mailbox, label) {
        // from the dialog: close it first, the confirmation opens after it
        if (modal && open_row && modal.classList.contains('show')) {
            $(modal).one('hidden.bs.modal', function () { after_layer(function () { request_reset(mailbox, label); }); });
            $(modal).modal('hide');
            return;
        }
        var text = STUDENT
            ? 'Dein E-Mail-Passwort wird nach Freigabe durch die Administration auf das ursprüngliche Passwort aus deinem E-Mail-Brief zurückgesetzt. Ein selbst gewähltes Passwort funktioniert danach nicht mehr. Deine Eltern bekommen eine kurze Nachricht darüber.'
            : 'Das Passwort für ' + label + ' (' + mailbox + ') wird nach Freigabe durch die Administration auf das ursprüngliche Passwort aus dem E-Mail-Brief zurückgesetzt. Ein selbst gewähltes Passwort funktioniert danach nicht mehr.';
        dashboardConfirm(text, function () {
            api_call('/api/request_mail_password_reset', { mailbox: mailbox }, function (answer) {
                if (!answer.success) return;
                if (answer.result === 'pending') {
                    dashboardAlert('Für dieses Postfach läuft schon eine Anfrage.', 'Schon beantragt');
                } else if (answer.result === 'limit') {
                    dashboardAlert('Das Passwort wurde heute schon mehrmals zurückgesetzt. Bitte versuche es morgen noch einmal oder wende dich an die Administration.', 'Heute nicht mehr möglich');
                }
                load();
            });
        }, { title: 'E-Mail-Passwort zurücksetzen?', confirm: 'Beantragen', danger: true });
    }

    function render(answer) {
        latest = {};
        answer.cases.forEach(function (entry) {
            entry.mailboxes.forEach(function (item) {
                if (item.latest) latest[item.mailbox] = { entry: entry, item: item };
            });
        });
        render_own();
        render_class_rows();
        clearTimeout(refresh_timer);
        if (answer.cases.some(function (entry) { return ACTIVE.indexOf(entry.state) >= 0; })) {
            refresh_timer = setTimeout(load, 10000);
        }
    }

    function load() {
        if (!root.querySelector('.pv-pw-own, .pv-pw-student')) return;
        api_call('/api/mail_password_reset_status', {}, function (answer) {
            if (answer.success) render(answer);
        }, { no_please_wait: true });
    }

    function start() {
        start_nextcloud();
        start_own();
        start_class_rows();
        root.querySelectorAll('.pv-pw-student .pv-pw-cell').forEach(render_cell);
        load();
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();
})();
