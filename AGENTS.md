# Shogun development conventions

- Open Shogun.xcodeproj; the shared scheme is Shogun. Minimum iOS 17, iPhone only.
- Use SwiftUI and native Apple components; avoid third-party dependencies.
- Organize screens under Features, domain types under Models, data access under Services, reusable views under Shared.
- Movies have stable metadata IDs. OwnedCopy belongs to a library and refers to a movie. Never put ownership on a user or collapse multiple copies into a single format flag.
- PersonalMovieState is keyed by user and movie, independent of library ownership. Ratings are nil or 1–5.
- Memberships scope accessible libraries. Mock filtering is demonstration only; future backend work must enforce permissions server-side and must not trust client-supplied user IDs.
- Phase 1 is offline and in-memory. Do not add Supabase, TMDB, authentication, secrets, remote artwork, or network dependencies.
- Posters use original procedural SwiftUI artwork. Preserve light/dark support, Dynamic Type, accessible labels, and native navigation.
- Build: xcodebuild -project Shogun.xcodeproj -scheme Shogun -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
- Run model checks: swiftc Shogun/Models/Models.swift Shogun/Services/MockCatalog.swift Shogun/Services/CatalogStore.swift Checks/main.swift -o /tmp/shogun-model-checks && /tmp/shogun-model-checks
- Validate UI on an iPhone simulator in light/dark appearance, large text, library switching, search, and cross-library rating consistency. Personal edits intentionally reset at relaunch.

## Git workflow

- `main` is the stable, tested branch. `dev` is the integration branch.
- Start each change on a new descriptive branch from the latest `dev` (for example, `feature/local-persistence` or `fix/library-search`).
- Merge completed work into `dev`, then run build checks, model checks, and appropriate simulator tests on the integrated changes.
- Merge `dev` into `main` only after testing passes. Push the updated branches.
- Do not develop directly on `main` or `dev`; use a separate branch for each change.

## Design system

- Shared visual rules live in `Shogun/DesignSystem`: Theme contains semantic color, typography, spacing, size and radius tokens plus native appearance setup; Styles contains reusable ViewModifier and ButtonStyle definitions; Components contains reusable styled view elements.
- Color values and light/dark variants stay in Assets.xcassets. Use ShogunTheme tokens rather than repeating literal fonts, colors, padding or radii in feature views.
- Use `.shogunCanvas()`, `.shogunSurface()`, `.shogunBrand()`, `.movieTitleStyle()` and `.movieMetadataStyle()` for their corresponding visual treatments. Header icon labels use ShogunIcon; rating buttons use ShogunRatingButtonStyle.
- Keep structural layout, navigation, data bindings and accessibility in feature/component views. Extract a style when it describes a reusable visual role; do not create a separate modifier for every stack.
- Preserve Dynamic Type semantic fonts, the two-line reserved movie title, top-aligned grid items and the existing Photos-style view menu.
