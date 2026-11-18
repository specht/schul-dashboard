// Neues Design (Vorschau): Klassenarbeiten (/tests). Only the new design
// loads this file (tests_preview_script in include/tests.rb); the page hands
// over its calendar options (pv_tests.options) before FullCalendar renders,
// so today's design keeps its page byte for byte.
//
// Desktop and tablet: the month as a grid on one panel, with a calm header
// (month, the class as a menu, today, back and forth, »Eintragen«). Phones:
// the month as an agenda, week by week; details and the form are sheets.
// Entries keep their kinds apart: class tests (KA, LEK, MSA, Vera) in the
// subject's colour, other entries of the class (Exkursion, Fahrt …) as a
// quiet surface with the subject colour at the edge, the school's own dates
// in the accent, holidays and A/B weeks quiet. Styles: preview/tests.css.
(function() {
    'use strict';

    var MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    var WEEKDAYS = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
    var WD = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
    var TYPES = { KA: 'Klassenarbeit' };
    var EXAMS = ['KA', 'LEK', 'MSA', 'Vera'];
    // the order within a day: holidays, the school's dates, tests, other
    // entries, the A/B week last (it spans the week and would push the rest down)
    var ORDER = { holiday: 0, school: 1, exam: 2, other: 3, week: 4 };
    var PHONE = window.matchMedia('(max-width: 767px)');
    var MENU_LAYER = 'tests-klasse';

    var calendar = null;
    var opts = null;
    var ui = {};
    var klassen = [];          // [{key, label, active}]
    var active_label = '';
    var manage_href = null;

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

    function can_add() {
        return !!(window.possible_lessons && possible_lessons.fach_order && possible_lessons.fach_order.length > 0);
    }

    // 'Ma', 'EN', 'Nawi', 'La LK' → the subject's colour token, if there is one
    // (design_tokens.rb, subject_key)
    function subject_key(fach) {
        var key = String(fach || '').trim().split(/[\s_-]/)[0].toLowerCase();
        if (!key) return null;
        var v = getComputedStyle(document.documentElement).getPropertyValue('--subj-' + key).trim();
        return v ? key : null;
    }

    function fach_label(fach) {
        var tr = (window.possible_lessons && possible_lessons.fach_tr) || {};
        return tr[fach] || fach || '';
    }

    function ymd(d) {
        return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    }

    function same_day(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function short_date(d) {
        return WD[d.getDay()] + ', ' + d.getDate() + '.' + (d.getMonth() + 1) + '.';
    }

    // the last day of an all-day event (FullCalendar's end is exclusive)
    function last_day(e) {
        if (!e.end) return e.start;
        var d = new Date(e.end);
        d.setDate(d.getDate() - 1);
        return d < e.start ? e.start : d;
    }

    function date_text(e) {
        var a = e.start, b = last_day(e);
        return same_day(a, b) ? short_date(a) : short_date(a) + ' bis ' + short_date(b);
    }

    function kind_of(x) {
        var p = x.extendedProps || {};
        var type = p.type || 'test';
        if (type === 'test') return EXAMS.indexOf((p.test || {}).typ) >= 0 ? 'exam' : 'other';
        if (type === 'holiday') return 'holiday';
        if (type === 'switch_week') return 'week';
        return 'school';
    }

    // the entries as the page delivers them, with the kind instead of a colour
    function classify(x) {
        x.extendedProps = x.extendedProps || {};
        var kind = kind_of(x);
        var subj = (kind === 'exam' || kind === 'other') ? subject_key((x.extendedProps.test || {}).fach) : null;
        delete x.color;
        x.extendedProps.pv_kind = kind;
        x.extendedProps.pv_subj = subj;
        x.extendedProps.pv_order = ORDER[kind];
        x.classNames = ['pv-t-' + kind];
        return x;
    }

    function title_of(e) {
        var p = e.extendedProps;
        if (p.type === 'test') {
            var t = p.test || {};
            return ((TYPES[t.typ] || t.typ || '') + ' ' + fach_label(t.fach)).trim();
        }
        return e.title;
    }

    // a quiet line of facts (doc/Gestaltung.md: commas, no pills)
    function facts_of(e, with_date) {
        var p = e.extendedProps, facts = [];
        if (with_date) facts.push(date_text(e));
        else if (!same_day(e.start, last_day(e))) facts.push('bis ' + short_date(last_day(e)));
        if (p.type === 'test') {
            var t = p.test || {};
            if (p.shorthand) facts.push(p.shorthand);
            if ((t.kommentar || '').trim()) facts.push(t.kommentar.trim());
            if (p.is_session_user) facts.push('dein Eintrag');
        } else if (p.pv_kind === 'holiday') {
            facts.push('Ferien und Feiertage');
        } else if (p.pv_kind === 'school') {
            facts.push('Termin der Schule');
        }
        return facts.join(', ');
    }

    function code_of(e) {
        var fach = String((e.extendedProps.test || {}).fach || '').trim().split(/[\s_]/)[0];
        return fach.substr(0, 4);
    }

    function paint(node, e) {
        var subj = e.extendedProps.pv_subj;
        if (!subj) return;
        node.style.setProperty('--c', 'var(--subj-' + subj + ')');
        node.style.setProperty('--ci', 'var(--subj-' + subj + '-ink)');
    }

    // ---------- the class menu (a popover; a sheet on phones) ----------
    function close_menu(animate) {
        var menu = document.querySelector('.pv-tests-menu');
        if (!menu) return;
        if (window.pv_back) window.pv_back.closed(MENU_LAYER);
        document.querySelectorAll('.pv-plan-veil').forEach(function(v) { v.remove(); });
        document.body.classList.remove('pv-sheet-open');
        document.removeEventListener('mousedown', on_outside, true);
        document.removeEventListener('keydown', on_key, true);
        if (ui.klasse) ui.klasse.setAttribute('aria-expanded', 'false');
        if (animate && PHONE.matches) {
            menu.style.transition = 'transform 0.18s ease-in';
            menu.style.transform = 'translateY(100%)';
            setTimeout(function() { menu.remove(); }, 180);
        } else {
            menu.remove();
        }
    }

    function on_outside(e) {
        if (!e.target.closest('.pv-tests-menu, #bu_pv_tests_klasse')) close_menu(false);
    }

    function on_key(e) {
        if (e.key === 'Escape') {
            e.stopPropagation();
            close_menu(false);
            ui.klasse.focus();
        }
    }

    function open_menu() {
        if (document.querySelector('.pv-tests-menu')) { close_menu(false); return; }
        var phone = PHONE.matches;
        // preview.js closes sheets pulled down through this
        window.pv_close_plan_menu = close_menu;
        var menu = el('div', 'pv-plan-menu pv-tests-menu');
        menu.setAttribute('role', 'dialog');
        menu.setAttribute('aria-label', 'Klasse wählen');
        menu.appendChild(el('div', 'pv-tests-menu-title', 'Klasse wählen'));
        var groups = [];
        klassen.forEach(function(k) {
            var m = k.label.match(/^(\d+)/);
            var grade = m ? m[1] : 'Weitere';
            var g = groups.filter(function(x) { return x.grade === grade; })[0];
            if (!g) groups.push(g = { grade: grade, items: [] });
            g.items.push(k);
        });
        groups.forEach(function(g) {
            var row = el('div', 'pv-tests-menu-row');
            row.setAttribute('aria-label', g.grade === 'Weitere' ? 'Weitere' : 'Klassenstufe ' + g.grade);
            row.setAttribute('role', 'group');
            var list = el('div', 'pv-tests-menu-list');
            g.items.forEach(function(k) {
                var a = el('a', 'pv-tests-menu-klasse' + (k.active ? ' active' : ''), k.label);
                a.href = '/tests/' + encodeURIComponent(k.key);
                if (k.active) a.setAttribute('aria-current', 'page');
                list.appendChild(a);
            });
            row.appendChild(list);
            menu.appendChild(row);
        });
        if (phone) {
            var veil = el('div', 'pv-menu-veil pv-plan-veil');
            veil.addEventListener('click', function() { close_menu(true); });
            document.body.appendChild(veil);
            document.body.appendChild(menu);
            document.body.classList.add('pv-sheet-open');
            if (window.pv_back) window.pv_back.opened(MENU_LAYER, function() { close_menu(true); });
        } else {
            ui.klasse.parentNode.appendChild(menu);
            document.addEventListener('mousedown', on_outside, true);
        }
        document.addEventListener('keydown', on_key, true);
        ui.klasse.setAttribute('aria-expanded', 'true');
        var current = menu.querySelector('.active') || menu.querySelector('a');
        if (current && !phone) current.focus({ preventScroll: true });
    }

    // ---------- the panel ----------
    function build() {
        var old = document.getElementById('calendar');
        var row = old.closest('.row');
        // the class chips and »Kalender verwalten« come from the server
        // (print_test_klassen_chooser): who may see what stays there
        document.querySelectorAll('.ttc[data-klasse]').forEach(function(a) {
            var k = { key: a.getAttribute('data-klasse'), label: a.textContent.trim(), active: a.classList.contains('active') };
            klassen.push(k);
            if (k.active) active_label = k.label;
        });
        if (!active_label) active_label = window.klasse || '';
        var manage = document.querySelector('a.ttc[href$="/manage_test_calendar"]');
        if (manage) manage_href = manage.getAttribute('href');

        document.body.classList.add('pv-tests-page');
        if (can_add()) document.body.classList.add('pv-tests-can-add');
        var panel = el('section', 'pv-tests');
        panel.setAttribute('aria-label', 'Klassenarbeiten');
        var head = el('div', 'pv-tests-head');
        var title = el('div', 'pv-tests-title');
        ui.title = el('h2', null, '');
        ui.title.id = 'pv_tests_title';
        ui.sub = el('div', 'pv-tests-sub', '');
        title.appendChild(ui.title);
        title.appendChild(ui.sub);
        head.appendChild(title);

        var tools = el('div', 'pv-tests-tools');
        var wrap = el('div', 'pv-tests-klasse-wrap');
        ui.klasse = el('button', 'pv-tests-btn pv-tests-klasse');
        ui.klasse.type = 'button';
        ui.klasse.id = 'bu_pv_tests_klasse';
        ui.klasse.setAttribute('aria-haspopup', 'dialog');
        ui.klasse.setAttribute('aria-expanded', 'false');
        ui.klasse.appendChild(el('span', null, active_label ? 'Klasse ' + active_label : 'Klasse wählen'));
        ui.klasse.appendChild(icon('chevron-down'));
        ui.klasse.addEventListener('click', function(e) { e.preventDefault(); open_menu(); });
        wrap.appendChild(ui.klasse);
        tools.appendChild(wrap);

        ui.today = el('button', 'pv-tests-btn', 'Heute');
        ui.today.type = 'button';
        ui.today.id = 'bu_pv_tests_today';
        ui.today.addEventListener('click', function() { calendar.today(); });
        tools.appendChild(ui.today);

        var seg = el('div', 'pv-tests-seg');
        var prev = el('button');
        prev.type = 'button';
        prev.id = 'bu_pv_tests_prev';
        prev.setAttribute('aria-label', 'Voriger Monat');
        prev.title = 'Voriger Monat';
        prev.appendChild(icon('chevron-left'));
        prev.addEventListener('click', function() { calendar.prev(); });
        var next = el('button');
        next.type = 'button';
        next.id = 'bu_pv_tests_next';
        next.setAttribute('aria-label', 'Nächster Monat');
        next.title = 'Nächster Monat';
        next.appendChild(icon('chevron-right'));
        next.addEventListener('click', function() { calendar.next(); });
        seg.appendChild(prev);
        seg.appendChild(next);
        tools.appendChild(seg);
        head.appendChild(tools);

        // the main action: only for those who teach in the class
        if (can_add()) {
            var add = el('button', 'btn btn-primary pv-tests-add');
            add.type = 'button';
            add.id = 'bu_pv_tests_add';
            add.appendChild(icon('plus'));
            add.appendChild(el('span', 'pv-tests-add-long', 'Eintragen'));
            add.appendChild(el('span', 'pv-tests-add-short', 'Neu'));
            add.addEventListener('click', add_entry);
            head.appendChild(add);
        }
        panel.appendChild(head);

        panel.appendChild(old);
        ui.agenda = el('div', 'pv-tests-agenda');
        ui.agenda.id = 'pv_tests_agenda';
        panel.appendChild(ui.agenda);

        var foot = el('div', 'pv-tests-foot');
        var legend = el('div', 'pv-tests-legend');
        [['exam', 'Klassenarbeit, LEK, in der Fachfarbe'], ['other', 'Exkursion, Fahrt, Elternabend'],
         ['school', 'Termin der Schule'], ['holiday', 'Ferien, Feiertage']].forEach(function(x) {
            var item = el('span', 'pv-tests-legend-item pv-tl-' + x[0]);
            item.appendChild(el('span', 'pv-tests-swatch'));
            item.appendChild(el('span', null, x[1]));
            legend.appendChild(item);
        });
        foot.appendChild(legend);
        if (can_add()) foot.appendChild(el('span', 'pv-tests-hint', 'Klicke auf einen Tag, um etwas einzutragen.'));
        if (manage_href) {
            var m = el('a', 'pv-tests-manage');
            m.href = manage_href;
            m.id = 'bu_pv_tests_manage';
            m.appendChild(icon('settings'));
            m.appendChild(el('span', null, 'Kalender verwalten'));
            foot.appendChild(m);
        }
        panel.appendChild(foot);

        row.parentNode.insertBefore(panel, row);
        row.hidden = true;

        ['testModal', 'showTestModal'].forEach(function(id) {
            var modal = document.getElementById(id);
            if (modal) modal.classList.add('pv-sheet');
        });
    }

    // a new entry: today if it is in the shown month, else its first weekday
    function add_entry() {
        var view = calendar.view;
        var d = new Date();
        if (!(d >= view.currentStart && d < view.currentEnd)) d = new Date(view.currentStart);
        while (d.getDay() === 0 || d.getDay() === 6) d.setDate(d.getDate() + 1);
        opts.dateClick({ dateStr: ymd(d), date: d, allDay: true, view: view });
    }

    function render_head() {
        var view = calendar.view;
        var start = view.currentStart;
        ui.title.textContent = MONTHS[start.getMonth()] + ' ' + start.getFullYear();
        var now = new Date();
        ui.today.disabled = now >= view.currentStart && now < view.currentEnd;
        var exams = calendar.getEvents().filter(function(e) {
            return e.extendedProps.pv_kind === 'exam' && e.start >= view.currentStart && e.start < view.currentEnd;
        }).length;
        var count = exams === 0 ? 'keine Arbeiten in diesem Monat' : (exams === 1 ? '1 Arbeit in diesem Monat' : exams + ' Arbeiten in diesem Monat');
        ui.sub.textContent = (active_label ? 'Klasse ' + active_label + ', ' : '') + count;
    }

    function monday_of(d) {
        var m = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        m.setDate(m.getDate() - ((m.getDay() + 6) % 7));
        return m;
    }

    function iso_week(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        var day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        var y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return Math.ceil(((t - y) / 86400000 + 1) / 7);
    }

    function day_heading(d) {
        var now = new Date();
        if (same_day(d, now)) return 'Heute';
        var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        if (same_day(d, tomorrow)) return 'Morgen';
        return WEEKDAYS[d.getDay()] + ', ' + d.getDate() + '.' + (d.getMonth() + 1) + '.';
    }

    function agenda_row(e) {
        var p = e.extendedProps, kind = p.pv_kind;
        var row = el('button', 'pv-ta-row pv-ta-' + kind);
        row.type = 'button';
        paint(row, e);
        var mark = el('span', 'pv-ta-mark');
        if (kind === 'holiday') mark.appendChild(icon('sun'));
        else if (kind === 'school') mark.appendChild(icon('calendar'));
        else if (code_of(e)) mark.textContent = code_of(e);
        else mark.appendChild(icon('school'));
        row.appendChild(mark);
        var text = el('span', 'pv-ta-text');
        text.appendChild(el('b', null, title_of(e)));
        var facts = facts_of(e, false);
        if (facts) text.appendChild(el('small', null, facts));
        row.appendChild(text);
        row.appendChild(icon('chevron-right'));
        row.addEventListener('click', function(ev) {
            opts.eventClick({ event: e, el: ev.currentTarget, jsEvent: ev, view: calendar.view });
        });
        return row;
    }

    // phones: the month week by week, the days with entries
    function render_agenda() {
        var box = ui.agenda;
        box.textContent = '';
        var view = calendar.view;
        var start = view.currentStart, end = view.currentEnd;
        var events = calendar.getEvents().filter(function(e) {
            return e.start < end && (e.end || e.start) > start;
        });
        var anything = false;
        for (var w = monday_of(start); w < end; w.setDate(w.getDate() + 7)) {
            var lo = w < start ? new Date(start) : new Date(w);
            var w_end = new Date(w);
            w_end.setDate(w_end.getDate() + 7);
            var hi = w_end > end ? end : w_end;
            var fri = new Date(w);
            fri.setDate(fri.getDate() + 4);
            var shown_to = fri < hi ? fri : new Date(hi.getTime() - 86400000);
            var in_week = events.filter(function(e) {
                if (e.extendedProps.pv_kind === 'week') return false;
                var anchor = e.start < start ? start : e.start;
                return anchor >= lo && anchor < hi;
            }).sort(function(a, b) {
                var aa = a.start < start ? start : a.start, bb = b.start < start ? start : b.start;
                return (aa - bb) || (a.extendedProps.pv_order - b.extendedProps.pv_order);
            });
            // a week that is only a weekend of this month, with nothing in it
            if (in_week.length === 0 && lo > shown_to) continue;
            var sw = events.filter(function(e) { return e.extendedProps.pv_kind === 'week' && e.start < hi && e.end > lo; })[0];
            var head = el('div', 'pv-ta-week');
            var range = lo > shown_to ? lo.getDate() + '. ' + MONTHS[lo.getMonth()]
                : (same_day(lo, shown_to) ? lo.getDate() + '. ' + MONTHS[lo.getMonth()]
                    : lo.getDate() + '. bis ' + shown_to.getDate() + '. ' + MONTHS[shown_to.getMonth()]);
            head.appendChild(el('b', null, 'KW ' + iso_week(w)));
            head.appendChild(el('span', null, range + (sw ? ', ' + sw.title : '')));
            box.appendChild(head);
            if (in_week.length === 0) {
                box.appendChild(el('div', 'pv-ta-empty', 'Nichts eingetragen.'));
                continue;
            }
            anything = true;
            var day = null, list = null;
            in_week.forEach(function(e) {
                var anchor = e.start < start ? start : e.start;
                if (!day || !same_day(day, anchor)) {
                    day = anchor;
                    var h = el('div', 'pv-ta-day' + (same_day(anchor, new Date()) ? ' pv-ta-today' : ''), day_heading(anchor));
                    box.appendChild(h);
                    list = el('div', 'pv-ta-list');
                    box.appendChild(list);
                }
                list.appendChild(agenda_row(e));
            });
        }
        if (!anything) {
            box.insertBefore(el('p', 'pv-ta-none', can_add()
                ? 'In diesem Monat ist für die Klasse noch nichts eingetragen. Mit »Neu« trägst du eine Arbeit ein.'
                : 'In diesem Monat ist für die Klasse noch nichts eingetragen.'), box.firstChild);
        }
    }

    var pending = null;
    function refresh() {
        if (pending) return;
        pending = setTimeout(function() {
            pending = null;
            if (!calendar) return;
            render_head();
            render_agenda();
        }, 0);
    }

    // details of an entry one cannot edit (someone else's test, holidays,
    // the school's dates), as text
    function show_details(e) {
        var p = e.extendedProps;
        var modal = $('#showTestModal');
        var title = title_of(e);
        if (p.type === 'test') title += ' (' + ((p.test || {}).klasse || active_label) + ')';
        modal.find('.modal-header').empty().append($('<h5 class="modal-title">').text(title));
        var body = modal.find('.modal-body').empty();
        var facts = $('<div class="pv-tests-facts">');
        var line = function(name, text) {
            if (!text) return;
            facts.append($('<div class="pv-tests-fact">').append(
                $('<i class="ti" aria-hidden="true">').addClass('ti-' + name), $('<span>').text(text)));
        };
        line('calendar', date_text(e));
        if (p.type === 'test') {
            var t = p.test || {};
            line('user', 'Eingetragen von ' + (p.display_name || p.shorthand || 'NN') + (p.shorthand && p.display_name && p.display_name !== p.shorthand ? ' (' + p.shorthand + ')' : ''));
            line('note', (t.kommentar || '').trim());
            line('eye', t.public_for_klasse === 'yes' ? 'Im Stundenplan der Klasse sichtbar' : 'Nur für Lehrkräfte sichtbar');
        } else if (p.pv_kind === 'holiday') {
            line('sun', 'Ferien und Feiertage');
        } else if (p.pv_kind === 'week') {
            line('repeat', 'Wechselwoche');
        } else {
            line('school', 'Termin der Schule');
        }
        body.append(facts);
        modal.modal('show');
    }

    function mount(info) {
        paint(info.el, info.event);
        var facts = facts_of(info.event, true);
        info.el.setAttribute('title', title_of(info.event) + (facts ? ', ' + facts : ''));
    }

    window.pv_tests = {
        // called by the page with its FullCalendar options, before rendering
        options: function(options) {
            opts = options;
            build();
            var page_events = options.events;
            options.events = function(info, ok, fail) {
                page_events(info, function(list) { ok(list.map(classify)); }, fail);
            };
            options.initialView = 'dayGridMonth';
            options.headerToolbar = false;
            options.fixedWeekCount = false;
            // rows as high as their entries (preview/tests.css gives each day
            // a minimum height): nothing hides behind »+2 weitere«
            options.height = 'auto';
            options.eventOrder = 'pv_order,start,-duration,title';
            options.dayHeaderContent = function(arg) { return WD[arg.date.getDay()]; };
            options.eventDidMount = mount;
            options.datesSet = function(info) {
                calendar = info.view.calendar;
                refresh();
            };
            options.eventsSet = refresh;

            var page_date_click = options.dateClick;
            options.dateClick = function(info) {
                if (!can_add()) {
                    dashboardAlert('Du unterrichtest nicht in der Klasse ' + (active_label || window.klasse) +
                        ' und kannst hier deshalb nichts eintragen.', 'Keine Berechtigung');
                    return;
                }
                page_date_click(info);
                $('#testModal .modal-title').text('Eintrag hinzufügen');
            };
            var page_event_click = options.eventClick;
            options.eventClick = function(info) {
                var p = info.event.extendedProps;
                if (p.type === 'test' && p.is_session_user) {
                    page_event_click(info);
                    $('#testModal .modal-title').text('Eintrag bearbeiten');
                    return;
                }
                show_details(info.event);
            };
        }
    };

    // after the page's own handlers: deleting asks in the dashboard's dialog
    document.addEventListener('DOMContentLoaded', function() {
        if (!opts) return;
        $('#bu_delete_test').off('click').on('click', function() {
            dashboardConfirm('Möchtest du diesen Eintrag löschen?', function() {
                api_call('/api/delete_test', { id: window.stored_test_id }, function(data) {
                    if (data.success) {
                        $('#testModal').modal('hide');
                        calendar.refetchEvents();
                    }
                });
            }, { title: 'Eintrag löschen', confirm: 'Löschen', danger: true });
        });
        var on_change = function() {
            close_menu(false);
            if (calendar) calendar.updateSize();
            refresh();
        };
        if (PHONE.addEventListener) PHONE.addEventListener('change', on_change); else PHONE.addListener(on_change);
    });
})();
