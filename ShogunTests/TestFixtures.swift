import XCTest
@testable import Shogun

/// Small deterministic catalog independent of the demo's display text and counts.
enum Fixtures {
    static let arrival = Movie(id: "arrival", title: "Arrival", year: 2016, symbol: "moon", palette: 0, synopsis: "First contact")
    static let jaws = Movie(id: "jaws", title: "Jaws", year: 1975, symbol: "water", palette: 1, synopsis: "Shark")
    static let unowned = Movie(id: "unowned", title: "Unowned", year: 2016, symbol: "star", palette: 2, synopsis: "Sample")
    static let movies = [arrival, jaws, unowned]
    static let libraries = [
        MovieLibrary(id: "personal", name: "Personal", isShared: false),
        MovieLibrary(id: "family", name: "Family", isShared: true),
        MovieLibrary(id: "readonly", name: "Read only", isShared: true),
        MovieLibrary(id: "hidden", name: "Hidden", isShared: true)
    ]
    static let memberships = [
        LibraryMembership(userID: "me", libraryID: "personal", role: .owner),
        LibraryMembership(userID: "me", libraryID: "family", role: .editor),
        LibraryMembership(userID: "me", libraryID: "readonly", role: .viewer),
        LibraryMembership(userID: "other", libraryID: "hidden", role: .owner)
    ]
    static let copies = [
        OwnedCopy(id: "1", libraryID: "personal", movieID: "arrival", format: .uhd),
        OwnedCopy(id: "2", libraryID: "personal", movieID: "arrival", format: .uhd),
        OwnedCopy(id: "3", libraryID: "family", movieID: "arrival", format: .dvd),
        OwnedCopy(id: "4", libraryID: "readonly", movieID: "jaws", format: .vhs),
        OwnedCopy(id: "5", libraryID: "hidden", movieID: "unowned", format: .digital)
    ]
    static func store(userID: String = "me", states: [PersonalMovieState] = []) -> CatalogStore {
        CatalogStore(movies: movies, copies: copies, libraries: libraries,
                     memberships: memberships, userID: userID, personalStates: states)
    }
}
