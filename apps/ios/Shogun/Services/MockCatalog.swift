import Foundation

enum MockCatalog {
    static let userID = "demo-user"
    static let libraries = [
        MovieLibrary(id: "personal", name: "My Library", isShared: false),
        MovieLibrary(id: "family", name: "Family Collection", isShared: true),
        MovieLibrary(id: "movie-club", name: "The Incredibly Extensive Shared Movie Collection of Family, Friends, Neighbors, and the Friday Night Film Appreciation Society", isShared: true)
    ]
    static let memberships = [
        LibraryMembership(userID: userID, libraryID: "personal", role: .owner),
        LibraryMembership(userID: userID, libraryID: "family", role: .editor),
        LibraryMembership(userID: userID, libraryID: "movie-club", role: .editor)
    ]
    static let movies: [Movie] = [
        Movie(id: "arrival-2016", title: "Arrival", year: 2016, palette: 0, synopsis: "A linguist searches for meaning when mysterious visitors arrive on Earth."),
        Movie(id: "grand-budapest-2014", title: "The Grand Budapest Hotel With a very long long title that could go one for some time so we'll see how long and the ui reposnds to this", year: 2014, palette: 1, synopsis: "A legendary concierge and his young colleague become entangled in an extraordinary adventure."),
        Movie(id: "interstellar-2014", title: "Interstellar", year: 2014, palette: 2, synopsis: "A team of explorers journeys beyond the stars in search of a future for humanity."),
        Movie(id: "spirited-away-2001", title: "Spirited Away", year: 2001, palette: 3, synopsis: "A young girl discovers a remarkable spirit world and finds the courage to save her family."),
        Movie(id: "blade-runner-1982", title: "Blade Runner", year: 1982, palette: 4, synopsis: "A detective pursues artificial humans through a rain-soaked future city."),
        Movie(id: "jaws-1975", title: "Jaws", year: 1975, palette: 5, synopsis: "An island community confronts a powerful threat beneath the summer waves."),
        Movie(id: "moonrise-2012", title: "Moonrise Kingdom", year: 2012, palette: 3, synopsis: "Two young adventurers run away together, setting a small island in motion."),
        Movie(id: "metropolis-1927", title: "Metropolis", year: 1927, palette: 2, synopsis: "In a towering future city, a divided society faces a moment of transformation.")
    ]
    static let copies = [
        OwnedCopy(id: "c1", libraryID: "personal", movieID: "arrival-2016", format: .uhd),
        OwnedCopy(id: "c2", libraryID: "personal", movieID: "arrival-2016", format: .digital),
        OwnedCopy(id: "c12", libraryID: "personal", movieID: "arrival-2016", format: .bluRay),
        OwnedCopy(id: "c13", libraryID: "personal", movieID: "arrival-2016", format: .vhs),
        OwnedCopy(id: "c3", libraryID: "personal", movieID: "grand-budapest-2014", format: .bluRay),
        OwnedCopy(id: "c4", libraryID: "personal", movieID: "interstellar-2014", format: .uhd),
        OwnedCopy(id: "c5", libraryID: "personal", movieID: "spirited-away-2001", format: .dvd),
        OwnedCopy(id: "c6", libraryID: "personal", movieID: "blade-runner-1982", format: .bluRay),
        OwnedCopy(id: "c7", libraryID: "personal", movieID: "jaws-1975", format: .vhs),
        OwnedCopy(id: "c8", libraryID: "family", movieID: "arrival-2016", format: .bluRay),
        OwnedCopy(id: "c9", libraryID: "family", movieID: "spirited-away-2001", format: .bluRay),
        OwnedCopy(id: "c10", libraryID: "family", movieID: "moonrise-2012", format: .dvd),
        OwnedCopy(id: "c11", libraryID: "personal", movieID: "jaws-1975", format: .vhs),
        OwnedCopy(id: "c14", libraryID: "movie-club", movieID: "metropolis-1927", format: .bluRay),
        OwnedCopy(id: "c15", libraryID: "movie-club", movieID: "moonrise-2012", format: .dvd)
    ]
}
