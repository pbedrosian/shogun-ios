import SwiftUI

final class CatalogStore: ObservableObject {
    @Published private(set) var movies: [Movie]
    private let userID: String
    @Published private var catalogLibraries: [MovieLibrary]
    @Published private var memberships: [LibraryMembership]
    @Published private(set) var copies: [OwnedCopy]
    @Published var libraryColumns = 3
    @Published var showingAddMovie = false
    @Published var libraryQuery = ""
    @Published var searchQuery = ""
    @Published var selectedLibraryID = "personal"
    @Published private var personalStates: [PersonalMovieState]

    /// Defaults preserve the offline demo; explicit inputs support isolated catalogs and users.
    init(movies: [Movie] = MockCatalog.movies,
         copies: [OwnedCopy] = MockCatalog.copies,
         libraries: [MovieLibrary] = MockCatalog.libraries,
         memberships: [LibraryMembership] = MockCatalog.memberships,
         userID: String = MockCatalog.userID,
         personalStates: [PersonalMovieState] = [PersonalMovieState(userID: MockCatalog.userID, movieID: "arrival-2016", watched: true, rating: 5)]) {
        self.movies = movies
        self.copies = copies
        self.catalogLibraries = libraries
        self.memberships = memberships
        self.userID = userID
        self.personalStates = personalStates
    }

    /// Apply a confirmed snapshot without recreating navigation or losing an open form's draft.
    func replaceContents(from other: CatalogStore) {
        precondition(userID == other.userID)
        movies = other.movies
        copies = other.copies
        catalogLibraries = other.catalogLibraries
        memberships = other.memberships
        personalStates = other.personalStates
        selectedLibraryID = other.selectedLibraryID
    }

    /// Library search is title-only; global search also matches release years.
    var libraryResults: [Movie] {
        movies(in: selectedLibraryID).filter { libraryQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(libraryQuery) }
    }
    var searchResults: [Movie] {
        movies.filter { searchQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(searchQuery) || ($0.year.map(String.init)?.contains(searchQuery) == true) }
    }
    var libraries: [MovieLibrary] {
        catalogLibraries.filter { library in memberships.contains { $0.userID == userID && $0.libraryID == library.id } }
    }
    var selectedLibrary: MovieLibrary? { libraries.first { $0.id == selectedLibraryID } ?? libraries.first }
    func copies(for movie: Movie, libraryID: String? = nil) -> [OwnedCopy] {
        let accessible = Set(libraries.map(\.id))
        return copies.filter { $0.movieID == movie.id && accessible.contains($0.libraryID) && (libraryID == nil || $0.libraryID == libraryID) }
    }
    func movies(in libraryID: String) -> [Movie] { movies.filter { !copies(for: $0, libraryID: libraryID).isEmpty } }
    func state(for movie: Movie) -> PersonalMovieState {
        personalStates.first { $0.userID == userID && $0.movieID == movie.id } ?? PersonalMovieState(userID: userID, movieID: movie.id)
    }
    var writableLibraries: [MovieLibrary] {
        libraries.filter { library in memberships.contains { $0.userID == userID && $0.libraryID == library.id && $0.role != .viewer } }
    }
    func zoomIn() { libraryColumns = max(2, libraryColumns - 1) }
    func zoomOut() { libraryColumns = min(5, libraryColumns + 1) }
    /// Always measure against the gesture's initial density so updates never compound.
    func updateLibraryPinch(magnification: Double, startingColumns: Int) {
        guard magnification.isFinite, magnification > 0, (2...5).contains(startingColumns) else { return }
        let columns = (Double(startingColumns) / magnification).rounded()
        libraryColumns = Int(min(5, max(2, columns)))
    }
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
