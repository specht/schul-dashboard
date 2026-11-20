// Neues Design (Vorschau): the Kursbuch (/lessons/<course>) as a list of
// lessons with the editing pane beside it (doc/Gestaltung.md, 6a). Loaded by
// lessons.html only for those who see the new design
// (lessons_preview_script in include/lesson.rb), so that the page stays
// exactly as it was for everyone else.
//
// Today's page stays the engine: its table rows (tr.lesson) keep the
// selection (click, Umschalt/Strg, ziehen, Strg+A), its pane (.lesson_pane)
// keeps every field, button and dialog, and saving, Umplanen and the
// feedback dialog run unchanged. This script only changes how they look:
//   - a header with the course's name, "Heute" and the Kursbuch-PDF;
//   - each lesson row shows date and lesson on the left, then Thema,
//     Stundenthema, Hausaufgaben and Notiz as text (links open in a new
//     tab) and a quiet line of facts; month headings, holidays quiet, a
//     line for today. Wide lists (from 900 px, a container query in
//     lessons.css) show the same elements as a table: a column each for
//     Thema, Stundenthema and Hausaufgaben, the rest as quiet icons;
//   - from 1024 px the pane stands beside the list (sticky); below that it
//     opens as a sheet when a lesson is tapped (phones: the whole screen,
//     tablets: a panel from the right). Back closes it, unsaved changes
//     are asked about first, saving closes it;
//   - the pane: a title (the selected lesson, "Noch nicht gespeichert"
//     below it while there are changes), sections without boxes,
//     Speichern always in view at the bottom, Umplanen as a menu (a sheet
//     on phones); removing lessons asks first.
(function () {
    var data = window.pv_lessons;
    if (!data || !window.pv_list || !document.body.classList.contains('ui-preview')) return;
    if (typeof window.update_table !== 'function' || typeof window.selection_updated !== 'function') return;

    // jQuery comes at the end of the page: looked up when used
    var $ = function (x) { return window.jQuery(x); };
    var OVERLAY = window.matchMedia('(max-width: 1023px)');
    var PHONE = window.matchMedia('(max-width: 767px)');
    var MONTHS = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August',
        'September', 'Oktober', 'November', 'Dezember'];
    var WEEKDAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];

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

    function info(o) { return ((window.lesson_data[o] || {}).info) || {}; }
    function str(v) { return (v === null || v === undefined) ? '' : String(v).trim(); }

    // text as text, line breaks kept, web addresses as links in a new tab
    // (as in the timetable's lesson dialog)
    function append_text(element, text) {
        String(text || '').split(/\r?\n|<br\s*\/?>/i).forEach(function (part, i) {
            if (i > 0) element.appendChild(el('br'));
            var at = 0;
            part.replace(/https?:\/\/[^\s<>"']+/gi, function (url, pos) {
                // punctuation at the end belongs to the sentence, not the address
                var trimmed = url.replace(/[.,;:!?]+$/, '');
                if (/\)$/.test(trimmed) && trimmed.indexOf('(') < 0) trimmed = trimmed.slice(0, -1);
                element.appendChild(document.createTextNode(part.slice(at, pos)));
                var a = el('a', null, trimmed);
                a.href = trimmed;
                a.target = '_blank';
                a.rel = 'noopener noreferrer';
                // a link is no click on the lesson
                a.addEventListener('mousedown', function (e) { e.stopPropagation(); });
                element.appendChild(a);
                at = pos + trimmed.length;
                return url;
            });
            element.appendChild(document.createTextNode(part.slice(at)));
        });
        return element;
    }

    function plural(n, one, many) { return n === 1 ? '1 ' + one : n + ' ' + many; }

    // ---------- the rows ----------
    var rows_ready = false;
    var meta = {};          // offset → {datum, stunde, first (first lesson of its day)}

    function date_label(datum) {
        var d = new Date(datum + 'T12:00:00');
        return { weekday: WEEKDAYS[d.getDay()], date: d.getDate() + '.' + (d.getMonth() + 1) + '.' };
    }

    // "Di, 20.10., 4. Stunde"
    function lesson_label(o) {
        var m = meta[o];
        if (!m) return 'Stunde ' + (o + 1);
        var d = date_label(m.datum);
        return d.weekday + ', ' + d.date + ', ' + m.stunde + '. Stunde';
    }

    function setup_rows() {
        var table = document.querySelector('.lesson_table');
        if (!table) return;
        var spans = window.time_span_for_lesson_offset || {};
        var last_month = null;
        Array.prototype.forEach.call(table.querySelectorAll('tr'), function (tr) {
            if (tr.classList.contains('lesson-table-info-row')) {
                var td = tr.querySelector('td');
                if (tr.classList.contains('today')) {
                    td.textContent = 'Heute';
                    td.id = 'pv_kb_today';
                } else {
                    tr.classList.add('pv-kb-break');
                }
                return;
            }
            if (!tr.classList.contains('lesson')) return;
            var o = $(tr).data('lesson_offset');
            var span = spans[o] || {};
            var cells = tr.children;
            var stunde = parseInt((cells[3] && cells[3].textContent) || '', 10);
            meta[o] = { datum: span.datum, stunde: isNaN(stunde) ? '' : stunde, first: tr.classList.contains('sep') };
            // a heading for each month
            var month = (span.datum || '').substr(0, 7);
            if (month && month !== last_month) {
                last_month = month;
                var head = el('tr', 'pv-kb-month');
                var htd = el('td', null, MONTHS[parseInt(month.substr(5, 2), 10) - 1] + ' ' + month.substr(0, 4));
                htd.colSpan = 11;
                head.appendChild(htd);
                tr.parentNode.insertBefore(head, tr);
            }
            var when = el('td', 'pv-kb-cell pv-kb-when');
            // (empty for the further lessons of a day: in the table the
            // lesson stays in its column)
            var day = el('div', 'pv-kb-day');
            if (meta[o].first && span.datum) {
                var d = date_label(span.datum);
                day.appendChild(el('span', 'pv-weekday', d.weekday));
                day.appendChild(document.createTextNode(' ' + d.date));
            }
            when.appendChild(day);
            when.appendChild(el('div', 'pv-kb-hour', (meta[o].stunde !== '' ? meta[o].stunde + '. Stunde' : '')));
            var what = el('td', 'pv-kb-cell pv-kb-what');
            var nr = el('td', 'pv-kb-cell pv-kb-nr', String(o + 1));
            nr.setAttribute('title', 'Stunde ' + (o + 1) + ' des Kurses');
            tr.appendChild(nr);
            tr.appendChild(when);
            tr.appendChild(what);
            tr.tabIndex = 0;
            tr.setAttribute('aria-label', lesson_label(o));
        });
        add_column_heads(table);
        rows_ready = true;
    }

    // wide lists (preview/lessons.css, container query): the lessons as a
    // table with a sticky row of column headings
    function add_column_heads(table) {
        var thead = table.parentNode.querySelector('thead');
        if (!thead) return;
        var tr = el('tr', 'pv-kb-colhead');
        [['pv-kb-h-nr', 'Nr.'], ['pv-kb-h-when', 'Datum'], ['pv-kb-h-thema', 'Thema'],
            ['pv-kb-h-topic', 'Stundenthema'], ['pv-kb-h-hw', 'Hausaufgaben'], ['pv-kb-h-more', 'Weiteres']
        ].forEach(function (h) {
            var th = el('th', h[0], h[1]);
            th.setAttribute('scope', 'col');
            tr.appendChild(th);
        });
        tr.children[2].appendChild(el('span', 'pv-kb-h-who', ' intern'));
        tr.children[3].appendChild(el('span', 'pv-kb-h-who', ' für SuS'));
        thead.appendChild(tr);
    }

    // a quiet icon in the table's last column (or beside the homework), its
    // meaning as tooltip and for screen readers
    function mark(name, label, count, cls) {
        var s = el('span', 'pv-kb-ic' + (cls ? ' ' + cls : ''));
        s.setAttribute('role', 'img');
        s.setAttribute('title', label);
        s.setAttribute('aria-label', label);
        s.appendChild(icon(name));
        if (count !== undefined && count !== null) s.appendChild(el('span', 'pv-kb-ic-n', String(count)));
        return s;
    }

    // a quiet icon with its label (homework: Nextcloud, Lernraum, Amt), no pill: facts stay quiet
    function chip(name, text, label) {
        var s = el('span', 'pv-kb-tag');
        if (label) s.setAttribute('title', label);
        s.appendChild(icon(name));
        s.appendChild(el('span', null, text));
        return s;
    }

    function line(cls, label, text) {
        var div = el('div', 'pv-kb-line' + (cls ? ' ' + cls : ''));
        if (label) div.appendChild(el('span', 'pv-kb-k', label));
        var v = el('span', 'pv-kb-v');
        append_text(v, text);
        div.appendChild(v);
        return div;
    }

    function render_row(o, tr) {
        var cell = tr.querySelector('.pv-kb-what');
        if (!cell) return;
        cell.textContent = '';
        var i = info(o);
        var thema = str(i.thema);
        var topic = str(i.stundenthema_text);
        var hw = str(i.hausaufgaben_text);
        var amt = str(i.ha_amt_text);
        var notes = str(i.notizen);
        if (thema) {
            var t = el('div', 'pv-kb-title');
            append_text(t, thema);
            cell.appendChild(t);
        }
        if (topic) cell.appendChild(line('pv-kb-topic', 'Stundenthema', topic));
        var est = str(i.homework_est_time);
        if (hw || amt || i.homework_nc || i.homework_lr) {
            var where = [];
            if (i.homework_nc) where.push('in der Nextcloud');
            if (i.homework_lr) where.push('im Lernraum');
            var h = line('pv-kb-hw', 'Hausaufgaben', hw);
            // the list: in words after the text
            var extra = [];
            if (amt) extra.push('Amt: ' + amt);
            if (where.length) extra.push(where.join(' und '));
            if (est && hw) extra.push('etwa ' + est + ' Minuten');
            if (extra.length) {
                var x = el('span', 'pv-kb-extra');
                append_text(x, (hw ? ', ' : '') + extra.join(', '));
                h.appendChild(x);
            }
            // the table: the time quietly, the places as chips
            var hm = el('span', 'pv-kb-hw-meta');
            if (est && hw) hm.appendChild(el('span', 'pv-kb-min', 'etwa ' + est + ' Min.'));
            if (i.homework_nc) hm.appendChild(chip('cloud', 'Nextcloud', 'Hausaufgaben in der Nextcloud'));
            if (i.homework_lr) hm.appendChild(chip('school', 'Lernraum', 'Hausaufgaben im Lernraum'));
            if (amt) hm.appendChild(chip('user', 'Amt: ' + amt));
            if (hm.firstChild) h.appendChild(hm);
            cell.appendChild(h);
        }
        if (notes) cell.appendChild(line('pv-kb-note', 'Notiz', notes));
        // facts in a quiet line (the list) or as icons (the table)
        var facts = [];
        var marks = el('div', 'pv-kb-marks');
        if (notes) marks.appendChild(mark('note', 'Notiz: ' + notes, null, 'pv-kb-ic-note'));
        if (i.lesson_fixed) {
            facts.push('fester Termin');
            marks.appendChild(mark('calendar-check', 'Fester Termin'));
        }
        if (i.lesson_jitsi) {
            facts.push(i.breakout_rooms ? 'Jitsi mit Gruppenräumen' : 'Jitsi');
            marks.appendChild(mark(i.breakout_rooms ? 'users-group' : 'video', i.breakout_rooms ? 'Jitsi mit Gruppenräumen' : 'Jitsi'));
        }
        if (i.booked_tablet) {
            facts.push('Tablet ' + i.booked_tablet.tablet_id);
            marks.appendChild(mark('device-tablet', 'Tablet ' + i.booked_tablet.tablet_id + ' gebucht'));
        }
        if (i.booked_tablet_sets) {
            var devices = i.booked_tablet_sets_tablet_count || 0;
            facts.push(plural(devices, 'Gerät gebucht', 'Geräte gebucht'));
            marks.appendChild(mark('device-laptop', plural(devices, 'Gerät gebucht', 'Geräte gebucht'), devices));
        }
        if (i.lesson_nc) {
            facts.push('Aufgaben in der Nextcloud');
            marks.appendChild(mark('cloud', 'Aufgaben in der Nextcloud'));
        }
        if (i.lesson_lr) {
            facts.push('Aufgaben im Lernraum');
            marks.appendChild(mark('school', 'Aufgaben im Lernraum'));
        }
        var comments = (window.lesson_data[o] || {}).comments || {};
        var text_n = 0, audio_n = 0;
        Object.keys(comments).forEach(function (email) {
            if (str(comments[email].text_comment)) text_n += 1;
            if (str(comments[email].audio_comment_tag)) audio_n += 1;
        });
        if (text_n) {
            facts.push(plural(text_n, 'Kommentar', 'Kommentare'));
            marks.appendChild(mark('message', plural(text_n, 'Kommentar', 'Kommentare'), text_n));
        }
        if (audio_n) {
            facts.push(plural(audio_n, 'Audiokommentar', 'Audiokommentare'));
            marks.appendChild(mark('microphone', plural(audio_n, 'Audiokommentar', 'Audiokommentare'), audio_n));
        }
        var sus = (((window.lesson_data[o] || {}).feedback || {}).sus) || {};
        var fb_n = Object.keys(sus).length;
        if (fb_n) {
            facts.push(plural(fb_n, 'Rückmeldung', 'Rückmeldungen'));
            marks.appendChild(mark('mood-smile', plural(fb_n, 'Rückmeldung', 'Rückmeldungen') + ' von Schülerinnen und Schülern', fb_n));
        }
        if (facts.length) cell.appendChild(el('div', 'pv-kb-facts', facts.join(', ')));
        if (marks.firstChild) cell.appendChild(marks);
        if (!cell.firstChild) cell.appendChild(el('div', 'pv-kb-empty', 'Noch nichts eingetragen'));
        tr.classList.toggle('pv-kb-blank', !thema && !topic);
    }

    function render_rows() {
        if (!rows_ready) return;
        Object.keys(window.row_for_lesson_offset).forEach(function (o) {
            render_row(parseInt(o, 10), window.row_for_lesson_offset[o][0]);
        });
    }

    var orig_update_table = window.update_table;
    var first_render = true;
    window.update_table = function () {
        var r = orig_update_table.apply(this, arguments);
        if (!rows_ready) setup_rows();
        render_rows();
        if (first_render) {
            first_render = false;
            // after today's page selected the lessons from the address (#3,4)
            // and scrolled (with a short animation)
            setTimeout(after_first_render, 120);
        }
        return r;
    };

    // ---------- selection ----------
    function selected_offsets() {
        return Object.keys(window.row_for_lesson_offset).filter(function (o) {
            return window.row_for_lesson_offset[o].hasClass('selected');
        }).map(function (o) { return parseInt(o, 10); }).sort(function (a, b) { return a - b; });
    }

    function nudge() {
        // unsaved changes: today's page shakes the buttons; here they say so
        if (window.pending_changes && pane) pane.classList.add('pv-kb-attention');
    }

    function select_only(o) {
        if (window.pending_changes) { nudge(); return false; }
        $('.lesson_table tr').removeClass('current').removeClass('selected');
        window.row_for_lesson_offset[o].addClass('current').addClass('selected');
        window.cursor = o;
        window.selection_updated();
        return true;
    }

    // a click in a menu, a dialog or the sheet is no click "beside the
    // table" (today's page then clears the selection): keep it
    var keep_selection = false;
    var last_selection = [];
    document.addEventListener('mousedown', function (e) {
        if (!e.target.closest) return;
        if (e.target.closest('.pv-amenu, .pv-amenu-veil, .modal, .modal-backdrop, .pv-kb-sheet, .pv-kb-veil, .pv-kb-head, .api_messages')) {
            keep_selection = true;
            setTimeout(function () { keep_selection = false; }, 0);
        }
    }, true);

    var orig_selection_updated = window.selection_updated;
    window.selection_updated = function () {
        if (keep_selection && selected_offsets().length === 0 && last_selection.length) {
            last_selection.forEach(function (o) {
                if (window.row_for_lesson_offset[o]) window.row_for_lesson_offset[o].addClass('selected');
            });
        }
        var r = orig_selection_updated.apply(this, arguments);
        last_selection = selected_offsets();
        pane_title();
        if (last_selection.length === 0 && open) close_sheet(false);
        return r;
    };

    var orig_update_changes = window.update_changes;
    window.update_changes = function () {
        var r = orig_update_changes.apply(this, arguments);
        if (pane) {
            pane.classList.toggle('pv-kb-dirty', !!window.pending_changes);
            if (!window.pending_changes) pane.classList.remove('pv-kb-attention');
        }
        return r;
    };

    // ---------- the pane ----------
    var pane = null, column = null, head = null, title = null, sub = null, foot = null;
    var hint = null, umplanen = null, close_button = null;

    function pane_title() {
        if (!title) return;
        var sel = selected_offsets();
        document.body.classList.toggle('pv-kb-none', sel.length === 0);
        if (sel.length === 0) {
            title.textContent = 'Keine Stunde ausgewählt';
            sub.textContent = '';
        } else if (sel.length === 1) {
            title.textContent = lesson_label(sel[0]);
            sub.textContent = 'Stunde ' + (sel[0] + 1) + ' im Kurs';
        } else {
            title.textContent = sel.length + ' Stunden ausgewählt';
            var a = meta[sel[0]], b = meta[sel[sel.length - 1]];
            sub.textContent = (a && b && a.datum && b.datum)
                ? (date_label(a.datum).weekday + ', ' + date_label(a.datum).date + ' bis ' + date_label(b.datum).weekday + ', ' + date_label(b.datum).date + ', gleiche Einträge für alle')
                : '';
        }
        if (umplanen) umplanen.disabled = $('.bu-umplanen').prop('disabled');
    }

    function umplanen_menu(e) {
        var sel = selected_offsets();
        if (sel.length === 0) return;
        var what = sel.length === 1 ? 'Diese Stunde' : sel.length + ' Stunden';
        pv_list.menu(e.currentTarget, 'Umplanen', [
            { label: 'Eine Stunde oberhalb einfügen', run: function () { $('.bu-insert-lesson-above').first().triggerHandler('click'); } },
            { label: 'Doppelstunde oberhalb einfügen', run: function () { $('.bu-insert-2-lesson-above').first().triggerHandler('click'); } },
            {
                label: what + ' aus dem Verlauf entfernen', danger: true, run: function () {
                    dashboardConfirm((sel.length === 1
                        ? 'Die Einträge dieser Stunde (Thema, Hausaufgaben, Notizen, Kommentare an Schülerinnen und Schüler) werden gelöscht, alle folgenden Einträge rücken eine Stunde nach vorn.'
                        : 'Die Einträge dieser ' + sel.length + ' Stunden (Thema, Hausaufgaben, Notizen, Kommentare an Schülerinnen und Schüler) werden gelöscht, alle folgenden Einträge rücken nach vorn.'),
                        function () { $('.bu-delete-lesson').first().triggerHandler('click'); },
                        { title: what + ' entfernen?', confirm: 'Entfernen', danger: true });
                }
            }
        ], e.detail === 0);
    }

    function build_pane() {
        pane = document.querySelector('.lesson_pane');
        if (!pane) return;
        column = pane.parentNode;
        column.classList.add('pv-kb-col');
        pane.setAttribute('aria-labelledby', 'pv_kb_pane_title');

        head = el('div', 'pv-kb-pane-head');
        var titles = el('div', 'pv-kb-pane-titles');
        title = el('h3', 'pv-kb-pane-title', 'Keine Stunde ausgewählt');
        title.id = 'pv_kb_pane_title';
        sub = el('div', 'pv-kb-pane-sub');
        titles.appendChild(title);
        titles.appendChild(sub);
        // unsaved changes: said in words below the title (the buttons at the
        // foot need the room)
        titles.appendChild(el('div', 'pv-kb-dirty-label', 'Noch nicht gespeichert'));
        close_button = el('button', 'pv-kb-close');
        close_button.type = 'button';
        close_button.id = 'bu_kb_close';
        close_button.setAttribute('aria-label', 'Schließen');
        close_button.setAttribute('title', 'Schließen');
        close_button.appendChild(icon('x'));
        close_button.addEventListener('click', function () { request_close(false); });
        head.appendChild(titles);
        head.appendChild(close_button);
        pane.insertBefore(head, pane.firstChild);

        hint = el('p', 'pv-kb-hint', 'Wähl links eine Stunde aus, um Thema, Stundenthema, Hausaufgaben und Notizen einzutragen. Mit gedrückter Umschalt- oder Strg-Taste wählst du mehrere Stunden auf einmal.');
        head.parentNode.insertBefore(hint, head.nextSibling);

        // the buttons at the bottom, always in view: Umplanen, Verwerfen, Speichern
        var buttons = pane.querySelector('.bu-save-discard-container');
        foot = el('div', 'pv-kb-pane-foot');
        umplanen = el('button', 'btn pv-kb-umplanen');
        umplanen.type = 'button';
        umplanen.id = 'bu_kb_umplanen';
        umplanen.setAttribute('aria-haspopup', 'menu');
        umplanen.appendChild(el('span', null, 'Umplanen'));
        umplanen.appendChild(icon('chevron-down'));
        umplanen.addEventListener('click', umplanen_menu);
        foot.appendChild(umplanen);
        if (buttons) {
            ['.bu-discard-changes', '.bu-save-changes'].forEach(function (sel) {
                var b = buttons.querySelector(sel);
                // the icon is hidden here: without the spaces that followed it,
                // otherwise the label sits off centre
                Array.prototype.forEach.call(b.childNodes, function (n) {
                    if (n.nodeType === 3) n.nodeValue = n.nodeValue.replace(/^[\s\u00a0]+/, '');
                });
                foot.appendChild(b);
            });
            buttons.hidden = true;
        }
        pane.appendChild(foot);

        // the items scroll between the title and the buttons
        var items = pane.querySelector('.pane_items');
        var scroller = el('div', 'pv-kb-pane-body');
        pane.insertBefore(scroller, foot);
        [hint, pane.querySelector('.status_label')].forEach(function (x) { if (x) scroller.appendChild(x); });
        if (items) scroller.appendChild(items);
        // what follows the items (Kursbuch-PDF) moves to the header
        Array.prototype.slice.call(pane.children).forEach(function (c) {
            if (c !== head && c !== scroller && c !== foot && c !== buttons) scroller.appendChild(c);
        });
        if (buttons) pane.appendChild(buttons);

        // every change counts at once (today's page listens to keys and
        // leaving a field; pasting with the mouse changed nothing until then)
        pane.addEventListener('input', function (e) {
            if (!e.target.classList || !e.target.classList.contains('form-control')) return;
            // several lessons: what is typed replaces "Einträge unverändert lassen"
            var dd = document.getElementById('dd_' + String(e.target.id).replace('ti_', ''));
            if (dd) $(dd).find('.dropdown-item').removeClass('checked');
            window.update_changes();
        });

        // "verschiedene Werte" (several lessons with different entries): a
        // Tabler chevron instead of Bootstrap's drawn caret
        pane.querySelectorAll('.dropdown-toggle').forEach(function (b) {
            b.classList.add('pv-kb-mixed');
            b.appendChild(icon('chevron-down'));
        });
        // the labels of the parts: what students see, what stays internal
        pane.querySelectorAll('.pane_items label .text-muted').forEach(function (s) {
            s.classList.add('pv-kb-who');
        });
    }

    // ---------- "du" (doc/Gestaltung.md, Sprache) ----------
    // the page's own texts as the new design says them
    function say(selector, text) {
        var e = document.querySelector(selector);
        if (e) e.textContent = text;
    }

    function du_texts() {
        say('#breakoutRoomsModal .modal-body p', 'Zieh Schülerinnen und Schüler hin und her, um sie in Gruppen einzuteilen.');
        say('#emailListModal .modal-body p', 'Bitte verwende die Adressen nach Möglichkeit im BCC.');
        var topic = document.querySelector('#ti_stundenthema_text');
        var expl = topic && topic.parentNode.querySelector('.explanation');
        if (expl) expl.textContent = 'Hier kannst du Schülerinnen und Schülern, die nicht an der Stunde teilnehmen können, mitteilen, was behandelt wird, oder Arbeitsanweisungen geben. Alle Schülerinnen und Schüler des Kurses sehen das, jeweils eine Woche im Voraus.';
        var fixed = document.querySelector('#ti_lesson_fixed');
        if (fixed && fixed.nextElementSibling) fixed.nextElementSibling.textContent = 'Du bekommst eine E-Mail, falls sich die Stunde verschiebt.';
        var fb = document.querySelector('#bu_feedback');
        if (fb && fb.nextElementSibling) fb.nextElementSibling.textContent = 'Hier kannst du Feedback zur Stunde oder zu den Hausaufgaben geben.';
        // the comment for one student: the name stays an element (the page fills it)
        var rec = document.querySelector('#recording_row .explanation');
        var name = rec && rec.querySelector('.first_name_here');
        if (rec && name) {
            rec.textContent = '';
            rec.appendChild(document.createTextNode('Hier kannst du einen Kommentar zur Stunde oder zur Hausaufgabe hinterlassen. '));
            rec.appendChild(name);
            rec.appendChild(document.createTextNode(' sieht einen freigegebenen Kommentar erst nach fünf Minuten, falls du ihn doch zurückziehen möchtest.'));
        }
    }

    // booked devices: the names as text, the note with "du"
    var orig_tablet_status = window.update_tablet_set_booking_status;
    if (typeof orig_tablet_status === 'function') {
        window.update_tablet_set_booking_status = function () {
            var r = orig_tablet_status.apply(this, arguments);
            var box = document.querySelector('.tablet-set-booking-status');
            var booked = window.booked_tablet_sets_config || [];
            if (box && booked.length) {
                box.textContent = '';
                box.appendChild(document.createTextNode('Für diese Stunde reserviert: '));
                booked.forEach(function (x, i) {
                    if (i > 0) box.appendChild(document.createTextNode(', '));
                    box.appendChild(el('b', null, x));
                });
                box.appendChild(document.createTextNode('. Die Buchung verfällt, falls sich die Stunde durch den Vertretungsplan verschiebt; du kannst dann neu buchen.'));
            }
            return r;
        };
    }

    // ---------- the header ----------
    function build_head() {
        var container = document.querySelector('.container-fluid.solid');
        if (!container) return;
        container.classList.add('pv-kb');
        var bar = el('div', 'pv-kb-head');
        var titles = el('div', 'pv-kb-head-titles');
        var h2 = el('h2', null, data.title);
        titles.appendChild(h2);
        var n = (window.schueler_for_lesson || []).length;
        titles.appendChild(el('div', 'pv-kb-head-facts', 'Kursbuch, ' + plural(n, 'Schülerin oder Schüler', 'Schülerinnen und Schüler')));
        bar.appendChild(titles);
        var actions = el('div', 'pv-kb-head-actions');
        var today = el('button', 'btn pv-kb-today');
        today.type = 'button';
        today.id = 'bu_kb_today';
        today.appendChild(icon('calendar'));
        today.appendChild(el('span', null, 'Heute'));
        today.addEventListener('click', function () { scroll_to_today(true); });
        actions.appendChild(today);
        var pdf = document.querySelector('.lesson_pane a[href^="/api/kursbuch_pdf/"]');
        if (pdf) {
            var label = pdf.previousElementSibling;
            // "Kursbuch" label and <br> above the link
            while (label && label.tagName !== 'LABEL') label = label.previousElementSibling;
            if (label) {
                if (label.nextElementSibling && label.nextElementSibling.tagName === 'BR') label.nextElementSibling.remove();
                label.remove();
            }
            pdf.className = 'btn pv-kb-pdf';
            pdf.removeAttribute('style');
            pdf.id = 'bu_kb_pdf';
            pdf.textContent = '';
            pdf.appendChild(icon('file-type-pdf'));
            pdf.appendChild(el('span', null, 'PDF'));
            pdf.setAttribute('title', 'Kursbuch als PDF herunterladen');
            pdf.setAttribute('aria-label', 'Kursbuch als PDF herunterladen');
            actions.appendChild(pdf);
        }
        bar.appendChild(actions);
        // above the list (the pane beside it reaches up to the top)
        var list = container.querySelector('.lc_table');
        if (list) list.insertBefore(bar, list.firstChild);
        else container.insertBefore(bar, container.firstChild);
    }

    function scroll_to_today(smooth) {
        var t = document.getElementById('pv_kb_today');
        if (!t) {
            // no line for today (all lessons are past or ahead): the next lesson
            return;
        }
        t.closest('tr').scrollIntoView({ block: 'start', behavior: smooth ? 'smooth' : 'auto' });
    }

    // ---------- tablets and phones: the pane as a sheet ----------
    var sheet = null, veil = null, open = false, opener = null;
    var LAYER = 'kb-lesson';

    function place_pane() {
        if (!pane) return;
        if (OVERLAY.matches) {
            if (pane.parentNode !== sheet) sheet.appendChild(pane);
        } else {
            if (open) close_sheet(false, true);
            if (pane.parentNode !== column) column.appendChild(pane);
        }
        document.body.classList.toggle('pv-kb-overlay', OVERLAY.matches);
    }

    // keep the page still while the sheet is open (an action menu that
    // opens and closes on top of it would otherwise free it)
    new MutationObserver(function () {
        if (open && !document.body.classList.contains('pv-sheet-open')) document.body.classList.add('pv-sheet-open');
    }).observe(document.body, { attributes: true, attributeFilter: ['class'] });

    function open_sheet() {
        if (!OVERLAY.matches || open || selected_offsets().length === 0) return;
        open = true;
        opener = document.activeElement;
        sheet.hidden = false;
        veil.hidden = false;
        document.body.classList.add('pv-kb-open');
        document.body.classList.add('pv-sheet-open');
        if (window.pv_back) window.pv_back.opened(LAYER, function () { request_close(true); });
        pane.querySelector('.pv-kb-pane-body').scrollTop = 0;
        // the sheet itself (a focus ring on the close button would look like a choice)
        sheet.focus({ preventScroll: true });
    }

    // from_back: the history entry is gone already
    function close_sheet(from_back, keep) {
        if (!open) return;
        open = false;
        sheet.hidden = true;
        veil.hidden = true;
        document.body.classList.remove('pv-kb-open');
        document.body.classList.remove('pv-sheet-open');
        if (!from_back && window.pv_back) window.pv_back.closed(LAYER);
        if (!keep && !window.pending_changes && selected_offsets().length) {
            $('.lesson_table tr').removeClass('current').removeClass('selected');
            window.cursor = null;
            window.selection_updated();
        }
        if (opener && document.body.contains(opener)) opener.focus({ preventScroll: true });
    }

    // run fn once the dialog that just closed took its history entry back
    // (pv_back goes back asynchronously; closing the sheet before that would
    // leave the sheet's entry behind)
    function after_dialog_back(fn) {
        var done = false;
        function go() {
            if (done) return;
            done = true;
            window.removeEventListener('popstate', go);
            setTimeout(fn, 0);
        }
        window.addEventListener('popstate', go);
        setTimeout(go, 400);
    }

    function ask_discard() {
        dashboardConfirm('Deine Änderungen an dieser Stunde sind noch nicht gespeichert.', function () {
            window.discard_changes();
            after_dialog_back(function () { close_sheet(false); });
        }, { title: 'Änderungen verwerfen?', confirm: 'Verwerfen', cancel: 'Weiter bearbeiten', danger: true });
    }

    function request_close(from_back) {
        if (!open) return;
        if (!window.pending_changes) { close_sheet(from_back); return; }
        if (!from_back) { ask_discard(); return; }
        // back took the history entry: the sheet stays open until decided.
        // Its entry comes back after pv_back's popstate handler is done (from
        // inside it, the handler would close the sheet again and again).
        setTimeout(function () {
            if (!open) return;
            if (window.pv_back) window.pv_back.opened(LAYER, function () { request_close(true); });
            ask_discard();
        }, 0);
    }

    // phones and tablets: pulled down (by its head, or anywhere while its
    // content is scrolled to the top), the sheet closes like every sheet –
    // with unsaved changes it springs back and asks first
    var drag = null;
    function sheet_shift(dy, ms) {
        sheet.style.transition = ms ? 'transform ' + ms + 'ms ease-out' : 'none';
        sheet.style.transform = dy ? 'translateY(' + dy + 'px)' : '';
    }
    document.addEventListener('touchstart', function (e) {
        drag = null;
        if (!open || !sheet || e.touches.length !== 1 || !sheet.contains(e.target)) return;
        if (e.target.closest('textarea, input, select, [contenteditable], .note-editor, .pv-amenu')) return;
        var body = pane.querySelector('.pv-kb-pane-body');
        if (body && body.contains(e.target) && body.scrollTop > 0) return;
        if (pane.querySelector('.pv-kb-pane-foot') && pane.querySelector('.pv-kb-pane-foot').contains(e.target)) return;
        drag = { y: e.touches[0].clientY, t: Date.now(), dy: 0, dragging: false };
    }, { passive: true });
    document.addEventListener('touchmove', function (e) {
        if (!drag || e.touches.length !== 1) return;
        var dy = e.touches[0].clientY - drag.y;
        if (!drag.dragging) {
            if (dy < -8) { drag = null; return; }
            if (dy < 8) return;
            drag.dragging = true;
        }
        e.preventDefault();
        drag.dy = Math.max(0, dy);
        sheet_shift(drag.dy, 0);
        // the veil as strong as the part of the sheet still showing
        veil_fade(Math.max(0, 1 - drag.dy / (sheet.offsetHeight || 1)), 0);
    }, { passive: false });
    function veil_fade(opacity, ms) {
        veil.style.transition = ms ? 'opacity ' + ms + 'ms ease-out' : 'none';
        veil.style.opacity = opacity === null ? '' : String(opacity);
    }
    function drag_end() {
        if (!drag) return;
        var d = drag;
        drag = null;
        if (!d.dragging) return;
        var quick = Date.now() - d.t < 250 && d.dy > 30;
        if ((d.dy > 90 || quick) && !window.pending_changes) {
            sheet_shift(sheet.offsetHeight + 20, 180);
            veil_fade(0, 180);
            setTimeout(function () {
                close_sheet(false);
                sheet_shift(0, 0);
                veil_fade(null, 0);
            }, 180);
        } else {
            sheet_shift(0, 160);
            veil_fade(null, 160);
            if (d.dy > 90 || quick) request_close(false);
        }
    }
    document.addEventListener('touchend', drag_end);
    document.addEventListener('touchcancel', drag_end);

    function build_sheet() {
        veil = el('div', 'pv-kb-veil');
        veil.hidden = true;
        veil.addEventListener('click', function () { request_close(false); });
        sheet = el('div', 'pv-kb-sheet');
        sheet.hidden = true;
        sheet.setAttribute('role', 'dialog');
        sheet.setAttribute('aria-modal', 'true');
        sheet.tabIndex = -1;
        sheet.setAttribute('aria-labelledby', 'pv_kb_pane_title');
        // inside the page's container: its button styles apply there too
        var host = document.getElementById('main_container') || document.body;
        host.appendChild(veil);
        host.appendChild(sheet);
        // Escape closes the sheet (not while a dialog or menu is open above it)
        document.addEventListener('keydown', function (e) {
            if (e.key !== 'Escape' || !open) return;
            if (document.querySelector('.modal.show, .pv-amenu')) return;
            e.preventDefault();
            request_close(false);
        });
        if (OVERLAY.addEventListener) OVERLAY.addEventListener('change', place_pane);
        else OVERLAY.addListener(place_pane);
        // saving closes the sheet
        $(document).ajaxSuccess(function (e, xhr, settings) {
            if (open && settings && settings.url === '/api/save_lesson_data') {
                setTimeout(function () { if (!window.pending_changes) close_sheet(false, true); }, 0);
            }
        });
        place_pane();
    }

    // ---------- clicks and keys on the rows ----------
    function bind_rows() {
        var table = document.querySelector('.lesson_table');
        if (!table) return;
        // another lesson while there are changes: today's page keeps the
        // selection (and shakes its hidden buttons); the note says why
        table.addEventListener('mousedown', function (e) {
            if (e.target.closest && e.target.closest('tr.lesson')) nudge();
        }, true);
        table.addEventListener('click', function (e) {
            if (e.target.closest('a')) return;
            var tr = e.target.closest('tr.lesson');
            if (!tr || !window.can_select) return;
            if (!OVERLAY.matches) return;
            var o = $(tr).data('lesson_offset');
            // touch: today's page may not have seen a pressed button
            if (!tr.classList.contains('selected') && !select_only(o)) return;
            open_sheet();
        });
        table.addEventListener('keydown', function (e) {
            var tr = e.target.closest && e.target.closest('tr.lesson');
            if (!tr || e.target !== tr || !window.can_select) return;
            var o = $(tr).data('lesson_offset');
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                if (select_only(o)) {
                    if (OVERLAY.matches) open_sheet();
                }
            } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                var next = window.row_for_lesson_offset[o + (e.key === 'ArrowDown' ? 1 : -1)];
                if (!next) return;
                e.preventDefault();
                next[0].focus();
                if (!OVERLAY.matches) select_only(o + (e.key === 'ArrowDown' ? 1 : -1));
            }
        });
    }

    function after_first_render() {
        var sel = selected_offsets();
        if (sel.length) {
            var tr = window.row_for_lesson_offset[sel[0]];
            if (tr) tr[0].scrollIntoView({ block: 'center' });
            open_sheet();
        } else {
            scroll_to_today(false);
        }
    }

    function start() {
        build_head();
        build_pane();
        build_sheet();
        bind_rows();
        du_texts();
        pane_title();
        // the other dialogs of the page: sheets on phones
        ['feedbackModal', 'breakoutRoomsModal', 'tabletSetModal', 'emailListModal'].forEach(function (id) {
            var m = document.getElementById(id);
            if (m) m.classList.add('pv-sheet', 'pv-kb-modal');
        });
    }

    // after today's page bound its handlers (its DOMContentLoaded comes first)
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
    else start();
})();
