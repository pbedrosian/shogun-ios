# Swift code organization and review rules

Shogun is a native SwiftUI app. It does not use CSS/SCSS. Shared visual values
live in `Shogun/DesignSystem/Theme` and asset color sets; reusable presentation
roles live in `DesignSystem/Styles`, and reusable visual elements in components.
Do not add a web styling layer to style native views.

## Responsibilities

| Location | Responsibility |
| --- | --- |
| `App/ShogunApp.swift` | Construct/inject dependencies and select Debug-only test services. |
| `App/AppNavigation.swift` | Route restoration, signed-out, recovery and signed-in states; compose tabs. |
| `Features/Auth` | Login/create-account/recovery screens and their shared fields/header/feedback. |
| `Features/Profile` | Profile screen, reusable header, and separate deletion sheet. |
| `Services/AuthStore.swift` | Main-actor UI/session state and user actions; views cannot access its private service. |
| `Services/AuthModels.swift` | Provider-independent account, error, configuration and service contracts. |
| `Services/SupabaseAuthService.swift` | SDK integration, account bootstrap, authenticated HTTP calls, safe error translation. |
| `Services/SecureAuthStorage.swift` | Keychain operations, without view or navigation responsibilities. |
| `Models` | Catalog value types and relationships, independent of SwiftUI. |
| `backend/supabase` | Server schema, RLS, and privileged functions; no admin credentials in iOS. |

Views can own transient form fields, focus, sheets, and visibility toggles. Persistent
account/session actions go through the store and its injected service protocol.
SDK details stay in the service. Privileged deletion stays in the Edge Function.
Do not introduce a generic repository/DI framework before a concrete use case needs it.

Split substantial screens and independently reusable components into focused files.
Small closely related components can share a file (`AuthComponents.swift`). Keep
Xcode navigator groups aligned with physical folders and add new files to the
correct target. Moving files alone must not change routing or accessibility IDs.

## Styling and readability

- Reuse semantic colors, typography, spacing and sizes from the theme. Define new
  shared roles in styles rather than copying modifier chains between screens.
- Keep layout/data bindings in views; styles should not make network calls or
  change application state. Native semantic colors such as secondary/destructive
  styling remain appropriate.
- Use the checked-in `.swift-format` settings when formatting modified Swift files:
  `xcrun swift-format format --in-place PATH_TO_FILE`. The configuration uses four
  spaces and a 100-column target. Review formatting changes; avoid unrelated churn.
  Formatter output can differ by Xcode version; no unverified cross-version format
  gate has been added to CI.
- Prefer readable multi-line state transitions over multiple mutations separated
  by semicolons. Keep service dependencies and implementation state private.
- Remove unused fields, injected dependencies, dead entry points and obsolete
  protocol conformances. Do not keep unused production APIs solely to test them.
- Share request construction/headers/status decoding, but retain endpoint-specific
  behavior such as a wrong-password error for deletion. Similar-looking code with
  different security or lifecycle semantics should not be combined blindly.

## Concurrency and authentication

`AuthStore` is main-actor isolated. Swift Task cancellation is the source of truth;
check it before publishing an asynchronous account result. A cancelled operation
must clear any partial session, even if a service ignores cancellation and returns
success. Sign-out/deletion use a common private account-state reset. Do not log
passwords, tokens, complete email links, or server credentials.

Debug-only catalog fixtures and UI auth doubles are isolated from the normal app
flow. The documented local testing login is a real Supabase account, not a hidden
authentication bypass. UI tests select doubles explicitly through Debug arguments.

## Validation and known boundaries

Compiler warnings are errors for our own Xcode project. The shared CI runner builds,
analyzes, runs unit/UI tests and enforces coverage. Third-party packages manage their
own warning settings. These checks catch many mistakes; they do not prove that all
unused properties, lifecycle bugs, or duplication have been eliminated.

Use existing regression tests for structural changes. Add focused tests for a changed
behavior, such as rejecting a successful response after cancellation; do not add
assertions that merely repeat file organization or implementation details. Backend
permission changes need SQL plus real-JWT checks; deletion has separate isolation
and cascade tests. Run the Release build when changing Debug-only boundaries.

Before SHO-20 connects collections, handle loading, errors, and truly empty library
states explicitly. The current `CatalogStore` is a fixture store that assumes at
least one accessible library; its selected-library fallback must not be reused as
an unchecked assumption for remote data. Preserve backend UUIDs and ownership/RLS
semantics rather than wiring the offline default initializer to a real account.

Keep collection synchronization, social login, and external email setup in their
own implementation scope. See [AUTH.md](AUTH.md) and [EMAIL.md](EMAIL.md) for current
behavior and outstanding environment setup.
