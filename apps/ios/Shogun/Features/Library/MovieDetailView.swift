import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    @State private var draft: PersonalMovieState?
    @State private var saving = false
    @State private var editingLibrary: MovieLibrary?
    let movie: Movie
    private var diary: PersonalMovieState { draft ?? store.state(for: movie) }
    private func edit(watched: Bool? = nil, rating: Int? = nil, clearRating: Bool = false) {
        if collection == nil {
            store.update(movie, watched: watched, rating: rating, clearRating: clearRating)
        } else {
            var value = diary
            if let watched { value.watched = watched }
            if clearRating { value.rating = nil } else if let rating { value.rating = rating }
            draft = value
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                PosterView(movie: movie).frame(maxWidth: ShogunTheme.Size.detailPosterWidth).frame(
                    maxWidth: .infinity)
                MovieOverviewView(
                    title: movie.title, year: movie.releaseYearText, synopsis: movie.synopsis)
                if let director = movie.director, !director.isEmpty {
                    LabeledContent("Director", value: director).accessibilityIdentifier(
                        "movie.director"
                    )
                    .accessibilityValue(director)
                }
                if let runtime = movie.runtimeMinutes {
                    LabeledContent("Runtime", value: "\(runtime) min").accessibilityIdentifier(
                        "movie.runtime")
                }
                if !movie.genres.isEmpty {
                    Text(movie.genres.joined(separator: " · ")).foregroundStyle(ShogunTheme.muted)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.control) {
                        Label("Owned copies", systemImage: "opticaldisc").font(
                            ShogunTheme.Typography.headline)
                        if store.copies(for: movie).isEmpty {
                            Text("Not in your libraries yet.").foregroundStyle(ShogunTheme.muted)
                        }
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty {
                                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.tight) {
                                    Text(library.name).font(ShogunTheme.Typography.emphasizedBody)
                                    Text(copies.map { $0.format.rawValue }.joined(separator: " · "))
                                        .font(ShogunTheme.Typography.body).foregroundStyle(
                                            ShogunTheme.muted)
                                    if collection != nil,
                                        store.writableLibraries.contains(where: {
                                            $0.id == library.id
                                        })
                                    {
                                        Button("Edit copies") { editingLibrary = library }
                                            .accessibilityIdentifier(
                                                "movie.editCopies.\(library.id)")
                                    }
                                    Text("\(copies.count) \(copies.count == 1 ? "copy" : "copies")")
                                        .font(ShogunTheme.Typography.caption).foregroundStyle(
                                            ShogunTheme.muted)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.regular) {
                        Text("Your viewing diary").font(ShogunTheme.Typography.headline)
                        Toggle(
                            "Watched",
                            isOn: Binding(get: { diary.watched }, set: { edit(watched: $0) }))
                        Text("Personal rating").font(ShogunTheme.Typography.body)
                        HStack {
                            ForEach(1...5, id: \.self) { rating in
                                Button {
                                    edit(rating: rating)
                                } label: {
                                    Image(
                                        systemName: rating <= (diary.rating ?? 0)
                                            ? "star.fill" : "star")
                                }.buttonStyle(ShogunRatingButtonStyle()).accessibilityLabel(
                                    "Rate \(rating) of 5 stars"
                                ).accessibilityAddTraits(diary.rating == rating ? .isSelected : [])
                            }
                        }
                        if let rating = diary.rating {
                            HStack {
                                Text("\(rating) of 5 stars").font(ShogunTheme.Typography.caption)
                                    .foregroundStyle(ShogunTheme.muted)
                                Spacer()
                                Button("Clear rating") { edit(clearRating: true) }.font(
                                    ShogunTheme.Typography.caption)
                            }
                        } else {
                            Text("Not rated").font(ShogunTheme.Typography.caption).foregroundStyle(
                                ShogunTheme.muted)
                        }
                    }
                }
                if let collection {
                    if draft != nil {
                        Button("Save diary") {
                            guard let draft else { return }
                            saving = true
                            Task {
                                if await collection.saveDiary(draft) { self.draft = nil }
                                saving = false
                            }
                        }.disabled(saving).accessibilityIdentifier("collection.saveDiary")
                    }
                    CollectionFeedback(store: collection)
                    Text("Changes are saved online. Refresh to see changes from another device.")
                        .font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
                } else {
                    Text("Demo changes stay in memory and reset when the app restarts.").font(
                        ShogunTheme.Typography.footnote
                    ).foregroundStyle(ShogunTheme.muted)
                }
            }.padding().disabled(saving)
        }.sheet(item: $editingLibrary) { library in
            EditCopiesSheet(
                movie: movie, library: library,
                copies: store.copies(for: movie, libraryID: library.id))
        }.accessibilityIdentifier("movie.detail").shogunCanvas().navigationTitle("Movie")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditCopiesSheet: View {
    let movie: Movie
    let library: MovieLibrary
    let copies: [OwnedCopy]
    @Environment(\.collection) private var collection
    @Environment(\.dismiss) private var dismiss
    @State private var expected: [OwnedCopy] = []
    @State private var quantities: [MovieFormat: Int] = [:]
    @State private var saving = false
    private var formats: [MovieFormat] {
        MovieFormat.allCases.flatMap {
            Array(repeating: $0, count: max(0, quantities[$0] ?? 0))
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Text(movie.title)
                        Text(library.name).foregroundStyle(ShogunTheme.muted)
                    }
                    Section("Copies") {
                        ForEach(MovieFormat.allCases) { format in
                            Stepper(
                                "\(format.rawValue): \(quantities[format] ?? 0)",
                                value: Binding(
                                    get: { quantities[format] ?? 0 },
                                    set: { quantities[format] = $0 }),
                                in: 0...max(99, copies.count)
                            )
                            .accessibilityIdentifier("editCopies.\(format.id)")
                        }
                        Text(
                            "\(formats.count) copies total (maximum 99). Zero removes this movie from this library."
                        )
                        .font(ShogunTheme.Typography.footnote)
                    }
                    if let collection { CollectionFeedback(store: collection) }

                }.listRowBackground(ShogunTheme.surface)
            }.shogunListCanvas().navigationTitle("Edit copies").navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            if await collection?.editCopies(
                                libraryID: library.id, movieID: movie.id, expected: expected,
                                formats: formats) == true
                            {
                                dismiss()
                            }
                            saving = false
                        }
                    }.disabled(saving || formats.count > 99).accessibilityIdentifier(
                        "editCopies.save")
                }
            }
        }.disabled(saving).interactiveDismissDisabled(saving)
            .onAppear {
                expected = copies
                quantities = Dictionary(grouping: copies, by: \.format).mapValues(\.count)
            }
    }
}
