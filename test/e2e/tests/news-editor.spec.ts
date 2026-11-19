import { test, expect, login, ACCOUNTS } from './fixtures';
import type { Page } from '@playwright/test';

// The news editor (manage_news.html, "Artikel schreiben") as text: a guide
// to the structure of an article, buttons that insert image{…},
// gallery{…} and file{…}{…} at the cursor, and quiet hints below the
// preview. Today's design, and »Text bearbeiten« in the new one (its
// blocks: design-preview-news-editor.spec.ts). Nothing is saved.

async function openEditor(page: Page, preview: 'on' | 'off') {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: preview } });
  await page.goto('/manage_news');
  await page.locator('.bu-compose:visible').first().click();
  await expect(page.locator('#editModal')).toBeVisible();
  if (preview === 'on') {
    await page.locator('.pv-nb-mode', { hasText: 'Text bearbeiten' }).click();
    await expect(page.locator('#ta_markdown')).toBeVisible();
  }
}

// phones in the new design: the preview (and its hints) is a pane of its own
async function showPreview(page: Page) {
  const pane = page.locator('.pv-nb-pane[data-pane="preview"]');
  if (await pane.isVisible()) await pane.click();
}

async function showEditor(page: Page) {
  const pane = page.locator('.pv-nb-pane[data-pane="edit"]');
  if (await pane.isVisible()) await pane.click();
}

async function selected(page: Page) {
  return page.locator('#ta_markdown').evaluate((ta: HTMLTextAreaElement) =>
    ta.value.substring(ta.selectionStart, ta.selectionEnd));
}

async function renderPreview(page: Page, markdown: string) {
  await showEditor(page);
  await page.locator('#ta_markdown').fill(markdown);
  const rendered = page.waitForResponse('**/api/get_news_preview');
  await page.locator('#bu_render_preview').click();
  expect((await rendered).status()).toBe(200);
  await showPreview(page);
}

