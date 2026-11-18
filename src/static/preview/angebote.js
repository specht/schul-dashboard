// Neues Design (Vorschau): AGs und Angebote (/angebote) as a list with
// actions (doc/Gestaltung.md, 6a; pv_list in preview.js). Loaded by
// angebote.html only for those who see the new design (angebote_preview_html
// in include/angebote.rb), so that the page stays exactly as it was for
// everyone else. It draws from the page's own data (stored_angebote,
// display_name_for_email, klasse_for_email) and uses the page's editor
// (edit_angebot, new_angebot); the server adds who is logged in, whether
// they are an admin and who may run offers (pv_angebote).
//
// The page: title and »Neues Angebot«, a short line, a search, then »Meine
// AGs und Angebote« (responsible or co-responsible) and »Alle anderen« by
// initial letter. A row: the name, who is responsible, how many take part;
// the participants fold open below the row (by class). Actions: Bearbeiten
// in the row, the rest in »•••« (a sheet on phones): Teilen, Zuweisen
// (admins), Übernehmen (when nobody responsible is left), Mitverantwortung
// abgeben, Löschen.
(function () {
    var data = window.pv_angebote;
    var script = document.currentScript;
    if (!data || !window.pv_list || !document.body.classList.contains('ui-preview') || !script) return;
    var container = script.closest('.container');
    var mount = container && container.querySelector('.angebote-container');
    if (!mount) return;

    var managers = data.managers;           // [{email, name}], sorted by name
    var manager_name = {};
    managers.forEach(function (m) { manager_name[m.email] = m.name; });
    var open_rows = {};                     // aid → participants shown

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

    // for the search: lower case, without accents ("Schüler" finds "schuler")
    function norm(s) {
        return String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
    }

    function count_label(n) {
        return n === 1 ? '1 Angebot' : n + ' Angebote';
    }

    function people(n) {
        return n === 0 ? 'keine Teilnehmer' : (n === 1 ? '1 Teilnehmer' : n + ' Teilnehmer');
    }

    function name_of(email) {
        return manager_name[email] || display_name_for_email[email] || email;
    }

    function co_owners(a) { return a.co_owners || []; }
    function recipients(a) { return (a.recipients || []).filter(function (x) { return !!x; }); }
    // still at school and allowed to run offers
    function active(email) { return !!manager_name[email]; }

    function is_owner(a) { return a.owner === data.me; }
    function is_co_owner(a) { return co_owners(a).indexOf(data.me) >= 0; }
    function is_mine(a) { return is_owner(a) || is_co_owner(a); }
    function can_share(a) { return is_owner(a) || data.admin; }
    // the responsible person left: a co-owner may take it over, or anyone
    // who runs offers when no co-owner is left either (/api/take_over_angebot)
    function can_take_over(a) {
        return !active(a.owner) && !is_owner(a) && (is_co_owner(a) || !co_owners(a).some(active));
    }

    function responsible(a) {
        var names = [a.owner].concat(co_owners(a)).map(function (email) {
            return active(email) ? name_of(email) : name_of(email) + ' (nicht mehr an der Schule)';
        });
        return 'Verantwortlich: ' + names.join(', ');
    }

    function find(aid) {
        for (var i = 0; i < stored_angebote.length; i++)
            if (stored_angebote[i].aid === aid) return stored_angebote[i];
        return null;
    }

    // the server's answer replaces the offer, the list (and today's table,
    // hidden) are drawn again
    function replace(angebot) {
        stored_angebote = stored_angebote.map(function (a) { return a.aid === angebot.aid ? angebot : a; });
        update_stored_angebote();
    }

    // ---------- dialogs: a sheet on phones ----------
    function modal(id, title_id) {
        var m = el('div', 'modal pv-sheet pv-agb-modal');
        m.id = id;
        m.tabIndex = -1;
        m.setAttribute('role', 'dialog');
        m.setAttribute('aria-hidden', 'true');
        m.setAttribute('aria-labelledby', title_id);
        m.innerHTML =
            "<div class='modal-dialog modal-dialog-scrollable modal-dialog-centered' role='document'>" +
            "<div class='modal-content'>" +
            "<div class='modal-header'><h5 class='modal-title' id='" + title_id + "'></h5></div>" +
            "<div class='modal-body'></div>" +
            "<div class='modal-footer'></div>" +
            "</div></div>";
        document.body.appendChild(m);
        return m;
    }

    // a search over everyone who may run offers; on_pick(email)
    function person_picker(parent, o) {
        var box = el('div', 'pv-agb-search pv-agb-picker');
        box.appendChild(icon('search'));
        var input = el('input', 'form-control');
        input.type = 'search';
        input.id = o.id;
        input.placeholder = o.placeholder;
        input.setAttribute('aria-label', o.placeholder);
        input.autocomplete = 'off';
        box.appendChild(input);
        parent.appendChild(box);
        var results = el('div', 'pv-agb-results');
        results.setAttribute('role', 'listbox');
        results.setAttribute('aria-label', o.placeholder);
        parent.appendChild(results);
        function show() {
            results.textContent = '';
            var words = norm(input.value).split(/\s+/).filter(function (w) { return w.length > 0; });
            if (words.length === 0) return;
            var skip = o.exclude();
            var hits = managers.filter(function (m) {
                if (skip.indexOf(m.email) >= 0) return false;
                var hay = norm(m.name + ' ' + m.email);
                return words.every(function (w) { return hay.indexOf(w) >= 0; });
            });
            if (hits.length === 0) {
                results.appendChild(el('p', 'pv-agb-noresult', 'Niemand passt zu »' + input.value.trim() + '«.'));
                return;
            }
            hits.slice(0, 8).forEach(function (m) {
                var b = el('button', 'pv-agb-result');
                b.type = 'button';
                b.setAttribute('role', 'option');
                b.setAttribute('data-email', m.email);
                b.appendChild(el('span', 'pv-agb-result-name', m.name));
                b.appendChild(el('span', 'pv-agb-result-mail', m.email));
                b.addEventListener('click', function (e) {
                    o.on_pick(e.currentTarget.getAttribute('data-email'));
                });
                results.appendChild(b);
            });
        }
        input.addEventListener('input', show);
        return {
            input: input,
            reset: function () { input.value = ''; show(); },
            refresh: show,
        };
    }

    // ---------- Teilen: who else may edit ----------
    var share = null;       // {modal, aid, picker}

    function share_dialog() {
        if (share) return share;
        var m = modal('angebotShareModal', 'pv_ag_share_title');
        var body = m.querySelector('.modal-body');
        body.appendChild(el('p', 'pv-agb-hint pv-agb-share-hint'));
        var list = el('div', 'pv-agb-people-list');
        body.appendChild(list);
        body.appendChild(el('label', 'pv-agb-label', 'Lehrkraft hinzufügen')).setAttribute('for', 'ti_ag_share');
        share = { modal: m, list: list, aid: null };
        share.picker = person_picker(body, {
            id: 'ti_ag_share',
            placeholder: 'Name suchen',
            exclude: function () {
                var a = find(share.aid);
                return a ? [a.owner].concat(co_owners(a)) : [];
            },
            on_pick: function (email) {
                api_call('/api/share_angebot', { aid: share.aid, email: email }, function (result) {
                    if (!result.success) return;
                    replace(result.angebot);
                    share.picker.reset();
                    fill_share();
                    share.picker.input.focus();
                });
            },
        });
        var done = el('button', 'btn btn-secondary', 'Fertig');
        done.type = 'button';
        done.setAttribute('data-dismiss', 'modal');
        m.querySelector('.modal-footer').appendChild(done);
        return share;
    }

    function person_line(email, note, remove) {
        var r = el('div', 'pv-agb-person');
        var text = el('div', 'pv-agb-person-text');
        text.appendChild(el('span', 'pv-agb-person-name', name_of(email)));
        if (note) text.appendChild(el('span', 'pv-agb-person-note', note));
        r.appendChild(text);
        if (remove) {
            var b = el('button', 'pv-agb-remove');
            b.type = 'button';
            b.setAttribute('aria-label', name_of(email) + ' entfernen');
            b.setAttribute('title', 'Entfernen');
            b.appendChild(icon('x'));
            b.addEventListener('click', function () { remove(email); });
            r.appendChild(b);
        }
        return r;
    }

    function fill_share() {
        var a = find(share.aid);
        if (!a) return;
        share.modal.querySelector('.modal-title').textContent = '»' + a.info.name + '« teilen';
        share.modal.querySelector('.pv-agb-share-hint').textContent = (is_owner(a)
            ? 'Wen du hier hinzufügst, kann das Angebot wie du bearbeiten: den Namen und die Teilnehmer. Löschen kannst nur du.'
            : 'Wer hier steht, kann das Angebot wie die verantwortliche Lehrkraft bearbeiten: den Namen und die Teilnehmer.');
        share.list.textContent = '';
        share.list.appendChild(person_line(a.owner, 'verantwortlich'));
        co_owners(a).forEach(function (email) {
            share.list.appendChild(person_line(email, 'bearbeitet mit', function (who) {
                api_call('/api/unshare_angebot', { aid: a.aid, email: who }, function (result) {
                    if (!result.success) return;
                    replace(result.angebot);
                    fill_share();
                });
            }));
        });
        share.picker.refresh();
    }

    function open_share(a) {
        share_dialog();
        share.aid = a.aid;
        share.picker.reset();
        fill_share();
        $(share.modal).modal('show');
    }

    // ---------- Zuweisen (admins): someone else becomes responsible ----------
    var assign = null;      // {modal, aid, chosen, picker}

    function assign_dialog() {
        if (assign) return assign;
        var m = modal('angebotAssignModal', 'pv_ag_assign_title');
        var body = m.querySelector('.modal-body');
        body.appendChild(el('p', 'pv-agb-hint', 'Die Lehrkraft, die du hier wählst, wird für das Angebot verantwortlich und kann es bearbeiten, teilen und löschen.'));
        body.appendChild(el('div', 'pv-agb-now'));
        body.appendChild(el('label', 'pv-agb-label', 'Neu verantwortlich')).setAttribute('for', 'ti_ag_assign');
        var chosen = el('div', 'pv-agb-chosen');
        chosen.hidden = true;
        assign = { modal: m, aid: null, chosen: null, chosen_box: chosen };
        assign.picker = person_picker(body, {
            id: 'ti_ag_assign',
            placeholder: 'Name suchen',
            exclude: function () {
                var a = find(assign.aid);
                return a ? [a.owner] : [];
            },
            on_pick: function (email) {
                assign.chosen = email;
                assign.picker.reset();
                show_chosen();
                // the picked result is gone: the focus to the next step
                assign.go.focus();
            },
        });
        body.appendChild(chosen);
        var keep = el('label', 'pv-agb-keep');
        var check = el('input');
        check.type = 'checkbox';
        check.id = 'cb_ag_keep_previous';
        check.checked = true;
        keep.appendChild(check);
        keep.appendChild(el('span', 'pv-agb-keep-text'));
        body.appendChild(keep);
        assign.keep = keep;
        assign.check = check;
        var cancel = el('button', 'btn btn-secondary', 'Abbrechen');
        cancel.type = 'button';
        cancel.setAttribute('data-dismiss', 'modal');
        var go = el('button', 'btn btn-primary', 'Zuweisen');
        go.type = 'button';
        go.id = 'bu_ag_assign';
        go.disabled = true;
        go.addEventListener('click', function () {
            var a = find(assign.aid);
            if (!a || !assign.chosen) return;
            var payload = { aid: a.aid, email: assign.chosen, keep_previous: !assign.keep.hidden && assign.check.checked };
            api_call('/api/assign_angebot', payload, function (result) {
                if (!result.success) return;
                replace(result.angebot);
                $(assign.modal).modal('hide');
            });
        });
        assign.go = go;
        var foot = m.querySelector('.modal-footer');
        foot.appendChild(cancel);
        foot.appendChild(go);
        return assign;
    }

    function show_chosen() {
        var box = assign.chosen_box;
        box.textContent = '';
        box.hidden = !assign.chosen;
        assign.go.disabled = !assign.chosen;
        if (!assign.chosen) return;
        box.appendChild(person_line(assign.chosen, assign.chosen, function () {
            assign.chosen = null;
            show_chosen();
            assign.picker.input.focus();
        }));
    }

    function open_assign(a) {
        assign_dialog();
        assign.aid = a.aid;
        assign.chosen = null;
        assign.modal.querySelector('.modal-title').textContent = '»' + a.info.name + '« zuweisen';
        var now = assign.modal.querySelector('.pv-agb-now');
        now.textContent = responsible(a);
        // the previous one stays co-responsible (unless they left)
        assign.keep.hidden = !active(a.owner);
        assign.check.checked = true;
        assign.keep.querySelector('.pv-agb-keep-text').textContent = name_of(a.owner) + ' bearbeitet das Angebot weiter mit';
        assign.picker.reset();
        show_chosen();
        $(assign.modal).modal('show');
    }

    // ---------- the actions of a row ----------
    function take_over(a) {
        dashboardConfirm('Du wirst für »' + a.info.name + '« verantwortlich und kannst es bearbeiten, teilen und löschen.', function () {
            api_call('/api/take_over_angebot', { aid: a.aid }, function (result) {
                if (result.success) replace(result.angebot);
            });
        }, { title: 'Angebot übernehmen', confirm: 'Übernehmen' });
    }

    function leave(a) {
        dashboardConfirm('Du kannst »' + a.info.name + '« dann nicht mehr bearbeiten. Verantwortlich bleibt ' + name_of(a.owner) + '.', function () {
            api_call('/api/unshare_angebot', { aid: a.aid, email: data.me }, function (result) {
                if (result.success) replace(result.angebot);
            });
        }, { title: 'Mitverantwortung abgeben', confirm: 'Abgeben' });
    }

    function delete_question(a) {
        return 'Das Angebot »' + a.info.name + '« löschen? Die Teilnahme verschwindet auch aus den Profilen und Zeugnissen, und der E-Mail-Verteiler entfällt.';
    }

    function remove(a) {
        pv_list.confirm_delete(delete_question(a), function () {
            api_call('/api/delete_angebot', { aid: a.aid }, function (result) {
                if (!result.success) return;
                stored_angebote = stored_angebote.filter(function (x) { return x.aid !== result.aid; });
                update_stored_angebote();
            });
        }, 'Angebot löschen');
    }

    function actions(a) {
        var list = [];
        if (is_mine(a)) list.push({ label: 'Bearbeiten', visible: true, run: function () { edit_angebot(a); } });
        if (can_share(a)) list.push({ label: 'Teilen', run: function () { open_share(a); } });
        if (data.admin) list.push({ label: 'Zuweisen', run: function () { open_assign(a); } });
        if (can_take_over(a)) list.push({ label: 'Übernehmen', run: function () { take_over(a); } });
        if (is_co_owner(a) && !is_owner(a)) list.push({ label: 'Mitverantwortung abgeben', run: function () { leave(a); } });
        if (is_owner(a)) list.push({ label: 'Löschen', danger: true, run: function () { remove(a); } });
        return list;
    }

    // ---------- the participants, by class ----------
    function participants(a) {
        var box = el('div', 'pv-agb-people');
        var groups = [];
        recipients(a).forEach(function (email) {
            var klasse = klasse_for_email[email] || '';
            var last = groups[groups.length - 1];
            if (!last || last.klasse !== klasse) groups.push(last = { klasse: klasse, names: [] });
            last.names.push(display_name_for_email[email] || email);
        });
        groups.forEach(function (g) {
            var line = el('div', 'pv-agb-klasse');
            line.appendChild(el('span', 'pv-agb-kl', g.klasse || 'Weitere'));
            line.appendChild(el('span', 'pv-agb-names', g.names.join(', ')));
            box.appendChild(line);
        });
        return box;
    }

    function render_row(a) {
        var n = recipients(a).length;
        var line = el('div', 'pv-lrow-facts pv-agb-line');
        line.appendChild(el('span', 'pv-agb-who', responsible(a)));
        var toggle = null;
        var people_box = null;
        if (n > 0) {
            toggle = el('button', 'pv-agb-count');
            toggle.type = 'button';
            toggle.appendChild(el('span', null, people(n)));
            toggle.appendChild(icon('chevron-down'));
            toggle.setAttribute('aria-expanded', 'false');
            line.appendChild(toggle);
        } else {
            line.appendChild(el('span', 'pv-agb-count pv-agb-count-none', people(0)));
        }
        var extra = el('div', 'pv-agb-extra');
        extra.appendChild(line);
        var o = { title: a.info.name, cls: 'pv-agb-row', extra: extra, actions: actions(a) };
        var row;
        function set_open(open) {
            if (open && !people_box) {
                people_box = participants(a);
                people_box.id = 'pv_ag_people_' + a.aid;
                extra.appendChild(people_box);
                toggle.setAttribute('aria-controls', people_box.id);
            }
            if (people_box) people_box.hidden = !open;
            open_rows[a.aid] = open;
            row.classList.toggle('pv-agb-open', open);
            toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
            row.querySelector('.pv-lrow-title').setAttribute('aria-expanded', open ? 'true' : 'false');
        }
        if (n > 0) o.open = function () { set_open(!open_rows[a.aid]); };
        row = pv_list.row(o);
        row.setAttribute('data-aid', a.aid);
        if (toggle) {
            toggle.addEventListener('click', function (e) {
                e.stopPropagation();
                set_open(!open_rows[a.aid]);
            });
            if (open_rows[a.aid]) set_open(true);
        }
        row.pv_ag_search = norm(a.info.name + ' ' + responsible(a));
        return row;
    }

    // ---------- the page ----------
    var root = el('div', 'pv-agb-page');
    mount.parentNode.insertBefore(root, mount.nextSibling);
    var intro = el('p', 'pv-agb-intro');
    intro.appendChild(document.createTextNode('Trag hier AGs und andere Gruppen ein, die du betreust. Klassenleitungen sehen die Teilnahme bei den Zeugnissen, Schülerinnen und Schüler in ihrem Profil, und jede Gruppe bekommt einen '));
    var link = el('a', null, 'E-Mail-Verteiler');
    link.href = '/mailing_lists';
    intro.appendChild(link);
    intro.appendChild(document.createTextNode('. Bearbeiten können die Verantwortlichen und alle, mit denen sie eine Gruppe teilen.'));
    root.appendChild(intro);

    var search_box = el('div', 'pv-agb-search');
    search_box.appendChild(icon('search'));
    var search = el('input', 'form-control');
    search.type = 'search';
    search.id = 'ti_ag_search';
    search.placeholder = 'Angebot oder Lehrkraft suchen';
    search.setAttribute('aria-label', 'Angebot oder Lehrkraft suchen');
    search.autocomplete = 'off';
    search_box.appendChild(search);
    root.appendChild(search_box);

    var lists = el('div', 'pv-agb-sections');
    root.appendChild(lists);
    var none = el('p', 'pv-lempty pv-agb-none');
    none.hidden = true;
    root.appendChild(none);

    var sections = [];      // {g, rows, count, total}

    function letter(name) {
        var c = norm(name).replace(/[^a-z0-9]/g, '').charAt(0).toUpperCase();
        return c === '' ? '#' : (/[0-9]/.test(c) ? '0–9' : c);
    }

    function render() {
        lists.textContent = '';
        sections = [];
        var all = stored_angebote.slice().sort(function (a, b) {
            return norm(a.info.name).localeCompare(norm(b.info.name), 'de');
        });
        var mine = all.filter(is_mine);
        var others = all.filter(function (a) { return !is_mine(a); });
        var g = pv_list.group(lists, { label: 'Meine AGs und Angebote', count: count_label(mine.length), cls: 'pv-agb-mine' });
        var rows = mine.map(function (a) { var r = render_row(a); g.body.appendChild(r); return r; });
        if (mine.length === 0)
            g.body.appendChild(el('p', 'pv-lempty pv-agb-empty', 'Du betreust noch kein Angebot. Mit »Neues Angebot« legst du eins an, oder jemand teilt eins mit dir.'));
        sections.push({ g: g, rows: rows, count: g.section.querySelector('.pv-lgroup-count') });
        if (others.length > 0) {
            var o = pv_list.group(lists, { label: 'Alle anderen', count: count_label(others.length), cls: 'pv-agb-others' });
            var orows = [];
            var current = null;
            var heading = null;
            // initial letters only where the list is long
            var letters = others.length > 12;
            others.forEach(function (a) {
                var l = letter(a.info.name);
                if (letters && l !== current) {
                    current = l;
                    heading = el('h4', 'pv-agb-letter', l);
                    heading.pv_ag_rows = [];
                    o.body.appendChild(heading);
                }
                var r = render_row(a);
                if (heading) {
                    r.pv_ag_heading = heading;
                    heading.pv_ag_rows.push(r);
                }
                o.body.appendChild(r);
                orows.push(r);
            });
            sections.push({ g: o, rows: orows, count: o.section.querySelector('.pv-lgroup-count') });
        }
        search_box.hidden = stored_angebote.length < 2;
        filter();
    }

    // searching: only the matching rows (and their letters), the counts as
    // "2 von 14"
    function filter() {
        var words = norm(search.value).split(/\s+/).filter(function (w) { return w.length > 0; });
        var any = false;
        sections.forEach(function (s) {
            var n = 0;
            s.rows.forEach(function (r) {
                var hit = words.every(function (w) { return r.pv_ag_search.indexOf(w) >= 0; });
                r.hidden = !hit;
                if (hit) n++;
            });
            s.rows.forEach(function (r) {
                if (r.pv_ag_heading) r.pv_ag_heading.hidden = !r.pv_ag_heading.pv_ag_rows.some(function (x) { return !x.hidden; });
            });
            var empty = s.g.body.querySelector('.pv-agb-empty');
            if (words.length === 0) {
                s.g.section.hidden = false;
                s.count.textContent = count_label(s.rows.length);
                if (empty) empty.hidden = false;
            } else {
                s.g.section.hidden = n === 0;
                s.count.textContent = n === s.rows.length ? count_label(n) : n + ' von ' + s.rows.length;
                if (n > 0) any = true;
            }
        });
        none.textContent = 'Kein Angebot passt zu »' + search.value.trim() + '«.';
        none.hidden = words.length === 0 || any;
    }

    search.addEventListener('input', filter);
    search.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && search.value) {
            e.preventDefault();
            search.value = '';
            filter();
        }
    });

    document.addEventListener('DOMContentLoaded', function () {
        // the page's editor as a sheet on phones, in »du«
        var editor = document.getElementById('angebotModal');
        editor.classList.add('pv-sheet');
        document.getElementById('ti_name').placeholder = 'Name des Angebots, zum Beispiel »Musical-AG«';
        // Löschen: in the »•••« menu, here only with the same question
        $('#bu_delete_angebot').off('click').on('click', function () {
            var a = find(old_aid);
            if (a) pv_list.confirm_delete(delete_question(a), delete_angebot, 'Angebot löschen');
        });
        // whenever the page draws its (hidden) table, the list follows
        var draw_table = window.update_stored_angebote;
        window.update_stored_angebote = function () {
            draw_table();
            render();
        };
        pv_list.page(container, { main: container.querySelector('.bu-new-angebot') });
        render();
    });
})();
