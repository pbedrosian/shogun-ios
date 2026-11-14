import SwiftUI

struct CatalogSearchView: View {
    @ObservedObject var search: CatalogSearchStore
    @ObservedObject var collection: CollectionStore
    let service: any MovieDiscoveryServicing
    @State private var addingMovie: CatalogMovie?
    private var canAdd: Bool { collection.catalog?.writableLibraries.isEmpty == false }
    var body: some View {
        NavigationStack {
            List {
                Group {
                    ForEach(search.results) { movie in
                        HStack {
                            NavigationLink(value: movie) {
                                MovieResultRow(
                                    title: movie.title, year: movie.releaseYearText,
                                    isOwned: collection.catalog?.ownedMovie(tmdbID: movie.id)
                                        != nil,
                                    artwork: CatalogPosterView(
                                        movie: movie,
                                        preferredURL: collection.catalog?.movies.first {
                                            $0.tmdbID == movie.id
                                        }?.posterURL))
                            }.accessibilityIdentifier("discovery.movie.\(movie.id)")
                            Button {
                                addingMovie = movie
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(ShogunTheme.Typography.viewIcon)
                            }.buttonStyle(.borderless).disabled(!canAdd)
                                .accessibilityLabel(
                                    collection.catalog?.ownedMovie(tmdbID: movie.id) == nil
                                        ? "Add \(movie.title) to library"
                                        : "Add another copy of \(movie.title)"
                                )
                                .accessibilityHint(
                                    "Choose a library, format and quantity before saving."
                                )
                                .accessibilityIdentifier("discovery.add.\(movie.id)")
                        }
                    }
                    if !search.results.isEmpty, !canAdd, !collection.isBusy {
                        Text("You need an owner or editor library to add a movie.")
                            .font(ShogunTheme.Typography.footnote).foregroundStyle(
                                ShogunTheme.muted
                            )
                            .accessibilityIdentifier("discovery.noWritableLibrary")
                    }
                    if let error = search.error {
                        Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                            "discovery.error")
                        Button("Try again", action: search.retry).accessibilityIdentifier(
                            "discovery.retry")
                    } else if search.canLoadMore {
                        Button("Load more movies", action: search.loadMore).accessibilityIdentifier(
                            "discovery.more")
                    }
                    if search.phase == .loadingMore { ProgressView("Loading more movies…") }

                }.listRowBackground(ShogunTheme.surface)
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
            .sheet(item: $addingMovie) { movie in
                SearchAddMovieSheet(movie: movie, service: service, collection: collection)
            }
        }
    }
}
