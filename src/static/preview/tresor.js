/* Neues Design (Vorschau): the Datentresor (tresor.html and the pages that
   include _tresor_public_template.html: Übersicht, Zeugnisformulare,
   AT-Notizen, Zeugnisdruck, Anlage Sozialverhalten). The template loads this
   file only for those who see the new design; the old design stays as it is.

   - The tresor's own toolbar (a fixed bar under today's top navigation)
     becomes a row of quiet tabs at the top of the page's panel, the time
     left and »Abmelden« at its end (doc/Gestaltung.md, »Bereiche mit eigener
     Navigation«). The countdown and »Abmelden« are the template's own
     buttons, moved, so that their handlers keep working.
   - Today's Zeugniskonferenzen (admins, on conference days) move into the
     panel as a section instead of a second panel.
   - Without Zeugnislisten (outside the Zeugnis period) the pages said
     nothing at all: the Übersicht stayed an empty panel. Here they say so.
   - The tresor's login (choosing the second factor, the code, the hotline)
     and its texts: »du« instead of »Sie«, left aligned, a calm notice when
     the tresor cannot be reached.
   Styles: preview/tresor.css (everything under .pv-tresor). */
(function () {
    'use strict';
    var body = document.body;
    if (!body || !body.classList.contains('ui-preview')) return;
    body.classList.add('pv-tresor');

    var PATH = location.pathname;

    function q(sel, root) { return (root || document).querySelector(sel); }
    function qa(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

    function el(tag, cls, text) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    }

    function icon(name) {
        var i = el('i', 'ti ti-' + name);
        i.setAttribute('aria-hidden', 'true');
        return i;
    }

    // a paragraph's content anew: strings as text, nodes (the page's own
    // links, with their handlers) as they are
    function compose(target, parts) {
        if (!target) return;
        target.textContent = '';
        parts.forEach(function (part) {
            if (part === null || part === undefined) return;
            target.append(typeof part === 'string' ? document.createTextNode(part) : part);
        });
    }

    // replaces whole sentences inside single text nodes (whitespace as the
    // browser shows it); a text that has changed in the page stays as it is
    function retext(root, pairs) {
        if (!root) return;
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        var nodes = [];
        while (walker.nextNode()) nodes.push(walker.currentNode);
        nodes.forEach(function (node) {
            var t = node.nodeValue.replace(/\s+/g, ' ');
            var hit = false;
            pairs.forEach(function (pair) {
                if (t.indexOf(pair[0]) >= 0) {
                    t = t.split(pair[0]).join(pair[1]);
                    hit = true;
                }
            });
            if (hit) node.nodeValue = t;
        });
    }

    function note(text, cls) {
        var p = el('p', 'pv-tresor-note' + (cls ? ' ' + cls : ''), text);
        return p;
    }

    // the page's panel: the first white container after the template
    function page_panel() {
        return q('#main_container > .container.bg-white');
    }

    // ---------- the tabs and the session ----------
    function build_nav(panel) {
        var old = q('#submenu');
        if (!old || !panel) return;
        var nav = el('div', 'pv-tresor-nav');
        nav.setAttribute('role', 'navigation');
        nav.setAttribute('aria-label', 'Datentresor');
        var tabs = el('ul', 'pv-tresor-tabs');
        qa('ul.submenu > li > a', old).forEach(function (a) {
            var li = a.parentElement;
            if (li.style.display === 'none') return;
            var href = a.getAttribute('href');
            var item = el('li');
            var link = el('a', 'pv-tresor-tab', a.textContent.replace(/\s+/g, ' ').trim());
            link.setAttribute('href', href);
            if (href === PATH) link.setAttribute('aria-current', 'page');
            item.append(link);
            tabs.append(item);
        });
        var session = el('div', 'pv-tresor-session');
        var time = q('#bu-refresh-second-factor');
        var left = q('#sf-time-left');
        if (time && left) {
            time.className = 'pv-tresor-time';
            time.removeAttribute('style');
            time.type = 'button';
            time.title = 'So lange bleibt der Datentresor offen. Klick, um die Zeit zu verlängern.';
            left.removeAttribute('style');
            left.classList.add('pv-tresor-time-left');
            compose(time, [icon('clock'), el('span', 'pv-tresor-time-label', 'noch'), left]);
            session.append(time);
        }
        var logout = q('#bu-delete-second-factor');
        if (logout) {
            logout.className = 'pv-tresor-logout';
            logout.removeAttribute('style');
            logout.type = 'button';
            logout.title = 'Vom Datentresor abmelden';
            compose(logout, [icon('logout'), el('span', null, 'Abmelden')]);
            session.append(logout);
        }
        nav.append(tabs, session);
        panel.insertBefore(nav, panel.firstChild);
        // phones: the current tab in view (the row scrolls sideways)
        var current = q('[aria-current]', tabs);
        if (current && tabs.scrollWidth > tabs.clientWidth) {
            var dx = current.getBoundingClientRect().right - tabs.getBoundingClientRect().right;
            if (dx > 0) tabs.scrollLeft += dx + 16;
        }

        // the template hides its bar when the tresor cannot be reached and
        // shows it only with a second factor: the tabs follow it
        function sync() {
            nav.hidden = getComputedStyle(old).display === 'none';
        }
        sync();
        new MutationObserver(sync).observe(old, { attributes: true, attributeFilter: ['style', 'class'] });
    }

    // ---------- today's Zeugniskonferenzen (admins) ----------
    function move_konferenzen(panel) {
        var here = q('#div_zeugniskonferenzen');
        var box = here && here.closest('.container');
        if (!box || !panel || box === panel) return;
        box.classList.add('pv-tresor-konferenz');
        box.classList.remove('container');
        var nav = q('.pv-tresor-nav', panel);
        panel.insertBefore(box, nav ? nav.nextSibling : panel.firstChild);
        compose(q('p', box), ['Klick auf eine Klasse, wenn ihre Zeugniskonferenz beginnt, und auf »Beenden«, wenn sie vorbei ist.']);
    }

    // ---------- the pages ----------
    function no_zeugnislisten() {
        return typeof window.zeugnisliste_for_klasse === 'object' && window.zeugnisliste_for_klasse !== null &&
            Object.keys(window.zeugnisliste_for_klasse).length === 0;
    }

    var EMPTY_LISTS = 'Gerade gibt es keine Zeugnislisten. Sie erscheinen hier, sobald die Zeugniszeit beginnt.';

    function page_uebersicht(panel) {
        var here = q('#zeugnisuebersicht-here');
        if (!here) return;
        here.classList.add('pv-tresor-scroll');
        if (no_zeugnislisten()) here.after(note(EMPTY_LISTS, 'pv-tresor-empty'));
        // written once the values have come from the tresor
        new MutationObserver(function () {
            retext(here, [['Sie haben bisher ', 'Du hast bisher '], [' benötigten Eintragungen vorgenommen.', ' nötigen Eintragungen gemacht.']]);
        }).observe(here, { childList: true, subtree: true });
    }

    function page_formulare(panel) {
        var forms = q('#zeugnisformulare_table_here');
        var lists = q('#zeugnislisten_table_here');
        if (forms) forms.classList.add('pv-tresor-scroll');
        if (!lists) return;
        lists.classList.add('pv-tresor-scroll');
        var hint = lists.previousElementSibling;
        if (hint && hint.tagName === 'P') {
            compose(hint, ['Klick auf ein Kürzel, um Eintragungen zu delegieren, und gib dann ein Kürzel oder mehrere, durch Kommas getrennt, ein.']);
            if (no_zeugnislisten()) hint.hidden = true;
        }
        if (no_zeugnislisten()) lists.after(note(EMPTY_LISTS, 'pv-tresor-empty'));
    }

    function page_at(panel) {
        var buttons = q('#klassen_buttons_here');
        var intro = buttons && buttons.previousElementSibling;
        if (intro && intro.tagName === 'P') compose(intro, ['Wähl eine Lerngruppe, deren AT-Notizen du sehen möchtest.']);
        var notes = q('#noten_here');
        if (notes) notes.classList.add('pv-tresor-scroll');
        window.addEventListener('load', function () {
            if (buttons && buttons.children.length === 0)
                buttons.append(note('Für dich gibt es hier keine Lerngruppen mit AT-Notizen.', 'pv-tresor-empty'));
        });
    }

    function page_druck(panel) {
        var buttons = q('#klassen_buttons_here');
        var hint = buttons && buttons.previousElementSibling;
        if (hint && hint.tagName === 'P') {
            hint.classList.add('pv-tresor-hint');
            compose(hint, [el('b', null, 'Wichtig:'), ' Druck vor den Zeugnissen eine Probeseite, damit du sicher bist, dass du den richtigen Drucker verwendest.']);
        }
        var list = q('#zeugnisse_here');
        if (list) list.classList.add('pv-tresor-scroll');
        if (no_zeugnislisten()) {
            body.classList.add('pv-tresor-nolists');
            if (buttons) buttons.after(note('Gerade gibt es keine Zeugnislisten und damit nichts zu drucken. Sobald die Zeugniszeit beginnt, wählst du hier eine Klasse.', 'pv-tresor-empty'));
        }
    }

    function page_sozialverhalten(panel) {
        retext(panel, [
            ['Hinweis: Tragen Sie ein »x« ein, wenn', 'Hinweis: Trag ein »x« ein, wenn'],
            ['Tipp: Nutzen Sie die Tasten', 'Tipp: Nutz die Tasten'],
            ['Wählen Sie hier, ob Sie dabei von oben nach unten oder von links nach rechts springen möchten:', 'Wähl hier, ob du dabei von oben nach unten oder von links nach rechts springen möchtest:'],
            ['Bitte wählen Sie eine Klasse, für die Sie Bewertungen eintragen möchten.', 'Wähl eine Klasse, für die du Bewertungen eintragen möchtest.'],
            ['Hinweis: Nutzen Sie diese Schaltfläche, um die Tabelle vor versehentlichen Änderungen zu schützen. Sobald Sie Werte ändern, sind diese automatisch gespeichert',
             'Hinweis: Mit diesem Knopf schützt du die Tabelle vor versehentlichen Änderungen. Sobald du Werte änderst, sind sie automatisch gespeichert'],
            ['dieser Schaltfläche abzuschließen. Sie müssen lediglich das Eingabefeld verlassen, um den eingetragenen Wert zu speichern.',
             'dieses Knopfes abzuschließen. Du musst nur das Eingabefeld verlassen, um den eingetragenen Wert zu speichern.']
        ]);
        var notes = q('#noten_here');
        if (notes) notes.classList.add('pv-tresor-scroll');
    }

    // ---------- the tresor's login (tresor.html) ----------
    function page_login(panel) {
        var title = el('h3', 'pv-tresor-title', 'Datentresor');
        panel.insertBefore(title, panel.firstChild);

        var failed = q('#connection-failed');
        if (failed) {
            var box = el('div', 'pv-tresor-unreachable');
            box.setAttribute('role', 'status');
            var text = el('div');
            text.append(el('p', 'pv-tresor-unreachable-title', 'Der Datentresor ist gerade nicht erreichbar.'),
                el('p', null, 'Er ist nur aus der Schule erreichbar: an einem Schulrechner oder im Schul-WLAN. Bist du dort angemeldet, versuch es gleich noch einmal.'));
            var again = el('button', 'btn btn-secondary', 'Erneut versuchen');
            again.type = 'button';
            again.id = 'bu_pv_tresor_retry';
            again.addEventListener('click', function () { location.reload(); });
            text.append(again);
            box.append(icon('alert-circle'), text);
            var old = q('p', failed);
            if (old) old.replaceWith(box);
        }

        var login = q('#div-login');
        if (login) {
            var paras = qa(':scope > p', login);
            // »Sie sind bereits per E-Mail am Dashboard angemeldet …«
            var intro = paras[0];
            var method = intro && q('strong', intro);
            if (intro && method) {
                compose(intro, ['Du bist per ', method, ' am Dashboard angemeldet. Für den Datentresor brauchst du einen zweiten Faktor. Wähl, wie du dich ausweist:']);
                intro.classList.add('pv-tresor-intro');
            }
            var choices = q('.bu_second_login', login);
            if (choices) choices.parentElement.classList.add('pv-tresor-methods');
            var sms_off = q('#bu_sf_otp') && q('#bu_sf_otp').parentElement.nextElementSibling;
            if (sms_off && sms_off.tagName === 'DIV') {
                sms_off.classList.add('pv-tresor-quiet');
                compose(sms_off, ['Gerade können keine SMS versendet werden.']);
            }
            compose(q('#hint-no-good-telephone-number'), [el('b', null, 'Hinweis:'), ' Du hast die SMS-Anmeldung erst heute eingerichtet. Aus Sicherheitsgründen kannst du sie für den Datentresor ab morgen nutzen.']);
            compose(q('#hint-no-good-otp-token'), [el('b', null, 'Hinweis:'), ' Du hast die OTP-Anmeldung erst heute eingerichtet. Aus Sicherheitsgründen kannst du sie für den Datentresor ab morgen nutzen.']);
            paras.forEach(function (p) {
                var profile = q("a[href='/profil#anmeldung']", p);
                var hotline = q('#hotline-2fa', p);
                var video = q("a[href*='youtu']", p);
                if (profile) {
                    profile.textContent = 'im Profil';
                    compose(p, ['Weitere Verfahren richtest du ', profile, ' ein: eine Telefonnummer hinterlegen (»Nummer hinterlegen«) oder einen OTP-Code einscannen (»OTP aktivieren«). Aus Sicherheitsgründen gilt ein neues Verfahren für den Datentresor erst ab dem nächsten Tag.']);
                    p.classList.add('pv-tresor-quiet');
                } else if (hotline) {
                    compose(p, ['Hast du alles versucht und kommst nicht weiter, oder ist es dringend? Du kannst auch ', hotline, '; du wirst dann telefonisch freigeschaltet.']);
                    p.classList.add('pv-tresor-quiet');
                } else if (video) {
                    video.textContent = 'Einführungsvideo';
                    compose(p, ['Wie das geht, zeigt ein kurzes ', video, '.']);
                    p.classList.add('pv-tresor-quiet');
                }
            });
        }

        var code_box = q('#div-confirm-login');
        if (code_box) {
            code_box.classList.remove('col-md-6', 'offset-md-3');
            var code = q('#code', code_box);
            if (code) {
                var label = el('label', 'pv-tresor-code-label', 'Code');
                label.setAttribute('for', 'code');
                var form = q('form', code_box);
                if (form) form.insertBefore(label, form.firstChild);
                code.setAttribute('inputmode', 'numeric');
                code.setAttribute('autocomplete', 'one-time-code');
            }
        }

        // the hotline's dialog: a sheet on phones, »du«
        var modal = q('#__2fa_modal');
        if (modal) {
            modal.classList.add('pv-sheet');
            retext(modal, [
                ['Bitte rufen Sie ', 'Ruf bitte '],
                ['Klicken Sie auf »Anmeldung anfordern«, sobald das Gespräch hergestellt ist.', 'Klick auf »Anmeldung anfordern«, sobald das Gespräch steht.'],
                ['Klicken Sie auf »Anmelden«, sobald Sie die Freigabe erhalten haben.', 'Klick auf »Anmelden«, sobald du freigeschaltet bist.']
            ]);
            qa('.modal-body > p', modal).forEach(function (p) {
                if (!p.textContent.trim() && !p.children.length) p.remove();
            });
        }
    }

    document.addEventListener('DOMContentLoaded', function () {
        var panel = page_panel();
        if (!panel) return;
        panel.classList.add('pv-tresor-panel');
        build_nav(panel);
        move_konferenzen(panel);
        if (PATH === '/tresor') page_login(panel);
        else if (PATH === '/zeugnisuebersicht') page_uebersicht(panel);
        else if (PATH === '/zeugnisformulare') page_formulare(panel);
        else if (PATH === '/zeugnis_at') page_at(panel);
        else if (PATH === '/zeugnisdruck') page_druck(panel);
        else if (PATH === '/anlage_sozialverhalten') page_sozialverhalten(panel);
    });
})();
