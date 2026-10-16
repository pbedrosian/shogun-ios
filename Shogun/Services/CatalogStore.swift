import SwiftUI

final class CatalogStore: ObservableObject {
    let movies = MockCatalog.movies
    @Published private(set) var copies = MockCatalog.copies
    @Published var libraryColumns = 3
    @Published var showingAddMovie = false
    @Published var libraryQuery = ""
    @Published var searchQuery = ""
    @Published var selectedLibraryID = "personal"
    @Published private var personalStates: [PersonalMovieState] = [PersonalMovieState(userID: MockCatalog.userID, movieID: "arrival-2016", watched: true, rating: 5)]
    var libraries: [MovieLibrary] {
        MockCatalog.libraries.filter { library in MockCatalog.memberships.contains { $0.userID == MockCatalog.userID && $0.libraryID == library.id } }
    }
    var selectedLibrary: MovieLibrary { libraries.first { $0.id == selectedLibraryID } ?? libraries[0] }
    func copies(for movie: Movie, libraryID: String? = nil) -> [OwnedCopy] {
        let accessible = Set(libraries.map(\.id))
        return copies.filter { $0.movieID == movie.id && accessible.contains($0.libraryID) && (libraryID == nil || $0.libraryID == libraryID) }
    }
    func movies(in libraryID: String) -> [Movie] { movies.filter { !copies(for: $0, libraryID: libraryID).isEmpty } }
    func state(for movie: Movie) -> PersonalMovieState {
        personalStates.first { $0.userID == MockCatalog.userID && $0.movieID == movie.id } ?? PersonalMovieState(userID: MockCatalog.userID, movieID: movie.id)
    }
    var writableLibraries: [MovieLibrary] {
        libraries.filter { library in MockCatalog.memberships.contains { $0.userID == MockCatalog.userID && $0.libraryID == library.id && $0.role != .viewer } }
    }
    func zoomIn() { libraryColumns = max(2, libraryColumns - 1) }
    func zoomOut() { libraryColumns = min(5, libraryColumns + 1) }
    @discardableResult func addCopy(movie: Movie, format: MovieFormat, libraryID: String) -> Bool {
        guard writableLibraries.contains(where: { $0.id == libraryID }), movies.contains(movie) else { return false }
        copies.append(OwnedCopy(id: UUID().uuidString, libraryID: libraryID, movieID: movie.id, format: format))
        return true
    }
    func update(_ movie: Movie, watched: Bool? = nil, rating: Int? = nil, clearRating: Bool = false) {
        var value = state(for: movie)
        if let watched { value.watched = watched }
        if clearRating { value.rating = nil } else if let rating { value.rating = min(5, max(1, rating)) }
        personalStates.removeAll { $0.userID == value.userID && $0.movieID == value.movieID }
        personalStates.append(value)
    }
}
