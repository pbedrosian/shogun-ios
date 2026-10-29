# Development handoff — October 28, 2026

## Current work

- SHO-8 is merged into `dev`: [MR #15](https://github.com/pbedrosian/shogun-ios/pull/15), merge commit `0095625`. iOS, backend and SonarCloud passed on the final SHO-8 head; integrated local validation passed 116 tests with 97.7% coverage.
- SHO-3 implementation is on `peterbedrosian/sho-3`, based on that merged `dev`. All SHO-3 changes are **uncommitted** for user review. No SHO-3 PR or hosted run exists yet.
- The Notion ticket is In Development. See [MOVIE_ADD.md](MOVIE_ADD.md) for behavior, authorization and retry semantics.

## SHO-3 implementation

- The + sheet supports title search, selection/details autofill, manual entry, writable library selection, and per-format quantities (1–99 copies total).
- Manual metadata includes optional year, director, synopsis, runtime, comma-separated genres and HTTPS poster URL. Saved metadata and artwork/fallback display in collection details/cards.
- Owned-copy editing is available from Library movie details for writable libraries. It changes formats/quantities only, preserves movie metadata/diary state, and rejects stale drafts; zero removes copies from that library.
- Review update: removed the saved-movie picker/sheet and dedicated client service/store APIs/tests. New entries use search/manual entry; every format starts at zero. The Library refresh button is removed; pull-to-refresh remains.
- TMDB import runs through the authenticated catalog Edge Function. It fetches canonical details server-side and calls a service-role-only RPC; clients cannot supply trusted metadata or actor identity.
- Manual creation derives identity from `auth.uid()`. Metadata and all requested copies commit atomically. The private retry ledger serializes concurrent retries, compares payloads, and rechecks writable membership even after a previously successful save. Manual titles never merge by title/year; provider IDs reuse stable UUIDs.
- Save errors/reload failures preserve open drafts and retry identity. Search and detail retries, pagination, cancellation and account binding retain the SHO-8 boundaries. Search/details browsing still makes no collection edits.
- Keyboard completion/scroll dismissal supports manual entry. Explicit Debug UI-test appearance is applied deterministically so dark-mode tests actually render dark on iOS 27.

## Local environment and validation

- Applied the additive `20261029010000_movie_add.sql` migration to the existing local stack. The database was not reset; user configuration and data were preserved.
- Backend unit tests: 19 passed. SQL checks: 138 passed. Real-JWT permission, movie-add concurrency/retry, live TMDB import, collection and account-deletion regression checks passed.
- Final Release build, Debug build/static analysis and model checks passed.
- Final clean native validation passed **122 tests, zero failures/skips**, with **96.7% app-source line coverage**; Models and CatalogStore remain 100%. Build/static analysis and coverage policy passed. Final report: `/tmp/shogun-sho3-verified/summary.md`; result bundle: `/tmp/shogun-sho3-verified/Tests.xcresult`. Final light/provider and dark/maximum-Dynamic-Type screenshots are in `/tmp/shogun-sho3-verified/screenshots` and were visually inspected. Earlier failed development runs are superseded by this complete passing run.
- Supabase/Docker were already running and remain running. Only task-created simulators were used for verification; all of them were deleted after validation.

## Review follow-up validation

- After the review changes, build/static analysis, 103 unit tests and three focused UI regressions passed (106 tests total). These cover zero-entry quantities, Library refresh-button removal, search/detail retries, save retries, and editing copy formats/quantities in dark/maximum Dynamic Type. Test log: `/tmp/shogun-sho3-copy-edit.log`. All selected test suites passed; Xcode then stalled exporting its result bundle, so the completed run was terminated during teardown. The xcresult bundle is incomplete. Release build passed.
- Backend: 150 SQL checks, real-JWT copy editing/permission/conflict/retry checks and 19 tooling unit tests passed. Additive copy-edit migration applied without resetting data.
- Sorting and format filters were recorded as SHO-28 in Backlog.

## Next steps

1. Rebuild the Shogun scheme in Xcode and review + search, provider save, manual save/quantities and failure/retry behavior against the running local backend.
2. Commit/push/create a PR only when the user authorizes those actions. Do not merge into `dev` or `main` automatically.
3. Quick Add remains SHO-4. Hosted deployment, production email and social login remain separate work.

---

# Development handoff — October 26, 2026

## Where we stopped tonight

- SHO-20 is merged into `dev`: [MR #14](https://github.com/pbedrosian/shogun-ios/pull/14), merge commit `4295428`. Its iOS/backend CI and SonarCloud passed. Integrated local build/analyzer, model checks, 92 unit tests and three collection UI regressions also passed.
- SHO-8 is implemented and open for review into `dev`: [MR #15](https://github.com/pbedrosian/shogun-ios/pull/15).
- Current branch: `peterbedrosian/sho-8`. Feature commit: `aae113f`. The handoff is committed separately afterward. SHO-8 has **not** been merged.
- Hosted CI on the latest MR head still needs checking tomorrow; do not assume local test results mean hosted CI passed.

## What SHO-8 includes

Live TMDB Search/details/posters/pagination with empty initial search, debounce,
obsolete-response suppression, retry states, exact provider-ID ownership matching,
and attribution. Provider IDs are distinct from persisted movie UUIDs; manual
movies are never merged by title/year. Browsing does not create collection rows.

Networking is shared through BackendHTTPClient/AuthenticatedBackendClient.
Collection/discovery services own separate DTO/error mapping; search/detail stores
own async state; common movie rows/summary presentation is reused. The Edge proxy
keeps the TMDB token server-side and shares live-session validation with deletion,
which still requires password verification.

The provider token is configured in ignored `backend/.env` and was verified through
the actual local Edge Function. Do not print or commit it. The iOS public-key/LAN
configuration remains in ignored `apps/ios/Configuration/Local.xcconfig`.
A hosted Supabase project/deployment is not configured yet; hosted credentials
belong in Supabase Edge Function Secrets, not current GitHub test workflows.

## Verification before stopping

- 116 iOS unit/UI tests, zero failures/skips; 97.7% app-source line coverage.
- Models and CatalogStore retain 100% line coverage.
- Build/analyzer, model checks, final Release build, formatting/whitespace checks passed.
- Two real Swift/Keychain local integration tests passed, including live TMDB discovery without collection mutations and session restoration/account binding.
- 17 backend unit tests, 112 SQL checks, real-JWT catalog gateway checks, live TMDB search/details/artwork/pagination, and permissions/collection/deletion regressions passed.
- Native metadata fields use stable accessibility identifiers; the discovery UI tests pass in dark mode and large Dynamic Type.
- Latest iOS report: `build/sho19-ci2/summary.md` and `Tests.xcresult` (the cached directory was reused; this report is for SHO-8).

## Local services at shutdown

Supabase containers (API/Auth/database/Studio/Mailpit/logging/Edge Runtime), the
Swagger/dev launcher, and Docker Desktop were stopped. No simulators were booted.
Project ports 54321/54322/54323/54324/54327/54328/54330 were verified closed.
Database volumes and ignored local configuration were preserved. GitHub CI can
continue remotely while the Mac services are stopped.

## Tomorrow

1. Check MR #15's **latest head** for iOS CI, backend CI and SonarCloud results; inspect any review feedback. Fix failures before merging. Merge into `dev` only when the user authorizes it.
2. Start local development from the repository root:

```sh
cd ~/dev/shogun-ios
npm run dev
```

The launcher can start Docker Desktop and reuse preserved data/configuration.
Do not reset the database. Rebuild the Shogun scheme in Xcode. For phone connection
issues, verify the Mac's current LAN IP before regenerating iOS configuration.

3. Sign in with the documented local testing account and test Search: blank/whitespace default, Arrival results, posters/details, pagination, back navigation, clearing the field and retry states. See [MOVIE_API.md](MOVIE_API.md) and [COLLECTIONS.md](COLLECTIONS.md).
4. After SHO-8 is reviewed/merged, the recommended next feature is **SHO-3: Add movie search and manual-entry fallback to plus flow**. Connect provider results to server-side metadata import/copy saving while retaining stable UUID/TMDB identity, writable destination checks, retry-safe saves and user drafts. Quick Add remains SHO-4.
5. Keep hosted deployment, production SMTP/email verification/reset and social login separate from this next feature. Current local email confirmation remains disabled; recovery mail uses Mailpit. See [EMAIL.md](EMAIL.md).

The current + sheet still selects existing persisted metadata. Searching TMDB does
not yet add that title to a library; SHO-3 is the missing bridge. Manual seeded demo
movies without a TMDB mapping intentionally do not acquire ownership badges solely
because their titles match provider results.

---

# Development handoff — October 21, 2026

## Where we left off

- User confirmed MR #9 was merged into `dev`.
- MR: https://github.com/pbedrosian/shogun-ios/pull/9
- Work branch: `peterbedrosian/sho-13.1`.
- Latest fix commit: `393c362` (stable accessibility identifier for the Already owned header in the add-movie UI test).
- SHO-13.1 adds five UI tests and an 85% overall app-source coverage floor, retaining 100% requirements for Models and CatalogStore. App views remain included in coverage.
- Last full local validation: 72 app tests passed, no failures/skips; 10 CI-tool tests passed; app-source coverage 1,243/1,261 executable lines (98.6%). Build and static analysis passed.
- Validation used Xcode 27 / iOS 27. The original hosted failure on iOS 26.2 was a text-based header lookup; the fix uses a stable identifier. Hosted results after the final push and merge have not been verified in this chat.

## Review follow-up validation

- After the review changes, build/static analysis, 103 unit tests and three focused UI regressions passed (106 tests total). These cover zero-entry quantities, Library refresh-button removal, search/detail retries, save retries, and editing copy formats/quantities in dark/maximum Dynamic Type. Test log: `/tmp/shogun-sho3-copy-edit.log`. All selected test suites passed; Xcode then stalled exporting its result bundle, so the completed run was terminated during teardown. The xcresult bundle is incomplete. Release build passed.
- Backend: 150 SQL checks, real-JWT copy editing/permission/conflict/retry checks and 19 tooling unit tests passed. Additive copy-edit migration applied without resetting data.
- Sorting and format filters were recorded as SHO-28 in Backlog.

## Next steps

1. Check the latest `dev` GitHub Actions and SonarQube Cloud results after the merge.
2. SonarQube Cloud's remote quality gate has not been confirmed updated to 85%. Custom gates require a supported paid plan and administrator permission. The repository's CI enforces 85% overall coverage independently. See docs/CI.md.
3. Before starting the next ticket, fetch the latest `dev` and create the appropriate ticket branch per AGENTS.md. The local checkout was left on the SHO-13.1 branch.

## Other discussion

- GitHub Copilot PR reviews require eligible Copilot access; no integration was added. Code reviews can also be requested in this Codex chat.
- GitHub Actions runs and cleans up its own iPhone simulator; a local simulator need not stay running for CI.
- Future backlog ideas already captured: watched-but-unowned movies and a ranking-test-generated Top 100 list, beyond Phase 2 (phase still to be decided).
