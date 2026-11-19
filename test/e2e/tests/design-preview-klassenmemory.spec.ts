import type { Locator, Page } from '@playwright/test';
import { test, expect, login, ACCOUNTS } from './fixtures';

// Neues Design (Vorschau): Klassenmemory (/klassenmemory_assign, teachers;
// preview/klassenmemory_assign.js and .css). One panel with the title and
// »Quiz« as the main action, the photos of a class as a grid; the quiz as a
// dialog, on phones a screen of its own, with back closing it a step at a
// time. The photos are drawn placeholders of the test stack
// (test/prepare_example_data.rb, assigned in test/e2e/seed.cypher): three in
// 5a with names, two of 5a's photo session without, twelve in class 11. The
// preview is for admins only on the test stack. Today's page stays as it was
// (last test).

const PASSWORD = 'beispielfotos';

async function noSidewaysScroll(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(1);
}

// inside the window, left to right
async function fitsWidth(page: Page, locator: Locator) {
  const box = (await locator.boundingBox())!;
  const width = page.viewportSize()!.width;
  expect(box.x).toBeGreaterThanOrEqual(-1);
  expect(box.x + box.width).toBeLessThanOrEqual(width + 1);
  return box;
}

async function unlock(page: Page) {
  await page.locator('#password').fill(PASSWORD);
  await page.locator('#submit_password').click();
  await expect(page.locator('#sus_here .sus-frame')).toHaveCount(5);
  // the photos are decrypted in the browser
  await expect(page.locator('#sus_here .sus-foto-sm').first()).toHaveAttribute('style', /data:image/);
}

