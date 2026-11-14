import SwiftUI

struct MovieCoverPicker: View {
    let movie: Movie
    let tmdbID: Int
    @ObservedObject var collection: CollectionStore
    var onChoose: ((MovieCoverSelection) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var covers: [MovieCover] = []
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0
    @State private var selected: MovieCover?
    @State private var useDefault = false
    @State private var saving = false
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: textSize.isAccessibilitySize ? 2 : 3)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ShogunTheme.Spacing.regular) {
                    Text(movie.title).font(ShogunTheme.Typography.headline)
                    Text(
                        onChoose == nil
                            ? "Your cover choice applies across your libraries."
                            : "Choose the cover to use when you save this movie."
                    )
                    .font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
                    Button {
                        selected = nil
                        useDefault = true
                    } label: {
                        Label(
                            "Use default cover",
                            systemImage: useDefault ? "checkmark.circle.fill" : "circle")
                    }.accessibilityIdentifier("cover.default")
                        .accessibilityAddTraits(useDefault ? .isSelected : [])
                    if loading {
                        ProgressView("Loading covers…").accessibilityIdentifier("cover.loading")
                    } else if let error {
                        Text(error).foregroundStyle(ShogunTheme.error)
                        Button("Try again") { retry += 1 }.accessibilityIdentifier("cover.retry")
                    } else if covers.isEmpty {
                        ContentUnavailableView(
                            "No alternate covers", systemImage: "photo",
                            description: Text("You can still use the default cover."))
                    } else {
                        LazyVGrid(columns: columns, spacing: ShogunTheme.Spacing.regular) {
                            ForEach(Array(covers.enumerated()), id: \.element.id) { index, cover in
                                Button {
                                    selected = cover
                                    useDefault = false
                                } label: {
                                    VStack {
                                        AsyncImage(url: cover.url) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            Rectangle().fill(ShogunTheme.surface)
                                                .overlay(Image(systemName: "photo"))
                                        }.aspectRatio(
                                            ShogunTheme.Size.posterAspect, contentMode: .fit)
                                        Image(
                                            systemName: isSelected(cover)
                                                ? "checkmark.circle.fill" : "circle")
                                    }
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(
                                        "Cover \(index + 1), \(cover.language ?? "no language"), \(cover.width) by \(cover.height) pixels"
                                    )
                                    .accessibilityAddTraits(isSelected(cover) ? .isSelected : [])
                                    .accessibilityIdentifier("cover.option.\(index)")
                            }
                        }
                    }
                    if onChoose == nil, let saveError = collection.error {
                        Text(saveError).foregroundStyle(ShogunTheme.error)
                            .accessibilityIdentifier("collection.error")
                    }
                    if saving { ProgressView("Saving cover…") }
                }.padding()
            }.shogunCanvas().navigationTitle("Change cover")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(saving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(onChoose == nil ? "Save" : "Use cover") {
                            if let onChoose {
                                if useDefault {
                                    onChoose(.defaultCover)
                                } else if let selected {
                                    onChoose(.poster(selected.path))
                                }
                                dismiss()
                            } else {
                                saving = true
                            }
                        }
                        .disabled(
                            saving || collection.isBusy || (!useDefault && selected == nil)
                        )
                        .accessibilityIdentifier("cover.save")
                    }
                }
                .disabled(saving)
                .task(id: retry) { await load() }
                .task(id: saving) {
                    guard saving else { return }
                    if await collection.setCover(
                        tmdbID: tmdbID, path: useDefault ? nil : selected?.path)
                    {
                        dismiss()
                    }
                    saving = false
                }
        }.interactiveDismissDisabled(saving)
    }
    private func isSelected(_ cover: MovieCover) -> Bool {
        !useDefault
            && (selected?.path == cover.path || (selected == nil && cover.url == movie.posterURL))
    }
    private func load() async {
        loading = true
        error = nil
        do {
            covers = try await collection.covers(tmdbID: tmdbID)
            loading = false
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = "Covers are unavailable. Check your connection and try again."
            loading = false
        }
    }
}
