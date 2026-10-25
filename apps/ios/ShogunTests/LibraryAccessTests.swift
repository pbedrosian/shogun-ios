import XCTest
@testable import Shogun

final class LibraryAccessTests: XCTestCase {
    func testOnlyCurrentUsersLibrariesAreVisible() throws {
        XCTAssertEqual(Fixtures.store().libraries.map(\.id), ["personal", "family", "readonly"])
    }

    func testOwnerAndEditorCanWriteButViewerCannot() throws {
        XCTAssertEqual(Fixtures.store().writableLibraries.map(\.id), ["personal", "family"])
    }

    func testAnotherUsersPermissionsDoNotLeak() throws {
        let store = Fixtures.store(userID: "other")
        XCTAssertEqual(store.libraries.map(\.id), ["hidden"])
        XCTAssertEqual(store.writableLibraries.map(\.id), ["hidden"])
    }

    func testUserWithoutMembershipHasNoAccess() throws {
        let store = Fixtures.store(userID: "nobody")
        XCTAssertTrue(store.libraries.isEmpty)
        XCTAssertTrue(store.writableLibraries.isEmpty)
        XCTAssertTrue(store.copies(for: Fixtures.arrival).isEmpty)
        XCTAssertFalse(store.addCopy(movie: Fixtures.arrival, format: .dvd, libraryID: "personal"))
    }

    func testSelectedLibraryFollowsSelection() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "family"
        XCTAssertEqual(store.selectedLibrary.id, "family")
    }

    func testInvalidSelectionFallsBackToFirstAccessibleLibrary() throws {
        let store = Fixtures.store()
        store.selectedLibraryID = "hidden"
        XCTAssertEqual(store.selectedLibrary.id, "personal")
    }

}
