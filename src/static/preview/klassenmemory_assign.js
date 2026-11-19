// Neues Design (Vorschau): Klassenmemory (/klassenmemory_assign). Loaded by
// the page only in the new design (design_preview_page_script in
// include/design_preview.rb), so that today's page stays as it was. The page
// keeps its logic; this adds what the new design needs around it (styles in
// preview/klassenmemory_assign.css):
//
// - the page: a title with a quiet line, »Quiz« as the main action in the
//   title row (once the photos are open), the password with a label, the
//   shown class marked, texts with »du«;
// - the quiz: a dialog (on phones a screen of its own) with a header (close,
//   back, which class); back and Escape close it a step at a time
//   (pv_back), the page behind it stands still (body.pv-sheet-open);
// - answers: »Weiß ich nicht« and »Weiter« in words with Tabler icons
//   instead of an emoji and a lone arrow;
// - Hall of Fame: the shading from the accent instead of a fixed green, the
//   setting as a switch that says its state in words.
(function () {
    var body = document.body;
    // jQuery (loaded with defer) is only there from the page's load on
    if (!body.classList.contains('ui-preview')) return;
    var form = document.getElementById('form');
    var page = form && form.closest('.container');
    var curtain = document.getElementById('quiz-curtain');
    var root = document.getElementById('div_quiz_root');
    var play = document.getElementById('div_quiz_play');
    if (!page || !curtain || !root || !play) return;
    body.classList.add('pv-km-page');

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

    // a div that acts as a button: reachable and usable with the keyboard
    function as_button(e, label) {
        e.setAttribute('role', 'button');
        e.setAttribute('tabindex', '0');
        if (label) e.setAttribute('aria-label', label);
        e.addEventListener('keydown', function (ev) {
            if (ev.key === 'Enter' || ev.key === ' ') {
                ev.preventDefault();
                ev.currentTarget.click();
            }
        });
    }

    // ---------- the page: title, quiet line, the password with a label ----------
    page.classList.add('pv-km');
    var head = el('div', 'pv-km-head');
    head.appendChild(el('h2', 'pv-km-title', 'Klassenmemory'));
    var tools = el('div', 'pv-km-tools');
    head.appendChild(tools);
    page.insertBefore(head, page.firstChild);
    var sub = el('p', 'pv-km-sub');
    head.after(sub);
    var messages = el('div', 'api_messages');
    messages.style.display = 'none';
    sub.after(messages);

    var password = document.getElementById('password');
    var submit = document.getElementById('submit_password');
    var label = el('label', 'pv-km-label', 'Passwort für die Fotos');
    label.setAttribute('for', 'password');
    form.insertBefore(label, form.firstChild);
    password.setAttribute('placeholder', 'Passwort');
    password.setAttribute('spellcheck', 'false');
    submit.textContent = 'Fotos öffnen';

    function unlocked() {
        return form.style.display === 'none';
    }

    function update_sub() {
        sub.textContent = unlocked()
            ? 'Tippe auf einen Namen, um ihn zu ändern. Im Quiz übst du die Namen deiner Schülerinnen und Schüler.'
            : 'Lerne die Namen und Gesichter deiner Schülerinnen und Schüler. Die Fotos sind mit einem Passwort geschützt.';
        body.classList.toggle('pv-km-unlocked', unlocked());
    }
    update_sub();

    // the photos of a class: names in »du«, labels usable with the keyboard
    function tune_tile(frame) {
        if (frame.dataset.pvKm) return;
        frame.dataset.pvKm = '1';
        var name = frame.querySelector('.sus-label');
        var input = frame.querySelector('.sus-edit');
        if (name) as_button(name, null);
        if (input) {
            input.setAttribute('placeholder', 'Name eingeben');
            input.setAttribute('aria-label', 'Name zu diesem Foto');
        }
    }
    new MutationObserver(function () {
        document.querySelectorAll('#sus_here .sus-frame').forEach(tune_tile);
    }).observe(document.getElementById('sus_here'), { childList: true, subtree: true });

    // ---------- the quiz: a dialog, on phones a screen of its own ----------
    var QUIZ = 'klassenmemory-quiz';
    var PLAY = 'klassenmemory-play';

    [root, play].forEach(function (panel) {
        panel.classList.add('pv-km-quiz-panel');
        panel.setAttribute('role', 'dialog');
        panel.setAttribute('aria-modal', 'true');
    });

    // root: the title next to »Schließen«
    var root_col = root.querySelector('.col-md-12');
    var root_close = root.querySelector('.right-top-button');
    var root_title = root.querySelector('h1');
    var root_head = el('div', 'pv-km-quiz-head');
    root_col.insertBefore(root_head, root_col.firstChild);
    root_title.id = 'pv_km_quiz_title';
    root_title.textContent = 'Klassenmemory-Quiz';
    root_head.appendChild(root_title);
    root_head.appendChild(root_close);
    as_button(root_close, 'Schließen');
    root.setAttribute('aria-labelledby', 'pv_km_quiz_title');
    root.querySelector('p').classList.add('pv-km-intro');
    root.querySelectorAll('.col-md-4 > br').forEach(function (br) { br.remove(); });
    var messages_root = el('div', 'api_messages');
    messages_root.style.display = 'none';
    root_head.after(messages_root);

    // the three ways to play: rows; two of them unfold the classes
    root.querySelectorAll('.bu_play').forEach(function (b) {
        b.classList.remove('btn', 'btn-lg', 'btn-success', 'w-100');
        b.classList.add('pv-km-mode');
        var which = b.getAttribute('data-which');
        var text = el('span', 'pv-km-mode-text', b.textContent.trim());
        b.textContent = '';
        b.appendChild(text);
        b.appendChild(icon(which === 'schule' ? 'chevron-right' : 'chevron-down'));
        if (which !== 'schule') b.setAttribute('aria-expanded', 'false');
        var quote = b.nextElementSibling;
        if (quote && quote.tagName === 'P') quote.classList.add('pv-km-mode-note');
        b.addEventListener('click', function (e) {
            if (e.currentTarget.hasAttribute('aria-expanded')) e.currentTarget.setAttribute('aria-expanded', 'true');
        });
    });

    // play: »Zurück« and which photos are asked
    var play_col = play.querySelector('.col-md-12');
    var play_back = play.querySelector('.right-top-button');
    var play_head = el('div', 'pv-km-quiz-head pv-km-play-head');
    var play_title = el('h2', null, 'Wer ist das?');
    play_title.id = 'pv_km_play_title';
    var play_what = el('div', 'pv-km-play-what');
    var play_titles = el('div', 'pv-km-play-titles');
    play_titles.appendChild(play_title);
    play_titles.appendChild(play_what);
    play_head.appendChild(play_back);
    play_head.appendChild(play_titles);
    play_col.insertBefore(play_head, play_col.firstChild);
    as_button(play_back, 'Zurück');
    play.setAttribute('aria-labelledby', 'pv_km_play_title');
    var messages_play = el('div', 'api_messages');
    messages_play.style.display = 'none';
    play_head.after(messages_play);

    function klasse_label(k) {
        return (window.KLASSEN_TR && window.KLASSEN_TR[k]) || k;
    }

    function update_play_what(path) {
        var parts = String(path || '').split('/');
        var text = '';
        if (parts[2] === 'klasse') text = 'Klasse ' + klasse_label(parts[3]);
        else if (parts[2] === 'klassenstufe') text = 'Klassenstufe ' + parts[3];
        else if (parts[2] === 'schule') text = 'Ganze Schule';
        play_what.textContent = text;
    }

    function focus_first(panel) {
        var target = panel.querySelector('.right-top-button');
        if (target) target.focus({ preventScroll: true });
    }

    // the page's own functions, wrapped: they are globals it calls by name
    var orig_reset = window.resetQuiz;
    var orig_navigate = window.quiz_navigate;
    var orig_back = window.quiz_back;
    if (orig_reset && orig_navigate && orig_back) {
        window.resetQuiz = function () {
            orig_reset.apply(this, arguments);
            root.querySelectorAll('.pv-km-mode[aria-expanded]').forEach(function (b) {
                b.setAttribute('aria-expanded', 'false');
            });
            body.classList.add('pv-sheet-open', 'pv-km-quiz-open');
            if (window.pv_back) window.pv_back.opened(QUIZ, function () {
                if (window.quiz_path !== '/') orig_navigate('/');
                close_quiz();
            });
            setTimeout(function () { focus_first(root); }, 50);
        };
        window.quiz_navigate = function (path) {
            orig_navigate.apply(this, arguments);
            if (path === '/') {
                if (window.pv_back) window.pv_back.closed(PLAY);
                setTimeout(function () { focus_first(root); }, 0);
            } else {
                update_play_what(path);
                if (window.pv_back) window.pv_back.opened(PLAY, function () {
                    orig_navigate('/');
                    if (window.update_hall_of_fame) window.update_hall_of_fame();
                    focus_first(root);
                });
                setTimeout(function () { focus_first(play); }, 0);
            }
            play.scrollTop = 0;
            root.scrollTop = 0;
        };
        window.quiz_back = function () {
            var closing = window.quiz_path === '/';
            orig_back.apply(this, arguments);
            if (closing) {
                close_quiz();
                if (window.pv_back) window.pv_back.closed(QUIZ);
            }
        };
    }

    function close_quiz() {
        $('#quiz-curtain').fadeOut();
        $('.div_quiz').fadeOut();
        body.classList.remove('pv-sheet-open', 'pv-km-quiz-open');
        var quiz = document.getElementById('bu_km_quiz');
        if (quiz) quiz.focus({ preventScroll: true });
    }

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape' || !body.classList.contains('pv-km-quiz-open')) return;
        if (document.activeElement && document.activeElement.closest('.sus-edit')) return;
        e.preventDefault();
        window.quiz_back();
    });

    // ---------- answers: words and Tabler icons ----------
    function tune_answers() {
        document.querySelectorAll('#name-buttons-here > .btn').forEach(function (b) {
            if (b.dataset.pvKm) return;
            b.dataset.pvKm = '1';
            if (b.classList.contains('bu-dont-know')) {
                b.textContent = '';
                b.appendChild(icon('help-circle'));
                b.appendChild(document.createTextNode('Weiß ich nicht'));
                b.classList.add('pv-km-aside');
            } else if (b.querySelector('.fa-angle-double-right')) {
                b.textContent = '';
                b.appendChild(document.createTextNode('Weiter'));
                b.appendChild(icon('arrow-right'));
                b.classList.add('pv-km-next');
            } else {
                b.classList.add('pv-km-name');
            }
        });
    }
    new MutationObserver(tune_answers).observe(document.getElementById('name-buttons-here'), { childList: true });

    // ---------- Hall of Fame: shading from the accent, the setting as a switch ----------
    function tune_fame() {
        document.querySelectorAll('#hall-of-fame td[style*="background-color"]').forEach(function (td) {
            var m = /rgba\(\s*74,\s*160,\s*63,\s*([0-9.]+)\s*\)/.exec(td.getAttribute('style') || '');
            if (!m) return;
            td.style.removeProperty('background-color');
            td.style.setProperty('--km-share', Math.max(0, Math.min(1, parseFloat(m[1]) || 0)));
            td.classList.add('pv-km-share');
        });
        var table = document.querySelector('#hall-of-fame table');
        if (table) table.classList.remove('table-striped');
    }
    new MutationObserver(tune_fame).observe(document.getElementById('hall-of-fame'), { childList: true, subtree: true });

    var orig_stats = window.update_recognize_stats_button;
    if (orig_stats) {
        window.update_recognize_stats_button = function () {
            orig_stats.apply(this, arguments);
            var b = document.getElementById('toggle_show_recognize_hall_of_fame');
            if (!b) return;
            var on = !!window.recognize_stats_public;
            b.className = 'pv-km-switch';
            b.setAttribute('role', 'switch');
            b.setAttribute('aria-checked', on ? 'true' : 'false');
            b.textContent = '';
            b.appendChild(icon(on ? 'toggle-right' : 'toggle-left'));
            b.appendChild(el('span', null, on ? 'Du stehst mit Namen in der Hall of Fame' : 'Du stehst ohne Namen in der Hall of Fame'));
        };
    }

    // ---------- after the page's own start ----------
    window.addEventListener('load', function () {
        // »Quiz« as the main action, next to the title
        var quiz = Array.prototype.find.call(document.querySelectorAll('#klassen-div button'), function (b) {
            return $(b).data('quiz') === 'yeah';
        });
        if (quiz) {
            quiz.className = 'btn btn-primary pv-km-quiz';
            quiz.id = 'bu_km_quiz';
            quiz.removeAttribute('style');
            quiz.textContent = '';
            quiz.appendChild(icon('player-play'));
            quiz.appendChild(document.createTextNode('Quiz'));
            tools.appendChild(quiz);
        }
        // the class shown first, marked like a chosen one
        var klassen = document.getElementById('klassen-div');
        klassen.setAttribute('role', 'group');
        klassen.setAttribute('aria-label', 'Klasse');
        if (!klassen.querySelector('.ttc.active')) {
            var first = Array.prototype.find.call(klassen.querySelectorAll('.ttc'), function (b) {
                return String($(b).data('klasse')) === String(window.current_klasse);
            });
            if (first) first.classList.add('active');
        }
        update_sub();
        tune_answers();
        tune_fame();
    });
    submit.addEventListener('click', function () { setTimeout(update_sub, 0); });
})();
