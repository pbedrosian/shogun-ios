import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.dynamicTypeSize) private var typeSize
    private var columnCount: Int { typeSize.isAccessibilitySize ? 2 : store.libraryColumns }
    private var movies: [Movie] { store.libraryResults }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
                        Text("SHOGUN").shogunBrand()
                        HStack(alignment: .center, spacing: ShogunTheme.Spacing.tight) {
                            Text(store.selectedLibrary.name).font(ShogunTheme.Typography.title).frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                Section("View Options") {
                                    Button { withAnimation { store.zoomIn() } } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }.disabled(store.libraryColumns <= 2 || typeSize.isAccessibilitySize)
                                    Button { withAnimation { store.zoomOut() } } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }.disabled(store.libraryColumns >= 5 || typeSize.isAccessibilitySize)
                                }
                                Text(typeSize.isAccessibilitySize ? "2 columns for larger text" : "\(store.libraryColumns) posters per row")
                            } label: {
                                ShogunIcon(systemName: "line.3.horizontal.decrease", font: ShogunTheme.Typography.viewIcon)
                            }.accessibilityLabel("Library view options")
                            Button { store.showingAddMovie = true } label: {
                                ShogunIcon(systemName: "plus")
                            }.accessibilityLabel("Add movie").disabled(store.writableLibraries.isEmpty)
                        }

                    }
                    Menu {
                        Picker("Library", selection: $store.selectedLibraryID) {
                            ForEach(store.libraries) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        HStack {
                            Image(systemName: store.selectedLibrary.isShared ? "person.2" : "person")
                            Text(store.selectedLibrary.name).fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "chevron.down").font(ShogunTheme.Typography.disclosure)
                        }.font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.ink).shogunSurface(padding: ShogunTheme.Spacing.selector)
                    }.accessibilityLabel("Select library, \(store.selectedLibrary.name)")
                    HStack(spacing: ShogunTheme.Spacing.medium) {
                        Image(systemName: "magnifyingglass").foregroundStyle(ShogunTheme.muted)
                        TextField("Search this library", text: $store.libraryQuery).font(ShogunTheme.Typography.body).autocorrectionDisabled()
                        if !store.libraryQuery.isEmpty {
                            Button { store.libraryQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search")
                        }
                    }.shogunSurface()
                    Text("\(movies.count) \(movies.count == 1 ? "movie" : "movies")")
                        .font(ShogunTheme.Typography.caption).foregroundStyle(ShogunTheme.muted)
                    if movies.isEmpty {
                        ContentUnavailableView.search(text: store.libraryQuery)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ShogunTheme.Spacing.small, alignment: .top), count: columnCount), alignment: .leading, spacing: ShogunTheme.Spacing.regular) {
                            ForEach(movies) { movie in
                                NavigationLink(value: movie) {
                                    MovieCard(movie: movie, compact: columnCount >= 4, formats: MovieFormat.allCases.filter { format in store.copies(for: movie, libraryID: store.selectedLibraryID).contains { $0.format == format } }.map(\.rawValue).joined(separator: " · "))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.horizontal, ShogunTheme.Spacing.screen).padding(.top, ShogunTheme.Spacing.regular).padding(.bottom, ShogunTheme.Spacing.large)
            }
            .shogunCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie).toolbar(.visible, for: .navigationBar)
            }
            .sheet(isPresented: $store.showingAddMovie) { LibraryAddMovieSheet() }
        }
    }
}

/// Minimal local add destination; full catalog/manual-entry flow is a later change.
private struct LibraryAddMovieSheet: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = AddMovieDraft()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Choose from the local sample catalog.").foregroundStyle(ShogunTheme.muted)
                    Picker("Library", selection: $draft.libraryID) {
                        ForEach(store.writableLibraries) { Text($0.name).tag($0.id) }
                    }
                    Picker("Movie", selection: $draft.movieID) {
                        ForEach(store.movies) { Text("\($0.title) (\($0.year))").tag($0.id) }
                    }
                    Picker("Format", selection: $draft.format) {
                        ForEach(MovieFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if let movie = store.movies.first(where: { $0.id == draft.movieID }), !store.copies(for: movie).isEmpty {
                    Section("Already owned") {
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty { LabeledContent(library.name, value: copies.map { $0.format.rawValue }.joined(separator: ", ")) }
                        }
                        Text("Saving adds another copy and keeps the existing movie record.").font(ShogunTheme.Typography.footnote)
                    }
                }
                Section { Text("Local demo only. Changes reset when Shogun restarts.").font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted) }
            }
            .scrollContentBackground(.hidden).background(ShogunTheme.canvas)
            .navigationTitle("Add Movie").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let movie = store.movies.first(where: { $0.id == draft.movieID }), store.addCopy(movie: movie, format: draft.format, libraryID: draft.libraryID) { dismiss() }
                    }.disabled(!store.writableLibraries.contains { $0.id == draft.libraryID })
                }
            }
        }
        .onAppear { draft.libraryID = store.writableLibraries.first(where: { $0.id == store.selectedLibraryID })?.id ?? store.writableLibraries.first?.id ?? "" }
        .presentationDragIndicator(.visible)
    }
}
private final class AddMovieDraft: ObservableObject {
    @Published var libraryID = ""
    @Published var movieID = MockCatalog.movies[0].id
    @Published var format = MovieFormat.bluRay
}
