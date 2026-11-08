# Rules for working on this repository

For humans and AI agents alike. These rules are decisions of the
maintainer – where they conflict with your own habits, they win. Add new
decisions here so that later sessions know them.

**Context:** The dashboard has been in production at a school for years
(teachers, students, parents). The repository is **public** (with forks),
and `doc/` is also published as public documentation. Several people work
on the repository.

Further reading: [doc/Architektur.md](doc/Architektur.md),
[doc/Development.md](doc/Development.md), [doc/Tests.md](doc/Tests.md),
[doc/Betrieb.md](doc/Betrieb.md), [TODO.md](TODO.md).

## 1. Data and confidentiality

- Local checkouts may have **real school data** linked in (`data/`,
  `internal/`, `logs/`, `env.rb`, `src/ruby/credentials.rb`). Don't open
  these files unless necessary, never quote their contents, never commit
  them.
- Nothing containing personal data goes into the repository: no dumps,
  exports, lists, logs, calendars, bank statements. `.gitignore` covers the
  usual cases – still never `git add -A`/`git add .`; stage files one by one
  and check them before committing.
- **Security findings** (concrete vulnerabilities) never go into the
  repository: not into `TODO.md`, not into `doc/`, not into commit
  messages. They live locally in `*.local.md` (gitignored). Use neutral
  commit messages for fixes; tests that describe a hole concretely are only
  pushed once the fix runs in production.
- Example and test data only from `src/example-data`.

## 2. Git and collaboration

- Never merge or push without the maintainer's explicit approval.
- Before every push: `git fetch`, merge new commits from `origin/master`,
  **then run the full test suite** (`./test.sh all`) on the merged state.
- No force push to `master`. Don't delete other people's branches; delete
  local branches only when they are fully contained in `master`.

## 3. Tests first, then changes

- Before changing an area, it must be covered by tests – for everything
  users interact with, also by **E2E tests**. Larger refactorings (e.g. of
  the template renderer) only with that safety net in place.
- Every bug fix gets a test that would have shown the bug.
- Tests run **only in containers** and **only against example data**, in
  the isolated test stack (`env.test.rb`, port 8125, Mailpit on 8126,
  production mode). Never against an instance with real data or against
  production.
- Commands: `./test.sh unit`, `./test.sh e2e`, `./test.sh all`; while
  writing tests `./test.sh up` and `./test.sh e2e-run`. Details in
  [doc/Tests.md](doc/Tests.md).
- E2E tests run on desktop **and** phone (Playwright projects `desktop`,
  `mobile`) and fail on HTTP 5xx, uncaught JavaScript errors and native
  browser dialogs.
- The page smoke test compares against
  `test/e2e/tests/known-page-errors.json`. Only rewrite that list after
  deliberate changes (`UPDATE_KNOWN_PAGE_ERRORS=1`) and review the diff;
  remove entries that got fixed.
- Create test data inside the test or in `test/e2e/seed.cypher` /
  `test/prepare_example_data.rb` – don't bend `src/example-data` for tests.

## 4. Local development

- The dev instance stays on **port 8025** (Neo4j browser 8021). Other local
  projects move, not the dashboard.
- If the dev instance can't reach its database (`getaddrinfo` for `neo4j`,
  502), check for port conflicts first (`docker ps`), only then the code.
- In the dev instance, `rerun` restarts Ruby on every file change under
  `src/ruby`; page templates take effect immediately.
- Never make a dev instance with real data reachable on the network: in
  development mode, fixed login codes work for every account.

## 5. Code rules

**Pages (`src/static/*.html`)**

- `#{…}` in pages and `_template.html` is evaluated as **Ruby**, also inside
  JavaScript and HTML comments. Use `${…}` in JS, never output `#{`.
- Escape values from the database or from users for HTML or JSON when they
  are inserted into a page.
- First line of a page: access check (`this_is_a_page_for_…`).
- **No native dialogs** (`alert`, `confirm`, `prompt`). Use
  `dashboardAlert(text, title)` and
  `dashboardConfirm(text, on_confirm, {title, confirm, cancel, danger})`
  from `_template.html`. They insert text as text (no HTML), confirmations
  focus "Abbrechen", destructive actions use `danger: true` and a clear
  button label ("Löschen", "Verwerfen"). A unit test enforces this.
- Pages that use `api_call` need an `.api_messages` element, otherwise users
  never see errors.
- In event handlers use `e.currentTarget`, not `e.target` (clicking an icon
  inside a button would yield the icon).
- Stable selectors for tests: `bu_…` (buttons), `ti_…` (inputs), `…Modal`;
  add `data-testid` where needed.
- The UI is German; students are addressed with "du".
- Pages must work with custom color schemes, in dark mode (`body.dark`) and
  on phones.

**Ruby (`src/ruby`)**

- API routes: check permissions first, then `parse_request_data` with
  required keys, types and lengths.
- Cypher always with parameters (`$name`), never insert values via `#{…}`.
- No shell strings containing data from requests or files:
  `system('cmd', arg1, arg2)` instead of `system("cmd #{arg}")`.
- Uploaded files: check the extension against a whitelist, never take the
  client's extension unchecked.
- New `include/*.rb` files must be required explicitly in `main.rb`.

**Infrastructure**

- `config.rb` generates `docker-compose.yaml` and the nginx configuration.
  Make new settings there optional: without them, the generated files and
  the `docker compose` call must stay **byte-identical** to before (check
  for development and production settings).
- The nginx configuration is copied into the image: after changes run
  `./config.rb build nginx && ./config.rb up -d nginx`.
- `src/static/errors/neustart.html` (the 502 page) is served by nginx
  without Ruby: fully self-contained, no `#{…}`; it polls `/api/ping`,
  which `src/ruby/config.ru` answers.

## 6. Documentation

- `doc/` and `TODO.md` are written in **German**; this file (agent rules)
  in English.
- `doc/*.md` is published publicly – general information only, no internal
  details of the school, no vulnerabilities.
- Record findings from tests (bugs, UX problems) in `TODO.md`; security
  findings only locally (see 1).

## 7. Deployment

- On the server: `git pull`, then `./config.rb restart ruby` (run
  `./config.rb build` first after changes to Dockerfiles, Gemfile or the
  nginx configuration). Only `src/static` changed: no restart needed.
- After deploying, check by hand what the test stack doesn't cover (e.g.
  SMS as second factor).
