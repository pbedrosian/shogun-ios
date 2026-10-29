import XCTest
@testable import Shogun

final class AddCopyTests: XCTestCase {
    func testOwnerAndEditorCanAddCopies() throws {
        for libraryID in ["personal", "family"] {
            let store = Fixtures.store()
            XCTAssertTrue(store.addCopy(movie: Fixtures.unowned, format: .bluRay, libraryID: libraryID))
            let copy = try XCTUnwrap(store.copies.last)
            XCTAssertEqual(copy.movieID, "unowned")
            XCTAssertEqual(copy.libraryID, libraryID)
            XCTAssertEqual(copy.format, .bluRay)
            XCTAssertEqual(store.copies.count, Fixtures.copies.count + 1)
        }
    }

    func testRejectedLibrariesPreserveAllCopies() throws {
        for libraryID in ["readonly", "hidden", "missing", ""] {
            let store = Fixtures.store()
            XCTAssertFalse(store.addCopy(movie: Fixtures.arrival, format: .dvd, libraryID: libraryID))
            XCTAssertEqual(store.copies.map(\.id), Fixtures.copies.map(\.id))
        }
    }

    func testUnknownMovieIsRejected() throws {
        let store = Fixtures.store()
        let unknown = Movie(id: "unknown", title: "Unknown", year: 2020, palette: 0, synopsis: "")
        XCTAssertFalse(store.addCopy(movie: unknown, format: .dvd, libraryID: "personal"))
        XCTAssertEqual(store.copies.count, Fixtures.copies.count)
    }

    func testAlteredMetadataWithExistingIDIsRejected() throws {
        let store = Fixtures.store()
        let changed = Movie(id: "arrival", title: "Changed", year: 2016, palette: 0, synopsis: "First contact")
        XCTAssertFalse(store.addCopy(movie: changed, format: .dvd, libraryID: "personal"))
        XCTAssertEqual(store.copies.count, Fixtures.copies.count)
    }

    func testRepeatedAdditionsHaveUniqueIDsAndOneMovieCard() throws {
        let store = Fixtures.store()
        for _ in 0..<3 { XCTAssertTrue(store.addCopy(movie: Fixtures.arrival, format: .uhd, libraryID: "personal")) }
        XCTAssertEqual(Set(store.copies.map(\.id)).count, store.copies.count)
        XCTAssertEqual(store.copies(for: Fixtures.arrival, libraryID: "personal").count, 5)
        XCTAssertEqual(store.movies(in: "personal").map(\.id), ["arrival"])
        XCTAssertEqual(store.movies, Fixtures.movies)
    }

    func testEveryFormatCanBeAdded() throws {
        let store = Fixtures.store()
        for format in MovieFormat.allCases {
            XCTAssertTrue(store.addCopy(movie: Fixtures.unowned, format: format, libraryID: "personal"))
            XCTAssertEqual(store.copies.last?.format, format)
        }
    }

    func testAddingCopyDoesNotChangePersonalStateOrSelection() throws {
        let store = Fixtures.store()
        store.update(Fixtures.arrival, watched: true, rating: 4)
        XCTAssertTrue(store.addCopy(movie: Fixtures.arrival, format: .dvd, libraryID: "family"))
        XCTAssertEqual(store.selectedLibraryID, "personal")
        XCTAssertEqual(store.state(for: Fixtures.arrival).rating, 4)
        XCTAssertTrue(store.state(for: Fixtures.arrival).watched)
    }

}
