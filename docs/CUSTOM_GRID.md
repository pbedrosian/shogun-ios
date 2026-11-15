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
- `LibraryMovieTile` owns tile presentation, a native tap/quarter-second hold adapter
  and drag/drop intent. It does not implement ordering or preferences storage.
- `LibraryCustomOrder` in Models contains pure reconciliation/movement rules.
- `LibraryOrderPreferences` handles account-scoped local serialization only;
  CatalogStore coordinates catalog state with those rules and storage.
- `ShogunJiggleStyle` owns Reduce Motion-aware visual movement.

The native hold recognizer enters arranging at its began state after 0.25 seconds,
while the finger is still down. Background dismissal listens only while arranging.
Each drag also requires a 0.25-second hold before movement, including when already
arranging, so a quick press or scroll does not immediately move a movie.
