import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinchStartingColumns: Int?
    @GestureState private var isPinching = false
    private var columnCount: Int { typeSize.isAccessibilitySize ? 2 : store.libraryColumns }
    private var movies: [Movie] { store.libraryResults }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.compact) {
                        Text("SHOGUN").shogunBrand()
                        HStack(alignment: .center, spacing: ShogunTheme.Spacing.tight) {
                            Text((store.selectedLibrary?.name ?? "Libraries")).font(
                                ShogunTheme.Typography.title
                            )
                            .lineLimit(2).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                Section("View Options") {
                                    Button {
                                        withAnimation { store.zoomIn() }
                                    } label: {
                                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                                    }.disabled(
                                        store.libraryColumns <= 2 || typeSize.isAccessibilitySize)
                                    Button {
                                        withAnimation { store.zoomOut() }
                                    } label: {
                                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                                    }.disabled(
                                        store.libraryColumns >= 5 || typeSize.isAccessibilitySize)
                                }
                                Text(
                                    typeSize.isAccessibilitySize
                                        ? "2 columns for larger text"
                                        : "\(store.libraryColumns) posters per row")
                            } label: {
                                ShogunIcon(
                                    systemName: "line.3.horizontal.decrease",
                                    font: ShogunTheme.Typography.viewIcon)
                            }.accessibilityLabel("Library view options")
                                .accessibilityIdentifier("library.viewOptions").accessibilityValue(
                                    "\(columnCount)")
                            if collection != nil {
                                Button {
                                    store.showingAddMovie = true
                                } label: {
                                    ShogunIcon(systemName: "plus")
                                }.accessibilityLabel("Add movie").disabled(
                                    store.writableLibraries.isEmpty)
                            }
                        }
                    }
                    Menu {
                        Picker("Library", selection: $store.selectedLibraryID) {
                            ForEach(store.libraries) {
                                Text($0.name).lineLimit(1).truncationMode(.tail).tag($0.id)
                            }
                        }
                    } label: {
                        HStack {
                            Image(
                                systemName: (store.selectedLibrary?.isShared ?? false)
                                    ? "person.2" : "person")
                            Text((store.selectedLibrary?.name ?? "Libraries")).fontWeight(.semibold)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer()
                            Image(systemName: "chevron.down").font(
                                ShogunTheme.Typography.disclosure)
                        }.font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.ink)
                            .shogunSurface(padding: ShogunTheme.Spacing.selector)
                    }.accessibilityLabel(
                        "Select library, \((store.selectedLibrary?.name ?? "Libraries"))"
                    ).accessibilityIdentifier("library.selector")
                    HStack(spacing: ShogunTheme.Spacing.medium) {
                        Image(systemName: "magnifyingglass").foregroundStyle(ShogunTheme.muted)
                        TextField("Search this library", text: $store.libraryQuery).font(
                            ShogunTheme.Typography.body
                        ).autocorrectionDisabled()
                        if !store.libraryQuery.isEmpty {
                            Button {
                                store.libraryQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }.accessibilityLabel("Clear search")
                        }
                    }.shogunSurface()
                    Text("\(movies.count) \(movies.count == 1 ? "movie" : "movies")")
                        .font(ShogunTheme.Typography.caption).foregroundStyle(ShogunTheme.muted)
                    if let collection {
                        CollectionFeedback(store: collection, showsRefreshButton: false)
                    }
                    if movies.isEmpty {
                        if store.libraryQuery.isEmpty {
                            ContentUnavailableView(
                                "No movies yet", systemImage: "film.stack",
                                description: Text("Add a copy from your available movie catalog."))
                        } else {
                            ContentUnavailableView.search(text: store.libraryQuery)
                        }
                    } else {
                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(
                                    .flexible(), spacing: ShogunTheme.Spacing.small, alignment: .top
                                ), count: columnCount), alignment: .leading,
                            spacing: ShogunTheme.Spacing.regular
                        ) {
                            ForEach(movies) { movie in
                                NavigationLink(value: movie) {
                                    MovieCard(
                                        movie: movie, compact: columnCount >= 4,
                                        formats: MovieFormat.allCases.filter { format in
                                            store.copies(
                                                for: movie, libraryID: store.selectedLibraryID
                                            ).contains { $0.format == format }
                                        }.map(\.rawValue).joined(separator: " · "))
                                }.buttonStyle(.plain).disabled(isPinching).accessibilityIdentifier(
                                    "library.movie.\(movie.id)")
                            }
                        }

                    }
                }.padding(.horizontal, ShogunTheme.Spacing.screen).padding(
                    .top, ShogunTheme.Spacing.regular
                ).padding(.bottom, ShogunTheme.Spacing.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("library.scroll")
            .contentShape(Rectangle())
            .highPriorityGesture(
                MagnifyGesture(minimumScaleDelta: 0.01)
                    .updating($isPinching) { _, active, _ in active = true }
                    .onChanged { value in
                        guard !typeSize.isAccessibilitySize else { return }
                        let startingColumns = pinchStartingColumns ?? store.libraryColumns
                        pinchStartingColumns = startingColumns
                        withAnimation(
                            reduceMotion
                                ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.9)
                        ) {
                            store.updateLibraryPinch(
                                magnification: Double(value.magnification),
                                startingColumns: startingColumns)
                        }
                    }
                    .onEnded { _ in pinchStartingColumns = nil },
                including: typeSize.isAccessibilitySize ? .subviews : .all
            )
            .onChange(of: isPinching) { _, active in
                if !active { pinchStartingColumns = nil }
            }
            .refreshable { await collection?.refresh() }
            .shogunCanvas()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Movie.self) { movie in
                MovieDetailView(movie: movie).toolbar(.visible, for: .navigationBar)
            }
            .sheet(isPresented: $store.showingAddMovie) { LibraryAddMovieSheet() }
        }
    }
}
