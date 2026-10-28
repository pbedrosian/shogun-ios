import SwiftUI

struct CatalogSearchView: View {
    @ObservedObject var search: CatalogSearchStore
    @ObservedObject var collection: CollectionStore
    let service: any MovieDiscoveryServicing
    var body: some View {
        NavigationStack {
            List {
                ForEach(search.results) { movie in
                    NavigationLink(value: movie) {
                        MovieResultRow(
                            title: movie.title, year: movie.releaseYearText,
                            isOwned: collection.catalog?.ownedMovie(tmdbID: movie.id) != nil,
                            artwork: CatalogPosterView(movie: movie))
                    }.accessibilityIdentifier("discovery.movie.\(movie.id)")
                }
                if let error = search.error {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("discovery.error")
                    Button("Try again", action: search.retry).accessibilityIdentifier(
                        "discovery.retry")
                } else if search.canLoadMore {
                    Button("Load more movies", action: search.loadMore).accessibilityIdentifier(
                        "discovery.more")
                }
                if search.phase == .loadingMore { ProgressView("Loading more movies…") }
            }
            .overlay {
                if search.phase == .loading {
                    ProgressView("Searching movies…").accessibilityIdentifier("discovery.loading")
                } else if search.phase == .empty {
                    ContentUnavailableView.search(text: search.query).accessibilityIdentifier(
                        "discovery.empty")
                }
            }
            .shogunListCanvas().navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .searchable(
                text: $search.query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search movies"
            )
            .onChange(of: search.query) { _, _ in search.search() }
            .onSubmit(of: .search) { search.search(immediately: true) }
            .navigationDestination(for: CatalogMovie.self) { movie in
                CatalogDetailView(movie: movie, service: service, collection: collection)
            }
        }
    }
}
