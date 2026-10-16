import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: CatalogStore
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.selectedLibrary.isShared ? "SHARED COLLECTION" : "YOUR COLLECTION").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                            Text(store.selectedLibrary.name).font(.title2.bold())
                        }
                        Spacer()
                        Image(systemName: store.selectedLibrary.isShared ? "person.2.fill" : "person.fill").font(.title2).foregroundStyle(.tint)
                    }
                    Picker("Library", selection: $store.selectedLibraryID) {
                        ForEach(store.libraries) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
                    let movies = store.movies(in: store.selectedLibraryID).filter { store.libraryQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(store.libraryQuery) }
                    Text("\(movies.count) movies · \(store.copies.filter { $0.libraryID == store.selectedLibraryID }.count) copies").font(.subheadline).foregroundStyle(.secondary)
                    if movies.isEmpty {
                        ContentUnavailableView.search(text: store.libraryQuery)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(movies) { movie in NavigationLink(value: movie) { MovieCard(movie: movie) }.buttonStyle(.plain) }
                        }
                    }
                }.padding()
            }
            .navigationTitle("Library")
            .searchable(text: $store.libraryQuery, prompt: "Search this library")
            .navigationDestination(for: Movie.self) { MovieDetailView(movie: $0) }
        }
    }
}
