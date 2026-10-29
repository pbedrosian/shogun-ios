# Database schema and permissions (SHO-18)

All commands below run from the repository root. Supabase/PostgreSQL enforce
permissions; the iOS app is still the offline demo until SHO-19/20.

## Apply and test locally

With Docker Desktop running and `npm ci` completed:

```sh
npm run backend:start
npx --no-install supabase --workdir backend migration up --local
npm run backend:test:db
npm run backend:fixtures
npm run backend:test:api
npm run backend:smoke
```

A fresh Supabase start applies migrations automatically. `migration up --local`
applies pending changes to an existing local database without resetting it.
SQL tests use authenticated/anonymous roles with explicit user identities, run in
a transaction, and roll back their data. REST tests sign in as the four fixture
users and clean up their own randomly identified resources. Do not run permission
tests against a hosted project: the npm commands explicitly target local services.

`npm run backend:fixtures` creates/reuses four Auth users plus a shared family
library with owner/editor/viewer memberships. The outsider is excluded. Existing
fixture passwords and these three membership roles are restored on each fixture
run. It is a development-only administration tool, not the invitation workflow.
The fixture script's loopback guard and disabled SQL seeds keep fixtures out of
hosted migration deployment.

## Data model

| Table | Responsibility |
| --- | --- |
| `profiles` | Private profile per Auth user; no email duplication |
| `libraries` | Named personal/shared library with one canonical owner |
| `library_memberships` | Owner/editor/viewer access to a library |
| `movies` | Stable metadata identity, distinct from copies and personal state |
| `owned_copies` | One owned copy and format per row, belonging to a library |
| `personal_movie_state` | Watched flag and nullable 1–5 rating per user/movie |
| `user_preferences` | User's default writable library |

UUIDs are internal identities. Movie provider identity is a separate unique,
positive `tmdb_id`; manual movies have no TMDB ID. Repeated copies of a movie,
including repeated copies in the same format, are supported without duplicating
metadata. Copy formats are VHS, DVD, Blu-ray, 4K UHD, and Digital. Movie title,
year, runtime, and rating constraints are enforced by PostgreSQL.

New Auth accounts atomically receive a profile, one personal library, its owner
membership, and a default-library preference. Existing Auth accounts are
backfilled when the initial migration is applied. No sample movies are seeded.
`POST /rest/v1/rpc/bootstrap_account` with `{}` is retry-safe for the signed-in
user. A unique partial index prevents duplicate personal libraries.
`POST /rest/v1/rpc/create_shared_library` with `{"library_name":"Family"}` creates
a shared library and owner membership atomically. Repeating shared-library
creation intentionally creates a new library; request-id handling is not added.
Neither RPC accepts a user ID. Account and ownership identities come from
`auth.uid()`; direct library insertion and owner transfer are unavailable to clients.

## Access rules

Anonymous clients have no application table or creation-RPC access. Every table
has RLS enabled, explicit grants, and operation-specific policies.

| Operation | Owner | Editor | Viewer | Unrelated user |
| --- | --- | --- | --- | --- |
| Read library, members, copies | Yes | Yes | Yes | No |
| Add/update/delete owned copies | Yes | Yes | No | No |
| Rename or delete shared library | Yes | No | No | No |
| Add/change/remove editor/viewer members | Yes | No | No | No |
| Change/remove canonical owner | No | No | No | No |
| Read/write own diary | Yes | Yes | Yes | Yes, for visible movies |
| Read/write another user's diary/profile/preferences | No | No | No | No |

Personal libraries cannot be shared or deleted by a client. Membership management
requires ownership and an existing user's profile ID. Invitation issuance,
acceptance, email lookup and UI belong to SHO-21; clients cannot enroll themselves
or manufacture a second owner. Owner transfer is deliberately unsupported.

TMDB metadata is readable by authenticated users and writable only by a trusted
server/service role (catalog ingestion is SHO-8). A manual movie is readable by
its creator, members of a library containing a copy, or a user who already has a
personal diary entry for it. This retains diary access independently of ownership.
Only its creator can edit manual metadata. No client can delete movie metadata,
change its provider identity, or transfer its creator ID. Corrections to shared
metadata are global to that identity; matching manual movies to providers is future work.

