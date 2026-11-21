# Personal custom grid — SHO-40

Select Custom in the sort menu, then press and hold a movie to enter arranging
mode. Other sorts do not offer press-and-hold or drag reordering. Drag tiles to
reorder; the bottom Library/Search/Profile tab bar is replaced by a Done button.
The Done control slides/fades in from the bottom; leaving arranging mode reverses
the transition and restores the native tabs. Reduce Motion uses an immediate swap.
Tap Done to restore the tabs and normal navigation. Custom appears alongside the
existing sorts. Selecting another sort never overwrites the custom arrangement.
VoiceOver offers Move earlier and Move later actions; Reduce Motion disables the
reordering transition.

Orders are movie identities, independent of copies and formats. Each account and
library has its own order, including shared libraries: changing your layout never
changes another member's layout. The first arrangement starts from the current
sort, including movies hidden by search or format filters. Moving a visible tile
preserves the relative order of the other movies. Later arrivals append at the
end; removed movies are pruned when the collection refreshes.

This first implementation persists locally through the existing injected
UserDefaults mechanism, under `library.customOrder.v1.<userID>`. It survives app
relaunch and collection refresh. It does not yet synchronize across devices.
Ownership, movie metadata, ratings and watched state are unchanged.

Regression coverage in SearchTests verifies sort restoration, persistence,
account/library isolation, filtered movement and successive collection refreshes.
AppFlowTests verifies native long-press/drag, Custom restoration after another
sort, and navigation after finishing arrangement.

## Responsibility boundaries

- `LibraryView` composes the screen and owns navigation/arranging visibility.
- `LibraryControls` contains focused heading, selector, search, summary and options
  views; interaction callbacks finish arranging before another control is used.
- `LibraryMovieTile` owns tile presentation, normal tap navigation and accessible
  move actions. It does not implement ordering or preferences storage.
- `LibraryGridInteraction` owns the scroll-container hold recognizer, simultaneous
  touch handling and edge scrolling. Its geometry policy chooses visible drop
  targets; it emits movie/position intents without deciding saved order.
- `LibraryLiftedMovie` in the same file renders the floating cover independently
  of grid layout; the original tile reserves an empty cell.
- `LibraryCustomOrder` in Models contains pure reconciliation/movement rules.
- `LibraryOrderPreferences` handles account-scoped local serialization only;
  CatalogStore coordinates catalog state with those rules and storage.
- `ShogunJiggleStyle` owns Reduce Motion-aware visual movement.

The native hold recognizer enters arranging at its began state after 0.25 seconds,
while the finger is still down. Background dismissal listens only while arranging
and no movie is currently held, so a second finger cannot dismiss an active drag.
Each drag also requires a 0.25-second hold before movement, including when already
arranging, so a quick press or scroll does not immediately move a movie.

While dragging, a separate lifted movie follows the finger above the grid. Its
original grid cell becomes empty and the neighboring movies slide aside as the
custom order changes, leaving the reserved landing space like iOS app arranging.
There is no drop text, dashed outline or destination badge. The lifted copy does
not participate in grid layout or intercept touches; the scroll container retains
the gesture even when tiles leave the viewport. Reduce Motion keeps ordering immediate. Ordering and persistence
continue through the existing CatalogStore policy and preferences adapter.

## Scrolling while arranging

Pinch-to-change-columns is disabled for the entire arranging session. Other
controls still end arranging before applying their normal actions. A quick swipe
scrolls normally; after holding a movie, another finger can pan the page without
moving the held finger. The hold recognizer ignores additional touches and allows
the native scroll pan to recognize simultaneously. The scroll pan's original
touch requirement is restored on release, cancellation, exit or view teardown.

Holding near the top or bottom edge scrolls automatically, faster toward the edge,
clamped to the content bounds. Drop targets are re-evaluated while scrolling even
when the finger stays still. Header areas and gaps choose the nearest visible
tile, allowing a movie to reach the first/last visible slot. Pull-to-refresh does
not refresh collection data while arranging.

The Debug-only `-shogun-demo -shogun-long-grid` fixture supplies 90 local movies for
multi-page scrolling regression tests; it does not connect to a real account.
