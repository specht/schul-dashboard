// Neues Design (Vorschau): small helpers for the new frame, loaded only for
// people who have switched the preview on (include/design_preview.rb).
(function() {
    var SIDEBAR = window.matchMedia('(min-width: 768px)');

    // Desktop: a menu of the sidebar opens as a panel next to it, beside its
    // entry – in several columns if it is longer than the window is high.
    function place_menu(menu, toggle) {
        if (!SIDEBAR.matches) return;
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
        top = Math.max(12, Math.min(top, bottom - Math.min(height, room) - 12));
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
    var sheet = null;   // { content, y, t, dragging, dy }
    function sheet_move(content, y, ms) {
        content.style.transition = ms ? 'transform ' + ms + 'ms ease-out' : 'none';
        content.style.transform = y ? 'translateY(' + y + 'px)' : '';
    }
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
        }
        e.preventDefault();
        sheet.dy = Math.max(0, dy);
        sheet_move(sheet.content, sheet.dy, 0);
    }, { passive: false });
    function sheet_end() {
        if (!sheet) return;
        var s = sheet;
        sheet = null;
        if (!s.dragging) return;
        var quick = Date.now() - s.t < 250 && s.dy > 30;
        if (s.dy > 90 || quick) {
            sheet_move(s.content, s.content.offsetHeight + 20, 180);
            if (s.modal) s.modal.dataset.pvSliding = '1';
            setTimeout(function() {
                if (s.menu) {
                    if (window.pv_menu_hide_now) window.pv_menu_hide_now();
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
        }
    }
    document.addEventListener('touchend', sheet_end);
    document.addEventListener('touchcancel', sheet_end);

    // Sheets close by sliding down, however they are closed ("Schließen",
    // the veil, Escape): the dialog hides once the slide is over.
    function slide_sheets_down() {
        if (!window.jQuery) return;
        var $ = window.jQuery;
        $(document).on('hide.bs.modal', '.ui-preview .pv-sheet', function(e) {
            if (SIDEBAR.matches || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
            var modal = e.currentTarget;
            if (modal.dataset.pvSliding === '1') { delete modal.dataset.pvSliding; return; }
            var content = modal.querySelector('.modal-content');
            if (!content) return;
            e.preventDefault();
            modal.dataset.pvSliding = '1';
            sheet_move(content, content.offsetHeight + 20, 180);
            setTimeout(function() {
                $(modal).modal('hide');
                setTimeout(function() { sheet_move(content, 0, 0); }, 50);
            }, 180);
        });
    }
    if (document.readyState === 'complete') slide_sheets_down(); else window.addEventListener('load', slide_sheets_down);

    // ---------- A sheet of links (phones), e.g. "Kurse" in the tab bar ----------
    // groups: [[title, [[label, href], …]], …]; closes like every sheet
    window.pv_close_plan_menu = window.pv_close_plan_menu || function(animate) {
        var menu = document.querySelector('.pv-plan-menu');
        if (!menu) return;
        document.querySelectorAll('.pv-plan-veil').forEach(function(v) { v.remove(); });
        document.body.classList.remove('pv-sheet-open');
        if (animate) {
            menu.style.transition = 'transform 0.18s ease-in';
            menu.style.transform = 'translateY(100%)';
            setTimeout(function() { menu.remove(); }, 180);
        } else {
            menu.remove();
        }
    };

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
            var head = document.createElement('div');
            head.className = 'pv-plan-group';
            head.textContent = g[0];
            menu.appendChild(head);
            var list = document.createElement('div');
            list.className = 'pv-sheet-links';
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
        var others = items.filter(function(a) { return a.getAttribute('data-own') !== '1'; });
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
        });
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fold_group_menu); else fold_group_menu();

    // ---------- The navigation by task (new design) ----------
    // Heute · Nachrichten · Datentresor, then sections: Unterricht (my courses,
    // Klassenarbeiten, Lerngruppen), Schule, Verwaltung; the profile menu keeps
    // only what concerns oneself. The links are the server's own (same
    // permissions): tools are copied into the sections, Lerngruppen is moved;
    // the original menus stay in the page, hidden (the Kurse sheet and the
    // search read them).
    var SCHULE = /^\/(events|polls|prepare_vote|mailing_lists|zufallsgruppen|kurslisten|bibliothek|projekttage|pk5|lab8|lab9|mittagessen|lehrbuchverein|gev|up|agr_app|klassenmemory_assign|salzh|angebote|groups)(\/|_|$)|^https:\/\/sv\./;
    var VERWALTUNG = /^\/(manage_news|manage_calendar|upload_images|upload_files|manage_monitor|admin|bookings|techpost|techpostadmin|development|tablets|school_wifi|show_all_login_codes|postfaecher|email_accounts|inactive_sus|stats|anmeldungen|aula_light|aula_progress|aula_sound)(\/|$)/;
    var MAX_COURSES = 6;

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

        // my courses (Kursbuch), in class order, without team meetings
        var courses = Array.prototype.slice.call(collapse.querySelectorAll('[aria-labelledby="navbarDropdownKurse"] a.dropdown-item[href]:not([data-meeting])'));
        var current = courses.filter(function(a) { return !a.closest('.dropdown-menu') || true; });
        var list = document.createElement('div');
        list.className = 'pv-nav-courses';
        current.forEach(function(a, i) {
            var e = entry(a);
            if (i >= MAX_COURSES) e.classList.add('pv-nav-extra');
            list.appendChild(e);
            seen[a.getAttribute('href')] = true;
        });
        if (current.length > MAX_COURSES) {
            var more = document.createElement('button');
            more.type = 'button';
            more.className = 'nav-link pv-nav-entry pv-nav-more';
            more.setAttribute('aria-expanded', 'false');
            more.textContent = 'Alle Kurse (' + current.length + ')';
            more.addEventListener('click', function() {
                var open = list.classList.toggle('pv-nav-all');
                more.setAttribute('aria-expanded', open ? 'true' : 'false');
            });
            list.appendChild(more);
        }
        if (current.length) unterricht.appendChild(list);
        links.forEach(function(a) {
            var href = a.getAttribute('href') || '';
            if (seen[href] || a.closest('[aria-labelledby="navbarDropdownKurse"], [aria-labelledby="navbarDropdownKlassen"]')) return;
            if (href === '/tests') { unterricht.appendChild(entry(a)); seen[href] = true; a.classList.add('pv-nav-moved'); }
        });
        // Lerngruppen: the whole menu moves (own groups first, the rest folded)
        var groups = document.getElementById('navbarDropdownKlassen');
        if (groups) unterricht.appendChild(groups.closest('.nav-item'));
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
        var ORDER = ['/events', '/polls', '/bibliothek', '/mailing_lists', '/prepare_vote', '/groups', '/angebote', '/zufallsgruppen', '/kurslisten', '/klassenmemory_assign', '/salzh', '/lehrbuchverein', '/mittagessen', '/gev', '/agr_app', '/up', '/projekttage', '/pk5', '/lab8', '/lab9'];
        var rank = function(a) {
            var href = a.getAttribute('href') || '';
            for (var i = 0; i < ORDER.length; i++) if (href.indexOf(ORDER[i]) === 0) return i;
            return ORDER.length;
        };
        Array.prototype.slice.call(schule.querySelectorAll('.pv-nav-entry'))
            .sort(function(a, b) { return rank(a) - rank(b); })
            .forEach(function(a) { schule.appendChild(a); });
        [unterricht, schule, verwaltung].forEach(function(sec) {
            if (sec.children.length > 1) main_nav.insertBefore(sec, anchor);
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
        if (typeof place_open_menus === 'function') place_open_menus();
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', regroup_navigation); else regroup_navigation();
})();

