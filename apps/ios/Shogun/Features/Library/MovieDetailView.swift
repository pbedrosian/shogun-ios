import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var store: CatalogStore
    @Environment(\.collection) private var collection
    @State private var draft: PersonalMovieState?
    @State private var saving = false
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
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
                    Text(movie.title).font(ShogunTheme.Typography.detailTitle)
                    Text(movie.releaseYearText).font(ShogunTheme.Typography.viewIcon).foregroundStyle(
                        .secondary)
                    Text(movie.synopsis).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.control) {
                        Label("Owned copies", systemImage: "opticaldisc").font(
                            ShogunTheme.Typography.headline)
                        if store.copies(for: movie).isEmpty {
                            Text("Not in your libraries yet.").foregroundStyle(.secondary)
                        }
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty {
                                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.tight) {
                                    Text(library.name).font(ShogunTheme.Typography.emphasizedBody)
                                    Text(copies.map { $0.format.rawValue }.joined(separator: " · "))
                                        .font(ShogunTheme.Typography.body).foregroundStyle(
                                            .secondary)
                                    Text("\(copies.count) \(copies.count == 1 ? "copy" : "copies")")
                                        .font(ShogunTheme.Typography.caption).foregroundStyle(
                                            .secondary)
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
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Clear rating") { edit(clearRating: true) }.font(
                                    ShogunTheme.Typography.caption)
                            }
                        } else {
                            Text("Not rated").font(ShogunTheme.Typography.caption).foregroundStyle(
                                .secondary)
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
                        .font(ShogunTheme.Typography.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Demo changes stay in memory and reset when the app restarts.").font(
                        ShogunTheme.Typography.footnote
                    ).foregroundStyle(.secondary)
                }
            }.padding().disabled(saving)
        }.accessibilityIdentifier("movie.detail").shogunCanvas().navigationTitle("Movie")
            .navigationBarTitleDisplayMode(.inline)
    }
}
