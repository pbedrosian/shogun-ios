# Shogun — Phase 1

Native iPhone app for iOS 17+, built with SwiftUI and Apple frameworks only.

## Open and run

1. Open `Shogun.xcodeproj` in Xcode 15 or later (validated with Xcode 27).
2. Select the **Shogun** scheme and an installed iPhone simulator with iOS 17 or later.
3. Press **Run** (Command-R). No API keys or accounts are needed.
4. For a physical iPhone, choose your development team under Signing & Capabilities and change `com.example.Shogun` to a unique bundle identifier.

## Included

- Library poster grid with personal/shared library selector and collection search.
- Movie details with title, year, synopsis, owned formats and copy counts across accessible libraries.
- Editable per-user watched status and optional 1–5 star rating, shared across library views.
- Searchable eight-movie sample catalog with existing-ownership indicators.
- Placeholder profile, tab navigation, and automatic system light/dark appearance.
- Original poster artwork generated locally by SwiftUI shapes, gradients, text and SF Symbols. No remote images or asset downloads.

The demo has six personal titles and three family titles, including an overlapping movie and two VHS copies of the same movie. Changes are in memory and reset when the app restarts. Account creation, invitations, full catalog/manual movie entry, persistence, Supabase and TMDB remain outside this preview. The Library redesign includes a small local sample-copy sheet behind the + button.

## Architecture

`App` owns one observable mock store. `Features` contains Library, Search and Profile views. `Shared` contains reusable poster/card views. `Models` separates stable movie metadata, library memberships, individual owned copies and user/movie viewing state. `Services` provides mock data and access filtering. Membership filtering is a local demonstration; future services must enforce authorization on the server.

## Validation

Run from this directory:

```sh
xcodebuild -project Shogun.xcodeproj -scheme Shogun -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ShogunDerivedData CODE_SIGNING_ALLOWED=NO build
swiftc -module-cache-path /tmp/ShogunModuleCache Shogun/Models/Models.swift Shogun/Services/MockCatalog.swift Shogun/Services/CatalogStore.swift Checks/main.swift -o /tmp/shogun-model-checks
/tmp/shogun-model-checks
```

The unsigned Debug simulator build succeeded for arm64 and x86_64. Model/store checks passed for unique IDs, valid references, memberships, all formats, repeated copies, metadata reuse, cross-library personal state, rating bounds and clearing.

Xcode reported CoreSimulator service failures and a version mismatch (installed 1051.49.0 versus expected 1171.7.0), plus a CoreDevice plugin loading issue. No simulator could be launched, so visual appearance, accessibility layout and interactive navigation remain unverified at runtime. Initial macro-plugin failures were avoided with ObservableObject and Published state. The final build reports only environmental diagnostics and an App Intents metadata notice; there is no App Intents dependency.

Manual checks in Xcode: switch libraries, search by title/year, open details from both tabs, change watched/rating then open the same title through the other library, clear rating, and check light/dark mode and large Dynamic Type. Restart to confirm the documented demo reset.

See AGENTS.md for project conventions. No signing team or production icon is configured; add these before distribution.

## Library redesign preview

Branch: `feature/library-redesign`, based on `dev`. Implements the supplied Figma screenshots with warm off-white/charcoal canvas colors, vintage-red controls, compact Library header, library selector, local search, and muted poster placeholders. Named color assets carry light/dark variants. Native tab navigation is retained and tinted to match.

The view menu immediately left of + offers Zoom In/Out across 2–5 columns. Dense grids omit captions; VoiceOver still reads movie title, year and formats. Accessibility Dynamic Type uses two columns. + opens a minimal local sample-copy form, defaults to the current writable library, and shows ownership across accessible libraries. This is not the full planned TMDB/manual-entry flow.

Verification: Debug simulator build and model/store checks pass, including zoom bounds, invalid-library rejection and adding a copy without duplicating metadata. Runtime visual verification remains unavailable from the agent environment because CoreSimulator services cannot be reached. In Xcode, run both appearances, open the view menu and check both bounds, switch libraries, search/no results, open a movie and return, add a sample copy, and check large text/VoiceOver. Compare the overall layout with the supplied screenshot; exact live Figma token inspection was unavailable due to the Starter-plan tool limit.

## Library pinch zoom (SHO-2)

Pinch anywhere in the Library scroll area, including the blank space below short collections, to change the same 2–5 column density used by the view menu. Density updates while both fingers remain down: spread to enlarge posters, pinch inward to fit more, and reverse direction without lifting. Each update divides the gesture's starting column count by its magnification and rounds to the nearest supported density, so updates do not compound or depend on event frequency. Ending or cancelling a gesture resets its baseline for the next pinch.

The pinch takes priority over poster taps and disables movie links while active. One-finger scrolling and ordinary taps remain available outside a pinch. The full Library viewport accepts pinch gestures, including empty results and space below the last row. Accessibility Dynamic Type retains two columns and ignores pinch changes, matching the disabled menu controls. Pinch transitions respect Reduce Motion. Density remains in memory and resets on relaunch.

