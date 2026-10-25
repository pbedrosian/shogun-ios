import XCTest
@testable import Shogun

final class CatalogIntegrityTests: XCTestCase {
    func testDemoIdentifiersAreUnique() throws {
        XCTAssertEqual(Set(MockCatalog.movies.map(\.id)).count, MockCatalog.movies.count)
        XCTAssertEqual(Set(MockCatalog.copies.map(\.id)).count, MockCatalog.copies.count)
        XCTAssertEqual(Set(MockCatalog.libraries.map(\.id)).count, MockCatalog.libraries.count)
    }

    func testCopiesReferenceExistingMoviesAndLibraries() throws {
        for copy in MockCatalog.copies {
            XCTAssertTrue(MockCatalog.movies.contains { $0.id == copy.movieID }, copy.id)
            XCTAssertTrue(MockCatalog.libraries.contains { $0.id == copy.libraryID }, copy.id)
        }
    }

    func testMembershipsReferenceExistingLibraries() throws {
        for membership in MockCatalog.memberships {
            XCTAssertTrue(MockCatalog.libraries.contains { $0.id == membership.libraryID })
        }
    }

    func testDemoIncludesEveryFormat() throws {
        XCTAssertEqual(Set(MockCatalog.copies.map(\.format)), Set(MovieFormat.allCases))
    }

    func testDemoPreservesRepeatedCopiesAndSharedMetadata() throws {
        XCTAssertEqual(MockCatalog.copies.filter { $0.movieID == "jaws-1975" && $0.format == .vhs }.count, 2)
        XCTAssertEqual(Set(MockCatalog.copies.filter { $0.movieID == "arrival-2016" }.map(\.libraryID)).count, 2)
        XCTAssertEqual(MockCatalog.movies.filter { $0.id == "arrival-2016" }.count, 1)
    }

}
