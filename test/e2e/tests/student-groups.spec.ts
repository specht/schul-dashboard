import { test, expect, login, apiLogin, dashboardDialog } from './fixtures';
import { request as playwrightRequest, type APIRequestContext, type TestInfo } from '@playwright/test';

// Student groups (Projekttage, Lab 8, Lab 9, Pk5): students form a group by
// inviting each other; a student belongs to at most one group per module.
// Accepting an invitation used to add the student to the new group without
// taking them out of their own one – the student was then in two groups and
// every later save of the group failed until someone removed the second
// membership in the database.
//
// The test students come from test/prepare_example_data.rb; desktop and
// mobile each use their own three per module, the state carries over between
// runs, so every test first brings its students into a known state.

const MODULES = [
  { name: 'Projekttage', page: '/projekttage', lastName: 'Gruppentest', api: {
    update: 'update_projekttage', invite: 'send_invitation_for_projekttage',
    uninvite: 'delete_invitation_for_projekttage',
    accept: 'accept_projekttage_invitation', reject: 'reject_projekttage_invitation' } },
  { name: 'Lab 8', page: '/lab8', lastName: 'Labtest', api: {
    update: 'update_lab8_projekt', invite: 'send_invitation_for_lab8_projekt',
    uninvite: 'delete_invitation_for_lab8_projekt',
    accept: 'accept_lab8_projekt_invitation', reject: 'reject_lab8_projekt_invitation' } },
  { name: 'Lab 9', page: '/lab9', lastName: 'Labtest', api: {
    update: 'update_lab9_projekt', invite: 'send_invitation_for_lab9_projekt',
    uninvite: 'delete_invitation_for_lab9_projekt',
    accept: 'accept_lab9_projekt_invitation', reject: 'reject_lab9_projekt_invitation' } },
  { name: 'Pk5', page: '/pk5', lastName: 'Pruefungstest', api: {
    update: 'update_pk5', invite: 'send_invitation_for_pk5',
    uninvite: 'delete_invitation_for_pk5',
    accept: 'accept_pk5_invitation', reject: 'reject_pk5_invitation' } },
];
type Module = typeof MODULES[number];

const FIRST_NAMES = ['Anna', 'Ben', 'Cem', 'Dana', 'Emil', 'Fiona'];

type Student = { name: string; email: string; api: APIRequestContext };

// three students of the module's class: a joins groups, b and c invite
async function students(module: Module, testInfo: TestInfo, baseURL: string | undefined) {
  const offset = testInfo.project.name === 'mobile' ? 3 : 0;
  const result: Student[] = [];
  for (const first of FIRST_NAMES.slice(offset, offset + 3)) {
    const email = `${first.toLowerCase()}.${module.lastName.toLowerCase()}@mail.beispielschule.de`;
    const api = await playwrightRequest.newContext({ baseURL });
    await apiLogin(api, email);
    result.push({ name: `${first} ${module.lastName}`, email, api });
  }
  return result;
}

function post(module: Module, who: Student, route: keyof Module['api'], data: object) {
  return who.api.post(`/api/${module.api[route]}`, { data });
}

// members of the student's group (names); saving fails if the student is in
// more than one group
async function groupOf(module: Module, who: Student) {
  const response = await post(module, who, 'update', {});
  expect(response.status(), `${who.name}: saving the group`).toBe(200);
  return ((await response.json()).result.sus as string[]).slice().sort();
}

async function invite(module: Module, from: Student, to: Student) {
  // an invitation left over from an earlier, aborted run
  await post(module, from, 'uninvite', { sus_email: from.email, other_email: to.email });
  const response = await post(module, from, 'invite', { sus_email: from.email, name: to.name });
  expect(response.status(), `${from.name} invites ${to.name}`).toBe(200);
}

async function accept(module: Module, who: Student, from: Student) {
  return post(module, who, 'accept', { sus_email: who.email, other_email: from.email });
}

// brings `who` into the group of `owner` (owner's group consists of owner
// and who alone afterwards, as only these tests use these students)
async function join(module: Module, who: Student, owner: Student) {
  if ((await groupOf(module, who)).includes(owner.name)) return;
  await invite(module, owner, who);
  expect((await accept(module, who, owner)).status()).toBe(200);
}

for (const module of MODULES) {
  test.describe(module.name, () => {
    test('Annehmen einer Einladung wechselt die Gruppe', async ({ baseURL }, testInfo) => {
      const [a, b, c] = await students(module, testInfo, baseURL);
      // a is in c's group …
      await join(module, a, c);
      expect(await groupOf(module, a)).toEqual([a.name, c.name].sort());
      // … and accepts b's invitation: a is now only in b's group
      await invite(module, b, a);
      expect((await accept(module, a, b)).status()).toBe(200);
      expect(await groupOf(module, a)).toEqual([a.name, b.name].sort());
      expect(await groupOf(module, b)).toEqual([a.name, b.name].sort());
      expect(await groupOf(module, c)).toEqual([c.name]);
    });

    test('Doppelklick auf „Einladung annehmen“ ändert nichts', async ({ baseURL }, testInfo) => {
      const [a, b, c] = await students(module, testInfo, baseURL);
      await join(module, a, c);
      await invite(module, b, a);
      const responses = await Promise.all([accept(module, a, b), accept(module, a, b), accept(module, a, b)]);
      for (const response of responses) expect(response.status()).toBe(200);
      expect(await groupOf(module, a)).toEqual([a.name, b.name].sort());
    });

    test('Einladung ablehnen', async ({ baseURL }, testInfo) => {
      const [a, b, c] = await students(module, testInfo, baseURL);
      await join(module, a, b);
      await invite(module, c, a);
      const reject = await post(module, a, 'reject', { sus_email: a.email, other_email: c.email });
      expect(reject.status()).toBe(200);
      // the invitation is gone: accepting it fails, a stays where they were
      const before = await groupOf(module, a);
      expect((await accept(module, a, c)).status()).not.toBe(200);
      expect(await groupOf(module, a)).toEqual(before);
    });

    test('Niemand lädt sich selbst oder ein Gruppenmitglied ein', async ({ baseURL }, testInfo) => {
      const [a, b] = await students(module, testInfo, baseURL);
      await join(module, a, b);
      const self = await post(module, a, 'invite', { sus_email: a.email, name: a.name });
      expect(self.status()).not.toBe(200);
      const member = await post(module, b, 'invite', { sus_email: b.email, name: a.name });
      expect(member.status()).not.toBe(200);
      expect(await groupOf(module, a)).toEqual([a.name, b.name].sort());
    });

    test('Vor dem Wechsel in eine andere Gruppe wird nachgefragt', async ({ page, baseURL }, testInfo) => {
      const [a, b, c] = await students(module, testInfo, baseURL);
      await join(module, a, c);
      await invite(module, b, a);

      await login(page, a.email);
      await page.goto(module.page);
      await page.locator(`.bu-accept-invitation[data-email="${b.email}"]`).click();
      const dialog = dashboardDialog(page);
      await expect(dialog).toBeVisible();
      await expect(dialog).toContainText('wechselst du');
      const reloaded = page.waitForEvent('load');
      await dialog.getByRole('button', { name: /wechseln/ }).click();
      await reloaded;
      expect(await groupOf(module, a)).toEqual([a.name, b.name].sort());
    });
  });
}
