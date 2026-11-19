// Neues Design (Vorschau): the Datentresor hotline as a bar on every page,
// for admins with the hotline role (include/start_todo.rb). A request means
// someone is on the phone right now: the bar names them and says how long
// they have been waiting; »Freigeben …« opens the dialog that releases them.
//
// The dialog and the release are the start page's, unchanged
// (timetable.html, .bu_open_ad_hoc_2fa_request): there the button opens it
// directly, from other pages it leads to /#hotline=<email>, and the start
// page opens the dialog when that person is still waiting. Nothing is ever
// released from here.
//
// The bar asks /api/hotline_requests every 20 s while the page is visible,
// and right away when it becomes visible again. Styles: preview/start.css.
(function () {
    'use strict';
    var POLL_MS = 20 * 1000;
    var bar = document.getElementById('pv_hotline');
    if (!bar) return;
    var requests = (window.pv_hotline_data || {}).requests || [];
    var fetched_at = Date.now();
    var stopped = false;
    var last_poll = Date.now();

    // the start page has the dialog
    function dialog_here() {
        return !!document.getElementById('adHoc2FaRequestModal');
    }

    function age() {
        return (Date.now() - fetched_at) / 1000;
    }

    function open_requests() {
        return requests.filter(function (r) { return r.expires_in - age() > 0; });
    }

    function waiting_label(r) {
        var min = Math.floor((r.waiting + age()) / 60);
        return min < 1 ? 'wartet seit eben' : 'wartet seit ' + min + ' min';
    }

    function node(tag, cls, text) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (text !== undefined) n.textContent = text;
        return n;
    }

    function render() {
        var open = open_requests();
        bar.textContent = '';
        bar.hidden = open.length === 0;
        document.body.classList.toggle('pv-hotline-on', open.length > 0);
        open.forEach(function (r) {
            var row = node('div', 'pv-hotline-row');
            var lead = node('i', 'ti ti-phone pv-hotline-icon');
            lead.setAttribute('aria-hidden', 'true');
            var text = node('span', 'pv-hotline-text');
            text.appendChild(node('span', 'pv-hotline-kicker', 'Datentresor-Hotline'));
            var who = node('span', 'pv-hotline-who');
            who.appendChild(node('b', null, r.name));
            who.appendChild(document.createTextNode(' '));
            who.appendChild(node('span', 'pv-hotline-wait', waiting_label(r)));
            text.appendChild(who);
            var action;
            if (dialog_here()) {
                action = node('button', 'pv-hotline-btn bu_open_ad_hoc_2fa_request', 'Freigeben …');
                action.type = 'button';
                action.setAttribute('data-email', r.email);
                action.setAttribute('data-name', r.dialog_name);
            } else {
                action = node('a', 'pv-hotline-btn', 'Freigeben …');
                action.setAttribute('href', '/#hotline=' + encodeURIComponent(r.email));
            }
            action.setAttribute('aria-label', r.name + ' freigeben …');
            row.appendChild(lead);
            row.appendChild(text);
            row.appendChild(action);
            bar.appendChild(row);
        });
    }

    function poll() {
        if (stopped || document.visibilityState !== 'visible') return;
        last_poll = Date.now();
        // quietly: no "please wait", no error message when the network is gone
        jQuery.post({ url: '/api/hotline_requests', data: '{}', contentType: 'application/json', dataType: 'json' })
            .done(function (d) {
                requests = d.requests || [];
                fetched_at = Date.now();
                render();
            })
            .fail(function (xhr) {
                // logged out, or no longer allowed: stop asking
                if (xhr.status >= 400 && xhr.status < 600 && xhr.status !== 502 && xhr.status !== 503 && xhr.status !== 504) {
                    stopped = true;
                    requests = [];
                    render();
                }
            });
    }

    // from another page: open the dialog for that person, if still waiting
    function open_from_hash() {
        var m = /^#hotline=(.+)$/.exec(window.pv_hotline_hash || '');
        if (!m || !dialog_here()) return;
        var email = '';
        try { email = decodeURIComponent(m[1]); } catch (err) { return; }
        var target = null;
        bar.querySelectorAll('.bu_open_ad_hoc_2fa_request').forEach(function (b) {
            if (b.getAttribute('data-email') === email) target = b;
        });
        if (target) jQuery(target).trigger('click');
        else if (window.dashboardAlert) window.dashboardAlert('Diese Anfrage ist schon erledigt oder abgelaufen.', 'Datentresor-Hotline');
    }

    render();
    // after the page's own handlers (the dialog's) are in place
    window.addEventListener('load', open_from_hash);
    setInterval(function () {
        if (Date.now() - last_poll >= POLL_MS - 500) poll(); else render();
    }, 10 * 1000);
    document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') poll();
    });
})();
