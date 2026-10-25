import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var store: CatalogStore
    let movie: Movie
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                PosterView(movie: movie).frame(maxWidth: ShogunTheme.Size.detailPosterWidth).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
                    Text(movie.title).font(ShogunTheme.Typography.detailTitle)
                    Text(String(movie.year)).font(ShogunTheme.Typography.viewIcon).foregroundStyle(.secondary)
                    Text(movie.synopsis).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.control) {
                        Label("Owned copies", systemImage: "opticaldisc").font(ShogunTheme.Typography.headline)
                        if store.copies(for: movie).isEmpty { Text("Not in your libraries yet.").foregroundStyle(.secondary) }
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty {
                                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.tight) {
                                    Text(library.name).font(ShogunTheme.Typography.emphasizedBody)
                                    Text(copies.map { $0.format.rawValue }.joined(separator: " · ")).font(ShogunTheme.Typography.body).foregroundStyle(.secondary)
                                    Text("\(copies.count) \(copies.count == 1 ? "copy" : "copies")").font(ShogunTheme.Typography.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.regular) {
                        Text("Your viewing diary").font(ShogunTheme.Typography.headline)
                        Toggle("Watched", isOn: Binding(get: { store.state(for: movie).watched }, set: { store.update(movie, watched: $0) }))
                        Text("Personal rating").font(ShogunTheme.Typography.body)
                        HStack {
                            ForEach(1...5, id: \.self) { rating in
                                Button { store.update(movie, rating: rating) } label: {
                                    Image(systemName: rating <= (store.state(for: movie).rating ?? 0) ? "star.fill" : "star")
                                }.buttonStyle(ShogunRatingButtonStyle()).accessibilityLabel("Rate \(rating) of 5 stars").accessibilityAddTraits(store.state(for: movie).rating == rating ? .isSelected : [])
                            }
                        }
                        if let rating = store.state(for: movie).rating {
                            HStack { Text("\(rating) of 5 stars").font(ShogunTheme.Typography.caption).foregroundStyle(.secondary); Spacer(); Button("Clear rating") { store.update(movie, clearRating: true) }.font(ShogunTheme.Typography.caption) }
                        } else { Text("Not rated").font(ShogunTheme.Typography.caption).foregroundStyle(.secondary) }
                    }
                }
                Text("Demo changes stay in memory and reset when the app restarts.").font(ShogunTheme.Typography.footnote).foregroundStyle(.secondary)
            }.padding()
        }.accessibilityIdentifier("movie.detail").shogunCanvas().navigationTitle("Movie").navigationBarTitleDisplayMode(.inline)
    }
}
