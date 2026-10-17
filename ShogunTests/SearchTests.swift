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

}
