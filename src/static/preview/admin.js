// Neues Design (Vorschau): Admin (/admin). People by their full names
// (»Scott Clarke« and the shorthand quietly beside it) instead of separate
// columns for Kürzel, Name and Vorname, and one search above the lists of
// teachers, students and external users: name, shorthand, address, class or
// role. Only the new design loads this file (design_preview_page_script),
// before preview.js turns the tables into list rows on narrow screens; the
// old design keeps its tables.
(function () {
    'use strict';

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }

    function norm(s) {
        return String(s || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    }

    // the table under a heading (inside its scroll box)
    function table_after(h) {
        for (var n = h && h.nextElementSibling; n; n = n.nextElementSibling) {
            if (n.tagName === 'TABLE') return n;
            var t = n.querySelector && n.querySelector('table');
            if (t) return t;
            if (n.tagName === 'H3') return null;
        }
        return null;
    }

    function drop_column(table, index) {
        var head = table.tHead && table.tHead.rows[0];
        if (head && head.cells[index]) head.deleteCell(index);
    }

    // the cells »Nachname«, »Vorname« (and »Kürzel«) become one: the full name
    function merge_names(table, kind) {
        var first_col = kind === 'teachers' ? 2 : 1;
        var removed = kind === 'teachers' ? 2 : 1;
        var head = table.tHead && table.tHead.rows[0];
        if (!head) return [];
        var people = [];
        var klasse = '';
        [].forEach.call(table.tBodies[0].rows, function (tr) {
            if (!tr.classList.contains('user_row')) {
                if (tr.cells.length === 1 && tr.cells[0].tagName === 'TH') {
                    // a class heading (students)
                    klasse = tr.cells[0].textContent.trim();
                    tr.cells[0].colSpan = Math.max(1, tr.cells[0].colSpan - removed);
                    tr.classList.add('pv-adm-klasse');
                } else if (tr.classList.contains('session-row') && tr.cells[0]) {
                    tr.cells[0].colSpan = Math.max(1, tr.cells[0].colSpan - removed);
                }
                return;
            }
            var c = tr.cells;
            var short = kind === 'teachers' ? c[0].textContent.trim() : '';
            var last = c[first_col - 1].textContent.trim();
            var first = c[first_col].textContent.trim();
            var name = (first + ' ' + last).trim();
            var cell = c[0];
            cell.textContent = '';
            cell.appendChild(el('span', 'pv-adm-name', name));
            if (short) cell.appendChild(el('span', 'pv-adm-short', short));
            for (var i = first_col; i > 0; i--) tr.deleteCell(i);
            var mail = tr.querySelector('input[readonly]');
            var rest = [].map.call(tr.cells, function (td) { return td.textContent; }).join(' ');
            var person = { row: tr, klasse: klasse, text: norm([name, last + ', ' + first, short, mail ? mail.value : '', klasse, rest].join(' ')) };
            tr._pv_person = person;
            people.push(person);
        });
        head.cells[0].textContent = 'Name';
        for (var i = first_col; i > 0; i--) drop_column(table, i);
        return people;
    }

    function setup() {
        if (!document.body.classList.contains('ui-preview')) return;
        var sections = [
            { id: 'teachers', kind: 'teachers' },
            { id: 'sus', kind: 'sus' },
            { id: 'external_users', kind: 'external' },
        ];
        var first_heading = document.getElementById('teachers');
        if (!first_heading) return;
        document.body.classList.add('pv-admin-page');
        sections.forEach(function (s) {
            s.heading = document.getElementById(s.id);
            s.table = table_after(s.heading);
            s.people = s.table ? merge_names(s.table, s.kind) : [];
            if (!s.heading) return;
            s.count = el('span', 'pv-adm-count', String(s.people.length));
            s.heading.appendChild(s.count);
            s.none = el('p', 'pv-adm-none', 'Niemand gefunden.');
            s.none.hidden = true;
            if (s.table) {
                var box = s.table.parentElement;
                box.parentNode.insertBefore(s.none, box.nextSibling);
            }
        });

        // the search: above the lists, stays at the top while scrolling
        var bar = el('div', 'pv-adm-search');
        var label = el('label', 'sr-only', 'Personen suchen');
        label.setAttribute('for', 'ti_admin_search');
        var input = el('input', 'form-control');
        input.type = 'search';
        input.id = 'ti_admin_search';
        input.placeholder = 'Name, Kürzel oder Klasse';
        input.autocomplete = 'off';
        var icon = el('i', 'ti ti-search');
        icon.setAttribute('aria-hidden', 'true');
        var status = el('span', 'pv-adm-status');
        status.setAttribute('aria-live', 'polite');
        bar.appendChild(label);
        bar.appendChild(icon);
        bar.appendChild(input);
        bar.appendChild(status);
        first_heading.parentNode.insertBefore(bar, first_heading);

        var filter = function () {
            var words = norm(input.value).split(/\s+/).filter(function (w) { return w; });
            var total = 0;
            sections.forEach(function (s) {
                if (!s.table) return;
                var hits = 0;
                var seen = {};
                s.people.forEach(function (p) {
                    var match = words.every(function (w) { return p.text.indexOf(w) >= 0; });
                    p.row.hidden = !match;
                    if (match) { hits++; seen[p.klasse] = true; }
                    // a person's sessions go with the person
                    for (var n = p.row.nextElementSibling; n && n.classList.contains('session-row'); n = n.nextElementSibling)
                        n.hidden = !match;
                });
                [].forEach.call(s.table.querySelectorAll('tr.pv-adm-klasse'), function (tr) {
                    tr.hidden = words.length > 0 && !seen[tr.cells[0].textContent.trim()];
                });
                s.count.textContent = words.length ? hits + ' von ' + s.people.length : String(s.people.length);
                s.none.hidden = !(words.length && hits === 0);
                s.table.parentElement.hidden = words.length > 0 && hits === 0;
                total += hits;
            });
            status.textContent = words.length ? (total === 1 ? '1 Person' : total + ' Personen') : '';
        };
        input.addEventListener('input', filter);
        input.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && input.value) { input.value = ''; filter(); }
        });
    }

    // at once: this script stands after the lists, and preview.js labels the
    // table cells on DOMContentLoaded – by then the columns must be merged
    setup();
})();
