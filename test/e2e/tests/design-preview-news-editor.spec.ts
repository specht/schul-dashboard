import { test, expect, login, ACCOUNTS, dashboardDialog, listAction } from './fixtures';
import type { Page } from '@playwright/test';

// Neues Design: the news editor as building blocks (preview/news.js).
// An article is put together from Einstieg, Absatz, Zwischenüberschrift,
// Bild (groß, links or rechts neben seinem Text), Bilderreihe, Galerie,
// Video and Datei; the stored text stays Markdown with image{…},
// images{…}{…}, gallery{…} and file{…}{…}. The preview shows the article
// at the website's widths.
// Example articles are invented.

const LONG = 'Lang erzählter Absatz mit vielen Einzelheiten über den Tag. '.repeat(7).trim();

async function openNew(page: Page) {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.goto('/manage_news');
  await page.locator('.bu-compose:visible').first().click();
  await expect(page.locator('#editModal')).toBeVisible();
}

const markdown = (page: Page) => page.locator('#ta_markdown').inputValue();
const block = (page: Page, n: number) => page.locator('.pv-nb-list > .pv-nb-block').nth(n);

async function addBlock(page: Page, label: string) {
  await page.locator('.pv-nb-add-end').getByRole('button', { name: label, exact: true }).click();
}

// phones: »Bearbeiten« and »Vorschau« are panes of their own
async function pane(page: Page, name: 'edit' | 'preview') {
  const tab = page.locator(`.pv-nb-pane[data-pane="${name}"]`);
  if (await tab.isVisible()) await tab.click();
}

