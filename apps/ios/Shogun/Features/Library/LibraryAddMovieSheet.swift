import SwiftUI

/// Adds a copy using existing metadata identity; catalog/manual metadata creation is separate.
struct LibraryAddMovieSheet: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    @State private var requestID = UUID().uuidString
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draft = AddMovieDraft()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        collection == nil
                            ? "Choose from the local sample catalog."
                            : "Choose from your available movie catalog."
                    ).foregroundStyle(ShogunTheme.muted)
                    Picker("Library", selection: $draft.libraryID) {
                        ForEach(store.writableLibraries) { Text($0.name).tag($0.id) }
                    }
                    Picker("Movie", selection: $draft.movieID) {
                        ForEach(store.movies) {
                            Text("\($0.title) (\($0.releaseYearText))").tag($0.id)
                        }
                    }
                    Picker("Format", selection: $draft.format) {
                        ForEach(MovieFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                if let movie = store.movies.first(where: { $0.id == draft.movieID }),
                    !store.copies(for: movie).isEmpty
                {
                    Section {
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty {
                                LabeledContent(
                                    library.name,
                                    value: copies.map { $0.format.rawValue }.joined(separator: ", ")
                                )
                            }
                        }
                        Text("Saving adds another copy and keeps the existing movie record.").font(
                            ShogunTheme.Typography.footnote)
                    } header: {
                        Text("Already owned").accessibilityIdentifier("addMovie.alreadyOwned")
                    }
                }
                if let collection {
                    CollectionFeedback(store: collection)
                } else {
                    Section {
                        Text("Local demo only. Changes reset when Shogun restarts.").font(
                            ShogunTheme.Typography.footnote
                        ).foregroundStyle(ShogunTheme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden).background(ShogunTheme.canvas)
            .navigationTitle("Add Movie").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let movie = store.movies.first(where: { $0.id == draft.movieID })
                        else { return }
                        if let collection {
                            saving = true
                            Task {
                                if await collection.saveCopy(
                                    id: requestID, movie: movie, format: draft.format,
                                    libraryID: draft.libraryID)
                                {
                                    dismiss()
                                }
                                saving = false
                            }
                        } else if store.addCopy(
                            movie: movie, format: draft.format, libraryID: draft.libraryID)
                        {
                            dismiss()
                        }
                    }.disabled(
                        saving || store.movies.isEmpty
                            || !store.writableLibraries.contains { $0.id == draft.libraryID })
                }
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .onChange(of: draft.libraryID) { _, _ in requestID = UUID().uuidString }
        .onChange(of: draft.movieID) { _, _ in requestID = UUID().uuidString }
        .onChange(of: draft.format) { _, _ in requestID = UUID().uuidString }
        .onAppear {
            draft.movieID = store.movies.first?.id ?? ""
            draft.libraryID =
                store.writableLibraries.first(where: { $0.id == store.selectedLibraryID })?.id
                ?? store.writableLibraries.first?.id ?? ""
        }
        .presentationDragIndicator(.visible)
    }
}
private final class AddMovieDraft: ObservableObject {
    @Published var libraryID = ""
    @Published var movieID = ""
    @Published var format = MovieFormat.bluRay
}
