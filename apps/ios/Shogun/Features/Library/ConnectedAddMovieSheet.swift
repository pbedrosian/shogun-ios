import SwiftUI

struct ConnectedAddMovieSheet: View {
    @EnvironmentObject private var catalog: CatalogStore
    @Environment(\.collection) private var collection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search: CatalogSearchStore
    @StateObject private var draft: MovieAddDraft
    @State private var selection: CatalogMovie?
    @State private var saving = false
    @State private var year = ""
    @State private var runtime = ""
    @State private var genres = ""
    private enum Field: Hashable { case title, year, director, synopsis, runtime, genres, poster }
    @FocusState private var editing: Field?
    @FocusState private var searching: Bool
    init(discovery: any MovieDiscoveryServicing) {
        _search = StateObject(wrappedValue: CatalogSearchStore(service: discovery))
        _draft = StateObject(wrappedValue: MovieAddDraft(discovery: discovery))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Find a movie") {
                    if draft.manual || selection != nil {
                        Text(draft.metadata.title).font(ShogunTheme.Typography.headline)
                        Button("Choose a different movie") {
                            selection = nil
                            draft.resetSelection()
                        }
                    } else {
                        TextField("Search by title", text: $search.query)
                            .accessibilityIdentifier("addMovie.search").focused($searching)
                            .submitLabel(.search)
                            .onSubmit {
                                searching = false
                                search.search(immediately: true)
                            }
                            .onChange(of: search.query) { _, _ in search.search() }
                        if search.phase == .loading { ProgressView("Searching movies…") }
                        ForEach(search.results) { movie in
                            Button {
                                searching = false
                                selection = movie
                            } label: {
                                MovieResultRow(
                                    title: movie.title, year: movie.releaseYearText,
                                    isOwned: catalog.ownedMovie(tmdbID: movie.id) != nil,
                                    artwork: CatalogPosterView(movie: movie))
                            }.accessibilityIdentifier("addMovie.result.\(movie.id)")
                        }
                        if search.phase == .empty {
                            Text("No movies found. You can enter one manually.")
                        }
                        if let error = search.error {
                            Text(error).foregroundStyle(.red)
                            Button("Retry search", action: search.retry)
                        }
                        if search.canLoadMore {
                            Button("Load more movies", action: search.loadMore)
                        }
                        if search.phase == .loadingMore { ProgressView("Loading more movies…") }
                        Button("Enter manually") {
                            searching = false
                            selection = nil
                            draft.enterManually(title: search.query)
                            year = ""
                            runtime = ""
                            genres = ""
                        }.accessibilityIdentifier("addMovie.manual")
                    }
                }
                if draft.manual || draft.providerID != nil {
                    metadataFields
                    if draft.loading { ProgressView("Loading movie details…") }
                    if let error = draft.error {
                        Text(error).foregroundStyle(.red)
                        Button("Retry details") {
                            if let selection {
                                Task {
                                    await draft.select(selection)
                                    syncNumbers()
                                }
                            }
                        }
                    }
                }
                Section("Copies") {
                    Picker("Library", selection: $draft.libraryID) {
                        ForEach(catalog.writableLibraries) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("addMovie.library")
                    if catalog.writableLibraries.isEmpty {
                        Text("You need an owner or editor library to save a movie.")
                    }
                    ForEach(MovieFormat.allCases) { format in
                        Stepper(
                            "\(format.rawValue): \(draft.quantities[format] ?? 0)",
                            value: Binding(
                                get: { draft.quantities[format] ?? 0 },
                                set: { draft.quantities[format] = $0 }), in: 0...99
                        )
                        .accessibilityIdentifier("addMovie.quantity.\(format.id)")
                    }
                    Text(
                        "\(draft.formats.count) \(draft.formats.count == 1 ? "copy" : "copies") total (maximum 99)."
                    )
                    .font(ShogunTheme.Typography.footnote)
                    if let providerID = draft.providerID,
                        let owned = catalog.ownedMovie(tmdbID: providerID)
                    {
                        Text(
                            "Already owned: \(catalog.copies(for: owned).count) copies. Saving adds more copies."
                        )
                        .accessibilityIdentifier("addMovie.alreadyOwned")
                    }
                }

            }.refreshable { await collection?.refresh() }.scrollDismissesKeyboard(.immediately)
                .safeAreaInset(edge: .bottom) {
                    if let collection, collection.error != nil || collection.isBusy {
                        CollectionFeedback(store: collection).font(ShogunTheme.Typography.footnote)
                            .padding().background(ShogunTheme.canvas)
                    }
                }.shogunListCanvas().navigationTitle("Add Movie").navigationBarTitleDisplayMode(
                    .inline
                )
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            finishEditing()
                        }
                        .accessibilityIdentifier("addMovie.keyboardDone")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            finishEditing()
                            let intent = draft.saveIntent()
                            saving = true
                            Task {
                                if await collection?.addMovie(intent) == true { dismiss() }
                                saving = false
                            }
                        }.disabled(
                            saving || !draft.canSave || !validNumbers
                                || !catalog.writableLibraries.contains { $0.id == draft.libraryID }
                        )
                        .accessibilityIdentifier("addMovie.save")
                    }
                }
        }.disabled(saving).interactiveDismissDisabled(saving)
            .task(id: selection?.id) {
                if let selection {
                    await draft.select(selection)
                    syncNumbers()
                }
            }
            .onAppear {
                draft.libraryID =
                    catalog.writableLibraries.first(where: {
                        $0.id == catalog.selectedLibraryID
                    })?.id ?? catalog.writableLibraries.first?.id ?? ""
            }
            .onDisappear { search.invalidate() }
    }
    private func finishEditing() {
        editing = nil
        searching = false
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach { $0.endEditing(true) }
        }
    }
    private var validNumbers: Bool {
        (year.isEmpty || Int(year).map { (1870...9999).contains($0) } == true)
            && (runtime.isEmpty || Int(runtime).map { (1...10000).contains($0) } == true)
    }
    private func syncNumbers() {
        year = draft.metadata.year.map(String.init) ?? ""
        runtime = draft.metadata.runtimeMinutes.map(String.init) ?? ""
        genres = draft.metadata.genres.joined(separator: ", ")
    }
    private var metadataFields: some View {
        Section(draft.manual ? "Movie information" : "Selected movie") {
            Group {
                TextField("Title", text: $draft.metadata.title).accessibilityIdentifier(
                    "addMovie.title"
                ).focused($editing, equals: .title)
                TextField("Year (optional)", text: $year).accessibilityIdentifier("addMovie.year")
                    .focused($editing, equals: .year)
                    .keyboardType(.numberPad)
                    .onChange(of: year) { _, value in draft.metadata.year = Int(value) }
                TextField("Director", text: $draft.metadata.director).accessibilityIdentifier(
                    "addMovie.director"
                ).focused($editing, equals: .director)
                TextField("Synopsis", text: $draft.metadata.synopsis, axis: .vertical)
                    .accessibilityIdentifier("addMovie.synopsis").focused(
                        $editing, equals: .synopsis)
                TextField("Runtime in minutes (optional)", text: $runtime).accessibilityIdentifier(
                    "addMovie.runtime"
                ).focused($editing, equals: .runtime).keyboardType(.numberPad)
                    .onChange(of: runtime) { _, value in draft.metadata.runtimeMinutes = Int(value)
                    }
                TextField("Genres, separated by commas", text: $genres).accessibilityIdentifier(
                    "addMovie.genres"
                ).focused($editing, equals: .genres)
                    .onChange(of: genres) { _, value in
                        draft.metadata.genres = value.split(separator: ",").map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }.filter { !$0.isEmpty }
                    }
                TextField("Poster URL (HTTPS, optional)", text: $draft.metadata.posterURL)
                    .accessibilityIdentifier("addMovie.poster").focused($editing, equals: .poster)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.disabled(!draft.manual)
            if !validNumbers {
                Text("Enter a valid year and positive runtime.").foregroundStyle(.red)
            }
            if !draft.metadata.isValid {
                Text("Check the movie information before saving.").foregroundStyle(.red)
            }
        }
    }
}
