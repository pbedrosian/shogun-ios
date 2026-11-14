# Personal movie covers (SHO-36)

From an owned TMDB movie's detail screen, the top-right **… → Change cover** opens a native poster
grid. Select a poster and Save, or choose **Use default cover** to reset. Cancel
does not write anything. Manual movie artwork is unchanged. The picker provides
loading, empty and retry states and remains usable at accessibility text sizes.

The same menu offers **Update count** and **Remove from collection** for libraries
where the account can edit copies. Multiple libraries produce a library chooser.
Removal confirms the movie, library and copy count, then uses the existing
optimistic-concurrency copy edit with zero formats. It preserves shared metadata,
other libraries and the personal diary. Cancellation and stale-copy conflicts
preserve the collection. Read-only accounts can still choose their personal cover.

The preference belongs to the signed-in account and metadata movie UUID, not a
library or owned copy. It applies across that person's libraries and appears in
library cards, collection search, movie details and global catalog search/details
for known catalog movies. Refresh loads another device's changes. An existing
screen resolves its movie against the refreshed catalog instead of keeping stale
navigation artwork. Sign-out invalidates pending responses and clears the catalog.

## Choose before adding

After selecting a TMDB result in Add Movie, the **Cover** section previews the
artwork and offers **Choose cover**. **Use cover** returns the selection to the
draft; it makes no persistent write. Cancelling either sheet preserves existing
covers and copies. Selecting a different movie or entering one manually clears the
previous draft cover. A failed save keeps the chosen cover and retry identity.

The final Add Movie Save sends an optional `coverPath` on the authenticated import:
omission preserves the account's existing cover, a filename chooses a poster, and
explicit null restores the shared default. The server checks the filename against
the movie's TMDB posters and calls `import_catalog_movie_with_cover` for explicit
choices. That trusted wrapper calls the same private add transaction with an
internal cover intent. Copies and the personal cover commit or roll back together.

The retry payload includes an explicit choice, distinguishing default reset from
omission. An unchanged request UUID cannot add duplicate copies; reusing it with a
different cover is rejected. A completed retry returns before applying artwork,
so it cannot overwrite a cover changed after the original save. The legacy import
RPC and its existing retry payload remain supported unchanged. Manual imports
cannot use the trusted provider-cover intent. Apply migration
`20261114020000_add_movie_cover` before deploying the updated catalog function.

## Server contract

The authenticated `catalog` Edge Function adds two operations:

- `posters`: `{operation: "posters", movieID: <TMDB integer>}` returns
  `{posters: [{path, url, language, width, height}]}`. It fetches the movie's TMDB
  images from a fixed origin, removes unsafe/duplicate filenames and orders English
  and textless posters first. Other languages remain selectable.
- `set_cover`: `{operation: "set_cover", movieID: <TMDB integer>, path: <filename or null>}`
  returns `{saved: true}`. The handler validates live Auth and checks non-null
  filenames against that movie's current TMDB poster list. A URL or another movie's
  filename cannot be supplied. Reset requires no TMDB request.

Only the service role can call `set_movie_cover(actor, provider_id, poster_path)`.
The Edge Function derives `actor` from live Auth, never the request body. The RPC
requires an existing account and imported TMDB catalog movie. It upserts or deletes
the account's row in `movie_cover_preferences`; it never updates `movies`, copies
or personal diary state. Repeated selection/reset is idempotent. The table enables
RLS, grants authenticated users only their own SELECT, denies direct client writes,
and cascades preferences on account/movie deletion.

`collection_snapshot` adds nullable `cover_poster_path` to each movie, scoped to
`auth.uid()`. The original `poster_path` remains the shared default. Older clients
ignore the added field. New clients prefer the override and fall back to the
default when it is absent. The migration is additive and must precede deployment
of the updated catalog function and client. Until both backend pieces are deployed,
the new client shows a recoverable error when cover selection is attempted.

TMDB credentials stay server-only. The app receives fixed HTTPS w342 CDN URLs.
Choosing a cover does not grant shared-library write privileges. No uploads,
physical-edition scans, offline cache or background sync are introduced.

## Validation

```sh
npm run backend:test
npm run backend:test:db
npm run backend:fixtures
npm run backend:test:api
npm run backend:test:covers
```

The cover integration test uses real local Auth/database permissions and mocked
TMDB posters. It checks movie-specific validation, retries/reset, a fresh sign-in
reading the persisted selection, isolation between accounts, and unchanged diary,
copies and default poster. It rejects hosted endpoints through `localSettings`.
`CollectionServiceTests`, `CollectionTests` and `CoverPickerUITests` cover wire
mapping, reset, sign-out, selection, failed-save retry, cancellation, unavailable
and empty lists, and dark accessibility text. Live TMDB is separate from repeatable
CI tests.

Hosted alpha migration/function deployment and TestFlight distribution require
separate authorization. This feature's local implementation does not change the
installed 1.0.0 build.

Source: [TMDB movie images API](https://developer.themoviedb.org/reference/movie-images).
