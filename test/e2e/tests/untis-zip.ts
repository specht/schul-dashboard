// A small Untis HTML export – teacher and class timetables as a ZIP – as the
// parser reads it (Parser#read_untis_zip): built from timetable rows for the
// tests of the timetable upload on /datenpflege. Stored without compression.

export type Lesson = { klasse: string, lehrer: string, fach: string, raum: string, dow: number, stunde: number };
export type Aufsicht = { where: string, lehrer: string, dow: number, stunde: number };

const DAYS = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

function td(text: string, attrs = '') {
  return `<td${attrs}>${text}</td>`;
}

// one timetable page: lines per slot (each line: the columns side by side),
// break duties per slot as white cells
function page(name: string, slots: Map<string, string[][]>, duties: Map<string, string[]>, hours: number) {
  let html = `<html><body><font size="6">${name}</font>\n<table border="3">\n<tr><td></td>`;
  for (const d of DAYS) html += `<td><table><tr>${td(d)}</tr></table></td>`;
  html += '</tr>\n';
  for (let h = 1; h <= hours; h++) {
    html += `<tr><td><table><tr>${td(String(h))}</tr></table></td>`;
    for (let d = 1; d <= 5; d++) {
      const lines = slots.get(`${d}/${h}`) || [];
      const here = duties.get(`${d}/${h}`) || [];
      const rows = lines.map((cols) => `<tr>${cols.map((c) => td(c)).join('')}</tr>`);
      for (const where of here) rows.push(`<tr>${td(where, ' bgcolor="#FFFFFF"')}</tr>`);
      html += rows.length ? `<td><table>${rows.join('')}</table></td>` : '<td></td>';
    }
    html += '</tr>\n';
  }
  return html + '</table></body></html>\n';
}

export function untisPages(lessons: Lesson[], aufsichten: Aufsicht[] = []): Record<string, string> {
  const hours = Math.max(8, ...lessons.map((l) => l.stunde));
  const pages: Record<string, string> = {};
  const teachers = [...new Set(lessons.map((l) => l.lehrer).concat(aufsichten.map((a) => a.lehrer)))];
  for (const t of teachers) {
    const slots = new Map<string, string[][]>();
    const bySlot = new Map<string, Lesson[]>();
    for (const l of lessons.filter((x) => x.lehrer === t)) {
      const key = `${l.dow}/${l.stunde}`;
      bySlot.set(key, [...(bySlot.get(key) || []), l]);
    }
    for (const [key, ls] of bySlot) {
      // several classes of one lesson: the first with a dot (»11.«)
      const klasse = ls.length > 1 ? `${ls[0].klasse}.` : ls[0].klasse;
      slots.set(key, [[klasse], [ls[0].fach], [ls[0].raum]]);
    }
    const duties = new Map<string, string[]>();
    for (const a of aufsichten.filter((x) => x.lehrer === t)) {
      const key = `${a.dow}/${a.stunde}`;
      duties.set(key, [...(duties.get(key) || []), a.where]);
    }
    pages[`${t}.htm`] = page(t, slots, duties, hours);
  }
  for (const k of [...new Set(lessons.map((l) => l.klasse))]) {
    const slots = new Map<string, string[][]>();
    const bySlot = new Map<string, Lesson[]>();
    for (const l of lessons.filter((x) => x.klasse === k)) {
      const key = `${l.dow}/${l.stunde}`;
      bySlot.set(key, [...(bySlot.get(key) || []), l]);
    }
    // the class timetables: subject / teacher / room, side by side
    for (const [key, ls] of bySlot) slots.set(key, [ls.map((l) => l.fach), ls.map((l) => l.lehrer), ls.map((l) => l.raum)]);
    pages[`${k}.htm`] = page(k, slots, new Map(), hours);
  }
  return pages;
}

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(buf: Buffer) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// a ZIP of the files, stored (no compression)
export function zip(files: Record<string, string>): Buffer {
  const parts: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const data = Buffer.from(text, 'latin1');
    const fname = Buffer.from(name, 'latin1');
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0, 6); local.writeUInt16LE(0, 8);
    local.writeUInt32LE(0, 10); local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(fname.length, 26); local.writeUInt16LE(0, 28);
    parts.push(local, fname, data);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0); entry.writeUInt16LE(20, 4); entry.writeUInt16LE(20, 6); entry.writeUInt16LE(0, 8);
    entry.writeUInt16LE(0, 10); entry.writeUInt32LE(0, 12); entry.writeUInt32LE(crc, 16); entry.writeUInt32LE(data.length, 20);
    entry.writeUInt32LE(data.length, 24); entry.writeUInt16LE(fname.length, 28); entry.writeUInt16LE(0, 30); entry.writeUInt16LE(0, 32);
    entry.writeUInt16LE(0, 34); entry.writeUInt16LE(0, 36); entry.writeUInt32LE(0, 38); entry.writeUInt32LE(offset, 42);
    central.push(entry, fname);
    offset += 30 + fname.length + data.length;
  }
  const dir = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(0, 4); end.writeUInt16LE(0, 6);
  end.writeUInt16LE(Object.keys(files).length, 8); end.writeUInt16LE(Object.keys(files).length, 10);
  end.writeUInt32LE(dir.length, 12); end.writeUInt32LE(offset, 16); end.writeUInt16LE(0, 20);
  return Buffer.concat([...parts, dir, end]);
}

export function untisZip(lessons: Lesson[], aufsichten: Aufsicht[] = []): Buffer {
  return zip(untisPages(lessons, aufsichten));
}
