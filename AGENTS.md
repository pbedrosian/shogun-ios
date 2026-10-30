# Shogun development conventions

- Repository layout: native app/project/tests/model checks live in apps/ios; Supabase configuration/migrations/fixtures/tests live in backend/supabase. Shared scripts, npm commands and CI entry points remain at the repository root. Run documented commands from the repository root.

- Open apps/ios/Shogun.xcodeproj; the shared scheme is Shogun. Minimum iOS 17, iPhone only.
- Use SwiftUI and native Apple components. The official Supabase Auth SDK is approved for authentication; keep other dependencies minimal.
- Organize screens under Features, domain types under Models, data access under Services, reusable views under Shared.
- Movies have stable metadata IDs. OwnedCopy belongs to a library and refers to a movie. Never put ownership on a user or collapse multiple copies into a single format flag.
- PersonalMovieState is keyed by user and movie, independent of library ownership. Ratings are nil or 1–5.
- Memberships scope accessible libraries. Mock filtering is demonstration only; future backend work must enforce permissions server-side and must not trust client-supplied user IDs.
- SHO-19 connects real Supabase authentication and Keychain-backed sessions. The production app has no offline/demo entry point. Preserve the sample catalog only as a Debug UI-test fixture; SHO-20 connects collections through CollectionStore/CollectionServicing; see docs/COLLECTIONS.md. SHO-25 authorizes local Supabase tooling/configuration beside the app; SQL schema and server-side authorization belong to SHO-18. Do not add TMDB or remote artwork as part of authentication. Never commit secrets.
- Database changes belong in versioned SQL migrations. Every exposed application table needs explicit grants and RLS. Derive identities from auth.uid(), restrict SECURITY DEFINER helpers and pin their search paths, and run backend:test:db plus backend:test:api for permission changes. See docs/DATABASE.md for the role model and recovery instructions.
- Persisted fixture posters use procedural SwiftUI artwork. SHO-8 provider search/details use TMDB artwork with procedural fallbacks and required attribution. Keep TMDB credentials server-only; see docs/MOVIE_API.md. Preserve light/dark support, Dynamic Type, accessible labels, and native navigation.
- Build: xcodebuild -project apps/ios/Shogun.xcodeproj -scheme Shogun -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
- Run model checks: swiftc apps/ios/Shogun/Models/Models.swift apps/ios/Shogun/Services/MockCatalog.swift apps/ios/Shogun/Services/CatalogStore.swift apps/ios/Checks/main.swift -o /tmp/shogun-model-checks && /tmp/shogun-model-checks
- Validate UI on an iPhone simulator in light/dark appearance, large text, library switching, search, and cross-library rating consistency. Debug fixture edits reset at relaunch; real saved edits must persist.

## Git workflow

- `main` is the protected release branch. `dev` is the default integration branch and carries the next release's SNAPSHOT version.
- Feature/fix work starts from latest `dev` and merges back through an MR. Work branches use `<devName>/sho-<ticket-number>` with lowercase `sho` and the matching Notion ticket number.
- Urgent hotfix ticket branches may start from the current release tag only with explicit approval when dev contains unrelated work; return the fix to dev. See docs/RELEASING.md.
- Release-candidate branches are the explicit exception: cut `release/<version>-rc.<n>` from an approved dev commit, stabilize and validate that frozen candidate, then promote it to main through an MR. Return candidate fixes to dev while retaining dev's next SNAPSHOT label. See docs/RELEASING.md.
- Approved frozen release candidates may be distributed to TestFlight alpha against the alpha backend. Production deployments use only an approved immutable final version tag on main (for example `1.0.0`). Uploading/distributing a candidate, cutting a final tag, and deploying production each require explicit user authorization; branch creation does not publish anything.
- Use `peterbedrosian` as the developer name for this user; for example, ticket SHO-2 uses branch `peterbedrosian/sho-2`. Do not use `feature/`, `fix/`, or `docs/` branch names for new work.
- Confirm the developer name and ticket number from the task context before creating a branch; ask for any missing value rather than inventing one.
- Make changes and run appropriate checks, then leave all work uncommitted for the user to review.
- Do not commit, merge, or push automatically. Wait for the user to review the changes and explicitly authorize each requested action. Completing work or passing tests is not authorization.
- Authorization to commit does not authorize pushing or merging; perform only the actions the user explicitly requests.
- When explicitly authorized, merge completed work into `dev` and run build checks, model checks, and appropriate simulator tests on the integrated changes. Merge `dev` into `main` only after testing passes and the user explicitly authorizes that merge. Push only when explicitly authorized.
- Do not develop directly on `main` or `dev`; use a separate branch for each change.

## Design system

- Shared visual rules live in `apps/ios/Shogun/DesignSystem`: Theme contains semantic color, typography, spacing, size and radius tokens plus native appearance setup; Styles contains reusable ViewModifier and ButtonStyle definitions; Components contains reusable styled view elements.
- Color values and light/dark variants stay in Assets.xcassets. Use ShogunTheme tokens rather than repeating literal fonts, colors, padding or radii in feature views.
- Use `.shogunCanvas()`, `.shogunSurface()`, `ShogunWordmark`, `.movieTitleStyle()` and `.movieMetadataStyle()` for their corresponding visual treatments. Header icon labels use ShogunIcon; rating buttons use ShogunRatingButtonStyle.
- Keep structural layout, navigation, data bindings and accessibility in feature/component views. Extract a style when it describes a reusable visual role; do not create a separate modifier for every stack.
- Preserve Dynamic Type semantic fonts, the two-line reserved movie title, top-aligned grid items and the existing Photos-style view menu.

## Maintainability

- Follow docs/ARCHITECTURE.md for view/store/service boundaries and styling. Keep navigation in App, screen-specific code in Features, and backend/SDK work in Services.
- Use the repository .swift-format settings for modified Swift files; avoid unrelated formatting churn. Do not bypass compiler warnings or coverage checks to make a refactor pass.
- Prefer Task cancellation checks to duplicate cancellation flags, and keep injected service implementations private to their coordinating store.

- Shared authenticated HTTP construction belongs in BackendHTTPClient. Feature services own their wire mapping/errors; views must not call providers or handle credentials. Keep TMDB IDs distinct from backend UUIDs and match ownership by provider ID, never title/year.
