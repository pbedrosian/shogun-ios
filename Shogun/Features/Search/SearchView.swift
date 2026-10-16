import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var store: CatalogStore
    private var results: [Movie] { store.movies.filter { store.searchQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(store.searchQuery) || String($0.year).contains(store.searchQuery) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Explore a small sample catalog. Movie lookup and adding copies will arrive in a future phase.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Sample movies") {
                    ForEach(results) { movie in
                        NavigationLink(value: movie) {
                            HStack(spacing: 14) {
                                PosterView(movie: movie).frame(width: 64)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(movie.title).font(.headline)
                                    Text(String(movie.year)).foregroundStyle(.secondary)
                                    if !store.copies(for: movie).isEmpty { Label("Already owned", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.tint) }
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            .overlay { if results.isEmpty { ContentUnavailableView.search(text: store.searchQuery) } }
            .navigationTitle("Search")
            .searchable(text: $store.searchQuery, prompt: "Title or release year")
            .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
        }
    }
}
