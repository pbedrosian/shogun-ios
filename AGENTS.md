# Shogun development conventions

- Repository layout: native app/project/tests/model checks live in apps/ios; Supabase configuration/migrations/fixtures/tests live in backend/supabase. Shared scripts, npm commands and CI entry points remain at the repository root. Run documented commands from the repository root.

- Open apps/ios/Shogun.xcodeproj; the shared scheme is Shogun. Minimum iOS 17, iPhone only.
- Use SwiftUI and native Apple components; avoid third-party dependencies.
- Organize screens under Features, domain types under Models, data access under Services, reusable views under Shared.
- Movies have stable metadata IDs. OwnedCopy belongs to a library and refers to a movie. Never put ownership on a user or collapse multiple copies into a single format flag.
- PersonalMovieState is keyed by user and movie, independent of library ownership. Ratings are nil or 1–5.
- Memberships scope accessible libraries. Mock filtering is demonstration only; future backend work must enforce permissions server-side and must not trust client-supplied user IDs.
- The iOS app remains an offline, in-memory demo until its Phase 2 integration tickets are implemented. SHO-25 authorizes local Supabase tooling/configuration beside the app; SQL schema and server-side authorization belong to SHO-18. Do not connect the app to live services or add TMDB, remote artwork, or an SDK as part of backend setup. Never commit secrets.
- Posters use original procedural SwiftUI artwork. Preserve light/dark support, Dynamic Type, accessible labels, and native navigation.
- Build: xcodebuild -project apps/ios/Shogun.xcodeproj -scheme Shogun -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
- Run model checks: swiftc apps/ios/Shogun/Models/Models.swift apps/ios/Shogun/Services/MockCatalog.swift apps/ios/Shogun/Services/CatalogStore.swift apps/ios/Checks/main.swift -o /tmp/shogun-model-checks && /tmp/shogun-model-checks
- Validate UI on an iPhone simulator in light/dark appearance, large text, library switching, search, and cross-library rating consistency. Personal edits intentionally reset at relaunch.

## Git workflow

- `main` is the stable, tested branch. `dev` is the integration branch.
- Start each change from the latest `dev`. Every new work branch must use `<devName>/sho-<ticket-number>` with lowercase `sho` and the matching Notion ticket number.
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
- Use `.shogunCanvas()`, `.shogunSurface()`, `.shogunBrand()`, `.movieTitleStyle()` and `.movieMetadataStyle()` for their corresponding visual treatments. Header icon labels use ShogunIcon; rating buttons use ShogunRatingButtonStyle.
- Keep structural layout, navigation, data bindings and accessibility in feature/component views. Extract a style when it describes a reusable visual role; do not create a separate modifier for every stack.
- Preserve Dynamic Type semantic fonts, the two-line reserved movie title, top-aligned grid items and the existing Photos-style view menu.
