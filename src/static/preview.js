// Neues Design (Vorschau): small helpers for the new frame, loaded only for
// people who have switched the preview on (include/design_preview.rb).
(function() {
    var SIDEBAR = window.matchMedia('(min-width: 768px)');

    // Desktop: a menu of the sidebar opens as a panel next to it, beside its
    // entry – in several columns if it is longer than the window is high.
    function place_menu(menu, toggle) {
        if (!SIDEBAR.matches) return;
        // opened from a section panel of the tablet rail: beside that panel
        var rail_body = toggle.closest('.pv-rail-open > .pv-nav-body');
        if (rail_body) menu.style.setProperty('--pv-menu-left', Math.round(rail_body.getBoundingClientRect().right) + 'px');
        else menu.style.removeProperty('--pv-menu-left');
        menu.style.columnCount = '';
        menu.style.width = '';
        // the space above the footer
        var foot = document.querySelector('.foot');
        var bottom = foot && foot.offsetHeight > 0 ? foot.getBoundingClientRect().top : window.innerHeight;
        var room = bottom - 24;
        menu.style.setProperty('--pv-menu-max', room + 'px');
        var height = menu.scrollHeight;
        var columns = Math.min(4, Math.max(1, Math.ceil(height / room)));
        if (columns > 1) {
            menu.style.columnCount = columns;
            menu.style.width = (columns * 236) + 'px';
            height = menu.scrollHeight;
        }
        // the first entry level with the sidebar entry that opened the panel
        var anchor = toggle.getBoundingClientRect();
        menu.style.setProperty('--pv-menu-top', '0px');
        var first = menu.querySelector('.dropdown-item');
        var offset = 8;
        if (first) {
            var m = menu.getBoundingClientRect(), f = first.getBoundingClientRect();
            offset = (f.top - m.top) + (f.height - anchor.height) / 2;
        }
        var top = anchor.top - offset;
        // menus of the footer (oneself): open upwards, the panel's bottom level
        // with the sidebar's bottom
        var in_foot = !!toggle.closest('.pv-nav-foot');
        if (in_foot) {
            bottom = window.innerHeight;
            top = bottom - 8 - Math.min(height, room);
        }
        top = Math.max(12, Math.min(top, bottom - Math.min(height, room) - (in_foot ? 8 : 12)));
        menu.style.setProperty('--pv-menu-top', Math.round(top) + 'px');
    }

    function place_open_menus() {
        document.querySelectorAll('.navbar .dropdown-menu.show').forEach(function(menu) {
            var toggle = menu.parentElement.querySelector('.dropdown-toggle');
            if (toggle) place_menu(menu, toggle);
        });
    }

    // whenever Bootstrap opens a menu (click, keyboard): place it
    function watch() {
        var nav = document.querySelector('nav.navbar');
        if (!nav) return;
        new MutationObserver(function(changes) {
            changes.forEach(function(c) {
                var el = c.target;
                if (el.classList && el.classList.contains('dropdown-menu') && el.classList.contains('show')) {
                    var toggle = el.parentElement.querySelector('.dropdown-toggle');
                    if (toggle) place_menu(el, toggle);
                }
            });
        }).observe(nav, { attributes: true, attributeFilter: ['class'], subtree: true });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', watch); else watch();
    window.addEventListener('resize', place_open_menus);

    // the icon rail on tablets shows no names: give every entry a tooltip
    function rail_titles() {
        document.querySelectorAll('.navbar .navbar-collapse > .navbar-nav > .nav-item > .nav-link').forEach(function(a) {
            if (a.getAttribute('title')) return;
            var name = (a.textContent || '').replace(/\s+/g, ' ').trim();
            if (name) a.setAttribute('title', name);
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', rail_titles); else rail_titles();

    // Phones: dialogs with .pv-sheet are sheets (preview.css) – pull one down to
    // close it, from its header or from its content when that is scrolled
    // to the top. Not far enough: it springs back.
    var sheet = null;   // { content, y, t, dragging, dy, veil, full, h }
    function sheet_move(content, y, ms) {
        content.style.transition = ms ? 'transform ' + ms + 'ms ease-out' : 'none';
        content.style.transform = y ? 'translateY(' + y + 'px)' : '';
    }
    // The veil follows the sheet: while it is pulled, the veil is as strong as
    // the part of the sheet still showing; it fades out with the sheet's slide
    // instead of standing until the sheet is gone.
    function sheet_veil(s) {
        if (s.menu) return document.querySelector('.pv-menu-veil:not(.pv-plan-veil)');
        if (s.plan) return document.querySelector('.pv-plan-veil');
        var backdrops = document.querySelectorAll('.modal-backdrop.show');
        return backdrops.length ? backdrops[backdrops.length - 1] : null;
    }
    function veil_to(veil, opacity, ms) {
        if (!veil) return;
        veil.style.transition = ms ? 'opacity ' + ms + 'ms ease-out' : 'none';
        veil.style.opacity = opacity === null ? '' : String(opacity);
        if (opacity === null) setTimeout(function() { veil.style.transition = ''; }, (ms || 0) + 20);
    }
    // a veil that goes with its sheet: fades with the slide, then is removed
    window.pv_veil_away = function(veil, ms) {
        if (!veil) return;
        veil.style.pointerEvents = 'none';
        veil_to(veil, 0, ms);
        setTimeout(function() { veil.remove(); }, ms);
    };
    document.addEventListener('touchstart', function(e) {
        sheet = null;
        if (SIDEBAR.matches || e.touches.length !== 1 || !e.target.closest) return;
        // the plan menu (a sheet on phones), from the sheet or its veil
        var plan = document.querySelector('.pv-plan-menu');
        if (plan && (plan.contains(e.target) || e.target.classList.contains('pv-plan-veil'))) {
            if (plan.contains(e.target) && plan.scrollTop > 0) return;
            sheet = { plan: true, content: plan, y: e.touches[0].clientY, t: Date.now(), dragging: false, dy: 0 };
            return;
        }
        // the "Mehr" menu (a sheet on phones), from the sheet or its veil
        var menu = document.querySelector('.ui-preview #navbarTogglerDemo02.show');
        if (menu && (menu.contains(e.target) || e.target.classList.contains('pv-menu-veil'))) {
            if (menu.contains(e.target) && menu.scrollTop > 0) return;
            sheet = { menu: true, content: menu, y: e.touches[0].clientY, t: Date.now(), dragging: false, dy: 0 };
            return;
        }
        // on the sheet or on the veil above it
        var modal = e.target.closest('.pv-sheet.show');
        if (!modal) return;
        var content = modal.querySelector('.modal-content');
        if (!content) return;
        var body = content.querySelector('.modal-body');
        if (body && body.contains(e.target) && body.scrollTop > 0) return;
        if (e.target.closest('textarea, input, select')) return;
        sheet = { modal: modal, content: content, y: e.touches[0].clientY, t: Date.now(), dragging: false, dy: 0 };
    }, { passive: true });
    document.addEventListener('touchmove', function(e) {
        if (!sheet || e.touches.length !== 1) return;
        var dy = e.touches[0].clientY - sheet.y;
        if (!sheet.dragging) {
            if (dy < -8) { sheet = null; return; }
            if (dy < 8) return;
            sheet.dragging = true;
            sheet.veil = sheet_veil(sheet);
            sheet.full = sheet.veil ? (parseFloat(getComputedStyle(sheet.veil).opacity) || 1) : 1;
            sheet.h = sheet.content.offsetHeight || 1;
        }
        e.preventDefault();
        sheet.dy = Math.max(0, dy);
        sheet_move(sheet.content, sheet.dy, 0);
        veil_to(sheet.veil, sheet.full * Math.max(0, 1 - sheet.dy / sheet.h), 0);
    }, { passive: false });
    function sheet_end() {
        if (!sheet) return;
        var s = sheet;
        sheet = null;
        if (!s.dragging) return;
        var quick = Date.now() - s.t < 250 && s.dy > 30;
        if (s.dy > 90 || quick) {
            sheet_move(s.content, s.content.offsetHeight + 20, 180);
            veil_to(s.veil, 0, 180);
            if (s.modal) s.modal.dataset.pvSliding = '1';
            setTimeout(function() {
                if (s.menu) {
                    if (window.pv_menu_hide_now) window.pv_menu_hide_now();
                    // the "Mehr" veil stays in the page (hidden): full again for the next time
                    if (s.veil) { s.veil.style.opacity = ''; s.veil.style.transition = ''; }
                    return;
                }
                if (s.plan) {
                    if (window.pv_close_plan_menu) window.pv_close_plan_menu(false);
                    return;
                }
                if (window.jQuery) window.jQuery(s.modal).modal('hide');
                setTimeout(function() { sheet_move(s.content, 0, 0); }, 50);
            }, 180);
        } else {
            sheet_move(s.content, 0, 160);
            veil_to(s.veil, null, 160);
        }
    }
    document.addEventListener('touchend', sheet_end);
    document.addEventListener('touchcancel', sheet_end);

    // Sheets close by sliding down, however they are closed ("Schließen",
    // the veil, Escape): the dialog hides once the slide is over.
    function slide_sheets_down() {
        if (!window.jQuery) return;
        var $ = window.jQuery;
        // Phones: every dialog is a sheet (doc/Gestaltung.md, 8) – only the
        // short questions and notes (dashboardAlert, dashboardConfirm) stay
        // in the middle of the screen
        $(document).on('show.bs.modal', '.ui-preview .modal', function(e) {
            if (SIDEBAR.matches || e.target !== e.currentTarget) return;
            if (/^__template_modal/.test(e.currentTarget.id || '')) return;
            e.currentTarget.classList.add('pv-sheet');
        });
        $(document).on('hide.bs.modal', '.ui-preview .pv-sheet', function(e) {
            if (SIDEBAR.matches || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
            var modal = e.currentTarget;
            if (modal.dataset.pvSliding === '1') { delete modal.dataset.pvSliding; return; }
            var content = modal.querySelector('.modal-content');
            if (!content) return;
            e.preventDefault();
            modal.dataset.pvSliding = '1';
            sheet_move(content, content.offsetHeight + 20, 180);
            veil_to(sheet_veil({ modal: modal }), 0, 180);
            setTimeout(function() {
                $(modal).modal('hide');
                setTimeout(function() { sheet_move(content, 0, 0); }, 50);
            }, 180);
        });
    }
    if (document.readyState === 'complete') slide_sheets_down(); else window.addEventListener('load', slide_sheets_down);

    // ---------- A sheet of links (phones), e.g. "Unterricht" in the tab bar ----------
    // groups: [[title, [[label, href], …]], …]; closes like every sheet
    window.pv_close_plan_menu = window.pv_close_plan_menu || function(animate) {
        var menu = document.querySelector('.pv-plan-menu');
        if (!menu) return;
        document.querySelectorAll('.pv-plan-veil').forEach(function(v) {
            if (animate) window.pv_veil_away(v, 180); else v.remove();
        });
        document.body.classList.remove('pv-sheet-open');
        if (animate) {
            menu.style.transition = 'transform 0.18s ease-in';
            menu.style.transform = 'translateY(100%)';
            setTimeout(function() { menu.remove(); }, 180);
        } else {
            menu.remove();
        }
    };

    // a group with {folded: true} as third part shows only its name with the
    // count, its links open on a tap (e.g. "Weitere Lerngruppen")
    window.pv_open_link_sheet = function(title, groups) {
        window.pv_close_plan_menu(false);
        var veil = document.createElement('div');
        veil.className = 'pv-menu-veil pv-plan-veil';
        veil.addEventListener('click', function() { window.pv_close_plan_menu(true); });
        var menu = document.createElement('div');
        menu.className = 'pv-plan-menu pv-link-sheet';
        menu.setAttribute('role', 'dialog');
        menu.setAttribute('aria-label', title);
        groups.forEach(function(g) {
            if (g[1].length === 0) return;
            var folded = !!(g[2] && g[2].folded);
            var head = document.createElement(folded ? 'button' : 'div');
            head.className = 'pv-plan-group';
            head.textContent = g[0];
            menu.appendChild(head);
            var list = document.createElement('div');
            list.className = 'pv-sheet-links';
            if (folded) {
                head.type = 'button';
                head.className = 'pv-more-groups pv-sheet-fold';
                head.textContent = g[0] + ' (' + g[1].length + ')';
                head.setAttribute('aria-expanded', 'false');
                list.hidden = true;
                head.addEventListener('click', function() {
                    list.hidden = !list.hidden;
                    head.setAttribute('aria-expanded', list.hidden ? 'false' : 'true');
                    if (!list.hidden) head.scrollIntoView({ block: 'start', behavior: 'smooth' });
                });
            }
            g[1].forEach(function(item) {
                var a = document.createElement('a');
                a.href = item[1];
                var name = document.createElement('span');
                name.textContent = item[0];
                a.appendChild(name);
                // the group's size
                if (item[2] && item[2] !== '0') {
                    var size = document.createElement('small');
                    size.className = 'pv-sheet-count';
                    size.textContent = item[2];
                    size.setAttribute('aria-label', item[2] + ' Schülerinnen und Schüler');
                    a.appendChild(size);
                }
                if (location.pathname === item[1].split('#')[0]) a.classList.add('active');
                list.appendChild(a);
            });
            menu.appendChild(list);
        });
        document.body.appendChild(veil);
        document.body.appendChild(menu);
        document.body.classList.add('pv-sheet-open');
    };

    // the entries of a menu of the navigation: [[label, href], …]
    window.pv_menu_links = function(toggle_id) {
        var menu = document.querySelector('[aria-labelledby="' + toggle_id + '"]');
        if (!menu) return [];
        return Array.prototype.map.call(menu.querySelectorAll('a.dropdown-item[href]:not([data-meeting])'), function(a) {
            var label = a.querySelector('.label');
            // [label, href, group size, one's own]
            return [(label || a).textContent.trim(), a.getAttribute('href'), a.getAttribute('data-count'), a.getAttribute('data-own') === '1'];
        }).filter(function(x) { return x[0] && x[1] && x[1].charAt(0) === '/'; });
    };

    // the Kursbuch entries (Planung) in the school's class order, grade 5
    // first, then by name – each part of the menu (between dividers) on its own
    function sort_course_menu() {
        var menu = document.querySelector('[aria-labelledby="navbarDropdownKurse"]');
        if (!menu) return;
        var parts = [[]];
        Array.prototype.slice.call(menu.children).forEach(function(el) {
            if (el.classList.contains('dropdown-divider')) parts.push(el, []);
            else parts[parts.length - 1].push(el);
        });
        var key = function(a) { return parseInt(a.getAttribute('data-order') || '999', 10); };
        var name = function(a) { return a.textContent.trim(); };
        parts.forEach(function(part) {
            if (!Array.isArray(part)) { menu.appendChild(part); return; }
            part.sort(function(a, b) { return key(a) - key(b) || name(a).localeCompare(name(b), 'de'); });
            part.forEach(function(el) { menu.appendChild(el); });
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', sort_course_menu); else sort_course_menu();

    // Lerngruppen: one's own groups first (classes, then courses), the others
    // behind "Weitere Lerngruppen (N)" – usually not needed (main.rb: data-own)
    function fold_group_menu() {
        var menu = document.querySelector('[aria-labelledby="navbarDropdownKlassen"]');
        if (!menu || menu.dataset.pvFolded) return;
        menu.dataset.pvFolded = '1';
        var items = Array.prototype.slice.call(menu.querySelectorAll('a.dropdown-item'));
        var own = items.filter(function(a) { return a.getAttribute('data-own') === '1'; });
        // the others in the school's order (the server lists the years 11
        // and 12 apart for some, before the rest)
        var order = function(a) { return parseInt(a.getAttribute('data-order') || '999', 10); };
        var others = items.filter(function(a) { return a.getAttribute('data-own') !== '1'; })
            .map(function(a, i) { return [a, i]; })
            .sort(function(x, y) { return order(x[0]) - order(y[0]) || x[1] - y[1]; })
            .map(function(x) { return x[0]; });
        if (others.length === 0) return;
        var own_classes = own.filter(function(a) { return /^Klasse\b/.test(a.textContent.trim()); });
        var own_courses = own.filter(function(a) { return own_classes.indexOf(a) < 0; });
        menu.querySelectorAll('.dropdown-divider').forEach(function(d) { d.remove(); });
        own_classes.forEach(function(a) { menu.appendChild(a); });
        if (own_classes.length && own_courses.length) {
            var d1 = document.createElement('div');
            d1.className = 'dropdown-divider';
            menu.appendChild(d1);
        }
        own_courses.forEach(function(a) { menu.appendChild(a); });
        var toggle = document.createElement('button');
        toggle.type = 'button';
        toggle.className = 'dropdown-item pv-more-groups';
        toggle.setAttribute('aria-expanded', 'false');
        toggle.textContent = 'Weitere Lerngruppen (' + others.length + ')';
        var box = document.createElement('div');
        box.className = 'pv-more-groups-list';
        box.hidden = true;
        others.forEach(function(a) { box.appendChild(a); });
        if (own.length) {
            var d2 = document.createElement('div');
            d2.className = 'dropdown-divider';
            menu.appendChild(d2);
        }
        menu.appendChild(toggle);
        menu.appendChild(box);
        toggle.addEventListener('click', function(e) {
            // keep the menu open (Bootstrap closes dropdowns on clicks inside)
            e.preventDefault();
            e.stopPropagation();
            box.hidden = !box.hidden;
            toggle.setAttribute('aria-expanded', box.hidden ? 'false' : 'true');
            // taller or shorter now: fit the panel into the window again
            var opener = menu.parentElement && menu.parentElement.querySelector('.dropdown-toggle');
            if (opener && menu.classList.contains('show')) place_menu(menu, opener);
            if (!box.hidden) toggle.scrollIntoView({ block: 'nearest' });
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fold_group_menu); else fold_group_menu();

    // ---------- Waiting for the server ----------
    // api_call (code.js) writes "Einen Moment bitte …" into the page's
    // message area after half a second, which pushes the page down. The new
    // design shows a thin bar at the top edge instead (preview.css); the old
    // design keeps its box.
    function busy_bar() {
        if (!document.body || !document.body.classList.contains('ui-preview') || document.querySelector('.pv-busy')) return;
        var bar = document.createElement('div');
        bar.className = 'pv-busy';
        bar.hidden = true;
        bar.setAttribute('role', 'progressbar');
        bar.setAttribute('aria-label', 'Wird geladen');
        document.body.appendChild(bar);
        var update = function() {
            var busy = !!document.querySelector('.api_messages .fa-spin');
            if (bar.hidden === busy) bar.hidden = !busy;
        };
        new MutationObserver(update).observe(document.body, { childList: true, subtree: true });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', busy_bar); else busy_bar();

    // ---------- Plain tables (pages not yet built for the new design) ----------
    // A Bootstrap table with one header row: every cell gets its column's
    // name (data-label). Where the list is narrow (a container query in
    // preview.css), each row becomes a list row: the first cell as its
    // title, the others as labelled facts, controls at the end. Matrices
    // (more than ten columns) scroll sideways with their first column in
    // place. A table without rows says so instead of showing a bare header.
    // Tables with a design of their own (pv-…, the library, Kursbuch and
    // class lists, calendars, dialogs) are left alone.
    function plain_tables() {
        if (!document.body || !document.body.classList.contains('ui-preview')) return;
        var main = document.getElementById('main_container');
        if (!main || main.dataset.pvTables) return;
        main.dataset.pvTables = '1';
        // the library styles its tables itself (preview/bib.js, which may
        // come later); Kursbuch and class lists are solid pages of their own
        if (document.body.classList.contains('pv-bib')) return;
        var OWN = '.fc, .modal, .container-fluid.solid, .lesson_table, .lesson_table_table, .schueler_table, .schueler_table_table, [class*="pv-"]';
        var busy = function() { return !!document.querySelector('.api_messages .fa-spin'); };
        var header_row = function(table) {
            if (table.tHead) return table.tHead.rows.length === 1 ? table.tHead.rows[0] : null;
            var first = table.tBodies[0] && table.tBodies[0].rows[0];
            if (first && first.cells.length > 1 && [].every.call(first.cells, function(c) { return c.tagName === 'TH'; })) {
                first.classList.add('pv-gt-headrow');
                return first;
            }
            return null;
        };
        var body_rows = function(table) {
            var rows = [];
            [].forEach.call(table.tBodies, function(tb) {
                [].forEach.call(tb.rows, function(tr) { if (!tr.classList.contains('pv-gt-headrow')) rows.push(tr); });
            });
            return rows;
        };
        var update = function(table) {
            var names = table._pv_names;
            var rows = body_rows(table);
            rows.forEach(function(tr) {
                if (tr.dataset.pvGt) return;
                tr.dataset.pvGt = '1';
                var col = 0;
                [].forEach.call(tr.cells, function(td, i) {
                    if (!td.hasAttribute('data-label')) td.setAttribute('data-label', names[col] || '');
                    if (i === 0) td.classList.add('pv-gt-first');
                    if (td.colSpan >= names.length && names.length > 1) td.classList.add('pv-gt-span');
                    if (td.querySelector('button, .btn, select, input[type=checkbox], input[type=radio]')) td.classList.add('pv-gt-act');
                    if (td.querySelector('input[type=text], input:not([type]), .input-group, textarea')) td.classList.add('pv-gt-field');
                    var t = td.textContent.trim();
                    if (i > 0 && (t === '–' || t === '-' || (t === '' && !td.querySelector('*')))) td.classList.add('pv-gt-none');
                    col += td.colSpan || 1;
                });
            });
            // empty: only once it stays empty (rows often come a moment later)
            var wrap = table.parentElement;
            var shown = rows.filter(function(tr) { return !tr.hidden && tr.style.display !== 'none'; }).length;
            clearTimeout(table._pv_empty);
            if (shown > 0) wrap.classList.remove('pv-gt-is-empty');
            else table._pv_empty = setTimeout(function() {
                if (!busy() && body_rows(table).filter(function(tr) { return !tr.hidden && tr.style.display !== 'none'; }).length === 0) wrap.classList.add('pv-gt-is-empty');
            }, 700);
        };
        var adopt = function(table) {
            if (table.dataset.pvGt) { update(table); return; }
            var own = table.closest(OWN);
            if (own && main.contains(own)) return;
            if (table.querySelector('[rowspan]')) return;
            var head = header_row(table);
            if (!head || head.cells.length < 2) return;
            table.dataset.pvGt = '1';
            table._pv_names = [].map.call(head.cells, function(th) { return th.textContent.trim(); });
            var wrap = table.parentElement;
            if (!wrap.classList.contains('table-responsive') || wrap.children.length > 1) {
                wrap = document.createElement('div');
                table.parentNode.insertBefore(wrap, table);
                wrap.appendChild(table);
            }
            wrap.classList.add('pv-gt-wrap');
            table.classList.add('pv-gt', table._pv_names.length > 10 ? 'pv-gt-matrix' : 'pv-gt-list');
            var note = document.createElement('p');
            note.className = 'pv-gt-empty-note';
            note.textContent = 'Keine Einträge.';
            wrap.appendChild(note);
            update(table);
        };
        var scan = function() { main.querySelectorAll('table.table').forEach(adopt); };
        var pending = null;
        new MutationObserver(function() {
            if (pending) return;
            pending = setTimeout(function() { pending = null; scan(); }, 50);
        }).observe(main, { childList: true, subtree: true });
        scan();
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', plain_tables); else plain_tables();

    // ---------- The navigation by task (new design) ----------
    // Heute, Nachrichten, Datentresor, then one entry each for Unterricht (my
    // courses), Lerngruppen, Schule (Klassenarbeiten and the school's tools)
    // and Verwaltung: each opens as a panel beside the sidebar, like the menus.
    // The profile menu keeps only what concerns oneself. The links are the
    // server's own (same permissions): tools are copied into the sections,
    // Lerngruppen is moved; the original menus stay in the page, hidden (the
    // Unterricht sheet and the search read them). Phones show the sections in
    // "Mehr" as tiles.
    var SCHULE = /^\/(tests|events|terminfinder|polls|mailing_lists|zufallsgruppen|kurslisten|bibliothek|projekttage|pk5|lab8|lab9|mittagessen|lehrbuchverein|gev|up|agr_app|klassenmemory_assign|salzh|angebote|groups)(\/|_|$)|^https:\/\/sv\./;
    var VERWALTUNG = /^\/(manage_news|manage_calendar|upload_images|upload_files|manage_monitor|admin|bookings|techpost|techpostadmin|development|tablets|school_wifi|show_all_login_codes|postfaecher|email_accounts|inactive_sus|stats|anmeldungen|aula_light|aula_progress|aula_sound)(\/|$)/;
    var SECTION_ICONS = { unterricht: 'ti-school', schule: 'ti-building', verwaltung: 'ti-settings' };

    // a section's panel: at most one open, level with its entry, inside the
    // window (in columns if it is longer than the window is high); a click
    // elsewhere or Escape closes it
    function section_panel(sec) {
        document.querySelectorAll('.pv-nav-section.pv-rail-open').forEach(function(open) {
            if (open === sec) return;
            open.classList.remove('pv-rail-open');
            open.querySelector('button.pv-nav-heading').setAttribute('aria-expanded', 'false');
        });
        if (!sec) return;
        var button = sec.querySelector('button.pv-nav-heading');
        // one panel at a time: an open menu (Lerngruppen, oneself) closes
        if (window.jQuery) {
            window.jQuery('.navbar .dropdown-menu.show').each(function() {
                var t = this.parentElement && this.parentElement.querySelector('[data-toggle="dropdown"]');
                if (t) window.jQuery(t).dropdown('hide');
            });
        }
        sec.classList.add('pv-rail-open');
        button.setAttribute('aria-expanded', 'true');
        place_section_panel(sec);
    }
    function place_section_panel(sec) {
        var button = sec.querySelector('button.pv-nav-heading');
        var panel = sec.querySelector('.pv-nav-body');
        var room = window.innerHeight - 24;
        panel.style.columnCount = '';
        panel.style.width = '';
        var lines = panel.querySelectorAll('.pv-nav-sub, .dropdown-divider');
        lines.forEach(function(line) { line.classList.remove('pv-col-top'); });
        var columns = Math.min(3, Math.max(1, Math.ceil(panel.scrollHeight / room)));
        if (columns > 1) {
            panel.style.columnCount = columns;
            panel.style.width = (columns * 272) + 'px';
            // a line between groups that lands at the top of a column
            // separates nothing there
            var top_of = panel.getBoundingClientRect().top + (parseFloat(getComputedStyle(panel).paddingTop) || 0);
            lines.forEach(function(line) {
                if (line.offsetParent && line.getBoundingClientRect().top - top_of < 12) line.classList.add('pv-col-top');
            });
        }
        var height = Math.min(panel.scrollHeight, room);
        var top = button.getBoundingClientRect().top - 6;
        top = Math.max(12, Math.min(top, window.innerHeight - 12 - height));
        panel.style.setProperty('--pv-rail-top', Math.round(top) + 'px');
    }
    document.addEventListener('click', function(e) {
        var open = document.querySelector('.pv-nav-section.pv-rail-open');
        if (open && !open.contains(e.target)) section_panel(null);
    });
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') section_panel(null);
    });
    // and a menu opening closes an open panel
    var close_panels_with_menus = function() {
        if (window.jQuery) window.jQuery(document).on('show.bs.dropdown', function() { section_panel(null); });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', close_panels_with_menus); else close_panels_with_menus();
    SIDEBAR.addEventListener('change', function() { section_panel(null); });
    window.addEventListener('resize', function() {
        var open = document.querySelector('.pv-nav-section.pv-rail-open');
        if (open) place_section_panel(open);
    });

    function regroup_navigation() {
        var collapse = document.getElementById('navbarTogglerDemo02');
        if (!collapse || collapse.dataset.pvRegrouped || !document.body.classList.contains('ui-preview')) return;
        collapse.dataset.pvRegrouped = '1';
        var main_nav = collapse.querySelector('.navbar-nav');
        if (!main_nav) return;
        var seen = {};
        var section = function(key, title) {
            var li = document.createElement('li');
            li.className = 'nav-item pv-nav-section';
            li.dataset.section = key;
            var head = document.createElement('div');
            head.className = 'pv-nav-heading';
            head.textContent = title;
            li.appendChild(head);
            return li;
        };
        var entry = function(a, label) {
            var copy = a.cloneNode(true);
            copy.classList.remove('dropdown-item');
            copy.classList.add('nav-link', 'pv-nav-entry');
            copy.removeAttribute('id');
            if (label) {
                var l = copy.querySelector('.label');
                if (l) l.textContent = label;
            }
            return copy;
        };
        var links = Array.prototype.slice.call(collapse.querySelectorAll('.dropdown-menu a.dropdown-item[href]'));
        var unterricht = section('unterricht', 'Unterricht');
        var schule = section('schule', 'Schule');
        var verwaltung = section('verwaltung', 'Verwaltung');

        // my courses (Kursbuch), in class order, without team meetings; the
        // earlier ones (after the divider) folded behind "Früherer Unterricht"
        var course_menu = collapse.querySelector('[aria-labelledby="navbarDropdownKurse"]');
        var current = [], earlier = [];
        if (course_menu) {
            var past_divider = false;
            Array.prototype.forEach.call(course_menu.children, function(el) {
                if (el.classList.contains('dropdown-divider')) { past_divider = true; return; }
                if (!el.matches('a.dropdown-item[href]:not([data-meeting])')) return;
                (past_divider ? earlier : current).push(el);
            });
        }
        var list = document.createElement('div');
        list.className = 'pv-nav-courses';
        current.forEach(function(a) {
            list.appendChild(entry(a));
            seen[a.getAttribute('href')] = true;
        });
        if (earlier.length) {
            var more = document.createElement('button');
            more.type = 'button';
            more.className = 'pv-more-groups pv-more-lessons';
            more.setAttribute('aria-expanded', 'false');
            more.textContent = 'Früherer Unterricht (' + earlier.length + ')';
            var box = document.createElement('div');
            box.className = 'pv-more-lessons-list';
            box.hidden = true;
            earlier.forEach(function(a) {
                box.appendChild(entry(a));
                seen[a.getAttribute('href')] = true;
            });
            more.addEventListener('click', function() {
                box.hidden = !box.hidden;
                more.setAttribute('aria-expanded', box.hidden ? 'false' : 'true');
                var sec = more.closest('.pv-nav-section.pv-rail-open');
                if (sec) place_section_panel(sec);
                if (!box.hidden) more.scrollIntoView({ block: 'nearest' });
            });
            if (current.length) {
                var d = document.createElement('div');
                d.className = 'dropdown-divider';
                list.appendChild(d);
            }
            list.appendChild(more);
            list.appendChild(box);
        }
        if (current.length || earlier.length) unterricht.appendChild(list);
        // Lerngruppen: the whole menu moves, as an entry of its own (own
        // groups first, the rest folded)
        var groups = document.getElementById('navbarDropdownKlassen');
        var groups_item = groups ? groups.closest('.nav-item') : null;
        if (groups) {
            groups_item.classList.add('pv-nav-groups');
            var gi = groups.querySelector('.icon');
            if (gi) gi.innerHTML = "<i class='ti ti-users-group'></i>";
        }
        links.forEach(function(a) {
            var href = a.getAttribute('href') || '';
            if (seen[href] || a.closest('[aria-labelledby="navbarDropdownKurse"], [aria-labelledby="navbarDropdownKlassen"]')) return;
            if (SCHULE.test(href)) { schule.appendChild(entry(a)); seen[href] = true; a.classList.add('pv-nav-moved'); }
            else if (VERWALTUNG.test(href)) { verwaltung.appendChild(entry(a)); seen[href] = true; a.classList.add('pv-nav-moved'); }
        });
        // the top level: Heute, Nachrichten, Datentresor stay; the old menus go
        var kurse_item = (document.getElementById('navbarDropdownKurse') || {}).closest ? document.getElementById('navbarDropdownKurse').closest('.nav-item') : null;
        if (kurse_item) kurse_item.classList.add('pv-nav-hidden');
        var admin_item = document.getElementById('navbarDropdownAdmin');
        if (admin_item) admin_item.closest('.nav-item').classList.add('pv-nav-hidden');
        // sections before the search / profile at the bottom
        var anchor = main_nav.querySelector('.nav-quick-search-item') || main_nav.querySelector('.nav-item.dropdown:last-child');
        // "Schule": the most used first, the seasonal ones last
        var ORDER = ['/events', '/terminfinder', '/tests', '/polls', '/bibliothek', '/mailing_lists', '/groups', '/angebote', '/zufallsgruppen', '/kurslisten', '/klassenmemory_assign', '/salzh', '/lehrbuchverein', '/mittagessen', '/gev', '/agr_app', '/up', '/projekttage', '/pk5', '/lab8', '/lab9'];
        var rank = function(a) {
            var href = a.getAttribute('href') || '';
            for (var i = 0; i < ORDER.length; i++) if (href.indexOf(ORDER[i]) === 0) return i;
            return ORDER.length;
        };
        Array.prototype.slice.call(schule.querySelectorAll('.pv-nav-entry'))
            .sort(function(a, b) { return rank(a) - rank(b); })
            .forEach(function(a) { schule.appendChild(a); });
        // sub-groups of the larger sections, in this order
        var SUB = {
            schule: [
                ['Planen & Abstimmen', /^\/(events|terminfinder|tests|polls|mailing_lists|groups|zufallsgruppen|kurslisten)/],
                ['Angebote', /^\/(bibliothek|angebote|lehrbuchverein|mittagessen|klassenmemory_assign|salzh)/],
                ['Projekte & Aktionen', /^\/(projekttage|pk5|lab8|lab9|up)(\/|_|$)/],
                ['Gremien', /^\/(gev|agr_app)|^https:\/\/sv\./],
            ],
            verwaltung: [
                ['Inhalte', /^\/(manage_news|manage_calendar|upload_images|upload_files|manage_monitor)/],
                ['Geräte & Räume', /^\/(bookings|tablets|techpost|techpostadmin|school_wifi|aula_)/],
                ['Konten & Anmeldung', /^\/(admin|show_all_login_codes|postfaecher|email_accounts|inactive_sus|anmeldungen|stats|development)/],
            ],
        };
        [['schule', schule], ['verwaltung', verwaltung]].forEach(function(pair) {
            var sec = pair[1], groups = SUB[pair[0]];
            var entries = Array.prototype.slice.call(sec.querySelectorAll('.pv-nav-entry'));
            var which = function(a) {
                var href = a.getAttribute('href') || '';
                for (var i = 0; i < groups.length; i++) if (groups[i][1].test(href)) return i;
                return groups.length;
            };
            // the group as a colour (phones: tiles tinted per group, preview.css)
            entries.forEach(function(a) { a.dataset.tone = pair[0] + '-' + which(a); });
            if (entries.length < 8) return;
            entries.sort(function(a, b) { return which(a) - which(b); });
            var last = -1;
            entries.forEach(function(a) {
                var g = which(a);
                if (g !== last && g < groups.length) {
                    var sub = document.createElement('div');
                    sub.className = 'pv-nav-sub';
                    sub.textContent = groups[g][0];
                    sec.appendChild(sub);
                }
                last = g;
                sec.appendChild(a);
            });
        });
        // each section one entry; it is marked when the current page is in it
        var here_path = location.pathname.replace(/\/$/, '') || '/';
        var first_section = true;
        [unterricht, 'groups', schule, verwaltung].forEach(function(sec) {
            if (sec === 'groups') {
                if (!groups_item) return;
                main_nav.insertBefore(groups_item, anchor);
                if (first_section) groups_item.classList.add('pv-nav-first');
                first_section = false;
                var in_groups = Array.prototype.some.call(groups_item.querySelectorAll('.dropdown-menu a[href]'), function(a) {
                    return (a.getAttribute('href') || '').replace(/\/$/, '') === here_path;
                });
                if (in_groups) groups.classList.add('pv-here');
                return;
            }
            if (sec.children.length <= 1) return;
            var key = sec.dataset.section;
            var head = sec.querySelector('.pv-nav-heading');
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'pv-nav-heading';
            button.setAttribute('aria-haspopup', 'true');
            var icon = document.createElement('div');
            icon.className = 'icon';
            icon.innerHTML = "<i class='ti " + (SECTION_ICONS[key] || 'ti-folder') + "'></i>";
            var name = document.createElement('span');
            name.className = 'label';
            name.textContent = head.textContent;
            button.appendChild(icon);
            button.appendChild(name);
            button.title = head.textContent;
            head.replaceWith(button);
            var body = document.createElement('div');
            body.className = 'pv-nav-body';
            while (button.nextSibling) body.appendChild(button.nextSibling);
            sec.appendChild(body);
            var contains_here = Array.prototype.some.call(body.querySelectorAll('a[href]'), function(a) {
                return (a.getAttribute('href') || '').replace(/\/$/, '') === here_path;
            });
            if (contains_here) button.classList.add('pv-here');
            button.setAttribute('aria-expanded', 'false');
            button.addEventListener('click', function(e) {
                e.preventDefault();
                // phones show every section open ("Mehr")
                if (!SIDEBAR.matches) return;
                section_panel(sec.classList.contains('pv-rail-open') ? null : sec);
            });
            if (first_section) sec.classList.add('pv-nav-first');
            first_section = false;
            main_nav.insertBefore(sec, anchor);
        });
        // the profile menu: its moved tools hidden, empty dividers too
        var profile = collapse.querySelector('[aria-labelledby="navbarDropdownProfile"]');
        if (profile) {
            Array.prototype.slice.call(profile.children).forEach(function(el, i, all) {
                if (!el.classList.contains('dropdown-divider')) return;
                var next = el.nextElementSibling;
                while (next && next.classList.contains('pv-nav-moved')) next = next.nextElementSibling;
                if (!next || next.classList.contains('dropdown-divider')) el.classList.add('pv-nav-hidden');
            });
        }
        // the current page marked in the new entries too
        var here = location.pathname.replace(/\/$/, '') || '/';
        collapse.querySelectorAll('.pv-nav-entry[href]').forEach(function(a) {
            if ((a.getAttribute('href') || '').replace(/\/$/, '') === here) a.classList.add('pv-active');
        });
        // desktop: search and oneself in a footer, only the list scrolls
        if (SIDEBAR.matches) {
            var foot = document.createElement('ul');
            foot.className = 'navbar-nav pv-nav-foot';
            var search_item = main_nav.querySelector('.nav-quick-search-item');
            var profile_toggle = document.getElementById('navbarDropdownProfile');
            if (search_item) foot.appendChild(search_item);
            if (profile_toggle) foot.appendChild(profile_toggle.closest('.nav-item'));
            if (foot.children.length) collapse.appendChild(foot);
        }
        if (typeof place_open_menus === 'function') place_open_menus();
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', regroup_navigation); else regroup_navigation();

    // The sidebar keeps its place across page loads (it is longer than the
    // window for many): its scroll position per tab, and the current entry
    // always in view; opened "Früherer Unterricht" / "Weitere Lerngruppen" stay open.
    function keep_sidebar_place() {
        var nav = document.querySelector('.ui-preview nav.navbar');
        if (!nav || !SIDEBAR.matches) return;
        nav = nav.querySelector('.navbar-collapse > .navbar-nav:not(.pv-nav-foot)') || nav;
        var KEY = 'pv_sidebar';
        var state = {};
        try { state = JSON.parse(sessionStorage.getItem(KEY) || '{}'); } catch (e) {}
        if (state.courses) { var m = nav.querySelector('.pv-more-lessons'); var c = nav.querySelector('.pv-more-lessons-list'); if (c && m) { c.hidden = false; m.setAttribute('aria-expanded', 'true'); } }
        if (state.groups) { var t = nav.querySelector('[aria-labelledby="navbarDropdownKlassen"] .pv-more-groups'); var b = nav.querySelector('.pv-more-groups-list'); if (t && b) { b.hidden = false; t.setAttribute('aria-expanded', 'true'); } }
        if (typeof state.top === 'number') nav.scrollTop = state.top;
        var active = nav.querySelector('.pv-active');
        if (active) {
            var r = active.getBoundingClientRect(), n = nav.getBoundingClientRect();
            if (r.top < n.top + 60 || r.bottom > n.bottom - 120) active.scrollIntoView({ block: 'center' });
        }
        var save = function() {
            try {
                sessionStorage.setItem(KEY, JSON.stringify({
                    top: nav.scrollTop,
                    courses: !!nav.querySelector('.pv-more-lessons[aria-expanded="true"]'),
                    groups: !!nav.querySelector('[aria-labelledby="navbarDropdownKlassen"] .pv-more-groups[aria-expanded="true"]'),
                }));
            } catch (e) {}
        };
        nav.addEventListener('click', save, true);
        window.addEventListener('pagehide', save);
    }
    if (document.readyState === 'complete') keep_sidebar_place(); else window.addEventListener('load', keep_sidebar_place);


    // the personal entries without the trailing "…" of today's menu
    var strip_ellipsis = function() {
        document.querySelectorAll('.ui-preview [aria-labelledby="navbarDropdownProfile"] .label').forEach(function(l) {
            l.textContent = l.textContent.replace(/\s*(…|\.\.\.)\s*$/, '');
        });
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', strip_ellipsis); else strip_ellipsis();
    // phones: the own card in "Mehr" opens the profile (instead of folding a menu)
    document.addEventListener('click', function(e) {
        if (SIDEBAR.matches || !e.target.closest || !e.target.closest('#navbarDropdownProfile')) return;
        if (!document.body.classList.contains('ui-preview')) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        location.href = '/profil';
    }, true);

    // phones: the search at the top of "Mehr" (the top bar has no icon)
    function more_search() {
        var nav = document.querySelector('.ui-preview #navbarTogglerDemo02 > .navbar-nav');
        if (!nav || !document.getElementById('bu_quick_search') || nav.querySelector('.pv-more-search')) return;
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'pv-more-search pv-search-button';
        b.innerHTML = "<i class='fa fa-search'></i><span>Suchen</span>";
        b.addEventListener('click', function() { if (window.pv_menu_hide_now) window.pv_menu_hide_now(); });
        nav.insertBefore(b, nav.firstChild);
    }
    // "Mo. 23.11.2026" in table cells: the weekday at a fixed width
    function weekday_columns() {
        document.querySelectorAll('.ui-preview td').forEach(function(td) {
            if (td.children.length) return;
            var m = /^(Mo|Di|Mi|Do|Fr|Sa|So)\.\s+(\d{1,2}\.\d{1,2}\.\d{2,4}.*)$/.exec(td.textContent.trim());
            if (!m) return;
            td.textContent = '';
            var wd = document.createElement('span');
            wd.className = 'pv-weekday';
            wd.textContent = m[1] + '.';
            td.appendChild(wd);
            td.appendChild(document.createTextNode(' ' + m[2]));
        });
    }
    // phones: Hilfe as a tile next to Datentresor (the personal part keeps four)
    function help_tile() {
        var nav = document.querySelector('.ui-preview #navbarTogglerDemo02 > .navbar-nav');
        var help = document.querySelector('[aria-labelledby="navbarDropdownProfile"] a[href="/hilfe"]');
        if (!nav || !help || nav.querySelector('.pv-help-tile')) return;
        var li = document.createElement('li');
        li.className = 'nav-item pv-help-tile';
        var a = help.cloneNode(true);
        a.className = 'nav-link nav-icon';
        li.appendChild(a);
        var tresor = nav.querySelector('a.nav-link[href="/tresor"]');
        var before = tresor ? tresor.closest('.nav-item').nextSibling : nav.querySelector('.pv-nav-section');
        nav.insertBefore(li, before);
    }
    // the page's footer line (copyright, Impressum, GitHub) moves into the
    // navigation: the sidebar's very bottom, the end of "Mehr"
    function legal_line() {
        var collapse = document.querySelector('.ui-preview #navbarTogglerDemo02');
        var foot = document.querySelector('.foot');
        if (!collapse || !foot || collapse.querySelector('.pv-legal')) return;
        var line = document.createElement('div');
        line.className = 'pv-legal';
        var school = foot.querySelector('a[href^="http"]');
        var imprint = foot.querySelector('a[href="/impressum"]');
        var github = document.querySelector('a.github');
        var parts = [];
        if (school) { var s = school.cloneNode(true); s.textContent = '© ' + new Date().getFullYear() + ' ' + school.textContent.replace(/\s+/g, ' ').trim(); parts.push(s); }
        if (imprint) parts.push(imprint.cloneNode(true));
        if (github) { var g = document.createElement('a'); g.href = github.href; g.target = '_blank'; g.rel = 'noopener'; g.className = 'pv-legal-icon'; g.setAttribute('aria-label', 'Quelltext auf GitHub'); g.title = 'Quelltext auf GitHub'; g.innerHTML = "<i class='fa fa-github'></i>"; parts.push(g); }
        // the tablet rail has no room for words: the Impressum as one quiet
        // icon there (preview.css), the line itself hidden
        if (imprint) { var r = document.createElement('a'); r.href = '/impressum'; r.className = 'pv-legal-rail'; r.title = 'Impressum'; r.setAttribute('aria-label', 'Impressum'); r.innerHTML = "<i class='ti ti-info-circle' aria-hidden='true'></i>"; parts.push(r); }
        parts.forEach(function(el) { line.appendChild(el); });
        // sidebar: the very bottom, below oneself; phones: the end of "Mehr"
        var foot_list = collapse.querySelector('.pv-nav-foot');
        if (foot_list) {
            var li = document.createElement('li');
            li.className = 'pv-legal-item';
            li.appendChild(line);
            foot_list.appendChild(li);
        } else collapse.querySelector('.navbar-nav').appendChild(line);
    }
    // phones, "Mehr": tiles fill their rows. The grids have six columns, a
    // tile spans two; a row that isn't full spreads its tiles: two left over
    // take half the width each, one left over turns the last four into two
    // rows of two (never a lonely tile). Separators start a new group.
    function balance_tiles() {
        var shown = function(el) { return getComputedStyle(el).display !== 'none'; };
        var by_order = function(a, b) { return (parseInt(getComputedStyle(a).order, 10) || 0) - (parseInt(getComputedStyle(b).order, 10) || 0); };
        var apply = function(run, per_row) {
            run.forEach(function(el) { el.classList.remove('pv-span-2', 'pv-span-3', 'pv-span-6'); el.classList.add(per_row === 2 ? 'pv-span-3' : 'pv-span-2'); });
            var n = run.length, rest = n % per_row;
            if (rest === 0) return;
            var wide = function(list, cls) { list.forEach(function(el) { el.classList.remove('pv-span-2', 'pv-span-3'); el.classList.add(cls); }); };
            if (per_row === 2 || n === 1) { wide([run[n - 1]], 'pv-span-6'); return; }
            if (rest === 2) wide(run.slice(n - 2), 'pv-span-3');
            else wide(run.slice(Math.max(0, n - 4)), 'pv-span-3');
        };
        var groups = function(holder, is_tile, per_row, sort) {
            if (!holder) return;
            var run = [];
            var kids = Array.prototype.slice.call(holder.children).filter(shown);
            if (sort) kids.sort(by_order);
            kids.forEach(function(el) {
                if (is_tile(el)) run.push(el);
                else { if (run.length) apply(run, per_row); run = []; }
            });
            if (run.length) apply(run, per_row);
        };
        var collapse = document.querySelector('.ui-preview #navbarTogglerDemo02');
        if (!collapse) return;
        // the top level and the profile's tiles share one grid on phones
        // (preview.css: the profile item dissolves), in their CSS order
        var top = collapse.querySelector('.navbar-nav:not(.pv-nav-foot)');
        var profile_menu = collapse.querySelector('[aria-labelledby="navbarDropdownProfile"]');
        var first_tiles = [];
        if (top) Array.prototype.slice.call(top.children).filter(shown).forEach(function(el) {
            if (el.classList.contains('nav-item') && !el.classList.contains('dropdown') && !el.classList.contains('pv-nav-section') && !el.classList.contains('nav-quick-search-item') && !el.classList.contains('pv-more-search')) first_tiles.push(el);
        });
        if (profile_menu) Array.prototype.slice.call(profile_menu.children).filter(shown).forEach(function(el) {
            // (Hell / Auto / Dunkel is a row across the width, not a tile)
            if (el.classList.contains('dropdown-item') && !el.classList.contains('switch-session') && !el.classList.contains('pv-mode-row')) first_tiles.push(el);
        });
        first_tiles.sort(by_order);
        if (first_tiles.length) apply(first_tiles, 3);
        collapse.querySelectorAll('.pv-nav-body').forEach(function(body) {
            groups(body, function(el) { return el.classList.contains('pv-nav-entry'); }, 3, false);
        });
    }
    // ---------- Back (button or swipe) closes what opened like a screen ----------
    // Dialogs and sheets (Bootstrap modals), "Mehr" on phones and overlays of
    // a page's own (pv_back.opened / pv_back.closed) get a history entry when
    // they open; back closes the top one instead of leaving the page, and
    // closing one in the page goes back over its entry (doc/Gestaltung.md).
    var pv_back = (function() {
        var open = [];          // [{id, close}] in opening order
        var skip_pop = 0;       // pops caused by our own history.back()
        var layer = function() { return history.state && history.state.pvLayer; };
        // a reload with a layer entry on top: nothing is open any more
        if (layer()) history.replaceState(Object.assign({}, history.state, { pvLayer: null }), '');
        // a dummy link (href="#") in an open layer must not navigate: the new
        // history entry would count as "back" and close the layer it opens
        // from (Termine: »Externe Teilnehmer…«); its own handler still runs
        document.addEventListener('click', function(e) {
            if (!open.length || !e.target.closest) return;
            if (e.target.closest('a[href="#"]')) e.preventDefault();
        }, true);
        window.addEventListener('popstate', function(e) {
            if (skip_pop > 0) { skip_pop--; return; }
            var want = e.state && e.state.pvLayer;
            // close every layer above the one the entry belongs to
            while (open.length && open[open.length - 1].id !== want) {
                var top = open.pop();
                try { top.close(); } catch (err) {}
            }
        });
        return {
            opened: function(id, close) {
                if (open.some(function(x) { return x.id === id; })) return;
                open.push({ id: id, close: close });
                history.pushState(Object.assign({}, history.state || {}, { pvLayer: id }), '');
            },
            closed: function(id) {
                var i = -1;
                open.forEach(function(x, k) { if (x.id === id) i = k; });
                if (i < 0) return;              // closed by back already
                open.splice(i, 1);
                if (layer() === id) { skip_pop++; history.back(); }
            }
        };
    })();
    window.pv_back = pv_back;

    // Keyboard shortcuts in every calendar, as in the timetable (and Google
    // Calendar): N or J the next week or month, P or K the one before, T
    // today. A calendar marks its buttons with data-pv-key="next|prev|today";
    // the visible, enabled one is pressed. Not while typing or with a dialog
    // or menu open. (The timetable has its own handler, with C as well.)
    document.addEventListener('keydown', function(e) {
        if (e.ctrlKey || e.metaKey || e.altKey || e.defaultPrevented || e.repeat) return;
        var target = e.target;
        if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
        if (document.querySelector('.modal.show, .pv-plan-menu') || document.body.classList.contains('pv-sheet-open')) return;
        var which = { n: 'next', j: 'next', p: 'prev', k: 'prev', t: 'today' }[(e.key || '').toLowerCase()];
        if (!which) return;
        var button = Array.prototype.find.call(document.querySelectorAll('[data-pv-key="' + which + '"]'), function(b) {
            return b.offsetParent !== null && !b.disabled;
        });
        if (!button) return;
        button.click();
        e.preventDefault();
    });

    // Light and dark in place (no reload): the mode's class and stylesheet,
    // the colours from the server (they differ per mode), the menu entry
    // turning into the other one (Hell / Dunkel). Pages that bake colours
    // into what they draw listen to "pv-colours-changed" (the timetable).
    // The old design keeps reloading (_template.html).
    function apply_dark(dark) {
        document.body.classList.toggle('dark', dark);
        var nav = document.querySelector('nav.navbar');
        if (nav) {
            nav.classList.toggle('navbar-dark', dark);
            nav.classList.toggle('navbar-light', !dark);
        }
        var sheet = document.querySelector('link[href="/dark.css"]');
        if (dark && !sheet) {
            sheet = document.createElement('link');
            sheet.rel = 'stylesheet';
            sheet.href = '/dark.css';
            document.head.appendChild(sheet);
        }
        if (!dark && sheet) sheet.remove();
        document.querySelectorAll('.nav-dark, .nav-light').forEach(function(b) {
            b.classList.toggle('nav-dark', !dark);
            b.classList.toggle('nav-light', dark);
            var i = b.querySelector('.icon i');
            if (i) i.className = dark ? 'fa fa-sun-o' : 'fa fa-moon';
            var label = b.querySelector('.label');
            if (label) label.textContent = dark ? 'Hell' : 'Dunkel';
        });
        // pages with their own switch follow (the profile's »Dunkles Design«)
        document.dispatchEvent(new CustomEvent('pv-dark-changed', { detail: { dark: dark } }));
        if (!window.color_scheme) return;
        fetch('/api/design_tokens?scheme=' + encodeURIComponent(window.color_scheme), { credentials: 'same-origin' })
            .then(function(r) { return r.json(); })
            .then(function(data) {
                if (!data.tokens) return;
                var tokens = document.getElementById('design_tokens');
                var backdrop = document.getElementById('design_backdrop');
                if (tokens) tokens.textContent = data.tokens;
                if (backdrop) backdrop.textContent = data.backdrop;
                var meta = document.querySelector('meta[name=theme-color]');
                if (meta) meta.setAttribute('content', data.theme_color);
                document.dispatchEvent(new CustomEvent('pv-colours-changed', { detail: { dark: dark } }));
            });
    }
    window.pv_apply_dark = apply_dark;

    // Hell / Auto / Dunkel (the menu and the profile, design_preview.rb
    // print_dark_mode_switch): stored, then switched in place. »Auto« follows
    // the device, also when it switches while the page is open; the server
    // learns the device's setting from a cookie (Main.effective_dark).
    var PREFERS_DARK = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
    function remember_prefers_dark() {
        if (!PREFERS_DARK) return;
        document.cookie = 'prefers_dark=' + (PREFERS_DARK.matches ? '1' : '0') + '; path=/; max-age=31536000; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
    }
    function dark_mode() {
        var seg = document.querySelector('.pv-mode');
        return seg ? seg.dataset.mode : null;
    }
    function show_dark_mode(mode) {
        document.querySelectorAll('.pv-mode').forEach(function(seg) {
            seg.dataset.mode = mode;
            seg.querySelectorAll('button[data-mode]').forEach(function(b) {
                b.setAttribute('aria-pressed', b.dataset.mode === mode ? 'true' : 'false');
            });
        });
    }
    function follow(mode) {
        var dark = mode === 'auto' ? !!(PREFERS_DARK && PREFERS_DARK.matches) : mode === 'dark';
        if (dark !== document.body.classList.contains('dark')) apply_dark(dark);
    }
    document.addEventListener('click', function(e) {
        if (!document.body.classList.contains('ui-preview') || !e.target.closest) return;
        var b = e.target.closest('.pv-mode button[data-mode]');
        if (!b || !window.api_call) return;
        // the menu stays open: one sees the choice take effect
        e.preventDefault();
        e.stopPropagation();
        var mode = b.dataset.mode;
        remember_prefers_dark();
        api_call('/api/set_dark_css', { mode: mode }, function(data) {
            if (!data.success) return;
            show_dark_mode(mode);
            follow(mode);
        });
    }, true);
    if (PREFERS_DARK) {
        PREFERS_DARK.addEventListener('change', function() {
            if (!document.body.classList.contains('ui-preview') || dark_mode() !== 'auto') return;
            remember_prefers_dark();
            follow('auto');
        });
    }
    // the font pair (profile, "Schrift"): a class on the body, preview.css
    // sets the fonts for it
    window.pv_apply_font = function(font) {
        var body = document.body;
        Array.prototype.slice.call(body.classList).forEach(function(c) {
            if (c.indexOf('pv-font-') === 0) body.classList.remove(c);
        });
        body.classList.add('pv-font-' + font);
    };
    // the menu entry: before _template.html's handler, which reloads
    document.addEventListener('click', function(e) {
        if (!document.body.classList.contains('ui-preview') || !e.target.closest) return;
        var b = e.target.closest('.nav-dark, .nav-light');
        if (!b || !window.api_call) return;
        e.preventDefault();
        e.stopPropagation();
        var dark = b.classList.contains('nav-dark');
        api_call('/api/set_dark_css', { mode: dark ? 'dark' : 'light' }, function(data) {
            if (data.success) apply_dark(dark);
        });
    }, true);
    function back_closes_layers() {
        if (!window.jQuery) return;
        var $ = window.jQuery;
        var n = 0;
        var id_of = function(el) {
            if (!el.dataset.pvLayer) el.dataset.pvLayer = 'modal-' + (el.id || ++n);
            return el.dataset.pvLayer;
        };
        $(document).on('show.bs.modal', '.modal', function(e) {
            if (e.target !== e.currentTarget) return;
            var el = e.currentTarget;
            pv_back.opened(id_of(el), function() { $(el).modal('hide'); });
        });
        $(document).on('hidden.bs.modal', '.modal', function(e) {
            if (e.target !== e.currentTarget) return;
            pv_back.closed(id_of(e.currentTarget));
        });
        // "Mehr" (phones only; on larger screens the menu is the sidebar)
        var menu = $('#navbarTogglerDemo02');
        menu.on('show.bs.collapse', function(e) {
            if (e.target !== menu[0] || SIDEBAR.matches) return;
            pv_back.opened('mehr', function() {
                if (window.pv_menu_hide_now) window.pv_menu_hide_now(); else menu.collapse('hide');
            });
        });
        menu.on('hidden.bs.collapse', function(e) {
            if (e.target !== menu[0]) return;
            pv_back.closed('mehr');
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', back_closes_layers); else back_closes_layers();

    // ---------- The page stands still behind an open sheet ----------
    // While a sheet is open ("Mehr", the plan menu, link sheets; on phones
    // every dialog), the page behind it doesn't scroll – a swipe on the veil
    // moved it before. Fixed at its scroll position (overflow: hidden alone
    // isn't enough for mobile Safari); back exactly there when it closes.
    (function() {
        var locked = null;
        var lock = function() {
            if (locked !== null) return;
            locked = window.scrollY;
            var b = document.body.style;
            b.position = 'fixed';
            b.top = (-locked) + 'px';
            b.left = '0';
            b.right = '0';
        };
        var unlock = function() {
            if (locked === null) return;
            var y = locked;
            locked = null;
            var b = document.body.style;
            b.position = '';
            b.top = '';
            b.left = '';
            b.right = '';
            window.scrollTo(0, y);
        };
        var check = function() {
            var c = document.body.classList;
            if (!c.contains('ui-preview')) return;
            if (c.contains('pv-sheet-open') || (c.contains('modal-open') && !SIDEBAR.matches)) lock(); else unlock();
        };
        var watch_body = function() {
            new MutationObserver(check).observe(document.body, { attributes: true, attributeFilter: ['class'] });
            check();
        };
        if (document.body) watch_body(); else document.addEventListener('DOMContentLoaded', watch_body);
    })();

    function later() { more_search(); weekday_columns(); help_tile(); legal_line(); balance_tiles(); }
    if (document.readyState === 'complete') later(); else window.addEventListener('load', function() { later(); setTimeout(weekday_columns, 1500); });
})();


// ---------- Lists with actions (doc/Gestaltung.md, 6a) ----------
// window.pv_list: the parts of the page type "Liste mit Aktionen" – rows,
// sub-rows, the "•••" menu (beside its button, a sheet on phones), folding,
// groups by school year and loading in blocks. Pages call these only in the
// new design (body.ui-preview); styles in preview.css (".pv-lrow" …).
(function() {
    var PHONE = window.matchMedia('(max-width: 767px)');

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }

    // a school year runs from 1 August to 31 July: its first year
    // ('2025-09-01', a Date or a moment → 2025)
    function school_year(d) {
        var y, m;
        if (typeof d === 'string') {
            y = parseInt(d.substr(0, 4), 10);
            m = parseInt(d.substr(5, 2), 10);
        } else {
            if (d && typeof d.toDate === 'function') d = d.toDate();
            d = d || new Date();
            y = d.getFullYear();
            m = d.getMonth() + 1;
        }
        return m >= 8 ? y : y - 1;
    }

    function school_year_label(y) {
        return 'Schuljahr ' + y + '/' + String((y + 1) % 100).padStart(2, '0');
    }

    // label, and on tablets a shorter one ("Neue Durchführung" → "Durchführen")
    function label_spans(button, label, short) {
        if (short && short !== label) {
            button.appendChild(el('span', 'pv-l-long', label));
            button.appendChild(el('span', 'pv-l-short', short));
            button.setAttribute('aria-label', label);
        } else {
            button.appendChild(el('span', null, label));
        }
    }

    // ---------- the "•••" menu ----------
    var open_menu = null;   // { menu, veil, trigger, sheet }
    var SHEET_LAYER = 'pv-action-sheet';

    function close_menu(animate, keep_focus) {
        var m = open_menu;
        if (!m) return;
        open_menu = null;
        m.trigger.setAttribute('aria-expanded', 'false');
        var slide = animate && m.sheet && !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (m.veil) { if (slide) window.pv_veil_away(m.veil, 180); else m.veil.remove(); }
        document.body.classList.remove('pv-sheet-open');
        document.removeEventListener('keydown', on_key, true);
        document.removeEventListener('mousedown', on_outside, true);
        window.removeEventListener('resize', on_resize);
        window.removeEventListener('scroll', on_scroll, true);
        if (slide) {
            m.menu.style.transition = 'transform 0.18s ease-in';
            m.menu.style.transform = 'translateY(100%)';
            setTimeout(function() { m.menu.remove(); }, 180);
        } else {
            m.menu.remove();
        }
        if (!keep_focus && document.body.contains(m.trigger)) m.trigger.focus({ preventScroll: true });
        // the sheet's history entry (back closes it, see pv_back)
        if (m.sheet && window.pv_back) window.pv_back.closed(SHEET_LAYER);
    }

    // phones: an action of the sheet runs once the sheet's history entry is
    // gone, so that a dialog it opens gets an entry of its own
    function after_sheet(fn) {
        if (!(history.state && history.state.pvLayer === SHEET_LAYER)) { fn(); return; }
        var done = false;
        var go = function() {
            if (done) return;
            done = true;
            window.removeEventListener('popstate', go);
            fn();
        };
        window.addEventListener('popstate', go);
        setTimeout(go, 400);
    }

    function menu_items() {
        return open_menu ? Array.prototype.slice.call(open_menu.menu.querySelectorAll('[role=menuitem]')) : [];
    }

    function on_key(e) {
        if (!open_menu) return;
        var items = menu_items();
        var i = items.indexOf(document.activeElement);
        if (e.key === 'Escape') {
            e.preventDefault();
            e.stopPropagation();
            close_menu(true);
        } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
            e.preventDefault();
            var n = items.length;
            if (n === 0) return;
            i = e.key === 'ArrowDown' ? (i + 1) % n : (i <= 0 ? n - 1 : i - 1);
            items[i].focus();
        } else if (e.key === 'Home' || e.key === 'End') {
            e.preventDefault();
            if (items.length) items[e.key === 'Home' ? 0 : items.length - 1].focus();
        } else if (e.key === 'Tab') {
            close_menu(false, true);
        }
    }

    function on_outside(e) {
        if (!open_menu) return;
        if (open_menu.menu.contains(e.target) || open_menu.trigger.contains(e.target)) return;
        if (open_menu.veil && e.target === open_menu.veil) return;
        close_menu(false, true);
    }

    function on_resize() { if (open_menu && open_menu.sheet !== PHONE.matches) close_menu(false, true); }

    function on_scroll(e) {
        if (open_menu && !open_menu.sheet && !open_menu.menu.contains(e.target)) place(open_menu.menu, open_menu.trigger);
    }

    // desktop: below the button, its right edge level with the button's;
    // above it when there is no room below
    function place(menu, trigger) {
        var r = trigger.getBoundingClientRect();
        var h = menu.offsetHeight, w = menu.offsetWidth;
        var top = r.bottom + 4;
        if (top + h > window.innerHeight - 8 && r.top - 4 - h > 8) top = r.top - 4 - h;
        var left = Math.max(8, Math.min(r.right - w, window.innerWidth - w - 8));
        menu.style.top = Math.round(top) + 'px';
        menu.style.left = Math.round(left) + 'px';
    }

    // actions: [{label, run, danger}]; title: the item's name (at the top of
    // the sheet, the menu's name for screen readers)
    // focus_first: opened from the keyboard (otherwise the menu itself has
    // the focus, the arrow keys still lead into it)
    function show_menu(trigger, title, actions, focus_first) {
        if (open_menu && open_menu.trigger === trigger) { close_menu(true); return; }
        close_menu(false, true);
        var sheet = PHONE.matches;
        var menu = el('div', 'pv-amenu' + (sheet ? ' pv-amenu-sheet' : ''));
        menu.setAttribute('role', 'menu');
        menu.setAttribute('aria-label', title);
        menu.tabIndex = -1;
        if (sheet) {
            var head = el('div', 'pv-amenu-title', title);
            head.setAttribute('aria-hidden', 'true');
            menu.appendChild(head);
        }
        var plain = actions.filter(function(a) { return !a.danger; });
        var danger = actions.filter(function(a) { return a.danger; });
        plain.concat(danger).forEach(function(a, i) {
            if (a.danger && i === plain.length && plain.length > 0) {
                var sep = el('div', 'pv-amenu-sep');
                sep.setAttribute('role', 'separator');
                menu.appendChild(sep);
            }
            var b = el('button', 'pv-amenu-item' + (a.danger ? ' pv-amenu-danger' : '') + (a.cls ? ' ' + a.cls : ''), a.label);
            b.type = 'button';
            b.setAttribute('role', 'menuitem');
            b.addEventListener('click', function(e) {
                e.stopPropagation();
                // the menu closes first: a confirmation opens on its own
                var was_sheet = open_menu && open_menu.sheet;
                close_menu(false);
                if (was_sheet) after_sheet(a.run); else a.run();
            });
            menu.appendChild(b);
        });
        var veil = null;
        if (sheet) {
            veil = el('div', 'pv-amenu-veil');
            veil.addEventListener('click', function() { close_menu(true); });
            document.body.appendChild(veil);
            document.body.classList.add('pv-sheet-open');
        }
        document.body.appendChild(menu);
        if (!sheet) place(menu, trigger);
        open_menu = { menu: menu, veil: veil, trigger: trigger, sheet: sheet };
        trigger.setAttribute('aria-expanded', 'true');
        document.addEventListener('keydown', on_key, true);
        document.addEventListener('mousedown', on_outside, true);
        window.addEventListener('resize', on_resize);
        window.addEventListener('scroll', on_scroll, true);
        // phones: back (button or swipe) closes the sheet, not the page
        if (sheet && window.pv_back) window.pv_back.opened(SHEET_LAYER, function() { close_menu(true); });
        var first = menu.querySelector('[role=menuitem]');
        if (first && focus_first) first.focus({ preventScroll: true });
        else menu.focus({ preventScroll: true });
    }

    // phones: pull the sheet down to close it
    var drag = null;
    document.addEventListener('touchstart', function(e) {
        drag = null;
        if (!open_menu || !open_menu.sheet || e.touches.length !== 1) return;
        if (!open_menu.menu.contains(e.target) && e.target !== open_menu.veil) return;
        if (open_menu.menu.scrollTop > 0) return;
        drag = { y: e.touches[0].clientY, t: Date.now(), dy: 0, on: false };
    }, { passive: true });
    document.addEventListener('touchmove', function(e) {
        if (!drag || !open_menu) return;
        var dy = e.touches[0].clientY - drag.y;
        if (!drag.on) {
            if (dy < -8) { drag = null; return; }
            if (dy < 8) return;
            drag.on = true;
        }
        e.preventDefault();
        drag.dy = Math.max(0, dy);
        open_menu.menu.style.transition = 'none';
        open_menu.menu.style.transform = 'translateY(' + drag.dy + 'px)';
        // the veil as strong as the part of the sheet still showing
        if (open_menu.veil) {
            open_menu.veil.style.transition = 'none';
            open_menu.veil.style.opacity = String(Math.max(0, 1 - drag.dy / (open_menu.menu.offsetHeight || 1)));
        }
    }, { passive: false });
    function drag_end() {
        var d = drag;
        drag = null;
        if (!d || !d.on || !open_menu) return;
        if (d.dy > 90 || (Date.now() - d.t < 250 && d.dy > 30)) {
            close_menu(true);
        } else {
            open_menu.menu.style.transition = 'transform 160ms ease-out';
            open_menu.menu.style.transform = '';
            if (open_menu.veil) {
                open_menu.veil.style.transition = 'opacity 160ms ease-out';
                open_menu.veil.style.opacity = '';
            }
        }
    }
    document.addEventListener('touchend', drag_end);
    document.addEventListener('touchcancel', drag_end);

    // ---------- a row ----------
    // o: {title, facts: [..] (joined with commas), chip: {label, state},
    //     open: fn (the title; on phones the whole row), open_label,
    //     actions: [{label, short, run, visible, danger, cls}], sub, cls,
    //     extra: element below the facts}
    // Visible actions show in the row on desktop and tablet, the others in
    // "•••"; on phones all of them are in the sheet. Delete (danger) always
    // goes into the menu, at its end.
    function row(o) {
        var r = el('div', 'pv-lrow' + (o.sub ? ' pv-lrow-sub' : '') + (o.chip && o.chip.state ? ' pv-state-' + o.chip.state : '') + (o.cls ? ' ' + o.cls : ''));
        var main = el('div', 'pv-lrow-main');
        r.appendChild(main);
        if (o.chip) main.appendChild(el('span', 'pv-lchip' + (o.chip.state ? ' pv-lchip-' + o.chip.state : ''), o.chip.label));
        var text = el('div', 'pv-lrow-text');
        main.appendChild(text);
        var title;
        if (o.open) {
            title = el('button', 'pv-lrow-title', o.title);
            title.type = 'button';
            title.addEventListener('click', function(e) { e.stopPropagation(); o.open(); });
        } else {
            title = el('span', 'pv-lrow-title', o.title);
        }
        text.appendChild(title);
        var facts = (o.facts || []).filter(function(f) { return f !== null && f !== undefined && f !== ''; });
        if (facts.length) text.appendChild(el('div', 'pv-lrow-facts', facts.join(', ')));
        if (o.extra) text.appendChild(o.extra);

        var actions = o.actions || [];
        var bar = el('div', 'pv-lrow-actions');
        actions.forEach(function(a) {
            if (!a.visible || a.danger) return;
            var b = el('button', 'pv-lact' + (a.cls ? ' ' + a.cls : ''));
            b.type = 'button';
            label_spans(b, a.label, a.short);
            b.addEventListener('click', function(e) { e.stopPropagation(); a.run(); });
            bar.appendChild(b);
        });
        if (actions.length) {
            var more = el('button', 'pv-lmore');
            more.type = 'button';
            more.setAttribute('aria-haspopup', 'menu');
            more.setAttribute('aria-expanded', 'false');
            more.setAttribute('aria-label', 'Weitere Aktionen für »' + o.title + '«');
            more.setAttribute('title', 'Weitere Aktionen');
            var dots = el('i', 'ti ti-dots');
            dots.setAttribute('aria-hidden', 'true');
            more.appendChild(dots);
            // desktop: what is not in the row; phones: everything
            var rest = function() {
                return PHONE.matches ? actions : actions.filter(function(a) { return !a.visible || a.danger; });
            };
            more.addEventListener('click', function(e) {
                e.stopPropagation();
                // e.detail is 0 when Enter or Space "clicked" the button
                show_menu(more, o.title, rest(), e.detail === 0);
            });
            bar.appendChild(more);
            // nothing left for the menu on larger screens: only on phones
            if (actions.every(function(a) { return a.visible && !a.danger; })) more.classList.add('pv-lmore-phone');
        }
        r.appendChild(bar);
        if (o.open) {
            var chev = el('i', 'pv-lrow-chev ti ti-chevron-right');
            chev.setAttribute('aria-hidden', 'true');
            r.appendChild(chev);
        }
        return r;
    }

    // ---------- folding: "2 beendete Durchführungen anzeigen" ----------
    // render(body) fills the folded part when it is opened the first time;
    // o: {open (start open), on_toggle(open)}
    function fold(parent, show_label, hide_label, render, o) {
        o = o || {};
        var b = el('button', 'pv-lfold', show_label);
        b.type = 'button';
        b.setAttribute('aria-expanded', 'false');
        var body = el('div', 'pv-lfold-body');
        body.hidden = true;
        var done = false;
        function toggle(open) {
            if (open && !done) { done = true; render(body); }
            body.hidden = !open;
            b.setAttribute('aria-expanded', open ? 'true' : 'false');
            b.textContent = open ? hide_label : show_label;
        }
        b.addEventListener('click', function() {
            var open = body.hidden;
            toggle(open);
            if (o.on_toggle) o.on_toggle(open);
        });
        parent.appendChild(b);
        parent.appendChild(body);
        if (o.open) toggle(true);
        return { button: b, body: body };
    }

    // ---------- a group with a heading (school year), foldable ----------
    // o: {label, count (quiet, next to the label), folded (foldable, closed
    //     at first), open (foldable, open at first), on_toggle(open), cls,
    //     render(body): fills the group the first time it is opened}
    function group(parent, o) {
        var s = el('section', 'pv-lgroup' + (o.cls ? ' ' + o.cls : ''));
        var h = el('h3', 'pv-lgroup-head');
        s.appendChild(h);
        var body = el('div', 'pv-lgroup-body');
        var done = false;
        var api = { section: s, body: body };
        if (o.folded) {
            var b = el('button', 'pv-lgroup-toggle');
            b.type = 'button';
            b.setAttribute('aria-expanded', 'false');
            b.appendChild(el('span', 'pv-lgroup-label', o.label));
            if (o.count) b.appendChild(el('span', 'pv-lgroup-count', o.count));
            var chev = el('i', 'pv-lgroup-chev ti ti-chevron-right');
            chev.setAttribute('aria-hidden', 'true');
            b.appendChild(chev);
            h.appendChild(b);
            body.hidden = true;
            api.open = function() {
                if (!body.hidden) return;
                if (!done) { done = true; if (o.render) o.render(body); }
                body.hidden = false;
                b.setAttribute('aria-expanded', 'true');
            };
            b.addEventListener('click', function() {
                var open = body.hidden;
                if (open) api.open();
                else { body.hidden = true; b.setAttribute('aria-expanded', 'false'); }
                if (o.on_toggle) o.on_toggle(open);
            });
        } else {
            h.appendChild(el('span', 'pv-lgroup-label', o.label));
            if (o.count) h.appendChild(el('span', 'pv-lgroup-count', o.count));
            done = true;
            api.open = function() {};
        }
        s.appendChild(body);
        parent.appendChild(s);
        if (!o.folded && o.render) o.render(body);
        else if (o.folded && o.open) api.open();
        return api;
    }

    // ---------- loading in blocks of 50 ----------
    // renders items[0..49], more on scroll (a sentinel at the end) or with
    // the button below ("Ältere Termine laden"); o.keep: a name under which
    // the list remembers how far it was shown when it is drawn again
    var blocks_shown = {};
    function blocks(parent, items, render, o) {
        o = o || {};
        var size = o.size || 50;
        var shown = 0;
        var first = o.keep && blocks_shown[o.keep] > size ? blocks_shown[o.keep] : size;
        var list = el('div', 'pv-lblocks');
        parent.appendChild(list);
        var foot = el('div', 'pv-lblocks-foot');
        var b = el('button', 'pv-lblocks-more', o.more || 'Ältere laden');
        b.type = 'button';
        foot.appendChild(b);
        parent.appendChild(foot);
        var observer = null;
        function next(n) {
            var end = Math.min(items.length, shown + (n || size));
            for (var i = shown; i < end; i++) list.appendChild(render(items[i], i));
            shown = end;
            if (o.keep) blocks_shown[o.keep] = shown;
            foot.hidden = shown >= items.length;
            if (shown >= items.length && observer) { observer.disconnect(); observer = null; }
        }
        b.addEventListener('click', function() { next(); });
        next(first);
        if (shown < items.length && 'IntersectionObserver' in window) {
            observer = new IntersectionObserver(function(entries) {
                // only while the list is in view (not in a folded group)
                if (entries.some(function(x) { return x.isIntersecting; }) && list.offsetParent !== null) next();
            }, { rootMargin: '200px 0px' });
            observer.observe(foot);
        }
        return { list: list, next: next, count: function() { return shown; } };
    }

    // ---------- the page: type "Liste mit Aktionen" ----------
    // container: the page's .container – at most about 980 px wide on
    // desktop, the title and the main action in one row (on phones the main
    // action with its short label, "Neu"); extra: quiet buttons beside it.
    function page(container, o) {
        o = o || {};
        container.classList.add('pv-page-list');
        var h2 = container.querySelector('h2');
        var head = el('div', 'pv-lhead');
        if (h2) {
            h2.parentNode.insertBefore(head, h2);
            head.appendChild(h2);
        }
        var side = el('div', 'pv-lhead-actions');
        head.appendChild(side);
        (o.extra || []).forEach(function(b) { if (b) { b.classList.add('pv-lhead-quiet'); side.appendChild(b); } });
        if (o.main) {
            var label = o.main.textContent.replace(/\s+/g, ' ').trim();
            var icon = o.main.querySelector('i');
            o.main.textContent = '';
            if (icon) o.main.appendChild(icon);
            label_spans(o.main, label, o.short || 'Neu');
            o.main.classList.add('pv-lhead-main');
            side.appendChild(o.main);
        }
        // the dividers of today's layout
        Array.prototype.forEach.call(container.querySelectorAll('hr'), function(hr) {
            if (!hr.closest('.modal')) hr.hidden = true;
        });
        // errors of api_call need a place on the page
        if (!document.querySelector('.api_messages')) {
            var msg = el('div', 'api_messages');
            msg.style.display = 'none';
            head.parentNode.insertBefore(msg, head.nextSibling);
        }
        return head;
    }

    function confirm_delete(text, on_confirm, title) {
        dashboardConfirm(text, on_confirm, { title: title || 'Löschen', confirm: 'Löschen', danger: true });
    }

    window.pv_list = {
        row: row, fold: fold, group: group, blocks: blocks, page: page,
        menu: show_menu, close_menu: close_menu, confirm_delete: confirm_delete,
        school_year: school_year, school_year_label: school_year_label,
        phone: function() { return PHONE.matches; }
    };
})();


// ---------- Copying (doc/Gestaltung.md, 7: »Kopieren«) ----------
// window.pv_copy: what people copy often (an address) as a quiet one-line
// field with a copy segment at its end. One click copies; a green check
// (ti-check) takes the place of the copy icon for a moment, the same size,
// so nothing moves; screen readers hear »… kopiert«. A long text ends in
// »…«, the title shows all of it. Styles: ".pv-copy" in preview.css.
//   pv_copy.field(text, {what, cls})  the field (a <button>); what: for
//                                     screen readers (»Adresse kopiert«)
//   pv_copy.run(button, text, {what})  copy from any other button
//                                          (with pv_copy.icons() in it)
(function() {
    var live = null;

    function announce(text) {
        if (!live) {
            live = document.createElement('div');
            live.className = 'sr-only';
            live.setAttribute('aria-live', 'polite');
            document.body.appendChild(live);
        }
        live.textContent = text;
    }

    function write(text, near, done) {
        function fallback() {
            // inside an open dialog, so that it keeps the focus
            var host = (near && near.closest('.modal')) || document.body;
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.position = 'fixed';
            ta.style.top = '0';
            ta.style.left = '0';
            ta.style.opacity = '0';
            host.appendChild(ta);
            ta.select();
            var ok = false;
            try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
            ta.remove();
            if (near) near.focus({ preventScroll: true });
            return ok;
        }
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(function() { done(true); }, function() { done(fallback()); });
        } else {
            done(fallback());
        }
    }

    function run(button, text, o) {
        o = o || {};
        write(text, button, function(ok) {
            if (!ok) {
                dashboardAlert('Das ließ sich nicht in die Zwischenablage kopieren. Du kannst den Text markieren und selbst kopieren.', 'Kopieren');
                return;
            }
            button.classList.add('pv-copied');
            announce((o.what || 'Adresse') + ' kopiert');
            clearTimeout(button.pv_copy_timer);
            button.pv_copy_timer = setTimeout(function() { button.classList.remove('pv-copied'); }, 1600);
        });
    }

    // the copy icon and, in its place after copying, the check
    function icons() {
        var frag = document.createDocumentFragment();
        ['copy', 'check'].forEach(function(name) {
            var i = document.createElement('i');
            i.className = 'ti ti-' + name + (name === 'check' ? ' pv-copy-ok' : ' pv-copy-icon');
            i.setAttribute('aria-hidden', 'true');
            frag.appendChild(i);
        });
        return frag;
    }

    function field(text, o) {
        o = o || {};
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'pv-copy' + (o.cls ? ' ' + o.cls : '');
        b.setAttribute('title', text + ' kopieren');
        b.setAttribute('aria-label', text + ' kopieren');
        b.setAttribute('data-copy', text);
        var t = document.createElement('span');
        t.className = 'pv-copy-text';
        t.textContent = text;
        b.appendChild(t);
        var end = document.createElement('span');
        end.className = 'pv-copy-end';
        end.appendChild(icons());
        b.appendChild(end);
        b.addEventListener('click', function(e) {
            // a field in a row that opens something: a click only copies
            e.stopPropagation();
            run(e.currentTarget, text, o);
        });
        return b;
    }

    window.pv_copy = { field: field, run: run, icons: icons };
})();
