import XCTest

@testable import Shogun

final class SearchTests: XCTestCase {
    func testEmptyGlobalQueryReturnsWholeCatalogIncludingUnowned() throws {
        XCTAssertEqual(Fixtures.store().searchResults, Fixtures.movies)
    }

    func testGlobalSearchMatchesTitleIgnoringCase() throws {
        let store = Fixtures.store()
        store.searchQuery = "RRIv"
        XCTAssertEqual(store.searchResults.map(\.id), ["arrival"])
    }

    func testGlobalSearchMatchesReleaseYear() throws {
        let store = Fixtures.store()
        store.searchQuery = "2016"
        XCTAssertEqual(store.searchResults.map(\.id), ["arrival", "unowned"])
    }

    func testGlobalSearchMatchesPartialYear() throws {
        let store = Fixtures.store()
        store.searchQuery = "197"
        XCTAssertEqual(store.searchResults.map(\.id), ["jaws"])
    }

    func testNoMatchReturnsEmptyResults() throws {
        let store = Fixtures.store()
        store.searchQuery = "no such movie"
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    func testGlobalSearchIsIndependentOfSelectedLibrary() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "family"
        store.searchQuery = "unowned"
        XCTAssertEqual(store.searchResults.map(\.id), ["unowned"])
    }

    func testLibrarySearchIsScopedAndDeduplicated() throws {
        let store = Fixtures.store()
        store.libraryQuery = "ARR"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.selectedLibraryID = "readonly"
        XCTAssertTrue(store.libraryResults.isEmpty)
    }

    func testLibrarySearchDoesNotMatchYear() throws {
        let store = Fixtures.store()
        store.libraryQuery = "2016"
        XCTAssertTrue(store.libraryResults.isEmpty)
    }

