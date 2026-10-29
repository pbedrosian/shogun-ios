import SwiftUI

struct CatalogDetailView: View {
    @StateObject private var detail: CatalogDetailStore
    @ObservedObject var collection: CollectionStore
    init(movie: CatalogMovie, service: any MovieDiscoveryServicing, collection: CollectionStore) {
        _detail = StateObject(wrappedValue: CatalogDetailStore(movie: movie, service: service))
        self.collection = collection
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                CatalogPosterView(movie: detail.movie).frame(
                    maxWidth: ShogunTheme.Size.detailPosterWidth
                )
                .frame(maxWidth: .infinity)
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
    }
}
