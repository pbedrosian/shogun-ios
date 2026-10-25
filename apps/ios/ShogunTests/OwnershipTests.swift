import XCTest
@testable import Shogun

final class OwnershipTests: XCTestCase {
    func testCopiesSpanAccessibleLibraries() throws {
        XCTAssertEqual(Fixtures.store().copies(for: Fixtures.arrival).map(\.id), ["1", "2", "3"])
    }

    func testCopiesCanBeScopedToOneLibrary() throws {
        XCTAssertEqual(Fixtures.store().copies(for: Fixtures.arrival, libraryID: "family").map(\.id), ["3"])
    }

    func testHiddenAndUnknownLibrariesReturnNoCopies() throws {
        let store = Fixtures.store()
        XCTAssertTrue(store.copies(for: Fixtures.unowned).isEmpty)
        XCTAssertTrue(store.copies(for: Fixtures.unowned, libraryID: "hidden").isEmpty)
        XCTAssertTrue(store.copies(for: Fixtures.arrival, libraryID: "missing").isEmpty)
    }

    func testMoviesAreDeduplicatedDespiteRepeatedCopies() throws {
        XCTAssertEqual(Fixtures.store().movies(in: "personal").map(\.id), ["arrival"])
    }

    func testViewerCanReadOwnedMovies() throws {
        XCTAssertEqual(Fixtures.store().movies(in: "readonly").map(\.id), ["jaws"])
    }

    func testInaccessibleLibraryReturnsNoMovies() throws {
        XCTAssertTrue(Fixtures.store().movies(in: "hidden").isEmpty)
    }

    func testUnownedMovieHasNoAccessibleCopies() throws {
        XCTAssertTrue(Fixtures.store().copies(for: Fixtures.unowned).isEmpty)
    }

}