Library readers may write their own watched/rating state even when they have no
permission to edit the collection. A new diary entry requires visibility of the
movie. Losing membership hides the library and copies on subsequent requests;
existing private diary entries and their movie metadata remain available. This is
intentional: diary history is independent of collection access.

Defaults must be null or a currently writable library. Downgrading an editor to
viewer, removing membership, or deleting the referenced library clears an invalid
default. The client chooses its fallback; it is not silently assigned another
shared library. Library deletion cascades memberships/copies, preserving metadata
and personal diaries. Auth-account deletion removes its owned libraries and
private state; creator audit references on surviving movies/copies become null.

Column grants make IDs, owner/source fields and copy library/movie references
immutable to clients. To retry a copy creation, supply the same UUID rather than
creating a new one; a repeated ID conflicts instead of adding another physical
copy. Client-side retry/error behavior is SHO-20.

Permission helpers live in the unexposed `private` schema, use an empty pinned
search path, and derive the caller from Auth. Their execute grants are restricted.
They bypass RLS only for narrow visibility/bootstrap operations to avoid recursive
policies. Do not use the service-role key in the app or to test user permissions.

## Inspect through Studio and Swagger

Studio is at http://127.0.0.1:54323. Studio's SQL editor runs with administrative
privileges and is not proof of end-user access. Use the SQL/REST suites instead.
Start Swagger with `npm run backend:docs` and open http://127.0.0.1:54328. Paste a
signed-in user's access JWT into the token field and click **Load API** to discover
and exercise their accessible tables/RPCs. Anonymous discovery does not list
application tables because those privileges are intentionally absent.

## Migration recovery and rollback

Migrations are in `backend/supabase/migrations`. Never rewrite a migration after
it has been shared/applied to a hosted environment. Use a new corrective migration
for normal changes, preserving compatibility with installed app versions.

For an intentional disposable local rebuild, `npm run backend:reset` deletes the
local database data and reapplies migrations. Run fixtures and both permission
suites afterward. Stopping Supabase does not reset it.

A destructive rollback script is provided outside the automatic migration path:
`backend/rollback/20261025013000_initial_schema.sql`. It removes SHO-18 tables,
RPCs, and the Auth bootstrap trigger, retaining Auth accounts. It does not drop
the entire private schema or use CASCADE; unexpected external dependencies fail
for review. It destroys all application data: back up first and pause writers.
Local-only invocation, if rollback is deliberately required:

```sh
docker exec -i supabase_db_shogun-local psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 --single-transaction \
  < backend/rollback/20261025013000_initial_schema.sql
```

This manual rollback does not change Supabase migration history. To reapply this
unreleased initial schema locally afterward, use a deliberate local database reset
and recreate fixtures. Do not run the rollback on a hosted project; production
recovery must use a verified backup or a reviewed forward migration. Hosted backup,
promotion and deployment procedures remain SHO-26/27.

## Automated coverage

Local verification passed a fresh migration rebuild, 88 SQL assertions, the real-JWT
REST suite, fixture idempotency, and SQL lint with no schema errors. The rollback
script was verified inside a rolled-back transaction, preserving the live schema.
Hosted CI will run when this branch is pushed; it has not run on these uncommitted changes.

`backend:test:db` covers bootstrap retries, constraints, RLS/grants, protected
identities, user isolation, role changes, revocation, defaults, cascading cleanup,
private diaries and definer-function hardening. `backend:test:api` verifies actual
JWT sessions through PostgREST, including INSERT RETURNING, denied writes and
revocation. The separate **Backend schema and permissions** GitHub Actions job
starts a clean local stack and runs both suites. iOS coverage thresholds remain
scoped to the iPhone app.

## Collection RPCs (SHO-20)

The additive `20261027010000_collection_sync.sql` migration exposes an authenticated,
RLS-scoped `collection_snapshot`, retry-safe `save_collection_copy`, private
`save_movie_diary`, validated `set_default_library`, and atomic
`create_collection_library`. No new table grants or client admin credentials are
needed. The creation definer pins an empty search path and derives ownership from
`auth.uid()`; the other functions execute under caller RLS. See
[collection behavior and checks](COLLECTIONS.md). The database suite now has 112
assertions, including 24 collection-specific checks; real-JWT collection tests also
run in backend CI.
