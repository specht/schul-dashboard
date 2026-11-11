import { test, expect, login, dashboardDialog, ACCOUNTS } from './fixtures';

// Resetting the own Nextcloud password to the initial one on /passwoerter,
// without asking anybody. The test stack's Nextcloud is a stand-in that records password
// changes (src/ruby/test/fake_nextcloud.ru).

const NEXTCLOUD = process.env.NEXTCLOUD_FAKE_URL || 'http://localhost:8127';
const PAGE = '/passwoerter';

type Change = { login: string; key: string; value: string; admin: string | null };

async function changesFor(login: string): Promise<Change[]> {
  const all: Change[] = await (await fetch(`${NEXTCLOUD}/_requests`)).json();
  return all.filter((change) => change.login === login);
}

for (const [who, email] of [
  ['Schüler:in', ACCOUNTS.schueler_oberstufe],
  ['Lehrkraft', ACCOUNTS.teacher],
] as const) {
  test(`${who} setzt das eigene Nextcloud-Passwort zurück`, async ({ page }) => {
    await login(page, email);
    await page.goto(PAGE);
    const ncLogin = await page.locator('#ti_nc_login').inputValue();
    const initialPassword = await page.locator('#ti_initial_nc_password').inputValue();
    expect(ncLogin.length).toBeGreaterThan(0);
    expect(initialPassword.length).toBeGreaterThan(0);
    const before = (await changesFor(ncLogin)).length;

    await page.locator('.bu-reset-nc-password').click();
    await dashboardDialog(page).getByRole('button', { name: 'Zurücksetzen' }).click();
    await expect(page.locator('.result-success')).toBeVisible();

    const changes = await changesFor(ncLogin);
    expect(changes).toHaveLength(before + 1);
    expect(changes[changes.length - 1]).toMatchObject({ key: 'password', value: initialPassword });
  });
}

test('Nextcloud lehnt ab: die Seite meldet einen Fehler', async ({ page }) => {
  await login(page, ACCOUNTS.schueler_oberstufe);
  await page.goto(PAGE);
  const ncLogin = await page.locator('#ti_nc_login').inputValue();
  await fetch(`${NEXTCLOUD}/_fail?login=${encodeURIComponent(ncLogin)}`, { method: 'POST' });
  await page.locator('.bu-reset-nc-password').click();
  await dashboardDialog(page).getByRole('button', { name: 'Zurücksetzen' }).click();
  await expect(page.locator('.result-error')).toBeVisible();
  await expect(page.locator('.result-success')).toHaveCount(0);
});
