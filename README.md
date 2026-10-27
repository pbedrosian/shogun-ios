# Shogun

Native iPhone movie catalog with a Supabase backend, managed in one repository.
The iOS app connects to Supabase authentication and durable account-scoped collections. The sample catalog is retained only for explicit Debug UI tests.

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

For Swift structure, shared styling, and future contribution rules, see
[code organization](docs/ARCHITECTURE.md).

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
are development tooling, not dependencies shipped in the iPhone app. Xcode resolves the official Supabase Swift Auth package (2.55.4) through Swift Package Manager; its first resolution requires internet access.

No Supabase cloud account, TMDB key, or `.env` file is required for the current
local setup. `.env.example` documents client reference values; the current
app does not load it. The launcher generates an ignored iOS xcconfig using the local public client key. Keep local credentials out of Git.

For real inbox delivery of verification and password-reset messages, follow the
[SMTP and email setup runbook](docs/EMAIL.md). Local verification is currently bypassed
and recovery mail is captured in Mailpit; the runbook does not enable external sending.

## First-time setup

From your checkout's repository root (for example, `~/dev/shogun-ios`):

```sh
cd ~/dev/shogun-ios
npm ci
npm run dev
```

The launcher opens Docker Desktop if needed, waits for its engine, starts
Supabase (including centralized logging) and Swagger UI, then opens Swagger UI,
Studio Logs in your browser, and the project
in Xcode. First startup downloads service images and may take several minutes.
In Xcode, select the **Shogun** scheme and an installed iPhone simulator, then
press **⌘R**. The app opens directly to **Sign in**, with links to create an account or reset a password. See [iOS authentication](docs/AUTH.md) for account creation, password recovery, phone networking, and release configuration. Simulator builds do not require your own signing team; physical
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
Membership permissions are enforced by PostgreSQL row-level security. The launcher does not
create fixtures or reset existing data.

## Local testing login

This is a disposable **local Supabase testing account**, not a hosted/production login.

| Email | Password |
| --- | --- |
| `testemail9678@gmail.com` | `Pb4229349` |

It is preconfirmed and seeded with the original demo data: My Library, Family
Collection, the long-name movie club, eight movies, fifteen copies (including
multiple formats and duplicate VHS copies), and Arrival watched/rated 5/5.
The profile's sample display name is Alex Morgan. The long movie-club name is shortened to fit the database's 120-character name limit. Shared-library memberships use
the same editor permissions as the original demo, with the local owner fixture
owning those shared libraries.

To recreate it after a local database reset, start Supabase, then run:

```sh
npm run backend:fixtures
SHOGUN_DEMO_EMAIL='testemail9678@gmail.com' SHOGUN_DEMO_PASSWORD='Pb4229349' npm run backend:demo
```

Rerunning restores these sample records without adding duplicates or deleting
unrelated data. Treat the documented password as public and use it only for this
local account. No confirmation email is sent. The signed-in app displays these
real backend collections. Copies, saved diary edits, and default-library preferences
persist across relaunch. See [collection usage and testing](docs/COLLECTIONS.md).

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
| Centralized backend logs | http://127.0.0.1:54323/project/default/logs/explorer |
| Captured authentication emails (Mailpit) | http://127.0.0.1:54324 |
| REST/Auth gateway | http://127.0.0.1:54321 |
| PostgreSQL | 127.0.0.1:54322 |

The signed-in iOS app uses Supabase authentication and real collection data.
Saved copies, diary edits and default-library preferences persist; explicit Debug
UI-test fixtures remain in memory. See [collection usage and tests](docs/COLLECTIONS.md).
Swagger documents the database REST API and RPCs, not Auth or Edge Functions.
Its Try it out controls execute real local requests.

To authenticate Swagger, use the local `ANON_KEY` from `npm run backend:status`
to sign in through Supabase Auth, then paste the returned **user access_token**
into Swagger and click **Load API**. The anon key itself does not go in Swagger's
token field. Follow the [local Swagger sign-in walkthrough](docs/BACKEND.md#authenticate-swagger-with-local-supabase)
for the exact command, fixture credentials, and switching between permission roles.

## Individual commands

### View backend logs

`npm run dev` and `npm run backend:start` automatically start Logflare and Vector
with Supabase. Open **Studio → Logs** to view API Gateway, Postgres, PostgREST,
and Auth logs in one place. Choose a collection and refresh it after making a
request; adjust the time range if needed. Disabled services have no logs, and
iPhone app/device console output remains in Xcode.

Logflare uses port 54327; Vector ingestion uses 54330 to avoid Swagger's port
54328. First startup may download two additional images. Logs are stored locally
in PostgreSQL; no cloud logging account is needed.
See [logging details](docs/BACKEND.md#centralized-service-logs).

### Backend commands

Run these from the repository root:

| Command | Purpose |
| --- | --- |
| `npm run backend:doctor` | Check the pinned CLI and Docker engine |
| `npm run backend:start` | Start Supabase only |
| `npm run backend:docs` | Start Swagger UI only; Supabase must already be running |
| `npm run backend:status` | Show local endpoints and keys; do not share its full output |
| `npm run ios:configure` | Regenerate simulator authentication configuration; add `-- --host <Mac LAN IP>` for a physical phone |
| `npm run backend:fixtures` | Create/refresh local test accounts without duplicating their IDs |
| `npm run backend:test:db` | Run SQL schema, integrity, and role permission tests |
| `npm run backend:test:deletion` | Verify authenticated account deletion, cascades, and other-user isolation with temporary local accounts |
| `npm run backend:test:api` | Test permissions through REST with fixture user JWTs |
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
npm run backend:test:db
npm run backend:test:api
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
- **Swagger has no movie/library endpoints:** anonymous clients have no table access.
  Load a signed-in user access token and click Load API to discover their endpoints.

More details: [iOS app and tests](apps/ios/README.md),
[backend configuration, fixtures, and API docs](docs/BACKEND.md), and
[CI, coverage, and Sonar setup](docs/CI.md), and
[database schema, permissions, and recovery](docs/DATABASE.md).

## Release boundaries

The iOS project and backend can be reviewed and released independently. iOS app
versions/build numbers and TestFlight/App Store delivery belong to `apps/ios`.
Backend changes are versioned SQL migrations under `backend/supabase/migrations`;
hosted deployment automation is planned in SHO-27. This layout does not add a
production deployment or change the existing dev/main Git workflow. Backend APIs
must remain compatible with app versions still installed on users' phones.
