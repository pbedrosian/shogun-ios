# Add movies from Search (SHO-4)

Search results offer a plus button; movie details offer **Add to library**, or
**Add another copy** when the person already owns that TMDB movie. Both open the
existing Add Movie form with the exact provider movie selected. The form fetches
canonical details without asking the person to search again.

Search additions prefer the account's configured writable default library, then
the selected writable library, then the first writable library. The person can
change the destination. The draft preserves that choice instead of resetting it
when it reappears. All quantities start at zero and require explicit selection;
there is no silent one-tap copy creation. Existing ownership shows the current
accessible copy count and saving deliberately adds copies.

Accounts without an owner/editor library can still browse details. Add actions
are disabled with an explanation. The backend rechecks membership on Save, so
revocation while a form is open cannot authorize a write. Cancelling does not
change the collection or clear the Search query. Failed saves retain the form and
the existing retry identity.

`CatalogSearchView` and `CatalogDetailView` present `SearchAddMovieSheet`, which
supplies the account-bound collection, current catalog, selected movie and default
destination to `ConnectedAddMovieSheet`. Library additions keep their current
library behavior. The shared form also supports SHO-36's cover-selection section
when that feature is integrated; Search does not implement a separate add API.

Validation includes `MovieAddTests/testSearchAddPrefersWritableDefaultAndPreservesUserDestination`
and `QuickAddUITests`: preselection without another search, explicit quantities,
failed-save retry, Add Another Copy, cancellation in dark/accessibility text, and
disabled actions with no writable library. Existing backend transaction and RLS
checks remain authoritative.
