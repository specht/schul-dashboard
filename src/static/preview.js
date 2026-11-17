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
})();
