// Neues Design: the news editor as building blocks (manage_news.html,
// "Artikel schreiben"). Loaded only in the new design (website.rb,
// news_editor_preview_script).
//
// An article is put together from blocks: Einstieg (always first), Absatz,
// Zwischenüberschrift, Bild (groß, links or rechts neben seinem Text),
// Galerie and Datei. The stored text stays what it always was – Markdown
// with image{…}, gallery{…} and file{…}{…} – and the textarea
// #ta_markdown keeps it: the page saves, compares and previews that text as
// before. An article opens unchanged in the blocks; text the blocks can't
// represent without changing it (code blocks) opens in »Text bearbeiten«.
//
// Uses from the page: update_buttons, news_render_preview, news_hints,
// NEWS_SIDE_TEXT_MIN, NEWS_CHARS_PER_LINE, news_parse_image, news_parse_row,
// NEWS_IMAGE_ROW, NEWS_ROW_RATIOS.
(function () {
    if (!document.body.classList.contains('ui-preview')) return;

    var GALLERY_MAX = 6;
    var DEFAULT_WIDTH = '5';
    var CREDIT = /foto|bild|grafik|quelle|©/i;
    // the article column of the website: phone, tablet, desktop (px)
    var WIDTHS = { phone: 345, tablet: 690, desktop: 825 };
    var TYPES = {
        lead: { label: 'Einstieg', icon: 'quote' },
        text: { label: 'Absatz', icon: 'align-left' },
        heading: { label: 'Zwischenüberschrift', icon: 'hash' },
        image: { label: 'Bild', icon: 'photo' },
        row: { label: 'Bilderreihe', icon: 'columns' },
        gallery: { label: 'Galerie', icon: 'layout-grid' },
        file: { label: 'Datei', icon: 'paperclip' },
        video: { label: 'Video', icon: 'video' },
    };
    var ADD = ['text', 'heading', 'image', 'row', 'gallery', 'video', 'file'];
    var ROW_MAX = 3;

    var blocks = [];
    var mode = 'blocks';
    var preview_timer = null;
    var uid = 0;
    var images = null;  // names for the suggestions (if allowed to see them)
    var files = null;

    // ---------- the text: parse and write ----------

    var INCLUDE_LINE = /^(image|gallery)\{[^}\n]+\}$|^images\{[^{}\n]*\}\{(\s*image\{[^{}\n]*\}\s*)+\}$/;
    var FILE_LINE = /^file\{[^}\n]+\}\{[^}\n]+\}$/;

    function parse_image(body) {
        var i = news_parse_image(body);
        return {
            type: 'image', slug: i.slug, caption: i.caption, text: '', crop: i.crop,
            layout: i.pos === null ? 'full' : (i.pos[0] === 'r' ? 'right' : 'left'),
            width: i.pos === null ? DEFAULT_WIDTH : i.pos[1],
        };
    }

    // a whole chunk that is a row of images, or null
    function parse_row(chunk) {
        var m = chunk.match(NEWS_IMAGE_ROW);
        if (!m || m.index !== 0 || m[0].length !== chunk.length) return null;
        var row = news_parse_row(chunk);
        if (!row) return null;
        return {
            type: 'row', ratio: row.ratio, caption: row.caption,
            items: row.images.map(function (i) { return { slug: i.slug, caption: i.caption, crop: i.crop || [50, 50] }; }),
        };
    }

    function crop_part(crop) {
        return crop && (crop[0] !== 50 || crop[1] !== 50) ? `, pos=${crop[0]},${crop[1]}` : '';
    }

    function write_row(b) {
        var caption = clean_caption(b.caption).replace(/"/g, '');
        var items = b.items.map(function (item) {
            var c = clean_caption(item.caption);
            return `image{${clean_slug(item.slug) || 'BILDNAME'}${crop_part(item.crop)}${c ? `, "${c}"` : ''}}`;
        });
        return `images{${b.ratio}${caption ? `, "${caption}"` : ''}}{${items.join(' ')}}`;
    }

    function parse_gallery(body) {
        var caption = '';
        var quote = body.indexOf('"');
        if (quote >= 0) {
            caption = body.substr(quote).trim();
            caption = caption.substr(1, caption.length - 2).trim();
            body = body.substr(0, quote);
        }
        var slugs = body.split(',').map(function (x) { return x.trim(); }).filter(function (x) { return x.length > 0; });
        return { type: 'gallery', slugs: slugs, caption: caption };
    }

    function write_image(b) {
        var slug = clean_slug(b.slug) || 'BILDNAME';
        var pos = b.layout === 'full' ? '' : `, ${b.layout === 'right' ? 'r' : 'l'}${b.width || DEFAULT_WIDTH}`;
        var caption = clean_caption(b.caption);
        return `image{${slug}${pos}${crop_part(b.crop)}${caption ? `, "${caption}"` : ''}}`;
    }

    function write_gallery(b) {
        var slugs = b.slugs.map(clean_slug).filter(function (x) { return x.length > 0; });
        if (slugs.length === 0) slugs = ['BILD1', 'BILD2'];
        var caption = clean_caption(b.caption);
        return `gallery{${slugs.join(', ')}${caption ? `, "${caption}"` : ''}}`;
    }

    function clean_slug(s) { return (s || '').trim().replace(/[^A-Za-z0-9_-]/g, ''); }
    function clean_caption(s) { return (s || '').replace(/[{}\n]/g, ' ').replace(/\s+/g, ' ').trim(); }
    function clean_line(s) { return (s || '').replace(/[{}\n]/g, ' ').replace(/\s+/g, ' ').trim(); }

    // ---------- YouTube videos ----------
    // Stored as the articles already have them: raw HTML, a 16:9 box
    // (Bootstrap's embed-responsive) with a youtube-nocookie.com iframe.

    var YOUTUBE_ID = /^[A-Za-z0-9_-]{11}$/;

    // seconds from "90", "90s", "1m30s", "1h2m3s"
    function seconds(t) {
        if (!t) return 0;
        if (/^\d+$/.test(t)) return parseInt(t, 10);
        var m = t.match(/^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?$/);
        if (!m) return 0;
        return (parseInt(m[1] || '0', 10) * 3600) + (parseInt(m[2] || '0', 10) * 60) + parseInt(m[3] || '0', 10);
    }

    // a YouTube link in any common form: watch?v=, youtu.be/, shorts/,
    // embed/, live/, with t= or start=; null if it isn't one
    function parse_youtube(link) {
        var url;
        try { url = new URL((link || '').trim()); } catch (e) { return null; }
        var host = url.hostname.replace(/^(www|m|music)\./, '');
        var id = null;
        if (host === 'youtu.be') id = url.pathname.split('/')[1];
        else if (host === 'youtube.com' || host === 'youtube-nocookie.com') {
            if (url.pathname === '/watch') id = url.searchParams.get('v');
            else {
                var m = url.pathname.match(/^\/(?:shorts|embed|live|v)\/([^/?#]+)/);
                if (m) id = m[1];
            }
        }
        if (!id || !YOUTUBE_ID.test(id)) return null;
        var start = seconds(url.searchParams.get('t') || url.searchParams.get('start') || '');
        return { id: id, start: start };
    }

    function attr(s) {
        return (s || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    function unattr(s) {
        return (s || '').replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
    }

    function video_src(v) {
        return `https://www.youtube-nocookie.com/embed/${v.id}${v.start ? `?start=${v.start}` : ''}`;
    }

    function write_video(b) {
        var v = parse_youtube(b.link);
        if (!v) return clean_line(b.link);
        var title = clean_line(b.title) || 'Video auf YouTube';
        return `<div class="embed-responsive embed-responsive-16by9" style="margin-bottom: 2em;"><iframe src="${video_src(v)}" title="${attr(title)}" loading="lazy" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen style="display: block; width: 100%;"></iframe></div>`;
    }

    // one chunk that is a YouTube iframe (in its box or alone)
    function parse_video(chunk) {
        if (!/^<(div|iframe|p)\b/i.test(chunk) || (chunk.match(/<iframe\b/gi) || []).length !== 1) return null;
        if (!/^(<div[^>]*>|<p>)?\s*<iframe\b[^>]*>\s*<\/iframe>\s*(<\/div>|<\/p>)?$/i.test(chunk)) return null;
        var src = (chunk.match(/<iframe\b[^>]*\ssrc="([^"]+)"/i) || [])[1];
        var v = parse_youtube(unattr(src || ''));
        if (!v) return null;
        var title = (chunk.match(/<iframe\b[^>]*\stitle="([^"]*)"/i) || [])[1];
        var link = `https://www.youtube.com/watch?v=${v.id}${v.start ? `&t=${v.start}s` : ''}`;
        return { type: 'video', link: link, title: title ? unattr(title) : '' };
    }

    // The text as chunks the way Markdown sees it: paragraphs (blank lines
    // between them), an image or gallery on its own line is a block of its
    // own, a heading at the start of a paragraph too.
    function chunks_of(markdown) {
        var chunks = [];
        var cur = [];
        var flush = function () {
            if (cur.length > 0) chunks.push(cur.join('\n'));
            cur = [];
        };
        markdown.replace(/\r\n?/g, '\n').split('\n').forEach(function (line) {
            var t = line.trim();
            if (t === '') { flush(); return; }
            if (INCLUDE_LINE.test(t)) { flush(); chunks.push(t); return; }
            if (cur.length === 0 && /^#{1,6}\s/.test(t)) { chunks.push(t); return; }
            cur.push(line.replace(/\s+$/, function (sp) { return sp.length >= 2 ? '  ' : ''; }));
        });
        flush();
        return chunks;
    }

    // the same text with every include written the way the editor writes it
    function canonical(markdown) {
        return chunks_of(markdown).map(function (c) {
            var video = parse_video(c);
            if (video) return write_video(video);
            var row = parse_row(c);
            if (row) return write_row(row);
            var m = c.match(/^(image|gallery)\{([^}]+)\}$/);
            if (!m) return c;
            return m[1] === 'image' ? write_image(parse_image(m[2])) : write_gallery(parse_gallery(m[2]));
        }).join('\n\n');
    }

    function parse(markdown) {
        var list = [];
        chunks_of(markdown).forEach(function (c) {
            var m = c.match(/^(image|gallery)\{([^}]+)\}$/);
            var prev = list[list.length - 1];
            var video = parse_video(c);
            if (video) {
                list.push(video);
                return;
            }
            var row = parse_row(c);
            if (row) {
                list.push(row);
                return;
            }
            if (m) {
                list.push(m[1] === 'image' ? parse_image(m[2]) : parse_gallery(m[2]));
                return;
            }
            var h = c.match(/^(#{1,6})\s+(.*)$/);
            if (h && c.indexOf('\n') < 0) {
                list.push({ type: 'heading', level: h[1].length, text: h[2].trim() });
                return;
            }
            if (FILE_LINE.test(c)) {
                var f = c.match(/^file\{([^}]+)\}\{([^}]+)\}$/);
                list.push({ type: 'file', name: f[1], label: f[2] });
                return;
            }
            // the text an image beside the text wraps
            if (prev && prev.type === 'image' && prev.layout !== 'full' && !prev.text) {
                prev.text = c;
                return;
            }
            // lists and indented text go on with the paragraph before
            if (prev && (prev.type === 'text' || prev.type === 'lead') && /^(\s{2,}|[-*+]\s|\d+\.\s)/.test(c)) {
                prev.text += '\n\n' + c;
                return;
            }
            list.push({ type: list.length === 0 ? 'lead' : 'text', text: c });
        });
        if (list.length === 0 || list[0].type !== 'lead') list.unshift({ type: 'lead', text: '' });
        list.forEach(function (b) { b.id = ++uid; });
        return list;
    }

    function serialize(list) {
        var parts = [];
        list.forEach(function (b) {
            var text = (b.text || '').trim();
            if (b.type === 'lead' || b.type === 'text') {
                if (text) parts.push(text);
            } else if (b.type === 'heading') {
                if (clean_line(b.text)) parts.push(`${'#'.repeat(b.level || 2)} ${clean_line(b.text)}`);
            } else if (b.type === 'image') {
                parts.push(write_image(b));
                if (b.layout !== 'full' && text) parts.push(text);
            } else if (b.type === 'gallery') {
                parts.push(write_gallery(b));
            } else if (b.type === 'row') {
                parts.push(write_row(b));
            } else if (b.type === 'video') {
                if (clean_line(b.link)) parts.push(write_video(b));
            } else if (b.type === 'file') {
                var name = clean_line(b.name) || 'DATEINAME.pdf';
                parts.push(`file{${name}}{${clean_line(b.label) || name}}`);
            }
        });
        return parts.join('\n\n');
    }

    // Can the blocks show this text without changing what the website shows?
    function fits_blocks(markdown) {
        if (/^\s*(```|~~~)/m.test(markdown)) return false;
        return serialize(parse(markdown)) === canonical(markdown).trim();
    }

    // ---------- checks next to the blocks ----------

    function side_text_chars(index) {
        var b = blocks[index];
        var text = b.text || '';
        for (var i = index + 1; i < blocks.length && blocks[i].type === 'text'; i++) text += ' ' + blocks[i].text;
        return text.replace(/file\{[^}]*\}\{([^}]*)\}/g, '$1').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
            .replace(/[*_`>]/g, '').replace(/\s+/g, ' ').trim().length;
    }

    function is_float(b) { return !!b && b.type === 'image' && b.layout !== 'full'; }

    function first_image_index() {
        for (var i = 0; i < blocks.length; i++)
            if (blocks[i].type === 'image' || blocks[i].type === 'gallery' || blocks[i].type === 'row') return i;
        return -1;
    }

    // [text, {label, run}?] per block
    function block_warnings(index) {
        var b = blocks[index];
        var w = [];
        if (b.type === 'lead') {
            var n = b.text.replace(/\s+/g, ' ').trim().length;
            if (n === 0) w.push(['Fang mit ein, zwei Sätzen an: wer, was, wann.']);
        }
        if (b.type === 'video' && !clean_line(b.link))
            w.push(['Füg den Link des Videos auf YouTube ein.']);
        else if (b.type === 'video' && !parse_youtube(b.link))
            w.push(['Das ist kein Link zu einem YouTube-Video. Kopier ihn aus der Adresszeile oder über »Teilen« bei YouTube.']);
        if (b.type === 'image' && !clean_slug(b.slug))
            w.push(['Trag den Namen des Bildes ein (aus »Bilder hochladen«).']);
        if (b.type === 'gallery' && b.slugs.map(clean_slug).filter(function (x) { return x; }).length < 2)
            w.push(['Eine Galerie braucht mindestens zwei Fotos.']);
        if (b.type === 'row') {
            if (b.items.filter(function (i) { return clean_slug(i.slug); }).length < 2)
                w.push(['Trag die Namen von zwei oder drei Bildern ein.']);
            var own = b.items.every(function (i) { return clean_caption(i.caption); });
            var all = `${b.caption} ${b.items.map(function (i) { return i.caption; }).join(' ')}`;
            if (!own && !clean_caption(b.caption)) w.push(['Es fehlt eine Bildunterschrift: zu jedem Bild oder gemeinsam darunter.']);
            else if (!CREDIT.test(all)) w.push(['Nenn in einer Bildunterschrift, von wem die Fotos sind (»Fotos: Name«).']);
        }
        if (b.type === 'image' || b.type === 'gallery') {
            if (!clean_caption(b.caption)) w.push(['Es fehlt die Bildunterschrift mit Fotonachweis.']);
            else if (!CREDIT.test(b.caption)) w.push(['Nenn in der Bildunterschrift, von wem das Foto ist (»Foto: Name«).']);
        }
        if (is_float(b)) {
            var chars = side_text_chars(index);
            if (chars === 0 && is_float(blocks[index + 1])) {
                w.push(['Steht mit dem nächsten Bild als Paar nebeneinander. Ist das nicht gewollt, stell eines auf »Groß«.']);
            } else if (chars < NEWS_SIDE_TEXT_MIN) {
                var lines = Math.round(chars / NEWS_CHARS_PER_LINE);
                var amount = chars === 0 ? 'Noch steht kein Text daneben' : (lines <= 1 ? 'Daneben steht nur etwa eine Zeile' : `Daneben stehen nur etwa ${lines} Zeilen`);
                w.push([`${amount}, neben dem Bild bliebe Platz frei. Schreib mehr (vier, fünf Sätze) oder stell es auf »Groß«.`,
                    { label: 'Groß stellen', run: function () { set_layout(b, 'full'); } }]);
            }
        }
        return w;
    }

    function note_for(b, index) {
        var notes = [];
        if (b.type === 'lead') notes.push('Sag hier, was passiert ist: wer, was, wann. Steht ganz oben, vor dem ersten Bild, und erscheint als Beschreibung, wenn jemand den Link teilt.');
        if (b.type === 'image' && b.layout === 'full') notes.push('Über die ganze Breite, zwischen zwei Absätzen. Passt immer.');
        if (is_float(b)) notes.push('Steht ab Tablet-Breite neben dem Text, der direkt danach kommt, am Handy groß darüber. Braucht etwa fünf Zeilen Text.');
        if (b.type === 'row') notes.push('Zwei oder drei Bilder nebeneinander, alle im gewählten Format zugeschnitten; am Handy untereinander. Zieh jedes Bild im Rahmen an die Stelle, die zu sehen sein soll.');
        if (b.type === 'gallery') notes.push('Viele Fotos als Raster, am besten am Ende. Eine Bildunterschrift für alle.');
        if (b.type === 'video') notes.push('Ein Video von YouTube, eingebettet über youtube-nocookie.com im Format 16:9. Mit Startzeit, wenn der Link eine hat (t=).');
        if (b.type === 'file') notes.push('Ein Link zum Herunterladen, etwa ein Elternbrief als PDF (aus »Dateien hochladen«).');
        if (index === first_image_index()) notes.push('Das erste Bild erscheint als Vorschaubild, wenn jemand den Link teilt: Nimm das Foto, das den Artikel am besten zeigt.');
        return notes.join(' ');
    }

    // ---------- the blocks on the page ----------

    function icon(name) {
        return $('<i>').addClass(`ti ti-${name}`).attr('aria-hidden', 'true');
    }

    function quiet_button(label, icon_name, cls) {
        var b = $('<button type="button">').addClass(`btn pv-nb-quiet ${cls || ''}`);
        if (icon_name) b.append(icon(icon_name));
        return b.append($('<span>').text(label));
    }

    function icon_button(label, icon_name, cls) {
        return $('<button type="button">').addClass(`btn pv-nb-icon ${cls}`).attr('aria-label', label).attr('title', label).append(icon(icon_name));
    }

    function autosize(ta) {
        ta.style.height = 'auto';
        ta.style.height = `${Math.max(ta.scrollHeight + 2, 40)}px`;
    }

    function field(label, el, cls) {
        var id = `pv_nb_f${++uid}`;
        el.attr('id', id);
        return $('<div>').addClass(`pv-nb-field ${cls || ''}`).append($('<label>').attr('for', id).text(label)).append(el);
    }

    function text_area(b, key, placeholder, rows) {
        var ta = $('<textarea class="form-control">').attr('rows', rows || 3).attr('placeholder', placeholder).val(b[key] || '');
        ta.on('input', function (e) {
            b[key] = e.currentTarget.value;
            autosize(e.currentTarget);
            changed();
        });
        return ta;
    }

    function line_input(b, key, placeholder, list) {
        var input = $('<input type="text" class="form-control">').attr('placeholder', placeholder).val(b[key] || '');
        if (list) input.attr('list', list);
        input.on('input', function (e) {
            b[key] = e.currentTarget.value;
            changed();
        });
        return input;
    }

    // The image in its frame (the row's ratio), as on the website: it
    // covers the frame (object-fit: cover) and the author drags it – mouse,
    // touch or the arrow keys – to the part that should be seen. Only the
    // axis where the image is larger than the frame moves, and never so far
    // that a gap appears. item.crop: [x, y] in percent, object-position.
    function frame_picker(item, ratio, name) {
        var box = $('<div>').addClass('pv-nb-crop');
        var frame = $('<div>').addClass('pv-nb-crop-frame').attr('tabindex', '0').attr('role', 'group')
            .css('aspect-ratio', ratio.replace(':', ' / '));
        var img = $('<img alt="" draggable="false">');
        frame.append(img);
        var label = $('<span>').addClass('pv-nb-crop-label');
        var natural = null;  // [width, height] once loaded
        var show = function () {
            var c = item.crop || [50, 50];
            img.css('object-position', `${c[0]}% ${c[1]}%`);
            frame.attr('aria-label', `${name}: Bildausschnitt, ${c[0]} % von links, ${c[1]} % von oben. Mit den Pfeiltasten verschiebst du das Bild.`);
            label.text(c[0] === 50 && c[1] === 50 ? 'Mitte' : `${c[0]} % von links, ${c[1]} % von oben`);
        };
        // how far the image reaches beyond the frame (px), per axis
        var overflow = function () {
            var w = frame[0].clientWidth, h = frame[0].clientHeight;
            if (!natural || !w || !h) return null;
            var scale = Math.max(w / natural[0], h / natural[1]);
            return [natural[0] * scale - w, natural[1] * scale - h];
        };
        var set = function (x, y) {
            var c = [Math.max(0, Math.min(100, Math.round(x))), Math.max(0, Math.min(100, Math.round(y)))];
            if (item.crop && c[0] === item.crop[0] && c[1] === item.crop[1]) return;
            item.crop = c;
            show();
            changed();
        };
        var load = function () {
            var slug = clean_slug(item.slug);
            box.toggleClass('pv-nb-crop-empty', !slug);
            natural = null;
            if (slug) img.attr('src', `/gen/i/${slug}-512.jpg`);
        };
        img.on('load', function () {
            natural = img[0].naturalWidth && img[0].naturalHeight ? [img[0].naturalWidth, img[0].naturalHeight] : null;
            box.removeClass('pv-nb-crop-broken');
        });
        img.on('error', function () { natural = null; box.addClass('pv-nb-crop-broken'); });

        // dragging: the image follows the pointer
        var drag = null;
        frame.on('pointerdown', function (e) {
            var o = overflow();
            if (!o || e.button > 0) return;
            drag = { x: e.clientX, y: e.clientY, start: (item.crop || [50, 50]).slice(), o: o };
            e.currentTarget.setPointerCapture(e.pointerId);
            frame.addClass('pv-nb-crop-dragging');
            e.preventDefault();
        });
        frame.on('pointermove', function (e) {
            if (!drag) return;
            var dx = e.clientX - drag.x, dy = e.clientY - drag.y;
            set(drag.o[0] > 0.5 ? drag.start[0] - dx / drag.o[0] * 100 : drag.start[0],
                drag.o[1] > 0.5 ? drag.start[1] - dy / drag.o[1] * 100 : drag.start[1]);
        });
        frame.on('pointerup pointercancel', function () {
            drag = null;
            frame.removeClass('pv-nb-crop-dragging');
        });
        // the sheet on phones must not take the drag for closing
        frame[0].addEventListener('touchstart', function (e) { e.stopPropagation(); }, { passive: true });
        // the arrow keys move the image like a drag
        frame.on('keydown', function (e) {
            var moves = { ArrowLeft: [1, 0], ArrowRight: [-1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1] };
            if (!moves[e.key]) return;
            e.preventDefault();
            var o = overflow() || [1, 1];
            var step = e.shiftKey ? 10 : 5;
            var c = item.crop || [50, 50];
            set(o[0] > 0.5 ? c[0] + moves[e.key][0] * step : c[0], o[1] > 0.5 ? c[1] + moves[e.key][1] * step : c[1]);
        });
        box.on('pv-nb-slug', load);
        var reset = quiet_button('Mitte', null, 'bu_nb_crop_reset').on('click', function () { set(50, 50); });
        box.append(frame);
        box.append($('<div>').addClass('pv-nb-crop-bar').append(label).append(reset));
        load();
        show();
        return box;
    }

    function thumb(slug_input) {
        var img = $('<img alt="">').addClass('pv-nb-thumb').attr('hidden', true);
        var show = function () {
            var slug = clean_slug(slug_input.val());
            img.attr('hidden', true);
            if (slug) img.attr('src', `/gen/i/${slug}-256.jpg`);
        };
        img.on('load', function () { img.attr('hidden', false); });
        img.on('error', function () { img.attr('hidden', true); });
        slug_input.on('change', show);
        show();
        return img;
    }

    function block_body(b, index) {
        var body = $('<div>').addClass('pv-nb-body');
        if (b.type === 'lead') {
            body.append(text_area(b, 'text', 'Worum geht es? Ein, zwei Sätze, die neugierig machen.', 2).addClass('ti_nb_lead'));
        } else if (b.type === 'text') {
            body.append(text_area(b, 'text', 'Ein Absatz. **fett**, *kursiv*, [Link](https://…)', 4).addClass('ti_nb_text'));
        } else if (b.type === 'heading') {
            body.append(line_input(b, 'text', 'Zwischenüberschrift').addClass('ti_nb_heading').attr('aria-label', 'Zwischenüberschrift'));
        } else if (b.type === 'image') {
            var slug = line_input(b, 'slug', 'zum Beispiel sportfest-start', 'pv_nb_images').addClass('ti_nb_slug');
            body.append($('<div>').addClass('pv-nb-row').append(field('Bildname', slug, 'pv-nb-grow')).append(thumb(slug)));
            var layouts = $('<div>').addClass('pv-nb-layouts').attr('role', 'radiogroup').attr('aria-label', 'Wo das Bild steht');
            [['full', 'Groß'], ['left', 'Links neben Text'], ['right', 'Rechts neben Text']].forEach(function (l) {
                var opt = $('<button type="button">').addClass('btn pv-nb-layout').attr('role', 'radio')
                    .attr('aria-checked', b.layout === l[0] ? 'true' : 'false').attr('data-layout', l[0]).text(l[1]);
                opt.on('click', function (e) { set_layout(b, e.currentTarget.getAttribute('data-layout')); });
                layouts.append(opt);
            });
            body.append(layouts);
            body.append(field('Bildunterschrift mit Fotonachweis', line_input(b, 'caption', 'Was ist zu sehen? Foto: Vorname Name').addClass('ti_nb_caption')));
            if (b.layout !== 'full')
                body.append(field('Text neben dem Bild', text_area(b, 'text', 'Der Absatz, der neben dem Bild steht, mindestens fünf Zeilen.', 5).addClass('ti_nb_side_text')));
        } else if (b.type === 'gallery') {
            var list = $('<div>').addClass('pv-nb-gallery');
            b.slugs.forEach(function (s, i) {
                var input = $('<input type="text" class="form-control ti_nb_gallery_slug">').attr('list', 'pv_nb_images')
                    .attr('placeholder', `Bildname ${i + 1}`).attr('aria-label', `Bildname ${i + 1}`).val(s);
                input.on('input', function (e) { b.slugs[i] = e.currentTarget.value; changed(); });
                var row = $('<div>').addClass('pv-nb-row').append(input).append(thumb(input));
                if (b.slugs.length > 2)
                    row.append(icon_button('Foto entfernen', 'x', 'bu_nb_gallery_remove').on('click', function () {
                        b.slugs.splice(i, 1);
                        changed(true);
                    }));
                list.append(row);
            });
            body.append(list);
            if (b.slugs.length < GALLERY_MAX)
                body.append(quiet_button('Foto hinzufügen', 'plus', 'bu_nb_gallery_add').on('click', function () {
                    b.slugs.push('');
                    changed(true);
                    focus_block(b, '.ti_nb_gallery_slug:last');
                }));
            body.append(field('Bildunterschrift mit Fotonachweis', line_input(b, 'caption', 'Fotos: Vorname Name').addClass('ti_nb_caption')));
        } else if (b.type === 'row') {
            var ratios = $('<div>').addClass('pv-nb-layouts pv-nb-ratios').attr('role', 'radiogroup').attr('aria-label', 'Format der Bilder');
            NEWS_ROW_RATIOS.forEach(function (r) {
                ratios.append($('<button type="button">').addClass('btn pv-nb-layout pv-nb-ratio').attr('role', 'radio')
                    .attr('aria-checked', b.ratio === r ? 'true' : 'false').attr('data-ratio', r).text(r)
                    .on('click', function (e) {
                        b.ratio = e.currentTarget.getAttribute('data-ratio');
                        changed(true);
                        focus_block(b, `.pv-nb-ratio[data-ratio="${b.ratio}"]`);
                    }));
            });
            body.append($('<div>').addClass('pv-nb-field').append($('<span>').addClass('pv-nb-field-label').text('Format')).append(ratios));
            var items = $('<div>').addClass('pv-nb-row-items');
            b.items.forEach(function (item, i) {
                var one = $('<div>').addClass('pv-nb-row-item');
                var slug = $('<input type="text" class="form-control ti_nb_row_slug">').attr('list', 'pv_nb_images')
                    .attr('placeholder', `Bildname ${i + 1}`).attr('aria-label', `Bildname ${i + 1}`).val(item.slug);
                var cap = $('<input type="text" class="form-control ti_nb_row_caption">')
                    .attr('placeholder', 'Bildunterschrift. Foto: Name').attr('aria-label', `Bildunterschrift ${i + 1}`).val(item.caption);
                var picker = frame_picker(item, b.ratio, `Bild ${i + 1}`);
                slug.on('input', function (e) { item.slug = e.currentTarget.value; changed(); });
                slug.on('change', function () { picker.trigger('pv-nb-slug'); });
                cap.on('input', function (e) { item.caption = e.currentTarget.value; changed(); });
                var head = $('<div>').addClass('pv-nb-row').append(slug);
                if (b.items.length > 2)
                    head.append(icon_button('Bild entfernen', 'x', 'bu_nb_row_remove').on('click', function () {
                        b.items.splice(i, 1);
                        changed(true);
                    }));
                one.append(head).append(cap).append(picker);
                items.append(one);
            });
            body.append(items);
            if (b.items.length < ROW_MAX)
                body.append(quiet_button('Bild hinzufügen', 'plus', 'bu_nb_row_add').on('click', function () {
                    b.items.push({ slug: '', caption: '', crop: [50, 50] });
                    changed(true);
                    focus_block(b, '.ti_nb_row_slug:last');
                }));
            body.append(field('Gemeinsame Bildunterschrift (wenn du willst)', line_input(b, 'caption', 'Fotos: Vorname Name').addClass('ti_nb_caption')));
        } else if (b.type === 'video') {
            var link = line_input(b, 'link', 'https://www.youtube.com/watch?v=…').addClass('ti_nb_video_link');
            body.append(field('Link zum Video auf YouTube', link));
            var found = $('<p>').addClass('pv-nb-video-found');
            var show_found = function () {
                var v = parse_youtube(b.link);
                found.text(v ? `Video ${v.id}${v.start ? `, Start bei ${Math.floor(v.start / 60)}:${`${v.start % 60}`.padStart(2, '0')}` : ''}` : '');
                found.attr('hidden', !v);
            };
            link.on('input', show_found);
            show_found();
            body.append(found);
            body.append(field('Worum geht es im Video? (für Screenreader)', line_input(b, 'title', 'zum Beispiel Konzert der Big Band').addClass('ti_nb_video_title')));
        } else if (b.type === 'file') {
            body.append($('<div>').addClass('pv-nb-row pv-nb-wrap')
                .append(field('Dateiname', line_input(b, 'name', 'elternbrief.pdf', 'pv_nb_files').addClass('ti_nb_file_name'), 'pv-nb-grow'))
                .append(field('Beschriftung des Links', line_input(b, 'label', 'Der Elternbrief').addClass('ti_nb_file_label'), 'pv-nb-grow')));
        }
        return body;
    }

    function render_block(b, index) {
        var t = TYPES[b.type];
        var el = $('<section>').addClass(`pv-nb-block pv-nb-${b.type}`).attr('data-id', `${b.id}`).attr('data-type', b.type);
        var head = $('<div>').addClass('pv-nb-head');
        head.append(icon(t.icon).addClass('pv-nb-type-icon'));
        var label = t.label;
        if (b.type === 'image') label = b.layout === 'full' ? 'Bild groß' : `Bild ${b.layout === 'left' ? 'links' : 'rechts'} neben Text`;
        head.append($('<span>').addClass('pv-nb-label').text(label));
        var tools = $('<span>').addClass('pv-nb-tools');
        if (b.type !== 'lead') {
            var up = icon_button('Nach oben', 'arrow-up', 'bu_nb_up').prop('disabled', index <= 1);
            var down = icon_button('Nach unten', 'arrow-down', 'bu_nb_down').prop('disabled', index >= blocks.length - 1);
            up.on('click', function () { move(b, -1); });
            down.on('click', function () { move(b, 1); });
            tools.append(up).append(down);
        }
        tools.append(icon_button('Baustein darunter einfügen', 'plus', 'bu_nb_insert').on('click', function (e) {
            toggle_add_bar(el, index + 1, e.currentTarget);
        }));
        if (b.type !== 'lead')
            tools.append(icon_button('Baustein entfernen', 'trash', 'bu_nb_remove').on('click', function () { remove(b); }));
        head.append(tools);
        el.append(head);
        el.append(block_body(b, index));
        var note = note_for(b, index);
        if (note) el.append($('<p>').addClass('pv-nb-note').text(note));
        el.append($('<div>').addClass('pv-nb-warn').attr('aria-live', 'polite'));
        return el;
    }

    function add_bar(at) {
        var bar = $('<div>').addClass('pv-nb-add').attr('role', 'group').attr('aria-label', 'Baustein hinzufügen');
        ADD.forEach(function (type) {
            bar.append(quiet_button(TYPES[type].label, TYPES[type].icon, `bu_nb_add bu_nb_add_${type}`).attr('data-type', type)
                .on('click', function (e) { add(e.currentTarget.getAttribute('data-type'), at()); }));
        });
        return bar;
    }

    function toggle_add_bar(block_el, index, button) {
        var open = block_el.next('.pv-nb-add-inline');
        $('.pv-nb-add-inline').remove();
        $('.bu_nb_insert').attr('aria-expanded', 'false');
        if (open.length > 0) return;
        $(button).attr('aria-expanded', 'true');
        var bar = add_bar(function () { return index; }).addClass('pv-nb-add-inline');
        bar.insertAfter(block_el);
        bar.find('button').first().focus();
    }

    function render_blocks() {
        var list = $('.pv-nb-list');
        list.empty();
        blocks.forEach(function (b, i) { list.append(render_block(b, i)); });
        list.append($('<div>').addClass('pv-nb-add-title').text('Baustein hinzufügen'));
        list.append(add_bar(function () { return blocks.length; }).addClass('pv-nb-add-end'));
        list.find('textarea').each(function (_, ta) { autosize(ta); });
        update_warnings();
    }

    function update_warnings() {
        blocks.forEach(function (b, i) {
            var box = $(`.pv-nb-block[data-id="${b.id}"] .pv-nb-warn`);
            box.empty();
            block_warnings(i).forEach(function (w) {
                var line = $('<p>').append(icon('bulb')).append($('<span>').text(w[0]));
                if (w[1]) line.append(quiet_button(w[1].label, null, 'bu_nb_fix').on('click', w[1].run));
                box.append(line);
            });
        });
    }

    function focus_block(b, selector) {
        var el = $(`.pv-nb-block[data-id="${b.id}"]`);
        var target = el.find(selector || 'textarea, input').first();
        if (target.length) target.focus();
        if (el.length && el[0].scrollIntoView) el[0].scrollIntoView({ block: 'nearest' });
    }

    function new_block(type) {
        if (type === 'image') return { type: 'image', slug: '', caption: '', layout: 'full', width: DEFAULT_WIDTH, text: '' };
        if (type === 'gallery') return { type: 'gallery', slugs: ['', ''], caption: '' };
        if (type === 'row') return { type: 'row', ratio: '3:2', caption: '', items: [{ slug: '', caption: '', crop: [50, 50] }, { slug: '', caption: '', crop: [50, 50] }] };
        if (type === 'file') return { type: 'file', name: '', label: '' };
        if (type === 'video') return { type: 'video', link: '', title: '' };
        if (type === 'heading') return { type: 'heading', level: 2, text: '' };
        return { type: 'text', text: '' };
    }

    function add(type, at) {
        var b = new_block(type);
        b.id = ++uid;
        blocks.splice(Math.max(1, at), 0, b);
        changed(true);
        focus_block(b);
    }

    function move(b, step) {
        var i = blocks.indexOf(b), j = i + step;
        if (i < 1 || j < 1 || j >= blocks.length) return;
        blocks.splice(i, 1);
        blocks.splice(j, 0, b);
        changed(true);
        focus_block(b, step < 0 ? '.bu_nb_up' : '.bu_nb_down');
    }

    function remove(b) {
        var empty = function (x) {
            if (x.type === 'gallery') return x.slugs.every(function (s) { return !s.trim(); }) && !x.caption.trim();
            if (x.type === 'image') return !x.slug.trim() && !x.caption.trim() && !x.text.trim();
            if (x.type === 'file') return !x.name.trim() && !x.label.trim();
            if (x.type === 'video') return !x.link.trim() && !x.title.trim();
            if (x.type === 'row') return !x.caption.trim() && x.items.every(function (i) { return !i.slug.trim() && !i.caption.trim(); });
            return !(x.text || '').trim();
        };
        var go = function () {
            var i = blocks.indexOf(b);
            if (i < 1) return;
            blocks.splice(i, 1);
            changed(true);
            var next = blocks[Math.min(i, blocks.length - 1)];
            if (next) focus_block(next, '.bu_nb_remove, textarea, input');
        };
        if (empty(b)) { go(); return; }
        dashboardConfirm(`Den Baustein »${TYPES[b.type].label}« mit seinem Inhalt entfernen?`, go,
            { title: 'Baustein entfernen', confirm: 'Entfernen', cancel: 'Abbrechen', danger: true });
    }

    // Groß has no text of its own: switching to it, the text beside the
    // image becomes the paragraph after it; switching to beside the text,
    // the paragraph after the image becomes its text.
    function set_layout(b, layout) {
        if (b.layout === layout) return;
        var i = blocks.indexOf(b);
        if (layout === 'full') {
            if (b.text.trim()) {
                var t = { type: 'text', text: b.text, id: ++uid };
                blocks.splice(i + 1, 0, t);
            }
            b.text = '';
        } else if (b.layout === 'full') {
            var next = blocks[i + 1];
            if (next && next.type === 'text') {
                b.text = next.text;
                blocks.splice(i + 1, 1);
            }
        }
        b.layout = layout;
        changed(true);
        focus_block(b, `.pv-nb-layout[data-layout="${layout}"]`);
    }

    // after every change: the text for saving, the buttons, the checks and
    // (a moment later) the preview
    function changed(redraw) {
        $('#ta_markdown').val(serialize(blocks));
        if (redraw) render_blocks(); else update_warnings();
        update_buttons();
        schedule_preview();
    }

    function schedule_preview() {
        clearTimeout(preview_timer);
        preview_timer = setTimeout(function () {
            if ($('#editModal').hasClass('show') && pending_changes_preview()) news_render_preview(true);
        }, 700);
    }

    // ---------- modes: blocks or text ----------

    function set_mode(m, quiet) {
        var editor = $('#editModal');
        if (m === 'blocks') {
            var text = $('#ta_markdown').val();
            if (!fits_blocks(text)) {
                if (!quiet)
                    dashboardAlert('Dieser Text enthält Teile, die die Bausteine nicht zeigen können, ohne sie zu verändern (zum Beispiel Code-Blöcke). Du bearbeitest ihn deshalb als Text.', 'Bausteine');
                m = 'text';
            } else {
                blocks = parse(text);
                render_blocks();
            }
        }
        mode = m;
        editor.toggleClass('pv-nb-mode-blocks', mode === 'blocks').toggleClass('pv-nb-mode-text', mode === 'text');
        autosize_all();
        $('.pv-nb-mode').each(function (_, b) {
            b.setAttribute('aria-pressed', b.getAttribute('data-mode') === mode ? 'true' : 'false');
        });
    }

    // ---------- the preview at the website's widths ----------

    var width = 'desktop';

    function set_width(w) {
        width = w;
        $('.pv-nb-width').each(function (_, b) {
            b.setAttribute('aria-pressed', b.getAttribute('data-width') === w ? 'true' : 'false');
        });
        fit_frame();
    }

    function fit_frame() {
        var stage = document.querySelector('.pv-nb-stage');
        var frame = document.querySelector('.pv-nb-frame');
        if (!stage || !frame) return;
        var w = WIDTHS[width];
        frame.style.width = `${w + 30}px`;
        var room = stage.clientWidth - 16;
        frame.style.zoom = room > 0 && room < w + 30 ? `${room / (w + 30)}` : '';
        frame.setAttribute('data-width', width);
    }

    // YouTube videos stay embedded; the website shows other embedded content
    // as a link on the article page
    function replace_embeds() {
        document.querySelectorAll('#ta_preview iframe').forEach(function (frame) {
            var src = frame.getAttribute('src') || '';
            if (parse_youtube(src)) return;
            var youtube = false;
            var p = document.createElement('div');
            p.className = 'pv-nb-embed';
            var a = document.createElement('a');
            if (/^https?:\/\//.test(src)) a.href = src;
            a.target = '_blank';
            a.rel = 'noopener';
            a.textContent = youtube ? 'Video auf YouTube ansehen' : 'Eingebetteten Inhalt öffnen';
            p.appendChild(a);
            frame.replaceWith(p);
        });
    }

    function after_preview() {
        replace_embeds();
        fit_frame();
    }

    // phones: one column, »Bausteine« or »Vorschau«
    function set_pane(p) {
        $('#editModal').toggleClass('pv-nb-show-preview', p === 'preview');
        $('.pv-nb-pane').each(function (_, b) {
            b.setAttribute('aria-selected', b.getAttribute('data-pane') === p ? 'true' : 'false');
        });
        if (p === 'preview') fit_frame(); else autosize_all();
    }

    // textareas get their height once they can be seen
    function autosize_all() {
        $('.pv-nb-list textarea:visible').each(function (_, ta) { autosize(ta); });
    }

    function segmented(cls, label, options, on) {
        var group = $('<div>').addClass(`pv-nb-seg ${cls}-group`).attr('role', 'group').attr('aria-label', label);
        options.forEach(function (o) {
            var b = $('<button type="button">').addClass(`btn ${cls}`).attr(`data-${o.key}`, o.value).attr('aria-pressed', 'false');
            if (o.icon) b.append(icon(o.icon));
            b.append($('<span>').text(o.label));
            b.on('click', function (e) { on(e.currentTarget.getAttribute(`data-${o.key}`)); });
            group.append(b);
        });
        return group;
    }

    function suggestions() {
        var load = function (url, key, id, name) {
            fetch(url, { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: '{}' })
                .then(function (r) { return r.ok ? r.json() : null; })
                .then(function (data) {
                    if (!data || !data[key]) return;
                    var list = $('<datalist>').attr('id', id);
                    data[key].slice(0, 500).forEach(function (x) { list.append($('<option>').attr('value', name(x))); });
                    $(`#${id}`).remove();
                    $('body').append(list);
                })
                .catch(function () { });
        };
        load('/api/get_all_images', 'images', 'pv_nb_images', function (x) { return x.slug; });
        load('/api/get_all_files', 'files', 'pv_nb_files', function (x) { return x.name; });
    }

    function setup() {
        var modal = $('#editModal');
        modal.addClass('pv-nb-editor pv-sheet');
        // above the tab bar on phones, like every dialog of the new design
        modal.appendTo(document.body);
        var write = modal.find('.news-write-col');
        var show = modal.find('.news-preview-col');
        $('.ti_title').attr('placeholder', 'Titel, kurz und konkret').attr('aria-label', 'Titel');

        // phones: Bausteine | Vorschau
        var panes = $('<div>').addClass('pv-nb-panes').attr('role', 'tablist');
        [['edit', 'Bearbeiten'], ['preview', 'Vorschau']].forEach(function (p) {
            panes.append($('<button type="button" role="tab">').addClass('btn pv-nb-pane').attr('data-pane', p[0]).text(p[1])
                .on('click', function (e) { set_pane(e.currentTarget.getAttribute('data-pane')); }));
        });
        modal.find('.modal-body').prepend(panes);

        // the left column: title, blocks or text
        var modes = segmented('pv-nb-mode', 'Bearbeiten als', [
            { key: 'mode', value: 'blocks', label: 'Bausteine', icon: 'layout-list' },
            { key: 'mode', value: 'text', label: 'Text bearbeiten', icon: 'code' },
        ], function (m) { set_mode(m); });
        $('.ti_title').after(modes);
        modes.after($('<div>').addClass('pv-nb-list'));
        // »Text bearbeiten«: the guide above the buttons and the text
        write.find('.news-blocks').before($('#news_guide'));
        $('#ta_markdown').attr('placeholder', 'Schreib hier deinen Artikel (Markdown). Wie ein guter Artikel aufgebaut ist, steht oben unter »So baust du einen Artikel auf«.');

        // the right column: widths, then the article as on the website
        var widths = segmented('pv-nb-width', 'Breite der Vorschau', [
            { key: 'width', value: 'phone', label: 'Handy', icon: 'device-mobile' },
            { key: 'width', value: 'tablet', label: 'Tablet', icon: 'device-tablet' },
            { key: 'width', value: 'desktop', label: 'Desktop', icon: 'device-desktop' },
        ], set_width);
        var bar = $('<div>').addClass('pv-nb-preview-bar').append($('<span>').addClass('pv-nb-preview-title').text('Vorschau')).append(widths);
        write.append($('<div>').addClass('pv-nb-link').attr('hidden', true));
        var stage = $('<div>').addClass('pv-nb-stage');
        var frame = $('<div>').addClass('pv-nb-frame');
        frame.append($('#preview_heading')).append($('#ta_preview'));
        stage.append(frame);
        show.prepend(bar);
        bar.after(stage);
        document.addEventListener('news-preview-rendered', after_preview);
        $('#ta_preview').removeAttr('style');
        $('<datalist id="pv_nb_images">').appendTo('body');
        $('<datalist id="pv_nb_files">').appendTo('body');

        $(window).on('resize', fit_frame);
        modal.on('shown.bs.modal', function () { fit_frame(); autosize_all(); });
        set_width(window.matchMedia('(max-width: 767px)').matches ? 'phone' : 'desktop');
        set_pane('edit');
        $('.ti_title').on('input', function () { if (mode === 'blocks') schedule_preview(); });
        $(document).on('keydown', '.pv-nb-list textarea, .pv-nb-list input', function (e) {
            if (e.keyCode === 13 && e.ctrlKey) news_render_preview();
        });
    }

    // the article's address on the website: to copy once it is published
    function show_link(info) {
        var box = $('.pv-nb-link');
        box.empty();
        var url = info && window.pv_news_public_url ? pv_news_public_url(info.timestamp) : null;
        box.attr('hidden', !url);
        if (!url) return;
        if (info.published) {
            box.append($('<span>').addClass('pv-nb-link-label').text('Auf der Website:'));
            box.append(pv_copy.field(url, { what: 'Link', cls: 'pv-nb-link-copy' }));
        } else {
            box.append($('<span>').text(`Nach dem Veröffentlichen unter ${url}`));
        }
    }

    // the page opens an article (or a new one): the text is in #ta_markdown
    function load(markdown, is_new, info) {
        show_link(is_new ? null : info);
        if (images === null) { images = true; suggestions(); }
        set_pane('edit');
        set_mode('blocks', true);
        if (is_new) {
            // a new article starts with its lead and one paragraph
            blocks = parse('');
            var t = { type: 'text', text: '', id: ++uid };
            blocks.push(t);
            render_blocks();
        }
        fit_frame();
    }

    window.pv_news_editor = {
        load: load,
        // for tests
        parse: function (m) { return parse(m); },
        serialize: function (m) { return serialize(parse(m)); },
        fits: function (m) { return fits_blocks(m); },
        youtube: function (l) { return parse_youtube(l); },
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
})();
