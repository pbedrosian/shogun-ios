# Development handoff — October 28, 2026

## Where we stopped

- Shogun **0.2** is on `main` and `dev`. Main promotion: [PR #19](https://github.com/pbedrosian/shogun-ios/pull/19), merge `ca28cf9`; dev head: `64cb2d1` ([PR #18](https://github.com/pbedrosian/shogun-ios/pull/18)). Their file contents match. Version bump commit: `4647f14`; Debug and Release use marketing version 0.2, build number remains 1.
- SHO-8 merged through [PR #15](https://github.com/pbedrosian/shogun-ios/pull/15). SHO-3 merged through [PR #16](https://github.com/pbedrosian/shogun-ios/pull/16), merge `e21d3d6`. No SHO-3 feature review/commit/push/merge remains outstanding.
- Workflow cost controls merged through [PR #17](https://github.com/pbedrosian/shogun-ios/pull/17), commit `0c8b5cd`, then reached main in PR #19. Both GitHub workflows are active on the default branch.
- This handoff update is maintained on `peterbedrosian/sho-3` as a separate documentation commit. Application/workflow/version commits are already pushed and merged; merging this handoff into dev/main requires separate authorization.

## Today's app changes

- The Library + sheet supports TMDB title search, details autofill, manual entry, writable destination selection, and per-format copy quantities. All quantities start at **zero**; adding requires 1–99 copies total.
- Manual metadata supports title, year, director, synopsis, runtime, genres and an optional HTTPS poster URL. Provider import fetches canonical metadata server-side; TMDB credentials stay out of the app.
- Removed the saved-movie picker/sheet and dedicated client APIs/tests for that flow. New entries use search or manual entry.
- Removed the Library refresh button; pull-to-refresh remains.
- Library movie details support **owned-copy editing only**, for writable libraries. Users can change formats/counts; zero removes copies from that library. Movie metadata and diary state are preserved; stale drafts return HTTP 409 and retries remain safe.
- Manual creation and provider import atomically save metadata/copies, derive the actor from validated authentication, and recheck membership. Manual movies never deduplicate solely by title/year; provider IDs preserve stable identity. Save failures retain drafts and retry IDs. See [MOVIE_ADD.md](MOVIE_ADD.md).
- Created **SHO-28: Add Library sorting and filters** in Backlog: recently added, A–Z/Z–A, and format/type filters. [Ticket](https://app.notion.com/p/40808c1af1ec81d791d4dcd64a7fda0d).

## Validation and CI fixes

- Final SHO-3 hosted iOS, backend and SonarCloud checks passed before PR #16 merged. Earlier hosted large-text form scrolling failure was fixed in `22de816`.
- For the main promotion, local build/static analysis, model checks, 103 unit tests and 16 of 17 UI tests passed in the full run. The remaining large-text manual-entry test exposed an iOS 27 keyboard-focus failure: a hittable synopsis field was under the navigation bar.
- Fixed the UI test helper in `0ae3e47`: typing fields must be in the clear form area before tapping; buttons retain their original reveal behavior. All **three affected UI tests passed** afterward, including manual movie entry and owned-copy editing. No application behavior was changed for this fix. These are full-run plus focused-rerun results, not a fresh all-green full-suite report.
- Initial full-run coverage was **90.6%** (85% required), with Models/CatalogStore at 100%. That report retains the original failed UI test and must not be described as an entirely passing run.
- Local backend verification passed: **19 tooling tests**, **150 SQL assertions**, and real-JWT permission, collection/retry, movie-add, catalog and account-deletion suites. CI report tooling: **10 tests** passed. The integrated dev build passed after the version/test commits; main has identical file contents.
- Built app Info.plist confirmed version **0.2**. No hosted Actions runs were requested or started during the version/main promotion.
- Diagnostics (temporary local files): `/tmp/shogun-main-promotion-f23eb9c/summary.md`, `/tmp/shogun-main-promotion.log`, `/tmp/shogun-version02-ui-final.log`, `/tmp/shogun-version02-ui-final.xcresult`, `/tmp/shogun-version02-integrated-build.log`. Earlier focused rerun logs are superseded by `ui-final`.

## Cost controls — preserve these tomorrow

- User explicitly wants **no development fees**. Default to local tests. Do not buy plans, credits, hosting, domains or subscriptions without explicit approval.
- Both workflows now run **weekly Monday at 13:17 UTC** (09:17 Eastern daylight / 08:17 Eastern standard), plus manual dispatch. No push or PR triggers. Next scheduled date after this handoff: **Monday, November 2, 2026 at 08:17 EST**; GitHub may delay scheduled starts.
- GitHub Actions account-wide saved budget for `pbedrosian` was verified in the budgets list: **$0**, **Usage blocked**, paid spending **$0.00**. The saved stop blocks paid overages after included capacity is exhausted. Scheduling reduces usage but does not itself enforce the allowance. Do not raise the budget or add payment details to unblock CI.
- iOS artifacts now expire after **three days**. Manual runs and other repositories share account limits. Run tests locally before merges; a previous weekly result does not validate newer commits.
- Sonar screenshot showed a Team trial scheduled to downgrade **November 5, 2026**. Leave the downgrade in place. Its destination plan and the email's additional product subscription were not independently verified; do not assume all Sonar billing is resolved. Do not cancel the downgrade or add payment details. Free-plan branch/PR limits may require later configuration; no paid upgrade is authorized.
- Local Supabase/Docker remain the development backend; no hosted deployment was added. No OpenAI API integration was added to Shogun. Existing account subscriptions are separate from repository changes.

## Services at shutdown

- Local Supabase was stopped using `npm run backend:stop`, preserving database volumes. Docker Desktop was stopped after confirming no other containers were running.
- No dev/Swagger launcher or xcodebuild process was running at shutdown. No simulator devices were booted; all simulators created for today's checks were deleted.
- Project service ports 54320/54321/54322/54323/54324/54327/54328/54329/54330 were checked closed. Ignored local configuration and credentials were preserved; do not reset the database tomorrow.
- Weekly GitHub schedules are intentionally still enabled remotely. Local shutdown does not disable them or cancel the saved spending stop.

## Tomorrow's starting point

1. Read this handoff and [MOVIE_ADD.md](MOVIE_ADD.md). No further app/version merge is pending. The separate handoff documentation change remains on `peterbedrosian/sho-3` until its merge is authorized.
2. Start local development from the repository root with `npm run dev`; it can start Docker Desktop and reuse preserved data/configuration. Rebuild the Shogun scheme in Xcode. For phone access, verify the current Mac LAN IP before regenerating ignored iOS configuration. Never print keys or the TMDB token.
3. Smoke-check version 0.2, provider/manual movie addition, zero initial quantities, pull-to-refresh, and editing owned copies from Library details. Keep the loading-section polish as a later review item.
4. Recommended next feature remains **SHO-4: Quick Add**, subject to the user's choice; SHO-28 sorting/filtering is separately in Backlog. Confirm the ticket before starting its branch from latest dev. SHO-3's Notion status was last known In Development; reconcile its status with the completed PR if requested rather than assuming it was updated.
5. Keep hosted deployment, production email and social login separate. Use local validation for daily work; do not start hosted runs merely to recheck already-passing results. See [CI.md](CI.md), [BACKEND.md](BACKEND.md), and [EMAIL.md](EMAIL.md).

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