Manual verification: begin with both fingers on blank space below a short collection, then repeat on posters and zoom in/out repeatedly without lifting; confirm no details open; exercise both bounds; alternate pinch and menu actions; scroll and tap details after releasing; switch libraries and filter/clear search; repeat in light/dark appearance and accessibility text sizes. Gesture recognition, navigation interactions, and visual layout require hands-on verification beyond the store tests.

SHO-2 verification: 67 XCTest tests passed with zero failures and zero skipped on a separate iPhone 17 / iOS 27.0 simulator, with coverage enabled. Seven pinch regression tests cover shared menu state, continuous reversals, every starting/target density, repeated updates without compounding, new gesture baselines, invalid/extreme scales, and preservation of collection state when no movies are visible. Xcode measured CatalogStore.swift at 79/79 executable lines (100%), including the pinch method at 5/5, and Models.swift at 3/3 (100%). Whole-app line coverage was 608/1244 (48.9%); launch-executed view lines do not establish gesture interaction coverage. Accessibility gesture gating, blank-space hit testing, and suppression of movie navigation remain device/UI verification items. Earlier simulator attempts stalled before test execution; the separate-device run completed successfully.

## Styling organization

`Shogun/DesignSystem/Theme/ShogunTheme.swift` is the central reference for colors, semantic type, spacing, radii, sizes and procedural poster styling. `SystemAppearance.swift` configures native bars. `Styles/ViewStyles.swift` owns reusable surface, canvas, brand, movie text and rating-button treatments. `Components/ShogunIcon.swift` owns header icon sizing. Feature views keep their structural stacks, alignment, navigation and behavior. This extraction preserves the existing layout and asset values.

## Unit tests

Open `Shogun.xcodeproj`, select the shared **Shogun** scheme and an iPhone simulator, then press **Command-U**. The scheme includes `ShogunTests` and `ShogunUITests` and collects combined code coverage. Native UI tests exercise library search, density controls/pinch, movie diary state across tabs, add-copy cancellation/saving, Search/Profile, dark appearance, and accessibility text sizes.

From the repository directory:

```sh
xcodebuild -project Shogun.xcodeproj -scheme Shogun \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO test
```

Use an installed simulator name from `xcrun simctl list devices available` if yours differs. To run one concern, add e.g. `-only-testing:ShogunTests/SearchTests`.

The suite is organized under `ShogunTests`, with fresh stores per test and deterministic shared fixtures in `TestFixtures.swift`:

| File | Concern |
| --- | --- |
| `ModelTests.swift` | Format identifiers/serialization, movie equality, personal-state defaults |
| `CatalogIntegrityTests.swift` | Demo identifiers, references, memberships, formats, metadata reuse |
| `LibraryAccessTests.swift` | Membership filtering, owner/editor/viewer permissions, selection fallback |
| `OwnershipTests.swift` | Cross-library copies, library scoping, repeated copies, deduplicated movie cards |
| `PersonalMovieStateTests.swift` | Watched/rating updates, bounds, clearing, user/movie isolation |
| `AddCopyTests.swift` | Valid additions, rejected writes, unique copy IDs, metadata/state preservation |
| `SearchTests.swift` | Global title/year search, library title search, query isolation, empty results |
| `PresentationStateTests.swift` | Zoom bounds, initial presentation state, in-memory reset on a fresh store |

Search and Library views consume the tested `CatalogStore.searchResults` and `libraryResults`. Store initialization accepts catalog/user inputs so permission tests can include viewers, other users, and inaccessible libraries without mutating global demo data. The default initializer preserves the existing app behavior. Result order remains catalog order; there is no sorting feature yet.

SHO-12 verification: 60 tests passed with zero failures on the iPhone 17 simulator (iOS 27.0). Xcode reported 100% executable-line coverage for `CatalogStore.swift` and `Models.swift`; this is not a claim of complete UI or branch coverage. Existing standalone checks in `Checks/main.swift` also passed.

Unit tests cover the current business logic, not rendered SwiftUI layout. Profile's library list uses the same tested access rules; its static account/about text, navigation, sheets, poster layout, accessibility, Dynamic Type, orientation, native appearance, and the Search/Profile header gap (SHO-11) still require UI/device verification. The demo assumes at least one accessible library when displaying `selectedLibrary`; a no-membership account screen is not implemented. No network, persistence, sign-in, invitations, or remote lookup behavior exists to test yet.

## Continuous integration (SHO-13)

GitHub Actions and the optional Jenkinsfile use `python3 scripts/ci/run.py` for unsigned simulator builds, Xcode static analysis, XCTest with coverage, and standalone model checks. At least 85% app-source line coverage and the existing 100% store/model baseline are enforced; reports include all app Swift sources without hiding views. SonarQube Cloud analysis activates when its project, organization, and token are configured.

See [CI setup and local reproduction](docs/CI.md) for the pinned hosted toolchain, artifacts, coverage policy, Jenkins requirements, Sonar activation, and remaining hosted acceptance checks.

SHO-13.1 verification: 72 app tests (67 unit + 5 UI), zero failures/skips, and 10 CI-tool tests passed locally on iPhone 16 / iOS 27 with Xcode 27. Combined app-source line coverage was 1234/1252 (98.6%), above the enforced 85% floor; core model/store files remained at 100%. Sonar's project-level new-code threshold must also be configured to 85% in its custom quality gate; it is not controlled by scanner properties.
