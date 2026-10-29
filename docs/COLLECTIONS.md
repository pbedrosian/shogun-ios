# Collection synchronization (SHO-20)

Normal signed-in launches read real account-scoped Supabase data. The previous
Debug fixture remains available only to explicit UI-test launches. No fixture data
is substituted when the server is unavailable.

## Run and test locally

From the repository root, with Docker running:

```sh
npm ci
npm run backend:start
npx supabase --workdir backend migration up --local
npm run dev
```

The migration is additive; do not reset the database to update an existing local
installation. `npm run dev` reuses running services. A fresh backend start applies
all migrations automatically. Keep the existing LAN configuration for a physical
phone, or use `npm run ios:configure` for a simulator; see [AUTH.md](AUTH.md).

Run the Shogun scheme in Xcode and sign in. The [README testing account](../README.md#local-testing-login)
has seeded movies and copies. A new account starts with a real empty personal
library. It does not receive demo movies automatically. The + sheet searches TMDB and supports manual metadata entry, including on a new
account with no saved movies. See [MOVIE_ADD.md](MOVIE_ADD.md) for the SHO-3 flow.

- Library shows server copies grouped by stable movie UUID. Select a library,
  search it, or use the [TMDB Search tab](MOVIE_API.md) to discover titles. Repeated physical copies stay
  separate rows and do not duplicate the movie card.
- Use + to search/select a movie or enter it manually, choose a library and quantities
  per format, then Save. Only owner and editor libraries are writable; the database
  rechecks permission on every save.
- In movie details, edit Watched/rating, then press **Save diary**. Unsaved edits
  remain in that screen until you save or leave it. Ratings belong to your account
  and movie, so the same diary appears through every library containing that movie.
- In Profile, choose **Use … by default** or create a shared library. Invitations
  and membership administration are separate work. A missing personal library can
  be recovered from the no-library screen.
- Pull to refresh Library/Search or press **Refresh collection** to fetch changes
  from another device. This phase does not subscribe to realtime events.
- Relaunch to verify the saved diary/default/copies persist. Selection while using
  the app is temporary; a fresh session starts in the saved writable default,
  otherwise the personal library, otherwise the first accessible library.

## Boundaries

| Layer | Responsibility |
| --- | --- |
| App | Construct dependencies; bind a collection service/store to the signed-in account. |
| CollectionServicing / SupabaseCollectionService | RPC requests and wire-to-domain mapping; never expose SDK or JSON in views. |
| SupabaseAuthService transport | Obtain/refresh the SDK session, require the bound account ID, attach public key/JWT and map HTTP failures. Shared request construction serves Auth and collections. |
| CollectionStore | Coordinate loads, save validation, errors, confirmed snapshots, defaults and cancellation/invalidation. |
| CatalogStore | Synchronous filtering, membership presentation, copies, diary queries and grid density. Accepts explicit remote snapshots; default constructor is fixture-only. |
| Feature views | Render loading/empty/error/content; hold transient form drafts; call store actions. |
| PostgreSQL | Enforce RLS, identity, constraints, atomic library creation and idempotent saves. |

The snapshot RPC uses caller RLS and a single statement snapshot, without REST row
pagination truncating the collection. Unknown release years stay nil and display
“Unknown year.” Backend UUIDs are preserved; procedural poster colors are derived
stably from IDs. At larger catalog sizes, add server query/search pagination rather
than downloading a global external catalog.

## Conflict, retries and offline behavior

Writes require a server response and a refreshed snapshot before the UI reports
success. There is no optimistic write queue or offline disk cache. While offline,
keep the last in-memory collection visible, show the error, and preserve the open
form's input. A cold launch offline shows an error/retry state after authentication
restoration; it does not show sample data. Closing a form or terminating the app
discards its unsaved draft. Refresh does not discard an open copy form.

Each add-movie form keeps one UUID for its current payload; metadata and all copies
are committed atomically. Provider metadata is fetched server-side, and provider
IDs map to stable movie UUIDs. Manual movies remain distinct, even if title/year
match an existing title. See [MOVIE_ADD.md](MOVIE_ADD.md).


Diary writes send the complete watched/rating pair: the last successfully committed
write wins, including an explicit null to clear rating. Defaults use the same
last-committed-write behavior. Refresh before editing when another device may have
changed the data. There is no version conflict dialog in this phase.

A revoked editor cannot save, even with a previously successful copy UUID. Refresh
removes inaccessible libraries/copies, clears invalid writable defaults locally,
and selects an accessible fallback. PostgreSQL also clears defaults after membership
revocation/downgrade. Private diary history remains private and survives losing a
shared collection. Signing out destroys the account's collection UI; late responses
cannot repopulate an invalidated store or use a different user's SDK session.

## Automated checks

```sh
npm run backend:test
npm run backend:test:db
npm run backend:fixtures
npm run backend:test:api
npm run backend:test:collection
npm run backend:test:movie-add
npm run backend:test:deletion
python3 scripts/ci/run.py --output build/sho20-ci
```

SQL tests roll back. Real-JWT collection checks create UUID-scoped temporary rows,
exercise concurrent retries, reload/second-session visibility, isolation, rating
bounds and revoked access, then remove only those rows and restore the fixture's
prior default. They refuse non-local backends. CI runs these checks as well.
Swift tests use service doubles for error/cancellation and transport tests for JWT
binding; simulator tests cover the actual forms and retry controls. No admin key
ships in the app, and tests do not use one for collection operations.

To exercise the real Swift service and Keychain restoration against local Supabase,
use an installed simulator's UUID in this explicit integration run (fixtures must
already exist). It makes no collection edits and keeps phone configuration intact:

```sh
xcodebuild -project apps/ios/Shogun.xcodeproj -scheme Shogun \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  SHOGUN_TEST_CONDITIONS=SHOGUN_LIVE_AUTH \
  SUPABASE_URL=http://127.0.0.1:54321 \
  -only-testing:ShogunTests/LiveAuthTests/testLocalCollectionReloadAndAccountBinding test
```

This local Keychain test uses ad-hoc simulator signing. The standard unsigned CI
suite uses explicit service/storage doubles and requires no running backend.
The Auth SDK opts into local initial-session events; routing still calls the SDK's
refreshing session API and validates the user with Auth before showing collections.
The initial event alone never authorizes the UI.
