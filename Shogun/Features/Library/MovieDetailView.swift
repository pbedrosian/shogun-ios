import SwiftUI

struct MovieDetailView: View {
    @EnvironmentObject private var store: CatalogStore
    let movie: Movie
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PosterView(movie: movie).frame(maxWidth: 230).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text(movie.title).font(.largeTitle.bold())
                    Text(String(movie.year)).font(.title3).foregroundStyle(.secondary)
                    Text(movie.synopsis).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Owned copies", systemImage: "opticaldisc").font(.headline)
                        if store.copies(for: movie).isEmpty { Text("Not in your libraries yet.").foregroundStyle(.secondary) }
                        ForEach(store.libraries) { library in
                            let copies = store.copies(for: movie, libraryID: library.id)
                            if !copies.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(library.name).font(.subheadline.weight(.semibold))
                                    Text(copies.map { $0.format.rawValue }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                                    Text("\(copies.count) \(copies.count == 1 ? "copy" : "copies")").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your viewing diary").font(.headline)
                        Toggle("Watched", isOn: Binding(get: { store.state(for: movie).watched }, set: { store.update(movie, watched: $0) }))
                        Text("Personal rating").font(.subheadline)
                        HStack {
                            ForEach(1...5, id: \.self) { rating in
                                Button { store.update(movie, rating: rating) } label: {
                                    Image(systemName: rating <= (store.state(for: movie).rating ?? 0) ? "star.fill" : "star").font(.title2).frame(minWidth: 36, minHeight: 44)
                                }.buttonStyle(.plain).foregroundStyle(.orange).accessibilityLabel("Rate \(rating) of 5 stars").accessibilityAddTraits(store.state(for: movie).rating == rating ? .isSelected : [])
                            }
                        }
                        if let rating = store.state(for: movie).rating {
                            HStack { Text("\(rating) of 5 stars").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Clear rating") { store.update(movie, clearRating: true) }.font(.caption) }
                        } else { Text("Not rated").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text("Demo changes stay in memory and reset when the app restarts.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Movie").navigationBarTitleDisplayMode(.inline)
    }
}
