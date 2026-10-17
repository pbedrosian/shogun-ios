import XCTest
@testable import Shogun

final class PresentationStateTests: XCTestCase {
    func testInitialPresentationState() throws {
        let store = CatalogStore()
        XCTAssertEqual(store.libraryColumns, 3)
        XCTAssertFalse(store.showingAddMovie)
        XCTAssertEqual(store.libraryQuery, "")
        XCTAssertEqual(store.searchQuery, "")
        XCTAssertEqual(store.selectedLibraryID, "personal")
    }

    func testZoomMovesOneColumnAtATime() throws {
        let store = Fixtures.store()
        store.zoomIn()
        XCTAssertEqual(store.libraryColumns, 2)
        store.zoomOut()
        XCTAssertEqual(store.libraryColumns, 3)
    }

    func testZoomStopsAtBothBounds() throws {
        let store = Fixtures.store()
        for _ in 0..<20 { store.zoomIn() }
        XCTAssertEqual(store.libraryColumns, 2)
        for _ in 0..<20 { store.zoomOut() }
        XCTAssertEqual(store.libraryColumns, 5)
    }

    func testNewStoreResetsDemoEditsAndPresentation() throws {
        let store = CatalogStore()
        let movie = try XCTUnwrap(store.movies.first)
        store.update(movie, watched: false, rating: 1)
        store.addCopy(movie: movie, format: .dvd, libraryID: "personal")
        store.selectedLibraryID = "family"
        store.libraryQuery = "arrival"
        store.searchQuery = "2016"
        store.showingAddMovie = true
        store.zoomOut()
        let fresh = CatalogStore()
        XCTAssertEqual(fresh.copies.count, MockCatalog.copies.count)
        XCTAssertEqual(fresh.state(for: movie).rating, 5)
        XCTAssertTrue(fresh.state(for: movie).watched)
        XCTAssertEqual(fresh.selectedLibraryID, "personal")
        XCTAssertEqual(fresh.libraryQuery, "")
        XCTAssertEqual(fresh.searchQuery, "")
        XCTAssertFalse(fresh.showingAddMovie)
        XCTAssertEqual(fresh.libraryColumns, 3)
    }

}
