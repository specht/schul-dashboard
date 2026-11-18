// Neues Design (Vorschau): the library pages (bibliothek.html, bib_*.html).
// Loaded by both library templates only for those who see the new design
// (bib_preview_head in include/bib_preview.rb, after the bundled code.js),
// so that every page stays exactly as it was for everyone else.
//
// The pages keep their markup and their scripts – every function, role
// check and scanner flow stays theirs. This file only changes how they are
// drawn:
// - the library's own navigation as a row of quiet tabs on the panel (the
//   page's extra links, e.g. »Metadaten bearbeiten«, as a second row),
// - books as list rows with a small cover (create_book_div), tables calm
//   and, where the list is narrow, as list rows (SortableTable), names as
//   text, shelves and states as single chips,
// - the scanner area (BarcodeWidget) calm, everyone addressed with "du",
// - per page: a title, one main action, hints as quiet lines, and the
//   order steps of a book in a dialog (a sheet on phones).
// Pages call bib_api_call; pv_bib.tap(url, fn) lets a page's part below
// see the answer after the page itself has drawn it.
(function () {
    'use strict';
    if (!document.body.classList.contains('ui-preview')) return;
    var B = window.PV_BIB || {};
    var PAGE = B.page || '';
    var PHONE = window.matchMedia('(max-width: 767px)');
    if (B.device) document.body.classList.add('pv-bib-device');

    // ---------- small helpers ----------
    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }

    function icon(name, cls) {
        var i = el('i', 'ti ti-' + name + (cls ? ' ' + cls : ''));
        i.setAttribute('aria-hidden', 'true');
        return i;
    }

    function date(ts) {
        return ts ? moment.unix(ts).format('DD.MM.YYYY') : '';
    }

    function plural(n, one, many) {
        return n + ' ' + (n === 1 ? one : many);
    }

    function q(sel, root) { return (root || document).querySelector(sel); }
    function qa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    // the page's panel (the first .container after the library's navigation)
    // (found once: the page's extra links move into it later)
    var the_panel;
    function panel() {
        if (the_panel === undefined) {
            the_panel = qa('#main_container > .container').filter(function (c) {
                return c.id !== 'device_navbar' && c.id !== 'subsubmenu' && !c.classList.contains('sandbox-hint') && !c.querySelector(':scope > section > ul.submenu');
            })[0] || null;
        }
        return the_panel;
    }

    // ---------- answers of the library for the page's parts (pv_bib.tap) ----------
    var taps = {};
    var original_call = window.bib_api_call;
    if (typeof original_call === 'function') {
        window.bib_api_call = function (url, data, callback, options) {
            return original_call(url, data, function (res) {
                if (typeof callback === 'function') callback(res);
                (taps[url] || []).forEach(function (fn) {
                    try { fn(res, data); } catch (err) { console.warn('pv_bib', url, err); }
                });
            }, options);
        };
    }
    function tap(url, fn) { (taps[url] = taps[url] || []).push(fn); }

    // ---------- the page head: title, quiet facts, one main action ----------
    // returns {head, facts, actions}; the head goes at the top of the panel
    // (below the library's navigation)
    function head(title, o) {
        o = o || {};
        var p = o.container || panel();
        if (!p) return null;
        var h = el('div', 'pv-bib-head');
        var text = el('div', 'pv-bib-head-text');
        var h2 = el('h2', 'pv-bib-title', title);
        text.appendChild(h2);
        var facts = el('p', 'pv-bib-facts');
        facts.hidden = true;
        text.appendChild(facts);
        h.appendChild(text);
        var actions = el('div', 'pv-bib-head-actions');
        h.appendChild(actions);
        var nav = q('.pv-bib-nav', p);
        if (nav) nav.parentNode.insertBefore(h, nav.nextSibling);
        else p.insertBefore(h, p.firstChild);
        // errors of api_call need a place on the page
        return {
            head: h, title: h2, actions: actions,
            facts: function (s) { facts.textContent = s || ''; facts.hidden = !s; }
        };
    }

    // a quiet hint line with an icon (instead of the yellow boxes)
    function hint(text, o) {
        o = o || {};
        var p = el('p', 'pv-bib-hint' + (o.cls ? ' ' + o.cls : ''));
        p.appendChild(icon(o.icon || 'info-circle'));
        var span = el('span', null, text);
        p.appendChild(span);
        return p;
    }

    // ---------- the library's navigation ----------
    // the template's submenu (links shown per role by the server) as one row
    // of quiet tabs at the top of the panel: one's own (Meine Bücher,
    // Katalog, Bestellungen), then the library's management
    var NAV_LABELS = { '/bib_all_orders': 'Alle Bestellungen', '/bib_scan': 'Scannen' };
    function build_nav() {
        var menu = qa('ul.submenu').filter(function (u) { return !u.closest('#subsubmenu'); })[0];
        var p = panel();
        if (!menu || !p) return;
        var section = menu.closest('section');
        var old = menu.closest('.container');
        if (old) old.classList.add('pv-bib-oldnav');
        if (!section || section.style.display === 'none') return;
        var groups = [[], []];
        var g = 0;
        qa(':scope > li', menu).forEach(function (li) {
            if (li.style.display === 'none') return;
            var a = q('a[href]', li);
            if (!a) { if (groups[0].length) g = 1; return; }
            groups[g].push(a);
        });
        // only staff links, no own ones: one group
        if (!groups[0].length) { groups[0] = groups[1]; groups[1] = []; }
        if (groups[0].length + groups[1].length < 2) return;
        var nav = el('nav', 'pv-bib-nav');
        nav.setAttribute('aria-label', 'Bibliothek');
        var here = location.pathname.replace(/\/$/, '');
        // pages without a tab of their own belong to one
        var BELONGS = {
            bib_confirm: ['/bibliothek'], bib_book: ['/bib_browse', '/bib_books'], bib_exemplar: ['/bib_browse', '/bib_books'],
            bib_book_edit: ['/bib_books'], bib_add_exemplare: ['/bib_books'], bib_print_label: ['/bib_books'],
            bib_user: ['/bib_users'], bib_process_order: ['/bib_all_orders'], bib_shelves: ['/bib_overview'],
        };
        var all = groups[0].concat(groups[1]).map(function (a) { return a.getAttribute('href'); });
        var target = all.filter(function (href) { return here === href || here.indexOf(href + '/') === 0; })[0] ||
            (BELONGS[PAGE] || []).filter(function (href) { return all.indexOf(href) >= 0; })[0];
        groups.forEach(function (links, i) {
            if (!links.length) return;
            var ul = el('ul', 'pv-bib-tabs' + (i === 1 ? ' pv-bib-tabs-staff' : ''));
            if (i === 1 && groups[0].length) ul.setAttribute('aria-label', 'Verwaltung');
            links.forEach(function (a) {
                var href = a.getAttribute('href');
                var li = el('li');
                var link = el('a', 'pv-bib-tab', NAV_LABELS[href] || a.textContent.replace(/\s+/g, ' ').trim());
                link.href = href;
                if (href === target) link.setAttribute('aria-current', href === here ? 'page' : 'true');
                li.appendChild(link);
                ul.appendChild(li);
            });
            nav.appendChild(ul);
        });
        p.insertBefore(nav, p.firstChild);
        // phones: the current tab in view (the row scrolls sideways)
        var current = q('[aria-current]', nav);
        if (current && nav.scrollWidth > nav.clientWidth) {
            nav.scrollLeft = Math.max(0, current.getBoundingClientRect().left - nav.getBoundingClientRect().left - 24);
        }
    }

    // the page's extra links (book: Buch, Metadaten bearbeiten …; overview:
    // its tabs), filled by the page on load: a second, quieter row
    function move_subnav() {
        var sub = q('#subsubmenu');
        var p = panel();
        if (!sub || !p) return;
        sub.classList.add('pv-bib-subnav');
        var nav = q('.pv-bib-nav', p);
        p.insertBefore(sub, nav ? nav.nextSibling : p.firstChild);
    }

    // the sidebar: the library is »Bibliothek«, on every one of its pages
    function mark_sidebar() {
        if (PAGE === 'bibliothek') return;
        qa('.navbar a[href="/bibliothek"]').forEach(function (a) { a.classList.add('pv-active'); });
    }

    // ---------- books: list rows with a small cover ----------
    var original_book_div = window.create_book_div;
    function book_cover(book, preview) {
        var c = el('div', 'pv-book-cover');
        if (!preview && book.has_cover) {
            var img = el('img');
            img.alt = '';
            img.loading = 'lazy';
            img.src = BIB_HOST + '/gen/covers/' + book.stem + '-400.jpg';
            img.addEventListener('error', function () { img.remove(); c.appendChild(icon('book')); });
            c.appendChild(img);
        } else {
            c.appendChild(icon('book'));
        }
        return c;
    }

    // same arguments as create_book_div in code.js; returns a jQuery element
    function book_row(book, shelf, options) {
        options = options || {};
        var row = el('div', 'pv-book' + (options.compact ? ' pv-book-compact' : '') + (options.clickable ? ' pv-book-link' : ''));
        row.setAttribute('data-stem', book.stem);
        row.appendChild(book_cover(book, options.preview));
        var text = el('div', 'pv-book-text');
        row.appendChild(text);
        if (options.preview) {
            // bib.html: drawn when it scrolls into view
            text.appendChild(el('div', 'pv-book-title', book.title || ''));
            return $(row);
        }
        var title = el(options.clickable ? 'a' : 'div', 'pv-book-title');
        if (options.clickable) {
            title.href = '/bib_book/' + book.stem;
            title.addEventListener('click', function (e) {
                if (e.ctrlKey || e.metaKey || e.shiftKey) return;
                e.preventDefault();
            });
        }
        title.appendChild(document.createTextNode(book.title || ''));
        if (book.subtitle && !options.compact) title.appendChild(el('span', 'pv-book-sub', ' – ' + book.subtitle));
        text.appendChild(title);
        var facts = [];
        if (book.author) facts.push(book.author);
        if (!options.compact) {
            var pub = [book.verlag, book.published].filter(Boolean).join(' ');
            if (pub) facts.push(pub);
        }
        if (facts.length) text.appendChild(el('div', 'pv-book-facts', facts.join(', ')));
        var line = [];
        var exemplar = options.exemplar;
        if (exemplar && exemplar.bnr) line.push('Signatur ' + book.stem + '-' + exemplar.bnr);
        else line.push('Signatur ' + book.stem);
        if (options.r && options.r.ts_checked_out) line.push('ausgeliehen am ' + date(options.r.ts_checked_out));
        if (!options.compact && book.isbn) line.push('ISBN ' + book.isbn);
        text.appendChild(el('div', 'pv-book-facts pv-book-sig', line.join(', ')));
        var states = el('div', 'pv-book-states');
        if (options.r && options.r.ts_summoned) {
            states.appendChild(el('span', 'pv-bib-chip pv-bib-chip-warn', 'Bitte zurückbringen'));
            row.classList.add('pv-book-summoned');
        }
        if (options.r && !options.r.ts_confirmed && options.exemplar && !options.compact) {
            states.appendChild(el('span', 'pv-bib-chip', 'Noch nicht bestätigt'));
        }
        if (exemplar && exemplar.ts_discarded) states.appendChild(el('span', 'pv-bib-chip pv-bib-chip-danger', 'ausgemustert am ' + date(exemplar.ts_discarded)));
        if (shelf) states.appendChild(el('span', 'pv-bib-chip pv-bib-shelf', shelf.location));
        if (states.childNodes.length) text.appendChild(states);
        if (options.clickable) {
            row.appendChild(icon('chevron-right', 'pv-book-chev'));
            row.addEventListener('click', function (e) {
                if (e.target.closest && e.target.closest('a') && (e.ctrlKey || e.metaKey || e.shiftKey)) return;
                if (typeof options.callback === 'function') options.callback(book);
            });
        }
        return $(row);
    }
    if (typeof original_book_div === 'function') window.create_book_div = book_row;

    // a shelf as a quiet chip (code.js: create_location_span returns HTML)
    window.create_location_span = function (location) {
        var s = el('span', 'pv-bib-chip pv-bib-shelf', location);
        return s.outerHTML;
    };

    // ---------- names in tables: as text, teachers marked in words ----------
    function name_cells(email, display) {
        var info = db_user_info[email];
        if (!info) {
            var td = el('td', 'pv-bib-email', email);
            td.colSpan = display ? 1 : 2;
            return $(td);
        }
        if (display) {
            var one = el('td', null, info.display_name || email);
            if (info.teacher) $(one).data('sort_value', info.last_name);
            return $(one);
        }
        var last = el('td', null, info.teacher && info.titel ? info.titel + ' ' + info.last_name : (info.last_name || ''));
        $(last).data('sort_value', info.last_name || '');
        var first = el('td', 'pv-st-name2', info.first_name || '');
        if (info.teacher) first.appendChild(el('span', 'pv-bib-tag', 'Lehrkraft'));
        return $([last, first]);
    }
    if (typeof window.create_user_td_span === 'function') {
        window.create_user_td_span = function (email) { return name_cells(email, false); };
        window.create_user_td_span_teacher = function (email) { return name_cells(email, true); };
    }

    // confirmed or not, hidden until …: a date, or a quiet state
    if (typeof window.create_confirmed_td === 'function') {
        window.create_confirmed_td = function (r, server_ts, add_link_button) {
            var td = el('td');
            if (r.ts_confirmed) {
                td.textContent = date(r.ts_confirmed);
                $(td).data('sort_value', r.ts_confirmed);
                return $(td);
            }
            var state = el('span', 'pv-bib-state');
            if (r.force_hide) {
                state.appendChild(icon('clock'));
                state.appendChild(document.createTextNode('versteckt, bis die Bestellung komplett ist'));
            } else if (r.ts_hide_before && server_ts < r.ts_hide_before) {
                state.appendChild(icon('clock'));
                state.appendChild(document.createTextNode('versteckt bis ' + date(r.ts_hide_before)));
            } else {
                state.appendChild(icon('alert-circle'));
                state.appendChild(document.createTextNode('noch nicht bestätigt'));
            }
            td.appendChild(state);
            if (add_link_button && !r.force_hide && !(r.ts_hide_before && server_ts < r.ts_hide_before)) {
                var a = el('a', 'pv-bib-link', 'Jetzt bestätigen');
                a.href = '/bib_confirm';
                td.appendChild(a);
            }
            $(td).data('sort_value', NaN);
            return $(td);
        };
    }

    // ---------- tables: calm, list rows where the list is narrow ----------
    // every cell gets its column's name (data-label): where the table is
    // narrow (a container query in bib.css), each row becomes a list row –
    // the first cells as its title, the others as labelled facts
    // (classes declared in code.js are no properties of window)
    if (typeof SortableTable === 'function') {
        var Base = SortableTable;
        var labelled = function (table, tr) {
            var names = table.headers.map(function (th) { return $(th).text().trim(); });
            var col = 0;
            $(tr).children('td').each(function (i, td) {
                var span = parseInt(td.getAttribute('colspan') || '1', 10);
                if (!td.hasAttribute('data-label')) td.setAttribute('data-label', names[col] || '');
                if (i === 0) td.classList.add('pv-st-first');
                // nothing to say ("–"): left out where the row is a list row
                var t = td.textContent.trim();
                if (i > 0 && (t === '–' || t === '-' || (t === '' && !td.querySelector('*')))) td.classList.add('pv-st-none');
                col += span;
            });
            if (table.options.clickable_rows) tr.classList.add('pv-st-link');
        };
        var Pv = class extends Base {
            constructor(options) {
                super(options);
                var self = this;
                var table = this.tbody.closest('table');
                table.addClass('pv-st');
                table.closest('.table-responsive').addClass('pv-st-wrap');
                this.tbody.children('tr').each(function (i, tr) { labelled(self, tr); });
                this.headers.forEach(function (th) {
                    var h = $(th);
                    if (!options.sortable && options.sortable !== undefined) return;
                    h.attr('tabindex', '0');
                    h.on('keydown', function (e) {
                        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); $(e.currentTarget).trigger('click'); }
                    });
                });
            }
            add_row(row, highlight, prepend, row_classes) {
                super.add_row(row, highlight, prepend, row_classes);
                if (row === null || !this.tbody) return;
                var tr = prepend ? this.tbody.children('tr').first() : this.tbody.children('tr').last();
                if (tr.length && this.headers) labelled(this, tr[0]);
            }
        };
        // the first rows are added in the base constructor, before the
        // headers are known to the subclass: labelled afterwards above
        SortableTable = Pv;
    }

    // ---------- the scanner area (BarcodeWidget) ----------
    // the new design says "du" to everyone; the widget picks its wording by
    // this variable only
    window.teacher_logged_in = false;

    // ---------- confirmation dialogs with du ----------
    // (the pages' own showTemplateModal texts are written with "Sie")
    function confirm_danger(text, title, label, run) {
        dashboardConfirm(text, run, { title: title, confirm: label, danger: true });
    }

    // ---------- a dialog of our own (a sheet on phones) ----------
    function modal(id, title) {
        var m = el('div', 'modal pv-sheet pv-bib-modal');
        m.id = id;
        m.tabIndex = -1;
        m.setAttribute('role', 'dialog');
        m.setAttribute('aria-hidden', 'true');
        m.setAttribute('aria-labelledby', id + '_title');
        m.innerHTML =
            "<div class='modal-dialog modal-dialog-scrollable modal-dialog-centered modal-lg' role='document'>" +
            "<div class='modal-content'>" +
            "<div class='modal-header'><h5 class='modal-title'></h5></div>" +
            "<div class='modal-body'></div>" +
            "<div class='modal-footer'></div>" +
            "</div></div>";
        q('.modal-title', m).id = id + '_title';
        q('.modal-title', m).textContent = title;
        document.body.appendChild(m);
        return { root: m, body: q('.modal-body', m), foot: q('.modal-footer', m) };
    }

    // ================================================================
    // the pages
    // ================================================================
    var pages = {};

    // ---------- Meine Bücher (students, teachers) ----------
    pages['bibliothek'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-list');
        var h = head(B.teacher ? 'Meine Bücher' : 'Meine Bücher');
        var unconfirmed = q('#unconfirmed_div');
        if (unconfirmed) unconfirmed.classList.add('pv-bib-gone');
        var go = el('a', 'btn btn-success pv-bib-main', 'Bücher bestätigen');
        go.href = '/bib_confirm';
        go.id = 'bu_pv_confirm';
        go.hidden = true;
        h.actions.appendChild(go);
        var note = hint('Bestätige deine ausgeliehenen Bücher, indem du den Barcode in jedem Buch scannst. Du findest ihn ganz vorn im Buch.', { icon: 'barcode', cls: 'pv-bib-confirm-hint' });
        note.hidden = true;
        h.head.parentNode.insertBefore(note, h.head.nextSibling);
        var empty = q('#no_books_hint');
        if (empty) {
            empty.className = 'pv-bib-empty';
            empty.textContent = 'Du hast gerade keine Bücher ausgeliehen. Bücher aus der Bibliothek erscheinen hier, sobald sie auf deinen Namen ausgeliehen sind.';
        }
        tap('/jwt/get_checked_out_books_for_user', function (data) {
            if (!data.success) return;
            var n = data.exemplare.length;
            var summoned = data.exemplare.filter(function (x) { return x.r && x.r.ts_summoned; }).length;
            var facts = [n === 0 ? 'Keine Bücher ausgeliehen' : plural(n, 'Buch', 'Bücher') + ' ausgeliehen'];
            if (data.unconfirmed_count > 0) facts.push(data.unconfirmed_count + ' noch nicht bestätigt');
            if (summoned > 0) facts.push(plural(summoned, 'Buch soll', 'Bücher sollen') + ' zurück in die Bibliothek');
            h.facts(facts.join(', '));
            go.hidden = !(data.unconfirmed_count > 0);
            note.hidden = !(data.unconfirmed_count > 0);
        });
    };

    // ---------- Bücher bestätigen (scanning one's own books) ----------
    pages['bib_confirm'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-list', 'pv-bib-confirm');
        var h = head('Bücher bestätigen');
        h.facts('Scanne den Barcode ganz vorn in jedem Buch, das du bekommen hast.');
        var row = q('.row', p);
        if (row) row.classList.add('pv-bib-scanrow');
        // the intro and the yellow box: one quiet line below the list
        var intro = row ? q('.col-lg-6 > p', row) : null;
        if (intro) intro.classList.add('pv-bib-gone');
        var box = row ? q('.alert-warning', row) : null;
        if (box) {
            var text = box.textContent.replace(/^\s*Hinweis:\s*/, '').replace(/\s+/g, ' ').trim();
            text = text.replace('Falls hier Bücher angezeigt werden, die Sie bereits zurückgegeben haben oder niemals bekommen haben, klären Sie diese Fälle bitte', 'Falls hier Bücher stehen, die du schon zurückgegeben oder nie bekommen hast, kläre das bitte')
                .replace('Falls hier Bücher angezeigt werden, die du bereits zurückgegeben hast oder niemals bekommen hast, kläre diese Fälle bitte', 'Falls hier Bücher stehen, die du schon zurückgegeben oder nie bekommen hast, kläre das bitte');
            var note = hint(text, { icon: 'help-circle', cls: 'pv-bib-foot-hint' });
            p.appendChild(note);
            box.classList.add('pv-bib-gone');
        }
        var left = q('#books_left_div');
        if (left && left.parentNode) left.parentNode.classList.add('pv-bib-progress');
        var list = q('#book_list');
        if (list) {
            var heading = el('h3', 'pv-bib-section', 'Noch nicht bestätigt');
            heading.hidden = true;
            list.parentNode.insertBefore(heading, list);
            tap('/jwt/get_checked_out_books_for_user_unconfirmed', function (data) {
                heading.hidden = !(data.success && data.exemplare.length > 0);
            });
            tap('/jwt/confirm_checked_out_book', function () {
                var shown = qa('.pv-book', list).filter(function (x) { return x.style.display !== 'none'; }).length;
                heading.hidden = shown === 0;
            });
        }
    };

    // ---------- Katalog (teachers, staff) ----------
    pages['bib_browse'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-list');
        var h = head('Katalog');
        h.facts('Suche nach Titel, Autor oder Verlag, oder wähle ein Fach.');
        var group = q('.input-group', p);
        if (group) {
            group.classList.add('pv-bib-search');
            var input = q('#ti_search', group);
            if (input) {
                input.setAttribute('placeholder', 'Titel, Autor oder Verlag');
                input.setAttribute('aria-label', 'Im Katalog suchen');
                input.setAttribute('type', 'search');
            }
        }
        var labels = q('#labels_here');
        if (labels) {
            labels.classList.add('pv-bib-filters');
            // the words before the buttons
            Array.prototype.slice.call(labels.childNodes).forEach(function (n) { if (n.nodeType === 3) n.remove(); });
            labels.setAttribute('role', 'group');
            labels.setAttribute('aria-label', 'Fächer');
            labels.insertBefore(el('span', 'pv-bib-filters-label', 'Fächer'), labels.firstChild);
        }
        var count = el('p', 'pv-bib-count');
        count.hidden = true;
        var list = q('#book_list');
        if (list) list.parentNode.insertBefore(count, list);
        tap('/jwt/search', function (data, req) {
            if (!data.success) return;
            var n = data.books.length;
            count.hidden = false;
            count.textContent = n === 0 ? '' : plural(n, 'Buch', 'Bücher');
            if (n === 0 && list) {
                list.textContent = '';
                var words = [req.query].concat((req.labels || '').split(';')).filter(Boolean);
                list.appendChild(el('p', 'pv-bib-empty', 'Kein Buch passt zu ' + words.map(function (w) { return '»' + w + '«'; }).join(' und ') + '. Versuche es mit weniger oder anderen Wörtern.'));
            }
        });
        tap('/jwt/get_labels', function () {
            qa('.bu-label', labels || p).forEach(function (b) {
                b.setAttribute('aria-pressed', $(b).data('flag') ? 'true' : 'false');
                b.addEventListener('click', function (e) {
                    var button = e.currentTarget;
                    setTimeout(function () { button.setAttribute('aria-pressed', $(button).data('flag') ? 'true' : 'false'); }, 0);
                });
            });
        });
    };

    // ---------- a book: details, one's copies, ordering, the copies (staff) ----------
    pages['bib_book'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-read', 'pv-bib-bookpage');
        var top = q('#book_here');
        if (top) top.classList.add('pv-bib-bookhead');
        var labels = q('#labels_here');
        var details = q('#book_details');
        // the labels (subjects) and shelves below the facts
        if (labels && details) details.parentNode.insertBefore(labels, details.nextSibling);
        var mine = q('#checked_out_user');
        var teacher = q('.bib_teacher_only');
        var manage = q('.bib_management_only');

        // ordering: a short form in a dialog (a sheet on phones); the page's
        // own steps (Klasse/Kurs or privat, the course, Lehrerexemplar,
        // Bestellung aufgeben) move into it as they are
        var order_button = q('#bu_order_overview');
        var order_div = q('#order_div');
        if (teacher && order_button && order_div) {
            var intro = qa(':scope > p', teacher)[0];
            var sec = el('section', 'pv-bib-sec pv-bib-order');
            sec.appendChild(el('h3', 'pv-bib-section', 'Bestellen'));
            sec.appendChild(el('p', 'pv-bib-text', 'Wenn du dieses Buch im Unterricht verwenden möchtest, kannst du es hier bestellen.'));
            var notice = q('#orders_placed_notice');
            if (notice) { notice.className = 'pv-bib-hint pv-bib-hint-acc'; notice.insertBefore(icon('shopping-cart'), notice.firstChild); sec.appendChild(notice); }
            var bar = el('div', 'pv-bib-actions');
            order_button.textContent = 'Buch bestellen';
            bar.appendChild(order_button);
            sec.appendChild(bar);
            if (intro) intro.classList.add('pv-bib-gone');
            qa(':scope > hr', teacher).forEach(function (x) { x.hidden = true; });
            teacher.insertBefore(sec, teacher.firstChild);
            var dlg = modal('bibOrderModal', 'Buch bestellen');
            var choose = el('div', 'pv-bib-choice');
            choose.setAttribute('role', 'group');
            choose.setAttribute('aria-label', 'Wofür?');
            var kurs = q('#bu_order_kurs');
            var privat = q('#bu_order_private');
            if (kurs) { kurs.textContent = 'Für eine Klasse oder einen Kurs'; choose.appendChild(kurs); }
            if (privat) { privat.textContent = 'Für mich'; choose.appendChild(privat); }
            order_div.insertBefore(choose, order_div.firstChild);
            qa(':scope > hr', order_div).forEach(function (x) { x.hidden = true; });
            var plus = q('#bu_plus_teacher');
            var plus_sync = function () {
                if (!plus) return;
                var on = plus.classList.contains('btn-success');
                plus.setAttribute('aria-pressed', on ? 'true' : 'false');
                plus.textContent = '';
                plus.appendChild(icon(on ? 'square-check' : 'square'));
                plus.appendChild(document.createTextNode('Ich brauche ein Lehrerexemplar'));
            };
            if (plus) {
                plus_sync();
                new MutationObserver(function () {
                    if (plus.lastChild && plus.lastChild.nodeType === 3 && plus.lastChild.textContent === 'Ich brauche ein Lehrerexemplar' && plus.querySelector('.ti')) return;
                    plus_sync();
                }).observe(plus, { attributes: true, attributeFilter: ['class'], childList: true });
            }
            // the hint about missing numbers: quieter, with du
            var warn = q('#order_kurs_div_confirm .alert-warning');
            if (warn) {
                warn.className = 'pv-bib-hint pv-bib-hint-small';
                warn.textContent = 'Stimmt die Gesamtzahl nicht (z. B. weil Schülerinnen und Schüler der 7. Klassen noch nicht im Lehrmittelverein sind oder für Oberstufenkurse noch keine Teilnehmerlisten im Dashboard stehen), kannst du trotzdem schon bestellen. Wir bearbeiten die Bestellung, sobald alles vorliegt, und die Zahlen stimmen dann von selbst.';
            }
            // the chosen course stays marked
            order_div.addEventListener('click', function (e) {
                var tr = e.target.closest && e.target.closest('#kurs_list_div tbody tr');
                if (!tr) return;
                qa('#kurs_list_div tbody tr').forEach(function (x) { x.classList.toggle('pv-st-selected', x === tr); });
            });
            dlg.body.appendChild(order_div);
            order_div.style.display = 'block';
            var close = el('button', 'btn btn-secondary', 'Schließen');
            close.type = 'button';
            close.setAttribute('data-dismiss', 'modal');
            dlg.foot.appendChild(close);
            qa('#bu_place_order_kurs, #bu_place_order_private').forEach(function (b) {
                b.textContent = 'Bestellung aufgeben';
            });
            // the page disables its button after the first click (its steps
            // stay open below it); the dialog opens again and again
            order_button.addEventListener('click', function (e) {
                var b = e.currentTarget;
                setTimeout(function () { b.disabled = false; }, 0);
                $(dlg.root).modal('show');
            });
            qa('#bu_place_order_kurs_success, #bu_place_order_private_success').forEach(function (s) {
                s.className = 'pv-bib-hint pv-bib-hint-ok';
                s.style.display = 'none';
                s.innerHTML = '';
                s.appendChild(icon('check'));
                var t = el('span', null, 'Deine Bestellung ist aufgenommen. Wie weit sie ist, siehst du unter ');
                var a = el('a', null, 'Bestellungen');
                a.href = '/bib_orders';
                t.appendChild(a);
                t.appendChild(document.createTextNode('.'));
                s.appendChild(t);
            });
        }

        // staff: ordering on behalf of a teacher, then the copies
        if (manage) {
            manage.classList.add('pv-bib-manage');
            var mh = q(':scope > h3', manage);
            if (mh) mh.textContent = 'Verwaltung';
            var imp_button = q('#bu_order_impersonate_overview');
            var imp_div = q('#order_impersonate_div');
            if (imp_button && imp_div) {
                var ip = qa(':scope > p', manage)[0];
                if (ip) ip.textContent = 'Du kannst dieses Buch im Namen einer Lehrkraft für einen Kurs bestellen.';
                var ibar = el('div', 'pv-bib-actions');
                imp_button.textContent = 'Für einen Kurs bestellen';
                imp_button.classList.remove('btn-success');
                imp_button.classList.add('btn-secondary');
                ibar.appendChild(imp_button);
                if (ip) ip.parentNode.insertBefore(ibar, ip.nextSibling);
                var idlg = modal('bibOrderImpersonateModal', 'Für einen Kurs bestellen');
                var search = q('#ti_kurs_impersonate_list_search');
                if (search) {
                    search.setAttribute('placeholder', 'Fach, Klasse oder Lehrkraft');
                    search.setAttribute('aria-label', 'Kurs suchen');
                    search.setAttribute('type', 'search');
                }
                var iplus = q('#bu_plus_teacher_impersonate');
                var iplus_sync = function () {
                    if (!iplus) return;
                    var on = iplus.classList.contains('btn-success');
                    iplus.setAttribute('aria-pressed', on ? 'true' : 'false');
                    iplus.textContent = '';
                    iplus.appendChild(icon(on ? 'square-check' : 'square'));
                    iplus.appendChild(document.createTextNode('Lehrerexemplar (+1)'));
                };
                if (iplus) {
                    iplus_sync();
                    new MutationObserver(function () {
                        if (iplus.lastChild && iplus.lastChild.nodeType === 3 && iplus.lastChild.textContent === 'Lehrerexemplar (+1)' && iplus.querySelector('.ti')) return;
                        iplus_sync();
                    }).observe(iplus, { attributes: true, attributeFilter: ['class'], childList: true });
                }
                var place = q('#bu_place_order_kurs_impersonate');
                if (place) place.textContent = 'Bestellung aufgeben';
                var ok = q('#bu_place_order_kurs_impersonate_success');
                if (ok) { ok.className = 'pv-bib-hint pv-bib-hint-ok'; ok.style.display = 'none'; ok.textContent = ''; ok.appendChild(icon('check')); ok.appendChild(el('span', null, 'Die Bestellung ist aufgenommen.')); }
                imp_div.addEventListener('click', function (e) {
                    var tr = e.target.closest && e.target.closest('#kurs_impersonate_list_div tbody tr');
                    if (!tr) return;
                    qa('#kurs_impersonate_list_div tbody tr').forEach(function (x) { x.classList.toggle('pv-st-selected', x === tr); });
                });
                idlg.body.appendChild(imp_div);
                imp_div.style.display = 'block';
                var iclose = el('button', 'btn btn-secondary', 'Schließen');
                iclose.type = 'button';
                iclose.setAttribute('data-dismiss', 'modal');
                idlg.foot.appendChild(iclose);
                imp_button.addEventListener('click', function (e) {
                    var b = e.currentTarget;
                    setTimeout(function () { b.disabled = false; }, 0);
                    $(idlg.root).modal('show');
                });
                $(idlg.root).on('shown.bs.modal', function () { if (search) search.focus(); });
            }
            qa(':scope > hr', manage).forEach(function (x) { x.hidden = true; });
        }

        tap('/jwt/get_book', function (data) {
            if (!data.success) return;
            var book = data.book;
            // the facts: one quiet line instead of four headings
            if (details) {
                var parts = [];
                var pub = [book.verlag, book.published].filter(Boolean).join(' ');
                if (pub) parts.push(pub);
                if (book.page_count) parts.push(book.page_count + ' Seiten');
                if (book.isbn) parts.push('ISBN ' + book.isbn);
                if (book.waehrung && book.preis) parts.push(currency_string(book.preis, book.waehrung));
                parts.push('Signatur ' + book.stem);
                var discarded = q('.text-danger', details);
                details.textContent = '';
                if (discarded) {
                    var d = hint(discarded.textContent, { icon: 'trash', cls: 'pv-bib-hint-danger' });
                    details.appendChild(d);
                }
                details.appendChild(el('p', 'pv-bib-facts', parts.join(', ')));
            }
            if (labels) {
                labels.classList.add('pv-bib-labels');
                qa('span', labels).forEach(function (s) {
                    if (!s.classList.contains('pv-bib-chip')) s.className = 'pv-bib-chip';
                });
            }
            if (!book.has_cover) {
                var c = q('#book_cover_container');
                if (c) {
                    c.style.display = '';
                    c.classList.add('pv-bib-nocover');
                    c.textContent = '';
                    c.appendChild(icon('book'));
                }
            }
            // one's own copies
            if (mine && data.checked_out_user.length > 0) {
                var n = data.checked_out_user.length;
                mine.classList.add('pv-bib-sec');
                var first = mine.firstElementChild;
                if (first) {
                    var tbl = q('table', first);
                    var hh = el('h3', 'pv-bib-section', n === 1 ? 'Dein Exemplar' : 'Deine Exemplare');
                    mine.insertBefore(hh, first);
                    if (first.firstChild && first.firstChild.nodeType === 3) first.firstChild.textContent = '';
                    if (tbl) {
                        tbl.classList.add('pv-st', 'pv-st-plain');
                        var names = qa('th', tbl).map(function (th) { return th.textContent; });
                        qa('tr', tbl).forEach(function (tr) {
                            qa('td', tr).forEach(function (td, i) { td.setAttribute('data-label', names[i] || ''); if (i === 0) td.classList.add('pv-st-first'); });
                        });
                        // the request to return it: a chip, not a red band
                        qa('.bg-persimmon-500', tbl).forEach(function (s) { s.className = 'pv-bib-chip pv-bib-chip-warn'; s.textContent = 'Bitte zurückbringen'; });
                    }
                }
            }
            // staff: the copies' sections with their numbers
            [['#checked_out_all', 'Ausgeliehen'], ['#in_stock_all', 'Im Bestand'], ['#in_limbo_all', 'In limbo'], ['#discarded_all', 'Ausgemustert']].forEach(function (x) {
                var box = q(x[0]);
                if (!box) return;
                var h3 = q(':scope > h3', box);
                if (!h3) return;
                box.classList.add('pv-bib-sec');
                var m = h3.textContent.match(/(\d+)\s*$/);
                h3.className = 'pv-bib-section';
                h3.textContent = x[1];
                if (m) h3.appendChild(el('span', 'pv-bib-count-inline', m[1]));
                qa('.alert-warning', box).forEach(function (a) { a.className = 'pv-bib-empty'; });
                // copies in stock: just signatures, as a flowing list
                if (x[0] === '#in_stock_all' || x[0] === '#discarded_all' || x[0] === '#in_limbo_all') {
                    qa('.pv-st-wrap', box).forEach(function (w) { if (qa('thead th', w).length === 1) w.classList.add('pv-st-sigs'); });
                }
                qa('p.text-muted', box).forEach(function (a) { a.className = 'pv-bib-note'; });
            });
            // »zurückfordern« in the rows: quiet text buttons, the state in words
            qa('.bu-summon-book').forEach(function (b) { summon_button(b); });
        });
    };

    // the »zurückfordern« buttons (book, copy): quiet; the page switches
    // btn-warning / btn-outline-secondary and the text, we follow
    function summon_button(b) {
        b.classList.add('pv-bib-summon');
        var sync = function () {
            var on = b.classList.contains('btn-warning');
            b.setAttribute('aria-pressed', on ? 'true' : 'false');
            var want = on ? 'Zurückgefordert' : 'Zurückfordern';
            if (b.textContent !== want) b.textContent = want;
        };
        sync();
        new MutationObserver(sync).observe(b, { attributes: true, attributeFilter: ['class'], childList: true, characterData: true, subtree: true });
    }

    // ---------- Bestellungen (teachers) ----------
    // a list with actions: the book, the course, how many are still
    // missing and the state; »Stornieren« in »•••« (with a confirmation)
    pages['bib_orders'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-list');
        var old = q('.bib_teacher_only h3', p);
        if (old) old.classList.add('pv-bib-gone');
        var h = head('Bestellungen');
        var table = q('#order_table');
        if (!table) return;
        table.classList.add('pv-bib-gone');
        var list = el('div', 'pv-bib-orders');
        table.parentNode.insertBefore(list, table);
        tap('/jwt/my_orders', function (data) {
            if (!data.success) return;
            list.textContent = '';
            if (data.orders.length === 0) {
                h.facts('');
                var e = el('p', 'pv-bib-empty', 'Du hast noch nichts bestellt. Bücher für deinen Unterricht findest du im ');
                var a = el('a', null, 'Katalog');
                a.href = '/bib_browse';
                e.appendChild(a);
                e.appendChild(document.createTextNode('.'));
                list.appendChild(e);
                return;
            }
            var open = data.orders.filter(function (o) { return !o.o.complete; }).length;
            h.facts(plural(data.orders.length, 'Bestellung', 'Bestellungen') + (open ? ', ' + open + ' in Bearbeitung' : ''));
            data.orders.slice().reverse().forEach(function (order) {
                list.appendChild(order_row(order));
            });
        });
        function order_row(order) {
            var missing;
            if (order.o.lesson_key) {
                order.book_info = {
                    ordering_teacher_has_this_book: order.u.email in order.users_who_have_this_book,
                    ordering_teacher_email: order.u.email,
                    users_who_have_this_book: order.users_who_have_this_book,
                };
                missing = calculate_kurs_order_count(order.o.lesson_key, order.b.stem, order.o.plus_teacher, order.book_info);
            } else {
                missing = calculate_private_order_count(order.o.count, order.b.stem, order.u.email, order.users_who_have_this_book);
            }
            var kurs = order.o.lesson_key ? ((kurse[order.o.lesson_key] || {}).fach || order.o.lesson_key) : 'für mich';
            var state = order.o.complete ? { label: 'Bereit', state: 'running' } :
                (order.f_count === 0 ? { label: 'In Bearbeitung', state: 'planned' } : { label: 'Teilweise bereit', state: 'running' });
            var actions = [];
            if (!(order.f_count > 0)) {
                actions.push({
                    label: 'Stornieren', danger: true, run: function () {
                        confirm_danger('Die Bestellung von »' + order.b.title + '« ' + (order.o.lesson_key ? 'für ' + kurs : 'für dich') + ' wird storniert.', 'Bestellung stornieren', 'Stornieren', function () {
                            bib_api_call('/jwt/cancel_order', { oid: order.o.id }, function (res) {
                                if (res.success) { r.remove(); }
                            });
                        });
                    }
                });
            }
            var r = pv_list.row({
                title: order.b.title + (order.b.author ? '' : ''),
                facts: [order.b.author, order.o.lesson_key ? kurs : 'für dich', 'bestellt am ' + date(order.o.ts_order_placed), order.o.complete || !(missing > 0) ? null : (missing === 1 ? '1 Exemplar ausstehend' : missing + ' Exemplare ausstehend')],
                chip: state,
                open: function () { location.href = '/bib_book/' + order.b.stem; },
                actions: actions,
                cls: 'pv-bib-order-row',
            });
            r.setAttribute('data-oid', order.o.id);
            return r;
        }
    };

    // ---------- Nutzer (staff): a table, filters as chips ----------
    pages['bib_users'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-table');
        var h = head('Nutzer');
        var group = q('.input-group', p);
        if (group) {
            group.classList.add('pv-bib-search');
            var input = q('#ti_search', group);
            if (input) { input.setAttribute('placeholder', 'Name oder E-Mail-Adresse'); input.setAttribute('aria-label', 'Nutzer suchen'); input.setAttribute('type', 'search'); }
        }
        var labels = q('#labels_here');
        if (labels) {
            labels.classList.add('pv-bib-filters');
            Array.prototype.slice.call(labels.childNodes).forEach(function (n) { if (n.nodeType === 3) n.remove(); });
            labels.setAttribute('role', 'group');
            labels.setAttribute('aria-label', 'Klassen');
            labels.insertBefore(el('span', 'pv-bib-filters-label', 'Klassen'), labels.firstChild);
            qa('.bu-label', labels).forEach(function (b) {
                b.setAttribute('aria-pressed', 'false');
                b.addEventListener('click', function (e) {
                    var button = e.currentTarget;
                    setTimeout(function () { button.setAttribute('aria-pressed', $(button).data('flag') ? 'true' : 'false'); }, 0);
                });
            });
        }
        tap('/jwt/get_users', function (data) {
            if (!data.success) return;
            var lent = data.users.filter(function (u) { return u.ausleih_count > 0; }).length;
            h.facts(plural(data.users.length, 'Person', 'Personen') + ', ' + lent + ' mit ausgeliehenen Büchern');
        });
    };

    // ---------- one person (staff): their books, lending ----------
    pages['bib_user'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-table', 'pv-bib-userpage');
        var name = q('h2.display_name', p);
        var info = q('#user_info', p);
        var h = head('');
        if (name) { h.title.classList.add('display_name'); name.remove(); }
        if (info) info.classList.add('pv-bib-gone');
        var email = decodeURIComponent(location.pathname.replace('/bib_user/', ''));
        var u = db_user_info[email] || {};
        h.title.textContent = u.display_name || email;
        var facts = [];
        if (u.teacher) facts.push('Lehrkraft');
        else if (u.klasse) facts.push('Klasse ' + u.klasse);
        if (typeof klassenleiter !== 'undefined' && u.no_tr_klasse && klassenleiter[u.no_tr_klasse]) {
            var kl = klassenleiter[u.no_tr_klasse].map(function (x) { return (db_user_info[shorthands[x]] || {}).display_name; }).filter(Boolean);
            if (kl.length) facts.push('Klassenleitung ' + kl.join(', '));
        }
        if (typeof lehrmittelverein_state_cache !== 'undefined' && !u.teacher) facts.push(lehrmittelverein_state_cache[email] ? 'im Lehrmittelverein' : 'nicht im Lehrmittelverein');
        h.facts(facts.join(', '));
        // »Ausleihen« is the page's main action
        var checkout = q('#bu_checkout');
        if (checkout) {
            checkout.textContent = 'Ausleihen';
            checkout.classList.add('pv-bib-main');
            h.actions.appendChild(checkout);
        }
        var noverein = q('#hint_no_verein');
        if (noverein) {
            noverein.className = 'pv-bib-hint';
            var who = u.display_name || email;
            noverein.textContent = '';
            noverein.appendChild(icon('info-circle'));
            noverein.appendChild(el('span', null, who + ' ist nicht im Lehrmittelverein, deshalb kann hier nichts ausgeliehen werden.'));
            h.head.parentNode.insertBefore(noverein, h.head.nextSibling);
        }
        qa(':scope > hr', p).forEach(function (x) { x.hidden = true; });
        // the lending form: first the scanner, beside it teacher and course
        var co = q('#check_out_div');
        if (co) {
            co.classList.add('pv-bib-checkout');
            var cop = q(':scope > p', co);
            if (cop) cop.textContent = 'Scanne alle Bücher, die ausgeliehen werden sollen. Lehrkraft und Kurs sind freiwillig und gelten für alle folgenden Bücher.';
            qa(':scope > hr', co).forEach(function (x) { x.hidden = true; });
            qa('label.col-form-label', co).forEach(function (l) { l.textContent = l.textContent.replace(':', '').trim(); });
            var heading = el('h3', 'pv-bib-section', 'Ausleihen');
            co.insertBefore(heading, co.firstChild);
            var anchor = (noverein && noverein.parentNode === h.head.parentNode) ? noverein : h.head;
            anchor.parentNode.insertBefore(co, anchor.nextSibling);
            checkout && checkout.addEventListener('click', function () {
                setTimeout(function () {
                    var input = q('._barcode_widget input', co);
                    if (input && B.device) input.focus();
                }, 400);
            });
        }
        [['#book_table', 'Ausgeliehen'], ['#div_returned', 'Zurückgegeben'], ['#div_in_limbo', 'Aufgehobene Ausleihen']].forEach(function (x) {
            var box = q(x[0]);
            if (!box) return;
            var h3 = x[0] === '#book_table' ? box.previousElementSibling : q(':scope > h3', box);
            if (h3 && h3.tagName === 'H3') { h3.className = 'pv-bib-section'; h3.textContent = x[1]; }
        });
        tap('/jwt/get_checked_out_books_for_email', function (data) {
            if (!data.success) return;
            var h3 = q('#book_table') && q('#book_table').previousElementSibling;
            if (h3 && h3.tagName === 'H3') {
                h3.textContent = 'Ausgeliehen';
                h3.appendChild(el('span', 'pv-bib-count-inline', String(data.exemplare.length)));
                if (data.exemplare.length === 0) {
                    var t = q('#book_table');
                    var e = el('p', 'pv-bib-empty', 'Gerade nichts ausgeliehen.');
                    t.parentNode.insertBefore(e, t);
                    t.classList.add('pv-bib-gone');
                }
            }
            // »Ausleihe aufheben« (special access): quiet red text buttons
            qa('#book_table .btn-danger').forEach(function (b) {
                b.className = 'pv-bib-danger-btn';
                b.textContent = 'Ausleihe aufheben';
            });
        });
        tap('/jwt/checkout_exemplar_for_user', function () {
            var t = q('#book_table');
            var e = t && t.previousElementSibling;
            if (e && e.classList.contains('pv-bib-empty')) { e.remove(); t.classList.remove('pv-bib-gone'); }
        });
    };

    // ---------- Rückgabe (staff, scanner) ----------
    pages['bib_return'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-table', 'pv-bib-returnpage');
        var old = q('.row h3', p);
        var intro = old ? old.nextElementSibling : null;
        if (old) old.classList.add('pv-bib-gone');
        if (intro && intro.tagName === 'P') intro.classList.add('pv-bib-gone');
        // the column of the old title is empty now: the scanner alone
        var col = old ? old.closest('[class*="col-"]') : null;
        if (col) col.classList.add('pv-bib-gone');
        var h = head('Rückgabe');
        h.facts('Scanne alle Bücher, die zurückgegeben werden.');
        var row = q('.row', p);
        if (row) row.classList.add('pv-bib-scanrow');
        var mode = q('#bu_do_return');
        if (mode) {
            mode.classList.add('pv-bib-mode');
            var sync = function () {
                var on = mode.classList.contains('btn-success');
                mode.setAttribute('role', 'switch');
                mode.setAttribute('aria-checked', on ? 'true' : 'false');
                var want = on ? 'Zurückbuchen' : 'Nur prüfen, nicht zurückbuchen';
                if (mode.textContent !== want || !mode.querySelector('.ti')) {
                    mode.textContent = '';
                    mode.appendChild(icon(on ? 'toggle-right' : 'toggle-left'));
                    mode.appendChild(document.createTextNode(want));
                }
            };
            sync();
            new MutationObserver(function () { sync(); }).observe(mode, { attributes: true, attributeFilter: ['class'] });
            h.actions.appendChild(mode);
        }
        var table = q('#book_table');
        if (table) {
            var heading = el('h3', 'pv-bib-section', 'Gescannt');
            table.parentNode.insertBefore(heading, table);
            var empty = el('p', 'pv-bib-empty', 'Gescannte Bücher erscheinen hier, das neueste oben.');
            table.parentNode.insertBefore(empty, table);
            tap('/jwt/return_book', function (data) { if (data.success) empty.hidden = true; });
        }
    };

    // ---------- Bücher scannen (staff, a phone or the station) ----------
    pages['bib_scan'] = function () {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-list', 'pv-bib-scanpage');
        var h = head('Bücher scannen');
        h.facts('Scanne ein Buch, um zu sehen, was über es bekannt ist: ISBN, Lagerort und Cover.');
        qa('.alert', p).forEach(function (a) {
            a.classList.add('pv-bib-alert');
        });
        qa('#info_div hr', p).forEach(function (x) { x.hidden = true; });
        qa('#bu_scan_isbn, #bu_set_shelf, #bu_take_photo').forEach(function (b) {
            b.classList.remove('btn-success', 'pull-right');
            b.classList.add('btn-secondary', 'pv-bib-inline-btn');
        });
        var cancel = q('#bu_scan_isbn_cancel');
        if (cancel) { cancel.classList.remove('btn-danger', 'pull-right'); cancel.classList.add('btn-secondary', 'pv-bib-inline-btn'); }
        qa('#link_book, #link_exemplar').forEach(function (a) { a.classList.remove('btn-success', 'w-100'); a.classList.add('btn-secondary'); });
    };

    // ---------- the other staff pages: a title and calm parts ----------
    var TITLES = {
        bib_overview: 'Übersicht', bib_books: 'Medien', bib_all_orders: 'Alle Bestellungen', bib_discard: 'Ausmustern',
        bib_exemplar: 'Exemplar', bib_book_edit: 'Metadaten bearbeiten', bib_add_exemplare: 'Neue Exemplare aufnehmen',
        bib_print_label: 'Label drucken', bib_shelves: 'Regale', bib_scan_shelf: 'Regal scannen', bib_process_order: 'Bestellung bearbeiten',
        bib_scan_isbn: 'ISBN erfassen', bib: 'Medien',
    };
    function generic() {
        var p = panel();
        if (!p) return;
        p.classList.add('pv-bib-table');
        if (TITLES[PAGE]) head(TITLES[PAGE]);
        qa('.alert-warning', p).forEach(function (a) { a.classList.add('pv-bib-alert'); });
    }

    // ---------- start ----------
    function start() {
        build_nav();
        move_subnav();
        mark_sidebar();
        if (pages[PAGE]) pages[PAGE]();
        else generic();
        // headings of sections in the pages: one size
        var p = panel();
        if (p) qa('h3', p).forEach(function (h3) { if (!h3.classList.contains('pv-bib-section') && !h3.closest('.modal')) h3.classList.add('pv-bib-section'); });
        document.body.classList.add('pv-bib-ready');
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();

    // at a library device, a scanner page is ready to scan: its field gets
    // the focus (the scanner types like a keyboard; F8 still works)
    if (B.device) {
        window.addEventListener('load', function () {
            setTimeout(function () {
                var input = qa('._barcode_widget input').filter(function (i) { return i.offsetParent !== null && !i.disabled; })[0];
                var active = document.activeElement;
                if (input && (!active || active === document.body)) input.focus();
            }, 0);
        });
    }

    window.pv_bib = { tap: tap, head: head, hint: hint, el: el, icon: icon };
})();
