import XCTest

@testable import Shogun

@MainActor final class CollectionTests: XCTestCase {
    let user = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    @MainActor final class Fake: CollectionServicing {
        var snapshot: CollectionSnapshot
        var fail = false
        var beforeLoad: (() async -> Void)?
        var failAfterSave = false
        var afterLoad: (() -> Void)?
        var copyIDs: [String] = []
        init(_ snapshot: CollectionSnapshot) { self.snapshot = snapshot }
        func load() async throws -> CollectionSnapshot {
            if fail { throw CollectionFailure.unavailable }
            await beforeLoad?()
            afterLoad?()
            return snapshot
        }
        func saveCopy(id: String, libraryID: String, movieID: String, format: MovieFormat)
            async throws
        {
            copyIDs.append(id)
            if fail { throw CollectionFailure.access }
            if failAfterSave { fail = true }
            let copies =
                snapshot.copies.contains(where: { $0.id == id })
                ? snapshot.copies
                : snapshot.copies + [
                    OwnedCopy(id: id, libraryID: libraryID, movieID: movieID, format: format)
                ]
            snapshot = CollectionSnapshot(
                movies: snapshot.movies, libraries: snapshot.libraries,
                memberships: snapshot.memberships, copies: copies, states: snapshot.states,
                defaultLibraryID: snapshot.defaultLibraryID)
        }
        func saveState(_ state: PersonalMovieState) async throws {
            if fail { throw CollectionFailure.unavailable }
            snapshot = CollectionSnapshot(
                movies: snapshot.movies, libraries: snapshot.libraries,
                memberships: snapshot.memberships, copies: snapshot.copies, states: [state],
                defaultLibraryID: snapshot.defaultLibraryID)
        }
        func setDefault(libraryID: String) async throws {
            if fail { throw CollectionFailure.access }
            snapshot = CollectionSnapshot(
                movies: snapshot.movies, libraries: snapshot.libraries,
                memberships: snapshot.memberships, copies: snapshot.copies, states: snapshot.states,
                defaultLibraryID: libraryID)
        }
        func createLibrary(id: String, name: String) async throws {
            if fail { throw CollectionFailure.access }
        }
        func restorePersonalLibrary() async throws {
            if fail { throw CollectionFailure.unavailable }
        }
    }
    func fixture(defaultID: String? = "family", memberships: [LibraryMembership]? = nil)
        -> CollectionSnapshot
    {
        CollectionSnapshot(
            movies: Fixtures.movies, libraries: Fixtures.libraries,
            memberships: memberships
                ?? Fixtures.memberships.map {
                    LibraryMembership(
                        userID: $0.userID == "me"
                            ? user.uuidString.lowercased() : $0.userID, libraryID: $0.libraryID,
                        role: $0.role)
                }, copies: Fixtures.copies,
            states: [], defaultLibraryID: defaultID)
    }
    func testReloadRelaunchDefaultsSelectionAndRevokedAccess() async throws {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        await store.refresh()
        let catalog = try XCTUnwrap(store.catalog)
        XCTAssertEqual(catalog.selectedLibraryID, "family")
        catalog.libraryQuery = "Arrival"
        catalog.searchQuery = "2016"
        catalog.libraryColumns = 4
        catalog.selectedLibraryID = "personal"
        await store.refresh()
        XCTAssertEqual(store.catalog?.selectedLibraryID, "personal")
        XCTAssertEqual(store.catalog?.libraryQuery, "Arrival")
        XCTAssertEqual(store.catalog?.searchQuery, "2016")
        XCTAssertEqual(store.catalog?.libraryColumns, 4)
        let relaunched = CollectionStore(userID: user, service: fake)
        await relaunched.refresh()
        XCTAssertEqual(relaunched.catalog?.selectedLibraryID, "family")
        fake.snapshot = fixture(memberships: [
            LibraryMembership(
                userID: user.uuidString.lowercased(), libraryID: "readonly", role: .viewer)
        ])
        await relaunched.refresh()
        XCTAssertEqual(relaunched.catalog?.selectedLibraryID, "readonly")
        XCTAssertNil(relaunched.defaultLibraryID)
        fake.snapshot = fixture(memberships: [])
        await relaunched.refresh()
        XCTAssertNil(relaunched.catalog?.selectedLibrary)
        XCTAssertEqual(relaunched.catalog?.selectedLibraryID, "")
    }
    func testRetryIsIdempotentButIntentionalCopiesRemainDistinct() async throws {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        await store.refresh()
        fake.fail = true
        let failed = await store.saveCopy(
            id: "retry", movie: Fixtures.arrival, format: .dvd, libraryID: "personal")
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.error)
        fake.fail = false
        for id in ["retry", "retry", "another"] {
            let saved = await store.saveCopy(
                id: id, movie: Fixtures.arrival, format: .dvd, libraryID: "personal")
            XCTAssertTrue(saved)
        }
        XCTAssertEqual(store.catalog?.copies.count, Fixtures.copies.count + 2)
        XCTAssertEqual(fake.copyIDs, ["retry", "retry", "retry", "another"])
        let otherDevice = CollectionStore(userID: user, service: fake)
        await otherDevice.refresh()
        XCTAssertEqual(otherDevice.catalog?.copies.count, store.catalog?.copies.count)
        let denied = await store.saveCopy(
            id: "no", movie: Fixtures.arrival, format: .dvd, libraryID: "readonly")
        XCTAssertFalse(denied)
    }
    func testDiaryAcrossLibrariesAndUserIsolation() async throws {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        await store.refresh()
        let state = PersonalMovieState(
            userID: user.uuidString.lowercased(), movieID: Fixtures.arrival.id, watched: true,
            rating: 4)
        let saved = await store.saveDiary(state)
        XCTAssertTrue(saved)
        let reloaded = CollectionStore(userID: user, service: fake)
        await reloaded.refresh()
        XCTAssertEqual(reloaded.catalog?.state(for: Fixtures.arrival).rating, 4)
        reloaded.catalog?.selectedLibraryID = "family"
        XCTAssertTrue(reloaded.catalog?.state(for: Fixtures.arrival).watched == true)
        let outsider = CollectionStore(userID: UUID(), service: fake)
        await outsider.refresh()
        XCTAssertTrue(outsider.catalog?.libraries.isEmpty == true)
        XCTAssertNil(outsider.catalog?.state(for: Fixtures.arrival).rating)
        let foreign = await outsider.saveDiary(state)
        XCTAssertFalse(foreign)
        var invalid = state
        invalid.rating = 6
        let rejected = await store.saveDiary(invalid)
        XCTAssertFalse(rejected)
        var cleared = state
        cleared.rating = nil
        let clear = await store.saveDiary(cleared)
        XCTAssertTrue(clear)
        fake.fail = true
        let failed = await store.saveDiary(state)
        XCTAssertFalse(failed)
        XCTAssertNil(store.catalog?.state(for: Fixtures.arrival).rating)
    }
    func testDefaultSaveCreationRecoveryErrorsAndInvalidation() async throws {
        let fake = Fake(fixture(defaultID: "missing"))
        let store = CollectionStore(userID: user, service: fake)
        fake.fail = true
        await store.refresh()
        XCTAssertNil(store.catalog)
        XCTAssertNotNil(store.error)
        fake.fail = false
        await store.refresh()
        XCTAssertNil(store.error)
        XCTAssertEqual(store.catalog?.selectedLibraryID, "personal")
        let denied = await store.setDefault(libraryID: "readonly")
        XCTAssertFalse(denied)
        let saved = await store.setDefault(libraryID: "personal")
        XCTAssertTrue(saved)
        XCTAssertEqual(store.defaultLibraryID, "personal")
        let invalid = await store.createLibrary(id: "new", name: "  ")
        XCTAssertFalse(invalid)
        let created = await store.createLibrary(id: "new", name: "  Friends  ")
        XCTAssertTrue(created)
        let restored = await store.restorePersonalLibrary()
        XCTAssertTrue(restored)
        let old = store.catalog
        fake.fail = true
        await store.refresh()
        XCTAssertTrue(store.catalog === old)
        let failed = await store.setDefault(libraryID: "family")
        XCTAssertFalse(failed)
        store.invalidate()
        XCTAssertNil(store.catalog)
        XCTAssertNil(store.error)
        XCTAssertNil(store.defaultLibraryID)
        await store.refresh()
        XCTAssertNil(store.catalog)
        let inactive = await store.restorePersonalLibrary()
        XCTAssertFalse(inactive)
    }
    func testInFlightResultCannotRepopulateSignedOutStore() async {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        fake.afterLoad = { store.invalidate() }
        await store.refresh()
        XCTAssertNil(store.catalog)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isBusy)
    }
    func testLostSaveResponseAndRefreshFailureDoNotDuplicateCopy() async throws {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        await store.refresh()
        fake.failAfterSave = true
        let failed = await store.saveCopy(
            id: "stable", movie: Fixtures.arrival, format: .dvd, libraryID: "personal")
        XCTAssertFalse(failed)
        XCTAssertEqual(store.catalog?.copies.count, Fixtures.copies.count)
        fake.fail = false
        fake.failAfterSave = false
        let retry = await store.saveCopy(
            id: "stable", movie: Fixtures.arrival, format: .dvd, libraryID: "personal")
        XCTAssertTrue(retry)
        XCTAssertEqual(store.catalog?.copies.count, Fixtures.copies.count + 1)
        let original = try XCTUnwrap(store.catalog)
        original.showingAddMovie = true
        await store.refresh()
        XCTAssertTrue(store.catalog === original)
        XCTAssertTrue(original.showingAddMovie)
    }
    func testBusyAndCancelledLoadsCannotPublish() async {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        var release: CheckedContinuation<Void, Never>?
        fake.beforeLoad = { await withCheckedContinuation { release = $0 } }
        let task = Task { await store.refresh() }
        while release == nil { await Task.yield() }
        XCTAssertTrue(store.isBusy)
        await store.refresh()
        let overlapping = await store.restorePersonalLibrary()
        XCTAssertFalse(overlapping)
        task.cancel()
        release?.resume()
        await task.value
        XCTAssertNil(store.catalog)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.isBusy)
    }

}
