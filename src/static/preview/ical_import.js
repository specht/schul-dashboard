// Neues Design: »Kalender einbinden« on the profile page (include/ical_import.rb,
// ical_import.rb). Only there for people with the role can_import_ical. The
// address of the calendar is a secret: once stored, the page only shows its
// host; to change it one enters a new one.
// Runs once the page is loaded: api_call (code.js) comes after the content.
document.addEventListener('DOMContentLoaded', function () {
    if (!document.body.classList.contains('ui-preview')) return;
    var box = document.getElementById('ical_import');
    if (!box) return;
    var state_el = box.querySelector('.pv-icim-state');
    var input = document.getElementById('ti_ical_import_url');
    var save = document.getElementById('bu_ical_import_save');
    var remove = document.getElementById('bu_ical_import_delete');
    var polls = 0, poll_timer = null;

    function when(ts) {
        var d = new Date(ts * 1000), now = new Date();
        var hm = d.getHours() + ':' + (d.getMinutes() < 10 ? '0' : '') + d.getMinutes() + ' Uhr';
        if (d.toDateString() === now.toDateString()) return 'heute, ' + hm;
        return d.getDate() + '.' + (d.getMonth() + 1) + '., ' + hm;
    }

    function line(icon, text, cls) {
        var p = document.createElement('p');
        p.className = 'pv-icim-line' + (cls ? ' ' + cls : '');
        var i = document.createElement('i');
        i.className = 'ti ti-' + icon;
        i.setAttribute('aria-hidden', 'true');
        p.appendChild(i);
        var span = document.createElement('span');
        span.textContent = text;
        p.appendChild(span);
        state_el.appendChild(p);
    }

    function show(s) {
        state_el.textContent = '';
        remove.hidden = !s.active;
        save.textContent = s.active ? 'Ersetzen' : 'Einbinden';
        input.placeholder = s.active ? 'Neue Adresse, um den Kalender zu ersetzen' : 'https://…/kalender.ics';
        if (!s.active) return;
        line('calendar', 'Eingebunden: Kalender von ' + (s.host || 'unbekannt'));
        var waiting = !s.ok_at && !s.error;
        if (s.error) {
            line('alert-triangle', s.error + (s.ok_at ? ' Es bleiben die Termine vom ' + when(s.ok_at) + '.' : ''), 'pv-icim-error');
        } else if (s.ok_at) {
            var n = s.count || 0;
            line('check', (n === 1 ? '1 Termin' : n + ' Termine') + ', zuletzt geholt ' + when(s.ok_at) + '.');
        } else {
            line('clock', 'Wird geholt …');
        }
        if (s.recurring) {
            line('info-circle', (s.recurring === 1 ? 'Eine Terminserie wird' : s.recurring + ' Terminserien werden') + ' noch nicht übernommen.', 'pv-icim-muted');
        }
        // right after saving: ask again until the first fetch is done
        clearTimeout(poll_timer);
        if (waiting && polls < 20) {
            polls++;
            poll_timer = setTimeout(load, 1500);
        }
    }

    function load() {
        api_call('/api/ical_import_state', {}, function (data) { if (data.success) show(data); });
    }

    save.addEventListener('click', function () {
        var url = input.value.trim();
        if (!url) { input.focus(); return; }
        api_call('/api/ical_import_set', { url: url }, function (data) {
            if (!data.success) return;
            input.value = '';
            polls = 0;
            show(data);
        });
    });
    input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') { e.preventDefault(); save.click(); }
    });
    remove.addEventListener('click', function () {
        dashboardConfirm('Die Termine dieses Kalenders verschwinden aus deinem Stundenplan.', function () {
            api_call('/api/ical_import_delete', {}, function (data) { if (data.success) show(data); });
        }, { title: 'Kalender entfernen?', confirm: 'Entfernen', danger: true });
    });
    load();
});
