import SwiftUI

#if DEBUG

    struct FixtureSearchView: View {
        @EnvironmentObject private var store: CatalogStore
        @Environment(\.collection) private var collection
        private var results: [Movie] { store.searchResults }
        var body: some View {
            NavigationStack {
                List {
                    ForEach(results) { movie in
                        NavigationLink(value: movie) {
                            MovieResultRow(
                                title: movie.title, year: movie.releaseYearText,
                                isOwned: !store.copies(for: movie).isEmpty,
                                artwork: PosterView(movie: movie))
                        }.accessibilityIdentifier("search.movie.\(movie.id)")
                    }

                }
                .refreshable { await collection?.refresh() }
                .safeAreaInset(edge: .bottom) {
                    if let collection {
                        CollectionFeedback(store: collection).padding().background(
                            ShogunTheme.canvas)
                    }
                }
                .overlay {
                    if results.isEmpty {
                        ContentUnavailableView.search(text: store.searchQuery)
                            .accessibilityIdentifier(
                                "search.empty")
                    }
                }
                .scrollContentBackground(.hidden).background(ShogunTheme.canvas)
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .searchable(
                    text: $store.searchQuery, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Title or release year"
                )
                .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
            }
        }
    }

#endif
