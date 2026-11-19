// Neues Design der Flurmonitore (Vorschau, include/monitor_neu.rb).
//
// Nur geladen, wenn die Adresse des Monitors ?design=neu oder
// ?design=neu-dunkel trägt. Dann ist das Skript von monitor.html abgeschaltet
// und dieses zeichnet dieselben Daten neu: dieselben Nachrichten über
// /ws_monitor (Vertretungsplan, Laufschrift, Bilder, Neu laden, Effekte), die
// Zeugniskonferenzen und die Wetter- und Festeffekte (monitor_effekte.js).
//
// - Blättern statt Scrollen: Was nicht auf eine Seite passt, kommt auf die
//   nächste; jede Seite steht STANDZEIT_S Sekunden, ein Balken im Fuß zeigt,
//   wie lange noch.
// - Feste Kacheln wie auf dem bisherigen Monitor: KLASSEN_ORDER der Reihe
//   nach in Spalten zu je sieben Klassen (vier Spalten), 11 und 12 höher.
//   Jede Klasse immer an derselben Stelle, auch ohne Änderungen. Was nicht in
//   eine Kachel passt, blättert in der Kachel; alle Kacheln im selben Takt.
// - Uhr und laufende Stunde im Kopf (Zeit des Servers, Stundenraster aus
//   HOURS_FOR_KLASSE).
// - Alles als Text eingesetzt (textContent), nie als HTML.
(function () {
    'use strict';

    const STANDZEIT_S = 15;
    const NACHRICHT_S = 10;
    const BILD_S = 30;
    // ab so vielen Minuten zwischen zwei Stunden ist es eine Pause (sonst Wechsel)
    const PAUSE_AB_MIN = 10;

    let DATEN = null;
    let KLASSEN_TR = {};
    let KLASSEN = [];

    let serverDiff = 0;           // ms, Uhr des Servers minus Uhr des Monitors
    let plan = null;              // {heute, stand, klassen: {klasse: [Einträge]}}
    let letzterStand = null;
    let nachrichten = [];
    let nachrichtIndex = 0;
    let nachrichtUhr = null;
    let bilder = [];
    let bildIndex = 0;
    let bildUhr = null;
    let zk = false;               // Zeugniskonferenzen statt Vertretungsplan

    let kacheln = [];             // [{klasse, el, box, zeilen, seiten: [[von, bis], …], zeigt}]
    let schritt = 0;
    let schrittStart = 0;

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
    // Ein Eintrag des Vertretungsplans als Zeile: Stunde, Marke, Fach, Rest

    function marke(e) {
        const text = e.vertretungs_text || '';
        const la = liste(e.lehrer_alt), ln = liste(e.lehrer_neu);
        if (/entf[äa]ll|f[äa]llt aus/i.test(text)) return ['Entfall', 'e'];
        if ((e.fach_neu || '').substring(0, 5) === 'Test-') return ['Testung', 'e'];
        if (/klausur/i.test(text)) return ['Klausur', 'v'];
        if (/verleg/i.test(text)) return ['Verlegt', 'r'];
        if (/aufgabe/i.test(text)) return ['Aufgaben', 'v'];
        // a substitution needs no mark: »Hb statt Se« says it, and the mark
        // took a third of the line (entries wrapped, tiles paged)
        if (e.raum_alt && e.raum_neu && e.raum_alt !== e.raum_neu) return ['Raum', 'r'];
        return null;
    }

    function zeileBauen(e, klasse) {
        const z = h('div', 'mn-zeile');
        if (e.type === 'extra') {
            z.appendChild(h('span', 'mn-st', ''));
            z.appendChild(h('span', 'mn-was', nurText(e.salzh_sus_label)));
            return z;
        }
        z.appendChild(h('span', 'mn-st', String(e.stunde_label || '').replace(/\s+/g, '')));
        const was = h('span', 'mn-was');
        const m = marke(e);
        const entfall = m && m[1] === 'e';
        if (m) was.appendChild(h('span', `mn-marke mn-m-${m[1]}`, m[0]));
        const testung = (e.fach_neu || '').substring(0, 5) === 'Test-';
        const fa = e.fach_alt || '', fn = testung ? '' : (e.fach_neu || '');
        // what is now in full, what it replaces quietly behind it (»statt …«),
        // so that the eye finds the new state first
        const teile = [];
        const statt = (neu, alt) => {
            const f = document.createDocumentFragment();
            f.appendChild(document.createTextNode(neu));
            if (alt) f.appendChild(h('span', 'mn-alt', ` statt ${alt}`));
            return f;
        };
        const fachStatt = !!(fa && fn && fa !== fn);
        if (fachStatt) {
            was.appendChild(h('b', null, fn));
            was.appendChild(h('span', 'mn-alt', ` statt ${fa}`));
        } else if (fn || fa) {
            was.appendChild(h('b', null, fn || fa));
        }
        const la = liste(e.lehrer_alt), ln = liste(e.lehrer_neu);
        if (!entfall && !testung) {
            if (la.length && ln.length && la.join(',') !== ln.join(',')) teile.push(statt(ln.join(', '), la.join(', ')));
            else if (ln.length) teile.push(statt(ln.join(', ')));
            else if (la.length) teile.push(statt(la.join(', ')));
            const ra = e.raum_alt || '', rn = e.raum_neu || '';
            if (ra && rn && ra !== rn) teile.push(statt(rn, ra));
            else if (rn || ra) teile.push(statt(rn || ra));
        }
        // weitere Klassen derselben Stunde
        const andere = liste([].concat(e.klassen_neu || [], e.klassen_alt || []))
            .filter((k, i, a) => a.indexOf(k) === i && k !== klasse).map(tr);
        if (andere.length) teile.push(statt(`mit ${andere.join(', ')}`));
        teile.forEach((t, i) => {
            // »Gewi statt Sp, Va statt Wg«: after a changed subject a comma
            const vorne = i === 0 ? (fachStatt ? ', ' : (was.childNodes.length ? ' ' : '')) : ', ';
            if (vorne) was.appendChild(document.createTextNode(vorne));
            was.appendChild(t);
        });
        let text = String(e.vertretungs_text || '').trim();
        // the mark says it already: »entfällt; verlegt auf …« → »verlegt auf …«
        if (entfall) text = text.replace(/^(entf[äa]llt|f[äa]llt aus|entfall)\s*[.;,:–-]?\s*/i, '');
        if (text) {
            if (was.childNodes.length) was.appendChild(document.createTextNode(' '));
            was.appendChild(h('span', 'mn-text', text));
        }
        z.appendChild(was);
        return z;
    }

    function eintraege(klasse) {
        return (plan && plan.klassen && plan.klassen[klasse]) || [];
    }

    function passt(e) { return e.scrollHeight <= e.clientHeight + 1; }

    // ------------------------------------------------------------------
    // Feste Kacheln, verteilt wie auf dem bisherigen Monitor (monitor.html):
    // KLASSEN_ORDER der Reihe nach von oben nach unten in Spalten zu je
    // sieben Klassen, vier Spalten nebeneinander; 11 und 12 sind höher
    // (9,8 statt 6,2 vw, Abstand 1 vw), mit denselben Verhältnissen wie dort.
    // Jede Klasse hat immer ihre Kachel an derselben Stelle, auch ohne
    // Änderungen (dann nur der Name, leise); leere Plätze gibt es nicht. Wer
    // mehr hat, als in die Kachel passt, blättert in der Kachel.

    const PRO_SPALTE = 7;
    const MIN_SPALTEN = 4;
    // Höhen in Zehntel-vw des bisherigen Monitors; das Raster wird so
    // gestreckt, dass die höchste Spalte (mindestens sieben normale Kacheln)
    // den Platz zwischen Kopf und Fuß füllt
    const HOEHE = 62, HOEHE_HOCH = 98, ABSTAND = 10;

    function istHoch(k) { return k === '11' || k === '12'; }

    function kachelBauen(klasse) {
        const k = h('div', 'mn-kasten mn-kachel' + (istHoch(klasse) ? ' mn-hoch' : ''));
        k.dataset.klasse = klasse;
        const name = h('div', 'mn-name');
        name.appendChild(h('h2', null, tr(klasse)));
        const punkte = name.appendChild(h('div', 'mn-kseite'));
        const box = h('div', 'mn-zeilen');
        k.appendChild(name);
        k.appendChild(box);
        return {klasse: klasse, el: k, box: box, punkte: punkte,
                zeilen: [], seiten: [[0, 0]], zeigt: null};
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
        for (const kachel of kacheln) kachelKopf(kachel, 0);
    }

    function kachelKopf(kachel, seite) {
        const n = kachel.zeilen.length;
        const seiten = kachel.seiten.length;
        kachel.el.classList.toggle('mn-still', n === 0);
        // a tile that pages: »1/2« under the name (dots read like a status)
        kachel.punkte.textContent = seiten > 1 ? `${seite + 1}/${seiten}` : '';
    }

    // Seiten einer Kachel: so viele Zeilen, wie hineinpassen
    function kachelBerechnen(kachel) {
        kachel.zeilen = eintraege(kachel.klasse).map((e) => zeileBauen(e, kachel.klasse));
        // zum Messen: Kopf mit Seitenzahl wie bei mehreren Seiten
        kachel.seiten = [[0, 0], [0, 0]];
        kachelKopf(kachel, 0);
        const box = kachel.box;
        box.textContent = '';
        const seiten = [];
        let start = 0;
        for (let j = 0; j < kachel.zeilen.length; j++) {
            box.appendChild(kachel.zeilen[j].cloneNode(true));
            if (!passt(box) && j > start) {
                seiten.push([start, j]);
                box.textContent = '';
                start = j;
                box.appendChild(kachel.zeilen[j].cloneNode(true));
            }
        }
        seiten.push([start, kachel.zeilen.length]);
        kachel.seiten = seiten;
        kachel.zeigt = null;
        box.textContent = '';
    }

    function kachelZeigen(kachel, seite) {
        const [von, bis] = kachel.seiten[seite];
        kachel.box.textContent = '';
        for (let i = von; i < bis; i++) kachel.box.appendChild(kachel.zeilen[i].cloneNode(true));
        kachelKopf(kachel, seite);
    }

    // ------------------------------------------------------------------
    // Seiten: alle Kacheln blättern im selben Takt

    function seitenZahl() {
        return Math.max(1, ...kacheln.map((k) => k.seiten.length));
    }

    function neuBerechnen() {
        if (zk || !plan) return;
        for (const k of kacheln) kachelBerechnen(k);
        schritt = schritt % seitenZahl();
        schrittZeigen(false);
    }

    function schrittZeigen(blenden) {
        schrittStart = Date.now();
        for (const kachel of kacheln) {
            const seite = schritt % kachel.seiten.length;
            if (kachel.zeigt === seite) continue;
            kachel.zeigt = seite;
            if (blenden && !bewegungAus()) {
                kachel.box.classList.add('mn-weg');
                setTimeout(() => { kachelZeigen(kachel, seite); kachel.box.classList.remove('mn-weg'); }, 300);
            } else {
                kachelZeigen(kachel, seite);
            }
        }
        const n = seitenZahl();
        el.mn.dataset.seite = String(schritt + 1);
        el.mn.dataset.seiten = String(n);
        el.seite.hidden = n < 2;
        el.balken.hidden = n < 2;
        el.seite.textContent = `Seite ${schritt + 1} von ${n}`;
        const b = el.balken.firstChild;
        if (b.getAnimations) for (const a of b.getAnimations()) a.cancel();
        if (n > 1 && b.animate) {
            b.animate([{width: '0%'}, {width: '100%'}], {duration: STANDZEIT_S * 1000, easing: 'linear', fill: 'forwards'});
        }
    }

    function bewegungAus() {
        return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    }

    function takt() {
        uhrZeigen();
        if (zk) { zkZeitenZeigen(); return; }
        if (!plan) return;
        if ((Date.now() - schrittStart) / 1000 >= STANDZEIT_S) {
            schritt = (schritt + 1) % seitenZahl();
            schrittZeigen(true);
        }
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
    // Fuß: Nachrichten nacheinander, lange laufen einmal durch

    function nachrichtenStarten() {
        clearTimeout(nachrichtUhr);
        nachrichtIndex = 0;
        nachrichtZeigen();
    }

    function nachrichtZeigen() {
        const box = el.nachricht;
        box.textContent = '';
        if (!nachrichten.length) return;
        nachrichtIndex %= nachrichten.length;
        const span = h('span');
        span.appendChild(h('i', 'ti ti-speakerphone'));
        span.appendChild(document.createTextNode(nachrichten[nachrichtIndex]));
        box.appendChild(span);
        let dauer = NACHRICHT_S * 1000;
        const ueber = span.scrollWidth - box.clientWidth;
        box.classList.toggle('mn-lang', ueber > 2);
        if (ueber > 2 && span.animate && !bewegungAus()) {
            const vw = window.innerWidth / 100;
            const lauf = (ueber / (6 * vw)) * 1000;
            const halt = 2000;
            dauer = Math.max(dauer, lauf + 2 * halt);
            span.animate([
                {transform: 'translateX(0)', offset: 0},
                {transform: 'translateX(0)', offset: halt / dauer},
                {transform: `translateX(${-ueber}px)`, offset: (halt + lauf) / dauer},
                {transform: `translateX(${-ueber}px)`, offset: 1},
            ], {duration: dauer, fill: 'forwards'});
        }
        nachrichtUhr = setTimeout(() => {
            nachrichtIndex = (nachrichtIndex + 1) % Math.max(1, nachrichten.length);
            nachrichtZeigen();
        }, dauer);
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
        const tag = (paket.data || {})[heute] || {};
        return {heute: heute, stand: tag.vplan_timestamp || paket.vplan_timestamp || null, klassen: tag.klassen || {}};
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
            bilder = ((d.data || {}).images || []).map(String);
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
        const mn = h('div', 'mn' + (DATEN.dunkel ? ' mn-dunkel' : ''));
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
        el.seite = el.fuss.appendChild(h('span', 'mn-seite'));
        el.balken = el.fuss.appendChild(h('div', 'mn-balken'));
        el.balken.appendChild(h('b'));
        el.seite.hidden = true;
        el.balken.hidden = true;
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
        zk = !!(DATEN.zeugniskonferenzen || {}).an;
        aufbauen();
        datumZeigen();
        uhrZeigen();
        if (zk) {
            zkZeigen();
        } else {
            rasterAufbauen();
        }
        verbinden();
        setInterval(takt, 1000);
        let warten = null;
        window.addEventListener('resize', () => { clearTimeout(warten); warten = setTimeout(neuBerechnen, 300); });
        if (document.fonts && document.fonts.ready) document.fonts.ready.then(() => neuBerechnen());
        if (window.MonitorEffekte) {
            window.MonitorEffekte.start({buehne: el.mn, kaesten: '.mn-kasten', kiesel: null, dunkel: !!DATEN.dunkel});
        }
    }

    window.addEventListener('load', start);
})();
