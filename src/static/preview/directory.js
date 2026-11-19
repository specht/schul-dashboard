// Neues Design (Vorschau): the class directory (/directory/<klasse>, also
// for a course) as a table page (doc/Gestaltung.md, 6a). Loaded by
// directory.html only for those who see the new design
// (directory_preview_html in include/directory.rb), so that the page stays
// exactly as it was for everyone else. The server embeds what today's page
// shows the same person (pv_directory) and which of its actions they may use.
//
// The page: the title with a quiet line (how many, the class teachers), then
// the students: on wide screens a table (number, picture and name with a
// quiet line of facts and the last access, the address and the parents'
// address as copy fields, group A/B, Antikenfahrt or Forschertage, "•••"
// for the rest); where it is narrow (phones, tablets upright) every student is a list row
// that opens a dialog (a sheet on phones) with everything about them. Then
// sections: the class's mailing lists, Unterricht (Sitzplan, Gruppen bilden,
// Live-Anmeldungen, E-Mails aus dem Unterricht), lists and printouts, the
// teachers of the class. Students see their classmates with their address,
// the teachers and their own timetable to print.
(function () {
    var data = window.pv_directory;
    var script = document.currentScript;
    if (!data || !window.pv_list || !window.pv_copy || !document.body.classList.contains('ui-preview') || !script) return;
    var mount = script.closest('.pv-dir-mount');
    if (!mount) return;

    var can = data.can || {};
    var teacher = !!data.teacher;

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

    function copy_field(text, what) {
        return pv_copy.field(text, { what: what || 'Adresse' });
    }

    var GENDER = { m: 'männlich', w: 'weiblich', d: 'divers' };
    function gender(g) { return GENDER[g] || g || ''; }

    function full_name(s) { return s.first_name + ' ' + s.last_name; }

    function people(n) {
        return n === 1 ? '1 Schülerin oder Schüler' : n + ' Schülerinnen und Schüler';
    }

    // "heute" → "zuletzt heute"; "noch nie angemeldet" stays
    function last_access(label) {
        return /^noch nie/.test(label) ? label : 'zuletzt ' + label;
    }

    function af_name(s) { return (data.af_names || {})[s.af || ''] || 'nicht eingeteilt'; }
    function ft_name(s) { return (data.ft_names || {})[s.ft || ''] || 'nicht eingeteilt'; }

    // the quiet line below a name: what today's table shows in columns
    function facts(s) {
        var f = [];
        if (s.klasse) f.push('Klasse ' + s.klasse);
        if (teacher) {
            if (s.geburtstag) f.push(s.geburtstag);
            if (s.geschlecht) f.push(gender(s.geschlecht));
            if (s.bildungsgang) f.push(s.bildungsgang);
            // the level only where it says something (courses, a repeater)
            if (s.stufe && (!data.is_klasse || s.stufe !== data.level)) f.push('Stufe ' + s.stufe);
            if (s.tutor) f.push('Tutor:in ' + s.tutor);
            if (s.zugriff) f.push(last_access(s.zugriff));
        }
        return f.join(', ');
    }

    function picture(s, cls) {
        var d = el('div', 'pv-dir-pic' + (cls ? ' ' + cls : ''));
        if (s.pic) d.style.backgroundImage = 'url(' + JSON.stringify(s.pic) + ')';
        d.setAttribute('aria-hidden', 'true');
        return d;
    }

    // what changes on the page (a group, the Dashboard-Amt) is drawn again
    // wherever the student is shown
    function changed(s) {
        (s.views || []).forEach(function (fn) { fn(); });
    }

    // the dialog is filled anew for every student: its views go with it
    var collecting = null;      // while the dialog is filled
    var dialog_views = [];

    function watch(s, fn) {
        s.views = s.views || [];
        s.views.push(fn);
        if (collecting) collecting.push([s, fn]);
        fn();
    }

    // ---------- actions ----------
    // phones: a dialog opens once the sheet or dialog before it has gone back
    // over its history entry (pv_back), otherwise it would close at once
    function after_layer(fn) {
        setTimeout(function () {
            if (!(history.state && history.state.pvLayer)) { fn(); return; }
            var done = false;
            var go = function () {
                if (done) return;
                done = true;
                window.removeEventListener('popstate', go);
                fn();
            };
            window.addEventListener('popstate', go);
            setTimeout(go, 400);
        }, 0);
    }

    var GROUPS = {
        group2: { url: '/api/toggle_group2_for_user', key: 'group2', label: 'Gruppe', name: function (s) { return s.group2; } },
        af: { url: '/api/toggle_group_af_for_user', key: 'group_af', label: 'Antikenfahrt', name: af_name },
        ft: { url: '/api/toggle_group_ft_for_user', key: 'group_ft', label: 'Forschertage', name: ft_name },
    };

    // the next group (A → B, the groups of the Antikenfahrt in turn), as
    // today's buttons do
    function toggle_group(s, kind, button) {
        var g = GROUPS[kind];
        if (button) button.disabled = true;
        api_call(g.url, { email: s.email }, function (r) {
            if (button) button.disabled = false;
            if (r.success) {
                s[kind] = r[g.key];
                changed(s);
            }
        });
    }

    // the group as a quiet button that switches it (or as text)
    function group_value(s, kind) {
        var g = GROUPS[kind];
        var allowed = !!can[kind];
        var node = el(allowed ? 'button' : 'span', 'pv-dir-group');
        if (allowed) {
            node.type = 'button';
            node.addEventListener('click', function (e) {
                e.stopPropagation();
                toggle_group(s, kind, e.currentTarget);
            });
        }
        watch(s, function () {
            var name = g.name(s);
            node.textContent = name;
            if (allowed) {
                node.setAttribute('title', g.label + ' wechseln');
                node.setAttribute('aria-label', g.label + ': ' + name + ', wechseln');
            }
        });
        return node;
    }

    function set_amt(s, flag) {
        var name = full_name(s);
        var text = flag
            ? 'Möchtest du das Dashboard-Amt an ' + name + ' vergeben? ' + s.first_name + ' bekommt eine E-Mail, dass ' + s.pronoun +
              ' ab sofort die Hausaufgaben im Dashboard eintragen und ab morgen Dateien in die Nextcloud hochladen kann.'
            : 'Möchtest du ' + name + ' das Dashboard-Amt entziehen? ' + s.first_name + ' bekommt eine E-Mail, dass ' + s.pronoun +
              ' die Hausaufgaben nicht mehr im Dashboard eintragen und keine Dateien mehr in die Nextcloud hochladen kann.';
        dashboardConfirm(text, function () {
            api_call('/api/set_sus_dashboard_amt', { email: s.email, flag: flag ? 'true' : 'false' }, function (r) {
                if (r.success) {
                    s.amt = flag;
                    changed(s);
                }
            });
        }, {
            title: flag ? 'Dashboard-Amt vergeben' : 'Dashboard-Amt entziehen',
            confirm: flag ? 'Vergeben' : 'Entziehen',
            danger: !flag,
        });
    }

    // E-Mail-Briefe (access data) as a PDF in a new tab; the tab opens right
    // away (in the click), phones block it once the PDF is there
    function letters(emails) {
        var win = window.open('', '_blank');
        fetch('/api/print_email_letters', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ emails: emails }),
        }).then(function (response) {
            if (!response.ok) throw new Error(response.status);
            return response.blob();
        }).then(function (blob) {
            if (blob.type.indexOf('pdf') < 0) throw new Error(blob.type);
            var url = window.URL.createObjectURL(blob);
            if (win && !win.closed) win.location.href = url; else window.open(url, '_blank');
        }).catch(function () {
            if (win && !win.closed) win.close();
            dashboardAlert(emails.length === 1 ? 'Der E-Mail-Brief ließ sich nicht erstellen.' : 'Die E-Mail-Briefe ließen sich nicht erstellen.', 'E-Mail-Brief');
        });
    }

    // what "•••" offers for a student on wide screens (the name opens all
    // the rest; in the dialog these are buttons)
    function actions_for(s) {
        var a = [];
        if (can.letters) a.push({ label: 'E-Mail-Brief (Zugangsdaten)', run: function () { letters([s.email]); } });
        if (can.amt) a.push({
            label: s.amt ? 'Dashboard-Amt entziehen' : 'Dashboard-Amt vergeben',
            run: function () { set_amt(s, !s.amt); },
        });
        return a;
    }

    // ---------- a student: the dialog (a sheet on phones) ----------
    var modal = null;

    function build_modal() {
        modal = el('div', 'modal pv-sheet pv-dir-modal');
        modal.id = 'directoryStudentModal';
        modal.tabIndex = -1;
        modal.setAttribute('role', 'dialog');
        modal.setAttribute('aria-hidden', 'true');
        modal.setAttribute('aria-labelledby', 'pv_dir_modal_title');
        var dialog = el('div', 'modal-dialog modal-dialog-scrollable modal-dialog-centered');
        dialog.setAttribute('role', 'document');
        var content = el('div', 'modal-content');
        var head = el('div', 'modal-header');
        var who = el('div', 'pv-dir-modal-who');
        head.appendChild(who);
        var body = el('div', 'modal-body');
        var foot = el('div', 'modal-footer');
        content.appendChild(head);
        content.appendChild(body);
        content.appendChild(foot);
        dialog.appendChild(content);
        modal.appendChild(dialog);
        document.body.appendChild(modal);
    }

    function dl_row(dl, label, value) {
        // an address takes the whole width on phones
        var row = el('div', 'pv-dir-dl-row' + (value instanceof Element && value.classList.contains('pv-copy') ? ' pv-dir-dl-wide' : ''));
        row.appendChild(el('dt', null, label));
        var dd = el('dd');
        if (value instanceof Node) dd.appendChild(value); else dd.textContent = value;
        row.appendChild(dd);
        dl.appendChild(row);
        return dd;
    }

    // a value with a quiet button beside it (»Wechseln«, »Vergeben«)
    function value_with_action(text_fn, label_fn, run, s) {
        var box = el('div', 'pv-dir-dd-act');
        var span = el('span');
        var b = el('button', 'pv-dir-ddbtn');
        b.type = 'button';
        box.appendChild(span);
        box.appendChild(b);
        b.addEventListener('click', function (e) { run(e.currentTarget); });
        watch(s, function () {
            span.textContent = text_fn();
            b.textContent = label_fn();
        });
        return box;
    }

    function open_student(s) {
        if (!modal) build_modal();
        dialog_views.forEach(function (x) {
            x[0].views = x[0].views.filter(function (fn) { return fn !== x[1]; });
        });
        collecting = [];
        var who = modal.querySelector('.pv-dir-modal-who');
        who.textContent = '';
        who.appendChild(picture(s, 'pv-dir-pic-lg'));
        var t = el('div', 'pv-dir-modal-text');
        t.appendChild(el('h5', 'modal-title', full_name(s)));
        t.firstChild.id = 'pv_dir_modal_title';
        t.appendChild(el('div', 'pv-dir-modal-facts', (s.klasse ? 'Klasse ' + s.klasse : data.title) + ', Nr. ' + s.nr));
        who.appendChild(t);

        var body = modal.querySelector('.modal-body');
        body.textContent = '';
        var dl = el('dl', 'pv-dir-dl');
        body.appendChild(dl);
        dl_row(dl, 'E-Mail', copy_field(s.email));
        if (s.eltern) dl_row(dl, 'Eltern', copy_field(s.eltern));
        if (teacher) {
            dl_row(dl, 'Geburtsdatum', s.geburtstag || 'nicht hinterlegt');
            if (s.geschlecht) dl_row(dl, 'Geschlecht', gender(s.geschlecht));
            if (s.bildungsgang) dl_row(dl, 'Bildungsgang', s.bildungsgang);
            if (s.stufe) dl_row(dl, 'Stufe', String(s.stufe));
            if ('tutor' in s) dl_row(dl, 'Tutor:in', s.tutor || 'keine Angabe');
            dl_row(dl, 'Letzter Zugriff', s.zugriff);
            ['group2', 'af', 'ft'].forEach(function (kind) {
                if (!(kind in s)) return;
                var g = GROUPS[kind];
                if (can[kind]) {
                    dl_row(dl, g.label, value_with_action(function () { return g.name(s); }, function () { return 'Wechseln'; },
                        function (b) { toggle_group(s, kind, b); }, s));
                } else {
                    var dd = dl_row(dl, g.label, '');
                    watch(s, function () { dd.textContent = g.name(s); });
                }
            });
        }
        if ('amt' in s) {
            if (can.amt) {
                dl_row(dl, 'Dashboard-Amt', value_with_action(function () { return s.amt ? 'ja' : 'nein'; },
                    function () { return s.amt ? 'Entziehen' : 'Vergeben'; },
                    function () {
                        var flag = !s.amt;
                        $(modal).one('hidden.bs.modal', function () { after_layer(function () { set_amt(s, flag); }); });
                        $(modal).modal('hide');
                    }, s));
            } else if (s.amt) {
                dl_row(dl, 'Dashboard-Amt', 'ja');
            }
        }

        var foot = modal.querySelector('.modal-footer');
        foot.textContent = '';
        if (can.letters) {
            var b = el('button', 'btn btn-secondary', 'E-Mail-Brief');
            b.type = 'button';
            b.id = 'bu_dir_letter';
            b.setAttribute('title', 'E-Mail-Brief mit den Zugangsdaten (PDF)');
            b.addEventListener('click', function () { letters([s.email]); });
            foot.appendChild(b);
        }
        var close = el('button', 'btn btn-secondary', 'Schließen');
        close.type = 'button';
        close.setAttribute('data-dismiss', 'modal');
        foot.appendChild(close);
        dialog_views = collecting;
        collecting = null;
        $(modal).modal('show');
    }

    // ---------- the students ----------
    var root = el('div', 'pv-dir');
    mount.appendChild(root);

    var head = el('div', 'pv-dir-head');
    head.appendChild(el('h2', null, data.title));
    var head_facts = [people(data.students.length)];
    var kl = (data.teachers || []).filter(function (t) { return t.kl; }).map(function (t) { return t.name; });
    if (kl.length) head_facts.push('Klassenleitung ' + kl.join(' und '));
    head.appendChild(el('p', 'pv-dir-facts', head_facts.join(', ')));
    root.appendChild(head);

    var students = el('div', 'pv-dir-students');
    root.appendChild(students);

    var show = {
        parents: teacher,
        group2: teacher,
        af: !!data.af_names,
        ft: !!data.ft_names,
        act: !!(can.letters || can.amt),
    };

    function student_row(s) {
        var tr = el('tr', 'pv-dir-row');
        tr.setAttribute('data-user-id', s.id);
        tr.setAttribute('data-email', s.email);
        tr.appendChild(el('td', 'pv-dir-nr', s.nr + '.'));

        var person = el('td', 'pv-dir-person');
        var who = el('div', 'pv-dir-who');
        who.appendChild(picture(s));
        var text = el('div', 'pv-dir-text');
        var line = el('div', 'pv-dir-nameline');
        var name;
        if (teacher) {
            name = el('button', 'pv-dir-name');
            name.type = 'button';
            name.setAttribute('aria-haspopup', 'dialog');
            name.addEventListener('click', function (e) {
                e.stopPropagation();
                open_student(s);
            });
        } else {
            name = el('span', 'pv-dir-name');
        }
        name.appendChild(el('span', 'pv-dir-last', s.last_name));
        name.appendChild(document.createTextNode(', ' + s.first_name));
        line.appendChild(name);
        if ('amt' in s) {
            var chip = el('span', 'pv-lchip pv-dir-amt', 'Dashboard-Amt');
            line.appendChild(chip);
            watch(s, function () { chip.hidden = !s.amt; });
        }
        text.appendChild(line);
        var f = facts(s);
        if (f) text.appendChild(el('div', 'pv-dir-facts', f));
        who.appendChild(text);
        if (teacher) who.appendChild(icon('chevron-right')).classList.add('pv-dir-chev');
        person.appendChild(who);
        tr.appendChild(person);

        var mail = el('td', 'pv-dir-mail');
        mail.appendChild(copy_field(s.email));
        tr.appendChild(mail);
        if (show.parents) {
            var parents = el('td', 'pv-dir-parents');
            parents.appendChild(copy_field(s.eltern));
            tr.appendChild(parents);
        }
        ['group2', 'af', 'ft'].forEach(function (kind) {
            if (!show[kind]) return;
            var td = el('td', 'pv-dir-g pv-dir-' + kind);
            td.appendChild(group_value(s, kind));
            tr.appendChild(td);
        });
        if (show.act) {
            var td = el('td', 'pv-dir-act');
            var more = el('button', 'pv-lmore pv-dir-more');
            more.type = 'button';
            more.setAttribute('aria-haspopup', 'menu');
            more.setAttribute('aria-expanded', 'false');
            more.setAttribute('aria-label', 'Weitere Aktionen für ' + full_name(s));
            more.setAttribute('title', 'Weitere Aktionen');
            more.appendChild(icon('dots'));
            more.addEventListener('click', function (e) {
                e.stopPropagation();
                pv_list.menu(more, full_name(s), actions_for(s), e.detail === 0);
            });
            td.appendChild(more);
            tr.appendChild(td);
        }
        return tr;
    }

    if (data.students.length === 0) {
        students.appendChild(el('p', 'pv-lempty', data.is_klasse
            ? 'In dieser Klasse ist zurzeit niemand eingetragen.'
            : 'In dieser Lerngruppe ist zurzeit niemand eingetragen.'));
    } else {
        var wrap = el('div', 'pv-dir-scroll');
        var table = el('table', 'pv-dir-table' + (teacher ? ' pv-dir-opens' : ''));
        var thead = el('thead');
        var hr = el('tr');
        function th(label, cls) {
            var c = el('th', cls, label);
            c.scope = 'col';
            hr.appendChild(c);
            return c;
        }
        th('Nr.', 'pv-dir-nr');
        th('Name', 'pv-dir-person');
        th('E-Mail', 'pv-dir-mail');
        if (show.parents) th('Eltern', 'pv-dir-parents');
        if (show.group2) th('Gruppe', 'pv-dir-g');
        if (show.af) th('Antikenfahrt', 'pv-dir-g');
        if (show.ft) th('Forschertage', 'pv-dir-g');
        if (show.act) th('', 'pv-dir-act').appendChild(el('span', 'sr-only', 'Aktionen'));
        thead.appendChild(hr);
        table.appendChild(thead);
        var tbody = el('tbody');
        data.students.forEach(function (s) { tbody.appendChild(student_row(s)); });
        table.appendChild(tbody);
        wrap.appendChild(table);
        students.appendChild(wrap);
    }

    // ---------- sections below ----------
    function section(title, cls) {
        var s = el('section', 'pv-dir-sec' + (cls ? ' ' + cls : ''));
        s.appendChild(el('h3', 'pv-dir-h', title));
        root.appendChild(s);
        return s;
    }

    // a link or button with an icon, quiet (a row on phones)
    function link(o) {
        var a;
        if (o.href) {
            a = el('a', 'pv-dir-link');
            a.href = o.href;
            if (o.blank) { a.target = '_blank'; a.rel = 'noopener'; }
        } else {
            a = el('button', 'pv-dir-link');
            a.type = 'button';
        }
        a.appendChild(icon(o.icon || 'arrow-right'));
        a.appendChild(el('span', 'pv-dir-link-label', o.label));
        a.appendChild(icon('chevron-right')).classList.add('pv-dir-link-chev');
        if (o.run) a.addEventListener('click', function (e) { e.preventDefault(); o.run(); });
        return a;
    }

    function links(parent, items) {
        var box = el('div', 'pv-dir-links');
        items.forEach(function (o) { box.appendChild(link(o)); });
        parent.appendChild(box);
        return box;
    }

    if (data.lists && data.lists.length) {
        var ls = section('E-Mail-Verteiler', 'pv-dir-lists-sec');
        var grid = el('div', 'pv-dir-lists');
        data.lists.forEach(function (l) {
            var item = el('div', 'pv-dir-list');
            item.appendChild(el('div', 'pv-dir-list-label', l.label));
            item.appendChild(copy_field(l.email));
            grid.appendChild(item);
        });
        ls.appendChild(grid);
    }

    var tools_sec = null;
    var tools_box = null;
    if (teacher && data.is_klasse) {
        tools_sec = section('Unterricht', 'pv-dir-tools-sec');
        tools_box = links(tools_sec, data.tools || []);
    }

    if (data.downloads && data.downloads.length) {
        var ds = section('Listen und Ausdrucke', 'pv-dir-downloads-sec');
        links(ds, data.downloads.map(function (o) {
            if (!o.letters) return o;
            return {
                label: o.label, icon: o.icon,
                run: function () { letters(data.students.map(function (s) { return s.email; })); },
            };
        }));
    }

    if (data.timetable) {
        var tt = section('Stundenplan zum Ausdrucken', 'pv-dir-timetable-sec');
        links(tt, data.timetable);
        tt.appendChild(el('p', 'pv-dir-note', 'Der Hintergrund kommt aus deinem Dashboard: Du kannst ihn in deinem Profil ändern.'));
    }

    if (data.teachers) {
        var ts = section('Lehrkräfte', 'pv-dir-teachers-sec');
        if (data.teachers.length === 0) {
            ts.appendChild(el('p', 'pv-lempty', 'Für diese Klasse sind keine Lehrkräfte eingetragen.'));
        } else {
            var tw = el('div', 'pv-dir-scroll');
            var tt2 = el('table', 'pv-dir-teachers');
            var th2 = el('thead');
            var tr2 = el('tr');
            ['Kürzel', 'Name', 'Fächer (Wochenstunden)', 'E-Mail'].forEach(function (label, i) {
                var c = el('th', ['pv-dir-sh', 'pv-dir-tname', 'pv-dir-subjects', 'pv-dir-mail'][i], label);
                c.scope = 'col';
                tr2.appendChild(c);
            });
            th2.appendChild(tr2);
            tt2.appendChild(th2);
            var tb2 = el('tbody');
            data.teachers.forEach(function (t) {
                var r = el('tr', 'pv-dir-trow' + (t.kl ? ' pv-dir-kl' : ''));
                r.appendChild(el('td', 'pv-dir-sh', t.shorthand));
                var n = el('td', 'pv-dir-tname');
                var nl = el('div', 'pv-dir-nameline');
                nl.appendChild(el('span', 'pv-dir-name', t.name || t.shorthand));
                if (t.kl) nl.appendChild(el('span', 'pv-lchip', 'Klassenleitung'));
                n.appendChild(nl);
                // phones: Kürzel and subjects as the quiet line
                n.appendChild(el('div', 'pv-dir-facts pv-dir-tfacts', [t.shorthand, t.faecher].filter(Boolean).join(', ')));
                r.appendChild(n);
                r.appendChild(el('td', 'pv-dir-subjects', t.faecher));
                var m = el('td', 'pv-dir-mail');
                if (t.email) m.appendChild(copy_field(t.email));
                r.appendChild(m);
                tb2.appendChild(r);
            });
            tt2.appendChild(tb2);
            tw.appendChild(tt2);
            ts.appendChild(tw);
        }
    }

    // Sitzplan and Gruppenbildung: today's page script works them out from
    // the rooms and seats (directory.html) and writes them into
    // #additional_teacher_content, hidden here – they join the section
    // Unterricht as links, the hints as quiet lines
    function adopt_teacher_content() {
        var old = document.getElementById('additional_teacher_content');
        if (!old || !tools_box) return;
        var first = tools_box.firstChild;
        var notes = [];
        Array.prototype.forEach.call(old.querySelectorAll('a[href]'), function (a) {
            var label = a.textContent.trim();
            var href = a.getAttribute('href');
            tools_box.insertBefore(link({
                label: label,
                href: href,
                icon: /^\/zufallsgruppen/.test(href) ? 'users-group' : 'layout-grid',
            }), first);
        });
        Array.prototype.forEach.call(old.querySelectorAll('.text-muted'), function (d) {
            var t = d.textContent.trim();
            if (t) notes.push(t);
        });
        notes.forEach(function (t) { tools_sec.appendChild(el('p', 'pv-dir-note', t)); });
        if (tools_box.children.length === 0 && notes.length === 0) tools_sec.hidden = true;
    }
    if (tools_box) {
        document.addEventListener('DOMContentLoaded', function () {
            // after the page's own DOMContentLoaded handler
            setTimeout(adopt_teacher_content, 0);
        });
    }
})();
