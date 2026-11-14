import SwiftUI

struct CatalogDetailView: View {
    @StateObject private var detail: CatalogDetailStore
    @ObservedObject var collection: CollectionStore
    private let service: any MovieDiscoveryServicing
    @State private var addingMovie: CatalogMovie?
    init(movie: CatalogMovie, service: any MovieDiscoveryServicing, collection: CollectionStore) {
        _detail = StateObject(wrappedValue: CatalogDetailStore(movie: movie, service: service))
        self.collection = collection
        self.service = service
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                CatalogPosterView(movie: detail.movie).frame(
                    maxWidth: ShogunTheme.Size.detailPosterWidth
                )
                .frame(maxWidth: .infinity)
                Button(
                    collection.catalog?.ownedMovie(tmdbID: detail.movie.id) == nil
                        ? "Add to library" : "Add another copy"
                ) { addingMovie = detail.movie }
                .disabled(collection.catalog?.writableLibraries.isEmpty != false)
                .accessibilityIdentifier("discovery.addToLibrary")
                if collection.catalog?.writableLibraries.isEmpty != false, !collection.isBusy {
                    Text("You need an owner or editor library to add a movie.")
                        .font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
                }
                MovieOverviewView(
                    title: detail.movie.title, year: detail.movie.releaseYearText,
                    synopsis: detail.movie.synopsis)
                if detail.isLoading { ProgressView("Loading movie details…") }
                if let error = detail.error {
                    Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                        "discovery.detailError")
                    Button("Retry details") { Task { await detail.load() } }
                        .accessibilityIdentifier("discovery.detailRetry")
                }
                if let director = detail.movie.director {
                    LabeledContent("Director", value: director).accessibilityIdentifier(
                        "discovery.director")
                }
                if let runtime = detail.movie.runtimeMinutes {
                    LabeledContent("Runtime", value: "\(runtime) minutes").accessibilityIdentifier(
                        "discovery.runtime")
                }
                if !detail.movie.genres.isEmpty {
                    Text(detail.movie.genres.joined(separator: " · ")).foregroundStyle(
                        ShogunTheme.muted)
                }
                if let owned = collection.catalog?.ownedMovie(tmdbID: detail.movie.id),
                    let catalog = collection.catalog
                {
                    NavigationLink("View your owned copies and diary") {
                        MovieDetailView(movie: owned).environmentObject(catalog)
                    }.accessibilityIdentifier("discovery.owned")
                }
            }.padding()
        }.shogunCanvas().navigationTitle("Movie").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("discovery.detail")
            .task { await detail.load() }
            .sheet(item: $addingMovie) { movie in
                SearchAddMovieSheet(movie: movie, service: service, collection: collection)
            }
    }
}

struct SearchAddMovieSheet: View {
    let movie: CatalogMovie
    let service: any MovieDiscoveryServicing
    @ObservedObject var collection: CollectionStore
    var body: some View {
        if let catalog = collection.catalog {
            ConnectedAddMovieSheet(
                discovery: service, initialMovie: movie,
                preferredLibraryID: collection.defaultLibraryID
            )
            .environmentObject(catalog).environment(\.collection, collection)
        } else {
            ContentUnavailableView(
                "Collection unavailable", systemImage: "film.stack",
                description: Text("Close this sheet and refresh your collection."))
        }
    }
}
