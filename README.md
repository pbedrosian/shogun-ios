# Shogun

Native iPhone movie catalog with a Supabase backend, managed in one repository.
The iOS app currently uses offline sample data; live integration follows the backend schema work.

## Repository layout

```text
apps/ios/             Xcode project, Swift sources, app tests and model checks
backend/supabase/     Local configuration, migrations, fixtures and database tests
scripts/backend/      Shared backend and startup commands
scripts/ci/           Shared iOS build/test/coverage runner
ci/                   Coverage policy
.github/workflows/    GitHub Actions
docs/                 Setup and CI documentation
```

## Dependencies

Local development is intended for macOS with:

| Dependency | Purpose |
| --- | --- |
| Full Xcode 16.4+ with an installed iPhone simulator runtime | Build, run, and test the iOS app; Command Line Tools alone are insufficient for CI |
| Node.js 22+ and npm | Run shared development tools |
| Docker Desktop with its Docker CLI available in Terminal | Run local PostgreSQL, Auth, REST API, Studio, and email services |
| Python 3 | Run the shared iOS CI checks |
| Git | Work with this repository |

The app targets iOS 17+. Local validation used Xcode 27 / iOS 27 and Docker engine
29.9.2. `npm ci` installs **Supabase CLI 2.122.0** and **Swagger UI 5.34.0** from
`package-lock.json`; a global Supabase CLI install is unnecessary. Node packages
are development tooling, not dependencies shipped in the iPhone app.

No Supabase cloud account, TMDB key, or `.env` file is required for the current
local setup. `.env.example` documents future client configuration; the current
app and startup scripts do not load it. Keep local credentials out of Git.

## First-time setup

From your checkout's repository root (for example, `~/dev/shogun-ios`):

```sh
cd ~/dev/shogun-ios
npm ci
npm run dev
```

The launcher opens Docker Desktop if needed, waits for its engine, starts
Supabase and Swagger UI, then opens Swagger UI in your browser and the project
in Xcode. First startup downloads service images and may take several minutes.
In Xcode, select the **Shogun** scheme and an installed iPhone simulator, then
press **⌘R**. Simulator builds do not require your own signing team; physical
phone setup is described in the [iOS README](apps/ios/README.md).

Keep this Terminal open if the launcher started Swagger UI. In a **second
Terminal**, create the local test accounts and check the backend:

```sh
cd ~/dev/shogun-ios
npm run backend:fixtures
npm run backend:smoke
```

Fixtures provide separate owner/editor/viewer/outsider Auth identities. Their
emails and local-only password are documented in [backend setup](docs/BACKEND.md).
Actual library membership permissions arrive with SHO-18. The launcher does not
create fixtures or reset existing data.

## Daily startup and shutdown

From the repository root:

```sh
npm run dev
```

Already-running services are reused. After dependency/lockfile changes, rerun
`npm ci` before starting. To start services without opening browser or Xcode:

```sh
npm run dev -- --no-open
```

Press **Ctrl-C** in the launcher's Terminal to stop the Swagger UI server it
started. If it reused a docs server from another Terminal, stop that process there.
Supabase stays running until you run:

```sh
npm run backend:stop
```

Stopping Supabase preserves local data. Docker Desktop and Xcode remain open;
quit them separately when finished.

## Local services

| Service | Address |
| --- | --- |
| Swagger UI / interactive database REST docs | http://127.0.0.1:54328 |
| Supabase Studio / database and Auth administration | http://127.0.0.1:54323 |
| Captured authentication emails (Mailpit) | http://127.0.0.1:54324 |
| REST/Auth gateway | http://127.0.0.1:54321 |
| PostgreSQL | 127.0.0.1:54322 |

**The iOS app is not connected to Supabase yet.** It still displays sample data;
app edits reset on relaunch. Movie/library tables and their Swagger endpoints
will be added in SHO-18. Swagger currently documents the database REST API,
not Auth or Edge Functions. Its Try it out controls execute real local requests.

## Individual commands

Run these from the repository root:

| Command | Purpose |
| --- | --- |
| `npm run backend:doctor` | Check the pinned CLI and Docker engine |
| `npm run backend:start` | Start Supabase only |
| `npm run backend:docs` | Start Swagger UI only; Supabase must already be running |
| `npm run backend:status` | Show local endpoints and keys; do not share its full output |
| `npm run backend:fixtures` | Create/refresh local test accounts without duplicating their IDs |
| `npm run backend:smoke` | Verify API health and fixture sign-ins |
| `npm run backend:stop` | Stop Supabase and preserve local data |
| `npm run backend:reset` | **Delete local database data** and rebuild from migrations |

After an intentional database reset, rerun `backend:fixtures` and
`backend:smoke`. Reset is for disposable local development data, not normal startup.

## Validation

Tooling checks without a running backend or simulator:

```sh
npm run backend:test
python3 -m unittest discover -s scripts/ci -p 'test_*.py'
```

With the backend running and fixtures created:

```sh
npm run backend:smoke
```

For the complete iOS build, static analysis, unit/UI tests, and coverage checks:

```sh
python3 scripts/ci/run.py
```

The CI runner needs full Xcode, Python 3, and an installed iOS simulator runtime.
It writes reports under `build/ci`; use a fresh output directory on subsequent
runs, such as `python3 scripts/ci/run.py --output /tmp/shogun-ci-next`.
GitHub Actions and Jenkins use the same root-level runner.

## Troubleshooting

- **Docker unavailable:** open Docker Desktop, wait until its engine is running,
  then run `npm run backend:doctor`. The launcher waits up to two minutes for
  Docker; investigate Desktop errors if that times out.
- **Missing npm packages:** run `npm ci` from the repository root.
- **Port 54328 occupied:** reuse an existing Shogun docs server or stop its
  Terminal process before starting `backend:docs`. For Supabase port conflicts,
  stop the conflicting local stack; the fixture scripts expect the configured ports.
- **Smoke check cannot sign in:** run `npm run backend:fixtures`, especially after
  a database reset.
- **Xcode cannot find a simulator/runtime:** install an iOS runtime in Xcode
  settings and select its iPhone simulator. If command-line builds select the wrong
  Xcode, check `xcode-select -p` and Xcode's Command Line Tools setting.
- **Swagger has no movie/library endpoints:** expected until SHO-18 adds tables
  and grants; an empty schema does not mean the backend failed to start.

More details: [iOS app and tests](apps/ios/README.md),
[backend configuration, fixtures, and API docs](docs/BACKEND.md), and
[CI, coverage, and Sonar setup](docs/CI.md).

## Release boundaries

The iOS project and backend can be reviewed and released independently. iOS app
versions/build numbers and TestFlight/App Store delivery belong to `apps/ios`.
Backend changes are versioned SQL migrations under `backend/supabase/migrations`;
hosted deployment automation is planned in SHO-27. This layout does not add a
production deployment or change the existing dev/main Git workflow. Backend APIs
must remain compatible with app versions still installed on users' phones.
