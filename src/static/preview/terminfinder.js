// Neues Design: Terminfinder (/terminfinder, include/terminfinder.rb). A
// teacher adds people, classes, groups (the same list as for Termine,
// recipients.json) or rooms and sees, day by day, when all of them are free
// for the chosen duration. Only lessons count (with substitutions and
// cancellations). Two views: »Freie Zeiten« (one bar per day, busy times
// only) and »Stundenpläne« (the week as in the timetable, one column per
// person, class or room side by side, the common free times between them).
// A time opens a dialog; »Termin anlegen«
// carries date, time and participants to /events (preview/events.js) through
// sessionStorage, not the address, so that no names end up in a URL.
(function () {
    if (!document.body.classList.contains('ui-preview')) return;

    var WD = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
    var WEEKDAYS = ['Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag'];
    var MONTHS_SHORT = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'];
    var DAY_END = 18 * 60;          // suggestions end at 18 Uhr
    var DAY_START = 8 * 60;         // … and start with the first lesson, at the latest 8 Uhr
    var MAX_PEOPLE = 150;           // TERMINFINDER_MAX_PEOPLE
    var MAX_RESULTS = 8;
    var MAX_TIMETABLES = 10;        // TERMINFINDER_MAX_TIMETABLES
    var STORE_DURATION = 'pv_tf_duration';
    var STORE_VIEW = 'pv_tf_view';
    var DRAFT = 'pv_terminfinder';  // read by preview/events.js
    // groups that make no sense here (parents have no timetable, the whole
    // student body is more than one can ask)
    var SKIP = /^(eltern\.|\/eltern\/|\/ev\/|\/schueler\/\*)/;
    var PHONE = window.matchMedia('(max-width: 767px)');

    var chosen = [];                // recipient keys in the order added
    var duration = 60;
    var monday = null;              // the shown week
    var cache = {};                 // week + people -> answer of the server
    var answer = null;              // the shown answer
    var request_no = 0;
    var view = 'free';              // 'free' or 'grid'
    var tt_cache = {};              // week + keys -> lessons of the timetables
    var tt_answer = null;           // the shown lessons
    var tt_key = null;              // … for this week + keys
    var tt_request_no = 0;
    var phone_day = null;           // the day shown on phones (grid), 0–4
    var ui = {};

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    }
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    function ymd(d) { return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()); }
    function minutes(hhmm) { var p = hhmm.split(':'); return parseInt(p[0], 10) * 60 + parseInt(p[1], 10); }
    function hhmm(m) { return Math.floor(m / 60) + ':' + pad(m % 60); }
    function hhmm0(m) { return pad(Math.floor(m / 60)) + ':' + pad(m % 60); }
    function iso_week(d) {
        var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
        var day = t.getUTCDay() || 7;
        t.setUTCDate(t.getUTCDate() + 4 - day);
        var y = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
        return { year: t.getUTCFullYear(), week: Math.ceil(((t - y) / 86400000 + 1) / 7) };
    }
    function week_key(d) { var w = iso_week(d); return w.year + '-' + pad(w.week); }
    function monday_of(d) {
        var m = new Date(d);
        m.setHours(0, 0, 0, 0);
        m.setDate(m.getDate() - ((m.getDay() + 6) % 7));
        return m;
    }
    // this week, from Saturday on the next one
    function this_week() {
        var now = new Date();
        var m = monday_of(now);
        if (now.getDay() === 6 || now.getDay() === 0) m.setDate(m.getDate() + 7);
        return m;
    }
    function week_label(m) {
        var fri = new Date(m);
        fri.setDate(fri.getDate() + 4);
        return m.getMonth() === fri.getMonth()
            ? m.getDate() + '.–' + fri.getDate() + '. ' + MONTHS_SHORT[fri.getMonth()]
            : m.getDate() + '. ' + MONTHS_SHORT[m.getMonth()] + ' – ' + fri.getDate() + '. ' + MONTHS_SHORT[fri.getMonth()];
    }
    function duration_text(m) {
        if (m < 60) return m + ' Min.';
        var h = Math.floor(m / 60), r = m % 60;
        if (r === 30) return h + '½ Std.';
        if (r === 0) return h + ' Std.';
        return h + ' Std. ' + r + ' Min.';
    }
    function label_of(key) { return ((window.recipients || {})[key] || {}).label || key; }
    function people_text(n) { return n === 1 ? '1 Person' : n + ' Personen'; }
    function rooms_text(n) { return n === 1 ? '1 Raum' : n + ' Räume'; }
    function is_room(key) { return key.charAt(0) === '@'; }
    // a column's name in the grid: the room, the class, a person's last name
    function short_of(key) {
        if (is_room(key)) return key.slice(1);
        var k = /^\/klasse\/(.+)$/.exec(key);
        if (k) return k[1];
        var label = label_of(key).replace(/\s*\(.*\)\s*$/, '');
        if ((window.recipients[key] || {}).entries) return label;
        var words = label.split(/\s+/);
        return words[words.length - 1];
    }

    // ---------- who ----------

    function usable(key) {
        var r = window.recipients[key];
        return r && !r.external && !SKIP.test(key);
    }
    function members(key) {
        var r = window.recipients[key] || {};
        var list = r.entries ? r.entries : [key];
        return list.filter(function (email) { return !/^eltern\./.test(email); });
    }
    function emails() {
        var seen = {}, list = [];
        chosen.forEach(function (key) {
            members(key).forEach(function (email) {
                if (!seen[email]) { seen[email] = true; list.push(email); }
            });
        });
        return list;
    }

    function search(text) {
        var terms = text.trim().toLowerCase().split(/\s+/).filter(Boolean);
        if (!terms.length) return [];
        var found = [];
        Object.keys(window.recipients).forEach(function (key) {
            if (!usable(key) || chosen.indexOf(key) >= 0) return;
            var label = label_of(key).toLowerCase();
            var words = label.split(/[\s()\-,.]+/);
            var all = terms.every(function (t) { return words.some(function (w) { return w.indexOf(t) === 0; }); });
            if (!all) return;
            var r = window.recipients[key];
            // people first (teachers before students), then groups; the label's
            // start before a later word
            var rank = (label.indexOf(terms[0]) === 0 ? 0 : 4) + (r.entries ? 2 : (r.room ? 3 : (r.teacher ? 0 : 1)));
            found.push({ key: key, rank: rank, label: label_of(key) });
        });
        found.sort(function (a, b) { return a.rank - b.rank || a.label.localeCompare(b.label, 'de'); });
        return found.slice(0, MAX_RESULTS);
    }

    var active = -1;
    function show_results() {
        var list = search(ui.search.value);
        ui.results.textContent = '';
        active = list.length ? 0 : -1;
        list.forEach(function (item, i) {
            var r = window.recipients[item.key];
            var b = el('button', 'pv-tf-result');
            b.type = 'button';
            b.setAttribute('role', 'option');
            b.dataset.key = item.key;
            b.appendChild(el('span', 'pv-tf-result-name', item.label));
            var sub = r.entries ? 'Gruppe, ' + people_text(members(item.key).length) : (r.room ? 'Raum' : (r.teacher ? 'Lehrkraft' : 'Schülerin oder Schüler'));
            b.appendChild(el('span', 'pv-tf-result-sub', sub));
            b.addEventListener('mousedown', function (e) { e.preventDefault(); });
            b.addEventListener('click', function (e) { add(e.currentTarget.dataset.key); });
            ui.results.appendChild(b);
        });
        if (ui.search.value.trim() && !list.length) ui.results.appendChild(el('div', 'pv-tf-result-none', 'Niemand gefunden.'));
        var open = !!ui.search.value.trim();
        ui.results.hidden = !open;
        ui.search.setAttribute('aria-expanded', open ? 'true' : 'false');
        mark_active();
    }
    function mark_active() {
        Array.prototype.forEach.call(ui.results.querySelectorAll('.pv-tf-result'), function (b, i) {
            b.classList.toggle('active', i === active);
            b.setAttribute('aria-selected', i === active ? 'true' : 'false');
        });
    }
    function close_results() {
        ui.results.hidden = true;
        ui.search.setAttribute('aria-expanded', 'false');
    }

    function add(key) {
        if (chosen.indexOf(key) < 0) chosen.push(key);
        ui.search.value = '';
        close_results();
        ui.search.focus();
        changed();
    }
    function remove(key) {
        chosen = chosen.filter(function (k) { return k !== key; });
        changed();
    }

    function render_chips() {
        ui.chips.textContent = '';
        chosen.forEach(function (key) {
            var r = window.recipients[key] || {};
            var chip = el('span', 'pv-tf-chip');
            var text = key === pv_tf_me.email ? label_of(key) + ' (du)' : label_of(key);
            if (r.entries) text += ' (' + members(key).length + ')';
            chip.appendChild(el('span', 'pv-tf-chip-label', text));
            var x = el('button', 'pv-tf-chip-remove');
            x.type = 'button';
            x.setAttribute('aria-label', label_of(key) + ' entfernen');
            x.appendChild(el('i', 'ti ti-x'));
            x.firstChild.setAttribute('aria-hidden', 'true');
            x.addEventListener('click', function () { remove(key); });
            chip.appendChild(x);
            ui.chips.appendChild(chip);
        });
    }

    function render_facts() {
        var list = emails();
        var parts = [];
        var rooms = list.filter(is_room).length;
        if (list.length - rooms) parts.push(people_text(list.length - rooms));
        if (rooms) parts.push(rooms_text(rooms));
        if (answer && answer.missing.length) {
            var names = answer.missing.map(function (e) { return label_of(e); });
            var shown = names.slice(0, 3).join(', ') + (names.length > 3 ? ' und ' + (names.length - 3) + ' weitere' : '');
            parts.push('ohne Stundenplan: ' + shown);
        }
        ui.facts.textContent = parts.join(', ');
        ui.facts.hidden = !parts.length;
    }

    // ---------- the week ----------

    function render_head() {
        var w = iso_week(monday);
        ui.label.textContent = week_label(monday);
        ui.sub.textContent = 'Kalenderwoche ' + w.week;
        ui.today.disabled = ymd(monday) === ymd(this_week());
    }

    function load() {
        var list = emails();
        render_facts();
        if (!list.length) { answer = null; render_days(); return; }
        if (list.length > MAX_PEOPLE) {
            answer = null;
            render_days('Das sind ' + list.length + ' Personen. Der Terminfinder vergleicht höchstens ' + MAX_PEOPLE + '.');
            return;
        }
        var week = week_key(monday);
        var key = week + '/' + list.slice().sort().join(',');
        if (cache[key]) { answer = cache[key]; render_facts(); render_days(); return; }
        var no = ++request_no;
        ui.days.classList.add('pv-tf-loading');
        api_call('/api/terminfinder_week', { week: week, emails: list }, function (data) {
            if (no !== request_no) return;
            ui.days.classList.remove('pv-tf-loading');
            if (!data.success) return;
            cache[key] = data;
            answer = data;
            render_facts();
            render_days();
        });
    }

    // ---------- the timetables side by side (grid) ----------

    // one column per chip: a person, a class (5–10) or a room with its own
    // timetable; other groups (and 11, 12) as how many of them are busy
    function lanes() {
        return chosen.slice(0, MAX_TIMETABLES).map(function (key) {
            var r = window.recipients[key] || {};
            var k = /^\/klasse\/(.+)$/.exec(key);
            var own = r.room || !r.entries || (k && (window.pv_tf_klassen || []).indexOf(k[1]) >= 0);
            return { key: key, timetable: !!own };
        });
    }
    function lanes_key() {
        return week_key(monday) + '/' + lanes().filter(function (l) { return l.timetable; }).map(function (l) { return l.key; }).join(',');
    }
    function load_timetables() {
        var keys = lanes().filter(function (l) { return l.timetable; }).map(function (l) { return l.key; });
        var ck = lanes_key();
        if (!keys.length) { tt_answer = { timetables: {} }; tt_key = ck; render_days(); return; }
        if (tt_cache[ck]) { tt_answer = tt_cache[ck]; tt_key = ck; render_days(); return; }
        var no = ++tt_request_no;
        ui.days.classList.add('pv-tf-loading');
        api_call('/api/terminfinder_timetables', { week: week_key(monday), keys: keys }, function (data) {
            if (no !== tt_request_no) return;
            ui.days.classList.remove('pv-tf-loading');
            if (!data.success) return;
            tt_cache[ck] = data;
            tt_answer = data;
            tt_key = ck;
            render_days();
        });
    }

    function render_grid(start, today, now_min) {
        if (!tt_answer || tt_key !== lanes_key()) { load_timetables(); return; }
        var shown = lanes();
        var span = DAY_END - start;
        var pct = function (m) { return ((m - start) / span * 100) + '%'; };
        if (chosen.length > MAX_TIMETABLES) {
            ui.days.appendChild(el('p', 'pv-tf-empty', 'Nebeneinander zeigt der Terminfinder höchstens ' + MAX_TIMETABLES + ' Stundenpläne, hier die ersten ' + MAX_TIMETABLES + '.'));
        }
        var days = [];
        for (var i = 0; i < 5; i++) {
            var d = new Date(monday);
            d.setDate(d.getDate() + i);
            days.push(d);
        }
        // phones: one day, chosen above
        var one = PHONE.matches;
        if (one) {
            if (phone_day === null) {
                phone_day = 0;
                days.forEach(function (d, i) { if (ymd(d) === today) phone_day = i; });
            }
            var tabs = el('div', 'pv-tf-durations pv-tf-daytabs');
            tabs.setAttribute('role', 'radiogroup');
            tabs.setAttribute('aria-label', 'Tag');
            days.forEach(function (d, i) {
                var b = el('button', 'btn pv-tf-view pv-tf-daytab' + (i === phone_day ? ' active' : ''));
                b.type = 'button';
                b.setAttribute('role', 'radio');
                b.setAttribute('aria-checked', i === phone_day ? 'true' : 'false');
                b.appendChild(el('span', 'pv-weekday', WD[d.getDay()]));
                b.appendChild(el('span', 'pv-tf-daytab-date', d.getDate() + '.'));
                b.addEventListener('click', function () { phone_day = i; render_days(); });
                tabs.appendChild(b);
            });
            ui.days.appendChild(tabs);
            days = [days[phone_day]];
        }
        var grid = el('div', 'pv-tf-grid' + (one ? ' pv-tf-grid-one' : ''));
        grid.style.setProperty('--pv-tf-days', String(days.length));
        grid.style.setProperty('--pv-tf-lanes', String(shown.length));
        grid.style.setProperty('--pv-tf-height', Math.round(span * (one ? 1.0 : 0.8)) + 'px');

        // the heads: day, note, the columns' names
        grid.appendChild(el('div', 'pv-tf-grid-corner'));
        days.forEach(function (d) {
            var date = ymd(d);
            var head = el('div', 'pv-tf-grid-head' + (date < today ? ' pv-tf-grid-past-head' : ''));
            var line = el('div', 'pv-tf-grid-day-name');
            line.appendChild(el('span', 'pv-weekday', WD[d.getDay()]));
            line.appendChild(el('span', 'pv-tf-date', d.getDate() + '.' + (d.getMonth() + 1) + '.'));
            head.appendChild(line);
            var note = day_note(date);
            if (note) head.appendChild(el('div', 'pv-tf-note', note.title));
            var names = el('div', 'pv-tf-lane-names');
            shown.forEach(function (l) {
                var n = el('span', 'pv-tf-lane-name', short_of(l.key));
                n.title = label_of(l.key);
                names.appendChild(n);
            });
            head.appendChild(names);
            grid.appendChild(head);
        });

        // the hours
        var axis = el('div', 'pv-tf-grid-axis');
        axis.setAttribute('aria-hidden', 'true');
        for (var h = Math.ceil(start / 60); h < DAY_END / 60; h++) {
            var t = el('span', 'pv-tf-grid-hour', h + ':00');
            t.style.top = pct(h * 60);
            axis.appendChild(t);
        }
        grid.appendChild(axis);

        days.forEach(function (d) {
            var date = ymd(d);
            var col = el('div', 'pv-tf-grid-day');
            col.dataset.date = date;
            for (var h = Math.ceil(start / 60); h < DAY_END / 60; h++) {
                var line = el('span', 'pv-tf-grid-line');
                line.style.top = pct(h * 60);
                col.appendChild(line);
            }
            var note = day_note(date);
            if (note && note.kind === 'holiday') {
                col.classList.add('pv-tf-grid-holiday');
                col.appendChild(el('span', 'pv-tf-none', 'Kein Schultag.'));
                grid.appendChild(col);
                return;
            }
            // what is over
            var over = date < today ? DAY_END : (date === today ? Math.min(DAY_END, Math.max(start, now_min)) : start);
            if (over > start) {
                var past = el('span', 'pv-tf-grid-over');
                past.style.top = '0';
                past.style.height = pct(over);
                col.appendChild(past);
            }
            // the common free times, under the columns
            var from = Math.max(start, Math.ceil(over / 5) * 5);
            if (from < DAY_END) {
                windows(stretches(busy_of(date), from, DAY_END), null).forEach(function (w) {
                    var b = el('button', 'pv-tf-grid-free');
                    b.type = 'button';
                    b.style.top = pct(w.from);
                    b.style.height = 'calc(' + pct(w.to) + ' - ' + pct(w.from) + ')';
                    b.setAttribute('aria-label', 'Alle frei von ' + hhmm(w.from) + ' bis ' + hhmm(w.to) + ' Uhr');
                    b.appendChild(el('span', 'pv-tf-grid-free-time', hhmm(w.from) + '–' + hhmm(w.to)));
                    b.addEventListener('click', function () { open_slot(date, w, null); });
                    col.appendChild(b);
                });
            }
            var cols = el('div', 'pv-tf-lanes');
            shown.forEach(function (l, i) {
                var lane = el('div', 'pv-tf-lane');
                lane.dataset.key = l.key;
                if (l.timetable) {
                    var list = (tt_answer.timetables || {})[l.key];
                    if (list === null || list === undefined) lane.classList.add('pv-tf-lane-none');
                    (list || []).forEach(function (x) {
                        if (x.date !== date) return;
                        lane.appendChild(lesson_block(x, pct, l.key));
                    });
                } else {
                    // a group: how many of them are busy
                    var who = members(l.key).filter(function (e) { return answer.people[e]; });
                    var busy = [];
                    who.forEach(function (email) {
                        (answer.people[email][date] || []).forEach(function (p) {
                            busy.push({ email: email, from: minutes(p[0]), to: minutes(p[1]) });
                        });
                    });
                    stretches(busy, start, DAY_END).forEach(function (p) {
                        if (!p.busy.length) return;
                        var seg = el('span', 'pv-tf-group-busy');
                        seg.style.top = pct(p.from);
                        seg.style.height = 'calc(' + pct(p.to) + ' - ' + pct(p.from) + ')';
                        seg.style.setProperty('--share', String(Math.max(0.25, p.busy.length / Math.max(1, who.length))));
                        seg.title = label_of(l.key) + ': ' + p.busy.length + ' von ' + who.length + ' belegt, ' + hhmm(p.from) + ' bis ' + hhmm(p.to);
                        lane.appendChild(seg);
                    });
                }
                cols.appendChild(lane);
            });
            col.appendChild(cols);
            grid.appendChild(col);
        });
        var scroll = el('div', 'pv-tf-grid-scroll');
        scroll.appendChild(grid);
        ui.days.appendChild(scroll);
    }

    // a lesson in its subject's colour (as in the timetable), cancelled ones
    // quiet and crossed out, break duties hatched
    function lesson_block(x, pct, key) {
        var from = minutes(x.from), to = minutes(x.to);
        var b = el('div', 'pv-tf-lesson');
        b.style.top = pct(from);
        b.style.height = 'calc(' + pct(to) + ' - ' + pct(from) + ')';
        var code = (x.label.split(/[\s_\-(]/)[0] || '').toLowerCase().replace(/[^a-z0-9]/g, '');
        if (x.off) b.classList.add('pv-tf-lesson-off');
        else if (x.duty) b.classList.add('pv-tf-lesson-duty');
        else if (code) {
            b.style.setProperty('--pv-tf-bg', 'var(--subj-' + code + ', var(--acc))');
            b.style.setProperty('--pv-tf-ink', 'var(--subj-' + code + '-ink, var(--acc-ink))');
        }
        if (x.changed) b.classList.add('pv-tf-lesson-changed');
        // narrow columns: the subject first, then the room (a room's own
        // column: who is in it); everything in the tooltip
        var first = x.duty ? 'Aufsicht' : (x.label.split(/[\s(]/)[0] || x.label);
        var second = x.room || x.label.slice(first.length).replace(/[()]/g, ' ').trim();
        b.appendChild(el('span', 'pv-tf-lesson-label', first));
        if (second) b.appendChild(el('span', 'pv-tf-lesson-room', second));
        var what = [label_of(key) + ':', x.duty ? 'Aufsicht' : x.label];
        if (x.room) what.push('(' + x.room + ')');
        what.push(hhmm(from) + ' bis ' + hhmm(to));
        if (x.off) what.push('– fällt aus');
        else if (x.changed) what.push('– Vertretung oder Änderung');
        b.title = what.join(' ');
        return b;
    }

    // the day's busy times per person, in minutes
    function busy_of(date) {
        var result = [];
        Object.keys(answer.people).forEach(function (email) {
            (answer.people[email][date] || []).forEach(function (p) {
                result.push({ email: email, from: minutes(p[0]), to: minutes(p[1]) });
            });
        });
        return result;
    }

    // stretches of the day with the same busy people: [{from, to, busy: [emails]}]
    function stretches(busy, from, to) {
        var cuts = [from, to];
        busy.forEach(function (b) {
            if (b.from > from && b.from < to) cuts.push(b.from);
            if (b.to > from && b.to < to) cuts.push(b.to);
        });
        cuts = cuts.sort(function (a, b) { return a - b; }).filter(function (c, i, a) { return i === 0 || c !== a[i - 1]; });
        var list = [];
        for (var i = 0; i + 1 < cuts.length; i++) {
            var a = cuts[i], b = cuts[i + 1];
            var who = {};
            busy.forEach(function (x) { if (x.from < b && x.to > a) who[x.email] = true; });
            list.push({ from: a, to: b, busy: Object.keys(who) });
        }
        return list;
    }

    // windows of at least `duration` in which nobody except `allowed` is
    // busy (allowed: one email, or null for everyone free)
    function windows(parts, allowed) {
        var list = [], cur = null;
        parts.forEach(function (p) {
            var ok = p.busy.length === 0 || (allowed && p.busy.length === 1 && p.busy[0] === allowed);
            if (ok) {
                if (cur && cur.to === p.from) cur.to = p.to;
                else { cur = { from: p.from, to: p.to }; list.push(cur); }
            } else cur = null;
        });
        return list.filter(function (w) { return w.to - w.from >= duration; });
    }

    function day_note(date) {
        var note = null;
        (answer ? answer.days : []).forEach(function (d) {
            if (date >= d.from && date < d.to && (!note || d.kind === 'holiday')) note = d;
        });
        return note;
    }

    function day_start() {
        var first = DAY_START;
        if (answer) Object.keys(answer.people).forEach(function (email) {
            Object.keys(answer.people[email]).forEach(function (date) {
                answer.people[email][date].forEach(function (p) { first = Math.min(first, minutes(p[0])); });
            });
        });
        return Math.max(7 * 60, Math.floor(first / 15) * 15);
    }

    function render_days(message) {
        ui.days.textContent = '';
        render_head();
        if (message || !answer) {
            ui.days.appendChild(el('p', 'pv-tf-empty', message || 'Füge oben Personen, Klassen oder Gruppen hinzu. Dann erscheinen hier die Zeiten, in denen alle frei sind.'));
            return;
        }
        var start = day_start();
        var total = Object.keys(answer.people).length;
        var now = new Date();
        var today = ymd(now);
        var now_min = now.getHours() * 60 + now.getMinutes();
        if (view === 'grid') { render_grid(start, today, now_min); return; }
        var scale = el('div', 'pv-tf-scale');
        scale.setAttribute('aria-hidden', 'true');
        for (var h = Math.ceil(start / 60); h <= DAY_END / 60; h += 2) {
            var tick = el('span', 'pv-tf-tick', String(h));
            tick.style.left = ((h * 60 - start) / (DAY_END - start) * 100) + '%';
            scale.appendChild(tick);
        }
        ui.days.appendChild(scale);
        for (var i = 0; i < 5; i++) {
            var d = new Date(monday);
            d.setDate(d.getDate() + i);
            ui.days.appendChild(render_day(d, start, total, today, now_min));
        }
    }

    function render_day(d, start, total, today, now_min) {
        var date = ymd(d);
        var row = el('div', 'pv-tf-day');
        row.dataset.date = date;
        var head = el('div', 'pv-tf-day-head');
        head.appendChild(el('span', 'pv-weekday', WD[d.getDay()]));
        head.appendChild(el('span', 'pv-tf-date', d.getDate() + '.' + (d.getMonth() + 1) + '.'));
        var note = day_note(date);
        var past = date < today;
        var from = start;
        if (date === today) from = Math.max(start, Math.ceil(now_min / 5) * 5);
        if (past || from >= DAY_END) {
            // over: one quiet line
            row.classList.add('pv-tf-past');
            head.appendChild(el('span', 'pv-tf-note', 'vorbei'));
            row.appendChild(head);
            return row;
        }
        if (note) head.appendChild(el('span', 'pv-tf-note', note.title));
        row.appendChild(head);
        var holiday = note && note.kind === 'holiday';

        var parts = stretches(busy_of(date), start, DAY_END);
        var bar = el('div', 'pv-tf-bar');
        bar.setAttribute('aria-hidden', 'true');
        if (!holiday) parts.forEach(function (p) {
            var seg = el('span', p.busy.length ? 'pv-tf-busy' : 'pv-tf-free');
            seg.style.left = ((p.from - start) / (DAY_END - start) * 100) + '%';
            seg.style.width = ((p.to - p.from) / (DAY_END - start) * 100) + '%';
            if (p.busy.length) seg.style.setProperty('--share', String(Math.max(0.25, p.busy.length / total)));
            bar.appendChild(seg);
        });
        row.appendChild(bar);

        var slots = el('div', 'pv-tf-slots');
        if (holiday) {
            slots.appendChild(el('span', 'pv-tf-none', 'Kein Schultag.'));
        } else {
            var clipped = stretches(busy_of(date), from, DAY_END);
            var all = windows(clipped, null);
            all.forEach(function (w) { slots.appendChild(slot_button(date, w, null)); });
            if (!all.length) {
                // nobody can always: where all but one are free
                var near = [];
                if (total >= 3) {
                    Object.keys(answer.people).forEach(function (email) {
                        windows(clipped, email).forEach(function (w) { near.push({ w: w, email: email }); });
                    });
                }
                near.sort(function (a, b) { return (b.w.to - b.w.from) - (a.w.to - a.w.from) || a.w.from - b.w.from; });
                slots.appendChild(el('span', 'pv-tf-none', 'Keine gemeinsame Zeit von ' + duration_text(duration) + '.'));
                near.slice(0, 3).sort(function (a, b) { return a.w.from - b.w.from; }).forEach(function (n) {
                    slots.appendChild(slot_button(date, n.w, n.email));
                });
            }
        }
        row.appendChild(slots);
        return row;
    }

    function slot_button(date, w, except) {
        var b = el('button', 'btn pv-tf-slot' + (except ? ' pv-tf-slot-near' : ''));
        b.type = 'button';
        b.appendChild(el('span', 'pv-tf-slot-time', hhmm(w.from) + ' bis ' + hhmm(w.to)));
        if (except) b.appendChild(el('span', 'pv-tf-slot-except', 'ohne ' + label_of(except)));
        b.addEventListener('click', function () { open_slot(date, w, except); });
        return b;
    }

    // ---------- a time ----------

    var slot = null;
    function open_slot(date, w, except) {
        slot = { date: date, w: w, except: except };
        var d = new Date(date + 'T12:00:00');
        document.getElementById('lb_tf_slot_title').textContent = WEEKDAYS[d.getDay()] + ', ' + d.getDate() + '.' + (d.getMonth() + 1) + '.';
        var n = Object.keys(answer.people).length;
        var who = except
            ? 'Frei von ' + hhmm(w.from) + ' bis ' + hhmm(w.to) + ' Uhr: alle außer ' + label_of(except) + '.'
            : 'Frei von ' + hhmm(w.from) + ' bis ' + hhmm(w.to) + ' Uhr: ' + (n === 1 ? 'eine Person.' : 'alle ' + n + '.');
        document.querySelector('.pv-tf-slot-who').textContent = who;
        var select = document.getElementById('ti_tf_slot_start');
        select.textContent = '';
        for (var m = w.from; m + duration <= w.to; m += (m % 15 ? 15 - m % 15 : 15)) {
            var o = el('option', '', hhmm(m) + ' Uhr');
            o.value = String(m);
            select.appendChild(o);
        }
        update_end();
        var create = document.getElementById('bu_tf_create_event');
        create.hidden = !pv_tf_can_create_events;
        $('#tfSlotModal').modal('show');
    }
    function update_end() {
        var m = parseInt(document.getElementById('ti_tf_slot_start').value, 10);
        document.querySelector('.pv-tf-slot-end').textContent = 'bis ' + hhmm(m + duration) + ' Uhr';
    }
    function create_event() {
        if (!slot) return;
        var m = parseInt(document.getElementById('ti_tf_slot_start').value, 10);
        var draft = {
            date: slot.date,
            start: hhmm0(m),
            end: hhmm0(m + duration),
            recipients: chosen.filter(function (k) { return k !== pv_tf_me.email && !is_room(k); }),
        };
        try { sessionStorage.setItem(DRAFT, JSON.stringify(draft)); } catch (e) {}
        window.location.href = '/events';
    }

    // ---------- swiping the week (phones) ----------

    function install_swipe() {
        var box = ui.days;
        box.style.touchAction = 'pan-y pinch-zoom';
        var start = null, dragging = false;
        var place = function (x, ms) {
            box.style.transition = ms ? 'transform ' + ms + 'ms ease-out, opacity ' + ms + 'ms ease-out' : 'none';
            box.style.transform = x ? 'translateX(' + x + 'px)' : '';
            box.style.opacity = x ? String(Math.max(0.4, 1 - Math.abs(x) / box.offsetWidth)) : '';
        };
        box.addEventListener('touchstart', function (e) {
            start = (e.touches.length === 1 && PHONE.matches) ? { x: e.touches[0].clientX, y: e.touches[0].clientY, t: Date.now() } : null;
            // the system's back gesture starts at the screen edge
            if (start && (start.x < 24 || start.x > window.innerWidth - 24)) start = null;
            dragging = false;
        }, { passive: true });
        box.addEventListener('touchmove', function (e) {
            if (!start || e.touches.length !== 1) return;
            var dx = e.touches[0].clientX - start.x, dy = e.touches[0].clientY - start.y;
            if (!dragging) {
                if (Math.abs(dy) > 10 && Math.abs(dy) > Math.abs(dx)) { start = null; return; }
                if (Math.abs(dx) < 10) return;
                dragging = true;
            }
            place(dx, 0);
        }, { passive: true });
        box.addEventListener('touchend', function (e) {
            if (!start) return;
            var s0 = start;
            start = null;
            if (!dragging) return;
            dragging = false;
            var dx = (e.changedTouches[0] || {}).clientX - s0.x;
            var quick = Date.now() - s0.t < 250 && Math.abs(dx) > 40;
            if (!(Math.abs(dx) > box.offsetWidth * 0.25 || quick)) { place(0, 150); return; }
            var dir = dx < 0 ? 1 : -1;
            place(-dir * box.offsetWidth, 140);
            setTimeout(function () {
                go(dir);
                place(dir * box.offsetWidth * 0.5, 0);
                requestAnimationFrame(function () { place(0, 160); });
            }, 140);
        });
        box.addEventListener('touchcancel', function () { if (start) { start = null; dragging = false; place(0, 150); } });
    }

    function go(dir) {
        monday.setDate(monday.getDate() + 7 * dir);
        load();
    }

    function changed() {
        render_chips();
        load();
    }

    function set_view(v) {
        view = v === 'grid' ? 'grid' : 'free';
        try { localStorage.setItem(STORE_VIEW, view); } catch (e) {}
        Array.prototype.forEach.call(document.querySelectorAll('.pv-tf-views .pv-tf-view'), function (b) {
            var on = b.dataset.view === view;
            b.classList.toggle('active', on);
            b.setAttribute('aria-checked', on ? 'true' : 'false');
        });
        if (answer) render_days();
    }

    function set_duration(m) {
        duration = m;
        try { localStorage.setItem(STORE_DURATION, String(m)); } catch (e) {}
        Array.prototype.forEach.call(document.querySelectorAll('.pv-tf-duration'), function (b) {
            var on = parseInt(b.dataset.minutes, 10) === m;
            b.classList.toggle('active', on);
            b.setAttribute('aria-checked', on ? 'true' : 'false');
        });
        if (answer) render_days();
    }

    function setup() {
        var container = document.querySelector('.pv-tf');
        if (!container) return;
        if (window.pv_list) pv_list.page(container);
        ui.search = document.getElementById('ti_tf_search');
        ui.results = document.getElementById('tf_results');
        ui.chips = container.querySelector('.pv-tf-chips');
        ui.facts = container.querySelector('.pv-tf-facts');
        ui.days = container.querySelector('.pv-tf-days');
        ui.label = container.querySelector('.pv-tf-week-label');
        ui.sub = container.querySelector('.pv-tf-week-sub');
        ui.today = document.getElementById('bu_tf_today');
        monday = this_week();

        var stored = 60;
        try { stored = parseInt(localStorage.getItem(STORE_DURATION) || '60', 10); } catch (e) {}
        if ([30, 45, 60, 90, 120].indexOf(stored) < 0) stored = 60;
        set_duration(stored);
        var stored_view = 'free';
        try { stored_view = localStorage.getItem(STORE_VIEW) || 'free'; } catch (e) {}
        set_view(stored_view);
        Array.prototype.forEach.call(document.querySelectorAll('.pv-tf-views .pv-tf-view'), function (b) {
            b.addEventListener('click', function (e) { set_view(e.currentTarget.dataset.view); });
        });
        PHONE.addEventListener('change', function () { if (answer) render_days(); });
        Array.prototype.forEach.call(document.querySelectorAll('.pv-tf-duration'), function (b) {
            b.addEventListener('click', function (e) { set_duration(parseInt(e.currentTarget.dataset.minutes, 10)); });
        });
        document.getElementById('bu_tf_prev').addEventListener('click', function () { go(-1); });
        document.getElementById('bu_tf_next').addEventListener('click', function () { go(1); });
        // P, N, T (preview.js)
        document.getElementById('bu_tf_prev').dataset.pvKey = 'prev';
        document.getElementById('bu_tf_next').dataset.pvKey = 'next';
        ui.today.dataset.pvKey = 'today';
        ui.today.addEventListener('click', function () { monday = this_week(); load(); });
        document.getElementById('ti_tf_slot_start').addEventListener('change', update_end);
        document.getElementById('bu_tf_create_event').addEventListener('click', create_event);

        ui.search.addEventListener('input', show_results);
        ui.search.addEventListener('focus', function () { if (ui.search.value.trim()) show_results(); });
        ui.search.addEventListener('blur', close_results);
        ui.search.addEventListener('keydown', function (e) {
            var items = ui.results.querySelectorAll('.pv-tf-result');
            if (e.key === 'ArrowDown' && items.length) { e.preventDefault(); active = (active + 1) % items.length; mark_active(); }
            else if (e.key === 'ArrowUp' && items.length) { e.preventDefault(); active = (active - 1 + items.length) % items.length; mark_active(); }
            else if (e.key === 'Enter') { e.preventDefault(); if (active >= 0 && items[active]) add(items[active].dataset.key); }
            else if (e.key === 'Escape' && !ui.results.hidden) { e.preventDefault(); e.stopPropagation(); ui.search.value = ''; close_results(); }
        });
        install_swipe();
        render_days();
        load_recipients(pv_tf_me.id, function () {
            // rooms: searched like people, busy while a lesson is in them
            (window.pv_tf_rooms || []).forEach(function (r) {
                window.recipients['@' + r] = { label: 'Raum ' + r, room: true };
            });
            if (window.recipients[pv_tf_me.email]) chosen.push(pv_tf_me.email);
            changed();
        });
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
})();
