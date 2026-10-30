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

    func testUnknownSavedPreferencesFallBackAndKeepRecognizedFormats() throws {
        let suite = "shogun-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(
            ["sort": "Unknown sort", "formats": ["DVD", "Unknown format"], "columns": 99],
            forKey: "library.preferences.v1.\(MockCatalog.userID)")
        let store = CatalogStore(preferences: preferences)
        XCTAssertEqual(store.librarySort, .recentlyAdded)
        XCTAssertEqual(store.libraryFormats, [.dvd])
        XCTAssertEqual(store.libraryColumns, 3)
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

    func testPinchAndMenuShareDensityState() {
        let store = Fixtures.store()
        store.updateLibraryPinch(magnification: 1.3, startingColumns: 3)
        XCTAssertEqual(store.libraryColumns, 2)
        store.zoomOut()
        XCTAssertEqual(store.libraryColumns, 3)
        store.updateLibraryPinch(magnification: 0.8, startingColumns: 3)
        XCTAssertEqual(store.libraryColumns, 4)
        store.zoomIn()
        XCTAssertEqual(store.libraryColumns, 3)
    }

    func testPinchCanReverseDirectionWithoutLiftingFingers() {
        let store = Fixtures.store()
        for (scale, expected) in [(0.6, 5), (0.8, 4), (1.0, 3), (1.5, 2), (1.0, 3), (0.6, 5)] {
            store.updateLibraryPinch(magnification: scale, startingColumns: 3)
            XCTAssertEqual(store.libraryColumns, expected)
        }
    }

    func testPinchIgnoresSmallOrInvalidMovements() {
        let store = Fixtures.store()
        for scale in [1.0, 1.1, 0.9, 0, -1, .nan, .infinity] {
            store.updateLibraryPinch(magnification: scale, startingColumns: 3)
            XCTAssertEqual(store.libraryColumns, 3)
        }
        store.updateLibraryPinch(magnification: 0.5, startingColumns: 0)
        XCTAssertEqual(store.libraryColumns, 3)
    }

    func testPinchClampsExtremeScalesAndUsesNewGestureBaseline() {
        let store = Fixtures.store()
        store.updateLibraryPinch(magnification: .leastNonzeroMagnitude, startingColumns: 3)
        XCTAssertEqual(store.libraryColumns, 5)
        store.updateLibraryPinch(magnification: .greatestFiniteMagnitude, startingColumns: 3)
        XCTAssertEqual(store.libraryColumns, 2)
        store.zoomOut()
        store.zoomOut()
        store.updateLibraryPinch(magnification: 1.3, startingColumns: store.libraryColumns)
        XCTAssertEqual(store.libraryColumns, 3)
    }

    func testPinchSupportsEveryStartingDensityWithoutCompoundingUpdates() {
        let store = Fixtures.store()
        for startingColumns in 2...5 {
            for targetColumns in 2...5 {
                let scale = Double(startingColumns) / Double(targetColumns)
                for _ in 0..<3 {
                    store.updateLibraryPinch(magnification: scale, startingColumns: startingColumns)
                    XCTAssertEqual(store.libraryColumns, targetColumns)
                }
            }
            store.updateLibraryPinch(magnification: 1, startingColumns: startingColumns)
            XCTAssertEqual(store.libraryColumns, startingColumns)
        }
    }

    func testInvalidPinchBaselineLeavesExistingDensityUnchanged() {
        let store = Fixtures.store()
        store.zoomOut()
        for baseline in [Int.min, -1, 0, 1, 6, Int.max] {
            store.updateLibraryPinch(magnification: 2, startingColumns: baseline)
            XCTAssertEqual(store.libraryColumns, 4)
        }
        store.updateLibraryPinch(magnification: -.infinity, startingColumns: 4)
        XCTAssertEqual(store.libraryColumns, 4)
    }

    func testPinchWorksWithNoVisibleMoviesAndPreservesCollectionState() {
        let store = Fixtures.store()
        store.selectedLibraryID = "family"
        store.libraryQuery = "no matching movies"
        store.searchQuery = "jaws"
        let originalCopies = store.copies
        let originalState = store.state(for: Fixtures.arrival)
        XCTAssertTrue(store.libraryResults.isEmpty)

        store.updateLibraryPinch(magnification: 0.6, startingColumns: 3)

        XCTAssertEqual(store.libraryColumns, 5)
        XCTAssertEqual(store.selectedLibraryID, "family")
        XCTAssertEqual(store.libraryQuery, "no matching movies")
        XCTAssertEqual(store.searchQuery, "jaws")
        XCTAssertEqual(store.copies.map(\.id), originalCopies.map(\.id))
        XCTAssertEqual(store.state(for: Fixtures.arrival).watched, originalState.watched)
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, originalState.rating)
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
