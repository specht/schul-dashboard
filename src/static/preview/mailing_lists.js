// Neues Design (Vorschau): E-Mail-Verteiler (/mailing_lists) as a list with
// actions (doc/Gestaltung.md, 6a; pv_list in preview.js). Loaded by
// mailing_lists.html only for those who see the new design
// (mailing_lists_preview_html in include/directory.rb), so that the page stays
// exactly as it was for everyone else. The server embeds the sections and
// lists (pv_mailing_lists); the recipients of a list are loaded when it is
// opened (/api/mailing_list_recipients), for those who may see them.
//
// The page: title, a quiet line instead of the yellow box, a search over all
// lists, then one section per class or group of lists (folded, except one's
// own classes). A row: the list's name, below it the address (one click
// copies it) and how many it reaches. Opening a row shows the recipients in a
// dialog (a sheet on phones) with a search, each address copyable, and
// "Alle Adressen kopieren" for BCC when the list itself does not work.
(function () {
    var data = window.pv_mailing_lists;
    var script = document.currentScript;
    if (!data || !window.pv_list || !window.pv_copy || !document.body.classList.contains('ui-preview') || !script) return;

    var mount = script.closest('.ml-table');
    var container = script.closest('.container');
    if (!mount || !container) return;

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

    function addresses(n) {
        return n === 1 ? '1 Adresse' : n + ' Adressen';
    }

    function lists_count(n) {
        return n === 1 ? '1 Verteiler' : n + ' Verteiler';
    }

    // for the search: lower case, without accents ("Schüler" finds "schuler")
    function norm(s) {
        return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    // ---------- copying (pv_copy in preview.js) ----------
    // the address as a quiet one-line field: one click copies it, a green
    // check for a moment, announced for screen readers
    function address_button(email) {
        var b = pv_copy.field(email, { what: 'Adresse', cls: 'pv-ml-addr' });
        b.setAttribute('data-email', email);
        return b;
    }

    // ---------- the recipients: a dialog, a sheet on phones ----------
    var cache = {};
    var modal = null;
    var current = null;     // the list shown in the dialog

    function build_modal() {
        modal = el('div', 'modal pv-sheet pv-ml-modal');
        modal.id = 'mailingListModal';
        modal.tabIndex = -1;
        modal.setAttribute('role', 'dialog');
        modal.setAttribute('aria-hidden', 'true');
        modal.setAttribute('aria-labelledby', 'pv_ml_modal_title');
        modal.innerHTML =
            "<div class='modal-dialog modal-dialog-scrollable modal-dialog-centered' role='document'>" +
            "<div class='modal-content'>" +
            "<div class='modal-header'><div class='pv-ml-modal-head'>" +
            "<h5 class='modal-title' id='pv_ml_modal_title'></h5>" +
            "<div class='pv-ml-modal-facts'></div>" +
            "</div></div>" +
            "<div class='modal-body'>" +
            "<div class='pv-ml-search pv-ml-people-search'><input type='search' class='form-control' id='ti_ml_people_search' placeholder='Empfänger suchen' aria-label='Empfänger suchen' autocomplete='off'></div>" +
            "<div class='pv-ml-people'></div>" +
            "<p class='pv-ml-bcc'>Falls der Verteiler einmal nicht funktioniert: »Alle Adressen kopieren« und die Adressen in das BCC-Feld einfügen.</p>" +
            "</div>" +
            "<div class='modal-footer'>" +
            "<button type='button' class='btn btn-secondary' id='bu_ml_copy_all'><span class='pv-ml-copy-label'>Alle Adressen kopieren</span></button>" +
            "<button type='button' class='btn btn-secondary' data-dismiss='modal'>Schließen</button>" +
            "</div></div></div>";
        modal.querySelector('#bu_ml_copy_all').prepend(pv_copy.icons());
        modal.querySelector('.pv-ml-people-search').prepend(icon('search'));
        document.body.appendChild(modal);
        modal.querySelector('#ti_ml_people_search').addEventListener('input', function (e) {
            show_people(e.currentTarget.value);
        });
        modal.querySelector('#bu_ml_copy_all').addEventListener('click', function (e) {
            var button = e.currentTarget;
            if (!current || !cache[current.email]) return;
            var text = cache[current.email].map(function (p) { return p.email; }).join('; ');
            pv_copy.run(button, text, { what: 'Alle Adressen' });
        });
    }

    function person_row(p) {
        var r = el('div', 'pv-ml-person');
        r.appendChild(el('div', 'pv-ml-person-name', p.name || p.email));
        var line = el('div', 'pv-ml-person-addr');
        line.appendChild(address_button(p.email));
        r.appendChild(line);
        return r;
    }

    function show_people(query) {
        var box = modal.querySelector('.pv-ml-people');
        box.textContent = '';
        var people = current ? cache[current.email] : null;
        if (!people) return;
        if (people.length === 0) {
            box.appendChild(el('p', 'pv-lempty', 'Dieser Verteiler erreicht zurzeit niemanden.'));
            return;
        }
        var words = norm(query).split(/\s+/).filter(function (w) { return w.length > 0; });
        var shown = people.filter(function (p) {
            var hay = norm(p.name + ' ' + p.email);
            return words.every(function (w) { return hay.indexOf(w) >= 0; });
        });
        if (shown.length === 0) {
            box.appendChild(el('p', 'pv-lempty', 'Niemand in diesem Verteiler passt zu »' + query.trim() + '«.'));
            return;
        }
        pv_list.blocks(box, shown, person_row, { size: 100, more: 'Weitere anzeigen' });
    }

    function open_list(list) {
        if (!modal) build_modal();
        current = list;
        modal.querySelector('.modal-title').textContent = list.label;
        var facts = modal.querySelector('.pv-ml-modal-facts');
        facts.textContent = '';
        facts.appendChild(address_button(list.email));
        facts.appendChild(el('span', 'pv-ml-count', addresses(list.count)));
        var search = modal.querySelector('#ti_ml_people_search');
        search.value = '';
        // a search only where the list is long
        search.parentNode.hidden = list.count <= 12;
        var copy_all = modal.querySelector('#bu_ml_copy_all');
        copy_all.disabled = true;
        copy_all.classList.remove('pv-copied');
        var box = modal.querySelector('.pv-ml-people');
        box.textContent = '';
        if (cache[list.email]) {
            show_people('');
            copy_all.disabled = cache[list.email].length === 0;
        } else {
            box.appendChild(el('p', 'pv-lempty', 'Wird geladen …'));
            api_call('/api/mailing_list_recipients', { email: list.email }, function (result) {
                if (current !== list) {
                    if (result.success) cache[list.email] = result.recipients;
                    return;
                }
                if (!result.success) {
                    box.textContent = '';
                    box.appendChild(el('p', 'pv-lempty', 'Die Empfänger ließen sich nicht laden. Bitte später noch einmal versuchen.'));
                    return;
                }
                cache[list.email] = result.recipients;
                show_people(search.value);
                copy_all.disabled = result.recipients.length === 0;
            }, { no_please_wait: true });
        }
        $(modal).modal('show');
    }

    // ---------- the list ----------
    function list_row(list) {
        var line = el('div', 'pv-lrow-facts pv-ml-line');
        line.appendChild(address_button(list.email));
        line.appendChild(el('span', 'pv-ml-count', addresses(list.count)));
        var o = { title: list.label, cls: 'pv-ml-row', extra: line };
        if (data.recipients) {
            o.open = function () { open_list(list); };
            o.actions = [{ label: 'Empfänger', visible: true, run: o.open }];
        }
        var row = pv_list.row(o);
        row.setAttribute('data-email', list.email);
        row.pv_ml_search = norm(list.label + ' ' + list.email);
        return row;
    }

    // the head: title, then a quiet line instead of the yellow box
    var h3 = container.querySelector('h3');
    var h2 = el('h2', null, h3 ? h3.textContent : 'E-Mail-Verteiler');
    if (h3) h3.replaceWith(h2); else container.prepend(h2);
    var root = el('div', 'pv-ml-page');
    mount.parentNode.insertBefore(root, mount.nextSibling);
    mount.hidden = true;
    var intro = el('p', 'pv-ml-intro', data.recipients
        ? (data.du ? 'Alle E-Mail-Verteiler, die du verwenden kannst, und wer darüber erreicht wird.'
                   : 'Alle E-Mail-Verteiler, die Sie verwenden können, und wer darüber erreicht wird.')
        : (data.du ? 'Alle E-Mail-Verteiler, die du verwenden kannst, und wie viele Adressen darüber erreicht werden.'
                   : 'Alle E-Mail-Verteiler, die Sie verwenden können, und wie viele Adressen darüber erreicht werden.'));
    root.appendChild(intro);

    var search_box = el('div', 'pv-ml-search');
    search_box.appendChild(icon('search'));
    var search = el('input', 'form-control');
    search.type = 'search';
    search.id = 'ti_ml_search';
    search.placeholder = 'Verteiler suchen';
    search.setAttribute('aria-label', 'Verteiler suchen');
    search.autocomplete = 'off';
    search_box.appendChild(search);
    root.appendChild(search_box);

    var list_root = el('div', 'pv-ml-sections');
    root.appendChild(list_root);
    var empty = el('p', 'pv-lempty pv-ml-none');
    empty.hidden = true;
    root.appendChild(empty);

    var groups = [];
    data.sections.forEach(function (s) {
        var g = pv_list.group(list_root, {
            label: s.label,
            count: lists_count(s.lists.length),
            folded: true,
            open: !!s.open,
            cls: 'pv-ml-section',
        });
        var rows = s.lists.map(function (list) {
            var row = list_row(list);
            g.body.appendChild(row);
            return row;
        });
        groups.push({ g: g, rows: rows, label: norm(s.label), toggle: g.section.querySelector('.pv-lgroup-toggle'), count: g.section.querySelector('.pv-lgroup-count') });
    });
    if (data.sections.length === 0) {
        empty.textContent = 'Zurzeit gibt es keine E-Mail-Verteiler.';
        empty.hidden = false;
        search_box.hidden = true;
    }

    function set_open(x, open) {
        x.g.body.hidden = !open;
        x.toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    }

    // searching: every section with a match open, only the matching rows;
    // afterwards the sections as they were
    var folds = null;
    function filter() {
        var words = norm(search.value).split(/\s+/).filter(function (w) { return w.length > 0; });
        if (words.length === 0) {
            groups.forEach(function (x, i) {
                x.g.section.hidden = false;
                x.rows.forEach(function (r) { r.hidden = false; });
                x.count.textContent = lists_count(x.rows.length);
                if (folds) set_open(x, folds[i]);
            });
            folds = null;
            empty.hidden = data.sections.length > 0;
            return;
        }
        if (!folds) folds = groups.map(function (x) { return !x.g.body.hidden; });
        var any = false;
        groups.forEach(function (x) {
            var n = 0;
            x.rows.forEach(function (r) {
                var hay = x.label + ' ' + r.pv_ml_search;
                var hit = words.every(function (w) { return hay.indexOf(w) >= 0; });
                r.hidden = !hit;
                if (hit) n++;
            });
            x.g.section.hidden = n === 0;
            x.count.textContent = n === x.rows.length ? lists_count(n) : n + ' von ' + x.rows.length;
            if (n > 0) { set_open(x, true); any = true; }
        });
        empty.textContent = 'Kein Verteiler passt zu »' + search.value.trim() + '«.';
        empty.hidden = any;
    }
    search.addEventListener('input', filter);
    search.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && search.value) {
            e.preventDefault();
            search.value = '';
            filter();
        }
    });

    pv_list.page(container);
})();
