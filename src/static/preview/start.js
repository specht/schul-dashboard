// Neues Design (Vorschau), start page: "Zu erledigen" – open polls, books the
// library needs back, deadlines of the Datentresor and the hint about the
// Authenticator app in one place, never in a column of their own beside the
// timetable (doc/Gestaltung.md, 12).
//
// - wide screens: a box at the top of the column beside the week (#pv_side)
// - phones (the day as an agenda): at the top of the first day, above the
//   first lesson; more than two rows fold into one line
// - tablets and in between: the same above the week
//
// The data comes with the page and with /api/refresh_start_page
// (include/start_todo.rb); timetable.html calls pv_todo.place() whenever it
// draws the agenda, the week's header or the side column. Styles:
// preview/start.css. Only loaded in the new design.
(function () {
    'use strict';
    var data = window.pv_todo_data || { items: [], count: 0 };
    var el = document.createElement('section');
    el.className = 'pv-todo';
    el.id = 'pv_todo';
    el.setAttribute('aria-label', 'Zu erledigen');
    var folded = true;          // phones: more than two rows as one line
    var show_hidden = false;    // hidden polls, after »… anzeigen«
    var done = {};              // rows dealt with here (OTP: switched, later)
    var mode = null;

    var WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
    var DEADLINES = {
        noteneingabe: ['Noteneingabe im Datentresor', null],
        zeugniskonferenz: ['Für die Zeugniskonferenzen markieren', 'Für Klassenleitungen: wen du besprechen möchtest. Wer eine Note ab 4– hat, ist schon markiert.'],
        sozialverhalten: ['Arbeits- und Sozialverhalten eintragen', 'Damit die Klassenleitungen die Zeugnisse rechtzeitig drucken können.'],
    };

    function parse_time(s) {
        // '2026-11-20T14:00:00', local time (the school's)
        var m = /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d)/.exec(s || '');
        return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) : null;
    }

    function hhmm(d) {
        return d.getHours() + ':' + String(d.getMinutes()).padStart(2, '0');
    }

    // "bis Fr 14:00", close to the end a countdown: "noch 1 h 20 min"
    function when_label(end) {
        var now = new Date();
        var ms = end - now;
        if (ms <= 0) return null;
        if (ms < 3 * 3600 * 1000) {
            var min = Math.max(1, Math.ceil(ms / 60000));
            var text = min < 60 ? min + ' min' : Math.floor(min / 60) + ' h' + (min % 60 ? ' ' + (min % 60) + ' min' : '');
            return { text: 'noch ' + text, soon: true };
        }
        var day = function (d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
        var days = Math.round((day(end) - day(now)) / 86400000);
        var date;
        if (days === 0) date = 'heute';
        else if (days === 1) date = 'morgen';
        else if (days < 7) date = WEEKDAYS[end.getDay()];
        else date = end.getDate() + '.' + (end.getMonth() + 1) + '.,';
        return { text: 'bis ' + date + ' ' + hhmm(end), soon: false };
    }

    function item_key(item) {
        return item.kind + ':' + (item.prid || item.key || item.variant || '');
    }

    function expired(item) {
        if (!item.end) return false;
        var end = parse_time(item.end);
        return !!end && end <= new Date();
    }

    function is_open(item) {
        return !item.hidden && !item.answered && !done[item_key(item)] && !expired(item);
    }

    function current_items() {
        return (data.items || []).filter(function (item) {
            return !expired(item) && done[item_key(item)] !== 'gone';
        });
    }

    function open_count() {
        return current_items().filter(is_open).length;
    }

    // ---------- rows ----------

    function node(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined && text !== null) n.textContent = text;
        return n;
    }

    function icon(name) {
        var i = node('i', 'ti ti-' + name);
        i.setAttribute('aria-hidden', 'true');
        return i;
    }

    function button(label, cls, href) {
        var b = node(href ? 'a' : 'button', 'pv-todo-btn' + (cls ? ' ' + cls : ''), label);
        if (href) b.setAttribute('href', href); else b.setAttribute('type', 'button');
        return b;
    }

    function when_span(item, prefix) {
        var span = node('span', 'pv-todo-when');
        span.setAttribute('data-end', item.end);
        if (prefix) span.setAttribute('data-prefix', prefix);
        update_when(span);
        return span;
    }

    function update_when(span) {
        var label = when_label(parse_time(span.getAttribute('data-end')));
        var prefix = span.getAttribute('data-prefix') || '';
        span.textContent = label ? prefix + label.text : '';
        span.classList.toggle('pv-todo-soon', !!(label && label.soon));
    }

    function facts(parts) {
        var small = node('small', 'pv-todo-facts');
        parts.filter(function (p) { return p; }).forEach(function (p, i) {
            if (i > 0) small.appendChild(document.createTextNode(', '));
            small.appendChild(typeof p === 'string' ? document.createTextNode(p) : p);
        });
        return small;
    }

    function row(item) {
        var r = node('div', 'pv-todo-row');
        r.setAttribute('data-kind', item.kind);
        var lead = node('span', 'pv-todo-lead');
        var text = node('span', 'pv-todo-text');
        var actions = node('span', 'pv-todo-actions');
        var key = item_key(item);
        if (item.kind === 'poll') {
            r.setAttribute('data-prid', item.prid);
            var avatar = node('span', 'pv-todo-avatar');
            if (item.avatar) avatar.style.backgroundImage = 'url(' + JSON.stringify(item.avatar) + ')';
            lead.appendChild(avatar);
            text.appendChild(node('b', 'pv-todo-title', item.title));
            var state = item.answered ? 'beantwortet' : (item.hidden ? 'ausgeblendet' : null);
            text.appendChild(facts([item.organizer, state, item.answered ? null : when_span(item)]));
            var launch = button(item.answered ? 'Ändern' : 'Teilnehmen', 'bu-launch-poll' + (item.answered ? ' pv-todo-quiet' : ''));
            launch.setAttribute('data-poll-run-id', item.prid);
            if (item.answered) r.classList.add('pv-todo-done');
            actions.appendChild(launch);
        } else if (item.kind === 'deadline') {
            var info = DEADLINES[item.key] || [item.key, null];
            lead.appendChild(icon('hourglass'));
            text.appendChild(node('b', 'pv-todo-title', info[0]));
            text.appendChild(facts([when_span(item)]));
            if (info[1]) text.appendChild(node('small', 'pv-todo-note', info[1]));
        } else if (item.kind === 'books') {
            lead.appendChild(icon('book'));
            text.appendChild(node('b', 'pv-todo-title', item.count === 1 ? 'Ein Buch zurückbringen' : item.count + ' Bücher zurückbringen'));
            text.appendChild(facts([(item.count === 1 ? 'Die Bibliothek braucht es' : 'Die Bibliothek braucht sie') + ' dringend, bitte ins Rückgaberegal']));
            actions.appendChild(button('Meine Bücher', null, '/bibliothek'));
        } else if (item.kind === 'otp') {
            lead.appendChild(icon(done[key] === 'switched' ? 'check' : 'qrcode'));
            if (done[key] === 'switched') {
                text.appendChild(node('b', 'pv-todo-title', 'Umgestellt'));
                text.appendChild(facts(['Ab jetzt kommt dein erster Code per E-Mail, der zweite aus deiner Authenticator-App']));
                r.classList.add('pv-todo-done');
            } else if (item.variant === 'switch') {
                text.appendChild(node('b', 'pv-todo-title', 'Deine Authenticator-App kann mehr'));
                text.appendChild(facts(['Mit »Code per E-Mail« als Standard kommt der zweite Code aus der App, ganz ohne SMS']));
                actions.appendChild(button('Umstellen', 'pv-todo-otp-switch'));
                actions.appendChild(button('Später', 'pv-todo-otp-later pv-todo-quiet'));
            } else {
                text.appendChild(node('b', 'pv-todo-title', 'Anmelden ohne SMS'));
                text.appendChild(facts(['Mit einer Authenticator-App steht dein Code sofort auf dem Handy, auch ohne Netz']));
                actions.appendChild(button('Einrichten', null, '/profil#anmeldung'));
                actions.appendChild(button('Später', 'pv-todo-otp-later pv-todo-quiet'));
            }
        }
        r.appendChild(lead);
        r.appendChild(text);
        if (actions.children.length > 0) r.appendChild(actions);
        return r;
    }

    // ---------- the box ----------

    function render() {
        var items = current_items();
        var hidden = items.filter(function (item) { return item.hidden; });
        var rows = items.filter(function (item) { return !item.hidden || show_hidden; });
        var open = items.filter(is_open).length;
        el.textContent = '';
        el.className = 'pv-todo pv-todo-' + mode + (mode === 'side' ? ' pv-side-box' : '');
        var foldable = mode !== 'side' && rows.length > 2;
        el.classList.toggle('pv-todo-folded', foldable && folded);
        if (foldable) {
            var fold = node('button', 'pv-todo-fold');
            fold.type = 'button';
            fold.setAttribute('aria-expanded', folded ? 'false' : 'true');
            fold.setAttribute('aria-controls', 'pv_todo_list');
            var answered = rows.filter(function (item) { return item.answered || done[item_key(item)]; }).length;
            var label = open > 0
                ? open + (open === 1 ? ' Aufgabe offen' : ' Aufgaben offen') + (answered > 0 ? ', ' + answered + ' erledigt' : '')
                : 'Alles erledigt';
            fold.appendChild(icon('list-check'));
            fold.appendChild(node('span', 'pv-todo-fold-label', label));
            fold.appendChild(icon('chevron-down'));
            el.appendChild(fold);
        } else {
            el.appendChild(node('h3', 'pv-todo-head', 'Zu erledigen'));
        }
        var list = node('div', 'pv-todo-list');
        list.id = 'pv_todo_list';
        rows.forEach(function (item) { list.appendChild(row(item)); });
        if (hidden.length > 0 && !show_hidden) {
            var more = node('button', 'pv-todo-show-hidden', hidden.length === 1 ? '1 ausgeblendete Umfrage anzeigen' : hidden.length + ' ausgeblendete Umfragen anzeigen');
            more.type = 'button';
            list.appendChild(more);
        }
        el.appendChild(list);
        last_expired = expired_count();
        set_badges(open);
        return items.length > 0;
    }

    // the badges on "Stundenplan" (sidebar) and "Heute" (tab bar), as the
    // server drew them on every page (include/start_todo.rb)
    function set_badges(n) {
        document.querySelectorAll('.pv-todo-badge').forEach(function (b) {
            b.hidden = n === 0;
            var num = b.querySelector('.pv-todo-badge-n');
            if (num) num.textContent = String(n);
            var link = b.closest('a');
            if (link && link.getAttribute('title')) link.setAttribute('title', 'Stundenplan' + (n > 0 ? ' ' + n + ' offen' : ''));
        });
        var tab = document.querySelector(".pv-tabbar a.pv-tab[href='/']");
        if (tab) {
            var badge = tab.querySelector('.pv-badge');
            if (n > 0) {
                if (!badge) { badge = node('span', 'pv-badge'); tab.insertBefore(badge, tab.firstChild); }
                badge.textContent = String(n);
            } else if (badge) badge.remove();
        }
    }

    function wanted_mode() {
        var body = document.body;
        if (!body.classList.contains('ui-preview') || !window.calendar || !document.getElementById('calendar')) return null;
        var side = document.getElementById('pv_side');
        if (side && !side.hidden && body.classList.contains('pv-week-head-on') && window.matchMedia('(min-width: 1200px)').matches) return 'side';
        if (body.classList.contains('pv-agenda-on')) {
            if (location.hash === '#woche') return null;
            // the first day the page shows (today, at the weekend Monday) or today
            var shown = window.calendar.view.currentStart;
            var first = (window.timetable_options || {}).initialDate;
            var iso = shown.getFullYear() + '-' + String(shown.getMonth() + 1).padStart(2, '0') + '-' + String(shown.getDate()).padStart(2, '0');
            return (iso === first || shown.toDateString() === new Date().toDateString()) ? 'agenda' : null;
        }
        return 'top';
    }

    // into the right place for what the page shows now (or out)
    function place() {
        mode = wanted_mode();
        if (!mode || !render()) {
            if (el.parentNode) el.parentNode.removeChild(el);
            last_expired = expired_count();
            set_badges(open_count());
            return;
        }
        if (mode === 'side') {
            var side = document.getElementById('pv_side');
            if (side.firstChild !== el) side.insertBefore(el, side.firstChild);
        } else if (mode === 'agenda') {
            var agenda = document.getElementById('pv_agenda');
            if (agenda.firstChild !== el) agenda.insertBefore(el, agenda.firstChild);
        } else {
            var calendar = document.getElementById('calendar');
            if (calendar.previousSibling !== el) calendar.parentNode.insertBefore(el, calendar);
        }
    }

    function update(new_data) {
        data = new_data || { items: [], count: 0 };
        // what the server no longer lists is gone for good
        place();
    }

    // fresh data after answering a poll (it is then answered, not open)
    function refresh() {
        jQuery.post({ url: '/api/refresh_start_page', data: '{}', contentType: 'application/json', dataType: 'json' }).done(function (d) {
            if (d.todo) update(d.todo);
        });
    }

    // ---------- actions (delegated: the rows are drawn anew) ----------

    document.addEventListener('click', function (e) {
        var t = e.target.closest ? e.target.closest('.pv-todo button') : null;
        if (!t || !el.contains(t)) return;
        if (t.classList.contains('pv-todo-fold')) {
            folded = !folded;
            render();
            var again = el.querySelector('.pv-todo-fold');
            if (again) again.focus();
        } else if (t.classList.contains('pv-todo-show-hidden')) {
            show_hidden = true;
            render();
        } else if (t.classList.contains('pv-todo-otp-switch')) {
            t.disabled = true;
            api_call('/api/set_preferred_login_method', { method: 'email' }, function (d) {
                if (!d.success) { t.disabled = false; return; }
                done['otp:switch'] = 'switched';
                render();
            });
        } else if (t.classList.contains('pv-todo-otp-later')) {
            t.disabled = true;
            api_call('/api/snooze_otp_nudge', {}, function (d) {
                if (!d.success) { t.disabled = false; return; }
                current_items().forEach(function (item) { if (item.kind === 'otp') done[item_key(item)] = 'gone'; });
                place();
            });
        }
    });

    // the countdowns; a row whose time is over goes (and the badges count less)
    var last_expired = 0;
    function expired_count() {
        return (data.items || []).filter(expired).length;
    }
    setInterval(function () {
        if (expired_count() !== last_expired) { place(); return; }
        el.querySelectorAll('.pv-todo-when').forEach(update_when);
    }, 30 * 1000);

    jQuery(document).on('hidden.bs.modal', '#pollResponseModal', refresh);

    window.pv_todo = { place: place, update: update };
})();
