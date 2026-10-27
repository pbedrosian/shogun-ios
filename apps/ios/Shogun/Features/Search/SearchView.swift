import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    private var results: [Movie] { store.searchResults }
    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { movie in
                    NavigationLink(value: movie) {
                        HStack(spacing: ShogunTheme.Spacing.selector) {
                            PosterView(movie: movie).frame(
                                width: ShogunTheme.Size.searchPosterWidth)
                            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
                                Text(movie.title).font(ShogunTheme.Typography.headline)
                                Text(movie.releaseYearText).foregroundStyle(.secondary)
                                if !store.copies(for: movie).isEmpty {
                                    Label("Already owned", systemImage: "checkmark.circle.fill")
                                        .font(ShogunTheme.Typography.caption).foregroundStyle(.tint)
                                }
                            }
                        }.padding(.vertical, ShogunTheme.Spacing.tight)
                    }.accessibilityIdentifier("search.movie.\(movie.id)")
                }

            }
            .refreshable { await collection?.refresh() }
            .safeAreaInset(edge: .bottom) {
                if let collection {
                    CollectionFeedback(store: collection).padding().background(ShogunTheme.canvas)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: store.searchQuery).accessibilityIdentifier(
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