    func testEmptyLibraryQueryReturnsSelectedLibraryMovies() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "readonly"
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws"])
    }

    func testClearingQueriesRestoresResults() throws {
        let store = Fixtures.store()
        store.searchQuery = "absent"
        store.libraryQuery = "absent"
        store.searchQuery = ""
        store.libraryQuery = ""
        XCTAssertEqual(store.searchResults, Fixtures.movies)
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
    }

    func testQueriesAreIndependent() throws {
        let store = Fixtures.store()
        store.searchQuery = "jaws"
        store.libraryQuery = "arrival"
        XCTAssertEqual(store.searchResults.map(\.id), ["jaws"])
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
    }

    func testWhitespaceIsLiteralRatherThanSilentlyTrimmed() throws {
        let store = Fixtures.store()
        store.searchQuery = " Arrival "
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    func testLibraryResultsRefreshAfterCopyAdded() throws {
        let store = Fixtures.store()
        store.libraryQuery = "unowned"
        XCTAssertTrue(store.libraryResults.isEmpty)
        XCTAssertTrue(store.addCopy(movie: Fixtures.unowned, format: .dvd, libraryID: "personal"))
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned"])
    }

    func testLibraryFormatsCombineAsUnionWithSearchAndLibraryScope() {
        let store = Fixtures.store()
        store.libraryFormats = [.dvd]
        XCTAssertTrue(store.libraryResults.isEmpty)  // Family DVD must not match personal UHD.
        store.selectedLibraryID = "family"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.libraryFormats = [.dvd, .vhs]
        store.libraryQuery = "ARR"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        store.selectedLibraryID = "readonly"
        XCTAssertTrue(store.libraryResults.isEmpty)
        store.libraryQuery = ""
        XCTAssertEqual(store.libraryResults.map(\.id), ["jaws"])
        store.libraryFormats.removeAll()
        store.selectedLibraryID = "personal"
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival"])
        XCTAssertEqual(store.copies.count, Fixtures.copies.count)
    }

    func testRecentlyAddedUsesNewestCopyInSelectedLibraryAndKeepsSingleCard() {
        let copies = [
            OwnedCopy(
                id: "1", libraryID: "personal", movieID: "arrival", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 10)),
            OwnedCopy(
                id: "2", libraryID: "personal", movieID: "arrival", format: .vhs,
                createdAt: Date(timeIntervalSince1970: 30)),
            OwnedCopy(
                id: "3", libraryID: "personal", movieID: "jaws", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 20)),
            OwnedCopy(
                id: "4", libraryID: "family", movieID: "jaws", format: .dvd,
                createdAt: Date(timeIntervalSince1970: 40)),
            OwnedCopy(id: "5", libraryID: "personal", movieID: "unowned", format: .dvd),
        ]
        let store = CatalogStore(
            movies: Fixtures.movies.reversed(), copies: copies,
            libraries: Fixtures.libraries, memberships: Fixtures.memberships,
            userID: "me", personalStates: [])
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
        store.libraryFormats = [.dvd]
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
        store.librarySort = .titleDescending
        XCTAssertEqual(store.libraryResults.map(\.id), ["unowned", "jaws", "arrival"])
        store.librarySort = .titleAscending
        XCTAssertEqual(store.libraryResults.map(\.id), ["arrival", "jaws", "unowned"])
    }

    func testLibrarySortTiesUseYearThenStableIDAndMissingDatesSortLast() {
        let movies = [
            Movie(id: "b", title: "Same", year: 2000, palette: 0, synopsis: ""),
            Movie(id: "a", title: "Same", year: 2000, palette: 0, synopsis: ""),
            Movie(id: "old", title: "Same", year: 1990, palette: 0, synopsis: ""),
            Movie(id: "missing", title: "A", year: nil, palette: 0, synopsis: ""),
        ]
        let copies = movies.map {
            OwnedCopy(
                id: $0.id, libraryID: "personal", movieID: $0.id, format: .dvd,
                createdAt: $0.id == "missing" ? nil : Date(timeIntervalSince1970: 10))
        }
        let store = CatalogStore(
            movies: movies, copies: copies, libraries: Fixtures.libraries,
            memberships: Fixtures.memberships, userID: "me", personalStates: [])
        XCTAssertEqual(store.libraryResults.map(\.id), ["old", "a", "b", "missing"])
        store.librarySort = .titleAscending
        XCTAssertEqual(store.libraryResults.map(\.id), ["missing", "old", "a", "b"])
        store.librarySort = .titleDescending
        XCTAssertEqual(store.libraryResults.map(\.id), ["old", "a", "b", "missing"])
    }

    func testTenThousandMovieLibraryCombinesSortFiltersAndSearch() {
        let movies = (0..<10_000).map {
            Movie(
                id: "movie-\($0)", title: String(format: "Movie %05d", $0), year: 2000,
                palette: 0, synopsis: "")
        }
        var copies = movies.enumerated().map { index, movie in
            OwnedCopy(
                id: movie.id, libraryID: "personal", movieID: movie.id, format: .dvd,
                createdAt: Date(timeIntervalSince1970: Double(index)))
        }
        copies += movies.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { index, movie in
            OwnedCopy(id: "vhs-\(index)", libraryID: "personal", movieID: movie.id, format: .vhs)
        }
        let store = CatalogStore(
            movies: movies, copies: copies, libraries: Fixtures.libraries,
            memberships: Fixtures.memberships, userID: "me", personalStates: [])
        let start = Date()
        let all = store.libraryResults
        XCTAssertEqual(all.count, 10_000)
        XCTAssertEqual(all.first?.id, "movie-9999")
        store.libraryFormats = [.vhs]
        store.librarySort = .titleAscending
        let filtered = store.libraryResults
        XCTAssertEqual(filtered.count, 5_000)
        XCTAssertEqual(filtered.first?.id, "movie-0")
        store.libraryQuery = "09998"
        XCTAssertEqual(store.libraryResults.map(\.id), ["movie-9998"])
        store.selectedLibraryID = "hidden"
        XCTAssertTrue(store.libraryResults.isEmpty)
        print(
            "10,000-movie sort/filter/search sequence: \(Date().timeIntervalSince(start)) seconds")
    }

}
