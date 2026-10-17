import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    private var results: [Movie] { store.searchResults }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Explore a small sample catalog. Movie lookup and adding copies will arrive in a future phase.").font(ShogunTheme.Typography.body).foregroundStyle(.secondary)
                }
                Section("Sample movies") {
                    ForEach(results) { movie in
                        NavigationLink(value: movie) {
                            HStack(spacing: ShogunTheme.Spacing.selector) {
                                PosterView(movie: movie).frame(width: ShogunTheme.Size.searchPosterWidth)
                                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
                                    Text(movie.title).font(ShogunTheme.Typography.headline)
                                    Text(String(movie.year)).foregroundStyle(.secondary)
                                    if !store.copies(for: movie).isEmpty { Label("Already owned", systemImage: "checkmark.circle.fill").font(ShogunTheme.Typography.caption).foregroundStyle(.tint) }
                                }
                            }.padding(.vertical, ShogunTheme.Spacing.tight)
                        }
                    }
                }
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: store.searchQuery) } }
            .scrollContentBackground(.hidden).background(ShogunTheme.canvas)
            .navigationTitle("Search")
            .searchable(text: $store.searchQuery, prompt: "Title or release year")
            .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
        }
    }
}