test('Neues Design: Klassenmemory mit Fotos und Quiz, passt auf jede Breite', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const phone = testInfo.project.name === 'mobile';
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  try {
    await page.goto('/klassenmemory_assign');
    const body = page.locator('body');
    await expect(body).toHaveClass(/ui-preview/);
    await expect(body).toHaveClass(/pv-km-page/);

    // ---------- the page: title, the password with a label ----------
    await expect(page.locator('.pv-km-head h2')).toHaveText('Klassenmemory');
    await expect(page.getByLabel('Passwort für die Fotos')).toBeVisible();
    await expect(page.locator('#submit_password')).toHaveText('Fotos öffnen');
    // »Quiz« only once the photos are open
    await expect(page.locator('#bu_km_quiz')).toBeHidden();
    await noSidewaysScroll(page);

    // ---------- the photos of 5a: a grid, the class marked ----------
    await unlock(page);
    await expect(page.locator('#form')).toBeHidden();
    await expect(page.locator('#bu_km_quiz')).toBeVisible();
    await expect(page.locator('#klassen-div .ttc.active')).toHaveText('5a');
    await expect(page.locator('#sus_here .sus-label', { hasText: 'Max Mustermann' })).toBeVisible();
    await expect(page.locator('#sus_here .sus-label.nodata')).toHaveCount(2);
    for (const frame of await page.locator('#sus_here .sus-frame').all()) {
      const box = await fitsWidth(page, frame);
      expect(box.width).toBeGreaterThanOrEqual(120);
      // 2 : 3
      expect(Math.abs(box.height - box.width * 1.5)).toBeLessThan(3);
    }
    await noSidewaysScroll(page);
    expect(await page.locator('.pv-km').innerText()).not.toContain('·');

    // a name opens the field (in »du«), leaving it shows the name again
    const label = page.locator('#sus_here .sus-label.nodata').first();
    await label.click();
    const input = page.locator('#sus_here .sus-edit:visible');
    await expect(input).toHaveAttribute('placeholder', 'Name eingeben');
    await fitsWidth(page, input);
    await input.blur();
    await expect(input).toHaveCount(0);

    // ---------- the quiz: a dialog, on phones the whole screen ----------
    await page.locator('#bu_km_quiz').click();
    const start = page.locator('#div_quiz_root');
    await expect(start).toBeVisible();
    await expect(start).toHaveAttribute('role', 'dialog');
    await expect(start.locator('h1')).toHaveText('Klassenmemory-Quiz');
    await expect(body).toHaveClass(/pv-sheet-open/);
    await expect(page.locator('#hall-of-fame table')).toBeVisible();
    const startBox = await fitsWidth(page, start);
    if (phone) {
      expect(startBox.x).toBeLessThanOrEqual(1);
      expect(startBox.width).toBeGreaterThanOrEqual(page.viewportSize()!.width - 1);
    }
    expect(await start.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
    await expect(start.getByRole('button', { name: 'Schließen' })).toBeVisible();
    // the picture beside the Hall of Fame stays inside the dialog
    const picture = start.locator('img[src="/api/jauch"]');
    await expect(picture).toBeVisible();
    await fitsWidth(page, picture);

    // the setting in words, as a switch (switched twice: back as it was)
    const fame = start.getByRole('switch');
    const before = await fame.getAttribute('aria-checked');
    await fame.click();
    await expect(fame).not.toHaveAttribute('aria-checked', before!);
    await fame.click();
    await expect(fame).toHaveAttribute('aria-checked', before!);
    await expect(fame).toContainText('in der Hall of Fame');

    // one class
    const klasse = start.locator('.pv-km-mode[data-which="klasse"]');
    await expect(klasse).toHaveAttribute('aria-expanded', 'false');
    await klasse.click();
    await expect(klasse).toHaveAttribute('aria-expanded', 'true');
    await start.locator('.klassen-buttons-here .ttc', { hasText: /^5a$/ }).click();

    // ---------- playing: the photo and the answers fit ----------
    const play = page.locator('#div_quiz_play');
    await expect(play).toBeVisible();
    await expect(start).toBeHidden();
    await expect(play.locator('h2')).toHaveText('Wer ist das?');
    await expect(play.locator('.pv-km-play-what')).toHaveText('Klasse 5a');
    const photo = play.locator('#quiz-foto .sus-frame');
    await expect(photo).toBeVisible();
    const photoBox = await fitsWidth(page, photo);
    expect(photoBox.width).toBeGreaterThanOrEqual(140);
    const answers = play.locator('#name-buttons-here .btn');
    await expect(answers.first()).toBeVisible();
    // the photo and the first answers in the window, without scrolling
    const firstAnswer = (await answers.first().boundingBox())!;
    expect(firstAnswer.y + firstAnswer.height).toBeLessThanOrEqual(page.viewportSize()!.height);
    for (const b of await answers.all()) {
      const box = await fitsWidth(page, b);
      expect(box.height).toBeGreaterThanOrEqual(43);
    }
    expect(await play.evaluate((el) => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1);
    await noSidewaysScroll(page);

    // »Weiß ich nicht« in words (no emoji), then »Weiter«
    const dontKnow = play.getByRole('button', { name: 'Weiß ich nicht' });
    await expect(dontKnow.locator('.ti-help-circle')).toHaveCount(1);
    expect(await play.innerText()).not.toContain('🤔');
    await dontKnow.click();
    await expect(play.locator('.sus-quiz-label')).toHaveClass(/shown/);
    const weiter = play.getByRole('button', { name: 'Weiter' });
    await expect(weiter).toBeVisible();
    await weiter.click();
    await expect(dontKnow).toBeVisible();

    // ---------- back: first to the start, then out of the quiz ----------
    await page.goBack();
    await expect(play).toBeHidden();
    await expect(start).toBeVisible();
    await expect(page).toHaveURL(/\/klassenmemory_assign$/);

    // a class without photos (5b has no students in the example data): a
    // short sentence instead of an error, »Zurück« returns to the start
    await start.locator('.klassen-buttons-here .ttc', { hasText: /^5b$/ }).click();
    await expect(play.locator('.quiz-no-photos')).toHaveText('Für diese Auswahl gibt es noch keine Fotos mit Namen.');
    await expect(play.locator('.pv-km-play-what')).toHaveText('Klasse 5b');
    await play.getByRole('button', { name: 'Zurück' }).click();
    await expect(start).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(start).toBeHidden();
    await expect(page.locator('#quiz-curtain')).toBeHidden();
    await expect(body).not.toHaveClass(/pv-sheet-open/);
    await expect(page).toHaveURL(/\/klassenmemory_assign$/);
    await expect(page.locator('#sus_here .sus-frame')).toHaveCount(5);
  } finally {
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Neues Design: Klassenmemory dunkel lesbar', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'on' } });
  await page.request.post('/api/set_dark_css', { data: { mode: 'dark' } });
  try {
    await page.goto('/klassenmemory_assign');
    await expect(page.locator('body')).toHaveClass(/dark/);
    await unlock(page);
    // light type on a dark ground: the panel, a name on a photo, the quiz
    const luminance = (rgb: string) => {
      const [r, g, b] = (rgb.match(/[\d.]+/g) || []).map(Number);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };
    const colours = async (locator: Locator) => locator.evaluate((el) => {
      let ground = 'rgba(0, 0, 0, 0)';
      for (let e: Element | null = el; e; e = e.parentElement) {
        const bg = getComputedStyle(e).backgroundColor;
        if (bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') { ground = bg; break; }
      }
      return { ink: getComputedStyle(el).color, ground };
    });
    for (const locator of [page.locator('.pv-km-head h2'), page.locator('#sus_here .sus-label').first()]) {
      const { ink, ground } = await colours(locator);
      expect(luminance(ink)).toBeGreaterThan(luminance(ground) + 100);
    }
    await page.locator('#bu_km_quiz').click();
    const heading = page.locator('#div_quiz_root h1');
    await expect(heading).toBeVisible();
    const { ink, ground } = await colours(heading);
    expect(luminance(ink)).toBeGreaterThan(luminance(ground) + 100);
  } finally {
    await page.request.post('/api/set_dark_css', { data: { mode: 'light' } });
    await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  }
});

test('Klassenmemory ohne Vorschau: wie bisher', async ({ page }) => {
  await login(page, ACCOUNTS.admin);
  await page.request.post('/api/set_ui_preview', { data: { mode: 'off' } });
  const response = await page.goto('/klassenmemory_assign');
  expect(await response!.text()).not.toContain('preview/klassenmemory_assign');
  await expect(page.locator('body')).not.toHaveClass(/ui-preview/);
  await expect(page.locator('.pv-km-head')).toHaveCount(0);
  await expect(page.locator('#password')).toHaveAttribute('placeholder', 'Bitte gib das Passwort ein, um das Klassenmemory zu starten');
  await expect(page.locator('#submit_password')).toHaveText('Passwort absenden');
  await unlock(page);
  // »Quiz!« among the classes, the photos as framed tiles of their own size
  const quiz = page.locator('#klassen-div .ttc', { hasText: 'Quiz!' });
  await expect(quiz).toBeVisible();
  await expect(page.locator('#sus_here .sus-label.nodata').first()).toHaveText('(kein Name zugeordnet)');
  await expect(page.locator('#sus_here .sus-label.nodata').first()).toHaveCSS('color', 'rgb(204, 55, 41)');
  await page.locator('#sus_here .sus-label.nodata').first().click();
  await expect(page.locator('#sus_here .sus-edit:visible')).toHaveAttribute('placeholder', 'Bitte geben Sie einen Namen ein');
  await page.locator('#sus_here .sus-edit:visible').blur();
  await quiz.click();
  const start = page.locator('#div_quiz_root');
  await expect(start).toBeVisible();
  await expect(start.locator('h1')).toHaveText('Klassen-Memory');
  await expect(start.locator('.bu_play.btn-success.w-100')).toHaveCount(3);
  await expect(start.locator('#toggle_show_recognize_hall_of_fame')).toHaveClass(/btn-outline-/);
  await expect(start).not.toHaveAttribute('role', 'dialog');
  await start.locator('.bu_play[data-which="klasse"]').click();
  await start.locator('.klassen-buttons-here .ttc', { hasText: /^5a$/ }).click();
  const play = page.locator('#div_quiz_play');
  await expect(play).toBeVisible();
  await expect(play.locator('.bu-dont-know')).toHaveText('🤔');
  await expect(play.locator('.pv-km-play-head')).toHaveCount(0);
  // the back button at the top right, as before
  await play.locator('.right-top-button').click();
  await expect(start).toBeVisible();
  await start.locator('.right-top-button').click();
  await expect(start).toBeHidden();
});
