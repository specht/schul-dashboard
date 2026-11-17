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
        var top = toggle.getBoundingClientRect().top - 8;
        top = Math.max(12, Math.min(top, bottom - Math.min(height, room) - 12));
        menu.style.setProperty('--pv-menu-top', top + 'px');
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
            setTimeout(function() {
                if (s.menu) {
                    if (window.pv_menu_hide_now) window.pv_menu_hide_now();
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
})();
