// Neues Design der Flurmonitore (Vorschau, include/monitor_neu.rb).
//
// Nur geladen, wenn die Adresse des Monitors ?design=neu oder
// ?design=neu-dunkel trägt. Dann ist das Skript von monitor.html abgeschaltet
// und dieses zeichnet dieselben Daten neu: dieselben Nachrichten über
// /ws_monitor (Vertretungsplan, Laufschrift, Bilder, Neu laden, Effekte), die
// Zeugniskonferenzen und die Wetter- und Festeffekte (monitor_effekte.js).
//
// - Kompakt wie auf dem bisherigen Monitor: ein Eintrag eine Zeile in Spalten
//   (Stunde, Fach, Lehrkraft, Raum), was sich ändert neu und fett, das Alte
//   durchgestrichen dahinter; Hinweise in einer zweiten Zeile darunter.
// - Feste Kacheln wie auf dem bisherigen Monitor: KLASSEN_ORDER der Reihe
//   nach in Spalten zu je sieben Klassen (vier Spalten), 11 und 12 höher.
//   Jede Klasse immer an derselben Stelle, auch ohne Änderungen. Was nicht in
//   eine Kachel passt, rollt in der Kachel wie bisher (»Fahrstuhl«): oben
//   OBEN_S Sekunden stehen, langsam hinunter, unten kurz stehen, schnell
//   wieder hinauf.
// - Uhr und laufende Stunde im Kopf (Zeit des Servers, Stundenraster aus
//   HOURS_FOR_KLASSE).
// - Alles als Text eingesetzt (textContent), nie als HTML.
// - Lehrerzimmer und Silentium: heute und morgen nebeneinander, die Karten der
//   Lehrkräfte laufen ohne Ende durch wie bisher; über jeder Spalte die
//   Kürzel zum Antippen (springt zur nächsten Karte, hebt sie 5 s hervor,
//   hält 5 s an). Sekretariat: links die Klassen, rechts die Lehrkräfte.
(function () {
    'use strict';

    // the old monitor's elevator (monitor.html: top_delay, bottom_delay,
    // scroll_down_speed, scroll_up_speed)
    const OBEN_S = 5;
    const UNTEN_S = 2;
    const RUNTER_VW_S = 1.0;
    const HOCH_VW_S = 10.0;
    // without motion (prefers-reduced-motion): a screenful at a time
    const SPRUNG_S = 8;
    // Laufband wie bisher (monitor.html: ticker_speed), vw pro Sekunde
    const LAUF_VW_S = 6.0;
    const BILD_S = 30;
    // ab so vielen Minuten zwischen zwei Stunden ist es eine Pause (sonst Wechsel)
    const PAUSE_AB_MIN = 10;

    // two columns (Lehrerzimmer, Silentium, Sekretariat): like the old
    // monitor's continuous scroller (1 vw/s; after a tap or a swipe 5 s still)
    const SPALTE_VW_S = 1.0;
    const PAUSE_S = 5;
    const MARKIERT_S = 5;

    let DATEN = null;
    let modus = 'flur';
    let spalten2 = [];            // [{el, datum, chips, lauf, inhalt, endlos, hoehe, pos, pauseBis}]
    let KLASSEN_TR = {};
    let KLASSEN = [];

    let serverDiff = 0;           // ms, Uhr des Servers minus Uhr des Monitors
    let plan = null;              // {heute, stand, klassen: {klasse: [Einträge]}}
    let letzterStand = null;
    let nachrichten = [];
    let band = null;              // die laufende Animation des Laufbands
    let bandStand = null;         // [Nachrichten, Breite], für die es gebaut ist
    let bilder = [];
    let bildIndex = 0;
    let bildUhr = null;
    let zk = false;               // Zeugniskonferenzen statt Vertretungsplan

    let kacheln = [];             // [{klasse, el, box, liste, rollen: {weite, pos, phase, bis}}]
    let rollenZeit = 0;

    const el = {};

    // ------------------------------------------------------------------
    // Hilfsfunktionen

    function h(tag, klasse, text) {
        const e = document.createElement(tag);
        if (klasse) e.className = klasse;
        if (text !== undefined && text !== null) e.textContent = text;
        return e;
    }

    function tr(k) { return KLASSEN_TR[k] || k; }
    function jetzt() { return new Date(Date.now() + serverDiff); }
    function zwei(n) { return (n < 10 ? '0' : '') + n; }
    function uhrzeit(d) { return `${d.getHours()}:${zwei(d.getMinutes())}`; }
    function datumIso(d) { return `${d.getFullYear()}-${zwei(d.getMonth() + 1)}-${zwei(d.getDate())}`; }
    function minuten(hhmm) { const p = String(hhmm).split(':'); return parseInt(p[0], 10) * 60 + parseInt(p[1], 10); }
    function hhmmKurz(hhmm) { const p = String(hhmm).split(':'); return `${parseInt(p[0], 10)}:${p[1]}`; }
    function ausIso(iso) { const p = String(iso).split('-').map((x) => parseInt(x, 10)); return new Date(p[0], p[1] - 1, p[2]); }
    function nurText(html) {
        return (new DOMParser().parseFromString(String(html || ''), 'text/html').body.textContent || '').trim();
    }
    function liste(a) { return (a || []).filter((x) => x !== null && x !== undefined && String(x).trim() !== ''); }

    // ------------------------------------------------------------------
    // Ein Eintrag des Vertretungsplans als Zeile in Spalten: Stunde, Fach,
    // Lehrkraft, Raum (rechts); darunter, was der Plan dazu schreibt

    // a mark only where the line alone would mislead: the lesson is not
    // taking place (the other changes show as »neu ~~alt~~«)
    function marke(e) {
        const text = e.vertretungs_text || '';
        if (/entf[äa]ll|f[äa]llt aus/i.test(text)) return 'Entfall';
        if ((e.fach_neu || '').substring(0, 5) === 'Test-') return 'Testung';
        return null;
    }

    // the new value in full, the old one struck through behind it
    function wert(klasse, neu, alt) {
        const z = h('span', klasse);
        neu = neu || '';
        alt = alt || '';
        if (neu && alt && neu !== alt) {
            z.appendChild(h('b', null, neu));
            z.appendChild(document.createTextNode(' '));
            z.appendChild(h('s', 'mn-alt', alt));
        } else {
            z.appendChild(document.createTextNode(neu || alt));
        }
        return z;
    }

    function zeileBauen(e, klasse) {
        const z = h('div', 'mn-zeile');
        if (e.type === 'extra') {
            z.appendChild(h('span', 'mn-st mn-z1', ''));
            z.appendChild(h('span', 'mn-text mn-z1', nurText(e.salzh_sus_label)));
            return z;
        }
        z.appendChild(h('span', 'mn-st mn-z1', String(e.stunde_label || '').replace(/\s+/g, '')));
        const m = marke(e);
        const testung = m === 'Testung';
        const fach = wert('mn-fach mn-z1', testung ? '' : e.fach_neu, e.fach_alt);
        z.appendChild(fach);
        if (m) {
            const zelle = z.appendChild(h('span', 'mn-wer mn-z1 mn-breit'));
            zelle.appendChild(h('span', 'mn-marke', m));
        } else {
            const la = liste(e.lehrer_alt), ln = liste(e.lehrer_neu);
            z.appendChild(wert('mn-wer mn-z1', ln.join(', '), la.join(', ')));
            z.appendChild(wert('mn-raum mn-z1', e.raum_neu, e.raum_alt));
        }
        // weitere Klassen derselben Stunde, dann der Text des Plans
        const teile = [];
        const andere = liste([].concat(e.klassen_neu || [], e.klassen_alt || []))
            .filter((k, i, a) => a.indexOf(k) === i && k !== klasse).map(tr);
        if (andere.length) teile.push(`mit ${andere.join(', ')}`);
        let text = String(e.vertretungs_text || '').trim();
        // the mark says it already: »entfällt; verlegt auf …« → »verlegt auf …«
        if (m === 'Entfall') text = text.replace(/^(entf[äa]llt|f[äa]llt aus|entfall)\s*[.;,:–-]?\s*/i, '');
        if (text) teile.push(text);
        if (teile.length) z.appendChild(h('span', 'mn-text', teile.join(', ')));
        return z;
    }

    function eintraege(klasse) {
        return (plan && plan.klassen && plan.klassen[klasse]) || [];
    }

    // ------------------------------------------------------------------
    // Feste Kacheln, verteilt wie auf dem bisherigen Monitor (monitor.html):
    // KLASSEN_ORDER der Reihe nach von oben nach unten in Spalten zu je
    // sieben Klassen, vier Spalten nebeneinander; 11 und 12 sind höher
    // (9,8 statt 6,2 vw, Abstand 1 vw), mit denselben Verhältnissen wie dort.
    // Jede Klasse hat immer ihre Kachel an derselben Stelle, auch ohne
    // Änderungen (dann nur der Name, leise); leere Plätze gibt es nicht. Wer
    // mehr hat, als in die Kachel passt, rollt in der Kachel.

    const PRO_SPALTE = 7;
    const MIN_SPALTEN = 4;
    // Höhen in Zehntel-vw des bisherigen Monitors; das Raster wird so
    // gestreckt, dass die höchste Spalte (mindestens sieben normale Kacheln)
    // den Platz zwischen Kopf und Fuß füllt
    const HOEHE = 62, HOEHE_HOCH = 98, ABSTAND = 10;

    function istHoch(k) { return k === '11' || k === '12'; }

    function kachelBauen(klasse) {
        const k = h('div', 'mn-kasten mn-kachel mn-still' + (istHoch(klasse) ? ' mn-hoch' : ''));
        k.dataset.klasse = klasse;
        const name = h('div', 'mn-name');
        name.appendChild(h('h2', null, tr(klasse)));
        const box = h('div', 'mn-zeilen');
        const liste = box.appendChild(h('div', 'mn-liste'));
        k.appendChild(name);
        k.appendChild(box);
        return {klasse: klasse, el: k, box: box, liste: liste,
                rollen: {weite: 0, pos: 0, phase: 'oben', bis: 0}};
    }

    function rasterAufbauen() {
        el.raster.textContent = '';
        kacheln = [];
        const spalten = [];
        KLASSEN.forEach((k, i) => {
            if (i % PRO_SPALTE === 0) spalten.push([]);
            spalten[spalten.length - 1].push(k);
        });
        const hoehe = (s) => s.reduce((a, k) => a + (istHoch(k) ? HOEHE_HOCH : HOEHE), 0) + (s.length - 1) * ABSTAND;
        const gesamt = Math.max(PRO_SPALTE * HOEHE + (PRO_SPALTE - 1) * ABSTAND, ...spalten.map(hoehe));
        el.raster.style.setProperty('--mn-spalten', String(Math.max(MIN_SPALTEN, spalten.length)));
        const prozent = (x) => `${(x * 100 / gesamt).toFixed(4)}%`;
        for (const spalte of spalten) {
            const sp = el.raster.appendChild(h('section', 'mn-spalte'));
            let y = 0;
            for (const klasse of spalte) {
                const kachel = kachelBauen(klasse);
                const hk = istHoch(klasse) ? HOEHE_HOCH : HOEHE;
                kachel.el.style.top = prozent(y);
                kachel.el.style.height = prozent(hk);
                y += hk + ABSTAND;
                sp.appendChild(kachel.el);
                kacheln.push(kachel);
            }
        }
    }

    // die Einträge einer Klasse in ihre Kachel; was nicht passt, rollt
    function kachelFuellen(kachel) {
        const zeilen = eintraege(kachel.klasse).map((e) => zeileBauen(e, kachel.klasse));
        kachel.liste.textContent = '';
        for (const z of zeilen) kachel.liste.appendChild(z);
        kachel.el.classList.toggle('mn-still', zeilen.length === 0);
        rollenMessen(kachel);
    }

    function rollenMessen(kachel) {
        const r = kachel.rollen;
        const weite = kachel.liste.scrollHeight - kachel.box.clientHeight;
        r.weite = weite > 1 ? weite : 0;
        r.pos = 0;
        r.phase = 'oben';
        r.bis = Date.now() / 1000 + OBEN_S;
        kachel.liste.style.transform = '';
        if (r.weite) kachel.el.dataset.rollt = 'oben';
        else delete kachel.el.dataset.rollt;
    }

    function neuBerechnen() {
        if (zk || !plan) return;
        if (modus !== 'flur') { zweiSpaltenFuellen(); return; }
        for (const k of kacheln) kachelFuellen(k);
    }

    // ------------------------------------------------------------------
    // Zwei Spalten (Lehrerzimmer, Silentium, Sekretariat)

    function lehrerzimmer() { return modus === 'lehrerzimmer' || modus === 'silentium'; }

    function spalteBauen(titel) {
        const el2 = h('section', 'mn-kasten mn-spalte2');
        const kopf = el2.appendChild(h('div', 'mn-spalte-kopf'));
        kopf.appendChild(h('h2', null, titel));
        const datum = kopf.appendChild(h('span', 'mn-spalte-datum'));
        let chips = null;
        if (lehrerzimmer()) {
            chips = el2.appendChild(h('div', 'mn-chips'));
            chips.setAttribute('role', 'toolbar');
            chips.setAttribute('aria-label', `Kürzel ${titel.toLowerCase()}`);
        }
        const lauf = el2.appendChild(h('div', 'mn-lauf'));
        const inhalt = lauf.appendChild(h('div', 'mn-lauf-inhalt'));
        const sp = {el: el2, datum: datum, chips: chips, lauf: lauf, inhalt: inhalt, endlos: false, hoehe: 0, pos: 0, pauseBis: 0};
        // swiped, scrolled, tapped: stands still for a while (as before)
        for (const ev of ['wheel', 'touchstart', 'touchmove', 'pointerdown']) {
            lauf.addEventListener(ev, () => { sp.pauseBis = Date.now() / 1000 + PAUSE_S; }, {passive: true});
        }
        return sp;
    }

    function zweiSpaltenAufbauen() {
        el.raster.textContent = '';
        el.raster.classList.add('mn-zwei');
        spalten2 = lehrerzimmer() ? [spalteBauen('Heute'), spalteBauen('Morgen')] : [spalteBauen('Klassen'), spalteBauen('Lehrkräfte')];
        for (const sp of spalten2) el.raster.appendChild(sp.el);
    }

    // an entry of a teacher: lesson, classes, subject, teacher, room
    function zeileLehrkraft(e) {
        const z = h('div', 'mn-zeile');
        if (e.type === 'extra') {
            z.appendChild(h('span', 'mn-st mn-z1', ''));
            z.appendChild(h('span', 'mn-text mn-z1', nurText(e.salzh_sus_label)));
            return z;
        }
        z.appendChild(h('span', 'mn-st mn-z1', String(e.stunde_label || '').replace(/\s+/g, '')));
        z.appendChild(wert('mn-kl mn-z1', liste(e.klassen_neu).map(tr).join(', '), liste(e.klassen_alt).map(tr).join(', ')));
        const m = marke(e);
        z.appendChild(wert('mn-fach mn-z1', m === 'Testung' ? '' : e.fach_neu, e.fach_alt));
        if (m) {
            const zelle = z.appendChild(h('span', 'mn-wer mn-z1 mn-breit'));
            zelle.appendChild(h('span', 'mn-marke', m));
        } else {
            z.appendChild(wert('mn-wer mn-z1', liste(e.lehrer_neu).join(', '), liste(e.lehrer_alt).join(', ')));
            z.appendChild(wert('mn-raum mn-z1', e.raum_neu, e.raum_alt));
        }
        let text = String(e.vertretungs_text || '').trim();
        if (m === 'Entfall') text = text.replace(/^(entf[äa]llt|f[äa]llt aus|entfall)\s*[.;,:–-]?\s*/i, '');
        if (text) z.appendChild(h('span', 'mn-text', text));
        return z;
    }

    function karteBauen(name, eintraegeListe, alsLehrkraft, klasse) {
        const k = h('div', 'mn-karte');
        k.appendChild(h('h3', 'mn-karte-name', name));
        const l = k.appendChild(h('div', 'mn-liste' + (alsLehrkraft ? ' mn-liste-lk' : '')));
        for (const e of eintraegeListe) l.appendChild(alsLehrkraft ? zeileLehrkraft(e) : zeileBauen(e, klasse));
        return k;
    }

    function tagText(tag) {
        return tag ? ausIso(tag).toLocaleDateString('de-DE', {weekday: 'long', day: 'numeric', month: 'numeric'}) : '';
    }

    function zweiSpaltenFuellen() {
        if (lehrerzimmer()) {
            spalteMitKuerzeln(spalten2[0], plan.heute, plan.lehrer);
            spalteMitKuerzeln(spalten2[1], plan.morgen, plan.lehrerMorgen);
            return;
        }
        // Sekretariat: the classes with changes, the teachers (also the
        // shorthands starting with _) – both today
        spalten2[0].datum.textContent = tagText(plan.heute);
        spalten2[1].datum.textContent = tagText(plan.heute);
        inhaltSetzen(spalten2[0], KLASSEN.filter((k) => eintraege(k).length > 0)
            .map((k) => karteBauen(tr(k), eintraege(k), false, k)), 'Keine Vertretungen');
        inhaltSetzen(spalten2[1], (DATEN.kuerzel || []).filter((k) => (plan.lehrer[k] || []).length > 0)
            .map((k) => { const c = karteBauen(k, plan.lehrer[k], true); c.dataset.kuerzel = k; return c; }), 'Keine Vertretungen');
    }

    // a day of the Lehrerzimmer: every teacher's shorthand to tap (only the
    // ones with entries take a tap), their cards below
    function spalteMitKuerzeln(sp, tag, lehrer) {
        sp.datum.textContent = tagText(tag);
        const kuerzel = (DATEN.kuerzel || []).filter((k) => String(k).charAt(0) !== '_');
        const mit = kuerzel.filter((k) => (lehrer[k] || []).length > 0);
        sp.chips.textContent = '';
        for (const k of kuerzel) {
            if (mit.indexOf(k) >= 0) {
                const b = sp.chips.appendChild(h('button', 'mn-chip mn-chip-an', k));
                b.type = 'button';
                b.dataset.kuerzel = k;
                b.addEventListener('click', () => kuerzelTippen(sp, k, b));
            } else {
                sp.chips.appendChild(h('span', 'mn-chip', k));
            }
        }
        inhaltSetzen(sp, mit.map((k) => { const c = karteBauen(k, lehrer[k], true); c.dataset.kuerzel = k; return c; }),
            tag ? 'Keine Vertretungen' : '');
    }

    function inhaltSetzen(sp, karten, leer) {
        sp.inhalt.textContent = '';
        if (!karten.length && leer) sp.inhalt.appendChild(h('p', 'mn-leer', leer));
        for (const c of karten) sp.inhalt.appendChild(c);
        laufMessen(sp);
    }

    // more than fits: a copy below, the column runs on without an end
    function laufMessen(sp) {
        for (const k of sp.lauf.querySelectorAll('.mn-lauf-kopie')) k.remove();
        sp.hoehe = sp.inhalt.offsetHeight;
        sp.endlos = sp.hoehe > sp.lauf.clientHeight + 1;
        if (sp.endlos) {
            const kopie = sp.inhalt.cloneNode(true);
            kopie.classList.add('mn-lauf-kopie');
            kopie.setAttribute('aria-hidden', 'true');
            sp.lauf.appendChild(kopie);
        }
        sp.pos = sp.endlos ? sp.pos % sp.hoehe : 0;
        sp.lauf.scrollTop = sp.pos;
        sp.lauf.dataset.endlos = sp.endlos ? '1' : '';
    }

    function laufSchritt(sp, t, dt, vw, sprung) {
        if (!sp.endlos) return;
        // still (after a tap or a swipe): where it is now is where it goes on
        if (t < sp.pauseBis) { sp.pos = sp.lauf.scrollTop; return; }
        if (sprung) {
            sp.pos += sp.lauf.clientHeight * 0.85;
            sp.pauseBis = t + SPRUNG_S;
        } else {
            sp.pos += dt * SPALTE_VW_S * vw;
        }
        if (sp.pos >= sp.hoehe) sp.pos -= sp.hoehe;
        sp.lauf.scrollTop = sp.pos;
    }

    // a shorthand tapped: to the nearest of its cards (there are two, the
    // column runs without an end), highlighted, the column stands still
    function kuerzelTippen(sp, k, chip) {
        const karten = Array.from(sp.lauf.querySelectorAll('.mn-karte')).filter((c) => c.dataset.kuerzel === k);
        if (!karten.length) return;
        const vw = window.innerWidth / 100;
        const jetztOben = sp.lauf.scrollTop;
        let beste = karten[0], besteOben = 0, abstand = Infinity;
        for (const c of karten) {
            const oben = Math.max(0, c.offsetTop - 0.6 * vw);
            if (Math.abs(oben - jetztOben) < abstand) { abstand = Math.abs(oben - jetztOben); beste = c; besteOben = oben; }
        }
        sp.pauseBis = Date.now() / 1000 + 1 + PAUSE_S;
        sp.lauf.scrollTo({top: besteOben, behavior: bewegungAus() ? 'auto' : 'smooth'});
        for (const c of el.raster.querySelectorAll('.mn-markiert')) c.classList.remove('mn-markiert');
        for (const c of el.raster.querySelectorAll('.mn-chip-gewaehlt')) c.classList.remove('mn-chip-gewaehlt');
        beste.classList.add('mn-markiert');
        if (chip) chip.classList.add('mn-chip-gewaehlt');
        clearTimeout(sp.markierUhr);
        sp.markierUhr = setTimeout(() => {
            beste.classList.remove('mn-markiert');
            if (chip) chip.classList.remove('mn-chip-gewaehlt');
        }, MARKIERT_S * 1000);
    }

    function bewegungAus() {
        return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    }

    // ------------------------------------------------------------------
    // Rollen wie bisher: alle Kacheln, die mehr haben, als hineinpasst,
    // jede für sich (alle beginnen zugleich, wenn ein neuer Plan kommt)

    function rollenSchritt() {
        const t = Date.now() / 1000;
        const dt = Math.min(0.25, Math.max(0, t - rollenZeit));
        rollenZeit = t;
        const vw = window.innerWidth / 100;
        const sprung = bewegungAus();
        for (const sp of spalten2) laufSchritt(sp, t, dt, vw, sprung);
        for (const k of kacheln) {
            const r = k.rollen;
            if (!r.weite) continue;
            if (r.phase === 'oben' || r.phase === 'unten' || r.phase === 'halt') {
                if (t < r.bis) continue;
                r.phase = r.phase === 'unten' ? 'hoch' : 'runter';
            }
            if (r.phase === 'runter') {
                r.pos = Math.min(r.weite, sprung ? r.pos + k.box.clientHeight * 0.85 : r.pos + dt * RUNTER_VW_S * vw);
                if (r.pos >= r.weite) {
                    r.phase = 'unten';
                    r.bis = t + (sprung ? SPRUNG_S : UNTEN_S);
                } else if (sprung) {
                    r.phase = 'halt';
                    r.bis = t + SPRUNG_S;
                }
            } else if (r.phase === 'hoch') {
                r.pos = sprung ? 0 : Math.max(0, r.pos - dt * HOCH_VW_S * vw);
                if (r.pos <= 0) {
                    r.phase = 'oben';
                    r.bis = t + (sprung ? SPRUNG_S : OBEN_S);
                }
            }
            k.liste.style.transform = `translateY(${(-r.pos).toFixed(1)}px)`;
            if (k.el.dataset.rollt !== r.phase) k.el.dataset.rollt = r.phase;
        }
        window.requestAnimationFrame(rollenSchritt);
    }

    function takt() {
        uhrZeigen();
        if (zk) zkZeitenZeigen();
    }

    // ------------------------------------------------------------------
    // Kopf: Datum, Stand, Uhr, laufende Stunde

    function uhrZeigen() {
        const t = jetzt();
        el.uhr.textContent = uhrzeit(t);
        const [zeile1, zeile2] = stundeText(t);
        el.stunde1.textContent = '';
        if (zeile1) {
            el.stunde1.appendChild(h('b', null, zeile1[0]));
            if (zeile1[1]) el.stunde1.appendChild(document.createTextNode(' ' + zeile1[1]));
        }
        el.stunde2.textContent = zeile2 || '';
    }

    // [[fett, Rest], zweite Zeile]
    function stundeText(t) {
        const tag = plan ? plan.heute : DATEN.heute;
        if (zk) return [null, ''];
        if (tag && tag !== datumIso(t)) {
            return [['Plan für', ausIso(tag).toLocaleDateString('de-DE', {weekday: 'long'})], ''];
        }
        const stunden = DATEN.stunden || [];
        if (!stunden.length) return [null, ''];
        const m = t.getHours() * 60 + t.getMinutes();
        // Ende des Blocks ohne Pause, zu dem die Stunde i gehört
        const blockEnde = (i) => {
            let j = i;
            while (j + 1 < stunden.length && minuten(stunden[j + 1][1]) - minuten(stunden[j][2]) < PAUSE_AB_MIN) j++;
            return j;
        };
        for (let i = 0; i < stunden.length; i++) {
            const [nr, von, bis] = stunden[i];
            if (m < minuten(von)) {
                if (i === 0) return [[`${nr}. Stunde`, `ab ${hhmmKurz(von)}`], ''];
                const pause = minuten(von) - minuten(stunden[i - 1][2]) >= PAUSE_AB_MIN;
                if (pause) return [['Pause', ''], `${nr}. Stunde ab ${hhmmKurz(von)}`];
                return [[`${nr}. Stunde`, `ab ${hhmmKurz(von)}`], ''];
            }
            if (m < minuten(bis)) {
                const ende = blockEnde(i);
                if (ende + 1 < stunden.length) return [[`${nr}. Stunde`, 'läuft'], `Pause ab ${hhmmKurz(stunden[ende][2])}`];
                return [[`${nr}. Stunde`, 'läuft'], `bis ${hhmmKurz(bis)}`];
            }
        }
        return [['Unterricht beendet', ''], ''];
    }

    function datumZeigen() {
        const tag = plan ? plan.heute : DATEN.heute;
        let text = tag ? ausIso(tag).toLocaleDateString('de-DE', {weekday: 'long', day: 'numeric', month: 'long'}) : '';
        if (plan && plan.stand) {
            const s = new Date(plan.stand);
            if (!isNaN(s.getTime())) {
                if (datumIso(s) === datumIso(jetzt())) text += `, Stand ${uhrzeit(s)} Uhr`;
                else text += `, Stand ${s.toLocaleDateString('de-DE', {weekday: 'short'}).replace('.', '')}, ${s.getDate()}.${s.getMonth() + 1}., ${uhrzeit(s)} Uhr`;
            }
        }
        el.datum.textContent = text;
    }

    // ------------------------------------------------------------------
    // Fuß: Laufband wie auf dem bisherigen Monitor – alle Nachrichten in einer
    // Zeile, jede mit dem Lautsprecher davor, ohne Ende von rechts nach links.
    // Eine Animation, die der Browser auf der Grafikkarte abspielt (stockt
    // nicht, wenn daneben die Effekte rechnen): zwei gleiche Abschnitte, einer
    // mindestens so breit wie das Band; die Animation schiebt genau einen
    // Abschnitt weiter und beginnt nahtlos von vorn.

    function nachrichtenStarten() {
        bandStand = null;
        bandAufbauen();
    }

    function bandAufbauen() {
        const box = el.nachricht;
        if (bandStand && bandStand[0] === nachrichten && bandStand[1] === window.innerWidth) return;
        bandStand = [nachrichten, window.innerWidth];
        // die Stelle im Band merken, damit es nach einer Änderung nicht von vorn beginnt
        let anteil = 0;
        if (band) {
            try {
                const d = band.effect.getTiming().duration;
                anteil = ((band.currentTime || 0) % d) / d;
            } catch (e) { /* neu von vorn */ }
            band.cancel();
            band = null;
        }
        box.textContent = '';
        if (!nachrichten.length) return;
        const zeile = box.appendChild(h('div', 'mn-band'));
        const abschnitt = zeile.appendChild(h('div', 'mn-abschnitt'));
        // so oft wiederholen, bis ein Abschnitt breiter als das Band ist
        for (let runde = 0; runde < 50 && (runde === 0 || abschnitt.getBoundingClientRect().width < box.clientWidth); runde++) {
            for (const text of nachrichten) {
                const m = abschnitt.appendChild(h('span', 'mn-meldung'));
                m.appendChild(h('i', 'ti ti-speakerphone'));
                m.appendChild(document.createTextNode(text));
            }
        }
        zeile.appendChild(abschnitt.cloneNode(true));
        const w = abschnitt.getBoundingClientRect().width;
        if (!(w > 0) || !zeile.animate || bewegungAus()) return;
        const dauer = (w * 100 / window.innerWidth) / LAUF_VW_S * 1000;
        band = zeile.animate([{transform: 'translateX(0px)'}, {transform: `translateX(${-w}px)`}],
            {duration: dauer, iterations: Infinity, easing: 'linear'});
        band.currentTime = anteil * dauer;
    }

    // ------------------------------------------------------------------
    // Bilder aus „Monitore verwalten“: über dem Plan, wie bisher

    function bilderZeigen() {
        clearInterval(bildUhr);
        bildUhr = null;
        for (const e of el.mn.querySelectorAll('.mn-bild')) e.remove();
        if (!bilder.length) return;
        const url = (id) => `url("/gen/i/${encodeURIComponent(id)}-2048.jpg")`;
        bildIndex = 0;
        const hinten = h('div', 'mn-bild');
        const vorne = h('div', 'mn-bild');
        hinten.style.backgroundImage = url(bilder[0]);
        vorne.style.opacity = '0';
        el.mn.insertBefore(hinten, el.fuss);
        el.mn.insertBefore(vorne, el.fuss);
        if (bilder.length < 2) return;
        bildUhr = setInterval(() => {
            bildIndex = (bildIndex + 1) % bilder.length;
            vorne.style.backgroundImage = url(bilder[bildIndex]);
            vorne.style.opacity = '1';
            setTimeout(() => {
                hinten.style.backgroundImage = url(bilder[bildIndex]);
                vorne.style.opacity = '0';
            }, 4000);
        }, BILD_S * 1000);
    }

    // ------------------------------------------------------------------
    // Zeugniskonferenzen (Schalter auf „Monitore verwalten“)

    function zkZeigen() {
        const info = DATEN.zeugniskonferenzen || {};
        const laufend = info.laufend || {};
        const beendet = info.beendet || [];
        el.titel.textContent = 'Zeugniskonferenzen';
        el.raster.textContent = '';
        const gitter = el.raster.appendChild(h('div', 'mn-zk'));
        let jetztGesetzt = false;
        for (const eintrag of (info.heute || [])) {
            const zeit = eintrag[0], klasse = eintrag[1];
            let aktiv = false;
            if (zeit in laufend) aktiv = true;
            else if (Object.keys(laufend).length === 0 && beendet.indexOf(zeit) < 0) aktiv = true;
            if (jetztGesetzt) aktiv = false;
            if (aktiv) jetztGesetzt = true;
            const k = gitter.appendChild(h('div', 'mn-kasten' + (aktiv ? ' mn-jetzt' : '')));
            k.appendChild(h('div', 'mn-zk-zeit', zeit));
            k.appendChild(h('div', 'mn-zk-klasse', klasse === 'OS' ? 'Oberstufe' : `Klasse ${tr(klasse)}`));
            const stand = k.appendChild(h('div', 'mn-zk-stand'));
            if (zeit in laufend) {
                stand.appendChild(h('i', 'ti ti-clock'));
                stand.appendChild(document.createTextNode('läuft seit '));
                const span = stand.appendChild(h('span', 'mn-zk-dauer', ''));
                span.dataset.ts = String(laufend[zeit]);
            } else if (beendet.indexOf(zeit) >= 0) {
                stand.appendChild(h('i', 'ti ti-check'));
                stand.appendChild(document.createTextNode('beendet'));
            } else if (aktiv) {
                stand.appendChild(h('i', 'ti ti-clock'));
                stand.appendChild(document.createTextNode('wartet auf Beginn'));
            }
        }
        zkZeitenZeigen();
    }

    function zkZeitenZeigen() {
        const t = Math.floor(jetzt().getTime() / 1000);
        for (const span of el.raster.querySelectorAll('.mn-zk-dauer')) {
            const d = Math.max(0, t - parseInt(span.dataset.ts, 10));
            span.textContent = `${zwei(Math.floor(d / 60))}:${zwei(d % 60)}`;
        }
    }

    // ------------------------------------------------------------------
    // Verbindung zum Server (dieselben Nachrichten wie bisher)

    function planAus(paket) {
        const heute = paket.today;
        const tage = paket.data || {};
        const tag = tage[heute] || {};
        const morgen = paket.tomorrow || null;
        return {heute: heute, morgen: morgen, stand: tag.vplan_timestamp || paket.vplan_timestamp || null,
                klassen: tag.klassen || {}, lehrer: tag.lehrer || {},
                lehrerMorgen: (morgen && tage[morgen] && tage[morgen].lehrer) || {}};
    }

    function nachricht(d) {
        if (d.command === 'force_reload') {
            window.location.reload();
        } else if (d.command === 'update_time') {
            serverDiff = d.time * 1000 - Date.now();
            uhrZeigen();
        } else if (d.command === 'monitor_effekte_vorschau') {
            // nur Fenster im Folgen-Modus (?effekt=folgen) reagieren darauf
            if (window.MonitorEffekte) window.MonitorEffekte.vorschauNachricht(d.effekt || '');
        } else if (d.command === 'monitor_effekte_neu') {
            // Test „Im Schulhaus zeigen“ oder neue Story-Pausen: gleich neu abfragen
            if (window.MonitorEffekte) window.MonitorEffekte.neuAbfragen();
        } else if (d.command === 'update_monitor_messages') {
            nachrichten = ((d.data || {}).messages || []).map(String);
            // pictures only in the hallway (as before)
            bilder = modus === 'flur' ? ((d.data || {}).images || []).map(String) : [];
            nachrichtenStarten();
            bilderZeigen();
        } else if (d.command === 'update_vplan' && !zk) {
            const paket = d.data || {};
            const stand = JSON.stringify([paket.timestamp, paket.today]);
            if (stand === letzterStand) return;
            letzterStand = stand;
            plan = planAus(paket);
            datumZeigen();
            neuBerechnen();
            uhrZeigen();
        }
    }

    function verbinden() {
        const ws = new WebSocket((location.protocol === 'http:' ? 'ws://' : 'wss://') + location.host + '/ws_monitor');
        let wachHalten = null;
        ws.onopen = function () {
            wachHalten = setInterval(() => { if (ws.readyState === ws.OPEN) ws.send(''); }, 20000);
        };
        ws.onclose = function () {
            clearInterval(wachHalten);
            setTimeout(verbinden, 10000);
        };
        ws.onmessage = function (msg) {
            let d = null;
            try { d = JSON.parse(msg.data); } catch (e) { return; }
            if (d) nachricht(d);
        };
    }

    // ------------------------------------------------------------------
    // Aufbau

    function aufbauen() {
        const mn = h('div', 'mn' + (DATEN.dunkel ? ' mn-dunkel' : '') + ` mn-${DATEN.modus || 'flur'}`);
        mn.id = 'mn';
        mn.setAttribute('data-testid', 'monitor-neu');
        const kopf = mn.appendChild(h('header', 'mn-kopf'));
        const links = kopf.appendChild(h('div'));
        el.titel = links.appendChild(h('h1', null, 'Vertretungsplan'));
        el.datum = links.appendChild(h('div', 'mn-datum'));
        el.uhr = kopf.appendChild(h('div', 'mn-uhr'));
        el.uhr.setAttribute('data-testid', 'monitor-uhr');
        const stunde = kopf.appendChild(h('div', 'mn-stunde'));
        stunde.setAttribute('data-testid', 'monitor-stunde');
        el.stunde1 = stunde.appendChild(h('div'));
        el.stunde2 = stunde.appendChild(h('div'));
        el.raster = mn.appendChild(h('main', 'mn-raster'));
        // „ticker“: die Effekte halten den Fuß frei (monitor_effekte.js)
        el.fuss = mn.appendChild(h('footer', 'mn-fuss ticker'));
        el.nachricht = el.fuss.appendChild(h('div', 'mn-nachricht'));
        const schema = DATEN.schema || [];
        let schemaText = schema[0] ? `Farbschema »${schema[0]}«` : '';
        if (schema[0] && schema[1]) schemaText += ` von ${schema[1]}`;
        el.fuss.appendChild(h('span', 'mn-schema', schemaText));
        el.mn = mn;
        document.body.appendChild(mn);
        document.body.classList.add('mn-aktiv');
        if (DATEN.dunkel) document.body.classList.add('mn-dunkel-seite');
    }

    function start() {
        const quelle = document.getElementById('monitor_neu_daten');
        if (!quelle) return;
        DATEN = JSON.parse(quelle.textContent);
        KLASSEN_TR = DATEN.klassen_tr || {};
        KLASSEN = (DATEN.klassen || []).map(String);
        modus = DATEN.modus || 'flur';
        zk = !!(DATEN.zeugniskonferenzen || {}).an;
        aufbauen();
        datumZeigen();
        uhrZeigen();
        if (zk) {
            zkZeigen();
        } else if (modus === 'flur') {
            rasterAufbauen();
        } else {
            zweiSpaltenAufbauen();
        }
        verbinden();
        setInterval(takt, 1000);
        rollenZeit = Date.now() / 1000;
        window.requestAnimationFrame(rollenSchritt);
        let warten = null;
        window.addEventListener('resize', () => {
            clearTimeout(warten);
            warten = setTimeout(() => { neuBerechnen(); bandStand = null; bandAufbauen(); }, 300);
        });
        if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => { neuBerechnen(); bandStand = null; bandAufbauen(); });
        // weather and feasts only in the hallway (as before)
        if (window.MonitorEffekte && modus === 'flur') {
            // the footer is an opaque box: figures stand on its top edge
            window.MonitorEffekte.start({buehne: el.mn, kaesten: '.mn-kasten', kiesel: null, dunkel: !!DATEN.dunkel, bandKante: true});
        }
    }

    window.addEventListener('load', start);
})();