test('Neues Design: ein Artikel aus Bausteinen', async ({ page }) => {
  try {
    await openNew(page);
    await expect(page.locator('.pv-nb-mode[aria-pressed="true"]')).toHaveText('Bausteine');
    await expect(page.locator('#ta_markdown')).toBeHidden();
    // a new article: Einstieg and one paragraph, each with its short hint
    await expect(page.locator('.pv-nb-list > .pv-nb-block')).toHaveCount(2);
    await expect(block(page, 0)).toHaveAttribute('data-type', 'lead');
    await expect(block(page, 0).locator('.pv-nb-note')).toContainText('wer, was, wann');
    await expect(block(page, 0).locator('.pv-nb-warn')).toContainText('wer, was, wann');
    await expect(block(page, 0).locator('.bu_nb_remove')).toHaveCount(0);

    await page.locator('.ti_title').fill('Sportfest der 7. Klassen');
    await block(page, 0).locator('textarea').fill('Am Freitag haben alle siebten Klassen beim Sportfest um Punkte gekämpft.');
    await expect(block(page, 0).locator('.pv-nb-warn')).toBeEmpty();
    await block(page, 1).locator('textarea').fill(LONG);
    await expect(page.locator('#bu_save')).toBeEnabled();

    // an image: large by default, with its caption
    await addBlock(page, 'Bild');
    const image = block(page, 2);
    await expect(image).toHaveAttribute('data-type', 'image');
    await expect(image.locator('.pv-nb-layout[aria-checked="true"]')).toHaveText('Groß');
    await expect(image.locator('.pv-nb-warn')).toContainText('Trag den Namen des Bildes ein');
    await image.locator('.ti_nb_slug').fill('sportfest-start');
    await image.locator('.ti_nb_caption').fill('Der Start');
    await expect(image.locator('.pv-nb-warn')).toContainText('von wem das Foto ist');
    await image.locator('.ti_nb_caption').fill('Der Start. Foto: Erika Beispiel');
    await expect(image.locator('.pv-nb-warn')).toBeEmpty();
    await expect(image.locator('.pv-nb-note')).toContainText('Vorschaubild, wenn jemand den Link teilt');
    expect(await markdown(page)).toBe(
      `Am Freitag haben alle siebten Klassen beim Sportfest um Punkte gekämpft.\n\n${LONG}\n\nimage{sportfest-start, "Der Start. Foto: Erika Beispiel"}`);

    // up: between lead and paragraph; then beside the text: the paragraph
    // after it becomes its text
    await image.locator('.bu_nb_up').click();
    await expect(block(page, 1)).toHaveAttribute('data-type', 'image');
    await block(page, 1).locator('.pv-nb-layout', { hasText: 'Rechts neben Text' }).click();
    await expect(page.locator('.pv-nb-list > .pv-nb-block')).toHaveCount(2);
    await expect(block(page, 1).locator('.pv-nb-label')).toHaveText('Bild rechts neben Text');
    await expect(block(page, 1).locator('.ti_nb_side_text')).toHaveValue(LONG);
    expect(await markdown(page)).toBe(
      `Am Freitag haben alle siebten Klassen beim Sportfest um Punkte gekämpft.\n\nimage{sportfest-start, r5, "Der Start. Foto: Erika Beispiel"}\n\n${LONG}`);

    // too little text beside it: a hint, with a way out
    await block(page, 1).locator('.ti_nb_side_text').fill('Kurz.');
    const warn = block(page, 1).locator('.pv-nb-warn');
    await expect(warn).toContainText('neben dem Bild bliebe Platz frei');
    await warn.getByRole('button', { name: 'Groß stellen' }).click();
    await expect(page.locator('.pv-nb-list > .pv-nb-block')).toHaveCount(3);
    await expect(block(page, 1).locator('.pv-nb-layout[aria-checked="true"]')).toHaveText('Groß');
    await expect(block(page, 2)).toHaveAttribute('data-type', 'text');
    await expect(block(page, 2).locator('textarea')).toHaveValue('Kurz.');

    // a gallery and a file at the end, inserted below a block with its »+«
    await addBlock(page, 'Galerie');
    const gallery = block(page, 3);
    await gallery.locator('.ti_nb_gallery_slug').nth(0).fill('sportfest-1');
    await gallery.locator('.ti_nb_gallery_slug').nth(1).fill('sportfest-2');
    await gallery.locator('.bu_nb_gallery_add').click();
    await gallery.locator('.ti_nb_gallery_slug').nth(2).fill('sportfest-3');
    await gallery.locator('.ti_nb_caption').fill('Fotos: Erika Beispiel');
    await block(page, 2).locator('.bu_nb_insert').click();
    await page.locator('.pv-nb-add-inline .bu_nb_add', { hasText: 'Zwischenüberschrift' }).click();
    await block(page, 3).locator('.ti_nb_heading').fill('Die Siegerehrung');
    await addBlock(page, 'Datei');
    await block(page, 5).locator('.ti_nb_file_name').fill('urkunden.pdf');
    await block(page, 5).locator('.ti_nb_file_label').fill('Alle Urkunden');
    expect(await markdown(page)).toBe([
      'Am Freitag haben alle siebten Klassen beim Sportfest um Punkte gekämpft.',
      'image{sportfest-start, "Der Start. Foto: Erika Beispiel"}',
      'Kurz.',
      '## Die Siegerehrung',
      'gallery{sportfest-1, sportfest-2, sportfest-3, "Fotos: Erika Beispiel"}',
      'file{urkunden.pdf}{Alle Urkunden}',
    ].join('\n\n'));

    // removing a block with content asks first
    await block(page, 5).locator('.bu_nb_remove').click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toBeVisible();
    await dialog.getByRole('button', { name: 'Entfernen' }).click();
    await expect(page.locator('.pv-nb-list > .pv-nb-block')).toHaveCount(5);
    expect(await markdown(page)).not.toContain('file{');

    // the preview follows by itself, at the website's widths
    await block(page, 2).locator('textarea').fill(`Kurz. ${LONG} ${LONG}`);
    await block(page, 1).locator('.pv-nb-layout', { hasText: 'Links neben Text' }).click();
    const rendered = page.waitForResponse('**/api/get_news_preview');
    await expect(block(page, 1).locator('.ti_nb_side_text')).toHaveValue(`Kurz. ${LONG} ${LONG}`);
    expect((await rendered).status()).toBe(200);
    await pane(page, 'preview');
    const preview = page.locator('#ta_preview');
    await expect(preview.locator('.image-float.pull-left')).toHaveCount(1);
    await expect(preview.locator('.image-gallery .gallery-item')).toHaveCount(3);
    await page.locator('.pv-nb-width', { hasText: 'Desktop' }).click();
    await expect(page.locator('.pv-nb-frame')).toHaveAttribute('data-width', 'desktop');
    await expect(preview.locator('.image-float')).toHaveCSS('float', 'left');
    await page.locator('.pv-nb-width', { hasText: 'Handy' }).click();
    await expect(preview.locator('.image-float')).toHaveCSS('float', 'none');
    await page.locator('.pv-nb-width', { hasText: 'Tablet' }).click();
    await expect(preview.locator('.image-float')).toHaveCSS('float', 'left');

    // »Text bearbeiten« shows the same text; back to the blocks
    await pane(page, 'edit');
    await page.locator('.pv-nb-mode', { hasText: 'Text bearbeiten' }).click();
    await expect(page.locator('#ta_markdown')).toBeVisible();
    await expect(page.locator('.pv-nb-list')).toBeHidden();
    await expect(page.locator('.news-blocks')).toBeVisible();
    await page.locator('#ta_markdown').fill('Neuer Einstieg.\n\n## Weiter\n\nSchluss.');
    await page.locator('.pv-nb-mode', { hasText: 'Bausteine' }).click();
    await expect(page.locator('.pv-nb-list > .pv-nb-block')).toHaveCount(3);
    await expect(block(page, 0).locator('textarea')).toHaveValue('Neuer Einstieg.');
    await expect(block(page, 1).locator('.ti_nb_heading')).toHaveValue('Weiter');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: vorhandene Artikel öffnen unverändert in den Bausteinen', async ({ page }, testInfo) => {
  const suffix = `${testInfo.project.name} ${Date.now().toString(36)}`;
  // as authors write today: an image beside the text glued to its
  // paragraph, no blank line before a heading's text, spaces in the includes
  const content = [
    'Die Theater-AG hat am Mittwoch ihr neues Stück gezeigt.',
    '',
    'image{theater-buehne,r6,"Auf der Bühne. Foto: Max Muster"}',
    LONG,
    '',
    '## Applaus',
    '',
    'Am Ende gab es viel Applaus.',
    '- für die Technik',
    '- für die Kostüme',
    '',
    'image{theater-ende}',
    '',
    'Hier gibt es das Programmheft: file{programm.pdf}{Programmheft}',
  ].join('\n');
  const code = 'Ein Beispiel:\n\n```\nzeile 1\n\n\nzeile 2\n```';
  const titles = { plain: `Theater ${suffix}`, code: `Code ${suffix}` };
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  for (const [key, text] of [['plain', content], ['code', code]] as const) {
    expect((await page.request.post('/api/store_news_entry', { data: { title: titles[key], content: text } })).status()).toBe(200);
    // entries are keyed by the second they were stored in
    await page.waitForTimeout(1100);
  }
  const year = new Date().getFullYear();
  const entries = async () => ((await (await page.request.post('/api/get_news', { data: { year } })).json()).news as any[])
    .filter((n) => Object.values(titles).includes(n.title));
  try {
    await page.goto('/manage_news');
    const open = async (title: string) => {
      const row = page.locator('.pv-news-entry', { hasText: title });
      const loaded = page.waitForResponse('**/api/get_news_entry');
      await listAction(page, row, 'Bearbeiten');
      await loaded;
      await expect(page.locator('#editModal')).toBeVisible();
    };
    await open(titles.plain);
    await expect(page.locator('.pv-nb-mode[aria-pressed="true"]')).toHaveText('Bausteine');
    const types = await page.locator('.pv-nb-list > .pv-nb-block').evaluateAll((els) => els.map((e) => e.getAttribute('data-type')));
    expect(types).toEqual(['lead', 'image', 'heading', 'text', 'image', 'text']);
    await expect(block(page, 1).locator('.pv-nb-label')).toHaveText('Bild rechts neben Text');
    await expect(block(page, 1).locator('.ti_nb_side_text')).toHaveValue(LONG);
    await expect(block(page, 3).locator('textarea')).toHaveValue('Am Ende gab es viel Applaus.\n- für die Technik\n- für die Kostüme');
    await expect(block(page, 4).locator('.pv-nb-warn')).toContainText('Es fehlt die Bildunterschrift');
    // nothing changed: the text is exactly the stored one, nothing to save
    expect(await markdown(page)).toBe(content);
    await expect(page.locator('#bu_save')).toBeDisabled();
    // a change writes the whole article the editor's way
    await block(page, 4).locator('.ti_nb_caption').fill('Verbeugung. Foto: Erika Beispiel');
    await expect(page.locator('#bu_save')).toBeEnabled();
    expect(await markdown(page)).toContain('image{theater-buehne, r6, "Auf der Bühne. Foto: Max Muster"}\n\n' + LONG);
    expect(await markdown(page)).toContain('image{theater-ende, "Verbeugung. Foto: Erika Beispiel"}');
    await page.locator('#bu_discard').click();
    await expect(page.locator('#editModal')).toBeHidden();

    // text the blocks can't show unchanged: opens as text
    await open(titles.code);
    await expect(page.locator('.pv-nb-mode[aria-pressed="true"]')).toHaveText('Text bearbeiten');
    await expect(page.locator('#ta_markdown')).toBeVisible();
    await expect(page.locator('#ta_markdown')).toHaveValue(code);
    await page.locator('.pv-nb-mode', { hasText: 'Bausteine' }).click();
    const dialog = dashboardDialog(page);
    await expect(dialog).toContainText('Code-Blöcke');
    await dialog.getByRole('button', { name: 'OK' }).click();
    await expect(page.locator('.pv-nb-mode[aria-pressed="true"]')).toHaveText('Text bearbeiten');
  } finally {
    for (const e of await entries())
      await page.request.post('/api/delete_news_entry', { data: { timestamp: e.timestamp } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: ein Video von YouTube als Baustein', async ({ page }) => {
  // no requests to YouTube from the test stack
  await page.route(/youtube(-nocookie)?\.com|ytimg\.com/, (route) => route.fulfill({ status: 204, body: '' }));
  try {
    await openNew(page);
    await block(page, 0).locator('textarea').fill('Die Big Band hat gespielt.');
    await addBlock(page, 'Video');
    const video = block(page, 2);
    await expect(video).toHaveAttribute('data-type', 'video');
    await expect(video.locator('.pv-nb-warn')).toContainText('Link des Videos');
    await video.locator('.ti_nb_video_link').fill('https://example.org/watch?v=abc');
    await expect(video.locator('.pv-nb-warn')).toContainText('kein Link zu einem YouTube-Video');
    // the common forms of a link, with and without a start time
    for (const [link, src] of [
      ['https://www.youtube.com/watch?v=dQw4w9WgXcQ', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'],
      ['https://youtu.be/dQw4w9WgXcQ?t=90', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=90'],
      ['https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=1m5s', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=65'],
      ['https://www.youtube.com/shorts/dQw4w9WgXcQ', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'],
      ['https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=12', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=12'],
    ]) {
      await video.locator('.ti_nb_video_link').fill(link);
      expect(await markdown(page)).toContain(`<iframe src="${src}" `);
    }
    await expect(video.locator('.pv-nb-warn')).toBeEmpty();
    await expect(video.locator('.pv-nb-video-found')).toHaveText('Video dQw4w9WgXcQ, Start bei 0:12');
    await video.locator('.ti_nb_video_title').fill('Konzert der Big Band');
    expect(await markdown(page)).toBe('Die Big Band hat gespielt.\n\n' +
      '<div class="embed-responsive embed-responsive-16by9" style="margin-bottom: 2em;"><iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=12" ' +
      'title="Konzert der Big Band" loading="lazy" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" ' +
      'allowfullscreen style="display: block; width: 100%;"></iframe></div>');

    // the preview shows the embed
    await pane(page, 'preview');
    await expect(page.locator('#ta_preview .embed-responsive iframe')).toHaveAttribute('src', 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?start=12');

    // the way articles have embedded videos so far opens as a video block
    await pane(page, 'edit');
    await page.locator('.pv-nb-mode', { hasText: 'Text bearbeiten' }).click();
    await page.locator('#ta_markdown').fill('Einstieg.\n\n<div class="embed-responsive embed-responsive-16by9" style="margin-bottom: 2em;"><iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ" frameborder="0" allow="autoplay; encrypted-media" allowfullscreen="" style="display: block; width: 100%;"></iframe></div>');
    await page.locator('.pv-nb-mode', { hasText: 'Bausteine' }).click();
    await expect(block(page, 1)).toHaveAttribute('data-type', 'video');
    await expect(block(page, 1).locator('.ti_nb_video_link')).toHaveValue('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: eine Bilderreihe mit Format und Bildausschnitt', async ({ page }) => {
  // the images: a wide picture, so the picking area has its proportions
  await page.route(/\/gen\/i\//, (route) => route.fulfill({
    contentType: 'image/svg+xml',
    body: '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="600"><rect width="900" height="600" fill="#579"/></svg>',
  }));
  try {
    await openNew(page);
    await block(page, 0).locator('textarea').fill('Zwei Bilder vom Sportfest.');
    await addBlock(page, 'Bilderreihe');
    const row = block(page, 2);
    await expect(row).toHaveAttribute('data-type', 'row');
    await expect(row.locator('.pv-nb-ratio[aria-checked="true"]')).toHaveText('3:2');
    await expect(row.locator('.pv-nb-row-item')).toHaveCount(2);
    await expect(row.locator('.pv-nb-warn')).toContainText('zwei oder drei Bildern');
    await row.locator('.ti_nb_row_slug').nth(0).fill('lauf-1');
    await row.locator('.ti_nb_row_slug').nth(0).dispatchEvent('change');
    await row.locator('.ti_nb_row_slug').nth(1).fill('lauf-2');
    await row.locator('.ti_nb_row_slug').nth(1).dispatchEvent('change');
    await row.locator('.ti_nb_row_caption').nth(0).fill('Der Start');
    await expect(row.locator('.pv-nb-warn')).toContainText('Es fehlt eine Bildunterschrift');
    await row.locator('.ti_nb_caption').fill('Fotos: Erika Beispiel');
    await expect(row.locator('.pv-nb-warn')).toBeEmpty();
    expect(await markdown(page)).toBe('Zwei Bilder vom Sportfest.\n\nimages{3:2, "Fotos: Erika Beispiel"}{image{lauf-1, "Der Start"} image{lauf-2}}');

    // the format: one for all images of the row
    await row.locator('.pv-nb-ratio', { hasText: '1:1' }).click();
    await expect(block(page, 2).locator('.pv-nb-ratio[aria-checked="true"]')).toHaveText('1:1');
    expect(await markdown(page)).toContain('images{1:1, "Fotos: Erika Beispiel"}');

    // the image in its 1:1 frame: wider than the frame (3:2), so it moves
    // sideways only; dragging it right shows more of its left part
    const first = block(page, 2).locator('.pv-nb-row-item').nth(0);
    const frame = first.locator('.pv-nb-crop-frame');
    await expect(frame).toBeVisible();
    await expect.poll(() => first.locator('.pv-nb-crop-frame img').evaluate((i: HTMLImageElement) => i.naturalWidth)).toBe(900);
    const label = first.locator('.pv-nb-crop-label');
    const drag = async (dx: number, dy: number) => {
      const r = (await frame.boundingBox())!;
      await page.mouse.move(r.x + r.width / 2, r.y + r.height / 2);
      await page.mouse.down();
      await page.mouse.move(r.x + r.width / 2 + dx * r.width, r.y + r.height / 2 + dy * r.height, { steps: 4 });
      await page.mouse.up();
    };
    // the overflow is half the frame's width: an eighth of the width is 25 %
    await drag(0.125, 0.3);
    await expect(label).toHaveText('25 % von links, 50 % von oben');
    await expect(first.locator('.pv-nb-crop-frame img')).toHaveCSS('object-position', '25% 50%');
    expect(await markdown(page)).toContain('image{lauf-1, pos=25,50, "Der Start"}');
    // never beyond the edge
    await drag(-0.45, 0);
    await expect(label).toHaveText('100 % von links, 50 % von oben');
    // the arrow keys move the image like a drag; up and down don't apply here
    await frame.press('ArrowRight');
    await expect(label).toHaveText('95 % von links, 50 % von oben');
    await frame.press('ArrowUp');
    await expect(label).toHaveText('95 % von links, 50 % von oben');
    await first.locator('.bu_nb_crop_reset').click();
    await expect(label).toHaveText('Mitte');
    expect(await markdown(page)).toContain('image{lauf-1, "Der Start"}');
    await drag(0.125, 0);
    await expect(label).toHaveText('25 % von links, 50 % von oben');

    // a third image at most
    await block(page, 2).locator('.bu_nb_row_add').click();
    await expect(block(page, 2).locator('.pv-nb-row-item')).toHaveCount(3);
    await expect(block(page, 2).locator('.bu_nb_row_add')).toHaveCount(0);
    await block(page, 2).locator('.ti_nb_row_slug').nth(2).fill('lauf-3');
    expect(await markdown(page)).toBe('Zwei Bilder vom Sportfest.\n\nimages{1:1, "Fotos: Erika Beispiel"}{image{lauf-1, pos=25,50, "Der Start"} image{lauf-2} image{lauf-3}}');

    // the preview: side by side from tablet width, one below the other on phones
    await pane(page, 'preview');
    const preview = page.locator('#ta_preview');
    await expect(preview.locator('.image-row.ratio-1-1.images-3 > .image')).toHaveCount(3);
    await expect(preview.locator('.image-row > .image').first()).toHaveAttribute('data-pos', '25 50');
    await expect(preview.locator('.image-row > .image img').first()).toHaveCSS('object-position', '25% 50%');
    await expect(preview.locator('.image-row > .image-row-caption')).toHaveText('Fotos: Erika Beispiel');
    await page.locator('.pv-nb-width', { hasText: 'Desktop' }).click();
    const columns = () => preview.locator('.image-row').evaluate((el) => getComputedStyle(el).gridTemplateColumns.split(' ').length);
    await expect.poll(columns).toBe(3);
    await page.locator('.pv-nb-width', { hasText: 'Handy' }).click();
    await expect.poll(columns).toBe(1);

    // it opens again as a row
    await pane(page, 'edit');
    await page.locator('.pv-nb-mode', { hasText: 'Text bearbeiten' }).click();
    await page.locator('.pv-nb-mode', { hasText: 'Bausteine' }).click();
    await expect(block(page, 1)).toHaveAttribute('data-type', 'row');
    await expect(block(page, 1).locator('.pv-nb-row-item').nth(0).locator('.pv-nb-crop-label')).toHaveText('25 % von links, 50 % von oben');
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});
