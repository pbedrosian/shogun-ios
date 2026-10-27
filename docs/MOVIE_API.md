# Movie discovery (SHO-8)

The signed-in Search tab now searches TMDB's full movie catalog through a Supabase
Edge Function. It starts empty, debounces nonblank queries, supports pagination,
and opens provider details for owned and unowned movies. Clearing the field clears
results/errors and cancels obsolete work. Loading, no matches, failures and retries
have separate UI states. Search state survives tab switching and returning from
movie details.

## Local setup

Your TMDB **API Read Access Token** is server-only. Put it in the ignored file
`backend/.env`; no quote or Bearer prefix is required:

```dotenv
TMDB_READ_ACCESS_TOKEN=your_read_access_token
```

`backend/.env.example` has an empty template. Never add this token to iOS xcconfig,
Info.plist, source control, a README, GitHub test logs, or a public client bundle.
`[edge_runtime.secrets]` in `backend/supabase/config.toml` reads the local variable
for the Edge Runtime. If the stack is already running when you add/change the token,
restart it to reload configuration (this preserves the database):

```sh
npm run backend:stop
npm run dev
```

Then rebuild and run the Shogun scheme in Xcode. Keep the existing Mac LAN address
for a physical phone; normal startup does not overwrite `Local.xcconfig`. Log in,
open Search and enter `Arrival`. Open a result to see its synopsis, director,
runtime, genres and poster. Missing metadata uses explicit unknown/fallback text;
poster loading or failure uses the existing procedural artwork.

The token has been verified through the local proxy. Standard CI never requires a
real TMDB credential: provider HTTP responses are mocked in unit tests, and its
local gateway checks cover JWT validation and blank-query suppression without
calling TMDB.

## Deployment and GitHub

Local configuration is not automatically deployed. For a hosted Supabase project,
set `TMDB_READ_ACCESS_TOKEN` in **Edge Functions → Secrets**, and deploy the
`catalog` function plus its shared session helper. Its gateway JWT check is disabled
in config because the handler validates the live user through Auth; this supports
current signing keys and rejects deleted/invalid users. It must not become an
unauthenticated proxy.

Current GitHub workflows only validate code and ephemeral local services. They do
not deploy Supabase, and do not need a TMDB repository secret. If deployment
execution is automated later, its Supabase deployment credentials belong in scoped
GitHub Actions secrets; the provider token still belongs in the hosted function's
server secrets. Hosted environment/promotion work remains separate.

## Responsibilities and identities

| Layer | Responsibility |
| --- | --- |
| App / AccountServices | Construct account-bound collection and discovery dependencies. |
| BackendHTTPClient | One implementation of URLs, public key/JWT headers, HTTP and status failures. |
| AuthenticatedBackendClient / Auth service | Retrieve/refresh the SDK session and require the bound account for each request. |
| MovieDiscoveryService | Typed request/response mapping and discovery-specific errors. No provider credentials. |
| CatalogSearchStore | Debounce, cancellation/generation checks, paging, deduplication and retry state. |
| CatalogDetailStore | Detail loading/retry without discarding the selected result on failure. |
| Feature/shared views | Navigation, accessibility and rendering; shared movie rows/summary presentation. |
| catalog Edge handler | Narrow authenticated search/detail contract; no caller-specified upstream URLs or user IDs. |
| TMDB client | Provider authentication, fixed HTTPS origin, timeouts, rate-limit/error mapping, metadata and artwork normalization. |

Collection RPCs and catalog requests share transport; their feature errors remain
separate. Edge Functions share live-session validation, with deletion still requiring
current-password reauthentication and server-side administrative deletion.

A TMDB movie ID is separate from a persisted Supabase movie UUID. `Movie.tmdbID`
retains the provider mapping from the backend. An ownership badge requires an exact
provider-ID match and an accessible copy. Manual movies with identical titles or
years are never silently merged. The provider's `tmdb:<id>` placeholder identity is
for rendering only and must never be submitted as a database UUID.

Browsing does not create metadata, owned copies or diary rows. The separate Add
Movie flow still chooses existing persisted metadata; connecting discovery results
to save/import and manual entry is **SHO-3**, and quick add is **SHO-4**. Unowned
catalog details intentionally do not display a writable personal diary. Owned
matches link to the existing persisted copy/diary screen.

The proxy currently uses `en-US`, excludes adult results, caps paging at TMDB's
500-page limit, and uses HTTPS w342 poster URLs on TMDB's image CDN. Provider
requests have bounded timeouts and no automatic retry loop. A 429 asks the user to
wait and retry. No offline discovery cache or background synchronization is added.
The Search tab requires the app's current sign-in flow; guest discovery is not added.

## Attribution

The app's Profile credits and catalog detail screens include the TMDB logo, link
and required notice. The bundled SVG is unchanged approved `blue_short` artwork.
Original asset URL:
https://www.themoviedb.org/assets/2/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg

The asset was retrieved from a cached mirror of that same named SVG because the
original asset host rejected the development environment's request. Preserve its
colors/aspect ratio and keep the app brand more prominent. Review provider terms
for the eventual hosted/commercial release.

## Verification

```sh
npm run backend:test
npm run backend:test:catalog
npm run backend:test:catalog -- --live
npm run backend:test:deletion
python3 scripts/ci/run.py --output build/sho8-ci
```

`--live` explicitly uses the configured server token against TMDB. It prints only
success/failure, never the token. Without that flag the gateway smoke suite makes
no external provider request. Fixtures (`npm run backend:fixtures`) must exist for
real-JWT checks.

Focused Swift tests cover blank queries, paging/deduplication, failed-page retry,
obsolete results even when a service ignores cancellation, sign-out invalidation,
missing artwork/year, provider identity, detail retry and account binding. The
explicit local Swift integration test also checks that browsing leaves collection
rows unchanged. Run it with ad-hoc simulator signing as described in
[COLLECTIONS.md](COLLECTIONS.md), selecting
`LiveAuthTests/testLocalTMDBSearchDetailsAndNoCollectionMutation` and local URL
`http://127.0.0.1:54321`.

Simulator checks cover empty initial Search, full-catalog results, pagination,
detail navigation, retries, saved ownership/diary links, dark mode and large text.
Legacy offline catalog UI is isolated to explicit Debug test launches.

## API references

- [TMDB application authentication](https://developer.themoviedb.org/docs/authentication-application)
- [Movie search](https://developer.themoviedb.org/reference/search-movie)
- [Movie details](https://developer.themoviedb.org/reference/movie-details)
- [TMDB attribution](https://developer.themoviedb.org/docs/faq)
- [Supabase function secrets](https://supabase.com/docs/guides/functions/secrets)
