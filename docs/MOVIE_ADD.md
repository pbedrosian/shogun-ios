# Add movie search and manual entry — SHO-3

The signed-in + sheet starts with an empty title search. Results use the SHO-8
debounced search, pagination and retry behavior. Selecting a result fetches full
details and fills title, year, director, synopsis, runtime, genres and poster URL.
Save stays disabled until details load successfully. Choose a different movie to
return to search, or Enter manually when the movie is unavailable. Manual entry
remains available when search fails or is unconfigured. Quick Add stays SHO-4.

Manual movies require a nonblank title. Year (1870–9999), director, synopsis,
positive runtime, comma-separated genres, and an HTTPS poster URL are optional.
Poster entry uses a URL, not a photo upload. Failed artwork uses the procedural
poster fallback. Saved metadata appears in collection movie details after reload.

Select an owner/editor destination and quantities for VHS, DVD, Blu-ray, 4K UHD
and Digital. Each quantity creates separate OwnedCopy rows; all formats start at zero. Total quantity must be 1–99. A new account can add its first movie
without existing metadata. Provider ownership badges match TMDB IDs, never title
or year. Manually entering the same title intentionally creates separate metadata.

## Persistence and authorization

`add_manual_movie` derives identity from `auth.uid()`. The catalog Edge Function's
`import` operation validates the live user, fetches canonical TMDB details, and
calls `import_catalog_movie` using server-only service credentials. Authenticated
clients cannot execute the provider RPC or supply trusted actor/metadata fields.
The transaction checks and locks a writable membership on every call, including
retries. Metadata creation and all requested copy rows commit together.

Provider IDs reuse the existing global TMDB metadata UUID. Manual metadata has
its own UUID and no TMDB ID. The existing policy makes provider metadata readable
to signed-in accounts; it does not share copies, libraries or private diary rows.

The draft retains its request UUID across retries of the same payload. A private
ledger serializes concurrent retries and returns the original movie UUID without
adding copies again. Changing selection, manual metadata, destination or quantities
creates a new request at the next Save. A second intentional add uses a new request.
Provider retry identity excludes refreshed canonical metadata, so provider changes
between retries do not duplicate or invalidate an already committed request.
Ledger rows follow account, movie and library deletion.

The UI reports success only after the write and collection reload both succeed.
A failed write/reload leaves the entire open draft intact. Refreshing the collection
also retains the draft. Closing the form, signing out or terminating the app discards
unsaved input. After an uncertain save followed by app termination, refresh and check
existing copies before intentionally adding again. There is no offline queue.

## Local verification

Apply the additive migration without resetting preserved data:

```sh
npx supabase --workdir backend migration up --local
npm run backend:test
npm run backend:test:db
npm run backend:test:api
npm run backend:test:movie-add
npm run backend:test:movie-add -- --live
python3 scripts/ci/run.py --output /tmp/shogun-sho3-ci
```

The optional live run uses the existing local server-only TMDB token and never
prints it. The default real-JWT movie-add checks need no provider credentials and
run in backend CI. Integration tests create UUID-scoped temporary resources and
remove them, preserving existing libraries and movies. SQL tests roll back.

## Verified implementation

Local validation on October 28: 122 unit/UI tests, zero failures/skips; 96.7% app-source
line coverage, with Models and CatalogStore at 100%. Build/static analysis, model
checks and Release build passed. Backend validation passed 19 unit tests, 138 SQL
checks, real-JWT permission/concurrent-retry checks, live TMDB import and existing
collection/deletion regressions. The native tests exercise provider search/details
retries, preserved save drafts, and manual metadata/two-copy saves
in dark appearance at maximum Dynamic Type.

Report: `/tmp/shogun-sho3-verified/summary.md`. Result bundle:
`/tmp/shogun-sho3-verified/Tests.xcresult`. Implementation remains uncommitted for review.

## Library copy editor

From a saved movie's Library detail page, choose Edit copies under a writable library.
Adjust per-format quantities and Save. Zero copies removes that movie's copies from
that library; movie metadata and private diary entries are preserved. Viewer libraries
have no edit action and are also rejected server-side. Conflicting changes from another
device are rejected; refresh, close and reopen the editor to review the latest quantities.
An unchanged retry after a successful but uncertain response creates no duplicate copies.

Review changes: all new-entry quantities start at zero, the Library uses pull-to-refresh
without a refresh button, and the saved-movie picker and its dedicated client code/tests
were removed. Sorting and format filters are tracked in SHO-28.
