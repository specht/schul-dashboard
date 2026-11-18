// Neues Design (Vorschau): Termine (/events) as a list with actions
// (doc/Gestaltung.md, 6a; pv_list in preview.js). Loaded by events.html only
// for those who see the new design (events_preview_script in
// include/event.rb), so that the page stays exactly as it was for everyone
// else. The server embeds what is coming and the last four weeks
// (stored_events); older events are loaded by school year
// (/api/get_events_archive) and then become part of stored_events, so that
// editing and deleting work as on today's page.
(function () {
    if (!document.body.classList.contains('ui-preview') || !window.pv_list) return;

    var loaded_years = {};      // school years fetched from the server
    var open_groups = {};       // groups the person opened (kept when drawn again)
    var pending_eid = null;     // /events#eid of an older event

    // /events#eid: the event may be older than the embedded part
    if (window.location.hash.length > 1) {
        var eid = window.location.hash.substr(1);
        if (!stored_events.some(function (e) { return e.eid === eid; })) {
            pending_eid = eid;
            history.replaceState(null, '', window.location.pathname + window.location.search);
        }
    }

    function add_events(events) {
        var known = {};
        stored_events.forEach(function (e) { known[e.eid] = true; });
        events.forEach(function (e) {
            if (!known[e.eid]) { stored_events.push(e); known[e.eid] = true; }
        });
    }

    function key(e) { return e.info.date + 'T' + e.info.start_time; }

    // "Mi, 18.11., 15:00 bis 16:00 Uhr" (with the year when it is not this one)
    function when(e) {
        var m = moment(e.info.date).locale('de');
        var day = m.format(m.year() === moment().year() ? 'dd, D.M.' : 'dd, D.M.YYYY');
        return day + ', ' + e.info.start_time + ' bis ' + e.info.end_time + ' Uhr';
    }

    function delete_by_id(eid) {
        api_call('/api/delete_event', { eid: eid }, function (data) {
            if (data.success) {
                stored_events = stored_events.filter(function (x) { return x.eid !== data.eid; });
                update_stored_events();
            }
        });
    }

    function render_event(e) {
        var title = e.info.title || '(ohne Titel)';
        // without participants the server lists [null] (as on today's page)
        var n = e.recipients.filter(function (r) { return !!r; }).length;
        var row = pv_list.row({
            title: title,
            cls: 'pv-event',
            facts: [when(e), n + ' Teilnehmer', e.info.jitsi ? 'mit Jitsi' : null],
            open: function () { edit_event(e); },
            actions: [
                { label: 'Bearbeiten', visible: true, cls: 'pv-bu-edit-event', run: function () { edit_event(e); } },
                {
                    label: 'Löschen', danger: true, cls: 'pv-bu-delete-event', run: function () {
                        pv_list.confirm_delete('Den Termin »' + title + '« löschen? Er verschwindet auch aus den Kalendern der Teilnehmer.',
                            function () { delete_by_id(e.eid); }, 'Termin löschen');
                    }
                },
            ],
        });
        row.setAttribute('data-eid', e.eid);
        return row;
    }

    function count(n) { return n + ' ' + (n === 1 ? 'Termin' : 'Termine'); }

    function fill(body, list, more, keep) {
        body.textContent = '';
        if (list.length === 0) {
            var p = document.createElement('p');
            p.className = 'pv-lempty';
            p.textContent = 'Keine Termine.';
            body.appendChild(p);
            return;
        }
        pv_list.blocks(body, list, render_event, { more: more, keep: keep });
    }

    function render() {
        var root = document.querySelector('.pv-events-list');
        root.textContent = '';
        var today = moment().format('YYYY-MM-DD');
        var from = pv_events_recent_from;
        var upcoming = stored_events.filter(function (e) { return e.info.date >= today; });
        upcoming.sort(function (a, b) { return key(a) < key(b) ? -1 : key(a) > key(b) ? 1 : 0; });
        var desc = function (a, b) { return key(a) < key(b) ? 1 : key(a) > key(b) ? -1 : 0; };
        var recent = stored_events.filter(function (e) { return e.info.date < today && e.info.date >= from; }).sort(desc);
        var older = {};
        stored_events.forEach(function (e) {
            if (e.info.date >= from) return;
            var y = pv_list.school_year(e.info.date);
            (older[y] = older[y] || []).push(e);
        });
        var archive = {};
        pv_events_archive.forEach(function (x) { archive[x.school_year] = x.count; });
        Object.keys(older).forEach(function (y) { if (!(y in archive)) archive[y] = older[y].length; });
        var years = Object.keys(archive).map(function (y) { return parseInt(y, 10); }).sort(function (a, b) { return b - a; });

        pv_list.group(root, {
            label: 'Anstehend', count: upcoming.length ? count(upcoming.length) : '', cls: 'pv-events-upcoming',
            render: function (body) {
                if (upcoming.length === 0) {
                    var p = document.createElement('p');
                    p.className = 'pv-lempty';
                    p.textContent = 'Keine anstehenden Termine. Mit »Neuer Termin« laden Sie zu einem ein.';
                    body.appendChild(p);
                    return;
                }
                pv_list.blocks(body, upcoming, render_event, { more: 'Weitere Termine laden', keep: 'upcoming' });
            },
        });
        if (recent.length > 0)
            pv_list.group(root, {
                label: 'Letzte vier Wochen', count: count(recent.length), cls: 'pv-events-recent',
                render: function (body) { fill(body, recent, 'Ältere Termine laden', 'recent'); },
            });
        years.forEach(function (y) {
            var list = (older[y] || []).sort(desc);
            var g = pv_list.group(root, {
                label: pv_list.school_year_label(y),
                count: count(loaded_years[y] ? list.length : archive[y]),
                folded: true, open: !!open_groups[y], cls: 'pv-events-year',
                on_toggle: function (open) { open_groups[y] = open; },
                render: function (body) {
                    if (loaded_years[y]) { fill(body, list, 'Ältere Termine laden', 'year:' + y); return; }
                    var p = document.createElement('p');
                    p.className = 'pv-lempty';
                    p.textContent = 'Wird geladen …';
                    body.appendChild(p);
                    api_call('/api/get_events_archive', { school_year: y }, function (data) {
                        if (!data.success) return;
                        add_events(data.events);
                        loaded_years[y] = true;
                        var mine = stored_events.filter(function (e) {
                            return e.info.date < from && pv_list.school_year(e.info.date) === y;
                        }).sort(desc);
                        fill(body, mine, 'Ältere Termine laden', 'year:' + y);
                        var c = g.section.querySelector('.pv-lgroup-count');
                        if (c) c.textContent = count(mine.length);
                    });
                },
            });
            g.section.setAttribute('data-school-year', String(y));
        });
    }

    // today's table stays in the page, hidden; the list takes its place
    function setup() {
        if (document.querySelector('.pv-events-list')) return;
        var container = document.querySelector('#main_container > .container');
        var table = container.querySelector('.events-container');
        table.hidden = true;
        var list = document.createElement('div');
        list.className = 'pv-events-list';
        table.parentNode.insertBefore(list, table.nextSibling);
        pv_list.page(container, { main: container.querySelector('.bu-new-event') });
    }

    var first = true;
    update_stored_events = function () {
        setup();
        render();
        // the first drawing happens once the recipients are known: now an
        // older event from /events#eid can be opened
        if (first && pending_eid) {
            var eid = pending_eid;
            pending_eid = null;
            api_call('/api/get_events_archive', { eid: eid }, function (data) {
                if (!data.success || data.events.length === 0) return;
                add_events(data.events);
                render();
                stored_events.forEach(function (e) { if (e.eid === eid) edit_event(e); });
            });
        }
        first = false;
    };

    document.addEventListener('DOMContentLoaded', setup);
})();
