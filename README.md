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

The demo has six personal titles and three family titles, including an overlapping movie and two VHS copies of the same movie. Changes are in memory and reset when the app restarts. Account creation, invitations, adding movies, persistence, Supabase and TMDB are intentionally outside Phase 1.

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
