// Wetter- und Festeffekte für die Monitore im Schulhaus.
//
// Wetter: nur bei markanten amtlichen Warnungen des Deutschen Wetterdienstes
// für das eigene Warngebiet (der Server fragt den DWD, siehe
// src/ruby/monitor_effekte.rb). Feste: Advent/Weihnachten und die Tage vor
// Ostern.
//
// Grundsatz: Der Monitor bleibt lesbar. Fast alles läuft HINTER den Kästen
// (die Kästen sind durchscheinend und weichgezeichnet, man sieht es also
// gedämpft hindurch); vorne gibt es nur wenige, kurze Auftritte.
//
// Vorschau ohne echte Warnung: /monitor?effekt=schnee (auch regen, gewitter,
// hitze, sturm, frost, weihnachten, ostern; mehrere mit Komma, dazu
// &staerke=1..3). In der Vorschau läuft alles im Zeitraffer.
// ?effekt=rundgang zeigt alle Effekte nacheinander, je 40 Sekunden.
(function () {
    'use strict';

    const NS = 'http://www.w3.org/2000/svg';
    const WETTER = ['schnee', 'regen', 'gewitter', 'hitze', 'sturm', 'frost'];
    const FESTE = ['weihnachten', 'nikolaus', 'ostern', 'valentinstag', 'fasching', 'sommerferien', 'schulanfang', 'adventskonzert', 'forschertag'];
    const ABFRAGE_ALLE_MS = 10 * 60 * 1000;
    const RUNDGANG_MS = 40 * 1000;

    let opt = null;
    let buehne = null;
    let cvH = null, cxH = null;   // Leinwand hinter den Kästen
    let cvV = null, cxV = null;   // Leinwand vor den Kästen
    let domH = null, domV = null; // Ebenen für SVG-Figuren (hinten/vorne)
    let W = 0, H = 0, VW = 1, DPR = 1;
    let UNTEN = 0;                // Boden für Figuren: sichtbarer Rand, über einem laufenden Schriftband
    let SICHTBAR_UNTEN = 0;
    let LAUF_BODEN = 0;           // Boden für kurz durchlaufende Figuren: knapp auf der Schrift im Band       // unterer sichtbarer Rand der Bühne (Fenster flacher als 16:9)
    let kaesten = [];             // [{el, x, y, w, h}] relativ zur Bühne
    let kaestenZeit = 0;
    let wetter = null;            // laufender Wettereffekt
    let fest = null;              // laufender Festeffekt
    let zustand = {wetter: '', fest: ''};
    let vorschau = false;
    let laeuft = false;
    let letzte = 0;
    let funken = [];              // Glitzer auf der vorderen Leinwand
    let sprites = {};

    // ------------------------------------------------------------------
    // Hilfsfunktionen

    function zufall(a, b) { return a + Math.random() * (b - a); }
    function auswahl(liste) { return liste[Math.floor(Math.random() * liste.length)]; }
    function svg(tag, attrs, kinder) {
        const e = document.createElementNS(NS, tag);
        for (const k in (attrs || {})) e.setAttribute(k, attrs[k]);
        for (const k of (kinder || [])) e.appendChild(k);
        return e;
    }
    function svgAusText(text) {
        const t = document.createElement('template');
        t.innerHTML = text.trim();
        return t.content.firstChild;
    }
    function leinwand(w, h) {
        const c = document.createElement('canvas');
        c.width = Math.max(1, Math.ceil(w));
        c.height = Math.max(1, Math.ceil(h));
        return c;
    }
    let idZaehler = 0;
    function neueId(name) { idZaehler += 1; return `fx-${name}-${idZaehler}`; }

    // Zeitraffer in der Vorschau: aus Minuten werden Sekunden
    function dauer(echt, vorschauWert) { return vorschau ? vorschauWert : echt; }

    // ------------------------------------------------------------------
    // Gestaltung (CSS wird einmal in die Seite gelegt)

    const CSS = `
    .fx-ebene { position: absolute; left: 0; top: 0; width: 100%; height: 100%; pointer-events: none; overflow: hidden; }
    .fx-fixiert { position: fixed; }
    .fx-vorne-ebene { z-index: 60; }
    /* das Schriftband unten hat immer Vorrang: es liegt über allen Effekten (Aussehen unverändert) */
    .ticker { z-index: 62; }
    canvas.fx-vorne-ebene { z-index: 59; }
    .fx-deko { position: absolute; pointer-events: none; display: block; overflow: visible; }
    .fx-wachsen { transform-origin: 50% 100%; transform: scaleY(0.15); transition-property: transform; transition-timing-function: cubic-bezier(.2,.7,.3,1); }
    .fx-wachsen.fx-hangend { transform-origin: 50% 0%; }
    .fx-wachsen.fx-gewachsen { transform: scaleY(1); }

    /* Hitze: tropfende Kästen. Im SVG ist 1px eine Einheit des viewBox und die
       ist hier 1vw breit – daher px in den Längen. */
    .fx-geschmolzen { background-color: transparent !important; box-shadow: none !important;
        -webkit-backdrop-filter: none !important; backdrop-filter: none !important; }
    .fx-kiesel-schief { transform: translateY(.2vw) rotate(-7deg); transition: transform 3s ease-in; }
    .fx-tropfnase { transform-box: fill-box; transform-origin: 50% 0%; animation: fx-tropfnase var(--d) ease-in-out infinite; animation-delay: var(--v); }
    @keyframes fx-tropfnase { 0% { transform: scaleY(.55); } 68% { transform: scaleY(1); } 74% { transform: scaleY(.62); } 100% { transform: scaleY(.55); } }
    .fx-tropfen { transform-box: fill-box; transform-origin: 50% 50%; animation: fx-tropfen var(--d) ease-in infinite; animation-delay: var(--v); opacity: 0; }
    @keyframes fx-tropfen {
        0% { transform: translateY(calc(var(--l) * .5)) scale(.2); opacity: 0; }
        60% { transform: translateY(calc(var(--l) * .96)) scale(1); opacity: 1; }
        68% { transform: translateY(calc(var(--l) * 1.0)) scale(1); opacity: 1; }
        100% { transform: translateY(calc(var(--l) + 3.5px)) scale(.85, 1.15); opacity: 0; }
    }

    /* Hitze: Sonne */
    .fx-sonne { position: absolute; width: 50vw; height: 50vw; right: -19vw; top: -21vw; border-radius: 50%;
        background: radial-gradient(circle, rgba(255,253,235,1) 0 8%, rgba(255,226,130,.95) 12%, rgba(255,186,70,.55) 24%, rgba(255,150,50,.22) 42%, rgba(255,140,40,0) 68%);
        animation: fx-sonne-puls 7s ease-in-out infinite alternate; }
    .fx-sonne-strahlen { position: absolute; left: -30%; top: -30%; width: 160%; height: 160%; border-radius: 50%;
        background: repeating-conic-gradient(from 0deg, rgba(255,226,140,.38) 0deg 3.5deg, rgba(255,226,140,0) 3.5deg 13deg);
        -webkit-mask: radial-gradient(circle, transparent 9%, #000 15%, rgba(0,0,0,.6) 35%, transparent 62%);
        mask: radial-gradient(circle, transparent 9%, #000 15%, rgba(0,0,0,.6) 35%, transparent 62%);
        animation: fx-drehen 140s linear infinite; }
    @keyframes fx-sonne-puls { from { transform: scale(1); } to { transform: scale(1.06); } }
    @keyframes fx-drehen { to { transform: rotate(1turn); } }
    .fx-hitze-toenung { position: absolute; left: 0; top: 0; width: 100%; height: 100%;
        background: radial-gradient(ellipse at 96% 0%, rgba(255,166,60,.30), rgba(255,130,40,.12) 45%, rgba(255,100,30,0) 78%),
                    linear-gradient(to top, rgba(255,128,40,.14), rgba(255,128,40,0) 45%); }
    .fx-hitze-glanz { position: absolute; width: 44vw; height: 44vw; right: -16vw; top: -18vw; border-radius: 50%;
        background: radial-gradient(circle, rgba(255,214,120,.22), rgba(255,190,90,.10) 40%, rgba(255,190,90,0) 70%); }

    /* Frost: Eiszapfen und vereiste Ränder */
    .fx-zapfen-glitzer { animation: fx-glitzern var(--d) ease-in-out infinite; animation-delay: var(--v); opacity: 0; }
    @keyframes fx-glitzern { 0%, 80%, 100% { opacity: 0; transform: scale(.4); } 88% { opacity: 1; transform: scale(1); } }
    .fx-frost-kasten { box-shadow: 0 0 .5vw rgba(0,0,0,.35), inset 0 0 .9vw rgba(175,212,255,.95), inset 0 0 .25vw rgba(255,255,255,1) !important; transition: box-shadow 4s; }

    /* Gewitter: Kästen zucken beim Donner */
    .fx-beben { animation: fx-beben 1.5s cubic-bezier(.3,.05,.3,1) both; animation-delay: var(--v, 0s); }
    @keyframes fx-beben {
        0% { transform: none; } 6% { transform: translate(-.45vw, .2vw) rotate(-.7deg); } 12% { transform: translate(.5vw, -.15vw) rotate(.8deg); }
        20% { transform: translate(-.4vw, .25vw) rotate(-.5deg); } 30% { transform: translate(.35vw, -.1vw) rotate(.45deg); }
        42% { transform: translate(-.22vw, .1vw) rotate(-.25deg); } 56% { transform: translate(.14vw, 0) rotate(.15deg); }
        72% { transform: translate(-.06vw, 0) rotate(-.05deg); } 100% { transform: none; } }
    .fx-zucken { animation: fx-zucken .75s cubic-bezier(.36,.07,.19,.97) both; animation-delay: var(--v, 0s); }
    @keyframes fx-zucken {
        10%, 90% { transform: translate(-.05vw, 0); } 20%, 80% { transform: translate(.1vw, .03vw); }
        30%, 50%, 70% { transform: translate(-.16vw, -.03vw); } 40%, 60% { transform: translate(.16vw, .02vw); } }

    /* Weihnachtsmann */
    .fx-rodel { position: absolute; left: 0; top: 0; width: 6.5vw; will-change: transform; overflow: visible; filter: drop-shadow(0 .15vw .2vw rgba(40,60,90,.3)); }
    .fx-rodel .fx-schal { transform-box: fill-box; transform-origin: 100% 30%; animation: fx-schal .18s ease-in-out infinite alternate; }
    @keyframes fx-schal { from { transform: skewY(-6deg) scaleY(.9); } to { transform: skewY(5deg) scaleY(1.1); } }
    .fx-wichtel { position: absolute; left: 0; top: 0; width: 4.6vw; will-change: transform; overflow: visible; filter: drop-shadow(0 .15vw .2vw rgba(0,0,0,.3)); }
    .fx-wichtel .fx-wb-bein { transform-box: fill-box; transform-origin: 50% 5%; }
    .fx-wichtel.fx-geht .fx-wb-a { animation: fx-gehen-a .42s ease-in-out infinite; }
    .fx-wichtel.fx-geht .fx-wb-b { animation: fx-gehen-b .42s ease-in-out infinite; }
    .fx-wichtel .fx-glocke { transform-box: fill-box; transform-origin: 50% 0; animation: fx-glocke .42s ease-in-out infinite alternate; }
    @keyframes fx-glocke { from { transform: rotate(-14deg); } to { transform: rotate(14deg); } }
    .fx-geschenk-fliegt { position: absolute; left: 0; top: 0; will-change: transform; }
    .fx-schlitten-flug { position: absolute; left: 0; top: 0; width: 32vw; will-change: transform; filter: drop-shadow(0 .4vw .5vw rgba(0,0,0,.28)); }
    .fx-bein { transform-box: fill-box; transform-origin: 50% 4%; animation: fx-bein-vorn .62s ease-in-out infinite; animation-delay: var(--v); }
    .fx-bein.fx-hinten { animation-name: fx-bein-hinten; }
    @keyframes fx-bein-vorn { 0%, 100% { transform: rotate(-58deg); } 50% { transform: rotate(12deg); } }
    @keyframes fx-bein-hinten { 0%, 100% { transform: rotate(48deg); } 50% { transform: rotate(-22deg); } }
    .fx-kopfnicken { transform-box: fill-box; transform-origin: 20% 90%; animation: fx-nicken .62s ease-in-out infinite; animation-delay: var(--v); }
    @keyframes fx-nicken { 0%, 100% { transform: rotate(-4deg); } 50% { transform: rotate(5deg); } }
    .fx-winken { transform-box: fill-box; transform-origin: 85% 95%; animation: fx-winken 1.1s ease-in-out infinite; }
    @keyframes fx-winken { 0%, 100% { transform: rotate(-18deg); } 50% { transform: rotate(22deg); } }
    .fx-bommel { transform-box: fill-box; transform-origin: 100% 60%; animation: fx-bommel 1.24s ease-in-out infinite; }
    @keyframes fx-bommel { 0%, 100% { transform: rotate(-6deg); } 50% { transform: rotate(8deg); } }
    .fx-nasenlicht { animation: fx-nasenlicht 1.4s ease-in-out infinite alternate; }
    @keyframes fx-nasenlicht { from { opacity: .45; } to { opacity: 1; } }

    /* Sturm: Schülertrupp bringt weggeflogene Kacheln zurück */
    .fx-trupp { position: absolute; left: 0; top: 0; will-change: transform; filter: drop-shadow(0 .2vw .25vw rgba(0,0,0,.25)); overflow: visible; }
    .fx-trupp.fx-traeger { width: 10.5vw; }
    .fx-trupp.fx-hammerkind { width: 5vw; }
    .fx-trupp .fx-tragarm { transform-box: fill-box; transition: transform .7s ease-in-out; }
    .fx-trupp .fx-tragarm-l { transform-origin: 70% 96%; }
    .fx-trupp .fx-tragarm-r { transform-origin: 30% 96%; }
    .fx-trupp.fx-arme-runter .fx-tragarm-l { transform: rotate(-160deg); }
    .fx-trupp.fx-arme-runter .fx-tragarm-r { transform: rotate(160deg); }
    .fx-trupp .fx-glied { transform-box: fill-box; transform-origin: 50% 4%; }
    .fx-trupp.fx-geht .fx-kbein-a { animation: fx-gehen-a .62s ease-in-out infinite; }
    .fx-trupp.fx-geht .fx-kbein-b { animation: fx-gehen-b .62s ease-in-out infinite; }
    @keyframes fx-gehen-a { 0%, 100% { transform: rotate(22deg); } 50% { transform: rotate(-22deg); } }
    @keyframes fx-gehen-b { 0%, 100% { transform: rotate(-22deg); } 50% { transform: rotate(22deg); } }
    .fx-trupp .fx-hammerarm { transform-box: fill-box; transform-origin: 80% 90%; transform: rotate(-129deg); transition: transform .4s ease-out; }
    .fx-trupp.fx-geht .fx-hammerarm { animation: fx-hammer-pendel .62s ease-in-out infinite alternate; }
    @keyframes fx-hammer-pendel { from { transform: rotate(-112deg); } to { transform: rotate(-146deg); } }
    .fx-trupp.fx-haemmert .fx-hammerarm { animation: fx-hammer .32s ease-in infinite; }
    /* Klettern: Beine mit Knie und die Greifhand werden pro Bild berechnet (fx-ik) */
    .fx-trupp .fx-ik-glied { display: none; }
    .fx-trupp.fx-ik .fx-ik-glied { display: inline; }
    .fx-trupp.fx-ik .fx-kbein-a, .fx-trupp.fx-ik .fx-kbein-b, .fx-trupp.fx-ik .fx-haltearm { display: none; }
    @keyframes fx-hammer { 0%, 100% { transform: rotate(-70deg); } 60% { transform: rotate(25deg); } }
    .fx-fallschirm-gruppe { position: absolute; left: 0; top: 0; width: 10vw; height: 17.5vw; transform-origin: 50% 8%; will-change: transform; }
    .fx-fallschirm { position: absolute; left: 0; top: 0; width: 10vw; overflow: visible; transform-origin: 50% 70%; }
    .fx-kachel-getragen { position: absolute; left: 0; top: 0; will-change: transform; background: rgba(255,255,255,.88);
        border-radius: .5vw; box-shadow: 0 0 .4vw rgba(0,0,0,.35); transform-origin: 0 0; }
    .fx-kachel-getragen b { position: absolute; left: -.9vw; top: -.9vw; width: 1.9vw; height: 1.9vw; border-radius: .9vw; background: #fff;
        box-shadow: 0 0 .3vw rgba(0,0,0,.4); font: bold .9vw/1.9vw sans-serif; text-align: center; color: #333; }
    .fx-sprechblase { position: absolute; left: 0; top: 0; background: #fff; color: #222; font: bold 1vw/1.3 sans-serif; padding: .25vw .6vw;
        border-radius: .8vw; box-shadow: 0 .1vw .3vw rgba(0,0,0,.3); white-space: nowrap; transition: opacity .3s; }

    /* Gewitter: Zeus */
    .fx-zeus .fx-knistern { animation: fx-knistern .18s steps(2) infinite; }
    @keyframes fx-knistern { 0% { opacity: 1; } 50% { opacity: .15; } }
    .fx-zeus { position: absolute; left: 0; top: 0; width: 24vw; will-change: transform, opacity; overflow: visible; }

    /* Glatteis: Eisläufer */
    .fx-eislaeufer { position: absolute; left: 0; top: 0; will-change: transform; filter: drop-shadow(0 .2vw .25vw rgba(0,0,0,.22)); overflow: visible; }
    .fx-eislaeufer .fx-schal { transform-box: fill-box; transform-origin: 100% 20%; animation: fx-schal .5s ease-in-out infinite alternate; }
    @keyframes fx-schal { from { transform: skewY(-6deg) scaleX(.95); } to { transform: skewY(5deg) scaleX(1.05); } }

    /* Hitze: Eiswagen */
    .fx-eiswagen { position: absolute; left: 0; top: 0; width: 24vw; will-change: transform; filter: drop-shadow(0 .3vw .35vw rgba(0,0,0,.22)); }
    .fx-rad { transform-box: fill-box; transform-origin: 50% 50%; animation: fx-drehen .7s linear infinite; }
    .fx-kugel-tropfen { transform-box: fill-box; transform-origin: 50% 0%; animation: fx-kugel-tropfen 3.2s ease-in infinite; }
    @keyframes fx-kugel-tropfen { 0%, 40% { transform: scaleY(.3); } 85% { transform: scaleY(1); } 100% { transform: scaleY(.3); } }

    .fx-zeitraffer { position: absolute; left: 50%; bottom: 5.5vw; transform: translateX(-50%); background: rgba(20,24,30,.72); color: #fff;
        font: bold 1.2vw/1.6 sans-serif; padding: .2vw 1vw; border-radius: 1vw; font-variant-numeric: tabular-nums; white-space: nowrap; }

    /* Starkregen ab Rot: Forschungs-U-Boot */
    .fx-uboot { position: absolute; left: 0; top: 0; width: 12vw; will-change: transform; overflow: visible; filter: drop-shadow(0 .2vw .3vw rgba(0,30,60,.35)); }
    .fx-ente { position: absolute; left: 0; top: 0; will-change: transform; overflow: visible; filter: drop-shadow(0 .1vw .15vw rgba(0,30,60,.3)); }
    .fx-uboot .fx-propeller { transform-box: fill-box; transform-origin: 50% 50%; animation: fx-propeller .15s linear infinite; }
    .fx-uboot .fx-uboot-lampe { animation: fx-uboot-lampe 2.4s ease-in-out infinite; }
    @keyframes fx-uboot-lampe { 0%, 100% { opacity: 1; } 50% { opacity: .75; } }

    /* Valentinstag, Fasching, letzter Schultag */
    .fx-amor { position: absolute; left: 0; top: 0; width: 10vw; will-change: transform; filter: drop-shadow(0 .25vw .35vw rgba(0,0,0,.3)); overflow: visible; }
    .fx-amor .fx-amor-fluegel { transform-box: fill-box; transform-origin: 92% 88%; animation: fx-fluegel .2s ease-in-out infinite alternate; }
    @keyframes fx-fluegel { from { transform: rotate(-16deg); } to { transform: rotate(14deg); } }
    .fx-amor .fx-amor-zug { display: none; }
    .fx-amor.fx-amor-gespannt .fx-amor-zug { display: inline; }
    .fx-amor.fx-amor-gespannt .fx-amor-ruhe { display: none; }
    .fx-amor-pfeilflug { position: absolute; left: 0; top: 0; width: 5vw; transform-origin: 100% 50%; will-change: transform, opacity; overflow: visible; }
    .klasse.fx-amor-treffer { animation: fx-amor-treffer 2.4s ease-out; }
    .klasse.fx-amor-verliebt { background-color: rgba(255,190,212,.92) !important; box-shadow: 0 0 1vw rgba(255,80,130,.55) !important; }
    .klasse.fx-amor-weich { transition: background-color 1.8s ease, box-shadow 1.8s ease; }
    @keyframes fx-amor-treffer { 0% { box-shadow: 0 0 0 0 rgba(255,70,120,0); } 12% { box-shadow: 0 0 1.8vw .6vw rgba(255,70,120,.9); } 100% { box-shadow: 0 0 0 0 rgba(255,70,120,0); } }
    .fx-herzballons { position: absolute; left: 0; top: 0; width: 8vw; will-change: transform; filter: drop-shadow(0 .3vw .3vw rgba(0,0,0,.2)); overflow: visible; }
    @keyframes fx-luftschlange { from { transform: rotate(-4deg); } to { transform: rotate(5deg); } }
    .fx-flugzeug { position: absolute; left: 0; top: 0; width: 40vw; will-change: transform; filter: drop-shadow(0 .3vw .3vw rgba(0,0,0,.2)); overflow: visible; }
    .fx-flugzeug .fx-propeller { transform-box: fill-box; transform-origin: 50% 50%; animation: fx-propeller .12s linear infinite; }
    @keyframes fx-propeller { 0%, 100% { transform: scaleY(1); } 50% { transform: scaleY(.15); } }
    .fx-flugzeug .fx-banner { transform-box: fill-box; transform-origin: 100% 50%; animation: fx-banner .7s ease-in-out infinite alternate; }
    @keyframes fx-banner { from { transform: skewY(-1.2deg) scaleY(.98); } to { transform: skewY(1.2deg) scaleY(1.02); } }

    /* Weihnachten: Geschenke hinter den Kacheln */
    .fx-geschenk { position: absolute; left: 0; top: 0; width: 2.2vw; will-change: transform; transition: opacity 2s; }
    .fx-geschenk svg { display: block; width: 100%; height: auto; overflow: visible; animation: fx-ei-auftauchen .8s cubic-bezier(.3,1.6,.5,1) both; transform-origin: 50% 90%; }

    /* Osterhase und Eier */
    .fx-hase { position: absolute; left: 0; top: 0; width: 8.5vw; will-change: transform; filter: drop-shadow(0 .25vw .35vw rgba(0,0,0,.22)); }
    .fx-hase .fx-teil { transform-box: fill-box; }
    .fx-ei { position: absolute; left: 0; top: 0; width: 2.1vw; will-change: transform; }
    .fx-ei svg { display: block; width: 100%; height: auto; overflow: visible; animation: fx-ei-auftauchen .9s cubic-bezier(.3,1.6,.5,1) both; transform-origin: 50% 90%; }
    @keyframes fx-ei-auftauchen { from { transform: scale(0) rotate(var(--r)); } to { transform: scale(1) rotate(var(--r)); } }
    `;

    function cssEinfuegen() {
        if (document.getElementById('fx-stil')) return;
        const s = document.createElement('style');
        s.id = 'fx-stil';
        s.textContent = CSS;
        document.head.appendChild(s);
    }

    // ------------------------------------------------------------------
    // Ebenen, Größe, Kästen

    function ebenenAnlegen() {
        const fix = opt.fixiert ? ' fx-fixiert' : '';
        cvH = document.createElement('canvas');
        cvH.className = 'fx-ebene fx-hinten-ebene' + fix;
        domH = document.createElement('div');
        domH.className = 'fx-ebene fx-hinten-ebene' + fix;
        cvV = document.createElement('canvas');
        cvV.className = 'fx-ebene fx-vorne-ebene' + fix;
        domV = document.createElement('div');
        domV.className = 'fx-ebene fx-vorne-ebene' + fix;
        // hinten: als erste Kinder, damit alle späteren (positionierten) Kästen darüber liegen
        buehne.insertBefore(domH, buehne.firstChild);
        buehne.insertBefore(cvH, buehne.firstChild);
        buehne.appendChild(cvV);
        buehne.appendChild(domV);
        cxH = cvH.getContext('2d');
        cxV = cvV.getContext('2d');
        groesseAnpassen();
        window.addEventListener('resize', groesseAnpassen);
    }

    function groesseAnpassen() {
        const r = opt.fixiert ? {width: window.innerWidth, height: window.innerHeight} : buehne.getBoundingClientRect();
        W = Math.max(1, r.width);
        H = Math.max(1, r.height);
        VW = W / 100;
        // Die Monitorseite ist immer 16:9 breit; ist das Fenster flacher, wird
        // unten abgeschnitten. Figuren, die am Boden laufen, nehmen den sichtbaren Rand.
        SICHTBAR_UNTEN = Math.max(10 * VW, Math.min(H, window.innerHeight - (opt.fixiert ? 0 : r.top)));
        UNTEN = SICHTBAR_UNTEN;
        LAUF_BODEN = SICHTBAR_UNTEN;
        kaestenZeit = -1e9;   // Schriftband beim nächsten Bild neu messen
        DPR = Math.min(window.devicePixelRatio || 1, 1.5);
        for (const c of [cvH, cvV]) {
            c.width = Math.round(W * DPR);
            c.height = Math.round(H * DPR);
        }
        cxH.setTransform(DPR, 0, 0, DPR, 0, 0);
        cxV.setTransform(DPR, 0, 0, DPR, 0, 0);
        sprites = {};
        kaestenZeit = 0;
        for (const e of [wetter, fest]) if (e && e.groesse) e.groesse();
    }

    function kaestenMessen(t) {
        if (t - kaestenZeit < 1.0) return;
        kaestenZeit = t;
        const b = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
        kaesten = [];
        for (const el of document.querySelectorAll(opt.kaesten)) {
            const r = el.getBoundingClientRect();
            if (r.width < 2 * VW || r.height < 1 * VW) continue;
            if (r.bottom < 0 || r.top > H || r.right < 0 || r.left > W) continue;
            kaesten.push({el: el, x: r.left - b.left, y: r.top - b.top, w: r.width, h: r.height});
        }
        // Läuft unten ein Schriftband (Ticker mit Text), gehen die Figuren darüber,
        // damit es frei und lesbar bleibt.
        UNTEN = SICHTBAR_UNTEN;
        LAUF_BODEN = SICHTBAR_UNTEN;
        const band = document.querySelector('.ticker');
        if (band && band.textContent.trim() !== '') {
            const r = band.getBoundingClientRect();
            if (r.height > 0 && getComputedStyle(band).display !== 'none') {
                UNTEN = Math.max(10 * VW, Math.min(SICHTBAR_UNTEN, r.top - b.top - 0.2 * VW));
                // Figuren, die nur kurz durchlaufen, gehen knapp auf der Schrift (Wunsch Jonas)
                const zeile = band.querySelector('.ticker-message') || band;
                const zr = zeile.getBoundingClientRect();
                const schrift = parseFloat(getComputedStyle(zeile).fontSize) || 2.5 * VW;
                LAUF_BODEN = Math.max(UNTEN, Math.min(SICHTBAR_UNTEN, zr.top - b.top + schrift * 0.22));
            }
        }
        // Verabredung mit Jonas: das Schriftband bleibt von allen Effekten frei. Alle
        // Ebenen enden an seiner Oberkante; Wasser und Schnee steigen ab dort.
        // die vordere Ebene mit den durchlaufenden Figuren endet erst am Laufboden
        const schnittBei = (y) => { const frei = Math.max(0, H - y); return frei > 1 ? `inset(0 0 ${frei.toFixed(0)}px 0)` : ''; };
        for (const [ebene, y] of [[cvH, UNTEN], [domH, UNTEN], [cvV, LAUF_BODEN], [domV, LAUF_BODEN]]) {
            const schnitt = schnittBei(y);
            if (ebene && ebene.style.clipPath !== schnitt) ebene.style.clipPath = schnitt;
        }
    }

    // Deko in jeden Kasten (Schneehaube, Tropfen, Eiszapfen). Kästen, die die
    // Seite neu aufbaut, bekommen sie beim nächsten Durchlauf.
    function dekorieren(name, bauen) {
        for (const el of document.querySelectorAll(opt.kaesten)) {
            if (el.dataset.fxDeko === name) continue;
            const r = el.getBoundingClientRect();
            if (r.width < 2 * VW) continue;
            for (const alt of el.querySelectorAll(':scope > .fx-deko')) alt.remove();
            if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
            el.dataset.fxDeko = name;
            bauen(el, r.width / VW, r.height / VW);
        }
    }
    function dekoEntfernen() {
        for (const el of document.querySelectorAll('.fx-deko')) el.remove();
        for (const el of document.querySelectorAll('[data-fx-z]')) {
            el.style.zIndex = el.dataset.fxZ === '-' ? '' : el.dataset.fxZ;
            delete el.dataset.fxZ;
        }
        for (const el of document.querySelectorAll('[data-fx-deko]')) delete el.dataset.fxDeko;
        for (const el of document.querySelectorAll('.fx-frost-kasten')) el.classList.remove('fx-frost-kasten');
        for (const el of document.querySelectorAll('.fx-geschmolzen')) el.classList.remove('fx-geschmolzen');
        for (const el of document.querySelectorAll('.fx-kiesel-schief')) el.classList.remove('fx-kiesel-schief');
    }
    // Was unten am Kasten hängt (Tropfen, Eiszapfen), soll über den Kasten
    // darunter reichen dürfen: frühere Kästen kommen nach vorn. Der Kiesel des
    // nächsten Kastens bleibt frei, weil ganz links nichts hängt.
    function nachVorne(el) {
        if (el.dataset.fxZ) return;
        el.dataset.fxZ = el.style.zIndex || '-';
        // unter der vorderen Ebene (z-index 59/60) bleiben
        el.style.zIndex = String(Math.max(1, 50 - Array.prototype.indexOf.call(document.querySelectorAll(opt.kaesten), el)));
    }

    function wachsenLassen(el, sekunden) {
        el.classList.add('fx-wachsen');
        el.style.transitionDuration = `${sekunden}s`;
        requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('fx-gewachsen')));
    }

    // Alle Kästen kurz zucken/wackeln lassen, jeder etwas versetzt
    function kaestenRuetteln(klasse, dauerMs) {
        for (const k of kaesten) {
            const el = k.el;
            el.style.setProperty('--v', `${zufall(0, 0.12).toFixed(2)}s`);
            el.classList.remove(klasse);
            void el.offsetWidth;
            el.classList.add(klasse);
            setTimeout(() => el.classList.remove(klasse), dauerMs + 200);
        }
    }

    // ------------------------------------------------------------------
    // Sprites (einmal vorgezeichnet, danach nur noch kopiert)

    function weichPunkt(radiusPx, farbe, rand) {
        const s = Math.ceil(radiusPx * 2 + 4);
        const c = leinwand(s, s);
        const g = c.getContext('2d');
        const m = s / 2;
        if (rand) {
            const h = g.createRadialGradient(m, m, radiusPx * 0.4, m, m, radiusPx);
            h.addColorStop(0, rand);
            h.addColorStop(1, 'rgba(0,0,0,0)');
            g.fillStyle = h;
            g.fillRect(0, 0, s, s);
        }
        const k = g.createRadialGradient(m, m, 0, m, m, radiusPx * (rand ? 0.72 : 1));
        k.addColorStop(0, farbe);
        k.addColorStop(0.5, farbe);
        k.addColorStop(1, farbe.replace(/[\d.]+\)$/, '0)'));
        g.fillStyle = k;
        g.fillRect(0, 0, s, s);
        return c;
    }

    function stern(radiusPx, farbe) {
        const s = Math.ceil(radiusPx * 2 + 4);
        const c = leinwand(s, s);
        const g = c.getContext('2d');
        const m = s / 2;
        const glanz = g.createRadialGradient(m, m, 0, m, m, radiusPx);
        glanz.addColorStop(0, farbe.replace(/[\d.]+\)$/, '.9)'));
        glanz.addColorStop(0.25, farbe.replace(/[\d.]+\)$/, '.35)'));
        glanz.addColorStop(1, farbe.replace(/[\d.]+\)$/, '0)'));
        g.fillStyle = glanz;
        g.fillRect(0, 0, s, s);
        g.fillStyle = 'rgba(255,255,255,.95)';
        g.beginPath();
        const a = radiusPx, b = radiusPx * 0.16;
        g.moveTo(m, m - a); g.quadraticCurveTo(m + b, m - b, m + a, m);
        g.quadraticCurveTo(m + b, m + b, m, m + a); g.quadraticCurveTo(m - b, m + b, m - a, m);
        g.quadraticCurveTo(m - b, m - b, m, m - a);
        g.fill();
        return c;
    }

    // Schneeflocke: weißer, weicher Kern; auf hellem Grund mit einem zarten,
    // leicht nach unten versetzten Schatten, damit man sie überhaupt sieht
    function flockeSprite(r, dunkel, weich) {
        const s = Math.ceil(r * 3 + 4);
        const c = leinwand(s, s);
        const g = c.getContext('2d');
        const m = s / 2;
        if (!dunkel) {
            const h = g.createRadialGradient(m, m + r * 0.25, 0, m, m + r * 0.25, r * 1.35);
            h.addColorStop(0, `rgba(70,95,130,${weich ? 0.16 : 0.42})`);
            h.addColorStop(1, 'rgba(70,95,130,0)');
            g.fillStyle = h;
            g.fillRect(0, 0, s, s);
        }
        const k = g.createRadialGradient(m - r * 0.2, m - r * 0.2, 0, m, m, r);
        k.addColorStop(0, 'rgba(255,255,255,1)');
        k.addColorStop(weich ? 0.2 : 0.6, `rgba(255,255,255,${weich ? 0.7 : 0.97})`);
        k.addColorStop(1, 'rgba(240,246,255,0)');
        g.fillStyle = k;
        g.fillRect(0, 0, s, s);
        return c;
    }

    function sprite(name, bauen) {
        if (!sprites[name]) sprites[name] = bauen();
        return sprites[name];
    }

    // ------------------------------------------------------------------
    // Glitzer (vorne) – Spur des Schlittens, Funkeln beim Eierverstecken

    function funkenStreuen(x, y, anzahl, art) {
        for (let i = 0; i < anzahl; i++) {
            const max = zufall(0.7, 1.6);
            funken.push({
                x: x + zufall(-0.4, 0.4) * VW, y: y + zufall(-0.3, 0.3) * VW,
                vx: zufall(-1.2, 0.4) * VW, vy: zufall(-0.4, 1.4) * VW,
                leben: max, max: max, groesse: zufall(0.25, 0.7) * VW,
                art: art || (Math.random() < 0.65 ? 'gold' : 'weiss'), drehung: zufall(0, 6.28),
            });
        }
        if (funken.length > 500) funken.splice(0, funken.length - 500);
    }

    function funkenZeichnen(dt) {
        if (funken.length === 0) return;
        const gold = sprite('stern-gold', () => stern(1.2 * VW * DPR, 'rgba(255,205,90,1)'));
        const weiss = sprite('stern-weiss', () => stern(1.2 * VW * DPR, 'rgba(210,230,255,1)'));
        const bunt = sprite('stern-bunt', () => stern(1.2 * VW * DPR, 'rgba(255,150,200,1)'));
        const rest = [];
        for (const f of funken) {
            f.leben -= dt;
            if (f.leben <= 0) continue;
            f.x += f.vx * dt; f.y += f.vy * dt; f.vy += 0.6 * VW * dt;
            const a = Math.min(1, f.leben / f.max * 1.6) * (0.65 + 0.35 * Math.sin(f.leben * 22 + f.drehung));
            const s = f.groesse * (0.6 + 0.4 * f.leben / f.max);
            cxV.globalAlpha = Math.max(0, a);
            const img = f.art === 'gold' ? gold : (f.art === 'bunt' ? bunt : weiss);
            cxV.drawImage(img, f.x - s, f.y - s, 2 * s, 2 * s);
            rest.push(f);
        }
        cxV.globalAlpha = 1;
        funken = rest;
    }

    // ==================================================================
    // SCHNEE

    // Kind auf dem Holzschlitten, fährt nach rechts; Kufen unten bei y = 38 von 42
    function rodelSvg() {
        const jacke = auswahl(['#d8343c', '#2f6fb3', '#2f9e6a', '#8e44ad']);
        const muetze = auswahl(['#f2c14e', '#e85a7a', '#3a86d4', '#ff8a3d']);
        return `<svg class="fx-rodel" viewBox="0 0 60 42" xmlns="${NS}">
            <path d="M4,38 L46,38 C55,38 57,31 52,27" stroke="#7a4a20" stroke-width="2.4" fill="none" stroke-linecap="round"/>
            <path d="M14,32 L14,38 M38,32 L38,38" stroke="#7a4a20" stroke-width="2"/>
            <rect x="7" y="29" width="40" height="4" rx="1.2" fill="#c08040" stroke="#7a4a20" stroke-width="1"/>
            <path class="fx-schal" d="M25,13.5 C18,12 12,14 6,10.5 L7,15 C12,17.5 19,16.5 25,16 Z" fill="#f6d04d" stroke="#b8941c" stroke-width=".6"/>
            <path d="M20,29 C17,20 21,12 28,12 C34,12 36,19 34,29 Z" fill="${jacke}"/>
            <path d="M30,26 L44,27" stroke="#2e3f5c" stroke-width="5.5" stroke-linecap="round"/>
            <rect x="43" y="23.5" width="5" height="6" rx="1.5" fill="#2b2b2b"/>
            <path d="M31,17 L41,22" stroke="${jacke}" stroke-width="3.6" stroke-linecap="round"/>
            <circle cx="42" cy="22.5" r="1.8" fill="#f6d7bf"/>
            <path d="M43,22.5 C47,24 50,25.5 52,27" stroke="#555" stroke-width=".8" fill="none"/>
            <circle cx="29" cy="8" r="5.2" fill="#f6d7bf"/>
            <path d="M23.6,7.6 C23.6,1 34.4,1 34.4,7.6 Z" fill="${muetze}"/>
            <rect x="23" y="6.5" width="12" height="2.4" rx="1" fill="#fff" opacity=".85"/>
            <circle cx="27.5" cy="0.6" r="2.2" fill="#fff"/>
            <circle cx="31.6" cy="9.4" r=".8" fill="#2a1a14"/>
            <path d="M30.6,11.6 q1.6,1.1 3.1,-.3" stroke="#2a1a14" stroke-width=".7" fill="none" stroke-linecap="round"/>
            <circle cx="32.6" cy="11" r="1.3" fill="#f19a9a" opacity=".55"/>
        </svg>`;
    }

    function Schnee(staerke) {
        const anzahl = [0, 180, 270, 380][staerke] || 270;
        const flocken = [];
        const nah = [];
        let wind = 0;
        function neu(f, oben) {
            f.z = Math.random();                       // 0 = weit weg, 1 = nah
            f.r = (0.13 + f.z * 0.36) * zufall(0.8, 1.25); // in vw
            f.x = zufall(-5, 105) * VW;
            f.y = oben ? zufall(-8, -1) * VW : zufall(0, H);
            f.vy = (2.2 + f.z * 4.5) * zufall(0.85, 1.15); // vw/s
            f.amp = zufall(0.3, 1.4);
            f.freq = zufall(0.5, 1.4);
            f.phase = zufall(0, 6.28);
            return f;
        }
        for (let i = 0; i < anzahl; i++) flocken.push(neu({}, false));
        for (let i = 0; i < [0, 8, 12, 18][staerke]; i++) {
            nah.push({x: zufall(0, 100) * VW, y: zufall(0, H), r: zufall(0.7, 1.4), vy: zufall(9, 14), phase: zufall(0, 6.28)});
        }
        const hauben = setInterval(() => dekorieren('schnee', schneehaube), 2000);
        dekorieren('schnee', schneehaube);
        // Schneeberg: wächst von 7:30 Uhr unten bis 14:00 Uhr auf drei Viertel
        let t0 = null, berg = 0, bergGesetzt = false;
        const huegel = [0, 1, 2].map(() => ({f: zufall(0.7, 1.6), p: zufall(0, 6.28), a: zufall(0.5, 1.1)}));
        // alle 60–90 Sekunden rodelt ein Kind über den Schneeberg
        let rodel = null, rodelNaechster = vorschau ? 2 : zufall(20, 60);
        const staub = [];
        // gelandete Flocken bleiben kurz auf der Bergkante liegen und verschmelzen dann mit ihr
        const gelandet = [];
        function landen(x, y, r, z) {
            if (gelandet.length > 260) gelandet.shift();
            gelandet.push({x: x, y: y, r: r, z: z, alter: 0, leben: zufall(1.2, 2.6)});
        }
        const glitzer = [];
        for (let i = 0; i < 30; i++) glitzer.push({x: zufall(0, 100), p: zufall(0, 6.28), v: zufall(1, 3), tief: zufall(0.3, 3)});
        function bergHoehe(x) {
            let y = UNTEN * (1 - berg);
            for (const h of huegel) y += Math.sin(x / (12 * VW) * h.f + h.p) * h.a * VW * Math.min(1, berg * 6);
            return y;
        }
        function rodelSchritt(dt, t) {
            const r = rodel;
            const bw = 6.5 * VW, bh = bw * 42 / 60;
            const steigung = (bergHoehe(r.x + VW) - bergHoehe(r.x - VW)) / (2 * VW);   // > 0: bergab nach rechts
            // bergab schneller, bergauf langsamer, aber immer in Fahrt
            r.v = Math.max(6 * VW, Math.min(17 * VW, r.v + r.richtung * steigung * 60 * VW * dt - (r.v - 9 * VW) * 0.4 * dt));
            r.x += r.richtung * r.v * dt;
            const y = bergHoehe(r.x) - bh * 38 / 42 + 0.15 * VW;
            const w = Math.atan(steigung) * 180 / Math.PI;
            const links = r.x - bw / 2;
            r.el.style.transform = `translate(${links.toFixed(1)}px, ${y.toFixed(1)}px) rotate(${w.toFixed(1)}deg)${r.richtung < 0 ? ' scale(-1, 1)' : ''}`;
            // Schneestaub hinter den Kufen
            if (Math.random() < dt * 30) {
                staub.push({x: r.x - r.richtung * bw * 0.4, y: bergHoehe(r.x) - 0.2 * VW, vx: -r.richtung * zufall(2, 6) * VW, vy: -zufall(2, 5) * VW, r: zufall(0.12, 0.3) * VW, alter: 0});
            }
            if ((r.richtung > 0 && links > W + VW) || (r.richtung < 0 && links < -bw - VW)) { r.el.remove(); rodel = null; }
        }
        return {
            stop() { clearInterval(hauben); dekoEntfernen(); uhrWeg(); if (rodel) { rodel.el.remove(); rodel = null; } },
            schritt(dt, t) {
                if (t0 === null) t0 = t;
                const zielBerg = Math.max(0.03, tagAnteil(t0, t) * FLUT_MAX);
                if (!bergGesetzt) {
                    bergGesetzt = true; berg = zielBerg;
                    // zu Beginn: Flocken nur im Himmel über dem Berg verteilen
                    for (const f of flocken.concat(nah)) {
                        if (f.y > bergHoehe(f.x) - VW) f.y = zufall(-5, bergHoehe(f.x) / VW - 1) * VW;
                    }
                }
                berg += (zielBerg - berg) * Math.min(1, dt * (vorschau ? 4 : 0.25));
                zeitrafferUhr(tagAnteil(t0, t));
                // der Berg selbst (hinter den Kacheln)
                const oben = UNTEN * (1 - berg) - 1.5 * VW;
                const g = cxH.createLinearGradient(0, oben, 0, H);
                g.addColorStop(0, '#ffffff');
                g.addColorStop(0.35, '#f3f7fc');
                g.addColorStop(1, '#d8e3f0');
                cxH.fillStyle = g;
                cxH.beginPath();
                cxH.moveTo(0, H);
                for (let x = 0; x <= W + 2 * VW; x += 2 * VW) cxH.lineTo(x, bergHoehe(x));
                cxH.lineTo(W, H);
                cxH.closePath();
                cxH.fill();
                // weicher bläulicher Schatten unter der Oberkante, damit der Berg plastisch wirkt
                cxH.strokeStyle = 'rgba(120,150,190,.35)';
                cxH.lineWidth = 0.5 * VW;
                cxH.beginPath();
                for (let x = 0; x <= W + 2 * VW; x += 2 * VW) {
                    const y = bergHoehe(x) + 0.9 * VW;
                    if (x === 0) cxH.moveTo(x, y); else cxH.lineTo(x, y);
                }
                cxH.stroke();
                cxH.strokeStyle = 'rgba(255,255,255,.95)';
                cxH.lineWidth = 0.18 * VW;
                cxH.beginPath();
                for (let x = 0; x <= W + 2 * VW; x += 2 * VW) {
                    const y = bergHoehe(x);
                    if (x === 0) cxH.moveTo(x, y); else cxH.lineTo(x, y);
                }
                cxH.stroke();
                // Glitzern im Schnee
                const sternBild = sprite('stern-weiss', () => stern(1.2 * VW * DPR, 'rgba(210,230,255,1)'));
                for (const gl of glitzer) {
                    const a = Math.max(0, Math.sin(t * gl.v + gl.p));
                    if (a < 0.6) continue;
                    const x = gl.x * VW, y = bergHoehe(x) + gl.tief * VW;
                    cxH.globalAlpha = (a - 0.6) * 2.5;
                    cxH.drawImage(sternBild, x - 0.4 * VW, y - 0.4 * VW, 0.8 * VW, 0.8 * VW);
                }
                cxH.globalAlpha = 1;
                const dunkel = opt.dunkel;
                const img = sprite('flocke', () => flockeSprite(0.5 * VW * DPR, dunkel, false));
                const bokeh = sprite('bokeh', () => flockeSprite(1.2 * VW * DPR, dunkel, true));
                wind = Math.sin(t * 0.13) * 1.2 + Math.sin(t * 0.41) * 0.6;
                for (const f of flocken) {
                    f.y += f.vy * VW * dt;
                    f.x += (wind * (0.5 + f.z) + Math.sin(t * f.freq + f.phase) * f.amp) * VW * dt;
                    if (f.y > H + VW || f.x < -6 * VW || f.x > W + 6 * VW) { neu(f, true); continue; }
                    // landet auf dem Schneeberg: bleibt oben liegen, fällt nie hindurch
                    const kante = bergHoehe(f.x);
                    if (f.y > kante) { landen(f.x, kante - f.r * VW * 0.4, f.r, f.z); neu(f, true); continue; }
                    // landet auf einem Kasten und wird Teil der Schneehaube
                    if (f.z > 0.35) {
                        for (const k of kaesten) {
                            if (f.x > k.x && f.x < k.x + k.w && f.y > k.y && f.y < k.y + f.vy * VW * dt + 2) {
                                if (Math.random() < 0.6) neu(f, true);
                                break;
                            }
                        }
                    }
                    const s = f.r * VW * 1.5;
                    cxH.globalAlpha = 0.5 + f.z * 0.5;
                    cxH.drawImage(img, f.x - s, f.y - s, 2 * s, 2 * s);
                }
                // liegende Flocken auf der Kante (wandern mit, wenn der Berg wächst)
                for (let i = gelandet.length - 1; i >= 0; i--) {
                    const g = gelandet[i];
                    g.alter += dt;
                    if (g.alter > g.leben) { gelandet.splice(i, 1); continue; }
                    const y = Math.min(g.y, bergHoehe(g.x) - g.r * VW * 0.4);
                    const s = g.r * VW * 1.5;
                    cxH.globalAlpha = (0.5 + g.z * 0.5) * (1 - g.alter / g.leben);
                    cxH.drawImage(img, g.x - s, y - s, 2 * s, 2 * s);
                }
                cxH.globalAlpha = 1;
                // wenige große, unscharfe Flocken ganz vorne – auch sie enden auf dem Berg
                for (const f of nah) {
                    f.y += f.vy * VW * dt;
                    f.x += (wind * 2.2 + Math.sin(t * 0.7 + f.phase) * 1.5) * VW * dt;
                    if (f.x > W + 3 * VW) f.x = -3 * VW;
                    if (f.x < -3 * VW) f.x = W + 3 * VW;
                    if (f.y > bergHoehe(f.x) - f.r * VW * 0.5) { f.y = zufall(-6, -3) * VW; f.x = zufall(0, 100) * VW; continue; }
                    const s = f.r * VW * 1.5;
                    cxV.globalAlpha = 0.75;
                    cxV.drawImage(bokeh, f.x - s, f.y - s, 2 * s, 2 * s);
                }
                cxV.globalAlpha = 1;
                // Rodelschlitten, sobald der Berg hoch genug ist
                rodelNaechster -= dt;
                if (!rodel && rodelNaechster <= 0 && berg > 0.08) {
                    const el = svgAusText(rodelSvg());
                    domV.appendChild(el);
                    const richtung = Math.random() < 0.5 ? 1 : -1;
                    rodel = {el: el, richtung: richtung, x: richtung > 0 ? -4 * VW : W + 4 * VW, v: 9 * VW};
                    rodelNaechster = dauer(zufall(60, 90), 12);
                }
                if (rodel) rodelSchritt(dt, t);
                cxV.fillStyle = '#ffffff';
                for (let i = staub.length - 1; i >= 0; i--) {
                    const p = staub[i];
                    p.alter += dt;
                    if (p.alter > 0.9) { staub.splice(i, 1); continue; }
                    p.vy += 9 * VW * dt; p.x += p.vx * dt; p.y += p.vy * dt;
                    cxV.globalAlpha = 0.9 * (1 - p.alter / 0.9);
                    cxV.beginPath(); cxV.arc(p.x, p.y, p.r, 0, 6.283); cxV.fill();
                }
                cxV.globalAlpha = 1;
            },
        };
    }

    // Schneehaube: weicher, unregelmäßiger Wulst auf der Oberkante, wächst langsam
    function schneehaube(el, wVw) {
        const h = 1.45;
        const id = neueId('schnee');
        let d = `M -0.25 ${h} `;
        const schritte = Math.max(3, Math.round(wVw / 2.2));
        let x = -0.25;
        d += `C -0.45 ${h * 0.75} -0.1 ${h * 0.45} 0.5 ${h * 0.42} `;
        x = 0.5;
        for (let i = 1; i <= schritte; i++) {
            const nx = 0.5 + (wVw - 1.0) * i / schritte;
            const y = h * zufall(0.05, 0.38);
            const cx = (x + nx) / 2;
            d += `S ${cx.toFixed(2)} ${y.toFixed(2)} ${nx.toFixed(2)} ${(h * zufall(0.2, 0.42)).toFixed(2)} `;
            x = nx;
        }
        d += `C ${wVw + 0.15} ${h * 0.45} ${wVw + 0.45} ${h * 0.75} ${wVw + 0.25} ${h} Z`;
        const s = svg('svg', {viewBox: `-0.5 0 ${wVw + 1} ${h}`, preserveAspectRatio: 'none', class: 'fx-deko'}, [
            svg('defs', {}, [svg('linearGradient', {id: id, x1: 0, y1: 0, x2: 0, y2: 1}, [
                svg('stop', {offset: 0, 'stop-color': '#ffffff'}),
                svg('stop', {offset: 0.7, 'stop-color': '#f4f8fd'}),
                svg('stop', {offset: 1, 'stop-color': '#dfe9f5'}),
            ])]),
            svg('path', {d: d, fill: `url(#${id})`}),
        ]);
        Object.assign(s.style, {left: '-0.5vw', top: `-${h - 0.3}vw`, width: `${wVw + 1}vw`, height: `${h}vw`,
            filter: 'drop-shadow(0 -.02vw .06vw rgba(60,90,130,.45)) drop-shadow(0 .1vw .15vw rgba(60,90,130,.3))'});
        el.insertBefore(s, el.firstChild);
        wachsenLassen(s, dauer(zufall(900, 1500), zufall(5, 9)));
        // kleine Haube auf dem Kiesel (Klassenname)
        const kiesel = opt.kiesel ? el.querySelector(`:scope > ${opt.kiesel}`) : null;
        if (kiesel && getComputedStyle(kiesel).position !== 'static') {
            const kw = kiesel.getBoundingClientRect().width / VW;
            const k = svg('svg', {viewBox: `0 0 ${kw} 0.8`, preserveAspectRatio: 'none', class: 'fx-deko'}, [
                svg('path', {d: `M 0.15 0.8 C 0.1 0.3 ${kw * 0.3} 0.05 ${kw * 0.5} 0.12 C ${kw * 0.75} 0 ${kw - 0.1} 0.3 ${kw - 0.15} 0.8 Z`, fill: '#fff'}),
            ]);
            Object.assign(k.style, {left: '0', top: '-0.42vw', width: `${kw}vw`, height: '0.8vw',
                filter: 'drop-shadow(0 .06vw .08vw rgba(60,90,130,.35))'});
            kiesel.appendChild(k);
            wachsenLassen(k, dauer(zufall(900, 1500), zufall(5, 9)));
        }
    }

    // ==================================================================
    // REGEN (und Grundlage für das Gewitter)
    //
    // Bei Regen (nicht beim Gewitter) läuft das Board im Lauf des Schultags voll:
    // um 7:30 Uhr eine Pfütze, um 14:00 Uhr steht das Wasser bei drei Vierteln –
    // höher nicht, damit man oben den Regen noch fallen sieht. Das Wasser liegt
    // hinter den Kacheln; vorne nur eine feine Wasserlinie und ein Hauch Blau.

    const FLUT_VON = 7 * 60 + 30, FLUT_BIS = 14 * 60, FLUT_MAX = 0.75;
    // Regen, Schnee und Hitze entwickeln sich über den Schultag: 0 um 7:30 Uhr,
    // 1 um 14:00 Uhr. In der Vorschau läuft der Tag einmal im Zeitraffer durch.
    const ZEITRAFFER_S = 22;
    function tagAnteil(t0, t) {
        if (vorschau) return Math.max(0, Math.min(1, (t - t0) / ZEITRAFFER_S));
        const d = new Date();
        const min = d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60;
        return Math.max(0, Math.min(1, (min - FLUT_VON) / (FLUT_BIS - FLUT_VON)));
    }
    let uhrEl = null;
    function zeitrafferUhr(anteil) {
        if (!vorschau) { uhrWeg(); return; }
        if (!uhrEl) { uhrEl = document.createElement('div'); uhrEl.className = 'fx-zeitraffer'; domV.appendChild(uhrEl); }
        const min = Math.round(FLUT_VON + (FLUT_BIS - FLUT_VON) * anteil);
        const zeit = `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')} Uhr`;
        uhrEl.textContent = anteil < 1 ? `Zeitraffer · ${zeit}` : `${zeit} · so bleibt es bis Schulschluss`;
    }
    function uhrWeg() { if (uhrEl) { uhrEl.remove(); uhrEl = null; } }

    // Gelbes Forschungs-U-Boot mit Glaskuppel (eine Forscherin schaut heraus),
    // Bullaugen, Greifarm, Scheinwerfer, Kufen. Fährt nach rechts; Lampe bei (107|22).
    const UBOOT_B = 12, UBOOT_LAMPE = [107, 22];
    function ubootSvg() {
        const k = '#6b5310';
        return `<svg class="fx-uboot" viewBox="0 0 120 52" xmlns="${NS}">
            <defs>
                <linearGradient id="fx-ub-gelb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe066"/><stop offset=".55" stop-color="#f5c22b"/><stop offset="1" stop-color="#d79a12"/></linearGradient>
                <radialGradient id="fx-ub-glas" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#e8f8ff"/><stop offset=".6" stop-color="#8fd0f0"/><stop offset="1" stop-color="#3a86b8"/></radialGradient>
            </defs>
            <path d="M28,40 L23,47 M86,40 L91,47 M17,47 L98,47" stroke="#4d5560" stroke-width="2.4" stroke-linecap="round" fill="none"/>
            <g>
                <rect x="1" y="16" width="9" height="19" rx="3" fill="none" stroke="#4d5560" stroke-width="2"/>
                <ellipse class="fx-propeller" cx="5.5" cy="25.5" rx="2" ry="8" fill="#7d8790"/>
                <circle cx="6" cy="25.5" r="2" fill="#4d5560"/>
            </g>
            <rect x="10" y="9" width="88" height="32" rx="16" fill="url(#fx-ub-gelb)" stroke="${k}" stroke-width="1.6"/>
            <path d="M16,34 L92,34" stroke="#ff7a1a" stroke-width="2.4" stroke-linecap="round"/>
            <rect x="44" y="1.5" width="26" height="12" rx="5" fill="url(#fx-ub-gelb)" stroke="${k}" stroke-width="1.4"/>
            <path d="M57,1.5 L57,-4 M54,-4 L60,-4" stroke="#4d5560" stroke-width="1.6" stroke-linecap="round"/>
            ${[30, 47, 64].map((x) => `<circle cx="${x}" cy="23" r="5" fill="url(#fx-ub-glas)" stroke="#5a6470" stroke-width="1.8"/><circle cx="${x - 1.5}" cy="21.5" r="1.4" fill="#fff" opacity=".8"/>`).join('')}
            <circle cx="91" cy="24" r="12.5" fill="url(#fx-ub-glas)" stroke="#5a6470" stroke-width="2.2"/>
            <circle cx="89" cy="26" r="4.2" fill="#f2c9a0"/>
            <path d="M84.6,25 C84.6,19.5 93.4,19.5 93.4,25 Z" fill="#7a3b14"/>
            <circle cx="90.6" cy="26" r=".8" fill="#2a1a14"/>
            <path d="M85,31 C86,29.5 92,29.5 93,31 L93,34 L85,34 Z" fill="#2f6fb3"/>
            <path d="M84,15.5 C87,13.5 92,13.8 95,16" stroke="#fff" stroke-width="1.4" fill="none" opacity=".8" stroke-linecap="round"/>
            <path d="M84,39 L93,45 L100,43 M100,43 L104,40 M100,43 L104,46" stroke="#4d5560" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
            <rect x="101" y="18.5" width="5" height="7" rx="1.5" fill="#4d5560"/>
            <circle class="fx-uboot-lampe" cx="${UBOOT_LAMPE[0]}" cy="${UBOOT_LAMPE[1]}" r="2.6" fill="#fff6b0"/>
        </svg>`;
    }

    // Entenfamilie auf dem Wasser: Mutter (Stockente) und Küken, Blick nach rechts
    function enteSvg(kueken) {
        if (kueken) {
            return `<svg class="fx-ente" viewBox="0 0 22 16" xmlns="${NS}" style="width: 2vw">
                <ellipse cx="10" cy="10.5" rx="7.5" ry="4.8" fill="#ffd84a" stroke="#c89a10" stroke-width=".8"/>
                <path d="M3,9 L1,6.5 L4.5,8 Z" fill="#ffd84a" stroke="#c89a10" stroke-width=".6"/>
                <path d="M6,9.5 C9,7.5 12,8.5 13,10.5 C10,12.5 7,11.5 6,9.5 Z" fill="#f2c534"/>
                <circle cx="15.5" cy="5.8" r="3.9" fill="#ffd84a" stroke="#c89a10" stroke-width=".8"/>
                <circle cx="16.9" cy="5.1" r=".75" fill="#2a1a14"/>
                <path d="M19.1,5.8 L22,6.6 L19.1,7.6 Z" fill="#f08a24"/>
            </svg>`;
        }
        return `<svg class="fx-ente" viewBox="0 0 46 30" xmlns="${NS}" style="width: 4.4vw">
            <path d="M6,18 L1,12.5 L9,15.5 Z" fill="#8a5c33" stroke="#5a3a1e" stroke-width=".9"/>
            <ellipse cx="20" cy="20" rx="15" ry="8" fill="#9b6a3c" stroke="#5a3a1e" stroke-width="1"/>
            <path d="M11,16.5 C17,12 26,13 30,18 C24,22.5 15,22 11,16.5 Z" fill="#7a5230"/>
            <path d="M19,19.2 L27,18.4" stroke="#3a6fd8" stroke-width="1.6" stroke-linecap="round"/>
            <path d="M27,17 C27,13 28,11 30,10 L35,12 C33,13 32,15 32,18 Z" fill="#9b6a3c"/>
            <circle cx="33" cy="8.5" r="6" fill="#9b6a3c" stroke="#5a3a1e" stroke-width="1"/>
            <path d="M28,7.8 C30,6.6 34,6.5 38,7.6" stroke="#6b4626" stroke-width="1.1" fill="none"/>
            <circle cx="35" cy="7.5" r="1.05" fill="#1d120c"/>
            <path d="M38,8.4 L45,9.6 L38,11.6 Z" fill="#f08a24" stroke="#b35d10" stroke-width=".5"/>
        </svg>`;
    }

    function Regen(staerke, gewitter) {
        const anzahl = [0, 260, 380, 520][staerke] || 380;
        const tropfen = [];
        const spritzer = [];
        const scheibe = [];
        const ringe = [];
        const blasen = [];
        const wasserSpritzer = [];   // Tröpfchen und kleine Wassersäulen beim Aufprall, vorne
        const winkel = 0.2;
        const flut = !gewitter;
        // ab Rot fährt etwa alle 2 Minuten ein Forschungs-U-Boot unten durchs Wasser
        let uboot = null, enten = null;
        // U-Boot (ab Rot) und Entenfamilie teilen sich einen Zeitslot: nie beide zugleich,
        // alle 60–90 Sekunden einer von beiden; ab Rot abwechselnd (Wunsch Jonas)
        let slotNaechster = vorschau ? 2 : zufall(30, 60), zuletzt = 'enten';
        let wasser = 0;     // 0 trocken … 1 Board voll
        let wasserGesetzt = false;
        let t0 = null;
        function neu(d, oben) {
            d.z = Math.random();
            d.x = zufall(-10, 105) * VW;
            d.y = oben ? zufall(-20, -2) * VW : zufall(-10, 100) * H / 100;
            d.len = (1.7 + d.z * 3.2) * VW;   // etwas größere Tropfen (Wunsch Jonas)
            d.v = (55 + d.z * 45) * VW;
            return d;
        }
        for (let i = 0; i < anzahl; i++) tropfen.push(neu({}, false));
        function scheibenTropfen(d) {
            d.x = zufall(2, 98) * VW; d.y = zufall(2, 90) * H / 100;
            d.r = zufall(0.18, 0.5) * VW; d.v = 0; d.warten = zufall(2, 12); d.a = 0;
            return d;
        }
        for (let i = 0; i < [0, 7, 11, 15][staerke]; i++) scheibe.push(scheibenTropfen({}));
        const farbe = (a) => opt.dunkel ? `rgba(205,222,250,${a})` : `rgba(28,52,96,${a})`;

        // Wasserstand nach der Uhr (in der Vorschau im Zeitraffer)
        function wasserZiel(t) {
            if (!flut) return 0;
            return Math.max(0.04, tagAnteil(t0, t) * FLUT_MAX);
        }
        // Höhe der Wasseroberfläche an der Stelle x (mit leichten Wellen)
        function oberflaeche(x, t) {
            const ruhe = 1 - glatt(0.9, 1, wasser);
            return UNTEN * (1 - wasser) + (Math.sin(x / (9 * VW) + t * 1.3) * 0.22 + Math.sin(x / (3.7 * VW) - t * 2.1) * 0.1) * VW * ruhe;
        }
        function glatt(a, b, x) { const u = Math.max(0, Math.min(1, (x - a) / (b - a))); return u * u * (3 - 2 * u); }
        function ring(x, y, flach, max) {
            if (ringe.length < 500) ringe.push({x: x, y: y, r: 0.1 * VW, max: max, leben: 0, dauer: zufall(0.7, 1.2), flach: flach});
        }

        function ubootSchritt(dt, t) {
            const u = uboot;
            const bw = UBOOT_B * VW, bh = bw * 52 / 120;
            u.x += u.richtung * 5.5 * VW * dt;
            // im freien Streifen unter den Kacheln, sanft auf und ab
            const y = UNTEN - bh - 0.6 * VW + Math.sin(t * 0.9 + u.p) * 0.35 * VW;
            const neig = Math.sin(t * 0.9 + u.p + 1.2) * 1.5;
            u.el.style.transform = `translate(${u.x.toFixed(1)}px, ${y.toFixed(1)}px) rotate(${(neig * u.richtung).toFixed(2)}deg)${u.richtung < 0 ? ' scale(-1, 1)' : ''}`;
            // Scheinwerferkegel nach vorn (zart, vorne)
            const lx = u.x + (u.richtung > 0 ? UBOOT_LAMPE[0] / 120 : 1 - UBOOT_LAMPE[0] / 120) * bw;
            const ly = y + UBOOT_LAMPE[1] / 52 * bh;
            const weite = 14 * VW;
            const kegel = cxV.createLinearGradient(lx, ly, lx + u.richtung * weite, ly);
            kegel.addColorStop(0, 'rgba(255,248,190,.38)');
            kegel.addColorStop(1, 'rgba(255,248,190,0)');
            cxV.fillStyle = kegel;
            cxV.beginPath();
            cxV.moveTo(lx, ly - 0.3 * VW);
            cxV.lineTo(lx + u.richtung * weite, ly - 2.6 * VW);
            cxV.lineTo(lx + u.richtung * weite, ly + 2.6 * VW);
            cxV.lineTo(lx, ly + 0.3 * VW);
            cxV.closePath();
            cxV.fill();
            // Blasen hinter dem Propeller
            if (Math.random() < dt * 9) {
                const px = u.x + (u.richtung > 0 ? 0.02 : 0.98) * bw;
                u.blasen.push({x: px, y: y + bh * 0.48, r: zufall(0.1, 0.25) * VW, v: zufall(2, 4) * VW, alter: 0});
            }
            cxV.strokeStyle = 'rgba(255,255,255,.6)';
            cxV.lineWidth = 0.05 * VW;
            for (let i = u.blasen.length - 1; i >= 0; i--) {
                const bl = u.blasen[i];
                bl.alter += dt; bl.y -= bl.v * dt; bl.x -= u.richtung * 0.8 * VW * dt;
                if (bl.alter > 1.6 || bl.y < oberflaeche(bl.x, t)) { u.blasen.splice(i, 1); continue; }
                cxV.beginPath(); cxV.arc(bl.x + Math.sin(bl.alter * 6) * 0.15 * VW, bl.y, bl.r, 0, 6.283); cxV.stroke();
            }
            if ((u.richtung > 0 && u.x > W + VW) || (u.richtung < 0 && u.x < -bw - VW)) { u.el.remove(); uboot = null; }
        }
        function entenSchritt(dt, t) {
            const e = enten;
            e.x += e.richtung * 3.2 * VW * dt;
            let alleWeg = true;
            e.tiere.forEach((tier, i) => {
                // Küken folgen der Mutter in einer Reihe, ein wenig unregelmäßig
                const x = e.x - e.richtung * (i === 0 ? 0 : 3.4 * VW + (i - 1) * 2.4 * VW + Math.sin(t * 1.7 + i) * 0.25 * VW);
                const yW = oberflaeche(x, t);
                const neig = Math.atan2(oberflaeche(x + VW, t) - oberflaeche(x - VW, t), 2 * VW) * 180 / Math.PI;
                const wackeln = Math.sin(t * 4 + i * 1.3) * 3;
                const y = yW - tier.h * tier.tauch + Math.sin(t * 2.6 + i) * 0.08 * VW;
                tier.el.style.transform = `translate(${(x - tier.w / 2).toFixed(1)}px, ${y.toFixed(1)}px) rotate(${(neig + wackeln * e.richtung).toFixed(1)}deg)${e.richtung < 0 ? ' scale(-1, 1)' : ''}`;
                // kleine Bugwelle
                if (Math.random() < dt * 2.2) ring(x - e.richtung * tier.w * 0.3, yW + 0.1 * VW, true, tier.w * 0.5);
                if (x > -tier.w - VW && x < W + tier.w + VW) alleWeg = false;
            });
            if (alleWeg && Math.abs(e.x - e.start) > 2 * VW) { for (const tier of e.tiere) tier.el.remove(); enten = null; }
        }
        return {
            stop() {
                uhrWeg();
                if (uboot) { uboot.el.remove(); uboot = null; }
                if (enten) { for (const tier of enten.tiere) tier.el.remove(); enten = null; }
            },
            schritt(dt, t) {
                if (t0 === null) t0 = t;
                const ziel = wasserZiel(t);
                if (!wasserGesetzt) { wasserGesetzt = true; wasser = ziel; }
                wasser += (ziel - wasser) * Math.min(1, dt * (vorschau ? 4 : 0.25));
                if (flut) zeitrafferUhr(tagAnteil(t0, t));
                const see = flut ? glatt(0.93, 1, wasser) : 0;   // 1 = Blick von oben auf den See
                // trübere Stimmung
                cxH.fillStyle = gewitter ? (opt.dunkel ? 'rgba(10,15,30,.35)' : 'rgba(35,45,70,.16)') : (opt.dunkel ? 'rgba(10,15,30,.15)' : 'rgba(40,55,80,.07)');
                cxH.fillRect(0, 0, W, H);

                // ---- Wasserkörper (hinter den Kacheln)
                if (flut && wasser > 0.005) {
                    const top = UNTEN * (1 - wasser);
                    const g = cxH.createLinearGradient(0, Math.max(0, top - VW), 0, H);
                    // kräftiger und dunkler, damit man das Wasser auch auf blauem Hintergrund erkennt
                    g.addColorStop(0, opt.dunkel ? 'rgba(60,125,205,.55)' : 'rgba(25,100,180,.55)');
                    g.addColorStop(1, opt.dunkel ? 'rgba(5,35,90,.78)' : 'rgba(8,40,105,.75)');
                    cxH.fillStyle = g;
                    cxH.beginPath();
                    cxH.moveTo(0, H);
                    for (let x = 0; x <= W + 2 * VW; x += 2 * VW) cxH.lineTo(x, oberflaeche(x, t));
                    cxH.lineTo(W, H);
                    cxH.closePath();
                    cxH.fill();
                    // Lichtspiel unter Wasser
                    cxH.strokeStyle = 'rgba(255,255,255,.07)';
                    cxH.lineWidth = 0.25 * VW;
                    for (let i = 0; i < 6; i++) {
                        const yy = top + (H - top) * (i + 0.5) / 6;
                        if (yy < top + VW) continue;
                        cxH.beginPath();
                        for (let x = 0; x <= W; x += 3 * VW) {
                            const y = yy + Math.sin(x / (6 * VW) + t * (0.6 + i * 0.13) + i) * 0.6 * VW;
                            if (x === 0) cxH.moveTo(x, y); else cxH.lineTo(x, y);
                        }
                        cxH.stroke();
                    }
                    // aufsteigende Luftblasen
                    if (wasser > 0.08 && Math.random() < dt * 3 && blasen.length < 60) {
                        blasen.push({x: zufall(0, 100) * VW, y: H + VW, r: zufall(0.12, 0.32) * VW, v: zufall(3, 7) * VW, p: zufall(0, 6.28)});
                    }
                    cxH.strokeStyle = 'rgba(255,255,255,.45)';
                    cxH.lineWidth = 0.05 * VW;
                    for (let i = blasen.length - 1; i >= 0; i--) {
                        const bl = blasen[i];
                        bl.y -= bl.v * dt;
                        const x = bl.x + Math.sin(t * 2 + bl.p) * 0.3 * VW;
                        if (bl.y < oberflaeche(x, t) + bl.r) { ring(x, oberflaeche(x, t), true, 0.8 * VW); blasen.splice(i, 1); continue; }
                        cxH.beginPath(); cxH.arc(x, bl.y, bl.r, 0, 6.283); cxH.stroke();
                    }
                }

                // ---- Regentropfen
                const dx = Math.sin(winkel), dy = Math.cos(winkel);
                const schichten = [[], [], []];
                for (const d of tropfen) {
                    d.x += d.v * dx * dt; d.y += d.v * dy * dt;
                    let weg = d.y > UNTEN;
                    if (flut && !weg && wasser > 0.005 && d.y >= oberflaeche(d.x, t)) {
                        // trifft die Wasseroberfläche: Ring und ein paar hochspritzende Tröpfchen
                        weg = true;
                        const oy = oberflaeche(d.x, t);
                        if (see < 0.5) {
                            ring(d.x, oy, true, zufall(0.8, 2.0) * VW);
                            // manchmal ein zweiter, späterer Ring
                            if (Math.random() < 0.35 && ringe.length < 500) ringe.push({x: d.x, y: oy, r: 0.1 * VW, max: zufall(1.4, 2.6) * VW, leben: -0.18, dauer: zufall(0.8, 1.3), flach: true});
                        }
                        if (d.z > 0.2 && wasserSpritzer.length < 700) {
                            const n = 4 + Math.floor(Math.random() * 3);
                            for (let i = 0; i < n; i++) wasserSpritzer.push({x: d.x, y: oy - 1, vx: zufall(-7, 7) * VW, vy: zufall(-14, -6) * VW, r: zufall(0.08, 0.13) * VW, leben: zufall(0.25, 0.45)});
                            // kleine Wassersäule, die senkrecht hochschießt
                            if (Math.random() < 0.35) wasserSpritzer.push({x: d.x, y: oy - 1, vx: zufall(-0.5, 0.5) * VW, vy: zufall(-22, -16) * VW, r: zufall(0.14, 0.2) * VW, leben: 0.6, saeule: true});
                        }
                    }
                    if (!weg && d.z > 0.15) {
                        for (const k of kaesten) {
                            if (d.x > k.x && d.x < k.x + k.w && d.y > k.y && d.y < k.y + d.v * dt + 2) {
                                // nicht alle Tropfen bleiben oben hängen – unten soll es auch plätschern
                                if (Math.random() < 0.45) {
                                    weg = true;
                                    // Aufprall auf der Kachelkante (auch bei Gewitter): Tröpfchen vorne
                                    // und ein kleiner flacher Ring auf der Kante
                                    if (wasserSpritzer.length < 700) {
                                        const n = 4 + Math.floor(Math.random() * 3);
                                        for (let i = 0; i < n; i++) wasserSpritzer.push({x: d.x, y: k.y - 1, vx: zufall(-7, 7) * VW, vy: zufall(-12, -5) * VW, r: zufall(0.07, 0.12) * VW, leben: zufall(0.25, 0.4), boden: k.y});
                                    }
                                    if (Math.random() < 0.6) ring(d.x, k.y, true, zufall(0.5, 1.1) * VW);
                                }
                                break;
                            }
                        }
                    }
                    if (weg) {
                        if (!flut && d.y > UNTEN && spritzer.length < 260 && Math.random() < 0.3) {
                            spritzer.push({x: d.x, y: H - 1, vx: zufall(-6, 6) * VW, vy: zufall(-9, -4) * VW, leben: zufall(0.18, 0.3)});
                        }
                        neu(d, true);
                        continue;
                    }
                    schichten[d.z < 0.33 ? 0 : (d.z < 0.66 ? 1 : 2)].push(d);
                }
                // Aufprall auf allen Kacheln: Tropfen schlagen überall auf den Kachelkanten auf,
                // nicht nur in der obersten Reihe (die die meisten fallenden Tropfen abfängt)
                const proKachel = [0, 1.8, 2.8, 3.8][staerke] || 2.8;
                for (const k of kaesten) {
                    if (flut && k.y > UNTEN * (1 - wasser)) continue;   // unter Wasser kein Aufprall
                    let n = proKachel * dt;
                    while (n > 0) {
                        if (Math.random() < n && wasserSpritzer.length < 700) {
                            const x = k.x + zufall(0.03, 0.97) * k.w;
                            const anzahl = 3 + Math.floor(Math.random() * 3);
                            for (let i = 0; i < anzahl; i++) wasserSpritzer.push({x: x, y: k.y - 1, vx: zufall(-6, 6) * VW, vy: zufall(-11, -4) * VW, r: zufall(0.07, 0.11) * VW, leben: zufall(0.22, 0.38), boden: k.y});
                            if (Math.random() < 0.5) ring(x, k.y, true, zufall(0.5, 1.0) * VW);
                        }
                        n -= 1;
                    }
                }
                // Plätschern unten: über die ganze Breite schlagen regelmäßig Tropfen auf dem
                // Wasser auf (ohne Wasser auf dem Boden über dem Schriftband) – mehr, als
                // physikalisch durch die Kacheln käme (Wunsch Jonas)
                if (!(flut && see >= 0.5)) {
                    let m = ([0, 10, 16, 22][staerke] || 16) * dt;
                    while (m > 0) {
                        if (Math.random() < m && wasserSpritzer.length < 700) {
                            const x = zufall(0, 100) * VW;
                            const y = flut && wasser > 0.005 ? oberflaeche(x, t) : UNTEN - 0.1 * VW;
                            const n = 4 + Math.floor(Math.random() * 3);
                            for (let i = 0; i < n; i++) wasserSpritzer.push({x: x, y: y - 1, vx: zufall(-7, 7) * VW, vy: zufall(-13, -5) * VW, r: zufall(0.08, 0.13) * VW, leben: zufall(0.25, 0.42), boden: y});
                            if (Math.random() < 0.3) wasserSpritzer.push({x: x, y: y - 1, vx: zufall(-0.5, 0.5) * VW, vy: zufall(-20, -14) * VW, r: zufall(0.13, 0.18) * VW, leben: 0.6, saeule: true, boden: y});
                            ring(x, y, true, zufall(0.8, 1.8) * VW);
                        }
                        m -= 1;
                    }
                }
                // im See sieht man die Tropfen kaum noch fallen, nur ihre Ringe
                const sichtbar = 1 - 0.85 * see;
                cxH.lineCap = 'round';
                for (let s = 0; s < 3; s++) {
                    cxH.strokeStyle = farbe([0.3, 0.45, 0.62][s] * sichtbar);
                    cxH.lineWidth = [0.08, 0.13, 0.2][s] * VW;
                    cxH.beginPath();
                    for (const d of schichten[s]) {
                        cxH.moveTo(d.x, d.y);
                        cxH.lineTo(d.x - dx * d.len, d.y - dy * d.len);
                    }
                    cxH.stroke();
                    // vordere Tropfen mit hellem Glanz, damit sie auch auf blauem Grund auffallen
                    if (s === 2 && !opt.dunkel) {
                        cxH.strokeStyle = `rgba(255,255,255,${0.55 * sichtbar})`;
                        cxH.lineWidth = 0.07 * VW;
                        cxH.stroke();
                    }
                }
                // Spritzer auf den Kästen
                cxH.fillStyle = farbe(0.55);
                cxH.beginPath();
                for (let i = spritzer.length - 1; i >= 0; i--) {
                    const sp = spritzer[i];
                    sp.leben -= dt;
                    if (sp.leben <= 0) { spritzer.splice(i, 1); continue; }
                    sp.x += sp.vx * dt; sp.y += sp.vy * dt; sp.vy += 60 * VW * dt;
                    cxH.moveTo(sp.x + 0.09 * VW, sp.y);
                    cxH.arc(sp.x, sp.y, 0.09 * VW, 0, 6.283);
                }
                cxH.fill();

                // ---- See von oben: überall Regenringe
                if (see > 0) {
                    const rate = [0, 16, 24, 34][staerke] * see;
                    let n = rate * dt;
                    while (n > 0) { if (Math.random() < n) ring(zufall(0, 100) * VW, zufall(0, 100) * H / 100, false, zufall(1.2, 3.2) * VW); n -= 1; }
                }
                for (let i = ringe.length - 1; i >= 0; i--) {
                    const r = ringe[i];
                    r.leben += dt;
                    if (r.leben < 0) continue;   // verzögerter Ring
                    const u = r.leben / r.dauer;
                    if (u >= 1) { ringe.splice(i, 1); continue; }
                    const rad = r.max * (0.15 + 0.85 * Math.sqrt(u));
                    const a = (1 - u) * (r.flach ? 0.55 : 0.4);
                    // Ringe auf der Wasseroberfläche auch vorne, damit man sie zwischen den Kacheln sieht
                    for (const [ctx, f] of [[cxH, 1], [cxV, r.flach ? 0.75 : 0.35]]) {
                        if (!f) continue;
                        ctx.strokeStyle = opt.dunkel ? `rgba(220,235,255,${a * f})` : `rgba(255,255,255,${a * f})`;
                        ctx.lineWidth = 0.07 * VW;
                        ctx.beginPath();
                        ctx.ellipse(r.x, r.y, rad, r.flach ? rad * 0.22 : rad * 0.8, 0, 0, 6.283);
                        ctx.stroke();
                        if (!r.flach && u < 0.6) {
                            ctx.beginPath();
                            ctx.ellipse(r.x, r.y, rad * 0.55, rad * 0.44, 0, 0, 6.283);
                            ctx.stroke();
                        }
                    }
                }

                // Tröpfchen und Wassersäulen beim Aufprall (vorne)
                cxV.fillStyle = opt.dunkel ? 'rgba(215,232,255,.85)' : 'rgba(255,255,255,.85)';
                cxV.strokeStyle = 'rgba(30,90,160,.35)';
                cxV.lineWidth = 0.03 * VW;
                cxV.beginPath();
                for (let i = wasserSpritzer.length - 1; i >= 0; i--) {
                    const sp = wasserSpritzer[i];
                    sp.leben -= dt;
                    sp.x += sp.vx * dt; sp.y += sp.vy * dt; sp.vy += 60 * VW * dt;
                    if (sp.leben <= 0 || (sp.vy > 0 && sp.y > (sp.boden !== undefined ? sp.boden : oberflaeche(sp.x, t)))) { wasserSpritzer.splice(i, 1); continue; }
                    if (sp.saeule) {
                        // längliche Säule, oben ein runder Tropfen
                        const h2 = Math.min(1.2 * VW, Math.max(0.2 * VW, -sp.vy * 0.05));
                        cxV.moveTo(sp.x + sp.r * 0.6, sp.y);
                        cxV.ellipse(sp.x, sp.y + h2 * 0.5, sp.r * 0.6, h2 * 0.5, 0, 0, 6.283);
                    }
                    cxV.moveTo(sp.x + sp.r, sp.y);
                    cxV.arc(sp.x, sp.y, sp.r, 0, 6.283);
                }
                cxV.fill();
                cxV.stroke();

                // ---- vorne: Wasserlinie und ein Hauch Blau unter Wasser (Schrift bleibt lesbar)
                if (flut && wasser > 0.005) {
                    const kante = (versatz) => {
                        cxV.beginPath();
                        for (let x = 0; x <= W + 2 * VW; x += VW) {
                            const y = oberflaeche(x, t) + versatz;
                            if (x === 0) cxV.moveTo(x, y); else cxV.lineTo(x, y);
                        }
                    };
                    cxV.fillStyle = opt.dunkel ? 'rgba(80,140,220,.13)' : 'rgba(15,75,160,.14)';
                    cxV.beginPath();
                    cxV.moveTo(0, H);
                    for (let x = 0; x <= W + 2 * VW; x += 2 * VW) cxV.lineTo(x, oberflaeche(x, t));
                    cxV.lineTo(W, H);
                    cxV.closePath();
                    cxV.fill();
                    if (see < 0.98) {
                        const k = 1 - see;
                        // dunklerer Streifen direkt unter der Oberfläche, damit man die Kante sieht
                        const top = UNTEN * (1 - wasser);
                        const band = cxV.createLinearGradient(0, top - 0.4 * VW, 0, top + 2.2 * VW);
                        band.addColorStop(0, `rgba(25,85,150,${0.28 * k})`);
                        band.addColorStop(1, 'rgba(25,85,150,0)');
                        cxV.fillStyle = band;
                        cxV.beginPath();
                        cxV.moveTo(0, top + 2.4 * VW);
                        for (let x = 0; x <= W + 2 * VW; x += 2 * VW) cxV.lineTo(x, oberflaeche(x, t));
                        cxV.lineTo(W, top + 2.4 * VW);
                        cxV.closePath();
                        cxV.fill();
                        // blauer Saum und helle Wasserlinie
                        cxV.lineJoin = 'round';
                        cxV.strokeStyle = `rgba(30,105,180,${0.55 * k})`;
                        cxV.lineWidth = 0.42 * VW;
                        kante(0.12 * VW); cxV.stroke();
                        cxV.strokeStyle = `rgba(255,255,255,${0.9 * k})`;
                        cxV.lineWidth = 0.16 * VW;
                        kante(-0.05 * VW); cxV.stroke();
                    }
                    // gemeinsamer Zeitslot für U-Boot und Entenfamilie
                    slotNaechster -= dt;
                    if (!uboot && !enten && slotNaechster <= 0) {
                        const ubootGeht = staerke >= 2 && UNTEN - UNTEN * (1 - wasser) > UBOOT_B * VW * 0.6 + 2 * VW;
                        const entenGehen = wasser > 0.06 && see < 0.5;   // Oberfläche von der Seite sichtbar
                        const wahl = ubootGeht && entenGehen ? (zuletzt === 'uboot' ? 'enten' : 'uboot') : (ubootGeht ? 'uboot' : (entenGehen ? 'enten' : null));
                        const richtung = Math.random() < 0.5 ? 1 : -1;
                        if (wahl === 'uboot') {
                            const el = svgAusText(ubootSvg());
                            domV.appendChild(el);
                            uboot = {el: el, richtung: richtung, x: richtung > 0 ? -UBOOT_B * VW - VW : W + VW, p: zufall(0, 6.28), blasen: []};
                        } else if (wahl === 'enten') {
                            const tiere = [];
                            const kueken = 3 + Math.floor(Math.random() * 3);
                            for (let i = 0; i <= kueken; i++) {
                                const el = svgAusText(enteSvg(i > 0));
                                domV.appendChild(el);
                                const w = (i > 0 ? 2 : 4.4) * VW;
                                tiere.push({el: el, w: w, h: w * (i > 0 ? 16 / 22 : 30 / 46), tauch: i > 0 ? 0.72 : 0.78});
                            }
                            const start = richtung > 0 ? -5 * VW : W + 5 * VW;
                            enten = {tiere: tiere, richtung: richtung, x: start, start: start};
                        }
                        if (wahl) { zuletzt = wahl; slotNaechster = dauer(zufall(60, 90), 9); }
                    }
                    if (uboot) ubootSchritt(dt, t);
                    if (enten) entenSchritt(dt, t);
                }

                // Tropfen auf der Scheibe (vorne)
                const glas = sprite('glastropfen', () => glastropfen(0.6 * VW * DPR));
                for (const d of scheibe) {
                    d.a = Math.min(1, d.a + dt * 0.5);
                    if (d.warten > 0) { d.warten -= dt; } else {
                        d.v = Math.min(d.v + 6 * VW * dt, 9 * VW);
                        d.y += d.v * dt;
                        d.x += Math.sin(t * 3 + d.r) * 0.2 * VW * dt;
                        if (Math.random() < dt * 0.8) d.warten = zufall(0.2, 1.2);
                        if (d.y > H + VW) scheibenTropfen(d);
                    }
                    const sz = d.r * 1.3;
                    cxV.globalAlpha = 0.85 * d.a;
                    cxV.drawImage(glas, d.x - sz, d.y - sz * 1.1, 2 * sz, 2.2 * sz);
                }
                cxV.globalAlpha = 1;
            },
        };
    }

    function glastropfen(r) {
        const s = Math.ceil(r * 2 + 4);
        const c = leinwand(s, s * 1.1);
        const g = c.getContext('2d');
        const m = s / 2, my = s * 0.58;
        const f = g.createRadialGradient(m, my - r * 0.3, r * 0.1, m, my, r);
        f.addColorStop(0, 'rgba(255,255,255,.05)');
        f.addColorStop(0.7, 'rgba(210,225,240,.22)');
        f.addColorStop(1, 'rgba(60,85,120,.38)');
        g.fillStyle = f;
        g.beginPath();
        g.moveTo(m, my - r * 1.25);
        g.bezierCurveTo(m + r * 0.5, my - r * 0.9, m + r, my - r * 0.3, m + r, my + r * 0.1);
        g.arc(m, my + r * 0.1, r, 0, Math.PI);
        g.bezierCurveTo(m - r, my - r * 0.3, m - r * 0.5, my - r * 0.9, m, my - r * 1.25);
        g.fill();
        g.strokeStyle = 'rgba(40,60,90,.28)';
        g.lineWidth = Math.max(1, r * 0.08);
        g.beginPath();
        g.arc(m, my + r * 0.1, r * 0.92, 0.2, Math.PI - 0.2);
        g.stroke();
        g.fillStyle = 'rgba(255,255,255,.9)';
        g.beginPath();
        g.ellipse(m - r * 0.35, my - r * 0.3, r * 0.22, r * 0.14, -0.6, 0, 6.283);
        g.fill();
        return c;
    }

    // ==================================================================
    // GEWITTER: Regen + Blitze + kurzes Zucken beim Donner
    //
    // Rücksicht auf Menschen mit Photosensitivität: höchstens zwei Lichtwechsel
    // pro Sekunde, das Aufhellen vorne bleibt schwach, Blitze kommen selten.

    // Schülertrupp, Blick nach links: zwei Träger (Arme hoch, nach dem Hochheben
    // runter) und ein Kind mit Hammer und Teleskopleiter (die Leiter malt die Leinwand).
    function kindSvgTeile(x, haar, hose, haut, art, zopf) {
        const bein = (klasse, dx) => `<g class="fx-glied ${klasse}"><path d="M${x + dx - 2.6},68 L${x + dx + 2.6},68 L${x + dx + 2.2},93 L${x + dx - 2.2},93 Z" fill="${hose}"/>
            <path d="M${x + dx - 5},92 L${x + dx + 2.6},92 L${x + dx + 2.6},96 L${x + dx - 5.5},96 Q${x + dx - 6.5},94 ${x + dx - 5},92 Z" fill="#2b2b2b"/></g>`;
        const arme = art === 'hammer'
            ? `<g class="fx-haltearm"><path d="M${x + 2},50 L${x + 9},44 L${x + 10.5},46.5 L${x + 3},53 Z" fill="#ff7a1a"/><circle cx="${x + 10}" cy="44.5" r="2.2" fill="${haut}"/></g>
               <g class="fx-ik-glied fx-ik-arm"><path d="" stroke="#ff7a1a" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/><circle r="2.3" fill="${haut}"/></g>
               <g class="fx-hammerarm"><path d="M${x - 2},50 L${x - 10},40 L${x - 8},38 L${x},48 Z" fill="#ff7a1a"/><circle cx="${x - 9.5}" cy="38.5" r="2.2" fill="${haut}"/>
               <path d="M${x - 9.5},38.5 L${x - 16},27" stroke="#8a5a30" stroke-width="2.2" stroke-linecap="round"/>
               <rect x="${x - 21}" y="22" width="10" height="5.5" rx="1" fill="#7d8790" transform="rotate(-30 ${x - 16} 25)"/></g>`
            : `<g class="fx-tragarm fx-tragarm-l"><path d="M${x - 3},50 L${x - 6},20 L${x - 2.5},19.5 L${x},48 Z" fill="#ff7a1a"/><circle cx="${x - 4.3}" cy="18" r="2.3" fill="${haut}"/></g>
               <g class="fx-tragarm fx-tragarm-r"><path d="M${x + 3},50 L${x + 5},20 L${x + 8.5},20.5 L${x + 6},50 Z" fill="#ff7a1a"/><circle cx="${x + 6.8}" cy="18.5" r="2.3" fill="${haut}"/></g>`;
        const ikBein = (n) => art === 'hammer' ? `<g class="fx-ik-glied fx-ik-bein-${n}"><path class="fx-ik-hose" d="" stroke="${hose}" stroke-width="4.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/><path class="fx-ik-schuh" d="" fill="#2b2b2b"/></g>` : '';
        return `${bein('fx-kbein-b', 1)}${ikBein('b')}
            <path d="M${x - 7},48 C${x - 7},44 ${x + 7},44 ${x + 7},48 L${x + 6},70 L${x - 6},70 Z" fill="#ff7a1a"/>
            <path d="M${x - 6.6},56 L${x + 6.6},56 M${x - 6.3},62 L${x + 6.3},62" stroke="#e8edf2" stroke-width="2"/>
            <path d="M${x - 1.5},45 L${x - 1.5},70" stroke="#2f6fb3" stroke-width="2.4"/>
            ${bein('fx-kbein-a', -1)}${ikBein('a')}
            ${arme}
            <circle cx="${x}" cy="37" r="7" fill="${haut}"/>
            <path d="M${x - 7},36 C${x - 7},28 ${x + 7},27 ${x + 7.5},35 C${x + 4},32 ${x},32 ${x - 7},36 Z" fill="${haar}"/>
            ${zopf ? `<path d="M${x + 6},34 C${x + 12},36 ${x + 12},44 ${x + 9},47" stroke="${haar}" stroke-width="3" fill="none" stroke-linecap="round"/>` : ''}
            <circle cx="${x - 3.5}" cy="37" r=".9" fill="#2a1a14"/>
            <path d="M${x - 5},40.5 q1.6,1.4 3.2,0" stroke="#2a1a14" stroke-width=".8" fill="none"/>
            <circle cx="${x - 1}" cy="40" r="1.4" fill="#f19a9a" opacity=".5"/>`;
    }
    function traegerSvg() {
        return `<svg class="fx-trupp fx-traeger fx-geht" viewBox="0 0 105 100" xmlns="${NS}">
            ${kindSvgTeile(26, '#5a3a22', '#2e3f5c', '#f2cdb0', 'tragen', true)}
            ${kindSvgTeile(78, '#1f1a17', '#3b3b46', '#c99a74', 'tragen', false)}
        </svg>`;
    }
    // Fallschirm, rot-weiß, mit Leinen zu den Schultern des Kindes (Kind darunter bei 25|75)
    function fallschirmSvg() {
        const bahnen = [];
        for (let i = 0; i < 6; i++) {
            const x0 = 4 + i * 15.33, x1 = x0 + 15.33;
            bahnen.push(`<path d="M${x0.toFixed(1)},42 Q${((x0 + x1) / 2).toFixed(1)},${i === 0 || i === 5 ? 20 : 4} ${x1.toFixed(1)},42 Q${((x0 + x1) / 2).toFixed(1)},38 ${x0.toFixed(1)},42 Z" fill="${i % 2 ? '#ffffff' : '#e8344e'}"/>`);
        }
        return `<svg class="fx-fallschirm" viewBox="0 0 100 175" xmlns="${NS}">
            <path d="M5,42 L45,122 M28,40 L46,122 M72,40 L54,122 M95,42 L55,122" stroke="#5a5a5a" stroke-width=".7" fill="none"/>
            <path d="M4,42 C4,12 96,12 96,42 Z" fill="#e8344e" stroke="#9c1f33" stroke-width="1"/>
            ${bahnen.join('')}
            <path d="M4,42 C4,12 96,12 96,42" fill="none" stroke="#9c1f33" stroke-width="1.2"/>
        </svg>`;
    }
    function hammerkindSvg() {
        return `<svg class="fx-trupp fx-hammerkind fx-geht" viewBox="0 0 50 100" xmlns="${NS}">
            ${kindSvgTeile(25, '#d8b45a', '#2e3f5c', '#f6d7bf', 'hammer', false)}
        </svg>`;
    }

    // Zeus als Silhouette im Blitzlicht, in der Haltung der Bronze vom Kap
    // Artemision: weiter Schritt, linker Arm zeigt nach vorn, der rechte holt
    // mit dem Blitzbündel weit nach hinten aus und wirft über den Kopf nach vorn.
    // Er steht auf einer Wolke; beim Blitz leuchtet ein Lichtsaum an seinem Umriss.
    // Der Wurfarm dreht sich um die Schulter (78|40), die Hand hält den Blitz bei (44|34).
    const ZEUS_SCHULTER = [78, 40], ZEUS_HAND = [44, 34], ZEUS_BREITE = 160, ZEUS_HOEHE = 124, ZEUS_VW = 24;
    // Gelenkpunkte: Hüfte (85|70), vordere Schulter (96|41), Wurfschulter (78|40), Ellbogen (58|38)
    const ZEUS_HUEFTE = [85, 70], ZEUS_VSCHULTER = [96, 41], ZEUS_ELLBOGEN = [58, 38];
    function zeusTeile(farbe, mitBlitz) {
        const glied = (d, w) => `<path d="${d}" stroke="${farbe}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
        return `
            <g class="fx-zeus-beine">
                ${glied('M81,70 C76,78 70,86 66,91 C61,97 56,103 53,108', 9)}
                ${glied('M53,108 L50,112 L60,112', 4.5)}
                ${glied('M88,69 C95,76 101,82 104,89 C106,96 108,103 110,109', 9.5)}
                ${glied('M109,110 L121,112', 4.5)}
                <path d="M77,66 C82,64 92,64 95,70 C93,75 82,77 77,73 Z" fill="${farbe}"/>
            </g>
            <g class="fx-zeus-oben">
                <path d="M74,40 C76,36 90,35 99,39 C101,48 96,58 93,66 C91,72 80,74 78,70 C75,62 72,50 74,40 Z" fill="${farbe}"/>
                <g class="fx-zeus-vorn">
                    ${glied('M96,41 C108,39 122,37 137,35', 6)}
                    ${glied('M137,35 L143,33.5', 3.2)}
                </g>
                ${glied('M84,36 L86,31', 6)}
                <circle cx="88" cy="25.5" r="7" fill="${farbe}"/>
                <path d="M84,28 C86,34 93,37 97,33 C97,30 95,28 93,28 Z" fill="${farbe}"/>
                <path d="M93,22 L97,25.5 L94,26.5 Z" fill="${farbe}"/>
                <path d="M81,22 C80,17 86,15 90,17 C87,18 84,19 81,22 Z" fill="${farbe}"/>
                <g class="fx-zeus-arm">
                    ${glied('M80,41 C72,40 64,39 58,38', 6.5)}
                    <g class="fx-zeus-unterarm">
                        ${mitBlitz ? '<circle cx="44" cy="34" r="20" fill="url(#fx-zglut)"/>' : ''}
                        ${glied('M58,38 C53,37 49,36 45,34.5', 5.2)}
                        <circle cx="44" cy="34" r="3.6" fill="${farbe}"/>
                        ${mitBlitz ? '${keraunos}' : ''}
                    </g>
                </g>
            </g>`;
    }
    function zeusSvg() {
        const dunkel = '#0f131a', licht = '#dce9ff';
        const keraunos = `<g transform="translate(44 34) rotate(-75)">
            <path d="M3,0 C7,-4 12,-3 18,-9 L16,-3 L25,-5 L18.5,0.5 L26,4.5 L16.5,3.5 L19,9 C12,4 7,5 3,0 Z" fill="url(#fx-zgold)"/>
            <path d="M-3,0 C-7,-4 -12,-3 -18,-9 L-16,-3 L-25,-5 L-18.5,0.5 L-26,4.5 L-16.5,3.5 L-19,9 C-12,4 -7,5 -3,0 Z" fill="url(#fx-zgold)"/>
            <rect x="-4" y="-2.5" width="8" height="5" rx="1.8" fill="#c08a2a"/>
            <path class="fx-knistern" d="M25,-5 l5,-4 l-1,5 l6,-3 M26,4.5 l6,2 l-4,2 l6,3 M-25,-5 l-5,-4 l1,5 l-6,-3 M-26,4.5 l-6,2 l4,2 l-6,3" stroke="#e8f1ff" stroke-width="1.1" fill="none" stroke-linejoin="round"/>
        </g>`;
        const wolke = [[30, 116, 14], [52, 112, 18], [78, 116, 20], [104, 112, 18], [128, 116, 15], [146, 119, 10], [16, 120, 10]]
            .map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}"/>`).join('');
        return `<svg class="fx-zeus" viewBox="0 0 ${ZEUS_BREITE} ${ZEUS_HOEHE}" xmlns="${NS}">
        <defs>
            <linearGradient id="fx-zgold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fffbe0"/><stop offset=".45" stop-color="#ffd85a"/><stop offset="1" stop-color="#d39a1c"/></linearGradient>
            <radialGradient id="fx-zglut"><stop offset="0" stop-color="#fff6c8" stop-opacity=".95"/><stop offset=".4" stop-color="#ffd86b" stop-opacity=".45"/><stop offset="1" stop-color="#ffd86b" stop-opacity="0"/></radialGradient>
            <radialGradient id="fx-zwolke" cx=".5" cy=".3" r=".8"><stop offset="0" stop-color="#4c5666"/><stop offset="1" stop-color="#232933"/></radialGradient>
            <filter id="fx-zweich" x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="2.6"/></filter>
            <filter id="fx-zsaum" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="1.1"/></filter>
        </defs>
        <!-- Lichtsaum: helle Kopie, leicht versetzt und weich, hinter der dunklen Figur -->
        <g class="fx-zeus-saum" filter="url(#fx-zsaum)" opacity=".25">
            <g transform="translate(1.6 -1.2)">${zeusTeile(licht, false)}</g>
        </g>
        ${zeusTeile(dunkel, true).replace('${keraunos}', keraunos)}
        <!-- Wolke, auf der er steht -->
        <g fill="#8d98a8" opacity=".5" filter="url(#fx-zweich)" transform="translate(0 -3)">${wolke}</g>
        <g fill="url(#fx-zwolke)" filter="url(#fx-zweich)">${wolke}</g>
    </svg>`;
    }

    function drehePunkt(p, um, grad) {
        const w = grad * Math.PI / 180, c = Math.cos(w), sn = Math.sin(w);
        return [um[0] + (p[0] - um[0]) * c - (p[1] - um[1]) * sn, um[1] + (p[0] - um[0]) * sn + (p[1] - um[1]) * c];
    }
    // Wurf als Bewegungskette: erst der Körper, dann der Oberarm, zuletzt
    // schnellt der Unterarm nach (Peitsche); danach schwingt alles aus.
    function zeusPose(z, s, t) {
        const glatt = (u) => u <= 0 ? 0 : (u >= 1 ? 1 : u * u * (3 - 2 * u));
        const mix = (a, b, u) => a + (b - a) * u;
        // Ruhe: leichtes Atmen
        const atem = Math.sin(t * 2.2) * 0.6;
        // 1) Ausholen 0,5–1,1 s: zurücklehnen, Oberarm nach hinten unten, Ellbogen knickt
        const ah = glatt((s - 0.5) / 0.6);
        // 2) Wurf 1,1–1,4 s: Körper kippt vor, Oberarm über den Kopf (beschleunigt), Unterarm folgt verzögert
        const wk = Math.max(0, Math.min(1, (s - 1.1) / 0.3));
        const wo = wk * wk;                                   // Oberarm beschleunigt
        const wu = glatt((s - 1.18) / 0.22);                  // Unterarm schnellt hinterher
        // 3) Ausschwingen ab 1,4 s: gedämpfte Schwingung um die Endhaltung
        const nach = s > 1.4 ? Math.exp(-(s - 1.4) * 4) * Math.sin((s - 1.4) * 16) : 0;
        z.lehne = mix(mix(atem * 0.3, -7, ah), 8, glatt(wk * 1.2)) - (s > 1.4 ? 4 * glatt((s - 1.4) / 0.8) : 0) + nach * 1.5;
        z.oberarm = mix(mix(atem, -24, ah), 152, wo) + nach * 8;
        z.unterarm = mix(mix(0, -48, ah), 6, wu) + nach * 14;
        z.vorn = mix(mix(0, -10, ah), 28, glatt(wk)) + nach * 4;
    }

    function Gewitter(staerke, mitZeus) {
        const regen = Regen(Math.min(3, staerke + 1), true);
        let blitz = null;
        let naechster = dauer(zufall(4, 10), mitZeus ? 5 : 1.5);
        let donner = [];
        function helligkeit(s) {
            if (s < 0.07) return 1;
            if (s < 0.16) return 0.12;
            if (s < 0.27) return 0.85;
            if (s < 0.8) return 0.85 * (1 - (s - 0.27) / 0.53);
            return 0;
        }
        let zeus = null;
        let einschlag = null, risse = null;
        // Rissnetz vom Einschlagpunkt aus: dunkle Bruchlinie mit hellem Rand (wie Putz)
        function risseZeichnen(ort) {
            const c = leinwand(W * DPR, H * DPR);
            const g = c.getContext('2d');
            g.setTransform(DPR, 0, 0, DPR, 0, 0);
            g.lineCap = 'round'; g.lineJoin = 'round';
            const linien = [];
            function riss(x, y, w, laenge, dicke, tiefe) {
                const pts = [[x, y]];
                let l = 0;
                while (l < laenge) {
                    const schritt = zufall(1.2, 3.2) * VW;
                    w += zufall(-0.45, 0.45);
                    x += Math.cos(w) * schritt; y += Math.sin(w) * schritt; l += schritt;
                    pts.push([x, y]);
                    if (tiefe > 0 && Math.random() < 0.22) riss(x, y, w + zufall(-1.1, 1.1), laenge * zufall(0.25, 0.5), dicke * 0.55, tiefe - 1);
                }
                linien.push({pts: pts, dicke: dicke});
            }
            const n = 9;
            for (let i = 0; i < n; i++) {
                riss(ort[0], ort[1], Math.PI * 2 * i / n + zufall(-0.3, 0.3), zufall(25, 70) * VW, zufall(0.18, 0.3) * VW, 2);
            }
            for (const [farbe, versatz, faktor] of [['rgba(255,255,255,.55)', 0.08 * VW, 1.1], ['rgba(35,30,28,.75)', 0, 1]]) {
                g.strokeStyle = farbe;
                for (const l of linien) {
                    g.lineWidth = Math.max(0.7, l.dicke * faktor);
                    g.beginPath();
                    l.pts.forEach(([x, y], i) => i ? g.lineTo(x + versatz, y + versatz) : g.moveTo(x + versatz, y + versatz));
                    g.stroke();
                }
            }
            // Einschlagkrater: dunkler, zersplitterter Fleck
            const k = g.createRadialGradient(ort[0], ort[1], 0, ort[0], ort[1], 4 * VW);
            k.addColorStop(0, 'rgba(30,25,22,.55)'); k.addColorStop(1, 'rgba(30,25,22,0)');
            g.fillStyle = k;
            g.beginPath(); g.arc(ort[0], ort[1], 4 * VW, 0, 6.283); g.fill();
            return c;
        }
        // Risse an den Kacheln, unter der Schrift: beim Einschlag springt jede getroffene
        // Kachel sofort an einer Ecke oder Kante; danach wachsen die Risse die ganze Zeit
        // langsam weiter, verzweigen sich und durchziehen am Ende die Kachel – genau dann,
        // wenn sie mit dem Hintergrund zusammen verheilt sind.
        function kachelRisse(ort) {
            const alle = [];
            for (const k of kaesten) {
                const nah = Math.hypot(k.x + k.w / 2 - ort[0], k.y + k.h / 2 - ort[1]) / W;
                if (Math.random() > 0.9 - nah * 0.5) continue;
                const wVw = k.w / VW, hVw = k.h / VW;
                const s = svg('svg', {viewBox: `0 0 ${wVw.toFixed(2)} ${hVw.toFixed(2)}`, class: 'fx-deko fx-riss'});
                Object.assign(s.style, {left: '0', top: '0', width: `${wVw}vw`, height: `${hVw}vw`, overflow: 'hidden'});
                const pfade = [];
                // ein Riss läuft von (x, y) in Richtung w, bleibt in der Kachel; f0 = ab welchem
                // Wachstum er beginnt (Verzweigungen starten, wenn der Hauptriss dort ankommt)
                function riss(x, y, w, laenge, dicke, f0, f1, tiefe) {
                    let d = `M ${x.toFixed(2)} ${y.toFixed(2)}`;
                    const punkte = [];
                    let l = 0;
                    while (l < laenge) {
                        const schritt = zufall(0.35, 0.9);
                        w += zufall(-0.45, 0.45);
                        x += Math.cos(w) * schritt; y += Math.sin(w) * schritt; l += schritt;
                        // an den Kanten zurück nach innen lenken
                        if (x < 0.2 || x > wVw - 0.2 || y < 0.2 || y > hVw - 0.2) {
                            x = Math.max(0.2, Math.min(wVw - 0.2, x)); y = Math.max(0.2, Math.min(hVw - 0.2, y));
                            w = Math.atan2(hVw / 2 - y, wVw / 2 - x) + zufall(-0.9, 0.9);
                        }
                        d += ` L ${x.toFixed(2)} ${y.toFixed(2)}`;
                        punkte.push([x, y, w, l / laenge]);
                    }
                    const hell = svg('path', {d: d, stroke: 'rgba(255,255,255,.75)', 'stroke-width': dicke * 1.5, fill: 'none', transform: 'translate(0.05 0.05)', 'stroke-linejoin': 'round', 'stroke-linecap': 'round', pathLength: 1});
                    const dunkel = svg('path', {d: d, stroke: 'rgba(40,34,30,.75)', 'stroke-width': dicke, fill: 'none', 'stroke-linejoin': 'round', 'stroke-linecap': 'round', pathLength: 1});
                    for (const pf of [hell, dunkel]) { pf.style.strokeDasharray = '1 2'; pf.style.strokeDashoffset = '1'; s.appendChild(pf); }
                    pfade.push({els: [hell, dunkel], f0: f0, f1: f1});
                    if (tiefe > 0) {
                        for (const pt of punkte) {
                            if (Math.random() < 0.09) {
                                const fStart = f0 + (f1 - f0) * pt[3];
                                riss(pt[0], pt[1], pt[2] + auswahl([-1, 1]) * zufall(0.5, 1.1), laenge * zufall(0.25, 0.5), dicke * 0.65, fStart, Math.min(1, fStart + (f1 - fStart) * zufall(0.7, 1)), tiefe - 1);
                            }
                        }
                    }
                }
                const anzahl = 2 + Math.floor(Math.random() * 2);
                const diagonale = Math.hypot(wVw, hVw);
                for (let i = 0; i < anzahl; i++) {
                    const ecke = auswahl([[0.2, 0.2], [wVw - 0.2, 0.2], [0.2, hVw - 0.2], [wVw - 0.2, hVw - 0.2], [zufall(0.15, 0.85) * wVw, hVw - 0.2], [wVw - 0.2, zufall(0.2, 0.8) * hVw], [zufall(0.15, 0.85) * wVw, 0.2]]);
                    const w = Math.atan2(hVw / 2 - ecke[1], wVw / 2 - ecke[0]) + zufall(-0.5, 0.5);
                    riss(ecke[0], ecke[1], w, diagonale * zufall(0.75, 1.1), zufall(0.09, 0.13), 0, 1, 2);
                }
                k.el.insertBefore(s, k.el.firstChild);
                alle.push({el: s, pfade: pfade});
            }
            return alle;
        }
        // Wachstum der Kachelrisse: sofort ein kurzer Sprung, dann gleichmäßig bis zum Ende
        function risseWachsen(liste, anteil) {
            const g = 0.12 + 0.88 * Math.max(0, Math.min(1, anteil));
            for (const r of liste) {
                for (const p of r.pfade) {
                    const u = p.f1 > p.f0 ? Math.max(0, Math.min(1, (g - p.f0) / (p.f1 - p.f0))) : 1;
                    const off = (1 - u).toFixed(4);
                    for (const el of p.els) el.style.strokeDashoffset = off;
                }
            }
        }
        // an Zeus-Tagen gibt es auch normale Blitze; nach seinem Blitz kommt Zeus erst nach 1–2 Minuten wieder
        let zeusAb = 0;
        function blitzZeichnen(start, ende) {
            const c = leinwand(W * DPR, H * DPR);
            const g = c.getContext('2d');
            g.setTransform(DPR, 0, 0, DPR, 0, 0);
            const pfade = [];
            function ast(x0, y0, x1, y1, versatz, tiefe, dicke) {
                let punkte = [[x0, y0], [x1, y1]];
                for (let i = 0; i < tiefe; i++) {
                    const neu = [punkte[0]];
                    for (let j = 1; j < punkte.length; j++) {
                        const a = punkte[j - 1], b = punkte[j];
                        neu.push([(a[0] + b[0]) / 2 + zufall(-versatz, versatz), (a[1] + b[1]) / 2 + zufall(-versatz, versatz) * 0.3]);
                        neu.push(b);
                    }
                    punkte = neu;
                    versatz *= 0.55;
                }
                pfade.push({punkte: punkte, dicke: dicke});
                if (dicke > 0.6) {
                    for (let i = 4; i < punkte.length - 4; i++) {
                        if (Math.random() < 0.035) {
                            const p = punkte[i];
                            const l = zufall(6, 16) * VW;
                            const w = zufall(-1, 1) * 0.9 + Math.PI / 2;
                            ast(p[0], p[1], p[0] + Math.cos(w) * l * (Math.random() < 0.5 ? -1 : 1) * 0.6, p[1] + Math.sin(w) * l, l * 0.18, 5, dicke * 0.45);
                        }
                    }
                }
            }
            const x0 = start ? start[0] : zufall(12, 88) * VW;
            const y0 = start ? start[1] : -2 * VW;
            if (ende) {
                // der große, böse Blitz: dicker, mit mehr Ästen, quer übers Bild
                ast(x0, y0, ende[0], ende[1], 14 * VW, 8, 1.9);
            } else {
                ast(x0, y0, x0 + zufall(-14, 14) * VW, Math.max(y0 + 20 * VW, H * zufall(0.55, 0.9)), 9 * VW, 7, 1);
            }
            g.lineCap = 'round';
            g.lineJoin = 'round';
            for (const durchgang of [
                {farbe: 'rgba(150,180,255,.35)', breite: 1.1, schatten: 3.0},
                {farbe: 'rgba(225,235,255,.95)', breite: 0.32, schatten: 0.8},
                {farbe: 'rgba(255,255,255,1)', breite: 0.12, schatten: 0},
            ]) {
                g.strokeStyle = durchgang.farbe;
                g.shadowColor = 'rgba(160,190,255,1)';
                g.shadowBlur = durchgang.schatten * VW;
                for (const p of pfade) {
                    g.lineWidth = Math.max(0.6, durchgang.breite * VW * p.dicke);
                    g.beginPath();
                    g.moveTo(p.punkte[0][0], p.punkte[0][1]);
                    for (const q of p.punkte) g.lineTo(q[0], q[1]);
                    g.stroke();
                }
            }
            return c;
        }
        return {
            stop() { regen.stop(); if (zeus) zeus.el.remove(); for (const r of document.querySelectorAll('.fx-riss')) r.remove(); },
            groesse() { blitz = null; },
            schritt(dt, t) {
                regen.schritt(dt, t);
                naechster -= dt;
                // Zeus blendet sich 4,3 Sekunden vor dem Blitz langsam ein, holt aus und wirft ihn
                if (mitZeus && !zeus && naechster <= 4.33 && naechster > 4.08 && t >= zeusAb) {
                    zeusAb = t + 999;   // wird beim Einschlag neu gesetzt
                    const el = svgAusText(zeusSvg());
                    domV.appendChild(el);
                    zeus = {el: el, saum: el.querySelector('.fx-zeus-saum'), start: t,
                            // in der linken oder rechten oberen Ecke; rechts gespiegelt, wirft dann nach links
                            spiegel: Math.random() < 0.5, x: 0,
                            lehne: 0, oberarm: 0, unterarm: 0, vorn: 0,
                            teile: {oben: el.querySelectorAll('.fx-zeus-oben'), arm: el.querySelectorAll('.fx-zeus-arm'),
                                    unterarm: el.querySelectorAll('.fx-zeus-unterarm'), vorn: el.querySelectorAll('.fx-zeus-vorn')}};
                }
                if (zeus) {
                    const s = t - zeus.start;
                    // aus dem Dunkel einblenden, weit ausholen, über den Kopf werfen,
                    // im Blitzlicht stehen bleiben, wieder ins Dunkel verblassen
                    // 3,5 s langsam aus dem Dunkel auftauchen, dann Wurf (Loslassen bei 4,33 s),
                    // kurz im Blitzlicht stehen, wieder verblassen
                    const ein = Math.min(1, s / 3.5);
                    const deckkraft = s < 3.5 ? ein * ein * (3 - 2 * ein) : (s < 5.6 ? 1 : Math.max(0, 1 - (s - 5.6) / 0.8));
                    zeusPose(zeus, s - 3.0, t);
                    zeus.y = -0.6 * VW - (1 - Math.min(1, s / 3.5)) * 1.5 * VW;
                    zeus.x = zeus.spiegel ? W - ZEUS_VW * VW + 0.5 * VW : -0.5 * VW;
                    zeus.el.style.opacity = deckkraft.toFixed(3);
                    zeus.el.style.transform = `translate(${zeus.x.toFixed(1)}px, ${zeus.y.toFixed(1)}px)${zeus.spiegel ? ' scaleX(-1)' : ''}`;
                    const setze = (liste, w, p) => { for (const e of liste) e.setAttribute('transform', `rotate(${w.toFixed(2)} ${p[0]} ${p[1]})`); };
                    setze(zeus.teile.oben, zeus.lehne, ZEUS_HUEFTE);
                    setze(zeus.teile.vorn, zeus.vorn, ZEUS_VSCHULTER);
                    setze(zeus.teile.arm, zeus.oberarm, ZEUS_SCHULTER);
                    setze(zeus.teile.unterarm, zeus.unterarm, ZEUS_ELLBOGEN);
                    // Lichtsaum: schwach, im Blitz hell
                    const hell = blitz ? helligkeit(t - blitz.start) : 0;
                    zeus.saum.setAttribute('opacity', (0.22 + 0.78 * hell).toFixed(3));
                    if (s > 6.5) { zeus.el.remove(); zeus = null; }
                }
                if (naechster <= 0) {
                    let start = null;
                    if (zeus) {
                        // Startpunkt des Blitzes: die Hand nach dem Wurf
                        const m = ZEUS_VW * VW / ZEUS_BREITE;
                        let h = drehePunkt(ZEUS_HAND, ZEUS_ELLBOGEN, zeus.unterarm);
                        h = drehePunkt(h, ZEUS_SCHULTER, zeus.oberarm);
                        h = drehePunkt(h, ZEUS_HUEFTE, zeus.lehne);
                        const hx = zeus.spiegel ? (ZEUS_BREITE - h[0]) : h[0];
                        start = [zeus.x + hx * m, (zeus.y || 0) + h[1] * m];
                    }
                    // Zeus' Blitz zuckt quer über den ganzen Monitor bis in die gegenüberliegende Ecke
                    const ende = zeus ? [zeus.spiegel ? zufall(2, 10) * VW : W - zufall(2, 10) * VW, H * zufall(0.88, 0.98)] : null;
                    blitz = {bild: blitzZeichnen(start, ende), start: t, zeus: !!zeus};
                    // es kracht: alles bebt, bekommt Risse; danach 1–2 Minuten kein Zeus
                    if (zeus) {
                        einschlag = {t: t + 0.12, ort: ende};
                        zeusAb = t + dauer(zufall(60, 120), 16);   // Zeus kommt alle 1–2 Minuten
                    }
                    // nächster Blitz nach 5–20 Sekunden (Wunsch Jonas); Zeus braucht ≥ 4,3 s Vorlauf
                    naechster = dauer(zufall(5, 20), zufall(6, 11));
                    donner.push(t + zufall(1.2, 2.6));
                }
                if (blitz) {
                    const h = helligkeit(t - blitz.start);
                    if (h <= 0 && t - blitz.start > 1) {
                        blitz = null;
                    } else {
                        cxH.fillStyle = `rgba(225,235,255,${0.28 * h})`;
                        cxH.fillRect(0, 0, W, H);
                        cxH.globalAlpha = h;
                        cxH.drawImage(blitz.bild, 0, 0, W, H);
                        cxH.globalAlpha = 1;
                        cxV.fillStyle = `rgba(235,242,255,${(blitz.zeus ? 0.22 : 0.13) * h})`;
                        cxV.fillRect(0, 0, W, H);
                        // Zeus' Blitz zuckt vor den Kacheln quer übers ganze Bild (keine Sekunde lang)
                        if (blitz.zeus) {
                            cxV.globalAlpha = h;
                            cxV.drawImage(blitz.bild, 0, 0, W, H);
                            cxV.globalAlpha = 1;
                        }
                    }
                }
                if (donner.length && t >= donner[0]) {
                    donner.shift();
                    kaestenRuetteln('fx-zucken', 750);
                }
                if (einschlag && t >= einschlag.t) {
                    kaestenRuetteln('fx-beben', 1500);
                    // Hintergrund und Kacheln springen im selben Augenblick
                    // Risse bleiben 30 Sekunden (Wunsch Jonas): erst deutlich, im letzten Drittel heilen sie
                    const bleiben = 30;
                    risse = {bild: risseZeichnen(einschlag.ort), start: t, kacheln: kachelRisse(einschlag.ort),
                        halten: dauer(bleiben * 0.67, 8), heilen: dauer(bleiben * 0.33, 6)};
                    einschlag = null;
                }
                // Risse im Hintergrund: 1 Minute deutlich, dann heilen sie langsam zu
                if (risse) {
                    const alter = t - risse.start;
                    const halten = risse.halten, heilen = risse.heilen;
                    const a = alter < halten ? 1 : Math.max(0, 1 - (alter - halten) / heilen);
                    // die Risse in den Kacheln heilen genau gleich mit
                    for (const r of risse.kacheln) r.el.style.opacity = a.toFixed(3);
                    risseWachsen(risse.kacheln, alter / (halten + heilen));
                    if (a <= 0) { for (const r of risse.kacheln) r.el.remove(); risse = null; } else {
                        cxH.globalAlpha = a;
                        cxH.drawImage(risse.bild, 0, 0, W, H);
                        cxH.globalAlpha = 1;
                    }
                }
            },
        };
    }

    // ==================================================================
    // HITZE: Sonne, warmes Licht, schmelzende Kästen

    function Hitze(staerke) {
        const sonne = document.createElement('div');
        sonne.className = 'fx-sonne';
        sonne.appendChild(Object.assign(document.createElement('div'), {className: 'fx-sonne-strahlen'}));
        const toenung = Object.assign(document.createElement('div'), {className: 'fx-hitze-toenung'});
        const glanz = Object.assign(document.createElement('div'), {className: 'fx-hitze-glanz'});
        domH.appendChild(toenung);
        domH.appendChild(sonne);
        domV.appendChild(glanz);
        const flimmern = [];
        for (let i = 0; i < 14; i++) flimmern.push({x: zufall(0, 100), y: zufall(0, 100), v: zufall(2, 5), p: zufall(0, 6.28), l: zufall(8, 18)});
        // die Kacheln zerfließen im Lauf des Tages (7:30 Uhr normal, 14:00 Uhr am stärksten)
        let t0 = null, schmelzStand = 0;
        const tropfen = setInterval(() => dekorieren('hitze', (el, w, h) => schmelzen(el, w, staerke, schmelzStand)), 2000);
        // alle 3 bis 5 Minuten fährt unten ein Eiswagen vorbei
        let wagen = null;
        let naechsterWagen = vorschau ? 2 : zufall(30, 120);
        return {
            stop() { clearInterval(tropfen); sonne.remove(); toenung.remove(); glanz.remove(); if (wagen) wagen.el.remove(); dekoEntfernen(); uhrWeg(); },
            schritt(dt, t) {
                if (t0 === null) t0 = t;
                const anteil = tagAnteil(t0, t);
                zeitrafferUhr(anteil);
                // Form neu zeichnen, sobald es merklich weiter geschmolzen ist
                if (Math.abs(anteil - schmelzStand) >= 0.04 || (anteil >= 1 && schmelzStand < 1)) {
                    schmelzStand = anteil;
                    for (const el of document.querySelectorAll('[data-fx-deko="hitze"]')) {
                        for (const alt of el.querySelectorAll(':scope > .fx-deko')) alt.remove();
                        delete el.dataset.fxDeko;
                    }
                    dekorieren('hitze', (el, w, h) => schmelzen(el, w, staerke, schmelzStand));
                }
                naechsterWagen -= dt;
                if (!wagen && naechsterWagen <= 0) {
                    const el = svgAusText(eiswagenSvg());
                    domV.appendChild(el);
                    wagen = {el: el, start: t, dauer: 15};
                    naechsterWagen = dauer(zufall(3, 5) * 60, 22);  // alle 3 bis 5 Minuten
                }
                if (wagen) {
                    const p = (t - wagen.start) / wagen.dauer;
                    if (p >= 1) { wagen.el.remove(); wagen = null; } else {
                        const breite = 24 * VW;
                        const x = -breite - VW + (W + breite + 2 * VW) * p;
                        // leichtes Federn auf der Straße
                        const y = LAUF_BODEN - breite * 0.5 - 0.2 * VW + Math.abs(Math.sin(t * 7)) * -0.12 * VW;
                        wagen.el.style.transform = `translate(${x}px, ${y}px)`;
                    }
                }
                // aufsteigende Hitzeschlieren
                cxH.lineWidth = 0.5 * VW;
                cxH.lineCap = 'round';
                for (const f of flimmern) {
                    f.y -= f.v * dt;
                    if (f.y < -20) { f.y = 110; f.x = zufall(0, 100); }
                    cxH.strokeStyle = opt.dunkel ? 'rgba(255,190,120,.05)' : 'rgba(255,170,90,.07)';
                    cxH.beginPath();
                    for (let i = 0; i <= 10; i++) {
                        const yy = (f.y + i * f.l / 10) * H / 100;
                        const xx = f.x * VW + Math.sin(t * 1.3 + f.p + i * 0.7) * 0.9 * VW;
                        if (i === 0) cxH.moveTo(xx, yy); else cxH.lineTo(xx, yy);
                    }
                    cxH.stroke();
                }
            },
        };
    }

    // Eiswagen in der Seitenansicht, fährt nach rechts (Führerhaus rechts)
    function eiswagenSvg() {
        return `<svg class="fx-eiswagen" viewBox="0 0 300 150" xmlns="${NS}">
        <defs>
            <linearGradient id="fx-wagen-lack" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#bff0dc"/><stop offset="1" stop-color="#7fcfb5"/></linearGradient>
            <linearGradient id="fx-waffel" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e9b86c"/><stop offset="1" stop-color="#c98b3d"/></linearGradient>
            <linearGradient id="fx-scheibe" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e6f5fd"/><stop offset="1" stop-color="#9fcde8"/></linearGradient>
            <clipPath id="fx-markise-clip"><rect x="44" y="40" width="124" height="20"/></clipPath>
        </defs>
        <ellipse cx="148" cy="138" rx="128" ry="5" fill="rgba(0,0,0,.18)"/>
        <!-- Waffeltüte auf dem Dach -->
        <g transform="translate(96 -2)">
            <path d="M14,30 L34,30 L24,58 Z" fill="url(#fx-waffel)"/>
            <path d="M16,34 L30,48 M20,32 L32,40 M32,34 L18,48 M28,32 L16,40" stroke="#a96e2a" stroke-width="1" opacity=".7"/>
            <circle cx="18" cy="26" r="8" fill="#f6a3c0"/>
            <circle cx="30" cy="26" r="8" fill="#fff4dc"/>
            <circle cx="24" cy="16" r="8.5" fill="#8a5a3c"/>
            <circle cx="24" cy="6" r="3" fill="#e0263a"/>
            <path d="M24,3 q2,-4 5,-5" stroke="#3e7d3a" stroke-width="1.2" fill="none"/>
            <path class="fx-kugel-tropfen" d="M13,30 q-1,6 1,9 q2,-3 1,-9 Z" fill="#f6a3c0"/>
            <circle cx="21" cy="12" r="2" fill="#fff" opacity=".45"/>
        </g>
        <!-- Aufbau -->
        <path d="M18,112 L18,62 Q18,38 42,38 L188,38 Q202,38 210,50 L238,82 Q262,84 272,96 L274,112 Q274,122 264,122 L28,122 Q18,122 18,112 Z" fill="url(#fx-wagen-lack)"/>
        <path d="M18,104 L274,104 L274,112 Q274,122 264,122 L28,122 Q18,122 18,112 Z" fill="#f28fb1"/>
        <path d="M18,101 L274,101" stroke="#fff" stroke-width="2.5"/>
        <!-- Verkaufsfenster mit Markise -->
        <rect x="50" y="58" width="112" height="34" rx="3" fill="#2f5d62"/>
        <rect x="56" y="72" width="16" height="20" rx="2" fill="#fff4dc"/><rect x="76" y="70" width="16" height="22" rx="2" fill="#f6a3c0"/>
        <rect x="96" y="73" width="16" height="19" rx="2" fill="#8a5a3c"/><rect x="116" y="71" width="16" height="21" rx="2" fill="#bfe3a0"/>
        <rect x="136" y="72" width="16" height="20" rx="2" fill="#ffd56e"/>
        <rect x="46" y="91" width="120" height="5" rx="2" fill="#ffffff"/>
        <g clip-path="url(#fx-markise-clip)">
            <rect x="44" y="40" width="124" height="14" fill="#ffffff"/>
            <rect x="44" y="40" width="14" height="14" fill="#f28fb1"/><rect x="72" y="40" width="14" height="14" fill="#f28fb1"/>
            <rect x="100" y="40" width="14" height="14" fill="#f28fb1"/><rect x="128" y="40" width="14" height="14" fill="#f28fb1"/><rect x="156" y="40" width="14" height="14" fill="#f28fb1"/>
        </g>
        <path d="M44,54 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 q3.5,6 7,0 Z" fill="#f28fb1"/>
        <text x="106" y="117" text-anchor="middle" font-family="Georgia, 'Times New Roman', serif" font-style="italic" font-weight="bold" font-size="13" fill="#ffffff">Eis</text>
        <!-- Führerhaus -->
        <path d="M194,50 L214,50 L236,82 L194,82 Z" fill="url(#fx-scheibe)" stroke="#5aa58f" stroke-width="2"/>
        <path d="M200,56 L210,56 L222,74" stroke="#fff" stroke-width="2" opacity=".7" fill="none"/>
        <circle cx="206" cy="68" r="5.5" fill="#f3c9a8"/><path d="M200,64 q6,-7 12,0 Z" fill="#ffffff"/>
        <path d="M188,62 L188,100" stroke="#5aa58f" stroke-width="1.5"/>
        <rect x="178" y="80" width="7" height="2.5" rx="1" fill="#5aa58f"/>
        <circle cx="266" cy="96" r="4.5" fill="#fff6c7" stroke="#d9c26b" stroke-width="1.5"/>
        <rect x="262" y="112" width="16" height="6" rx="3" fill="#d6d6d6"/>
        <rect x="14" y="112" width="12" height="6" rx="3" fill="#d6d6d6"/>
        <!-- Räder -->
        <g transform="translate(70 122)"><circle r="17" fill="#2b2b2b"/><g class="fx-rad"><circle r="9" fill="#e6e6e6"/><path d="M0,-9 L0,9 M-9,0 L9,0 M-6.4,-6.4 L6.4,6.4 M-6.4,6.4 L6.4,-6.4" stroke="#9a9a9a" stroke-width="1.6"/></g><circle r="2.5" fill="#777"/></g>
        <g transform="translate(228 122)"><circle r="17" fill="#2b2b2b"/><g class="fx-rad"><circle r="9" fill="#e6e6e6"/><path d="M0,-9 L0,9 M-9,0 L9,0 M-6.4,-6.4 L6.4,6.4 M-6.4,6.4 L6.4,-6.4" stroke="#9a9a9a" stroke-width="1.6"/></g><circle r="2.5" fill="#777"/></g>
    </svg>`;
    }

    // Die Kachel zerfließt: Statt des rechteckigen Hintergrunds liegt eine
    // geschmolzene Form hinter dem Inhalt – Seiten leicht gewölbt, untere Ecken
    // abgesackt, breite Tropfnasen an der Unterkante, aus denen Tropfen fallen.
    // Die Schrift wird nicht verzerrt und bleibt lesbar.
    // grad: 0 = noch fest, 1 = am stärksten geschmolzen (um 14:00 Uhr)
    function schmelzen(el, wVw, staerke, grad) {
        grad = Math.max(0.02, Math.min(1, grad === undefined ? 1 : grad));
        // zufällige Form je Kachel merken, damit sie beim Weiterschmelzen gleich bleibt
        if (!el._fxSchmelz) el._fxSchmelz = {saat: Math.random() * 1000};
        let saat = el._fxSchmelz.saat;
        const zuf = (a, b) => { saat = (saat * 9301 + 49297) % 233280; return a + (b - a) * saat / 233280; };
        const r = el.getBoundingClientRect();
        const hVw = r.height / VW;
        // Farbe des Kachelhintergrunds, etwas deckender, damit die Schrift gut lesbar bleibt.
        // Nur beim ersten Mal lesen: danach ist der Hintergrund (fx-geschmolzen) durchsichtig
        // und würde als Schwarz gelesen – beim Zeitraffer wurden die Kacheln sonst schwarz.
        if (!el._fxSchmelz.farbe) {
            const roh = el.classList.contains('fx-geschmolzen') ? '' : getComputedStyle(el).backgroundColor;
            el._fxSchmelz.farbe = (roh || '').match(/[\d.]+/g) || [255, 255, 255, 0.7];
            if (el._fxSchmelz.farbe.length > 3 && parseFloat(el._fxSchmelz.farbe[3]) === 0) el._fxSchmelz.farbe = [255, 255, 255, 0.7];
        }
        const m = el._fxSchmelz.farbe;
        const farbe = `rgba(${m[0]},${m[1]},${m[2]},${Math.max(0.93, parseFloat(m[3] === undefined ? 1 : m[3]))})`;
        el.classList.add('fx-geschmolzen');
        nachVorne(el);
        const kiesel = opt.kiesel ? el.querySelector(`:scope > ${opt.kiesel}`) : null;
        if (kiesel) kiesel.classList.toggle('fx-kiesel-schief', grad > 0.4);

        // um 14 Uhr triefen die Kacheln richtig (Wunsch Jonas); die Nasen bleiben schmal,
        // damit die Schrift der Kachel darunter lesbar bleibt
        const extrem = staerke >= 3;
        // Platz bis zur Kachel darunter: Nasen und Ecken reichen höchstens knapp bis an
        // deren Rand, nie in ihre Schrift (Jonas: Lesbarkeit war grenzwertig)
        let luecke = (window.innerHeight - r.bottom) / VW;
        for (const o of document.querySelectorAll(opt.kaesten)) {
            if (o === el) continue;
            const q = o.getBoundingClientRect();
            if (q.right < r.left + 4 || q.left > r.right - 4) continue;
            const dy = (q.top - r.bottom) / VW;
            if (dy > -0.2 && dy < luecke) luecke = dy;
        }
        const grenze = Math.max(0.3, luecke + 0.25);
        const sack = Math.min((extrem ? 1.45 : 1.05) * grad, grenze * 0.8);   // so weit sacken die unteren Ecken ab
        const bauch = (extrem ? 0.5 : 0.38) * grad;                           // Wölbung der Seiten
        const lmax = Math.min((extrem ? 4.8 : 4.0) * grad, grenze);           // längste Tropfnase
        // Oberkante: sackt in flachen Mulden etwas ein (links bleibt Platz für den Kiesel)
        const oben = Math.min(0.28, (extrem ? 0.28 : 0.22) * grad);
        const rand = 1.3;                             // Platz links/rechts im SVG
        const w = wVw, h = hVw, ro = 0.7;
        const breite = w + 2 * rand, hoehe = h + lmax + 1.5;
        const X = (x) => (x + rand).toFixed(2);
        // Tropfnasen entlang der Unterkante (links frei lassen für den Kiesel des nächsten Kastens)
        const n = Math.max(3, Math.round(w / (extrem ? 2.0 : 2.4)));
        const nasen = [];
        for (let i = 0; i < n; i++) {
            const x = 1.6 + (w - 2.6) * (i + zuf(0.2, 0.8)) / n;
            nasen.push({x: x, b: zuf(0.6, 1.4), l: Math.max(0.05, zuf(0.4, 1) * lmax)});
        }
        nasen.sort((p, q) => q.x - p.x);   // von rechts nach links
        let d = `M ${X(0)} ${ro} Q ${X(0)} 0 ${X(ro)} 0 `;
        const frei = Math.min(3.5, w * 0.3);
        d += `L ${X(frei)} 0 `;
        const mulden = Math.max(2, Math.round((w - frei) / 6));
        for (let i = 0; i < mulden; i++) {
            const x0 = frei + (w - ro - frei) * i / mulden, x1 = frei + (w - ro - frei) * (i + 1) / mulden;
            d += `Q ${X((x0 + x1) / 2 + zuf(-0.6, 0.6))} ${(2 * oben * zuf(0.55, 1)).toFixed(2)} ${X(x1)} 0 `;
        }
        d += `Q ${X(w)} 0 ${X(w)} ${ro} `;
        // rechte Seite: leicht nach außen gewölbt, unten abgesackt
        d += `C ${X(w + bauch)} ${(h * 0.45).toFixed(2)} ${X(w + bauch * 1.4)} ${(h * 0.85).toFixed(2)} ${X(w + bauch * 0.5)} ${(h + sack).toFixed(2)} `;
        d += `Q ${X(w - 0.2)} ${(h + sack + 0.35).toFixed(2)} ${X(w - 0.8)} ${(h + sack * 0.55).toFixed(2)} `;
        // Unterkante mit Tropfnasen
        for (const t of nasen) {
            const yRand = h + sack * 0.45 + zuf(-0.08, 0.12) * grad;
            d += `L ${X(t.x + t.b * 1.3)} ${yRand.toFixed(2)} `;
            d += `C ${X(t.x + t.b * 0.55)} ${yRand.toFixed(2)} ${X(t.x + t.b * 0.5)} ${(h + t.l * 0.55).toFixed(2)} ${X(t.x + t.b * 0.45)} ${(h + t.l - t.b * 0.45).toFixed(2)} `;
            d += `A ${(t.b * 0.45).toFixed(2)} ${(t.b * 0.45).toFixed(2)} 0 0 1 ${X(t.x - t.b * 0.45)} ${(h + t.l - t.b * 0.45).toFixed(2)} `;
            d += `C ${X(t.x - t.b * 0.5)} ${(h + t.l * 0.55).toFixed(2)} ${X(t.x - t.b * 0.55)} ${yRand.toFixed(2)} ${X(t.x - t.b * 1.3)} ${yRand.toFixed(2)} `;
        }
        // linke Seite: abgesackte Ecke, Wölbung zurück nach oben
        d += `L ${X(0.8)} ${(h + sack * 0.55).toFixed(2)} Q ${X(0.2)} ${(h + sack + 0.35).toFixed(2)} ${X(-bauch * 0.5)} ${(h + sack).toFixed(2)} `;
        d += `C ${X(-bauch * 1.4)} ${(h * 0.85).toFixed(2)} ${X(-bauch)} ${(h * 0.45).toFixed(2)} ${X(0)} ${ro} Z`;

        const form = svg('svg', {viewBox: `0 0 ${breite.toFixed(2)} ${hoehe.toFixed(2)}`, class: 'fx-deko fx-schmelzform'}, [
            svg('path', {d: d, fill: farbe}),
            // heller Glanz oben, wie eine weiche, warme Oberfläche
            svg('path', {d: `M ${X(0.9)} 0.35 L ${X(w - 0.9)} 0.35`, stroke: 'rgba(255,255,255,.7)', 'stroke-width': 0.12, 'stroke-linecap': 'round'}),
        ]);
        Object.assign(form.style, {left: `-${rand}vw`, top: '0', width: `${breite}vw`, height: `${hoehe}vw`,
            filter: 'drop-shadow(0 .15vw .25vw rgba(120,60,10,.28))'});
        // ab der Hälfte des Tages: an jeder Seite eine Bahn, die herunterläuft
        if (grad > 0.5) {
            const g2 = (grad - 0.5) / 0.5;
            for (const seite of [1, -1]) {
                const kante = seite > 0 ? w + bauch * 0.6 : -bauch * 0.6;
                const y0 = seite > 0 ? zuf(0.2, 0.45) * h : zuf(0.5, 0.65) * h;
                const breiteS = zuf(0.4, 0.6);
                const ende = y0 + (h - y0 + sack + 0.6 + 1.4) * g2 + 0.6;
                const aussen = kante + seite * breiteS;
                form.appendChild(svg('path', {
                    d: `M ${X(kante - seite * 0.2)} ${y0.toFixed(2)} C ${X(aussen)} ${(y0 + 0.4).toFixed(2)} ${X(aussen)} ${(ende - 0.8).toFixed(2)} ${X(kante + seite * breiteS * 0.6)} ${(ende - breiteS * 0.5).toFixed(2)} ` +
                       `A ${(breiteS * 0.5).toFixed(2)} ${(breiteS * 0.5).toFixed(2)} 0 0 ${seite > 0 ? 1 : 0} ${X(kante - seite * 0.1)} ${(ende - breiteS * 0.6).toFixed(2)} ` +
                       `C ${X(kante - seite * 0.25)} ${(ende - 1).toFixed(2)} ${X(kante - seite * 0.3)} ${(y0 + 0.8).toFixed(2)} ${X(kante - seite * 0.6)} ${(y0 + 0.3).toFixed(2)} Z`,
                    fill: farbe,
                }));
            }
        }
        el.insertBefore(form, el.firstChild);
        if (grad < 0.25) return;   // früh am Tag tropft es noch nicht

        // an einigen Nasen bewegt es sich: sie wachsen nach, ein Tropfen löst sich und fällt
        const tropfen = svg('svg', {viewBox: `0 0 ${breite.toFixed(2)} ${hoehe.toFixed(2)}`, class: 'fx-deko'});
        Object.assign(tropfen.style, {left: `-${rand}vw`, top: '0', width: `${breite}vw`, height: `${hoehe}vw`, overflow: 'visible'});
        for (const t of nasen) {
            if (zuf(0, 1) < 0.45) continue;
            const dauerT = zufall(6, 13), vers = -zufall(0, dauerT);
            const nase = svg('path', {
                d: `M ${X(t.x - t.b * 0.6)} ${(h + t.l * 0.4).toFixed(2)} C ${X(t.x - t.b * 0.45)} ${(h + t.l).toFixed(2)} ${X(t.x + t.b * 0.45)} ${(h + t.l).toFixed(2)} ${X(t.x + t.b * 0.6)} ${(h + t.l * 0.4).toFixed(2)} Z`,
                fill: farbe, class: 'fx-tropfnase',
            });
            nase.style.setProperty('--d', `${dauerT}s`);
            nase.style.setProperty('--v', `${vers}s`);
            tropfen.appendChild(nase);
            const tr = svg('ellipse', {cx: X(t.x), cy: (h + t.l * 0.5).toFixed(2), rx: (t.b * 0.32).toFixed(2), ry: (t.b * 0.4).toFixed(2), fill: farbe, class: 'fx-tropfen'});
            tr.style.setProperty('--d', `${dauerT}s`);
            tr.style.setProperty('--v', `${vers}s`);
            tr.style.setProperty('--l', `${(t.l * 0.55).toFixed(2)}px`);
            tropfen.appendChild(tr);
        }
        el.insertBefore(tropfen, form.nextSibling);
    }

    // ==================================================================
    // STURM: Die Kacheln sind mit Zeltleinen an Heringen festgespannt. Meist
    // ist es ruhig; ab und zu kommt eine Böe von links, dann zerren die Kacheln,
    // als wollten sie wegfliegen, die Leinen spannen sich, und ein Schwall
    // Blätter fliegt durchs Bild.

    function Sturm(staerke) {
        const linien = [];
        const blaetter = [];
        let boe = null;
        let naechsteBoe = dauer(zufall(10, 25), 2.5);
        let ruhend = [];   // Kästen im Ruhezustand (ohne Böen-Verschiebung gemessen)

        function neuesBlatt() {
            return {
                x: zufall(-30, -3) * VW, y: zufall(-5, 92) * H / 100,
                v: zufall(38, 70) * VW, r: zufall(0.75, 1.4) * VW,
                dreh: zufall(0, 6.28), vdreh: zufall(-7, 7), kipp: zufall(0, 6.28), vkipp: zufall(3, 9),
                art: Math.floor(Math.random() * 4), vorne: Math.random() < 0.18,
            };
        }
        // Stärke der Böe über die Zeit: schnell auf, kurz halten, abklingen
        function kraftBei(s, d) {
            if (s <= 0 || s >= d) return 0;
            const auf = 0.35, ab = 1.3;
            if (s < auf) return Math.sin(s / auf * Math.PI / 2);
            if (s < d - ab) return 1;
            return 0.5 + 0.5 * Math.cos((s - (d - ab)) / ab * Math.PI);
        }
        function boeStarten(t, ohneAbriss) {
            const d = zufall(2.6, 3.6) + staerke * 0.35;
            boe = {
                start: t, dauer: d,
                // die Böe läuft von links nach rechts über den Bildschirm
                kaesten: ruhend.map((k) => Object.assign({}, k, {
                    phase: zufall(0, 6.28), anteil: zufall(0.7, 1.15), verzug: zufall(0, 0.2) + (k.x / W) * 0.4,
                })),
            };
            // leere Kacheln (ohne Vertretungen) reißt die Böe aus den Heringen –
            // je Böe ein paar, sie fliegen davon und fehlen dann
            const leere = boe.kaesten.filter((k) => !weg.has(k.el) && istLeer(k.el));
            // Orange: alle 70–100 Sekunden eine Kachel, höchstens die Hälfte der leeren fehlt
            // gleichzeitig; Rot und Violett: alle 25–40 Sekunden, höchstens zwei Drittel.
            // (Vorschau: bei jeder Böe eine, gleiche Obergrenze)
            const fehlend = Array.from(weg.keys()).filter((el) => el.isConnected).length;
            const deckel = Math.max(1, Math.round((leere.length + fehlend) * (staerke >= 2 ? 2 / 3 : 1 / 2)));
            const anzahl = !ohneAbriss && t >= naechsterAbriss && fehlend < deckel ? 1 : 0;
            if (anzahl) naechsterAbriss = t + dauer(staerke >= 2 ? zufall(25, 40) : zufall(70, 100), 0);
            for (let i = 0; i < Math.min(leere.length, anzahl); i++) {
                const k = leere.splice(Math.floor(Math.random() * leere.length), 1)[0];
                k.abriss = t + k.verzug + zufall(0.45, 0.9);
            }
            for (let i = 0; i < [0, 10, 16, 24][staerke]; i++) blaetter.push(neuesBlatt());
            for (let i = 0; i < [0, 10, 14, 20][staerke]; i++) {
                linien.push({x: zufall(-40, -2) * VW, y: zufall(0, H), l: zufall(8, 20) * VW, v: zufall(90, 140) * VW, p: zufall(0, 6.28)});
            }
        }
        function istLeer(el) {
            return !el.querySelector('table tr');
        }
        // weggeflogene Kacheln: el → {k, start, l0, vx, vy, vr, fertig}
        const weg = new Map();
        // zurückgebrachte Kachel: Zustand der beiden Seile, bis das Kind sie erneuert hat
        // ('lose' altes Seil hängt noch, 'ab' wird abgezogen, 'weg', 'knoten' neues Seil wird
        // angeknüpft, 'fest' gespannt)
        const reparatur = new Map();
        // Schülertrupp: holt weggeflogene Kacheln zurück (eine nach der anderen).
        // Träger tragen die Kachel herein, sie schwebt hoch, die Arme gehen runter.
        // Das Hammerkind stellt an jedem Hering die Teleskopleiter auf, klettert
        // hoch, schlägt den Hering fest und klettert wieder runter. Dann gehen alle.
        let trupp = null;
        let naechsterAbriss = 0;
        // der Schülertrupp kommt bei Orange alle 60–80 s, bei Rot und Violett alle 40–55 s
        const truppAbstand = () => dauer(staerke >= 2 ? zufall(40, 55) : zufall(60, 80), zufall(10, 15));
        let truppAb = null;
        const TRAEGER_B = 10.5, KIND_B = 5;   // Breite in vw; Höhe = Breite · 100/105 bzw. · 2
        // Ein Einsatz dauert höchstens etwa 22 Sekunden (Jonas: 15 s war zu hektisch): der Trupp kommt
        // von der näheren Seite und läuft zügig; das Hammerkind steigt flink hoch, rutscht
        // an den Holmen herunter und schiebt die Leiter zum zweiten Hering. Je höher die
        // Kachel hängt, desto flinker steigt es.
        const EINSATZ_MAX = 31, LAUF = 12, SCHIEBEN = 8.8;   // s, vw/s, vw/s (19.11.: 20 % ruhiger; +5 s Seilarbeit)
        const SPROSSE = 1.5, SPROSSE_ERSTE = 0.75;           // vw, entlang der Leiter
        const glatt = (u) => { u = Math.max(0, Math.min(1, u)); return u * u * (3 - 2 * u); };

        // Leiter am Hering p: Spitze knapp unter dem Hering, Fuß etwas weiter rechts.
        // Das Kind steht rechts der Leiter (Blick nach links); seine Hüfte bleibt
        // 1,2 vw rechts vom Holm, die Füße stehen auf den Sprossen.
        function leiterGeometrie(p) {
            const boden = LAUF_BODEN - 0.2 * VW;
            const kh = KIND_B * 2 * VW;
            const lehne = 0.14 * (boden - p[1] - 1.0 * VW);
            // ganz rechts am Rand lehnt die Leiter spiegelverkehrt, das Kind steht dann links
            const seite = p[0] + 0.5 * VW + lehne + 4 * VW > W ? -1 : 1;
            const spitze = [p[0] + 0.5 * VW * seite, p[1] + 1.0 * VW];
            const fuss = [spitze[0] + lehne * seite, boden];
            const laenge = Math.hypot(fuss[0] - spitze[0], fuss[1] - spitze[1]);
            const winkel = Math.atan2(boden - spitze[1], spitze[0] - fuss[0]) * 180 / Math.PI;
            const ux = (spitze[0] - fuss[0]) / laenge, uy = (spitze[1] - fuss[1]) / laenge;
            const holmX = (y) => fuss[0] + (spitze[0] - fuss[0]) * (boden - y) / Math.max(1, boden - spitze[1]);
            const sprosse = (i) => [fuss[0] + ux * (SPROSSE_ERSTE + i * SPROSSE) * VW, fuss[1] + uy * (SPROSSE_ERSTE + i * SPROSSE) * VW];
            const anzahl = Math.max(0, Math.floor((laenge - 0.3 * VW - SPROSSE_ERSTE * VW) / (SPROSSE * VW)) + 1);
            const huefteX = (y) => holmX(y) + 1.2 * VW * seite;
            const stehY = boden - 3.2 * VW;          // Hüfte im Stehen (wie die gezeichneten Beine)
            const g = {boden, kh, seite, spitze, fuss, laenge, winkel, holmX, sprosse, anzahl, huefteX, stehY};
            // oben: der Hammerkopf (25 % der Kindhöhe) ist auf Höhe des Herings
            g.huefteOben = p[1] + (0.68 - 0.25) * kh;
            g.braucht = g.huefteOben < stehY - 0.5 * VW;   // ganz unten geht es ohne Leiter
            g.stufen = 0;
            if (g.braucht) while (g.stufen < anzahl && huefteNach(g, g.stufen) > g.huefteOben) g.stufen++;
            return g;
        }
        // auf welcher Sprosse steht Fuß a bzw. b nach n Schritten (-1 = Boden)?
        // Fuß a steigt bei den Schritten 1, 3, 5 …, Fuß b bei 2, 4, 6 …; jeder Fuß
        // nimmt dabei die übernächste Sprosse, die Hüfte steigt je Schritt eine Sprosse.
        function fussIndex(seite, n) {
            if (seite === 'a') return n < 1 ? -1 : (n % 2 ? n : n - 1) - 1;
            return n < 2 ? -1 : (n % 2 ? n - 1 : n) - 1;
        }
        // Knöchel auf der Sprosse: der Fußballen steht auf der Sprosse
        function fussOrt(g, i, seite) {
            if (i < 0) return [g.huefteX(g.stehY) + (seite === 'a' ? -0.1 : 0.1) * VW * g.seite, g.boden - 0.7 * VW];
            const sp = g.sprosse(i);
            return [sp[0] + 0.3 * VW * g.seite, sp[1] - 0.36 * VW];
        }
        function huefteNach(g, n) {
            const unten = Math.max(fussOrt(g, fussIndex('a', n), 'a')[1], fussOrt(g, fussIndex('b', n), 'b')[1]);
            return Math.min(g.stehY, unten - 2.35 * VW);
        }
        function kletterPose(g, c) {
            if (g.stufen === 0) return {hy: g.stehY, fa: fussOrt(g, -1, 'a'), fb: fussOrt(g, -1, 'b')};
            c = Math.max(0, Math.min(g.stufen, c));
            const j = Math.min(g.stufen, Math.floor(c) + 1);
            const u = c - (j - 1);
            const bewegt = j % 2 ? 'a' : 'b';
            const pose = {};
            for (const seite of ['a', 'b']) {
                const von = fussOrt(g, fussIndex(seite, j - 1), seite);
                if (seite !== bewegt) { pose['f' + seite] = von; continue; }
                // Fuß lösen, im Bogen etwas von der Leiter weg und auf die nächste Sprosse setzen
                const nach = fussOrt(g, fussIndex(seite, j), seite);
                const uf = glatt(u / 0.6);
                const bogen = Math.sin(uf * Math.PI);
                pose['f' + seite] = [von[0] + (nach[0] - von[0]) * uf + bogen * 0.45 * VW, von[1] + (nach[1] - von[1]) * uf - bogen * 0.35 * VW];
            }
            // erst steht der Fuß, dann drückt sich das Kind hoch
            const h0 = huefteNach(g, j - 1), h1 = huefteNach(g, j);
            pose.hy = h0 + (h1 - h0) * glatt((u - 0.3) / 0.7);
            return pose;
        }
        function rutschDauer(g) {
            const h = g.stehY - huefteNach(g, g.stufen);
            return Math.max(0.45, Math.min(1.1, Math.sqrt(2 * h / (90 * VW)) + 0.15));
        }
        // Herunterrutschen: Füße außen an den Holmen, Hand am Holm, schneller werdend
        function rutschPose(g, u) {
            const oben = huefteNach(g, g.stufen);
            const hy = oben + (g.stehY - oben) * u * u;
            const m = glatt((u - 0.7) / 0.3);
            const pose = {hy: hy};
            for (const [seite, ab] of [['a', 2.05], ['b', 2.3]]) {
                const y = Math.min(hy + ab * VW, g.boden - 0.7 * VW);
                const amHolm = [g.holmX(y) + 0.35 * VW * g.seite, y];
                const steh = fussOrt(g, -1, seite);
                pose['f' + seite] = [amHolm[0] + (steh[0] - amHolm[0]) * m, amHolm[1] + (steh[1] - amHolm[1]) * m];
            }
            const hyHand = hy - 3.1 * VW;
            pose.hand = [g.holmX(hyHand) + 0.15 * VW * g.seite, hyHand];
            return pose;
        }
        // die freie Hand greift die höchste Sprosse, die sie gut erreicht
        function griffOrt(g, hy) {
            const schulter = hy - 1.95 * VW;
            let i = 0;
            while (i + 1 < g.anzahl && g.sprosse(i + 1)[1] >= schulter - 1.5 * VW) i++;
            const sp = g.sprosse(i);
            return [sp[0] + 0.15 * VW * g.seite, sp[1]];
        }
        function standX(g, p) {
            return g.braucht ? g.huefteX(g.stehY) - 2.5 * VW : p[0] - KIND_B * VW * 0.18;
        }
        // Schritttakt so wählen, dass der ganze Einsatz in EINSATZ_MAX passt
        function kletterTakt(tr) {
            const [g1, g2] = tr.geo;
            if (!g1.braucht) return 0.2;
            const kb = KIND_B * VW;
            const s1 = standX(g1, tr.heringe[0]), s2 = standX(g2, tr.heringe[1]);
            const rein = Math.abs(tr.kx - s1) / (LAUF * VW);
            const raus = Math.min(s2 + kb, W - s2) / (LAUF * VW);
            const schieben = g1.seite === g2.seite ? Math.abs(g2.fuss[0] - g1.fuss[0]) / (SCHIEBEN * VW)
                : 1.1 + Math.abs(s2 - s1) / (LAUF * VW);
            const fest = rein + 0.6 + 2 * (0.75 + 2.6 + rutschDauer(g1)) + schieben + 0.5 + raus;
            return Math.max(0.21, Math.min(0.375, (EINSATZ_MAX - fest) / Math.max(1, 2 * g1.stufen)));
        }
        // Mit einer Chance von 1 zu 3 geht ein Einsatz mit Leiter schief: eine Böe weht das
        // Hammerkind von der Leiter, es schwebt am Fallschirm davon, die Leiter kippt um.
        function truppStarten(t, el, k) {
            const traeger = svgAusText(traegerSvg());
            const kind = svgAusText(hammerkindSvg());
            domV.appendChild(traeger);
            domV.appendChild(kind);
            const kachel = document.createElement('div');
            kachel.className = 'fx-kachel-getragen';
            const kiesel = el.querySelector(':scope > h3');
            const marke = document.createElement('b');
            marke.textContent = kiesel ? kiesel.textContent : '';
            kachel.appendChild(marke);
            kachel.style.width = `${k.w}px`;
            kachel.style.height = `${k.h}px`;
            domV.appendChild(kachel);
            const tb = TRAEGER_B * VW, kb = KIND_B * VW;
            const hy = heringY(k);
            // von der näheren Seite herein
            const vonRechts = k.x + k.w / 2 >= W / 2;
            const start = vonRechts ? W + 2 * VW : -tb - 2 * VW;
            const hRechts = [k.x + k.w + 0.85 * VW, hy], hLinks = [k.x - 0.85 * VW, hy];
            const q = (sel) => kind.querySelector(sel);
            trupp = {
                el: el, k: k, traeger: traeger, kind: kind, kachel: kachel, anfang: t,
                phase: 'rein', start: t, x: start, vonRechts: vonRechts, kachelDa: false,
                ziel: Math.max(VW, Math.min(W - tb - VW, k.x + k.w / 2 - tb * 0.5)),
                // das Hammerkind läuft hinter den Trägern; zuerst der Hering auf seiner Seite
                kx: vonRechts ? start + tb + VW : start - kb - VW, ky: 0,
                heringe: vonRechts ? [hRechts, hLinks] : [hLinks, hRechts], hering: 0,
                kphase: 'folgen', kstart: t, leiterWinkel: 0, leiterLaenge: 7 * VW, leiterDx: 0, schlaege: 0, hand: null,
                ik: {
                    a: {hose: q('.fx-ik-bein-a .fx-ik-hose'), schuh: q('.fx-ik-bein-a .fx-ik-schuh')},
                    b: {hose: q('.fx-ik-bein-b .fx-ik-hose'), schuh: q('.fx-ik-bein-b .fx-ik-schuh')},
                    arm: q('.fx-ik-arm path'), hand: q('.fx-ik-arm circle'),
                },
            };
            trupp.geo = trupp.heringe.map(leiterGeometrie);
            trupp.takt = kletterTakt(trupp);
            trupp.unfall = trupp.geo[0].braucht && Math.random() < 1 / 3;
        }
        function truppEnde() {
            if (!trupp) return;
            trupp.traeger.remove(); trupp.kind.remove(); trupp.kachel.remove();
            reparatur.delete(trupp.el);
            if (trupp.schirm) trupp.schirm.el.remove();
            trupp = null;
        }
        // Teleskopleiter: Fuß (x, y), Länge, Winkel (0 = waagerecht nach rechts, 90 = senkrecht)
        function leiterMalen(x, y, laenge, winkel, breite) {
            const w = winkel * Math.PI / 180;
            const dx = Math.cos(w), dy = -Math.sin(w);
            const b = (breite === undefined ? 0.32 : breite) * VW;
            const nx = -dy * b, ny = dx * b;
            const ueber = 0.16 * VW;   // Sprossen stehen in der Seitenansicht etwas über
            cxV.lineCap = 'round';
            cxV.strokeStyle = 'rgba(70,78,88,.95)';
            cxV.lineWidth = 0.22 * VW;
            cxV.beginPath();
            cxV.moveTo(x - nx, y - ny); cxV.lineTo(x - nx + dx * laenge, y - ny + dy * laenge);
            cxV.moveTo(x + nx, y + ny); cxV.lineTo(x + nx + dx * laenge, y + ny + dy * laenge);
            cxV.stroke();
            cxV.strokeStyle = 'rgba(190,200,210,1)';
            cxV.lineWidth = 0.1 * VW;
            cxV.stroke();
            cxV.strokeStyle = 'rgba(120,130,140,1)';
            cxV.lineWidth = 0.12 * VW;
            cxV.beginPath();
            const ux = -dy, uy = dx;
            for (let d = SPROSSE_ERSTE * VW; d < laenge - 0.2 * VW; d += SPROSSE * VW) {
                cxV.moveTo(x - nx - ux * ueber + dx * d, y - ny - uy * ueber + dy * d);
                cxV.lineTo(x + nx + ux * ueber + dx * d, y + ny + uy * ueber + dy * d);
            }
            cxV.stroke();
        }
        // zweigliedriges Glied (Hüfte–Knie–Knöchel, Schulter–Ellbogen–Hand), in SVG-Einheiten
        function ik2(hx, hy, ax, ay, a, b, waehle) {
            let dx = ax - hx, dy = ay - hy;
            let d = Math.hypot(dx, dy);
            const max = a + b - 0.01;
            if (d > max) { ax = hx + dx / d * max; ay = hy + dy / d * max; d = max; }
            d = Math.max(d, Math.abs(a - b) + 0.01);
            const w = Math.atan2(ay - hy, ax - hx);
            const alpha = Math.acos(Math.max(-1, Math.min(1, (a * a + d * d - b * b) / (2 * a * d))));
            const k1 = [hx + Math.cos(w + alpha) * a, hy + Math.sin(w + alpha) * a];
            const k2 = [hx + Math.cos(w - alpha) * a, hy + Math.sin(w - alpha) * a];
            return [waehle(k1, k2), [ax, ay]];
        }
        // Kind in Kletterhaltung: Hüfte (Welt), Knöchel a/b und Hand (Welt) → SVG
        function kindPose(tr, hx, hy, fa, fb, hand, spiegel) {
            const e = 0.1 * VW;                       // eine SVG-Einheit in px
            const fx = hx - 2.5 * VW, fy = hy - 6.8 * VW;
            const lokal = (pt) => { const lx = (pt[0] - fx) / e; return [spiegel ? 50 - lx : lx, (pt[1] - fy) / e]; };
            const zahl = (v) => v.toFixed(1);
            for (const [seite, f, dx] of [['a', fa, -1], ['b', fb, 1]]) {
                const [ax, ay] = lokal(f);
                // das Knie zeigt nach vorn zur Leiter (nach links)
                const [knie, k] = ik2(25 + dx, 68, ax, ay, 12.5, 12.5, (k1, k2) => (k1[0] <= k2[0] ? k1 : k2));
                const g = tr.ik[seite];
                g.hose.setAttribute('d', `M${25 + dx},68 L${zahl(knie[0])},${zahl(knie[1])} L${zahl(k[0])},${zahl(k[1])}`);
                const [x, y] = k;
                g.schuh.setAttribute('d', `M${zahl(x - 5)},${zahl(y - 1)} L${zahl(x + 2.6)},${zahl(y - 1)} L${zahl(x + 2.6)},${zahl(y + 3)} L${zahl(x - 5.5)},${zahl(y + 3)} Q${zahl(x - 6.5)},${zahl(y + 1)} ${zahl(x - 5)},${zahl(y - 1)} Z`);
            }
            const [hx2, hy2] = lokal(hand);
            // der Ellbogen hängt nach unten
            const [ell, h] = ik2(25.5, 48.5, hx2, hy2, 10, 10, (k1, k2) => (k1[1] >= k2[1] ? k1 : k2));
            tr.ik.arm.setAttribute('d', `M25.5,48.5 L${zahl(ell[0])},${zahl(ell[1])} L${zahl(h[0])},${zahl(h[1])}`);
            tr.ik.hand.setAttribute('cx', zahl(h[0]));
            tr.ik.hand.setAttribute('cy', zahl(h[1]));
            return [fx, fy];
        }
        function truppSchritt(dt, t) {
            const tr = trupp;
            const tb = TRAEGER_B * VW, th = tb * 100 / 105;
            const kb = KIND_B * VW, kh = kb * 2;
            const boden = LAUF_BODEN - 0.2 * VW;
            const lauf = LAUF * VW;
            const huepf = (an) => (an ? Math.abs(Math.sin(t * 10.1)) * -0.15 * VW : 0);
            // ---- Träger mit der Kachel: herein, hochheben, zur näheren Seite hinaus
            const m = 0.5;
            const getragenX = tr.x + tb * 0.08, getragenY = boden - th + th * 0.17 - tr.k.h * m;
            let kx = getragenX, ky = getragenY, km = m;
            let traegerRichtung = 0;
            if (tr.phase === 'rein') {
                traegerRichtung = tr.vonRechts ? -1 : 1;
                tr.x += traegerRichtung * lauf * dt;
                if ((traegerRichtung < 0 && tr.x <= tr.ziel) || (traegerRichtung > 0 && tr.x >= tr.ziel)) {
                    tr.x = tr.ziel; traegerRichtung = 0;
                    tr.phase = 'heben'; tr.start = t; tr.traeger.classList.remove('fx-geht');
                }
                kx = tr.x + tb * 0.08;
            } else if (tr.phase === 'heben') {
                const u = Math.min(1, (t - tr.start) / 1.2);
                const e = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
                kx = getragenX + (tr.k.x - getragenX) * e;
                ky = getragenY + (tr.k.y - getragenY) * e - Math.sin(u * Math.PI) * 2 * VW;
                km = m + (1 - m) * e;
                // die Kachel hat die Hände verlassen: Arme runter
                if (u > 0.15) tr.traeger.classList.add('fx-arme-runter');
                if (u >= 1) {
                    zurueckholen(tr.el);
                    reparatur.set(tr.el, {links: 'lose', rechts: 'lose', ab: 0, fort: 0});
                    tr.kachel.style.display = 'none';
                    tr.kachelDa = true;
                    tr.phase = 'raus';
                    tr.rausT = tr.x + tb / 2 < W / 2 ? -1 : 1;
                    tr.traeger.classList.add('fx-geht');
                }
            } else if (tr.phase === 'raus') {
                traegerRichtung = tr.rausT;
                tr.x += traegerRichtung * lauf * dt;
            }
            const traegerWeg = tr.phase === 'raus' && (tr.x < -tb - VW || tr.x > W + VW);
            tr.traeger.style.transform = `translate(${tr.x.toFixed(1)}px, ${(boden - th + huepf(traegerRichtung !== 0)).toFixed(1)}px)${traegerRichtung > 0 ? ' scale(-1, 1)' : ''}`;
            if (tr.phase === 'rein' || tr.phase === 'heben') {
                tr.kachel.style.transform = `translate(${kx.toFixed(1)}px, ${ky.toFixed(1)}px) scale(${km.toFixed(3)})`;
            }

            // ---- Hammerkind mit Teleskopleiter
            const p = tr.heringe[tr.hering];
            const g = tr.geo[tr.hering];
            const ks = t - tr.kstart;
            const weiter = (phase) => { tr.kphase = phase; tr.kstart = t; };
            let gehen = false, richtung = -1, pose = null;
            if (tr.kphase === 'folgen') {
                if (tr.vonRechts) tr.kx = Math.max(tr.x + tb + 0.5 * VW, tr.kx - lauf * dt);
                else tr.kx = Math.min(tr.x - kb - 0.5 * VW, tr.kx + lauf * dt);
                gehen = true; richtung = tr.vonRechts ? -1 : 1;
                if (tr.phase !== 'rein') weiter('hingehen');
            } else if (tr.kphase === 'hingehen') {
                const ziel = standX(g, p);
                richtung = Math.sign(ziel - tr.kx) || -1;
                tr.kx += richtung * lauf * dt; gehen = true;
                if ((richtung < 0 && tr.kx <= ziel) || (richtung > 0 && tr.kx >= ziel)) {
                    tr.kx = ziel; gehen = false; richtung = -1;
                    weiter(g.braucht ? 'aufstellen' : 'haemmern');
                }
            } else if (tr.kphase === 'aufstellen') {
                // Leiter von der Schulter nehmen, aufrichten und dabei ausfahren
                tr.leiterWinkel = g.winkel * glatt(ks / 0.35);
                tr.leiterLaenge = 7 * VW + (g.laenge - 7 * VW) * glatt((ks - 0.2) / 0.4);
                if (ks >= 0.6) weiter('hoch');
            } else if (tr.kphase === 'hoch') {
                // Sprosse für Sprosse, Füße abwechselnd
                pose = kletterPose(g, ks / tr.takt);
                if (ks / tr.takt >= g.stufen) weiter('haemmern');
            } else if (tr.kphase === 'haemmern') {
                if (g.braucht) pose = kletterPose(g, g.stufen);
                if (!tr.kachelDa) {
                    tr.kstart = t;    // die Kachel ist noch nicht oben: kurz warten
                } else {
                    // erst das alte Seil abziehen, dann das neue anknüpfen, dann hämmern
                    const seite = p[0] > tr.k.x + tr.k.w / 2 ? 'rechts' : 'links';
                    const rp = reparatur.get(tr.el) || {links: 'fest', rechts: 'fest'};
                    const ABZIEHEN = 1.0, KNUEPFEN = 1.6;
                    if (ks < ABZIEHEN) {
                        rp[seite] = 'ab'; rp.ab = ks / ABZIEHEN;
                        if (pose) pose.hand = [p[0] + Math.sin(ks * 14) * 0.25 * VW, p[1] - 0.2 * VW];
                    } else if (ks < ABZIEHEN + KNUEPFEN) {
                        rp[seite] = 'knoten'; rp.fort = (ks - ABZIEHEN) / KNUEPFEN;
                        if (pose) pose.hand = [p[0] + Math.sin(ks * 18) * 0.2 * VW, p[1] - 0.3 * VW + Math.cos(ks * 18) * 0.15 * VW];
                    } else {
                    rp[seite] = 'fest';
                    const kh2 = ks - ABZIEHEN - KNUEPFEN;
                    tr.kind.classList.add('fx-haemmert');
                    if (kh2 > 0.15 + tr.schlaege * 0.3 && tr.schlaege < 2) { tr.schlaege += 1; funkenStreuen(p[0], p[1], 4, 'weiss'); }
                    if (tr.unfall && g.braucht && tr.hering === 0 && kh2 > 0.4) {
                        // die Böe kommt (ohne weitere Kachel abzureißen) und weht das Kind herunter
                        if (boe) boeEnde();
                        boeStarten(t, true);
                        tr.kind.classList.remove('fx-haemmert', 'fx-ik');
                        tr.flug = {x: tr.kx, y: tr.fy, vx: 15 * VW, vy: -8 * VW, rot: 0, vr: 620};
                        tr.leiterFall = {start: t, w0: tr.leiterWinkel};
                        weiter('abgeweht');
                    }
                    if (kh2 > 0.75) {
                        tr.kind.classList.remove('fx-haemmert'); tr.schlaege = 0;
                        weiter(g.braucht ? 'rutschen' : 'naechster');
                    }
                    }
                }
            } else if (tr.kphase === 'rutschen') {
                const d = rutschDauer(g);
                pose = rutschPose(g, Math.min(1, ks / d));
                if (ks >= d) {
                    tr.kx = standX(g, p); tr.hand = null;
                    weiter(tr.hering === 0 && tr.geo[1].seite === g.seite ? 'schieben' : 'einfahren');
                }
            } else if (tr.kphase === 'schieben') {
                // die angelehnte Leiter seitlich zum zweiten Hering schieben
                const g2 = tr.geo[1];
                const weg = g2.fuss[0] - g.fuss[0];
                const u = Math.min(1, ks / Math.max(0.2, Math.abs(weg) / (SCHIEBEN * VW)));
                tr.leiterDx = weg * u;
                tr.kx = standX(g, p) + weg * u;
                gehen = u < 1; richtung = Math.sign(weg) || -1;
                if (u >= 1) { tr.hering = 1; tr.leiterDx = 0; tr.kx = standX(g2, tr.heringe[1]); gehen = false; richtung = -1; weiter('hoch'); }
            } else if (tr.kphase === 'naechster') {
                if (tr.hering === 0) { tr.hering = 1; weiter('hingehen'); } else { weiter('raus'); }
            } else if (tr.kphase === 'einfahren') {
                tr.leiterLaenge = g.laenge + (7 * VW - g.laenge) * glatt(ks / 0.3);
                tr.leiterWinkel = g.winkel * (1 - glatt((ks - 0.2) / 0.3));
                if (ks >= 0.5) {
                    tr.leiterWinkel = 0; tr.leiterLaenge = 7 * VW;
                    if (tr.hering === 0) { tr.hering = 1; weiter('hingehen'); } else weiter('raus');
                }
            } else if (tr.kphase === 'abgeweht') {
                const f = tr.flug;
                if (!tr.schirm) {
                    // wirbelt durch die Luft …
                    f.vy += 24 * VW * dt; f.vx *= Math.pow(0.7, dt);
                    f.x += f.vx * dt; f.y += f.vy * dt; f.rot += f.vr * dt;
                    tr.kind.style.transform = `translate(${f.x.toFixed(1)}px, ${f.y.toFixed(1)}px) rotate(${f.rot.toFixed(0)}deg)`;
                    if (ks >= 0.75) {
                        // … dann geht der Fallschirm auf
                        const gruppe = document.createElement('div');
                        gruppe.className = 'fx-fallschirm-gruppe';
                        gruppe.appendChild(svgAusText(fallschirmSvg()));
                        domV.appendChild(gruppe);
                        gruppe.appendChild(tr.kind);
                        tr.kind.style.transform = `translate(${2.5 * VW}px, ${7.5 * VW}px)`;
                        let r0 = ((f.rot % 360) + 540) % 360 - 180;
                        // Gruppe so setzen, dass das Kind genau dort bleibt, wo es gerade wirbelt:
                        // die Gruppe dreht sich um den Schirm (50 % | 8 %), das Kind hängt 11,1 vw darunter
                        const w0 = r0 * Math.PI / 180, arm = 11.1 * VW;
                        const mitte = [f.x + 2.5 * VW, f.y + 5 * VW];
                        const dreh = [mitte[0] + Math.sin(w0) * arm, mitte[1] - Math.cos(w0) * arm];
                        tr.schirm = {el: gruppe, tuch: gruppe.firstChild, x: dreh[0] - 5 * VW, y: dreh[1] - 1.4 * VW, vx: f.vx, vy: f.vy, r0: r0, start: t};
                        // sofort an die richtige Stelle, sonst springt das Kind ein Bild lang in die Ecke
                        gruppe.style.transform = `translate(${tr.schirm.x.toFixed(1)}px, ${tr.schirm.y.toFixed(1)}px) rotate(${r0.toFixed(1)}deg)`;
                        tr.schirm.tuch.style.transform = 'scale(0.15, 0.3)';
                    }
                } else {
                    const sc = tr.schirm, a = t - sc.start;
                    const auf = glatt(a / 0.45);
                    sc.tuch.style.transform = `scale(${(0.15 + 0.85 * auf).toFixed(3)}, ${(0.3 + 0.7 * auf).toFixed(3)})`;
                    // vom Wind seitlich davongetragen, langsam sinkend, pendelnd
                    sc.vx += (9 * VW - sc.vx) * Math.min(1, dt * 1.5);
                    sc.vy += ((sc.y > UNTEN - 19 * VW ? -0.5 : 2) * VW - sc.vy) * Math.min(1, dt * (a < 0.6 ? 6 : 2));
                    sc.x += sc.vx * dt; sc.y += sc.vy * dt;
                    // ruhig einpendeln (nicht schlagartig), dann leicht hin und her
                    const rot = sc.r0 * Math.exp(-a * 1.6) * Math.cos(a * 1.2) + Math.sin(a * 2.3) * 9 * Math.min(1, a / 2);
                    sc.el.style.transform = `translate(${sc.x.toFixed(1)}px, ${sc.y.toFixed(1)}px) rotate(${rot.toFixed(1)}deg)`;
                    const kindWeg = sc.x > W + VW || sc.x < -11 * VW || sc.y > H;
                    if ((kindWeg && traegerWeg) || t - tr.anfang > 45) { truppEnde(); truppAb = t + truppAbstand(); return; }
                }
            } else if (tr.kphase === 'raus') {
                if (tr.rausK === undefined) tr.rausK = tr.kx + kb / 2 < W / 2 ? -1 : 1;
                richtung = tr.rausK;
                tr.kx += richtung * lauf * dt; gehen = true;
                const kindWeg = tr.kx < -kb - VW || tr.kx > W + VW;
                if ((kindWeg && traegerWeg) || t - tr.anfang > 30) { truppEnde(); truppAb = t + truppAbstand(); return; }
            }
            tr.kind.classList.toggle('fx-geht', gehen);
            tr.kind.classList.toggle('fx-ik', !!pose);
            if (pose) {
                const hx = g.huefteX(pose.hy);
                // die Hand greift nach, sobald eine höhere Sprosse in Reichweite ist
                const ziel = pose.hand || griffOrt(g, pose.hy);
                if (!tr.hand || pose.hand) tr.hand = ziel.slice();
                else { const r = Math.min(1, dt * 22); tr.hand[0] += (ziel[0] - tr.hand[0]) * r; tr.hand[1] += (ziel[1] - tr.hand[1]) * r; }
                const [fx, fy] = kindPose(tr, hx, pose.hy, pose.fa, pose.fb, tr.hand, g.seite < 0);
                tr.kx = fx; tr.fy = fy;
                tr.kind.style.transform = `translate(${fx.toFixed(1)}px, ${fy.toFixed(1)}px)${g.seite < 0 ? ' scale(-1, 1)' : ''}`;
            } else if (tr.kphase !== 'abgeweht') {
                // beim Gehen in Laufrichtung, bei der Arbeit zur Leiter hin
                const arbeit = ['aufstellen', 'haemmern', 'einfahren'].indexOf(tr.kphase) >= 0 && g.braucht;
                const spiegeln = gehen ? richtung > 0 : arbeit && g.seite < 0;
                tr.kind.style.transform = `translate(${tr.kx.toFixed(1)}px, ${(boden - kh + huepf(gehen)).toFixed(1)}px)${spiegeln ? ' scale(-1, 1)' : ''}`;
            }
            // Leiter: beim Laufen waagerecht auf der Schulter, sonst am Hering angelehnt
            const getragen = ['folgen', 'hingehen', 'raus', 'naechster'].indexOf(tr.kphase) >= 0;
            if (getragen) {
                leiterMalen(tr.kx + kb * 0.5 - 3.5 * VW, boden - kh * 0.52 + huepf(gehen), 7 * VW, 0, 0.13);
            } else if (tr.leiterFall) {
                const lf = tr.leiterFall, a = t - lf.start;
                if (a < 0.9) {
                    const u = a / 0.9;
                    leiterMalen(g.fuss[0], g.fuss[1], tr.leiterLaenge, lf.w0 * (1 - u * u), 0.13);
                } else if (a < 1.9) {
                    // flach aufgeschlagen, kurz nachgefedert, dann nach unten aus dem Bild
                    const b = a - 0.9;
                    const feder = b < 0.25 ? Math.sin(b / 0.25 * Math.PI) * 4 : 0;
                    const sinken = b > 0.35 ? Math.pow(b - 0.35, 2) * 30 * VW : 0;
                    cxV.globalAlpha = Math.max(0, 1 - Math.max(0, b - 0.6) / 0.4);
                    leiterMalen(g.fuss[0], g.fuss[1] + sinken, tr.leiterLaenge, feder, 0.13);
                    cxV.globalAlpha = 1;
                }
            } else if (g.braucht) {
                leiterMalen(g.fuss[0] + tr.leiterDx, g.fuss[1], tr.leiterLaenge, tr.leiterWinkel, 0.13);
            }
        }

        function zurueckholen(el) {
            el.style.transition = 'opacity 1.2s';
            el.style.opacity = '0';
            el.style.visibility = '';
            el.style.transform = '';
            el.style.zIndex = '';
            requestAnimationFrame(() => { el.style.opacity = ''; });
            setTimeout(() => { el.style.transition = ''; }, 1400);
            weg.delete(el);
        }
        function boeEnde() {
            for (const k of boe.kaesten) if (!weg.has(k.el)) k.el.style.transform = '';
            boe = null;
            kaestenZeit = 0; // gleich neu messen, ohne Verschiebung
        }
        // Verschiebung einer Kachel in der Böe: nach rechts weg, nach oben,
        // gedreht, dazu schnelles Flattern
        function lage(k, t) {
            if (!boe) return {dx: 0, dy: 0, rot: 0, kraft: 0};
            const kraft = kraftBei(t - boe.start - k.verzug, boe.dauer) * k.anteil;
            return {
                kraft: kraft,
                dx: kraft * (0.45 + 0.13 * Math.sin(t * 23 + k.phase)) * VW,
                dy: -kraft * (0.3 + 0.22 * Math.abs(Math.sin(t * 17 + k.phase))) * VW,
                rot: kraft * (0.9 + 0.55 * Math.sin(t * 19 + k.phase)),
            };
        }
        // Punkt (px, py) der Kachel nach Drehung um ihre Mitte und Verschiebung
        function bewegt(k, l, px, py) {
            const cx = k.x + k.w / 2, cy = k.y + k.h / 2;
            const w = l.rot * Math.PI / 180;
            const c = Math.cos(w), sn = Math.sin(w);
            return [cx + (px - cx) * c - (py - cy) * sn + l.dx, cy + (px - cx) * sn + (py - cy) * c + l.dy];
        }
        function leine(x1, y1, x2, y2, kraft, t, phase) {
            // durchhängend in Ruhe, straff (und leicht vibrierend) in der Böe
            // das Seil hängt nach unten durch (Schwerkraft); straff fast gerade
            const ruhe = 1 - Math.min(1, kraft * 1.3);
            const sag = (0.35 * ruhe + kraft * 0.05 * Math.sin(t * 45 + phase)) * VW;
            // auch zwischen den Böen schwingt das Seil dauernd ein wenig im Wind
            const ph = phase * 0.013;
            const wackeln = ruhe * (Math.sin(t * 2.3 + ph) * 0.6 + Math.sin(t * 3.9 + ph * 1.7) * 0.4);
            const qx = (x1 + x2) / 2 + sag * 0.5 + wackeln * 0.3 * VW;
            const qy = (y1 + y2) / 2 + sag + (Math.sin(t * 1.6 + ph * 2.3) * 0.07 + wackeln * 0.05) * VW * ruhe;
            cxV.lineCap = 'round';
            cxV.setLineDash([]);
            cxV.strokeStyle = 'rgba(92,66,34,.9)';
            cxV.lineWidth = 0.17 * VW;
            cxV.beginPath(); cxV.moveTo(x1, y1); cxV.quadraticCurveTo(qx, qy, x2, y2); cxV.stroke();
            // gedrehtes Seil: helle Strähnen
            cxV.strokeStyle = 'rgba(222,190,132,.95)';
            cxV.lineWidth = 0.08 * VW;
            cxV.setLineDash([0.22 * VW, 0.14 * VW]);
            cxV.beginPath(); cxV.moveTo(x1, y1); cxV.quadraticCurveTo(qx, qy, x2, y2); cxV.stroke();
            cxV.setLineDash([]);
        }
        // lose Leine: hängt nur noch am Hering; in Ruhe liegt sie, in der Böe
        // flattert sie nach rechts weg, am Ende ausgefranst
        function loseLeine(px, py, laenge, wind, t, phase) {
            const ruheX = px + laenge * 0.55, ruheY = py + 0.15 * VW;
            const tempo = 5 + 7 * wind;   // ruhiger Wind: langsames Flattern, Böe: schnelles Schlagen
            const windX = px + laenge * 0.95, windY = py - laenge * 0.12 + Math.sin(t * tempo + phase) * 0.6 * VW;
            const ex = ruheX + (windX - ruheX) * wind, ey = ruheY + (windY - ruheY) * wind;
            const qx = (px + ex) / 2 + Math.sin(t * tempo * 1.4 + phase) * 0.4 * VW * wind;
            const qy = (py + ey) / 2 + (0.5 - 0.9 * wind) * VW + Math.cos(t * tempo * 1.2 + phase) * 0.35 * VW * wind;
            cxV.lineCap = 'round';
            cxV.strokeStyle = 'rgba(92,66,34,.9)';
            cxV.lineWidth = 0.17 * VW;
            cxV.beginPath(); cxV.moveTo(px, py); cxV.quadraticCurveTo(qx, qy, ex, ey); cxV.stroke();
            cxV.strokeStyle = 'rgba(222,190,132,.95)';
            cxV.lineWidth = 0.08 * VW;
            cxV.setLineDash([0.22 * VW, 0.14 * VW]);
            cxV.beginPath(); cxV.moveTo(px, py); cxV.quadraticCurveTo(qx, qy, ex, ey); cxV.stroke();
            cxV.setLineDash([]);
            // ausgefranstes Ende
            cxV.strokeStyle = 'rgba(160,125,75,.9)';
            cxV.lineWidth = 0.05 * VW;
            cxV.beginPath();
            for (const w of [-0.6, 0, 0.6]) {
                cxV.moveTo(ex, ey);
                cxV.lineTo(ex + Math.cos(w + wind * 0.2) * 0.4 * VW, ey + Math.sin(w + 0.4) * 0.4 * VW);
            }
            cxV.stroke();
        }
        // Wo die Heringe einer Kachel stecken: in der Lücke über der Kachel darunter –
        // gibt es darunter keine Kachel (unterste Reihe), unten im Boden (über dem Schriftband)
        function heringY(k) {
            const boden = UNTEN - 0.35 * VW;
            const darunter = kaesten.some((o) => o.el !== k.el && o.x < k.x + k.w - 4 && o.x + o.w > k.x + 4 && o.y > k.y + k.h - 2 && o.y < boden);
            return darunter ? Math.min(k.y + k.h + 0.45 * VW, boden) : boden;
        }
        function hering(x, y, aussen) {
            // am Boden: kleines Häufchen Erde, der Schaft verschwindet im Boden
            if (y >= UNTEN - 0.4 * VW) {
                cxV.fillStyle = 'rgba(110,80,50,.85)';
                cxV.beginPath(); cxV.ellipse(x + aussen * 0.12 * VW, UNTEN - 0.02 * VW, 0.55 * VW, 0.2 * VW, 0, Math.PI, 0); cxV.fill();
            }
            // kleiner Zelthering: Haken oben, schräg „im Boden“
            cxV.strokeStyle = 'rgba(80,86,92,.95)';
            cxV.lineWidth = 0.13 * VW;
            cxV.lineCap = 'round';
            cxV.beginPath();
            cxV.moveTo(x - aussen * 0.18 * VW, y - 0.12 * VW);
            cxV.quadraticCurveTo(x, y - 0.28 * VW, x + aussen * 0.08 * VW, y);
            cxV.lineTo(x + aussen * 0.3 * VW, y + 0.75 * VW);
            cxV.stroke();
        }
        function oese(x, y) {
            cxV.fillStyle = 'rgba(200,204,208,1)';
            cxV.strokeStyle = 'rgba(90,96,102,1)';
            cxV.lineWidth = 0.06 * VW;
            cxV.beginPath(); cxV.arc(x, y, 0.17 * VW, 0, 6.283); cxV.fill(); cxV.stroke();
            cxV.fillStyle = 'rgba(60,64,68,1)';
            cxV.beginPath(); cxV.arc(x, y, 0.07 * VW, 0, 6.283); cxV.fill();
        }

        return {
            stop() {
                if (boe) boeEnde();
                truppEnde();
                // nach dem Sturm sind alle Kacheln wieder da
                for (const el of Array.from(weg.keys())) zurueckholen(el);
            },
            schritt(dt, t) {
                if (!boe) ruhend = kaesten.slice();
                // bekommt eine weggeflogene Kachel Inhalt, kommt sie sofort zurück
                for (const [el, f] of weg) if (!istLeer(el) || !el.isConnected) { if (el.isConnected) zurueckholen(el); else weg.delete(el); }
                // solange der Schülertrupp arbeitet, wartet die nächste Böe
                if (!trupp) naechsteBoe -= dt;
                if (!boe && naechsteBoe <= 0 && ruhend.length) {
                    boeStarten(t);
                    // alle 20–30 Sekunden eine Böe (Wunsch Jonas, 19.11.)
                    naechsteBoe = dauer(zufall(20, 30), zufall(7, 10));
                }
                const liste = boe ? boe.kaesten : ruhend;
                let gesamt = 0;
                for (const k of liste) {
                    const l = lage(k, t);
                    gesamt = Math.max(gesamt, l.kraft);
                    const ay = k.y + k.h * 0.3;
                    const hy = heringY(k);
                    // Abriss: ab jetzt fliegt die Kachel davon
                    if (k.abriss && t >= k.abriss && !weg.has(k.el) && istLeer(k.el)) {
                        weg.set(k.el, {start: t, l0: l, vx: zufall(28, 40) * VW, vy: -zufall(6, 12) * VW, vr: zufall(70, 160), fertig: false});
                        k.el.style.zIndex = '58';   // fliegt über die anderen Kacheln hinweg, unter der vorderen Ebene
                        k.abriss = null;
                    }
                    const f = weg.get(k.el);
                    if (f) {
                        if (!f.fertig) {
                            const s = t - f.start;
                            const dxF = f.l0.dx + f.vx * s + 18 * VW * s * s;
                            const dyF = f.l0.dy + f.vy * s + 4 * VW * s * s * Math.sin(s * 3);
                            const rot = f.l0.rot + f.vr * s;
                            k.el.style.transform = `translate(${dxF.toFixed(1)}px, ${dyF.toFixed(1)}px) rotate(${rot.toFixed(1)}deg)`;
                            if (k.x + dxF > W + 2 * VW) {
                                f.fertig = true;
                                // nach ein paar Minuten bringt der Schülertrupp sie zurück
                                f.rueckholen = t + dauer(zufall(35, 70), zufall(4, 7));
                                k.el.style.visibility = 'hidden';
                                k.el.style.transform = '';
                                k.el.style.zIndex = '';
                            }
                        }
                        // die beiden Leinen bleiben am Hering zurück und flattern dauernd im
                        // Wind; in der Böe schlagen sie wild
                        const boeKraft = boe ? kraftBei(t - boe.start - (k.x / W) * 0.4, boe.dauer) : 0;
                        const wind = 0.45 + 0.55 * boeKraft;
                        const laenge = Math.hypot(0.85 * VW, hy - ay);
                        loseLeine(k.x - 0.85 * VW, hy, laenge, wind, t, k.x);
                        loseLeine(k.x + k.w + 0.85 * VW, hy, laenge, wind, t, k.y);
                        hering(k.x - 0.85 * VW, hy, -1);
                        hering(k.x + k.w + 0.85 * VW, hy, 1);
                        continue;
                    }
                    if (boe) k.el.style.transform = l.kraft > 0.001 ? `translate(${l.dx.toFixed(1)}px, ${l.dy.toFixed(1)}px) rotate(${l.rot.toFixed(2)}deg)` : '';
                    // zwei Leinen je Kachel: von der Seitenkante schräg nach unten zu einem Hering in der Lücke
                    const links = bewegt(k, l, k.x, ay);
                    const rechts = bewegt(k, l, k.x + k.w, ay);
                    const rp = reparatur.get(k.el);
                    for (const [seite, oe, px, ph] of [['links', links, k.x - 0.85 * VW, k.x], ['rechts', rechts, k.x + k.w + 0.85 * VW, k.y]]) {
                        const st = rp ? rp[seite] : 'fest';
                        if (st === 'fest') {
                            leine(oe[0], oe[1], px, hy, l.kraft, t, ph);
                        } else if (st === 'lose' || st === 'ab') {
                            // das alte, abgerissene Seil hängt noch – beim Abziehen fällt es herunter
                            const ab = st === 'ab' ? rp.ab : 0;
                            cxV.globalAlpha = Math.max(0, 1 - ab * ab);
                            loseLeine(px, hy + ab * ab * 3 * VW, Math.hypot(0.85 * VW, hy - ay), 0.45, t, ph);
                            cxV.globalAlpha = 1;
                        } else if (st === 'knoten') {
                            // das neue Seil wächst vom Hering bis zur Öse der Kachel
                            const f = rp.fort;
                            const ex = px + (oe[0] - px) * f, ey = hy + (oe[1] - hy) * f + Math.sin(t * 9) * 0.15 * VW * (1 - f);
                            leine(ex, ey, px, hy, 0, t, ph);
                        }
                    }
                    hering(k.x - 0.85 * VW, hy, -1);
                    hering(k.x + k.w + 0.85 * VW, hy, 1);
                    oese(links[0], links[1]);
                    oese(rechts[0], rechts[1]);
                }
                if (boe && t - boe.start > boe.dauer + 0.7) boeEnde();
                // Schülertrupp: nur zwischen den Böen losschicken, eine Kachel nach der anderen
                if (truppAb === null) truppAb = t + (vorschau ? 0 : truppAbstand());
                if (!trupp && !boe && t >= truppAb) {
                    for (const [el, f] of weg) {
                        if (f.fertig && f.rueckholen && t >= f.rueckholen) {
                            const k = ruhend.find((r) => r.el === el);
                            if (k) { truppStarten(t, el, k); break; }
                        }
                    }
                }
                if (trupp) truppSchritt(dt, t);
                // Windlinien und Blätter nur mit der Böe
                cxH.lineCap = 'round';
                cxH.lineWidth = 0.12 * VW;
                const f = opt.dunkel ? '220,230,245' : '90,110,140';
                for (let i = linien.length - 1; i >= 0; i--) {
                    const ln = linien[i];
                    ln.x += ln.v * dt;
                    if (ln.x - ln.l > W) { linien.splice(i, 1); continue; }
                    const g = cxH.createLinearGradient(ln.x - ln.l, 0, ln.x, 0);
                    g.addColorStop(0, `rgba(${f},0)`);
                    g.addColorStop(0.7, `rgba(${f},.5)`);
                    g.addColorStop(1, `rgba(${f},0)`);
                    cxH.strokeStyle = g;
                    cxH.beginPath();
                    cxH.moveTo(ln.x - ln.l, ln.y);
                    cxH.bezierCurveTo(ln.x - ln.l * 0.6, ln.y - Math.sin(t * 2 + ln.p) * 1.2 * VW, ln.x - ln.l * 0.3, ln.y + Math.sin(t * 2 + ln.p) * 1.2 * VW, ln.x, ln.y);
                    cxH.stroke();
                }
                for (let i = blaetter.length - 1; i >= 0; i--) {
                    const bl = blaetter[i];
                    bl.x += bl.v * dt;
                    bl.y += (Math.sin(t * 1.5 + bl.kipp) * 6 + 2) * VW * dt;
                    bl.dreh += bl.vdreh * dt; bl.kipp += bl.vkipp * dt;
                    if (bl.x > W + 3 * VW || bl.y > H + 3 * VW) { blaetter.splice(i, 1); continue; }
                    const img = sprite(`blatt${bl.art}`, () => blattSprite(bl.art));
                    const ctx = bl.vorne ? cxV : cxH;
                    const r = bl.r * (bl.vorne ? 1.7 : 1);
                    ctx.save();
                    ctx.translate(bl.x, bl.y);
                    ctx.rotate(bl.dreh);
                    ctx.scale(1, Math.max(0.12, Math.abs(Math.cos(bl.kipp))));
                    ctx.globalAlpha = bl.vorne ? 0.95 : 0.85;
                    ctx.drawImage(img, -r, -r, 2 * r, 2 * r);
                    ctx.restore();
                }
            },
        };
    }

    function blattSprite(art) {
        const s = Math.ceil(2 * VW * DPR);
        const c = leinwand(s, s);
        const g = c.getContext('2d');
        const farben = [['#d9822b', '#a4501a'], ['#c8a13a', '#8c6b1c'], ['#b5462f', '#7a2a1c'], ['#8a9a3a', '#5b6a22']][art];
        g.translate(s / 2, s / 2);
        g.rotate(-0.6);
        const r = s * 0.42;
        const f = g.createLinearGradient(-r, -r, r, r);
        f.addColorStop(0, farben[0]);
        f.addColorStop(1, farben[1]);
        g.fillStyle = f;
        g.beginPath();
        if (art === 1) {
            g.ellipse(0, 0, r, r * 0.45, 0, 0, 6.283);
        } else {
            g.moveTo(-r, 0);
            g.bezierCurveTo(-r * 0.4, -r * 0.75, r * 0.5, -r * 0.6, r, 0);
            g.bezierCurveTo(r * 0.5, r * 0.6, -r * 0.4, r * 0.75, -r, 0);
        }
        g.fill();
        g.strokeStyle = 'rgba(70,35,10,.55)';
        g.lineWidth = Math.max(1, s * 0.03);
        g.beginPath();
        g.moveTo(-r * 1.15, 0); g.lineTo(r * 0.85, 0);
        for (const x of [-0.4, 0, 0.4]) { g.moveTo(x * r, 0); g.lineTo((x + 0.25) * r, -r * 0.3); g.moveTo(x * r, 0); g.lineTo((x + 0.25) * r, r * 0.3); }
        g.stroke();
        return c;
    }

    // ==================================================================
    // FROST / GLATTEIS: Eiszapfen, vereiste Ränder, Eisblumen in den Ecken

    function Frost(staerke) {
        const laeufer = [];
        let naechsteGruppe = vorschau ? 2 : zufall(40, 150);
        let eisblumen = null;
        let deckkraft = 0;
        const zapfen = setInterval(() => dekorieren('frost', eiszapfen), 2000);
        dekorieren('frost', eiszapfen);
        function eisblumenZeichnen() {
            const c = leinwand(W * DPR, H * DPR);
            const g = c.getContext('2d');
            g.setTransform(DPR, 0, 0, DPR, 0, 0);
            g.lineCap = 'round';
            if (!opt.dunkel) {
                // auf hellem Grund braucht das Eis einen Hauch Blau, sonst sieht man es nicht
                g.shadowColor = 'rgba(70,110,160,.75)';
                g.shadowBlur = 2;
            }
            function zweig(x, y, w, l, tiefe) {
                if (tiefe <= 0 || l < 0.25 * VW) return;
                const x2 = x + Math.cos(w) * l, y2 = y + Math.sin(w) * l;
                g.lineWidth = Math.max(0.5, tiefe * 0.045 * VW);
                g.strokeStyle = `rgba(255,255,255,${0.18 + tiefe * 0.08})`;
                g.beginPath(); g.moveTo(x, y); g.lineTo(x2, y2); g.stroke();
                const n = 3;
                for (let i = 1; i <= n; i++) {
                    const px = x + (x2 - x) * i / (n + 1), py = y + (y2 - y) * i / (n + 1);
                    const ll = l * 0.42 * (1 - i / (n + 2));
                    zweig(px, py, w - 1.05, ll, tiefe - 1);
                    zweig(px, py, w + 1.05, ll, tiefe - 1);
                }
                zweig(x2, y2, w + zufall(-0.35, 0.35), l * 0.62, tiefe - 1);
            }
            const ecken = [[0, 0, 0.6], [W, 0, Math.PI - 0.6], [0, H, -0.6], [W, H, Math.PI + 0.6]];
            for (const e of ecken) {
                for (let i = 0; i < 4 + staerke; i++) {
                    zweig(e[0], e[1], e[2] + zufall(-0.75, 0.75), zufall(4, 7 + staerke * 1.5) * VW, 4);
                }
            }
            return c;
        }
        return {
            stop() { clearInterval(zapfen); for (const l of laeufer) l.el.remove(); dekoEntfernen(); },
            groesse() { eisblumen = null; },
            schritt(dt, t) {
                // alle 4 bis 5 Minuten gleiten ein paar Eisläufer unten durchs Bild
                naechsteGruppe -= dt;
                if (laeufer.length === 0 && naechsteGruppe <= 0) {
                    naechsteGruppe = dauer(zufall(4, 5) * 60, 24);
                    const n = 2 + Math.floor(Math.random() * 2);
                    for (let i = 0; i < n; i++) {
                        const el = svgAusText(eislaeuferSvg(i));
                        el.style.width = `${(6 - i * 0.6).toFixed(1)}vw`;
                        domV.appendChild(el);
                        laeufer.push({el: el, start: t, versatz: i * 8 + zufall(0, 3), dauer: 17 + i * 1.5, b: 6 - i * 0.6, p: zufall(0, 1), takt: zufall(1.25, 1.5)});
                    }
                }
                for (let i = laeufer.length - 1; i >= 0; i--) {
                    const l = laeufer[i];
                    const u = (t - l.start) / l.dauer;
                    if (u >= 1) { l.el.remove(); laeufer.splice(i, 1); continue; }
                    const breite = l.b * VW, hoehe = breite * 100 / 70;
                    // Schrittphase: je Bein ein Abstoß pro Takt; nach jedem Abstoß kurz schneller
                    const phase = ((t - l.start) / l.takt + l.p) % 1;
                    eislaufPose(l.el, phase);
                    const x = -breite - l.versatz * VW + (W + breite + (l.versatz + 2) * VW) * u + Math.sin(phase * Math.PI * 4) * 0.3 * VW;
                    const y = LAUF_BODEN - hoehe * 0.98 - 0.1 * VW;
                    l.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)`;
                }
                if (!eisblumen) eisblumen = eisblumenZeichnen();
                deckkraft = Math.min(1, deckkraft + dt / dauer(40, 3));
                cxV.globalAlpha = 0.8 * deckkraft * (opt.dunkel ? 0.8 : 1);
                cxV.drawImage(eisblumen, 0, 0, W, H);
                cxV.globalAlpha = 1;
            },
        };
    }

    const EISLAUF_FARBEN = [
        ['#d6453d', '#f2c14e', '#2f4a6d'], ['#3a74c9', '#ffffff', '#3b3b46'], ['#2f9c88', '#f28fb1', '#273a4a'],
    ];
    // Eisläufer in Seitenansicht, Blick nach rechts (viewBox 70 × 100, Eis bei y = 96):
    // Oberkörper nach vorn geneigt, Hüfte bei (30|58). Beine (Knie gebeugt) und Arme
    // setzt eislaufPose() in jedem Bild.
    const EIS_HUEFTE = [30, 58], EIS_SCHULTER = [41, 34], EIS_OBEN = 21, EIS_UNTEN = 20, EIS_ARM = [11, 10];
    function eislaeuferSvg(nr) {
        const [jacke, akzent, hose] = EISLAUF_FARBEN[nr % EISLAUF_FARBEN.length];
        const bein = (n, dunkler) => `<g class="fx-eis-bein-${n}"${dunkler ? ' opacity=".8"' : ''}>
            <path class="fx-eis-hose" d="" stroke="${hose}" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
            <g class="fx-eis-schuh"><path d="M-3,-3 L6,-3 Q9,-3 9,0.5 L9,2 L-3.5,2 Z" fill="#2b2b2b"/>
                <path d="M-6,5 L12,5 Q14.5,5 14.5,2.6" stroke="#c9d3dc" stroke-width="1.6" fill="none" stroke-linecap="round"/>
                <path d="M-1,2 L-1,5 M6,2 L6,5" stroke="#9aa6b0" stroke-width="1.2"/></g></g>`;
        const arm = (n, dunkler) => `<g class="fx-eis-arm-${n}"${dunkler ? ' opacity=".8"' : ''}>
            <path class="fx-eis-aermel" d="" stroke="${jacke}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
            <circle class="fx-eis-hand" r="2.6" fill="${akzent}"/></g>`;
        return `<svg class="fx-eislaeufer" viewBox="0 0 70 100" xmlns="${NS}">
            ${arm('b', true)}
            ${bein('b', true)}
            <path class="fx-schal" d="M39,29 C32,26 22,25 12,28 C16,30 23,30 29,31 C23,33 17,36 14,39 C22,37 31,33 37,32 Z" fill="${akzent}"/>
            <path d="M${EIS_HUEFTE[0]},${EIS_HUEFTE[1] - 2} L${EIS_SCHULTER[0]},${EIS_SCHULTER[1] + 1}" stroke="${jacke}" stroke-width="14" stroke-linecap="round"/>
            <path d="M28,52 L36,55" stroke="rgba(0,0,0,.2)" stroke-width="1.4"/>
            ${bein('a', false)}
            ${arm('a', false)}
            <circle cx="47" cy="23" r="6.8" fill="#f2cdb0"/>
            <circle cx="50.6" cy="22.4" r=".9" fill="#2a1a14"/>
            <circle cx="51" cy="25.8" r="1.6" fill="#f19a9a" opacity=".55"/>
            <path d="M40.5,21.5 C40,13.5 54,12.5 54,21 Z" fill="${akzent}"/>
            <path d="M40,21.3 L54.5,20.6" stroke="${jacke}" stroke-width="2.2"/>
            <circle cx="45" cy="12.2" r="2.6" fill="${jacke}"/>
        </svg>`;
    }
    // Schrittzyklus eines Beins (p = 0 … 1): gleiten (Fuß unter dem Körper, Knie gebeugt),
    // abstoßen (Fuß schräg nach hinten, Bein streckt sich), angehoben wieder nach vorn
    function eisFuss(p) {
        const glatt = (u) => u * u * (3 - 2 * u);
        if (p < 0.5) { const u = p / 0.5; return [36 - 7 * u, 92, 0]; }
        if (p < 0.78) { const u = glatt((p - 0.5) / 0.28); return [29 - 23 * u, 92 - u * 1.5, -6 * u]; }
        const u = glatt((p - 0.78) / 0.22);
        return [6 + 30 * u, 90.5 - Math.sin(u * Math.PI) * 7 + u * 1.5, -6 + 6 * u + Math.sin(u * Math.PI) * 10];
    }
    function eislaufPose(el, phase) {
        const zahl = (v) => v.toFixed(1);
        // Hüfte: beim Abstoßen etwas tiefer
        const hy = EIS_HUEFTE[1] + Math.abs(Math.sin(phase * Math.PI * 2)) * 1.2;
        const hx = EIS_HUEFTE[0];
        for (const [n, p] of [['a', phase], ['b', (phase + 0.5) % 1]]) {
            const [fx, fy, kipp] = eisFuss(p);
            let dx = fx - hx, dy = fy - hy, d = Math.hypot(dx, dy);
            const a = EIS_OBEN, b = EIS_UNTEN, max = a + b - 0.1;
            let ax = fx, ay = fy;
            if (d > max) { ax = hx + dx / d * max; ay = hy + dy / d * max; d = max; }
            const w = Math.atan2(ay - hy, ax - hx);
            const al = Math.acos(Math.max(-1, Math.min(1, (a * a + d * d - b * b) / (2 * a * d))));
            // das Knie zeigt nach vorn (in Laufrichtung)
            const k1 = [hx + Math.cos(w - al) * a, hy + Math.sin(w - al) * a];
            const k2 = [hx + Math.cos(w + al) * a, hy + Math.sin(w + al) * a];
            const knie = k1[0] >= k2[0] ? k1 : k2;
            const g = el.querySelector(`.fx-eis-bein-${n}`);
            g.querySelector('.fx-eis-hose').setAttribute('d', `M${hx},${zahl(hy)} L${zahl(knie[0])},${zahl(knie[1])} L${zahl(ax)},${zahl(ay)}`);
            g.querySelector('.fx-eis-schuh').setAttribute('transform', `translate(${zahl(ax)} ${zahl(ay + 1)}) rotate(${zahl(kipp)})`);
        }
        // Arme schwingen gegengleich zu den Beinen, leicht angewinkelt
        for (const [n, p] of [['a', (phase + 0.5) % 1], ['b', phase]]) {
            const schwung = Math.sin(p * Math.PI * 2);
            const w1 = (90 + schwung * 62) * Math.PI / 180;           // 90° = senkrecht nach unten
            const w2 = w1 - (25 + Math.max(0, schwung) * 35) * Math.PI / 180;
            const [sx, sy] = EIS_SCHULTER;
            const e = [sx + Math.cos(w1) * EIS_ARM[0], sy + Math.sin(w1) * EIS_ARM[0]];
            const h = [e[0] + Math.cos(w2) * EIS_ARM[1], e[1] + Math.sin(w2) * EIS_ARM[1]];
            const g = el.querySelector(`.fx-eis-arm-${n}`);
            g.querySelector('.fx-eis-aermel').setAttribute('d', `M${sx},${sy} L${zahl(e[0])},${zahl(e[1])} L${zahl(h[0])},${zahl(h[1])}`);
            const hand = g.querySelector('.fx-eis-hand');
            hand.setAttribute('cx', zahl(h[0])); hand.setAttribute('cy', zahl(h[1]));
        }
    }

    function eiszapfen(el, wVw) {
        el.classList.add('fx-frost-kasten');
        nachVorne(el);
        const lmax = 2.0;
        const id = neueId('eis');
        const s = svg('svg', {viewBox: `0 0 ${wVw} ${lmax}`, class: 'fx-deko fx-hangend'}, [
            svg('defs', {}, [svg('linearGradient', {id: id, x1: 0, y1: 0, x2: 0, y2: 1}, [
                svg('stop', {offset: 0, 'stop-color': '#ffffff', 'stop-opacity': 0.98}),
                svg('stop', {offset: 0.55, 'stop-color': '#dcecff', 'stop-opacity': 0.9}),
                svg('stop', {offset: 1, 'stop-color': '#a9cdf5', 'stop-opacity': 0.75}),
            ])]),
        ]);
        Object.assign(s.style, {left: '0', top: 'calc(100% - 0.12vw)', width: `${wVw}vw`, height: `${lmax}vw`,
            filter: 'drop-shadow(0 .05vw .08vw rgba(40,80,130,.45))'});
        let x = 3.3;
        while (x < wVw - 0.7) {
            const b = zufall(0.18, 0.42);
            const l = Math.random() < 0.3 ? zufall(1.0, lmax) : zufall(0.3, 0.9);
            const m = x + b;
            s.appendChild(svg('path', {
                d: `M ${x} 0 L ${x + 2 * b} 0 Q ${m + b * 0.25} ${l * 0.55} ${m + zufall(-0.04, 0.04)} ${l} Q ${m - b * 0.25} ${l * 0.55} ${x} 0 Z`,
                fill: `url(#${id})`,
            }));
            s.appendChild(svg('path', {d: `M ${m - b * 0.35} 0.05 Q ${m - b * 0.15} ${l * 0.4} ${m} ${l * 0.8}`, stroke: 'rgba(255,255,255,.95)', 'stroke-width': 0.04, fill: 'none'}));
            if (l > 0.8 && Math.random() < 0.5) {
                const g = svg('circle', {cx: m, cy: l * 0.92, r: 0.12, fill: '#fff', class: 'fx-zapfen-glitzer'});
                g.style.setProperty('--d', `${zufall(3, 7).toFixed(1)}s`);
                g.style.setProperty('--v', `-${zufall(0, 7).toFixed(1)}s`);
                g.style.transformBox = 'fill-box';
                g.style.transformOrigin = '50% 50%';
                s.appendChild(g);
            }
            x += 2 * b + zufall(0.05, 0.6);
        }
        el.appendChild(s);
        wachsenLassen(s, dauer(zufall(600, 1200), zufall(4, 8)));
    }

    // ==================================================================
    // WEIHNACHTEN: Lichterkette oben (ganzer Advent), ab dem 16. Dezember fliegt
    // der Weihnachtsmann vorbei

    // Grummeliger Weihnachtswichtel (eigene Figur, Wunsch Jonas statt Grinch): grüner
    // Mantel, grüne Zipfelmütze mit Glöckchen, Knollennase, zerzauster grauer Bart, fiese
    // Brauen; trägt den Geschenkesack über der Schulter und geht nach rechts.
    // viewBox-Ausschnitt 70|60, 190 × 350; Sacköffnung bei (140|244).
    const WICHTEL_VB = [70, 60, 190, 350], WICHTEL_SACK = [140, 244], WICHTEL_B = 4.6;
    function wichtelSvg() {
        return `<svg class="fx-wichtel fx-geht" viewBox="${WICHTEL_VB.join(' ')}" xmlns="${NS}">
            <path d="M106,246 C70,290 84,372 140,376 C190,380 200,318 176,262 C162,234 128,228 106,246 Z" fill="#c9a46a" stroke="#8a6a3a" stroke-width="2"/>
            <path d="M118,262 C130,290 128,330 120,356 M150,258 C160,300 160,336 150,364" stroke="#a8844c" stroke-width="2" fill="none"/>
            <rect x="116" y="222" width="30" height="26" rx="2" fill="#d6303c" transform="rotate(-14 131 235)"/>
            <path d="M131,220 L131,248 M116,234 L146,234" stroke="#f2c14e" stroke-width="4" transform="rotate(-14 131 235)"/>
            <rect x="146" y="230" width="24" height="22" rx="2" fill="#3a86d4" transform="rotate(10 158 241)"/>
            <path d="M158,228 L158,252" stroke="#ffffff" stroke-width="3" transform="rotate(10 158 241)"/>
            <path d="M120,244 C134,250 158,252 176,246" stroke="#8a6a3a" stroke-width="5" fill="none" stroke-linecap="round"/>
            <g class="fx-wb-bein fx-wb-b"><rect x="180" y="368" width="16" height="26" rx="4" fill="#33333d"/><ellipse cx="186" cy="398" rx="17" ry="8" fill="#5e3b1e"/></g>
            <path d="M176,262 C162,316 154,350 156,378 L254,378 C252,346 242,300 228,260 C214,250 190,250 176,262 Z" fill="#2f7d3a"/>
            <path d="M200,262 L204,378" stroke="#24632d" stroke-width="2"/>
            <rect x="160" y="326" width="92" height="10" rx="2" fill="#5a3418"/>
            <rect x="196" y="323" width="16" height="16" rx="2" fill="none" stroke="#e6c25a" stroke-width="3"/>
            <path d="M156,376 L254,376" stroke="#f3efe6" stroke-width="8" stroke-linecap="round"/>
            <g class="fx-wb-bein fx-wb-a"><rect x="212" y="368" width="16" height="26" rx="4" fill="#3b3b46"/><ellipse cx="226" cy="398" rx="18" ry="8" fill="#6b4423"/></g>
            <path d="M184,272 C170,262 160,252 150,244" stroke="#2f7d3a" stroke-width="15" stroke-linecap="round" fill="none"/>
            <circle cx="146" cy="242" r="8" fill="#f2c9a8"/>
            <path d="M228,276 C240,292 246,306 244,322" stroke="#2f7d3a" stroke-width="13" stroke-linecap="round" fill="none"/>
            <circle cx="244" cy="326" r="7" fill="#f2c9a8"/>
            <circle cx="210" cy="222" r="27" fill="#f2c9a8"/>
            <path d="M186,226 C180,252 192,276 212,282 C232,278 244,258 238,228 C232,240 222,244 212,244 C200,244 190,238 186,226 Z" fill="#dcdcd6"/>
            <path d="M190,250 L186,262 M200,262 L198,274 M214,268 L214,282 M228,258 L232,270" stroke="#c4c4bc" stroke-width="2" stroke-linecap="round"/>
            <path d="M214,236 C222,240 232,240 238,234" stroke="#c4c4bc" stroke-width="5" stroke-linecap="round" fill="none"/>
            <circle cx="234" cy="226" r="10" fill="#d97a6a"/>
            <circle cx="231" cy="222" r="3" fill="#f0a898"/>
            <ellipse cx="222" cy="214" rx="3.2" ry="2.2" fill="#2a1a14"/>
            <path d="M216,212 C219,210 224,210 227,212" stroke="#c99f86" stroke-width="1.6" fill="none"/>
            <path d="M210,200 L231,209" stroke="#55554f" stroke-width="6" stroke-linecap="round"/>
            <path d="M180,198 C182,162 178,126 160,90 C154,78 148,72 140,70 C150,82 170,106 190,136 C206,160 224,182 242,198 Z" fill="#2f7d3a"/>
            <path d="M188,192 C190,164 186,134 170,104 C178,120 196,152 214,192 Z" fill="#3f9a4b"/>
            <rect x="176" y="186" width="70" height="16" rx="7" fill="#24632d"/>
            <g class="fx-glocke"><path d="M138,72 L138,76" stroke="#a8842a" stroke-width="2"/><circle cx="138" cy="82" r="8" fill="#e6c25a"/><path d="M134,84 L142,84" stroke="#a8842a" stroke-width="2"/></g>
        </svg>`;
    }

    function Weihnachten(nah) {
        let flug = null;
        let naechster = vorschau ? 1.5 : zufall(10, 60);
        // der Weihnachtsmann fliegt erst ab dem 16. Dezember („nah“), davor nur die
        // Lichterkette; dann alle 60–90 Sekunden
        const abstand = () => dauer(zufall(60, 90), 26);   // alle 60–90 Sekunden (Wunsch Jonas)
        // Geschenke, die er im Vorbeifliegen verteilt: halb hinter den Kacheln,
        // sie verschwinden nach und nach innerhalb von etwa einer halben Stunde
        const geschenke = [];
        function geschenkAblegen(t, nahX) {
            // eine Kachel in der Nähe der Stelle, an der der Schlitten gerade ist
            const nahe = kaesten.filter((k) => Math.abs(k.x + k.w / 2 - nahX) < 14 * VW);
            const liste = nahe.length ? nahe : kaesten;
            if (!liste.length) return;
            const k = auswahl(liste);
            const seite = auswahl(['rechts', 'links', 'unten', 'rechts']);
            let dx, dy;
            if (seite === 'unten') { dx = zufall(0.25, 0.8) * k.w; dy = k.h - 1.1 * VW; }
            else if (seite === 'rechts') { dx = k.w - 0.9 * VW; dy = zufall(0.2, 0.65) * k.h; }
            else { dx = -1.3 * VW; dy = zufall(0.3, 0.7) * k.h; }
            const box = document.createElement('div');
            box.className = 'fx-geschenk';
            box.innerHTML = geschenkSvg();
            box.firstChild.style.setProperty('--r', `${zufall(-18, 18).toFixed(0)}deg`);
            domH.appendChild(box);
            const g = {el: k.el, dx: dx / VW, dy: dy / VW, box: box, ende: t + dauer(zufall(20, 32) * 60, zufall(20, 40))};
            geschenke.push(g);
            if (geschenke.length > 18) geschenke.shift().box.remove();
            geschenkSetzen(g);
            const r = box.getBoundingClientRect();
            const b0 = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            funkenStreuen(r.left - b0.left + r.width / 2, r.top - b0.top + r.height / 2, 10, 'gold');
        }
        function geschenkSetzen(g) {
            if (!g.el.isConnected) return;
            const r = g.el.getBoundingClientRect();
            const b0 = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            g.box.style.transform = `translate(${r.left - b0.left + g.dx * VW}px, ${r.top - b0.top + g.dy * VW}px)`;
        }
        let birnen = null;
        let kette = null;
        function ketteBauen() {
            birnen = [];
            kette = [];
            const boegen = Math.max(3, Math.round(W / (21 * VW)));
            const breite = W / boegen;
            const durchhang = 1.25 * VW, oben = 0.15 * VW;
            const farbenHell = ['#f2a922', '#e04a3a', '#f6d04d', '#2f9e6a', '#3a86d4'];
            const farbenDunkel = ['#ffe9b8', '#ffd27a', '#ffe9b8', '#ffc56b'];
            let n = 0;
            for (let i = 0; i < boegen; i++) {
                const x0 = i * breite;
                kette.push([x0, oben, x0 + breite / 2, oben + 2 * durchhang, x0 + breite, oben]);
                const proBogen = Math.max(5, Math.round(breite / (2.1 * VW)));
                for (let j = 1; j < proBogen; j++) {
                    const s = j / proBogen;
                    const x = x0 + breite * s;
                    const y = oben + durchhang * 4 * s * (1 - s);
                    const steigung = durchhang * 4 * (1 - 2 * s) / breite;
                    const farben = opt.dunkel ? farbenDunkel : farbenHell;
                    birnen.push({x: x, y: y, w: Math.atan(steigung), farbe: farben[n % farben.length], p: zufall(0, 6.28), v: zufall(0.6, 1.6)});
                    n += 1;
                }
            }
        }
        // Der Wichtel kommt so oft wie der Weihnachtsmann (versetzt, etwa 5 Minuten
        // nach ihm) und sammelt die Pakete wieder ein: Wo er darunter vorbeischleicht,
        // hüpft das Paket im Bogen in seinen Sack.
        let dieb = null, diebAb = null;
        const fliegende = [];
        function diebStarten(t) {
            const el = svgAusText(wichtelSvg());
            domV.appendChild(el);
            const richtung = Math.random() < 0.5 ? 1 : -1;
            // nur die Pakete, die jetzt schon liegen – neue bleiben für den nächsten Gang liegen
            dieb = {el: el, richtung: richtung, x: richtung > 0 ? -8 * VW : W + VW, ziele: new Set(geschenke)};
        }
        function diebSack() {
            const bw = WICHTEL_B * VW, bh = bw * WICHTEL_VB[3] / WICHTEL_VB[2];
            const y = LAUF_BODEN - bh - 0.2 * VW;
            const fx = (WICHTEL_SACK[0] - WICHTEL_VB[0]) / WICHTEL_VB[2], fy = (WICHTEL_SACK[1] - WICHTEL_VB[1]) / WICHTEL_VB[3];
            const sx = dieb.richtung > 0 ? fx : 1 - fx;
            return [dieb.x + sx * bw, y + fy * bh];
        }
        function diebSchritt(dt, t) {
            const bw = WICHTEL_B * VW, bh = bw * WICHTEL_VB[3] / WICHTEL_VB[2];
            // der Wichtel stapft gemächlich durchs Bild
            dieb.x += dieb.richtung * 8.5 * VW * dt;
            const hops = Math.abs(Math.sin(t * 15)) * -0.25 * VW;
            const y = LAUF_BODEN - bh - 0.2 * VW + hops;
            dieb.el.style.transform = `translate(${dieb.x.toFixed(1)}px, ${y.toFixed(1)}px)${dieb.richtung < 0 ? ' scale(-1, 1)' : ''}`;
            // Pakete über ihm springen in den Sack
            const mitte = dieb.x + bw / 2;
            const b0 = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            for (let i = geschenke.length - 1; i >= 0; i--) {
                const g = geschenke[i];
                if (!dieb.ziele.has(g)) continue;
                const r = g.box.getBoundingClientRect();
                const gx = r.left - b0.left + r.width / 2;
                if (Math.abs(gx - mitte) < 1.2 * VW || (dieb.richtung > 0 ? mitte > gx + 2 * VW : mitte < gx - 2 * VW)) {
                    geschenke.splice(i, 1);
                    // nach vorne holen, damit man den Sprung sieht
                    const von = [r.left - b0.left, r.top - b0.top];
                    g.box.classList.add('fx-geschenk-fliegt');
                    domV.appendChild(g.box);
                    fliegende.push({box: g.box, von: von, w: r.width, start: t});
                }
            }
            const weg = dieb.richtung > 0 ? dieb.x > W + VW : dieb.x < -bw - VW;
            if (weg && !fliegende.length) { dieb.el.remove(); dieb = null; }
        }
        function fliegendeSchritt(t) {
            for (let i = fliegende.length - 1; i >= 0; i--) {
                const f = fliegende[i];
                const u = Math.min(1, (t - f.start) / 0.75);
                const ziel = dieb ? diebSack() : f.von;
                const x = f.von[0] + (ziel[0] - f.w * 0.3 - f.von[0]) * u;
                const y = f.von[1] + (ziel[1] - f.w * 0.5 - f.von[1]) * u - Math.sin(u * Math.PI) * 5 * VW;
                f.box.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) scale(${(1 - 0.5 * u).toFixed(3)}) rotate(${(u * 360).toFixed(0)}deg)`;
                if (u >= 1) { f.box.remove(); fliegende.splice(i, 1); }
            }
        }
        function fliegen(t) {
            const el = svgAusText(schlittenSvg());
            domV.appendChild(el);
            // 4 bis 6 Geschenke an zufälligen Stellen der Strecke
            const abwurf = [];
            for (let i = 0, n = 4 + Math.floor(Math.random() * 3); i < n; i++) abwurf.push(zufall(0.15, 0.85));
            flug = {el: el, start: t, dauer: 14, y0: zufall(9, 26) * VW, richtung: 1, abwurf: abwurf.sort()};
        }
        return {
            stop() {
                if (flug) flug.el.remove();
                for (const g of geschenke) g.box.remove();
                for (const f of fliegende) f.box.remove();
                if (dieb) { dieb.el.remove(); dieb = null; }
            },
            groesse() { birnen = null; },
            schritt(dt, t) {
                if (!birnen) ketteBauen();
                // Kabel
                cxH.strokeStyle = opt.dunkel ? 'rgba(140,160,140,.55)' : 'rgba(25,55,35,.7)';
                cxH.lineWidth = 0.1 * VW;
                cxH.beginPath();
                for (const k of kette) { cxH.moveTo(k[0], k[1]); cxH.quadraticCurveTo(k[2], k[3], k[4], k[5]); }
                cxH.stroke();
                for (const b of birnen) {
                    const hell = 0.55 + 0.45 * Math.sin(t * b.v + b.p);
                    const glanz = sprite(`birne-glanz-${b.farbe}`, () => weichPunkt(1.1 * VW * DPR, hexRgba(b.farbe, 0.75)));
                    const birne = sprite(`birne-${b.farbe}`, () => birnenSprite(b.farbe));
                    cxH.globalAlpha = (opt.dunkel ? 0.9 : 0.55) * hell;
                    cxH.drawImage(glanz, b.x - 1.1 * VW, b.y + 0.35 * VW - 1.1 * VW, 2.2 * VW, 2.2 * VW);
                    cxH.globalAlpha = 0.75 + 0.25 * hell;
                    cxH.save();
                    cxH.translate(b.x, b.y);
                    cxH.rotate(b.w);
                    cxH.drawImage(birne, -0.3 * VW, -0.05 * VW, 0.6 * VW, 0.9 * VW);
                    cxH.restore();
                }
                cxH.globalAlpha = 1;
                // Geschenke folgen ihren Kacheln; abgelaufene verblassen nacheinander
                for (let i = geschenke.length - 1; i >= 0; i--) {
                    const g = geschenke[i];
                    geschenkSetzen(g);
                    if (t >= g.ende && !g.weg) {
                        g.weg = true;
                        g.box.style.opacity = '0';
                        setTimeout(() => g.box.remove(), 2200);
                        geschenke.splice(i, 1);
                    }
                }
                naechster -= dt;
                // nicht losfliegen, solange der Wichtel unterwegs ist
                if (nah && !flug && !dieb && naechster <= 0) {
                    fliegen(t);
                    naechster = abstand();
                }
                if (diebAb !== null && !dieb && !flug && t >= diebAb) {
                    diebAb = null;
                    if (geschenke.length) diebStarten(t);
                }
                if (dieb) diebSchritt(dt, t);
                fliegendeSchritt(t);
                if (flug) {
                    const p = (t - flug.start) / flug.dauer;
                    if (p >= 1) {
                        flug.el.remove(); flug = null;
                        // 20–30 Sekunden später kommt der Wichtel und ist vor dem nächsten Flug wieder weg
                        if (diebAb === null && !dieb) diebAb = t + dauer(zufall(20, 30), 5);
                        return;
                    }
                    const breite = 32 * VW;
                    const x = -breite - 2 * VW + (W + breite + 4 * VW) * p;
                    const y = flug.y0 + Math.sin(p * Math.PI * 2.4) * 1.6 * VW - p * 4 * VW;
                    const neigung = Math.cos(p * Math.PI * 2.4) * -2.2 - 1.5;
                    flug.el.style.transform = `translate(${x}px, ${y}px) rotate(${neigung}deg)`;
                    // Glitzerspur hinter den Kufen
                    funkenStreuen(x + breite * 0.01, y + breite * 0.3125 * 0.79, 2);
                    // Geschenke abwerfen (aus dem Sack, der hinten im Schlitten liegt)
                    while (flug.abwurf.length && p >= flug.abwurf[0]) {
                        flug.abwurf.shift();
                        geschenkAblegen(t, x + breite * 0.12);
                    }
                }
            },
        };
    }

    // ==================================================================
    // NIKOLAUS: Lichterkette wie im Advent; unten, wo keine Kachel ist, stehen
    // geputzte Stiefel. Morgens sind sie voller Süßigkeiten, bis 14 Uhr werden es
    // immer weniger – und neben den Stiefeln liegen die Verpackungsreste.

    const STIEFEL_ARTEN = [
        {schaft: '#5a3418', hell: '#8a5530', sohle: '#2a1a10', schnuerung: true},     // braunes Leder
        {schaft: '#1f1f24', hell: '#4a4a55', sohle: '#0d0d10', schnuerung: true},     // schwarzes Leder
        {schaft: '#c8202e', hell: '#ef5a63', sohle: '#5a0d12', schnuerung: false},    // roter Gummistiefel
        {schaft: '#1f5fa8', hell: '#5a92d6', sohle: '#0f2c52', schnuerung: false},    // blauer Gummistiefel
    ];
    const SUESSES = ['schokonikolaus', 'zuckerstange', 'mandarine', 'lolli', 'bonbon', 'schokoriegel'];
    function Nikolaus() {
        const advent = Weihnachten(false);
        let t0 = null, stiefel = null, stiefelZeit = null;
        // Wo in einer Kachel Text steht (Rechtecke relativ zur Bühne)
        function textFlaechen(el) {
            const b0 = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            const liste = [];
            const gang = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
            const bereich = document.createRange();
            for (let n = gang.nextNode(); n; n = gang.nextNode()) {
                if (!n.textContent.trim() || n.parentElement.closest('.fx-deko')) continue;
                bereich.selectNodeContents(n);
                for (const r of bereich.getClientRects()) {
                    if (r.width > 0 && r.height > 0) liste.push({l: r.left - b0.left, r: r.right - b0.left, t: r.top - b0.top, b: r.bottom - b0.top});
                }
            }
            return liste;
        }
        const ueberlappt = (a, b) => a.l < b.r && a.r > b.l && a.t < b.b && a.b > b.t;
        // Stiefel stehen unten rechts in Kacheln auf der Kachelkante – nur wo kein Text ist –
        // und zusätzlich unten im freien Streifen (über dem Schriftband), wenn dort Platz ist
        function stiefelStellen() {
            let saat = 7;
            const zuf = (a, b) => { saat = (saat * 9301 + 49297) % 233280; return a + (b - a) * saat / 233280; };
            const plaetze = [];
            const ordnung = kaesten.slice().sort((a, b) => ((a.x * 7 + a.y * 13) % 97) - ((b.x * 7 + b.y * 13) % 97));
            for (const k of ordnung) {
                if (plaetze.length >= 12) break;
                const texte = textFlaechen(k.el);
                for (const sc of [1, 0.85, 0.7]) {
                    const sw = 3.4 * VW * sc, sh = 4.6 * VW * sc, ueber = 1.8 * VW * sc;
                    // auf der Kachelkante, aber nie im oder unter dem Schriftband
                    const boden = Math.min(k.y + k.h - 0.25 * VW, UNTEN - 0.25 * VW);
                    const oben = boden - sh - ueber;
                    if (oben < k.y + 0.25 * VW) continue;
                    // nur rechts neben allem Text dieser Höhe, nicht zwischen Textspalten
                    const rechtsVomText = Math.max(k.x + 2.5 * VW, ...texte.filter((t) => t.b > oben && t.t < boden).map((t) => t.r + 0.6 * VW));
                    let gefunden = null;
                    for (let x = k.x + k.w - sw - 0.6 * VW; x >= rechtsVomText; x -= 0.5 * VW) {
                        if (!texte.some((t) => ueberlappt(t, {l: x - 0.5 * VW, r: x + sw + 0.5 * VW, t: oben, b: boden + 0.25 * VW}))) { gefunden = x; break; }
                    }
                    if (gefunden === null) continue;
                    // Platz für Verpackungsreste neben dem Stiefel, auf der Kachelkante, ohne Text
                    const reste = [];
                    for (let dx = -7; dx <= 7; dx += 0.5) {
                        const rx = gefunden + sw / 2 + dx * VW * sc;
                        const frei = rx > k.x + 0.8 * VW && rx < k.x + k.w - 0.8 * VW &&
                            Math.abs(dx) * VW * sc > sw * 0.6 &&
                            !texte.some((t) => ueberlappt(t, {l: rx - 1.0 * VW, r: rx + 1.0 * VW, t: boden - 1.0 * VW, b: boden + 0.3 * VW}));
                        if (frei) reste.push(rx - (gefunden + sw / 2));
                    }
                    plaetze.push({x: gefunden, w: sw, h: sh, boden: boden, s: sc, reste: reste});
                    break;
                }
            }
            // unten im freien Streifen
            const unten = UNTEN - 0.15 * VW;
            for (let x = 1.5 * VW; x < W - 4 * VW; x += 0.5 * VW) {
                if (plaetze.some((p) => Math.abs(p.boden - unten) < VW && Math.abs(p.x - x) < 11 * VW)) continue;
                let decke = 0;
                for (const k of kaesten) if (k.x < x + 5 * VW && k.x + k.w > x - 2 * VW && k.y < unten) decke = Math.max(decke, k.y + k.h);
                const sc = Math.min(1, (unten - decke - 0.3 * VW) / (6.4 * VW));
                if (sc < 0.6) continue;
                const reste = [];
                for (let dx = -6; dx <= 6; dx += 0.5) if (Math.abs(dx) > 2) reste.push(dx * VW * sc);
                plaetze.push({x: x, w: 3.4 * VW * sc, h: 4.6 * VW * sc, boden: unten, s: sc, reste: reste});
            }
            return plaetze.map((st, i) => {
                const n = 4 + Math.floor(zuf(0, 2.99));
                // Plätze für die Reste nebeneinander, mit Abstand, nahe am Stiefel zuerst
                const frei = st.reste.slice().sort((a, b) => Math.abs(a) - Math.abs(b));
                const restPlaetze = [];
                for (const r of frei) if (restPlaetze.every((q) => Math.abs(q - r) >= 2.7 * VW * st.s)) restPlaetze.push(r);
                const inhalt = [];
                for (let j = 0; j < n; j++) inhalt.push({art: SUESSES[Math.floor(zuf(0, SUESSES.length - 0.01))], dx: zuf(-0.15, 0.15), hoch: zuf(0.5, 1.5), kipp: zuf(-0.4, 0.4),
                    farbe: auswahl(['#e8344e', '#f2c14e', '#2f9e6a', '#3a86d4', '#a259d9']),
                    // wo die Verpackung landet: auf einem freien Platz neben dem Stiefel
                    restX: restPlaetze.length ? restPlaetze[j % restPlaetze.length] + zuf(-0.3, 0.3) * VW : (j % 2 ? -1 : 1) * st.w * (0.9 + j * 0.5),
                    restDreh: zuf(0, 6.28), ab: zuf(0.05, 0.98)});
                inhalt.sort((a, b) => a.ab - b.ab);
                return Object.assign(st, {art: STIEFEL_ARTEN[i % STIEFEL_ARTEN.length], blick: i % 3 === 1 ? -1 : 1, inhalt: inhalt, p: zuf(0, 6.28)});
            });
        }
        function stiefelMalen(g, st, t) {
            const {x, w, h, boden, art} = st;
            g.save();
            g.translate(x + w / 2, boden);
            g.scale(st.blick, 1);
            g.translate(-w / 2, 0);
            // Schaft und Fuß (Seitenansicht, Spitze nach rechts)
            g.fillStyle = art.schaft;
            g.beginPath();
            g.moveTo(0.06 * w, -h);
            g.lineTo(0.58 * w, -h);
            g.lineTo(0.6 * w, -0.42 * h);
            g.quadraticCurveTo(0.98 * w, -0.4 * h, 1.0 * w, -0.12 * h);
            g.lineTo(1.0 * w, 0);
            g.lineTo(0, 0);
            g.lineTo(0.04 * w, -0.5 * h);
            g.closePath();
            g.fill();
            // Sohle
            g.fillStyle = art.sohle;
            g.fillRect(-0.02 * w, -0.08 * h, 1.04 * w, 0.08 * h);
            // Öffnung oben
            g.fillStyle = 'rgba(0,0,0,.55)';
            g.beginPath(); g.ellipse(0.32 * w, -h, 0.27 * w, 0.06 * h, 0, 0, 6.283); g.fill();
            // Glanz: geputzt!
            g.strokeStyle = 'rgba(255,255,255,.55)';
            g.lineWidth = 0.12 * VW; g.lineCap = 'round';
            g.beginPath(); g.moveTo(0.16 * w, -0.9 * h); g.lineTo(0.14 * w, -0.5 * h); g.stroke();
            g.beginPath(); g.moveTo(0.7 * w, -0.33 * h); g.quadraticCurveTo(0.85 * w, -0.31 * h, 0.92 * w, -0.2 * h); g.stroke();
            if (art.schnuerung) {
                g.strokeStyle = 'rgba(240,230,210,.8)'; g.lineWidth = 0.06 * VW;
                for (let i = 0; i < 3; i++) {
                    const yy = -0.62 * h + i * 0.12 * h;
                    g.beginPath(); g.moveTo(0.48 * w, yy); g.lineTo(0.6 * w, yy + 0.05 * h); g.stroke();
                }
            }
            g.restore();
            // gelegentliches Funkeln auf dem Leder
            const f = Math.sin(t * 1.3 + st.p);
            if (f > 0.93) {
                const stb = sprite('stern-weiss', () => stern(1.2 * VW * DPR, 'rgba(255,255,255,1)'));
                g.globalAlpha = (f - 0.93) / 0.07;
                const sx = x + w * (st.blick > 0 ? 0.18 : 0.82);
                g.drawImage(stb, sx - 0.5 * VW, boden - 0.8 * h - 0.5 * VW, VW, VW);
                g.globalAlpha = 1;
            }
        }
        function suessesMalen(g, art, farbe, x, y, kipp, sc) {
            g.save(); g.translate(x, y); g.rotate(kipp);
            const u = 0.95 * VW * (sc || 1);
            if (art === 'schokonikolaus') {
                g.fillStyle = '#d6303c'; g.beginPath(); g.moveTo(0, -1.9 * u); g.quadraticCurveTo(0.65 * u, -0.6 * u, 0.55 * u, 0); g.lineTo(-0.55 * u, 0); g.quadraticCurveTo(-0.65 * u, -0.6 * u, 0, -1.9 * u); g.fill();
                g.fillStyle = '#f2c98a'; g.beginPath(); g.arc(0, -1.15 * u, 0.22 * u, 0, 6.283); g.fill();
                g.fillStyle = '#fff'; g.fillRect(-0.45 * u, -0.85 * u, 0.9 * u, 0.16 * u);
                g.strokeStyle = 'rgba(255,255,255,.6)'; g.lineWidth = 0.06 * u; g.beginPath(); g.moveTo(-0.25 * u, -0.4 * u); g.lineTo(-0.3 * u, -0.1 * u); g.stroke();
            } else if (art === 'zuckerstange') {
                g.lineCap = 'round'; g.lineWidth = 0.28 * u;
                const pfad = () => { g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -1.6 * u); g.arc(0.35 * u, -1.6 * u, 0.35 * u, Math.PI, 0); };
                g.strokeStyle = '#fff'; pfad(); g.stroke();
                g.setLineDash([0.2 * u, 0.2 * u]); g.strokeStyle = '#e02a3a'; pfad(); g.stroke(); g.setLineDash([]);
            } else if (art === 'mandarine') {
                g.fillStyle = '#f39a1c'; g.beginPath(); g.arc(0, -0.5 * u, 0.55 * u, 0, 6.283); g.fill();
                g.fillStyle = 'rgba(255,255,255,.35)'; g.beginPath(); g.arc(-0.18 * u, -0.7 * u, 0.15 * u, 0, 6.283); g.fill();
                g.fillStyle = '#2f8a3a'; g.beginPath(); g.ellipse(0.12 * u, -1.08 * u, 0.22 * u, 0.1 * u, -0.5, 0, 6.283); g.fill();
            } else if (art === 'lolli') {
                g.strokeStyle = '#f4f4f4'; g.lineWidth = 0.12 * u; g.beginPath(); g.moveTo(0, 0); g.lineTo(0, -1.4 * u); g.stroke();
                g.fillStyle = farbe; g.beginPath(); g.arc(0, -1.75 * u, 0.5 * u, 0, 6.283); g.fill();
                g.strokeStyle = 'rgba(255,255,255,.75)'; g.lineWidth = 0.1 * u; g.beginPath();
                for (let a = 0; a < 9; a += 0.4) { const r = 0.05 * u + a * 0.05 * u; g.lineTo(Math.cos(a) * r, -1.75 * u + Math.sin(a) * r); }
                g.stroke();
            } else if (art === 'bonbon') {
                g.fillStyle = farbe;
                g.beginPath(); g.ellipse(0, -0.6 * u, 0.42 * u, 0.3 * u, 0, 0, 6.283); g.fill();
                g.beginPath(); g.moveTo(-0.4 * u, -0.6 * u); g.lineTo(-0.85 * u, -0.85 * u); g.lineTo(-0.85 * u, -0.35 * u); g.closePath(); g.fill();
                g.beginPath(); g.moveTo(0.4 * u, -0.6 * u); g.lineTo(0.85 * u, -0.85 * u); g.lineTo(0.85 * u, -0.35 * u); g.closePath(); g.fill();
                g.fillStyle = 'rgba(255,255,255,.45)'; g.beginPath(); g.ellipse(-0.1 * u, -0.7 * u, 0.15 * u, 0.07 * u, 0, 0, 6.283); g.fill();
            } else {   // Schokoriegel in lila Papier, oben Silberfolie
                g.fillStyle = '#a259d9'; g.fillRect(-0.32 * u, -1.5 * u, 0.64 * u, 1.5 * u);
                g.fillStyle = '#c9cdd2'; g.fillRect(-0.32 * u, -1.85 * u, 0.64 * u, 0.4 * u);
                g.strokeStyle = 'rgba(255,255,255,.8)'; g.lineWidth = 0.08 * u;
                g.beginPath(); g.moveTo(-0.2 * u, -1.2 * u); g.lineTo(-0.2 * u, -0.3 * u); g.stroke();
            }
            g.restore();
        }
        // was nach dem Essen übrig bleibt, flach am Boden – gezeichnet wie im Vorschaubild
        const RESTE = {
            schokonikolaus: [
                ['f', '#c8202e', 'M-22,0 L-26,-12 L-18,-24 L-6,-30 L8,-28 L20,-20 L26,-6 L20,4 L4,8 L-12,6 Z'],
                ['s', '#8c1420', 1.2, 'M-18,-24 L-6,-14 L8,-28 M-6,-14 L-4,6 M-6,-14 L20,-20 M-6,-14 L-24,-6'],
                ['s', '#ff7a84', 2, 'M-14,-18 L-8,-22 L-2,-18'],
                ['f', '#e6c25a', 'M14,-4 L26,-12 L36,-4 L30,8 L18,8 Z'],
                ['s', '#fff3c0', 1.6, 'M18,-4 L26,-8 L30,0'],
            ],
            bonbon: [
                ['f', null, 'M-16,-6 C-8,-12 8,-12 16,-6 C8,0 -8,0 -16,-6 Z'],
                ['f', null, 'M-16,-6 L-34,-18 L-30,-6 L-38,4 L-26,0 Z'],
                ['f', null, 'M16,-6 L34,-16 L30,-4 L38,6 L26,0 Z'],
                ['s', 'rgba(255,255,255,.8)', 2, 'M-12,-8 L12,-8 M-10,-4 L10,-4'],
                ['s', 'rgba(0,0,0,.25)', 1.2, 'M-30,-14 L-26,-6 M-34,-2 L-28,-4 M30,-12 L28,-4 M34,4 L28,0'],
            ],
            mandarine: [
                ['s', '#f39a1c', 7, 'M-30,0 C-30,-14 -10,-16 -6,-6 C-2,4 -18,6 -18,-2 C-18,-8 -10,-8 -10,-4'],
                ['s', '#fff3dc', 2, 'M-29,2 C-29,-12 -9,-14 -5,-4'],
                ['s', '#f39a1c', 7, 'M2,2 C10,-12 24,-12 30,-2 C34,6 26,10 20,6'],
                ['s', '#fff3dc', 2, 'M3,4 C11,-10 25,-10 31,0'],
            ],
            schokoriegel: [
                ['f', '#a259d9', 'M-28,-10 L10,-16 L14,0 L-24,6 Z'],
                ['f', '#c9cdd2', 'M10,-16 L24,-20 L30,-12 L22,-2 L14,0 Z'],
                ['s', '#ffffff', 1.6, 'M14,-14 L22,-16 L26,-10'],
                ['s', 'rgba(255,255,255,.85)', 2, 'M-20,-8 L2,-12 M-18,-2 L4,-6'],
                ['s', '#7a3fb0', 1.2, 'M10,-16 L12,-12 L9,-9 L13,-5 L10,-2 L14,0'],
            ],
            lolli: [
                ['s', '#f4f4f4', 4, 'M-26,2 L14,-6'],
                ['s', '#c9cdd2', 1, 'M-26,2 L14,-6'],
                ['f', '#dff0ff', 'M14,-6 C20,-18 34,-14 30,-4 C28,4 18,6 14,-6 Z'],
                ['s', '#9ab8d0', 1, 'M14,-6 C20,-18 34,-14 30,-4 C28,4 18,6 14,-6 Z'],
                ['s', null, 2.5, 'M20,-8 L26,-10'],
            ],
            zuckerstange: [   // knisternde Cellophanhülle mit roten Streifenresten
                ['f', 'rgba(223,240,255,.9)', 'M-24,2 L-18,-10 L-4,-14 L10,-10 L22,-14 L26,-2 L12,4 L-6,6 Z'],
                ['s', '#9ab8d0', 1, 'M-24,2 L-18,-10 L-4,-14 L10,-10 L22,-14 L26,-2 L12,4 L-6,6 Z M-12,-10 L-8,2 M6,-11 L4,4'],
                ['s', '#e02a3a', 2.4, 'M-14,-4 L-10,-8 M2,-2 L6,-7 M14,-6 L18,-10'],
            ],
        };
        const resteCache = {};
        function restMalen(g, art, farbe, x, y, dreh, sc) {
            const teile = RESTE[art] || RESTE.bonbon;
            g.save(); g.translate(x, y); g.rotate((dreh - 3.14) * 0.06);
            const k = 2.4 * VW * (sc || 1) / 60;
            g.scale(k, k);
            g.lineCap = 'round'; g.lineJoin = 'round';
            for (const [art2, f, a, b] of teile) {
                const pfad = resteCache[b || a] || (resteCache[b || a] = new Path2D(b || a));
                if (art2 === 'f') { g.fillStyle = f || farbe; g.fill(pfad); }
                else { g.strokeStyle = f || farbe; g.lineWidth = a; g.stroke(pfad); }
            }
            g.restore();
        }
        return {
            stop() { advent.stop(); uhrWeg(); },
            groesse() { advent.groesse(); stiefel = null; },
            schritt(dt, t) {
                advent.schritt(dt, t);
                if (t0 === null) t0 = t;
                if (kaesten.length && (!stiefel || t - (stiefelZeit || 0) > 20)) { stiefel = stiefelStellen(); stiefelZeit = t; }
                if (!stiefel) return;
                const anteil = tagAnteil(t0, t);
                zeitrafferUhr(anteil);
                for (const st of stiefel) {
                    // Reste am Boden (hinter dem Stiefel gezeichnet, damit er vorne steht)
                    for (const s2 of st.inhalt) {
                        if (anteil >= s2.ab) restMalen(cxV, s2.art, s2.farbe, st.x + st.w / 2 + s2.restX, st.boden, s2.restDreh, st.s);
                    }
                    // noch nicht gegessene Süßigkeiten ragen oben heraus
                    st.inhalt.forEach((s2, i) => {
                        if (anteil >= s2.ab) return;
                        const n = st.inhalt.length;
                        const off = st.blick > 0 ? 0.32 : 0.68;
                        const sx = st.x + st.w * (off + (i - (n - 1) / 2) * 0.13 + s2.dx * 0.5);
                        suessesMalen(cxV, s2.art, s2.farbe, sx, st.boden - st.h + ((1 - s2.hoch) * 0.35 + 0.35) * VW * st.s, s2.kipp, st.s);
                    });
                    stiefelMalen(cxV, st, t);
                }
            },
        };
    }

    // ==================================================================
    // SCHULTERMINE (auf „Monitore verwalten“ eingetragen)

    // Kinder des Chors: rotes Gewand, weißer Kragen, Liederbuch; Maßstab: 1 Einheit = 0,1 vw
    const CHOR_HAAR = ['#7a3b14', '#1f1a17', '#d8b45a', '#5a3a22'], CHOR_HAUT = ['#f2c9a8', '#c99a74', '#f6d7bf', '#e0b48e'];
    function chorKind(g, x, y, i, t) {
        const e = 0.1 * VW;
        g.save(); g.translate(x, y); g.scale(e, e);
        const wippen = Math.sin(t * 6 + i) * 1.2;
        g.translate(0, wippen - 64);
        g.fillStyle = '#c8202e';
        g.beginPath(); g.moveTo(-14, 62); g.lineTo(-10, 18); g.bezierCurveTo(-8, 8, 8, 8, 10, 18); g.lineTo(14, 62); g.closePath(); g.fill();
        g.fillStyle = '#fffaf0';
        g.beginPath(); g.moveTo(-14, 22); g.bezierCurveTo(-6, 30, 6, 30, 14, 22); g.lineTo(12, 30); g.bezierCurveTo(4, 36, -4, 36, -12, 30); g.closePath(); g.fill();
        g.fillStyle = CHOR_HAUT[i % 4]; g.beginPath(); g.arc(0, 6, 10, 0, 6.283); g.fill();
        g.fillStyle = CHOR_HAAR[i % 4];
        g.beginPath(); g.moveTo(-10, 3); g.bezierCurveTo(-10, -8, 10, -8, 10, 3); g.bezierCurveTo(6, -1, -6, -1, -10, 3); g.fill();
        // singender Mund
        g.fillStyle = '#9c3b2c'; g.beginPath(); g.ellipse(0, 10.5, 2.6, 2 + Math.abs(Math.sin(t * 5 + i)) * 1.4, 0, 0, 6.283); g.fill();
        g.fillStyle = '#2e3f5c'; g.fillRect(-12, 30, 18, 12);
        g.strokeStyle = '#ffffff'; g.lineWidth = 1; g.beginPath(); g.moveTo(-3, 30); g.lineTo(-3, 42); g.stroke();
        g.restore();
    }
    function notenZeichen(g, x, y, gr, art, farbe) {
        g.save(); g.translate(x, y); g.fillStyle = farbe; g.strokeStyle = farbe; g.lineWidth = gr * 0.16;
        g.beginPath(); g.ellipse(0, 0, gr * 0.5, gr * 0.36, -0.35, 0, 6.283); g.fill();
        g.beginPath(); g.moveTo(gr * 0.45, -gr * 0.1); g.lineTo(gr * 0.45, -gr * 2);
        if (art === 1) g.lineTo(gr * 1.2, -gr * 1.5);
        g.stroke();
        if (art === 2) {
            g.beginPath(); g.ellipse(gr * 1.6, gr * 0.3, gr * 0.5, gr * 0.36, -0.35, 0, 6.283); g.fill();
            g.beginPath(); g.moveTo(gr * 2.05, gr * 0.2); g.lineTo(gr * 2.05, -gr * 1.7); g.moveTo(gr * 0.45, -gr * 2); g.lineTo(gr * 2.05, -gr * 1.7); g.stroke();
        }
        g.restore();
    }

    // ADVENTSKONZERT: goldenes Notenband hinter den Kacheln, Noten wandern darauf;
    // alle 3–5 Minuten zieht ein singender Kinderchor unten durch (ohne Banner)
    function Adventskonzert() {
        const advent = Weihnachten(false);
        const noten = [];
        for (let i = 0; i < 12; i++) noten.push({x: zufall(0, 100), linie: Math.floor(zufall(0, 5)), art: Math.floor(zufall(0, 3)), p: zufall(0, 6.28)});
        let chor = null, chorNaechster = vorschau ? 1 : zufall(20, 60);
        const singen = [];
        const band = (x, t, i) => H * 0.38 + Math.sin(x / (W * 0.16) + t * 0.35) * 4 * VW + Math.sin(x / (W * 0.07) - t * 0.2) * 0.8 * VW + (i - 2) * 0.85 * VW;
        return {
            stop() { advent.stop(); },
            groesse() { advent.groesse(); },
            schritt(dt, t) {
                advent.schritt(dt, t);
                // fünf Notenlinien, hinter den Kacheln
                cxH.strokeStyle = opt.dunkel ? 'rgba(240,200,110,.75)' : 'rgba(205,160,40,.8)';
                cxH.lineWidth = 0.13 * VW;
                for (let i = 0; i < 5; i++) {
                    cxH.beginPath();
                    for (let x = 0; x <= W + 2 * VW; x += 1.5 * VW) { const y = band(x, t, i); if (x === 0) cxH.moveTo(x, y); else cxH.lineTo(x, y); }
                    cxH.stroke();
                }
                // Noten wandern auf dem Band, leuchten sanft
                for (const n of noten) {
                    n.x += 3 * dt; if (n.x > 104) { n.x = -4; n.linie = Math.floor(zufall(0, 5)); n.art = Math.floor(zufall(0, 3)); }
                    const x = n.x * VW, y = band(x, t, n.linie) - 0.42 * VW;
                    cxH.globalAlpha = 0.75 + 0.25 * Math.sin(t * 2 + n.p);
                    notenZeichen(cxH, x, y, 0.9 * VW, n.art, opt.dunkel ? '#ffd56b' : '#c8901c');
                }
                cxH.globalAlpha = 1;
                // Kinderchor
                chorNaechster -= dt;
                if (!chor && chorNaechster <= 0) {
                    const richtung = Math.random() < 0.5 ? 1 : -1;
                    chor = {richtung: richtung, x: richtung > 0 ? -16 * VW : W + 4 * VW, n: 3 + Math.floor(Math.random() * 2)};
                    chorNaechster = dauer(zufall(180, 300), 12);   // höchstens alle 3–5 Minuten
                }
                if (chor) {
                    chor.x += chor.richtung * 4.5 * VW * dt;
                    for (let i = 0; i < chor.n; i++) {
                        const kx = chor.x - chor.richtung * i * 4 * VW;
                        chorKind(cxV, kx, LAUF_BODEN - 0.1 * VW, i, t);
                        if (Math.random() < dt * 1.4) singen.push({x: kx, y: LAUF_BODEN - 6.5 * VW, alter: 0, art: Math.floor(zufall(0, 3)), dx: zufall(-1.5, 1.5) * VW});
                    }
                    const letzte = chor.x - chor.richtung * (chor.n - 1) * 4 * VW;
                    if ((chor.richtung > 0 && letzte > W + 3 * VW) || (chor.richtung < 0 && letzte < -3 * VW)) chor = null;
                }
                for (let i = singen.length - 1; i >= 0; i--) {
                    const n = singen[i];
                    n.alter += dt;
                    if (n.alter > 2.6) { singen.splice(i, 1); continue; }
                    cxV.globalAlpha = Math.min(1, (2.6 - n.alter) / 0.8);
                    notenZeichen(cxV, n.x + n.dx * n.alter + Math.sin(n.alter * 3) * 0.5 * VW, n.y - n.alter * 3 * VW, 0.75 * VW, n.art, '#d9a92e');
                }
                cxV.globalAlpha = 1;
            },
        };
    }

    // FORSCHERTAG (nur Klassen 5 und 6): Geistesblitze – an den Kachelkanten dieser Klassen
    // gehen Glühbirnen an, aus denen Symbole aller Fachbereiche aufsteigen. Alle anderen
    // Kacheln bleiben normal (Wunsch Jonas).
    const SYMBOLE = ['reagenzglas', 'kamera', 'globus', 'note'];
    // was in den Kacheln auftaucht: Glühbirne (mit aufsteigendem Symbol) und Forscherdinge
    const FORSCHERDINGE = ['birne', 'filmrolle', 'kolben', 'buch', 'birne', 'globus', 'kamera', 'note'];
    function Forschertag() {
        const birnen = [];
        let naechsteBirne = 0.5, symbolNr = 0, dingNr = 0, reihe = [];
        // Kacheln der Klassenstufen 5 und 6 (am Kiesel erkennbar: „5a“, „6d“ …)
        const forscherKacheln = () => kaesten.filter((k) => {
            const kiesel = opt.kiesel ? k.el.querySelector(`:scope > ${opt.kiesel}`) : null;
            return /^\s*[56](\D|$)/.test(kiesel ? kiesel.textContent : '');
        });
        function birneMalen(g, x, y, hell, gr) {
            const e = gr / 20;
            g.save(); g.translate(x, y); g.scale(e, e);
            if (hell > 0.05) {
                g.globalAlpha = hell * 0.5; g.fillStyle = '#fff3a0'; g.beginPath(); g.arc(0, -8, 16, 0, 6.283); g.fill();
                g.globalAlpha = hell; g.strokeStyle = '#f2b31c'; g.lineWidth = 1.6; g.lineCap = 'round';
                g.beginPath(); g.moveTo(-15, -14); g.lineTo(-20, -17); g.moveTo(15, -14); g.lineTo(20, -17); g.moveTo(0, -24); g.lineTo(0, -30);
                g.moveTo(-12, -24); g.lineTo(-15, -28); g.moveTo(12, -24); g.lineTo(15, -28); g.stroke();
            }
            g.globalAlpha = 1;
            g.fillStyle = hell > 0.05 ? '#ffe680' : '#f4f1e6'; g.strokeStyle = '#c8a020'; g.lineWidth = 1.2;
            g.beginPath(); g.moveTo(-8, -8); g.bezierCurveTo(-8, -20, 8, -20, 8, -8); g.bezierCurveTo(8, -2, 4, 0, 4, 4); g.lineTo(-4, 4); g.bezierCurveTo(-4, 0, -8, -2, -8, -8); g.closePath(); g.fill(); g.stroke();
            g.fillStyle = '#8a96a3'; g.fillRect(-4, 4, 8, 5);
            g.restore();
        }
        function symbolMalen(g, art, x, y, gr, t) {
            const e = gr / 24;
            g.save(); g.translate(x, y); g.scale(e, e);
            if (art === 'reagenzglas') {
                g.strokeStyle = '#2f7d9c'; g.lineWidth = 2; g.beginPath(); g.moveTo(-4, -14); g.lineTo(-4, 8); g.bezierCurveTo(-4, 14, 4, 14, 4, 8); g.lineTo(4, -14); g.stroke();
                g.fillStyle = '#5bbbd6'; g.beginPath(); g.moveTo(-3, 0); g.lineTo(3, 0); g.lineTo(3, 8); g.bezierCurveTo(3, 12, -3, 12, -3, 8); g.fill();
                g.beginPath(); g.arc(1, -20 - (t * 8) % 8, 1.8, 0, 6.283); g.fill();
            } else if (art === 'kamera') {
                g.fillStyle = '#3a3f48'; g.fillRect(-12, -6, 20, 14);
                g.beginPath(); g.moveTo(8, -2); g.lineTo(16, -6); g.lineTo(16, 10); g.lineTo(8, 6); g.fill();
                g.strokeStyle = '#3a3f48'; g.lineWidth = 2; g.beginPath(); g.arc(-6, -12, 6, 0, 6.283); g.moveTo(10, -12); g.arc(4, -12, 6, 0, 6.283); g.stroke();
            } else if (art === 'globus') {
                g.rotate(Math.sin(t) * 0.2);
                g.fillStyle = '#5aa2d8'; g.beginPath(); g.arc(0, 0, 12, 0, 6.283); g.fill();
                g.fillStyle = '#4caf6a';
                g.beginPath(); g.ellipse(-4, -3, 4, 5, 0.4, 0, 6.283); g.fill();
                g.beginPath(); g.ellipse(5, -4, 3, 5, -0.3, 0, 6.283); g.fill();
                g.beginPath(); g.ellipse(2, 6, 4, 2.5, 0, 0, 6.283); g.fill();
            } else if (art === 'filmrolle') {
                // Spule dreht sich, ein Stück Filmstreifen hängt heraus
                g.fillStyle = '#3a3f48'; g.fillRect(0, 4, 18, 8);
                g.fillStyle = '#e9eef3'; for (let i = 0; i < 4; i++) { g.fillRect(2 + i * 4.4, 5, 2, 1.6); g.fillRect(2 + i * 4.4, 9.4, 2, 1.6); }
                g.save(); g.rotate(t * 2.2);
                g.fillStyle = '#5a6470'; g.beginPath(); g.arc(0, 0, 11, 0, 6.283); g.fill();
                g.fillStyle = '#e9eef3'; for (let i = 0; i < 5; i++) { const w = i / 5 * 6.283; g.beginPath(); g.arc(Math.cos(w) * 6, Math.sin(w) * 6, 2.6, 0, 6.283); g.fill(); }
                g.fillStyle = '#3a3f48'; g.beginPath(); g.arc(0, 0, 2.2, 0, 6.283); g.fill();
                g.restore();
            } else if (art === 'kolben') {
                // Erlenmeyerkolben mit bunter Flüssigkeit, Bläschen steigen auf
                g.fillStyle = '#7ee0a0'; g.beginPath(); g.moveTo(-9, 12); g.lineTo(9, 12); g.lineTo(4, 3); g.lineTo(-4, 3); g.closePath(); g.fill();
                g.strokeStyle = '#2f7d9c'; g.lineWidth = 1.8; g.lineJoin = 'round';
                g.beginPath(); g.moveTo(-3, -12); g.lineTo(-3, -2); g.lineTo(-11, 12); g.lineTo(11, 12); g.lineTo(3, -2); g.lineTo(3, -12); g.stroke();
                g.beginPath(); g.moveTo(-5, -12); g.lineTo(5, -12); g.stroke();
                g.fillStyle = '#7ee0a0';
                for (let i = 0; i < 3; i++) { const u = (t * 0.9 + i / 3) % 1; g.globalAlpha *= 1; g.beginPath(); g.arc(Math.sin(u * 9 + i) * 2, -12 - u * 14, 1.2 + u * 1.4, 0, 6.283); g.fill(); }
            } else if (art === 'buch') {
                // aufgeschlagenes Buch, eine Seite blättert um
                g.fillStyle = '#c8202e'; g.beginPath(); g.moveTo(-15, 8); g.lineTo(0, 10); g.lineTo(15, 8); g.lineTo(15, -6); g.lineTo(0, -4); g.lineTo(-15, -6); g.closePath(); g.fill();
                g.fillStyle = '#fffaf0'; g.beginPath(); g.moveTo(-13, 6); g.lineTo(0, 8); g.lineTo(0, -5); g.lineTo(-13, -7); g.closePath(); g.fill();
                g.beginPath(); g.moveTo(13, 6); g.lineTo(0, 8); g.lineTo(0, -5); g.lineTo(13, -7); g.closePath(); g.fill();
                g.strokeStyle = '#b8c2cc'; g.lineWidth = 0.8;
                for (let i = 0; i < 3; i++) { g.beginPath(); g.moveTo(-10, -2 + i * 3); g.lineTo(-3, -1 + i * 3); g.moveTo(3, -1 + i * 3); g.lineTo(10, -2 + i * 3); g.stroke(); }
                const blatt = Math.cos((t * 1.4) % 3.1416);   // 1 = rechts, -1 = links
                g.fillStyle = '#ffffff'; g.strokeStyle = '#d0d6dc';
                g.beginPath(); g.moveTo(0, 8); g.lineTo(0, -5); g.lineTo(13 * blatt, -7 - Math.abs(Math.sin((t * 1.4) % 3.1416)) * 4); g.lineTo(13 * blatt, 6); g.closePath(); g.fill(); g.stroke();
            } else {
                notenZeichen(g, -4, 6, 10, 1, '#a259d9');
            }
            g.restore();
        }
        return {
            stop() {},
            schritt(dt, t) {
                // Geistesblitze an zufälligen Kachelkanten (oben, in der Lücke), höchstens fünf zugleich
                naechsteBirne -= dt;
                // Geistesblitze reihum in allen Kacheln der Klassen 5 und 6: die Birne erscheint in
                // einer freien Ecke der Kachel (ohne Schrift), das Symbol steigt so weit auf, wie Platz ist
                if (naechsteBirne <= 0 && birnen.length < 7) {
                    if (!reihe.length) {
                        reihe = forscherKacheln().map((k) => k.el);
                        for (let i = reihe.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [reihe[i], reihe[j]] = [reihe[j], reihe[i]]; }
                    }
                    const el = reihe.shift();
                    const k = kaesten.find((kk) => kk.el === el);
                    if (k) {
                        const b0 = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
                        const texte = [];
                        const bereich = document.createRange();
                        const gang = document.createTreeWalker(k.el, NodeFilter.SHOW_TEXT);
                        for (let n = gang.nextNode(); n; n = gang.nextNode()) {
                            if (!n.textContent.trim()) continue;
                            bereich.selectNodeContents(n);
                            for (const r of bereich.getClientRects()) texte.push({l: r.left - b0.left, r: r.right - b0.left, t: r.top - b0.top, b: r.bottom - b0.top});
                        }
                        const y = k.y + k.h - 0.9 * VW;
                        const hub = Math.max(0, Math.min(4 * VW, y - 3.1 * VW - (k.y + 0.3 * VW)));
                        const start = zufall(0, 1);
                        for (let versuch = 0; versuch < 14; versuch++) {
                            // von rechts nach links, mit zufälligem Versatz
                            const x = k.x + k.w - 1.6 * VW - ((start + versuch) % 14) / 14 * (k.w - 3.2 * VW);
                            const weg = {l: x - 1.4 * VW, r: x + 1.4 * VW, t: y - 3.1 * VW - hub, b: y + 0.75 * VW};
                            if (texte.some((t2) => t2.l < weg.r && t2.r > weg.l && t2.t < weg.b && t2.b > weg.t)) continue;
                            const ding = FORSCHERDINGE[dingNr++ % FORSCHERDINGE.length];
                            birnen.push({x: x, y: y, hub: hub, alter: 0, ding: ding, symbol: SYMBOLE[symbolNr++ % SYMBOLE.length]});
                            break;
                        }
                    }
                    naechsteBirne = dauer(zufall(0.8, 1.6), zufall(0.5, 0.9));
                }
                for (let i = birnen.length - 1; i >= 0; i--) {
                    const b = birnen[i];
                    b.alter += dt;
                    if (b.alter > 4.2) { birnen.splice(i, 1); continue; }
                    const auf = Math.min(1, b.alter / 0.25), ab = b.alter > 3.4 ? Math.max(0, 1 - (b.alter - 3.4) / 0.8) : 1;
                    const hell = b.alter < 0.25 ? auf : (b.alter < 2.6 ? 0.8 + 0.2 * Math.sin(b.alter * 9) : Math.max(0, 1 - (b.alter - 2.6) / 0.6));
                    if (b.ding !== 'birne') {
                        // Forscherding: springt auf, schwebt ein wenig nach oben, verblasst
                        const pop = b.alter < 0.3 ? b.alter / 0.3 : 1 + Math.max(0, 0.12 - Math.abs(b.alter - 0.4)) ;
                        cxV.globalAlpha = ab;
                        cxV.save(); cxV.translate(b.x, b.y - 1.1 * VW - Math.min(1, b.alter / 4) * b.hub * 0.5); cxV.scale(pop, pop);
                        symbolMalen(cxV, b.ding, 0, 0, 2.3 * VW, t);
                        cxV.restore();
                        cxV.globalAlpha = 1;
                        continue;
                    }
                    cxV.globalAlpha = ab;
                    birneMalen(cxV, b.x, b.y, hell, 1.6 * VW);
                    // das Symbol steigt aus der Birne auf
                    if (b.alter > 0.35) {
                        const s2 = b.alter - 0.35;
                        cxV.globalAlpha = Math.min(1, s2 / 0.3) * Math.max(0, 1 - s2 / 3.8);
                        symbolMalen(cxV, b.symbol, b.x + Math.sin(s2 * 2) * 0.4 * VW, b.y - 2.2 * VW - Math.min(1, s2 / 3.8) * b.hub, 1.8 * VW, t);
                    }
                    cxV.globalAlpha = 1;
                }
            },
        };
    }

    function hexRgba(hex, a) {
        const n = parseInt(hex.slice(1), 16);
        return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
    }

    function birnenSprite(farbe) {
        const w = Math.ceil(0.6 * VW * DPR), h = Math.ceil(0.9 * VW * DPR);
        const c = leinwand(w, h);
        const g = c.getContext('2d');
        // Fassung
        g.fillStyle = '#2b3a2f';
        g.fillRect(w * 0.3, 0, w * 0.4, h * 0.24);
        // Glas
        const f = g.createRadialGradient(w * 0.4, h * 0.5, 0, w * 0.5, h * 0.55, w * 0.55);
        f.addColorStop(0, '#ffffff');
        f.addColorStop(0.35, farbe);
        f.addColorStop(1, farbe);
        g.fillStyle = f;
        g.beginPath();
        g.moveTo(w * 0.28, h * 0.22);
        g.bezierCurveTo(w * 0.02, h * 0.45, w * 0.1, h * 0.95, w * 0.5, h * 0.98);
        g.bezierCurveTo(w * 0.9, h * 0.95, w * 0.98, h * 0.45, w * 0.72, h * 0.22);
        g.closePath();
        g.fill();
        g.fillStyle = 'rgba(255,255,255,.7)';
        g.beginPath();
        g.ellipse(w * 0.36, h * 0.48, w * 0.08, h * 0.12, 0.3, 0, 6.283);
        g.fill();
        return c;
    }

    function rentier(x, y, nr, rudolph) {
        const v = `${(-nr * 0.15).toFixed(2)}s`;
        const fell = 'url(#fx-fell)';
        const bein = (hx, hy, hinten, fern) =>
            `<g class="fx-bein${hinten ? ' fx-hinten' : ''}" style="--v:${fern ? `${(-nr * 0.15 - 0.12).toFixed(2)}s` : v}">` +
            `<path d="M${hx - 2.6},${hy} L${hx - 1.7},${hy + 17} L${hx + 1.7},${hy + 17} L${hx + 2.6},${hy} Z" fill="${fern ? '#5b3820' : fell}"/>` +
            `<path d="M${hx - 2},${hy + 16.5} L${hx + 2.2},${hy + 16.5} L${hx + 2.4},${hy + 20} L${hx - 2.2},${hy + 20} Z" fill="#2b1a10"/></g>`;
        const nase = rudolph
            ? `<circle cx="45" cy="-22.5" r="7" fill="url(#fx-nasenglanz)" class="fx-nasenlicht"/><circle cx="44.6" cy="-22.6" r="2.6" fill="#e3262f"/><circle cx="43.8" cy="-23.4" r=".8" fill="#fff" opacity=".8"/>`
            : `<circle cx="44.6" cy="-22.6" r="2.1" fill="#2b1a10"/>`;
        return `<g transform="translate(${x},${y})">
            ${bein(13, 4, false, true)}${bein(-16, 4, true, true)}
            <ellipse cx="-24" cy="-4" rx="4.2" ry="3" fill="#f2e3cc"/>
            <ellipse cx="0" cy="0" rx="24" ry="11" fill="${fell}"/>
            <ellipse cx="3" cy="5.5" rx="17" ry="4.6" fill="#d7b48a" opacity=".55"/>
            ${bein(15, 4, false, false)}${bein(-14, 4, true, false)}
            <g class="fx-kopfnicken" style="--v:${v}">
                <path d="M13,-7 C19,-13 21,-19 25,-25 L33,-21 C30,-15 26,-7 22,-1 Z" fill="${fell}"/>
                <path d="M30,-30 C28,-37 24,-42 19,-46 M26,-37.5 L21.5,-38.5 M24,-41.5 C25,-46 27,-48 29,-51" stroke="#e2cda6" stroke-width="2.2" fill="none" stroke-linecap="round"/>
                <path d="M33.5,-31 C34.5,-39 37,-44 41.5,-47.5 M35.5,-38 L40,-38.5 M37.5,-43 L37,-48.5" stroke="#cdb48c" stroke-width="2.2" fill="none" stroke-linecap="round"/>
                <ellipse cx="34" cy="-25" rx="8.5" ry="6.2" fill="${fell}" transform="rotate(-12 34 -25)"/>
                <ellipse cx="40.5" cy="-22.3" rx="5.2" ry="3.8" fill="#a77a52"/>
                <ellipse cx="27.5" cy="-30" rx="4.6" ry="1.8" fill="#6b4429" transform="rotate(-35 27.5 -30)"/>
                <circle cx="35.5" cy="-27.2" r="1.25" fill="#1a0f08"/><circle cx="35.9" cy="-27.6" r=".4" fill="#fff"/>
                ${nase}
                <path d="M19,-15 C22,-11 26,-12 28,-16" stroke="#b8202c" stroke-width="2.6" fill="none"/>
                <circle cx="24" cy="-11.5" r="2" fill="url(#fx-gold)"/>
            </g>
        </g>`;
    }

    function schlittenSvg() {
        const tiere = [];
        for (let i = 0; i < 4; i++) tiere.push(rentier(178 + i * 70, 84 - i * 6, i, i === 3));
        const leine = 'M110.5,61 C140,74 165,78 202,72.5 L272,66.5 L342,60.5 L412,54.5';
        return `<svg class="fx-schlitten-flug" viewBox="0 0 480 150" xmlns="${NS}">
        <defs>
            <linearGradient id="fx-fell" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#a06f48"/><stop offset="1" stop-color="#6b4429"/></linearGradient>
            <linearGradient id="fx-rot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d81f36"/><stop offset="1" stop-color="#8b0d1f"/></linearGradient>
            <linearGradient id="fx-mantel" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e8303f"/><stop offset="1" stop-color="#a5101f"/></linearGradient>
            <linearGradient id="fx-gold" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe59a"/><stop offset=".5" stop-color="#e9b949"/><stop offset="1" stop-color="#b9862a"/></linearGradient>
            <linearGradient id="fx-sack" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#8a5a35"/><stop offset="1" stop-color="#5a371d"/></linearGradient>
            <radialGradient id="fx-nasenglanz"><stop offset="0" stop-color="#ff4b4b" stop-opacity=".9"/><stop offset="1" stop-color="#ff4b4b" stop-opacity="0"/></radialGradient>
        </defs>
        <path d="${leine}" stroke="#c99b3c" stroke-width="1.4" fill="none" opacity=".9"/>
        ${tiere.join('')}
        <g transform="translate(8,44)">
            <path d="M12,32 C4,14 16,-6 33,-4 C46,-3 52,9 48,23 C47,29 45,33 42,35 Z" fill="url(#fx-sack)"/>
            <path d="M22,-1 C26,2 33,2 38,-1" stroke="#3d2412" stroke-width="1.6" fill="none"/>
            <g transform="rotate(-14 27 -6)"><rect x="20" y="-14" width="14" height="13" rx="1.5" fill="#2f7d5b"/><rect x="25.6" y="-14" width="2.8" height="13" fill="#f2d16b"/></g>
            <g transform="rotate(10 41 -3)"><rect x="35" y="-9" width="12" height="11" rx="1.5" fill="#3a74c9"/><rect x="35" y="-4.6" width="12" height="2.4" fill="#fff"/></g>
            <g class="fx-winken"><path d="M55,15 C50,8 46,2 45,-5" stroke="url(#fx-mantel)" stroke-width="6.5" stroke-linecap="round" fill="none"/>
                <circle cx="44.6" cy="-6" r="3.4" fill="#fff"/><circle cx="44.2" cy="-9.4" r="3.3" fill="#2f6b4f"/></g>
            <path d="M49,38 C47,22 53,7 66,5 C79,7 85,22 83,38 Z" fill="url(#fx-mantel)"/>
            <path d="M65,6 L66.5,38" stroke="#fff" stroke-width="3.2" opacity=".95"/>
            <rect x="50" y="27" width="32" height="4.6" fill="#24150f"/>
            <rect x="62.5" y="26" width="7" height="6.6" rx="1" fill="none" stroke="url(#fx-gold)" stroke-width="1.6"/>
            <path d="M75,16 C85,18 93,20 99,18" stroke="url(#fx-mantel)" stroke-width="6.5" stroke-linecap="round" fill="none"/>
            <circle cx="99" cy="18" r="3.5" fill="#fff"/><circle cx="102.5" cy="17.2" r="3.3" fill="#2f6b4f"/>
            <circle cx="66" cy="-1" r="8" fill="#f6cfb2"/>
            <path d="M57,-1 C55.5,10 61.5,17 66,17 C72,17 77.5,9 75.5,-1 C72,3 61,3 57,-1 Z" fill="#fbfbfb" stroke="#e2e6ea" stroke-width=".6"/>
            <path d="M60,2.6 C63,0.6 65,1.6 66.2,2.8 C67.4,1.6 70,0.6 72.6,2.6 C69.6,5.8 63.4,5.8 60,2.6 Z" fill="#ffffff" stroke="#dde2e6" stroke-width=".5"/>
            <circle cx="66.7" cy="0.8" r="1.9" fill="#ea9c8c"/>
            <circle cx="69.6" cy="-3" r="1.05" fill="#24150f"/>
            <circle cx="71.2" cy="0.6" r="2.1" fill="#f19a9a" opacity=".45"/>
            <g class="fx-bommel"><path d="M58,-7 C57,-16 66,-21 75,-10 L76,-8 Z" fill="url(#fx-rot)"/>
                <path d="M61,-14 C55,-20 46,-19 42,-12 C48,-14 54,-12 58,-8 Z" fill="url(#fx-rot)"/>
                <circle cx="42" cy="-11.5" r="3.4" fill="#fff"/></g>
            <rect x="56" y="-9.5" width="21" height="5" rx="2.5" fill="#fff"/>
            <path d="M6,64 C0,46 0,22 8,12 C12,7 20,8 21,16 L24,36 L92,36 C100,36 108,42 112,50 C116,58 110,64 102,64 Z" fill="url(#fx-rot)"/>
            <path d="M10,60 C5,44 5,26 10,16 M24,38.5 L92,38.5 C99,38.5 105,43 108.5,50" stroke="url(#fx-gold)" stroke-width="2.4" fill="none" stroke-linecap="round"/>
            <path d="M40,55 c5,-9 17,-9 19,-1 c2,6 -6,9 -8.5,4.5 c-1.4,-3 2,-4.5 3.4,-2.2 M62,55 c5,-9 17,-9 19,-1 c2,6 -6,9 -8.5,4.5 c-1.4,-3 2,-4.5 3.4,-2.2" stroke="url(#fx-gold)" stroke-width="1.6" fill="none" stroke-linecap="round"/>
            <path d="M24,64 L22,74 M82,64 L84,74" stroke="#b98b35" stroke-width="2.6"/>
            <path d="M-4,74 L96,74 C112,74 122,66 119,56 C117,49 108,50 109,57" stroke="url(#fx-gold)" stroke-width="3.2" fill="none" stroke-linecap="round"/>
        </g>
    </svg>`;
    }

    // ==================================================================
    // OSTERN: der Osterhase hoppelt vorbei und versteckt Eier hinter den Kästen

    const GESCHENK_FARBEN = [['#c8102e', '#f2c14e'], ['#1f7a4d', '#ffffff'], ['#2f5fa8', '#f2c14e'], ['#f2c14e', '#c8102e'], ['#7a3f98', '#ffffff']];
    function geschenkSvg() {
        const [papier, band] = auswahl(GESCHENK_FARBEN);
        const id = neueId('geschenk');
        return `<svg viewBox="0 0 40 42" xmlns="${NS}">
            <defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffffff" stop-opacity=".35"/><stop offset=".4" stop-color="${papier}" stop-opacity="0"/></linearGradient></defs>
            <ellipse cx="20" cy="40" rx="17" ry="2.5" fill="rgba(0,0,0,.22)"/>
            <rect x="5" y="16" width="30" height="23" rx="1.5" fill="${papier}"/>
            <rect x="5" y="16" width="30" height="23" rx="1.5" fill="url(#${id})"/>
            <rect x="3" y="11" width="34" height="7" rx="1.5" fill="${papier}" stroke="rgba(0,0,0,.18)" stroke-width=".6"/>
            <rect x="17.5" y="11" width="5" height="28" fill="${band}"/>
            <rect x="3" y="13" width="34" height="3" fill="${band}" opacity=".9"/>
            <path d="M20,11 C14,2 6,5 10,10 C12,12 17,12 20,11 Z M20,11 C26,2 34,5 30,10 C28,12 23,12 20,11 Z" fill="${band}" stroke="rgba(0,0,0,.2)" stroke-width=".6"/>
            <circle cx="20" cy="11" r="2.4" fill="${band}" stroke="rgba(0,0,0,.25)" stroke-width=".6"/>
        </svg>`;
    }

    const EI_FARBEN = [
        ['#f7a8c4', '#e0558a'], ['#8fd6c8', '#2f9c88'], ['#ffd56e', '#e39a1c'],
        ['#a9c6f2', '#3f72c6'], ['#cdaaf0', '#8150c4'], ['#ffb98f', '#e0663a'],
    ];

    function eiSvg() {
        const [hell, kraeftig] = auswahl(EI_FARBEN);
        const id = neueId('ei');
        const muster = auswahl(['zickzack', 'punkte', 'streifen', 'wellen']);
        const umriss = 'M20,2 C31,2 38,20 38,32 C38,44 30,50 20,50 C10,50 2,44 2,32 C2,20 9,2 20,2 Z';
        let deko = '';
        if (muster === 'zickzack') {
            let p = 'M0,28'; for (let x = 0; x <= 40; x += 5) p += ` L${x},${x % 10 === 0 ? 24 : 31}`;
            deko = `<path d="${p}" stroke="#fff" stroke-width="2.6" fill="none"/><rect x="0" y="35" width="40" height="3.5" fill="${kraeftig}"/><rect x="0" y="16" width="40" height="2.5" fill="${kraeftig}"/>`;
        } else if (muster === 'punkte') {
            for (const [x, y, r] of [[12, 16, 2.6], [26, 13, 2.2], [20, 26, 3], [9, 32, 2.4], [31, 30, 2.6], [16, 41, 2.2], [28, 42, 2]]) {
                deko += `<circle cx="${x}" cy="${y}" r="${r}" fill="${Math.random() < 0.5 ? '#fff' : kraeftig}"/>`;
            }
        } else if (muster === 'streifen') {
            deko = `<rect x="0" y="14" width="40" height="5" fill="${kraeftig}"/><rect x="0" y="22" width="40" height="2" fill="#fff"/><rect x="0" y="33" width="40" height="5" fill="${kraeftig}"/><rect x="0" y="40" width="40" height="2" fill="#fff"/>`;
        } else {
            let p = 'M0,24'; for (let x = 0; x <= 40; x += 10) p += ` q2.5,-4 5,0 q2.5,4 5,0`;
            let q = 'M0,36'; for (let x = 0; x <= 40; x += 10) q += ` q2.5,-4 5,0 q2.5,4 5,0`;
            deko = `<path d="${p}" stroke="${kraeftig}" stroke-width="3" fill="none"/><path d="${q}" stroke="#fff" stroke-width="2.4" fill="none"/><circle cx="20" cy="14" r="2.4" fill="#fff"/>`;
        }
        return `<svg viewBox="0 0 40 54" xmlns="${NS}">
            <defs>
                <radialGradient id="${id}-f" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#fff" stop-opacity=".9"/><stop offset=".25" stop-color="${hell}"/><stop offset="1" stop-color="${kraeftig}"/></radialGradient>
                <clipPath id="${id}-c"><path d="${umriss}"/></clipPath>
                <radialGradient id="${id}-s"><stop offset="0" stop-color="#000" stop-opacity=".3"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>
            </defs>
            <ellipse cx="21" cy="50.5" rx="16" ry="3.2" fill="url(#${id}-s)"/>
            <path d="${umriss}" fill="url(#${id}-f)"/>
            <g clip-path="url(#${id}-c)" opacity=".92">${deko}</g>
            <path d="${umriss}" fill="none" stroke="rgba(0,0,0,.12)" stroke-width="1"/>
            <ellipse cx="13" cy="15" rx="4" ry="7" fill="#fff" opacity=".45" transform="rotate(25 13 15)"/>
        </svg>`;
    }

    function haseSvg() {
        return `<svg class="fx-hase" viewBox="0 0 140 140" xmlns="${NS}" style="overflow: visible">
        <defs>
            <linearGradient id="fx-hasenfell" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#d7aa7a"/><stop offset="1" stop-color="#b98654"/></linearGradient>
            <linearGradient id="fx-korb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c58b4e"/><stop offset="1" stop-color="#8d5a2b"/></linearGradient>
        </defs>
        <ellipse class="fx-schatten" cx="64" cy="134" rx="34" ry="4.5" fill="rgba(0,0,0,.2)"/>
        <g class="fx-teil fx-koerper" style="transform-origin: 50% 100%">
            <circle cx="30" cy="92" r="10" fill="#fffaf3"/><circle cx="27" cy="89" r="5" fill="#fff"/>
            <ellipse cx="46" cy="101" rx="21" ry="22" fill="url(#fx-hasenfell)"/>
            <ellipse cx="54" cy="125" rx="21" ry="6.5" fill="#b07c4c"/><ellipse cx="62" cy="123.5" rx="9" ry="3" fill="#f3e2cc" opacity=".8"/>
            <path d="M34,96 C30,70 46,52 66,52 C84,52 92,70 90,92 C88,112 70,124 56,124 C44,124 36,112 34,96 Z" fill="url(#fx-hasenfell)"/>
            <ellipse cx="79" cy="93" rx="10" ry="18" fill="#f5e6d3" transform="rotate(-12 79 93)"/>
            <g>
                <path d="M26,62 L54,62 L50,86 L30,86 Z" fill="url(#fx-korb)"/>
                <path d="M27,68 L53,68 M28,74 L52,74 M29,80 L51,80" stroke="#7a4a20" stroke-width="1.2" opacity=".7"/>
                <path d="M33,62 L34,86 M40,62 L40,86 M47,62 L46,86" stroke="#e0b07a" stroke-width="1" opacity=".55"/>
                <ellipse cx="32" cy="60" rx="5" ry="6.5" fill="#f7a8c4"/><ellipse cx="41" cy="58" rx="5" ry="6.5" fill="#8fd6c8"/><ellipse cx="49.5" cy="60" rx="5" ry="6.5" fill="#ffd56e"/>
                <path d="M26,62 C28,44 52,44 54,62" stroke="#8d5a2b" stroke-width="2.6" fill="none"/>
                <rect x="24.5" y="60.5" width="31" height="4" rx="2" fill="#a86f3a"/>
            </g>
            <ellipse cx="86" cy="119" rx="7.5" ry="4.6" fill="#c9965f"/><ellipse cx="78" cy="121" rx="7" ry="4.4" fill="#d7aa7a"/>
            <g class="fx-teil fx-kopf" style="transform-origin: 30% 80%">
                <g class="fx-teil fx-ohr-a" style="transform-origin: 50% 100%"><ellipse cx="74" cy="20" rx="7" ry="22" fill="#b98654" transform="rotate(-16 74 20)"/><ellipse cx="74.5" cy="21" rx="3.6" ry="16" fill="#f0b4bd" transform="rotate(-16 74.5 21)"/></g>
                <g class="fx-teil fx-ohr-b" style="transform-origin: 50% 100%"><ellipse cx="88" cy="17" rx="7.5" ry="23" fill="#d7aa7a" transform="rotate(9 88 17)"/><ellipse cx="88.3" cy="18" rx="3.8" ry="17" fill="#f5c1c8" transform="rotate(9 88.3 18)"/></g>
                <ellipse cx="86" cy="48" rx="19.5" ry="17" fill="url(#fx-hasenfell)"/>
                <ellipse cx="97.5" cy="55" rx="10.5" ry="8.2" fill="#f5e6d3"/>
                <ellipse class="fx-nase" cx="106" cy="50.5" rx="3.2" ry="2.4" fill="#e5899a"/>
                <path d="M104.5,54 q-2,3.4 -5.2,2.2" stroke="#7a5a48" stroke-width="1" fill="none" stroke-linecap="round"/>
                <ellipse cx="94" cy="42" rx="3" ry="3.7" fill="#2a1a14"/><circle cx="95.1" cy="40.7" r="1.15" fill="#fff"/>
                <ellipse cx="91.5" cy="52.5" rx="4.2" ry="2.5" fill="#f2a0a8" opacity=".5"/>
                <path d="M103,53 L118,50 M103,55 L118,56 M102,57 L115,61" stroke="#7a5a48" stroke-width=".6" opacity=".55"/>
            </g>
        </g>
    </svg>`;
    }

    function Ostern(nah) {
        let auftritt = null;
        let naechster = vorschau ? 1.5 : zufall(60, 240);
        const abstand = () => dauer(nah ? zufall(7, 9) * 60 : zufall(13, 17) * 60, 30);
        const eier = [];
        const MAX_EIER = 9;

        function versteck() {
            if (kaesten.length === 0) return null;
            const k = auswahl(kaesten);
            // halb hinter dem Kasten: zwischen den Spalten ist mehr Platz als zwischen den Zeilen
            const seite = auswahl(['rechts', 'rechts', 'links', 'unten', 'oben']);
            let dx, dy;
            if (seite === 'unten') { dx = zufall(0.2, 0.85) * k.w; dy = k.h - 1.2 * VW; }
            else if (seite === 'rechts') { dx = k.w - 0.9 * VW; dy = zufall(0.15, 0.7) * k.h; }
            else if (seite === 'links') { dx = -1.25 * VW; dy = zufall(0.35, 0.75) * k.h; }
            else { dx = zufall(0.3, 0.9) * k.w; dy = -1.7 * VW; }
            return {el: k.el, dx: dx / VW, dy: dy / VW, drehung: zufall(-28, 28)};
        }
        function eiVerstecken() {
            const v = versteck();
            if (!v) return;
            const box = document.createElement('div');
            box.className = 'fx-ei';
            box.innerHTML = eiSvg();
            box.firstChild.style.setProperty('--r', `${v.drehung.toFixed(0)}deg`);
            domH.appendChild(box);
            v.box = box;
            eier.push(v);
            if (eier.length > MAX_EIER) eier.shift().box.remove();
            eiSetzen(v);
            const r = box.getBoundingClientRect();
            const b = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            funkenStreuen(r.left - b.left + r.width / 2, r.top - b.top + r.height / 2, 14, 'bunt');
            funkenStreuen(r.left - b.left + r.width / 2, r.top - b.top + r.height / 2, 8, 'gold');
        }
        function eiSetzen(v) {
            if (!v.el.isConnected) {
                // Kasten wurde neu aufgebaut: neues Versteck suchen
                const n = versteck();
                if (!n) return;
                Object.assign(v, {el: n.el, dx: n.dx, dy: n.dy});
            }
            const r = v.el.getBoundingClientRect();
            const b = opt.fixiert ? {left: 0, top: 0} : buehne.getBoundingClientRect();
            v.box.style.transform = `translate(${r.left - b.left + v.dx * VW}px, ${r.top - b.top + v.dy * VW}px)`;
        }
        function hoppeln(t) {
            const el = svgAusText(haseSvg());
            domV.appendChild(el);
            const teile = {
                koerper: el.querySelector('.fx-koerper'), kopf: el.querySelector('.fx-kopf'),
                ohrA: el.querySelector('.fx-ohr-a'), ohrB: el.querySelector('.fx-ohr-b'),
                nase: el.querySelector('.fx-nase'), schatten: el.querySelector('.fx-schatten'),
            };
            const pause = zufall(30, 62);
            auftritt = {el: el, teile: teile, start: t, x: -9 * VW, pauseBei: pause * VW, phase: 'hin', huepfer: 0, pauseStart: 0, versteckt: 0};
        }
        function hasenSchritt(a, t, dt) {
            const breite = 8.5 * VW;
            const boden = LAUF_BODEN - breite - 0.4 * VW;
            const hopsDauer = 0.5;
            const hopsWeite = 5.2 * VW;
            let hoehe = 0, quetschen = 1, ohren = 0, kopf = 0;
            if (a.phase === 'hin' || a.phase === 'weg') {
                a.huepfer += dt / hopsDauer;
                const p = a.huepfer % 1;
                a.x += hopsWeite / hopsDauer * dt * (p < 0.12 || p > 0.9 ? 0.25 : 1.2);
                hoehe = Math.sin(Math.PI * Math.min(1, Math.max(0, (p - 0.1) / 0.8))) * 2.6 * VW;
                if (p < 0.12) quetschen = 0.88 + p;
                else if (p > 0.9) quetschen = 0.88 + (1 - p);
                else quetschen = 1.06;
                ohren = -24 * Math.sin(Math.PI * p);
                kopf = -4 * Math.sin(Math.PI * p);
                if (a.phase === 'hin' && a.x >= a.pauseBei && p > 0.9) {
                    a.phase = 'pause';
                    a.pauseStart = t;
                    a.huepfer = 0;
                }
                if (a.phase === 'weg' && a.x > W + 2 * VW) {
                    a.el.remove();
                    auftritt = null;
                    return;
                }
            } else if (a.phase === 'pause') {
                const s = t - a.pauseStart;
                // umschauen, Ohren zucken, Nase schnuppert – dann zwei Eier verstecken
                kopf = Math.sin(s * 2.2) * 6;
                ohren = (Math.sin(s * 9) > 0.8 ? 10 : 0) + Math.sin(s * 1.5) * 4;
                quetschen = 1 - 0.02 * Math.sin(s * 3);
                a.teile.nase.setAttribute('ry', (2.4 + Math.sin(s * 18) * 0.5).toFixed(2));
                if (s > 1.0 && a.versteckt === 0) { a.versteckt = 1; eiVerstecken(); }
                if (s > 1.8 && a.versteckt === 1) { a.versteckt = 2; if (Math.random() < 0.7) eiVerstecken(); }
                if (s > 3.2) a.phase = 'weg';
            }
            a.el.style.transform = `translate(${a.x}px, ${boden - hoehe}px)`;
            a.teile.koerper.style.transform = `scale(${(2 - quetschen).toFixed(3)}, ${quetschen.toFixed(3)})`;
            a.teile.kopf.style.transform = `rotate(${kopf.toFixed(1)}deg)`;
            a.teile.ohrA.style.transform = `rotate(${(ohren * 1.1).toFixed(1)}deg)`;
            a.teile.ohrB.style.transform = `rotate(${(ohren * 0.9 - 3).toFixed(1)}deg)`;
            // der Schatten bleibt am Boden und wird kleiner, je höher der Hase springt
            const sch = 1 - Math.min(0.6, hoehe / (5 * VW));
            const unten = hoehe / breite * 140;
            a.teile.schatten.setAttribute('transform', `translate(0 ${unten.toFixed(1)}) translate(64 134) scale(${sch.toFixed(3)}) translate(-64 -134)`);
        }
        return {
            stop() { if (auftritt) auftritt.el.remove(); for (const e of eier) e.box.remove(); },
            schritt(dt, t) {
                for (const e of eier) eiSetzen(e);
                naechster -= dt;
                if (!auftritt && naechster <= 0) {
                    hoppeln(t);
                    naechster = abstand();
                }
                if (auftritt) hasenSchritt(auftritt, t, dt);
            },
        };
    }

    // ==================================================================
    // VALENTINSTAG: Herzen steigen hinter den Kacheln auf; etwa alle 10 Minuten
    // schwebt ein Bündel Herzballons von unten durchs Bild.

    const HERZ_FARBEN = ['#e8344e', '#f06b8b', '#c81d4a', '#ff9db5'];
    function herzPfad(g, x, y, s) {
        g.beginPath();
        g.moveTo(x, y + s * 0.3);
        g.bezierCurveTo(x, y + s * 0.02, x - s * 0.5, y - s * 0.02, x - s * 0.5, y + s * 0.3);
        g.bezierCurveTo(x - s * 0.5, y + s * 0.6, x - s * 0.1, y + s * 0.72, x, y + s);
        g.bezierCurveTo(x + s * 0.1, y + s * 0.72, x + s * 0.5, y + s * 0.6, x + s * 0.5, y + s * 0.3);
        g.bezierCurveTo(x + s * 0.5, y - s * 0.02, x, y + s * 0.02, x, y + s * 0.3);
    }
    function herzSprite(farbe) {
        const s = Math.ceil(2 * VW * DPR);
        const c = leinwand(s, s);
        const g = c.getContext('2d');
        const f = g.createLinearGradient(0, 0, s, s);
        f.addColorStop(0, '#ffffff');
        f.addColorStop(0.25, farbe);
        f.addColorStop(1, farbe);
        g.fillStyle = f;
        herzPfad(g, s / 2, s * 0.05, s * 0.9);
        g.fill();
        g.fillStyle = 'rgba(255,255,255,.55)';
        g.beginPath(); g.ellipse(s * 0.33, s * 0.28, s * 0.07, s * 0.04, -0.6, 0, 6.283); g.fill();
        return c;
    }
    function herzballonsSvg() {
        const herz = (x, y, f, r) => `<g transform="translate(${x} ${y}) rotate(${r})"><path d="M0,6 C0,0 -10,-1 -10,6 C-10,12 -2,15 0,20 C2,15 10,12 10,6 C10,-1 0,0 0,6 Z" fill="${f}"/>
            <ellipse cx="-5" cy="4" rx="2" ry="1.2" fill="#fff" opacity=".6" transform="rotate(-30 -5 4)"/><path d="M0,20 l-1.5,2.5 h3 Z" fill="${f}"/></g>`;
        const kn = [40, 138];
        const hs = [[22, 18, '#e8344e', -12], [40, 6, '#f06b8b', 0], [58, 18, '#c81d4a', 12], [30, 34, '#ff9db5', -6], [50, 34, '#e8344e', 6]];
        const schnuere = hs.map(([x, y]) => `<path d="M${x},${y + 22} Q${(x + kn[0]) / 2 + 4},${(y + kn[1]) / 2} ${kn[0]},${kn[1]}" stroke="#7a6a6a" stroke-width=".7" fill="none"/>`).join('');
        return `<svg class="fx-herzballons" viewBox="0 0 80 140" xmlns="${NS}">${schnuere}${hs.map((h) => herz(...h)).join('')}
            <path d="M40,138 l-3,2 M40,138 l3,2" stroke="#e8344e" stroke-width="1.2"/></svg>`;
    }
    // Amor im Stil der rotfigurigen Vasenmalerei: terrakottafarbene Figur mit dunkler
    // Kontur, Flügel, Bogen. Blickrichtung rechts; Bogenspitze (Pfeilspitze) bei (92|38).
    const AMOR_B = 10, AMOR_SPITZE = [92, 38];
    function amorSvg() {
        const kontur = '#2a160c', haut = 'url(#fx-amor-haut)';
        const glied = (d, w) => `<path d="${d}" stroke="${kontur}" stroke-width="${w + 2.2}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>
            <path d="${d}" stroke="${haut}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
        const herzSpitze = (x, y, f) => `<path d="M${x + 6},${y} C${x + 2},${y + 4.5} ${x - 3},${y + 3.5} ${x - 2},${y} C${x - 3},${y - 3.5} ${x + 2},${y - 4.5} ${x + 6},${y} Z" fill="${f}" stroke="${kontur}" stroke-width=".7"/>`;
        return `<svg class="fx-amor" viewBox="0 0 100 90" xmlns="${NS}">
            <defs><linearGradient id="fx-amor-haut" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4ad73"/><stop offset="1" stop-color="#d4733a"/></linearGradient></defs>
            <g class="fx-amor-fluegel" style="animation-delay: -.1s" opacity=".9">
                <path d="M42,37 C34,15 16,7 6,13 C14,16 17,21 13,26 C21,27 24,32 20,38 C28,39 33,42 42,41 Z" fill="#e6d6bb" stroke="${kontur}" stroke-width="1.2"/>
            </g>
            ${glied('M45,58 C39,64 35,66 31,71', 7)}
            <ellipse cx="50" cy="48" rx="11.5" ry="12.5" fill="${haut}" stroke="${kontur}" stroke-width="1.3"/>
            <path d="M39.5,52 C47,57 56,56 61.5,50 L60.5,57 C54,61.5 46,61.5 40.5,58 Z" fill="#f7efe1" stroke="${kontur}" stroke-width="1.1"/>
            ${glied('M54,59 C57,66 53,72 46,74', 7.5)}
            <g class="fx-amor-fluegel">
                <path d="M45,37 C39,12 21,2 8,8 C17,11 20,17 15,22 C24,23 27,29 22,35 C30,36 36,40 45,42 Z" fill="#fbf5e8" stroke="${kontur}" stroke-width="1.3"/>
                <path d="M37,26 C29,20 23,17 16,16 M39,32 C31,28 26,26 20,26 M41,37 C35,35 30,34 25,34" stroke="#c7b08a" stroke-width="1" fill="none"/>
            </g>
            <g class="fx-amor-ruhe">${glied('M48,42 C44,47 44,52 47,55', 5)}</g>
            <g class="fx-amor-zug">${glied('M49,42 C43,40 42,36 46,35 C48,36 50,37 52,38', 5)}</g>
            <path d="M74,17 C87,26 87,50 74,59" stroke="#6e3c12" stroke-width="2.8" fill="none" stroke-linecap="round"/>
            <path class="fx-amor-ruhe" d="M74,17 L74,59" stroke="#f3e6c6" stroke-width=".9"/>
            <g class="fx-amor-zug">
                <path d="M74,17 L52,38 L74,59" stroke="#f3e6c6" stroke-width=".9" fill="none"/>
                <path d="M50,38 L88,38" stroke="#6b3d14" stroke-width="1.8"/>
                <path d="M50,38 L46,34.5 M50,38 L46,41.5 M54,38 L50,34.5 M54,38 L50,41.5" stroke="#e85a7a" stroke-width="1.5"/>
                ${herzSpitze(88, 38, '#e8344e')}
            </g>
            ${glied('M55,42 C62,41 68,40 75,38', 5.5)}
            <circle cx="56" cy="26" r="11" fill="${haut}" stroke="${kontur}" stroke-width="1.3"/>
            <g fill="#7a3b14" stroke="${kontur}" stroke-width=".9">
                <circle cx="47" cy="22" r="4.6"/><circle cx="50" cy="16.5" r="4.6"/><circle cx="56" cy="14.5" r="4.4"/>
                <circle cx="61.5" cy="16" r="3.8"/><circle cx="45.5" cy="28" r="3.6"/>
            </g>
            <circle cx="61.5" cy="25.5" r="1.4" fill="${kontur}"/>
            <path d="M59.5,21.5 q2.4,-1.2 4.4,.2" stroke="${kontur}" stroke-width=".9" fill="none"/>
            <path d="M60,31 q3,2.2 6,-.6" stroke="${kontur}" stroke-width="1" fill="none" stroke-linecap="round"/>
            <circle cx="63.5" cy="29" r="2.3" fill="#ff7f7f" opacity=".5"/>
            <path d="M51,27 c-1.6,-.2 -1.8,2.4 -.2,2.6" stroke="${kontur}" stroke-width=".8" fill="none"/>
        </svg>`;
    }
    function amorPfeilSvg() {
        return `<svg class="fx-amor-pfeilflug" viewBox="0 0 50 10" xmlns="${NS}">
            <path d="M3,5 L42,5" stroke="#6b3d14" stroke-width="1.6"/>
            <path d="M3,5 L0,1.5 M3,5 L0,8.5 M7,5 L4,1.5 M7,5 L4,8.5" stroke="#e85a7a" stroke-width="1.4"/>
            <path d="M50,5 C46,9.5 41,8.5 42,5 C41,1.5 46,.5 50,5 Z" fill="#e8344e" stroke="#2a160c" stroke-width=".6"/>
        </svg>`;
    }

    function Valentinstag() {
        const herzen = [];
        for (let i = 0; i < 26; i++) herzen.push({x: zufall(0, 100) * VW, y: zufall(0, 100) * H / 100, s: zufall(0.6, 1.6) * VW, v: zufall(2, 4.5) * VW, p: zufall(0, 6.28), f: auswahl(HERZ_FARBEN)});
        let ballons = null;
        let naechster = vorschau ? 2 : zufall(20, 90);
        // Amor: alle 60 Sekunden (Wunsch Jonas), in der Vorschau alle 12 Sekunden; die
        // getroffene Klasse bleibt markiert und wirft Herzen aus, bis er die nächste trifft
        let amor = null, amorNaechster = vorschau ? 1 : zufall(5, 20), verliebt = null;
        const funkeln = [];        // kleine Herzen am Treffpunkt (vorne)
        const getroffen = new Set();   // jedes Mal eine andere Kachel, bis alle einmal dran waren
        let herzRegen = null;          // aus der getroffenen Kachel rieseln Herzen nach unten
        const grosse = [];         // große Herzen überall, halb durchsichtig vorne (Schrift bleibt lesbar)
        function amorStarten(t) {
            const el = svgAusText(amorSvg());
            domV.appendChild(el);
            const aw = AMOR_B * VW, ah = aw * 0.9;
            const links = Math.random() < 0.5;
            // Ziel: eine Kachel auf der anderen Seite
            const andere = kaesten.filter((k) => (links ? k.x + k.w / 2 > W * 0.45 : k.x + k.w / 2 < W * 0.55));
            let frei = andere.filter((kk) => !getroffen.has(kk.el));
            if (!frei.length) {
                const letzte = Array.from(getroffen).pop();
                getroffen.clear();
                frei = andere.filter((kk) => kk.el !== letzte);
            }
            const k = frei.length ? auswahl(frei) : (andere.length ? auswahl(andere) : null);
            if (k) getroffen.add(k.el);
            const ziel = k ? [k.x + k.w * zufall(0.25, 0.75), k.y + k.h * zufall(0.3, 0.7)] : [links ? W * 0.75 : W * 0.25, H * 0.45];
            const schwebe = [links ? zufall(3, 12) * VW : W - zufall(3, 12) * VW - aw, zufall(2, 10) * VW];
            amor = {el: el, start: t, links: links, aw: aw, ah: ah, kachel: k, ziel: ziel,
                von: [links ? -aw - 2 * VW : W + 2 * VW, schwebe[1] + 6 * VW], schwebe: schwebe, pfeil: null, x: 0, y: 0};
        }
        function herzenUeberall() {
            for (let i = 0; i < 9; i++) {
                grosse.push({x: zufall(2, 98) * VW, y: zufall(3, 97) * H / 100, s: zufall(3, 6.5) * VW, f: auswahl(HERZ_FARBEN),
                    verzug: zufall(0, 1.2), leben: zufall(2.6, 3.6), alter: 0, dreh: zufall(-0.35, 0.35)});
            }
        }
        function amorSchritt(dt, t) {
            const a = amor, s = t - a.start;
            const zuflug = 2.2, zielen = 0.9, warten = 1.4, abflug = 2.0;
            let x, y;
            if (s < zuflug) {
                const u = 1 - Math.pow(1 - s / zuflug, 3);
                x = a.von[0] + (a.schwebe[0] - a.von[0]) * u;
                y = a.von[1] + (a.schwebe[1] - a.von[1]) * u;
            } else if (s < zuflug + zielen + warten) {
                x = a.schwebe[0]; y = a.schwebe[1];
                a.el.classList.toggle('fx-amor-gespannt', s < zuflug + zielen);
                if (s >= zuflug + zielen && !a.pfeil) {
                    // Schuss: der Pfeil fliegt im flachen Bogen zur Kachel
                    const spitzeX = a.links ? AMOR_SPITZE[0] / 100 * a.aw : (1 - AMOR_SPITZE[0] / 100) * a.aw;
                    const p0 = [x + spitzeX, y + AMOR_SPITZE[1] / 90 * a.ah];
                    const pel = svgAusText(amorPfeilSvg());
                    domV.appendChild(pel);
                    const weite = Math.hypot(a.ziel[0] - p0[0], a.ziel[1] - p0[1]);
                    a.pfeil = {el: pel, p0: p0, start: t, dauer: Math.max(0.55, Math.min(1.2, weite / (75 * VW))), weite: weite, steckt: null};
                }
            } else {
                const u = Math.min(1, (s - zuflug - zielen - warten) / abflug);
                const e = u * u;
                x = a.schwebe[0] + (a.links ? -1 : 1) * e * 30 * VW;
                y = a.schwebe[1] - e * 18 * VW;
                if (u >= 1 && !a.pfeil) { a.el.remove(); amor = null; return; }
            }
            // sanftes Auf und Ab beim Flattern
            y += Math.sin(t * 5) * 0.35 * VW;
            a.x = x; a.y = y;
            // Blick zum Ziel: SVG schaut nach rechts, von rechts kommend gespiegelt
            a.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px)${a.links ? '' : ' scale(-1, 1)'}`;
            // Pfeil im Flug, dann kurz steckend
            const pf = a.pfeil;
            if (pf) {
                const pw = 5 * VW, ph = pw / 5;
                if (!pf.steckt) {
                    const u = Math.min(1, (t - pf.start) / pf.dauer);
                    const bogen = pf.weite * 0.1;
                    const px = pf.p0[0] + (a.ziel[0] - pf.p0[0]) * u;
                    const py = pf.p0[1] + (a.ziel[1] - pf.p0[1]) * u - Math.sin(u * Math.PI) * bogen;
                    const vx = a.ziel[0] - pf.p0[0], vy = a.ziel[1] - pf.p0[1] - Math.cos(u * Math.PI) * Math.PI * bogen;
                    const w = Math.atan2(vy, vx) * 180 / Math.PI;
                    pf.el.style.transform = `translate(${(px - pw).toFixed(1)}px, ${(py - ph / 2).toFixed(1)}px) rotate(${w.toFixed(1)}deg)`;
                    if (u >= 1) {
                        pf.steckt = t;
                        // Treffer: Kachel leuchtet rosa, Herzen sprühen, überall gehen große Herzen auf
                        if (a.kachel) {
                            const ke = a.kachel.el;
                            ke.classList.remove('fx-amor-treffer'); void ke.offsetWidth; ke.classList.add('fx-amor-treffer');
                            setTimeout(() => ke.classList.remove('fx-amor-treffer'), 2500);
                        }
                        if (a.kachel) {
                            // die Kachel färbt sich rosa und bleibt 30 Sekunden so; so lange rieseln Herzen aus ihr
                            const ke = a.kachel.el;
                            if (verliebt && verliebt !== ke) {
                                const alt = verliebt;
                                alt.classList.remove('fx-amor-verliebt');
                                setTimeout(() => alt.classList.remove('fx-amor-weich'), 2000);
                            }
                            ke.classList.add('fx-amor-weich', 'fx-amor-verliebt');
                            verliebt = ke;
                            herzRegen = {k: a.kachel, bis: t + dauer(60, 12) + 30};
                        }
                        for (let i = 0; i < 10; i++) {
                            const w2 = zufall(0, 6.283), v = zufall(8, 22) * VW;
                            funkeln.push({x: a.ziel[0], y: a.ziel[1], vx: Math.cos(w2) * v, vy: Math.sin(w2) * v - 6 * VW, s: zufall(0.5, 1.1) * VW, f: auswahl(HERZ_FARBEN), leben: zufall(0.9, 1.5), alter: 0});
                        }
                        herzenUeberall();
                    }
                } else {
                    const alt = t - pf.steckt;
                    pf.el.style.opacity = Math.max(0, 1 - alt / 0.9).toFixed(2);
                    if (alt > 0.9) { pf.el.remove(); a.pfeil = null; a.pfeilFertig = true; }
                }
            }
        }
        return {
            stop() {
                for (const el of document.querySelectorAll('.fx-amor-verliebt, .fx-amor-weich')) el.classList.remove('fx-amor-verliebt', 'fx-amor-weich');
                if (ballons) ballons.el.remove();
                if (amor) { amor.el.remove(); if (amor.pfeil) amor.pfeil.el.remove(); amor = null; }
            },
            schritt(dt, t) {
                // große Herzen überall: wachsen auf, schweben, verblassen nach etwa 3 Sekunden
                for (let i = grosse.length - 1; i >= 0; i--) {
                    const g = grosse[i];
                    g.alter += dt;
                    const u = (g.alter - g.verzug) / g.leben;
                    if (u >= 1) { grosse.splice(i, 1); continue; }
                    if (u <= 0) continue;
                    const auf = Math.min(1, u / 0.18);
                    const groesse = g.s * (0.4 + 0.6 * (1 - Math.pow(1 - auf, 3))) * (1 + Math.sin(g.alter * 7) * 0.04);
                    cxV.globalAlpha = 0.45 * Math.min(1, (1 - u) / 0.35);
                    cxV.save();
                    cxV.translate(g.x, g.y - u * 3 * VW);
                    cxV.rotate(g.dreh);
                    cxV.drawImage(sprite(`herz-${g.f}`, () => herzSprite(g.f)), -groesse, -groesse, 2 * groesse, 2 * groesse);
                    cxV.restore();
                }
                cxV.globalAlpha = 1;
                // Herzregen: aus der getroffenen Kachel fallen viele Herzen nach unten
                if (herzRegen) {
                    const hk = herzRegen.k;
                    let neu = dt * 5;
                    while (neu > 0) {
                        if (Math.random() < neu) {
                            funkeln.push({x: hk.x + zufall(0.08, 0.92) * hk.w, y: hk.y + hk.h * zufall(0.45, 0.95), vx: zufall(-0.8, 0.8) * VW, vy: zufall(0.5, 2) * VW,
                                s: zufall(0.8, 1.5) * VW, f: auswahl(HERZ_FARBEN), leben: zufall(3, 4.2), alter: 0, p: zufall(0, 6.28), wachsen: true});
                        }
                        neu -= 1;
                    }
                    if (t >= herzRegen.bis) herzRegen = null;
                }
                // kleine Herzen am Treffpunkt und aus dem Herzregen, vorne; sie trudeln hin und her
                for (let i = funkeln.length - 1; i >= 0; i--) {
                    const f = funkeln[i];
                    f.alter += dt;
                    if (f.alter >= f.leben || f.y > H + 2 * VW) { funkeln.splice(i, 1); continue; }
                    f.vx *= Math.pow(0.3, dt); f.vy = f.vy * Math.pow(0.3, dt) + 6 * VW * dt;
                    f.x += f.vx * dt + (f.p !== undefined ? Math.sin(f.alter * 3 + f.p) * 0.9 * VW * dt : 0);
                    f.y += f.vy * dt;
                    // Herzen aus der Kachel wachsen erst aus ihr heraus
                    const gr = f.wachsen ? f.s * Math.min(1, 0.2 + f.alter / 0.6) : f.s;
                    cxV.globalAlpha = Math.min(1, (1 - f.alter / f.leben) * 1.6) * (f.wachsen ? Math.min(1, f.alter / 0.4) : 1);
                    cxV.drawImage(sprite(`herz-${f.f}`, () => herzSprite(f.f)), f.x - gr, f.y - gr, 2 * gr, 2 * gr);
                }
                cxV.globalAlpha = 1;
                amorNaechster -= dt;
                if (!amor && amorNaechster <= 0) {
                    amorStarten(t);
                    amorNaechster = dauer(60, 12);
                }
                if (amor) amorSchritt(dt, t);
                for (const h of herzen) {
                    h.y -= h.v * dt;
                    if (h.y < -2 * VW) { h.y = H + 2 * VW; h.x = zufall(0, 100) * VW; }
                    const img = sprite(`herz-${h.f}`, () => herzSprite(h.f));
                    cxH.globalAlpha = 0.6;
                    const x = h.x + Math.sin(t * 0.9 + h.p) * 1.2 * VW;
                    cxH.drawImage(img, x - h.s, h.y - h.s, 2 * h.s, 2 * h.s);
                }
                cxH.globalAlpha = 1;
                naechster -= dt;
                if (!ballons && naechster <= 0) {
                    const el = svgAusText(herzballonsSvg());
                    domV.appendChild(el);
                    ballons = {el: el, start: t, x: zufall(10, 80) * VW};
                    naechster = dauer(3 * 60, 17);   // alle 3 Minuten; Vorschau: gleich der nächste
                }
                if (ballons) {
                    const u = (t - ballons.start) / 16;
                    if (u >= 1) { ballons.el.remove(); ballons = null; } else {
                        const hoehe = 8 * VW * 140 / 80;
                        const y = H + 2 * VW - (H + hoehe + 4 * VW) * u;
                        const x = ballons.x + Math.sin(u * 6) * 3 * VW + u * 6 * VW;
                        ballons.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) rotate(${(Math.sin(u * 9) * 5).toFixed(1)}deg)`;
                    }
                }
            },
        };
    }

    // ==================================================================
    // FASCHING: Konfetti hinter den Kacheln, Luftschlangen an einigen Kacheln,
    // etwa alle 10 Minuten zwei Konfetti-Kanonen unten.

    const KONFETTI_FARBEN = ['#e8344e', '#f2c14e', '#2f9e6a', '#3a86d4', '#a259d9', '#ff8a3d', '#ff6fb5'];
    function Fasching() {
        const stuecke = [];
        const neu = (st, oben) => Object.assign(st, {x: zufall(0, 100) * VW, y: oben ? -zufall(1, 10) * VW : zufall(0, 100) * H / 100,
            v: zufall(3, 6) * VW, dreh: zufall(0, 6.28), vdreh: zufall(-4, 4), kipp: zufall(0, 6.28), vkipp: zufall(3, 7),
            f: auswahl(KONFETTI_FARBEN), b: zufall(0.3, 0.45) * VW, h: zufall(0.15, 0.22) * VW});
        for (let i = 0; i < 110; i++) stuecke.push(neu({}, false));
        const schuss = [];
        let naechster = vorschau ? 2 : zufall(20, 90);
        const deko = setInterval(() => dekorieren('fasching', luftschlange), 2000);
        dekorieren('fasching', luftschlange);
        function konfetti(ctx, st) {
            ctx.save();
            ctx.translate(st.x, st.y);
            ctx.rotate(st.dreh);
            ctx.scale(1, Math.max(0.15, Math.abs(Math.cos(st.kipp))));
            ctx.fillStyle = st.f;
            ctx.fillRect(-st.b / 2, -st.h / 2, st.b, st.h);
            ctx.restore();
        }
        return {
            stop() { clearInterval(deko); dekoEntfernen(); },
            schritt(dt, t) {
                for (const st of stuecke) {
                    st.y += st.v * dt; st.x += Math.sin(t + st.kipp) * 0.6 * VW * dt;
                    st.dreh += st.vdreh * dt; st.kipp += st.vkipp * dt;
                    if (st.y > H + VW) neu(st, true);
                    cxH.globalAlpha = 0.85;
                    konfetti(cxH, st);
                }
                cxH.globalAlpha = 1;
                naechster -= dt;
                if (naechster <= 0) {
                    naechster = dauer(5 * 60, 6);    // alle 5 Minuten; Vorschau: durchgehend
                    // zwei Kanonen unten links und rechts, schräg nach innen oben
                    for (const [x0, richtung] of [[2 * VW, 1], [W - 2 * VW, -1]]) {
                        for (let i = 0; i < 90; i++) {
                            const w = (-Math.PI / 2) + richtung * zufall(0.15, 0.7);
                            const v = zufall(35, 70) * VW;
                            schuss.push(neu({}, false));
                            Object.assign(schuss[schuss.length - 1], {x: x0, y: UNTEN - VW, vx: Math.cos(w) * v, vy: Math.sin(w) * v, leben: zufall(3, 5), b: zufall(0.4, 0.6) * VW, h: zufall(0.2, 0.28) * VW});
                        }
                    }
                }
                for (let i = schuss.length - 1; i >= 0; i--) {
                    const st = schuss[i];
                    st.leben -= dt;
                    if (st.leben <= 0 || st.y > H + 2 * VW) { schuss.splice(i, 1); continue; }
                    st.vx *= Math.pow(0.35, dt); st.vy = st.vy * Math.pow(0.35, dt) + 30 * VW * dt;
                    st.x += st.vx * dt; st.y += st.vy * dt;
                    st.dreh += st.vdreh * 2 * dt; st.kipp += st.vkipp * dt;
                    cxV.globalAlpha = Math.min(1, st.leben);
                    konfetti(cxV, st);
                }
                cxV.globalAlpha = 1;
            },
        };
    }
    // Luftschlange: hängt an der oberen rechten Ecke einiger Kacheln seitlich herunter
    function luftschlange(el, wVw) {
        if (Math.random() < 0.45) return;
        const farbe = auswahl(KONFETTI_FARBEN);
        let d = `M 0.4 0.2`;
        for (let i = 1; i <= 9; i++) {
            const y = i * 0.55;
            d += ` Q ${(i % 2 ? 1.3 : -0.1).toFixed(2)} ${(y - 0.27).toFixed(2)} 0.6 ${y.toFixed(2)}`;
        }
        const s = svg('svg', {viewBox: '0 0 1.6 5.4', class: 'fx-deko'}, [
            svg('path', {d: d, stroke: farbe, 'stroke-width': 0.22, fill: 'none', 'stroke-linecap': 'round'}),
            svg('path', {d: d, stroke: 'rgba(255,255,255,.45)', 'stroke-width': 0.06, fill: 'none', transform: 'translate(-0.05 -0.03)'}),
        ]);
        Object.assign(s.style, {left: `${(wVw - 0.5).toFixed(2)}vw`, top: '-0.3vw', width: '1.6vw', height: '5.4vw',
            filter: 'drop-shadow(0 .08vw .1vw rgba(0,0,0,.25))', transformOrigin: '30% 0%', animation: 'fx-luftschlange 3s ease-in-out infinite alternate'});
        el.appendChild(s);
    }

    // ==================================================================
    // LETZTER SCHULTAG VOR DEN SOMMERFERIEN: Sonne, und etwa alle 8 Minuten
    // zieht ein Propellerflugzeug ein Banner „Schöne Sommerferien!“ vorbei.

    function flugzeugSvg(banner) {
        return `<svg class="fx-flugzeug" viewBox="0 0 320 60" xmlns="${NS}">
            <g class="fx-banner">
                <path d="M4,14 C40,10 80,18 120,13 C150,10 175,16 196,13 L196,45 C175,48 150,42 120,45 C80,50 40,42 4,46 Z" fill="#fffaf0" stroke="#d9cdb4" stroke-width="1"/>
                <path d="M4,14 L4,46" stroke="#c8102e" stroke-width="3"/>
                <text x="100" y="35" text-anchor="middle" font-family="'Trebuchet MS', Arial, sans-serif" font-weight="bold" font-size="17" fill="#c8102e">${banner || 'Schöne Sommerferien!'}</text>
            </g>
            <path d="M196,29 L232,30" stroke="#6b6b6b" stroke-width="1"/>
            <g transform="translate(228 10)">
                <path d="M4,20 C10,12 40,10 70,14 C80,16 86,20 86,24 C86,28 80,31 70,32 C40,35 12,32 4,28 Z" fill="#3a86d4"/>
                <path d="M4,20 L0,6 L10,6 L18,18 Z" fill="#2f6fb3"/>
                <path d="M30,24 L52,24 L48,38 L36,38 Z" fill="#2a5f99"/>
                <path d="M54,15 C58,9 66,9 70,14 Z" fill="#cfe9f7" stroke="#2a5f99" stroke-width=".8"/>
                <circle cx="62" cy="13" r="3" fill="#f2cdb0"/>
                <rect x="85" y="21" width="3" height="6" rx="1" fill="#555"/>
                <ellipse class="fx-propeller" cx="89" cy="24" rx="1.6" ry="11" fill="rgba(80,80,80,.55)"/>
                <path d="M14,24 L70,24" stroke="#ffffff" stroke-width="1.6" opacity=".8"/>
            </g>
        </svg>`;
    }
    // Erster Schultag nach den Sommerferien: Flugzeug mit „Willkommen zurück!“, nur bis
    // 12 Uhr (danach sind Einschulungen); ab 12 Uhr startet kein neues Flugzeug mehr
    function Schulanfang() {
        return Sommerferien('Willkommen zurück!', true);
    }
    function Sommerferien(banner, bisMittag) {
        const sonne = document.createElement('div');
        sonne.className = 'fx-sonne';
        sonne.appendChild(Object.assign(document.createElement('div'), {className: 'fx-sonne-strahlen'}));
        domH.appendChild(sonne);
        let flug = null;
        let naechster = vorschau ? 1.5 : zufall(20, 60);
        return {
            stop() { sonne.remove(); if (flug) flug.el.remove(); },
            schritt(dt, t) {
                naechster -= dt;
                const mittag = bisMittag && !vorschau && new Date().getHours() >= 12;
                if (!flug && naechster <= 0 && !mittag) {
                    const el = svgAusText(flugzeugSvg(banner));
                    domV.appendChild(el);
                    flug = {el: el, start: t, y0: zufall(5, 16) * VW};
                    naechster = dauer(2 * 60, 18);   // alle 2 Minuten; Vorschau: gleich der nächste
                }
                if (flug) {
                    const u = (t - flug.start) / 17;
                    if (u >= 1) { flug.el.remove(); flug = null; return; }
                    const breite = 40 * VW;
                    const x = -breite - VW + (W + breite + 2 * VW) * u;
                    const y = flug.y0 + Math.sin(u * Math.PI * 3) * 0.8 * VW;
                    flug.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) rotate(${(Math.cos(u * Math.PI * 3) * -1.2).toFixed(2)}deg)`;
                }
            },
        };
    }

    // ==================================================================
    // Steuerung

    const BAUER = {schnee: Schnee, regen: Regen, gewitter: Gewitter, hitze: Hitze, sturm: Sturm, frost: Frost};

    function schleife(ts) {
        if (!wetter && !fest) { laeuft = false; return; }
        requestAnimationFrame(schleife);
        const t = ts / 1000;
        let dt = t - letzte;
        // 30 Bilder pro Sekunde reichen und schonen die Monitor-Rechner
        if (dt < 1 / 32) return;
        if (dt > 0.1) dt = 0.1;
        letzte = t;
        if (document.hidden) return;
        try {
            kaestenMessen(t);
            cxH.clearRect(0, 0, W, H);
            cxV.clearRect(0, 0, W, H);
            if (wetter) wetter.schritt(dt, t);
            if (fest) fest.schritt(dt, t);
            funkenZeichnen(dt);
        } catch (e) {
            // ein Fehler in den Effekten darf den Monitor nie stören
            console.error(e);
            alles_stoppen();
        }
    }

    function schleifeStarten() {
        if (laeuft) return;
        laeuft = true;
        letzte = performance.now() / 1000;
        requestAnimationFrame(schleife);
    }

    function alles_stoppen() {
        for (const e of [wetter, fest]) if (e) { try { e.stop(); } catch (x) { console.error(x); } }
        wetter = null;
        fest = null;
        zustand = {wetter: '', fest: ''};
        if (cxH) { cxH.clearRect(0, 0, W, H); cxV.clearRect(0, 0, W, H); }
        funken = [];
    }

    // Wendet an, was gerade gelten soll – startet und stoppt nur, was sich ändert
    function anwenden(soll) {
        const w = soll.wetter ? `${soll.wetter.effekt}:${soll.wetter.staerke}:${soll.wetter.zeus ? 'zeus' : ''}` : '';
        const f = soll.fest ? `${soll.fest.fest}:${soll.fest.nah ? 1 : 0}` : '';
        if (w !== zustand.wetter) {
            if (wetter) wetter.stop();
            wetter = null;
            if (soll.wetter && BAUER[soll.wetter.effekt]) wetter = BAUER[soll.wetter.effekt](Math.max(1, Math.min(3, soll.wetter.staerke || 2)), !!soll.wetter.zeus);
            zustand.wetter = w;
        }
        if (f !== zustand.fest) {
            if (fest) fest.stop();
            fest = null;
            const festBauer = {weihnachten: Weihnachten, nikolaus: Nikolaus, ostern: Ostern, valentinstag: Valentinstag, fasching: Fasching,
                sommerferien: () => Sommerferien(), schulanfang: Schulanfang, adventskonzert: Adventskonzert, forschertag: Forschertag};
            if (soll.fest && festBauer[soll.fest.fest]) fest = festBauer[soll.fest.fest](!!soll.fest.nah);
            zustand.fest = f;
        }
        // kein zusätzlicher Hinweis am Monitor (Wunsch Jonas): die Effekte sprechen für sich
        if (wetter || fest) schleifeStarten();
    }

    const VORSCHAU_TITEL = {
        schnee: 'Starker Schneefall', regen: 'Heftiger Starkregen', gewitter: 'Schweres Gewitter',
        hitze: 'Extreme Hitze', sturm: 'Orkanartige Böen', frost: 'Glatteis',
    };

    function vorschauLesen() {
        const p = new URLSearchParams(window.location.search);
        if (!p.has('effekt')) return null;
        const staerke = Math.max(1, Math.min(3, parseInt(p.get('staerke') || '2', 10) || 2));
        if (p.get('effekt').trim().toLowerCase() === 'folgen') return {folgen: true, staerke: staerke};
        return sollAus(p.get('effekt'), staerke);
    }

    // Was ein Vorschau-Name bedeutet: schnee, …, zeus, weihnachten, ostern, rundgang
    function sollAus(text, staerke) {
        const soll = {wetter: null, fest: null};
        if (text.trim().toLowerCase() === 'rundgang') {
            const namen = WETTER.concat(FESTE);
            // Zeus kommt bei jedem Gewitter
            soll.rundgang = namen.map((name) => (WETTER.indexOf(name) >= 0
                ? {wetter: {effekt: name, staerke: staerke, titel: VORSCHAU_TITEL[name], bis: null, zeus: name === 'gewitter'}, fest: null}
                : {wetter: null, fest: {fest: name, nah: true}}));
            return soll;
        }
        for (const name of text.split(',').map((s) => s.trim().toLowerCase())) {
            if (WETTER.indexOf(name) >= 0) soll.wetter = {effekt: name, staerke: staerke, titel: VORSCHAU_TITEL[name], bis: null, zeus: name === 'gewitter'};
            if (name === 'zeus') soll.wetter = {effekt: 'gewitter', staerke: staerke, titel: 'Schweres Gewitter mit Zeus', bis: null, zeus: true};
            if (FESTE.indexOf(name) >= 0) soll.fest = {fest: name, nah: true};
        }
        return soll;
    }

    // Folgen-Modus (?effekt=folgen): Das Fenster zeigt, was auf „Monitore
    // verwalten“ als Vorschau gewählt ist; leer = echter Stand. Nur solche
    // Fenster reagieren, die echten Monitore nicht.
    let folgen = false, folgenStaerke = 2, rundgangUhr = null, abfrageUhr = null;
    function rundgangStoppen() { if (rundgangUhr) { clearInterval(rundgangUhr); rundgangUhr = null; } }
    function vorschauZeigen(name) {
        rundgangStoppen();
        if (abfrageUhr) { clearInterval(abfrageUhr); abfrageUhr = null; }
        if (!name) {
            // echter Stand
            vorschau = false;
            abfragen();
            abfrageUhr = setInterval(abfragen, ABFRAGE_ALLE_MS);
            return;
        }
        vorschau = true;
        const soll = sollAus(name, folgenStaerke);
        if (soll.rundgang) {
            let i = 0;
            anwenden(soll.rundgang[0]);
            rundgangUhr = setInterval(() => { i = (i + 1) % soll.rundgang.length; anwenden(soll.rundgang[i]); }, RUNDGANG_MS);
        } else {
            anwenden(soll);
        }
    }
    let letzteVorschau = null;
    function vorschauNachricht(name) {
        if (!folgen || name === letzteVorschau) return;
        letzteVorschau = name;
        vorschauZeigen(name);
    }

    function abfragen() {
        // Monitore mit geheimem Monitor-Link (/monitor/<link>) haben keine
        // Sitzung und weisen sich mit dem Link aus
        const teile = window.location.pathname.split('/');
        const link = (teile[1] === 'monitor' && teile.length === 3 && teile[2].length >= 8) ? teile[2] : '';
        const url = link ? `/api/monitor_effekte?link=${encodeURIComponent(link)}` : '/api/monitor_effekte';
        fetch(url, {credentials: 'same-origin', cache: 'no-store'})
            .then((r) => r.ok ? r.json() : null)
            .then((d) => {
                if (!d) return;
                // im Folgen-Modus beim Start: die gerade gewählte Vorschau übernehmen
                if (folgen && letzteVorschau === null) { letzteVorschau = d.vorschau || ''; if (d.vorschau) { vorschauZeigen(d.vorschau); return; } }
                if (folgen && vorschau) return;
                if (d.an === false) { alles_stoppen(); return; }
                anwenden({wetter: d.wetter || null, fest: d.fest || null});
                // direkt nach dem Start des Servers sind die Warnungen evtl. noch unterwegs
                if (d.bereit === false) setTimeout(abfragen, 30 * 1000);
            })
            .catch(() => {});
    }

    // opt: {buehne: Element, kaesten: 'Selektor', kiesel: 'Selektor im Kasten',
    //       dunkel: dunkler Hintergrund,
    //       fixiert: Bühne ist das ganze Fenster}
    function start(o) {
        try {
            opt = Object.assign({kaesten: '.klasse', kiesel: null, dunkel: false, fixiert: false}, o || {});
            buehne = opt.buehne || document.body;
            const soll = vorschauLesen();
            folgen = !!(soll && soll.folgen);
            if (folgen) folgenStaerke = soll.staerke;
            vorschau = !!soll && !folgen;
            // Wer am Rechner „Bewegung reduzieren“ eingestellt hat, bekommt keine Effekte
            if (!vorschau && window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
            cssEinfuegen();
            ebenenAnlegen();
            if (vorschau && soll.rundgang) {
                let i = 0;
                anwenden(soll.rundgang[0]);
                rundgangUhr = setInterval(() => {
                    i = (i + 1) % soll.rundgang.length;
                    anwenden(soll.rundgang[i]);
                }, RUNDGANG_MS);
            } else if (vorschau) {
                anwenden(soll);
            } else {
                abfragen();
                abfrageUhr = setInterval(abfragen, ABFRAGE_ALLE_MS);
            }
        } catch (e) {
            console.error(e);
        }
    }

    window.MonitorEffekte = {start: start, stop: alles_stoppen, vorschauNachricht: vorschauNachricht};
})();