for (const preview of ['off', 'on'] as const) {
  const design = preview === 'on' ? 'Neues Design' : 'Bisheriges Design';

  test(`${design}: Artikel-Editor mit Anleitung und Bausteinen`, async ({ page }) => {
    try {
      await openEditor(page, preview);
      // a new article starts with the guide open
      const guide = page.locator('#news_guide');
      await expect(guide).toHaveAttribute('open', '');
      await expect(guide).toContainText('So baust du einen Artikel auf');
      await expect(guide).toContainText('Einstieg');
      await expect(guide).toContainText('mindestens fünf Zeilen');
      await expect(guide.locator('.news-guide-example')).toContainText('gallery{');
      await guide.locator('summary').click();
      await expect(guide).not.toHaveAttribute('open', '');

      // icons of the design: Tabler in the new one
      const blocks = page.locator('.news-blocks .bu_news_block');
      await expect(blocks).toHaveText(['Bild groß', 'Bild links', 'Bild rechts', 'Bilderreihe', 'Galerie', 'Datei']);
      await expect(blocks.first().locator('i')).toHaveClass(preview === 'on' ? 'ti ti-photo' : 'fa fa-picture-o');

      // the cursor in the middle of a paragraph: the block goes after it,
      // on its own line with blank lines around, the image name selected
      const ta = page.locator('#ta_markdown');
      await ta.fill('Einstieg in zwei Sätzen.\nNoch ein Satz.\n\nZweiter Absatz.');
      await ta.evaluate((el: HTMLTextAreaElement) => el.setSelectionRange(5, 5));
      await blocks.filter({ hasText: 'Bild groß' }).click();
      await expect(ta).toHaveValue('Einstieg in zwei Sätzen.\nNoch ein Satz.\n\nimage{BILDNAME, "Bildunterschrift. Foto: Name"}\n\nZweiter Absatz.');
      expect(await selected(page)).toBe('BILDNAME');
      await page.keyboard.type('sportfest');
      await expect(ta).toHaveValue(/image\{sportfest, "Bildunterschrift\. Foto: Name"\}\n\nZweiter Absatz\.$/);

      // at the end: after the last paragraph
      await ta.evaluate((el: HTMLTextAreaElement) => el.setSelectionRange(el.value.length, el.value.length));
      await blocks.filter({ hasText: 'Galerie' }).click();
      await expect(ta).toHaveValue(/Zweiter Absatz\.\n\ngallery\{BILD1, BILD2, BILD3, "Bildunterschrift\. Fotos: Name"\}\n\n$/);
      expect(await selected(page)).toBe('BILD1, BILD2, BILD3');

      // at the start of a line: right there
      await ta.fill('Erster.\n\nZweiter.');
      await ta.evaluate((el: HTMLTextAreaElement) => el.setSelectionRange(9, 9));
      await blocks.filter({ hasText: 'Bild links' }).click();
      await expect(ta).toHaveValue('Erster.\n\nimage{BILDNAME, l5, "Bildunterschrift. Foto: Name"}\n\nZweiter.');
      await ta.fill('');
      await blocks.filter({ hasText: 'Datei' }).click();
      await expect(ta).toHaveValue('file{DATEINAME.pdf}{Beschriftung}\n\n');
      expect(await selected(page)).toBe('DATEINAME.pdf');

      // the blocks render as the website shows them (in the new design's
      // preview at desktop width)
      await renderPreview(page, 'Einstieg.\n\nimage{x, "Foto: A"}\n\ngallery{a, b, c, "Fotos: B"}\n\nimage{y, r5, "Foto: C"}\n\nimage{z, l5, "Foto: D"}');
      const preview_ = page.locator('#ta_preview');
      await expect(preview_.locator('.image.image-full')).toHaveCount(1);
      await expect(preview_.locator('.image-gallery.gallery-3 .gallery-item')).toHaveCount(3);
      await expect(preview_.locator('.image-gallery > .caption')).toHaveText('Fotos: B');
      // a float starts below the image or heading before it; two floats
      // right after each other stand side by side
      for (const sel of ['.image-float.pull-right', '.image-full', '.image-gallery'])
        await expect(preview_.locator(sel)).toHaveCSS('clear', 'both');
      await expect(preview_.locator('.image-float.pull-left')).toHaveCSS('clear', 'none');
      await expect(preview_.locator('.gallery-items')).toHaveCSS('display', 'grid');
      // phones: every image at full width (today's design: the screen;
      // the new design: the preview's width)
      if (preview === 'on') await page.locator('.pv-nb-width', { hasText: 'Desktop' }).click();
      const phone = preview === 'on' ? false : (page.viewportSize()!.width < 768);
      await expect(preview_.locator('.image-float.pull-right')).toHaveCSS('float', phone ? 'none' : 'right');
    } finally {
      await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    }
  });

  test(`${design}: Artikel-Editor gibt leise Hinweise zum Aufbau`, async ({ page }) => {
    try {
      await openEditor(page, preview);
      const hints = page.locator('#news_hints');
      await expect(hints).toBeHidden();

      // everything that goes wrong in practice
      await renderPreview(page, [
        'image{start, l5, "Foto: Max Muster"}',
        'Kurzer Text.',
        '',
        'image{ziel, r5, "Ziel"}',
        'Noch ein kurzer Text daneben.',
        '',
        'Ein langer Absatz.',
        '',
        'image{ende}',
      ].join('\n'));
      await expect(hints).toBeVisible();
      await expect(hints.locator('.news-hints-title')).toHaveText('6 Hinweise zum Aufbau');
      await expect(hints.locator('li')).toHaveText([
        /beginnt mit einem Bild/,
        /Neben dem Bild »start« steht nur etwa eine Zeile, daneben bleibt Platz frei/,
        /»ziel« hat keinen Fotonachweis/,
        /Neben dem Bild »ziel« steht nur etwa eine Zeile/,
        /»ende« hat keine Bildunterschrift/,
        /endet mit einem einzelnen Bild/,
      ]);
      await expect(hints.locator('li i').first()).toHaveClass(preview === 'on' ? 'ti ti-bulb' : 'fa fa-lightbulb-o');

      // a side image next to a short paragraph, and placeholders left over
      await renderPreview(page, 'Einstieg.\n\nimage{BILDNAME, r5, "Bildunterschrift. Foto: Name"}\nZwei Zeilen Text.\n\n## Weiter\n\nSchluss.');
      await expect(hints.locator('li')).toHaveText([
        /noch Platzhalter \(BILDNAME, Bildunterschrift, Foto: Name\)/,
        /Neben dem Bild »BILDNAME« steht nur etwa eine Zeile/,
      ]);

      // two floats right after each other: a pair
      const long = 'Lang erzählter Absatz mit vielen Einzelheiten. '.repeat(9);
      await renderPreview(page, `${long}${long}\n\nimage{a, l4, "Foto: A"}\n\nimage{b, r4, "Foto: B"}\n${long}`);
      await expect(hints.locator('li')).toHaveText([
        /»a« und »b« stehen als Paar nebeneinander/,
      ]);

      // a good article: no hints
      await renderPreview(page, [
        'Am Freitag war Sportfest.',
        '',
        `image{start, l5, "Der Start. Foto: Max Muster"}\n${long}`,
        '',
        'image{ziel, "Im Ziel. Foto: Erika Beispiel"}',
        '',
        'Am Ende hat die 7b gewonnen.',
        '',
        'gallery{a, b, c, "Fotos: Erika Beispiel"}',
      ].join('\n'));
      await expect(hints).toBeHidden();
    } finally {
      await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
    }
  });
}
