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
        init(_ snapshot: CollectionSnapshot) { self.snapshot = snapshot }
        var addRequests: [MovieAddRequest] = []
        func editCopies(
            libraryID: String, movieID: String, expected: [OwnedCopy], formats: [MovieFormat]
        ) async throws {
            if fail { throw CollectionFailure.conflict }
        }
        func addMovie(_ request: MovieAddRequest) async throws {
            addRequests.append(request)
            if fail { throw CollectionFailure.unavailable }
            if failAfterSave { fail = true }
            guard !snapshot.movies.contains(where: { $0.id == request.id }) else { return }
            let film = Movie(
                id: request.id, title: request.metadata.title, year: request.metadata.year,
                palette: 0, synopsis: request.metadata.synopsis, tmdbID: request.providerID)
            snapshot = CollectionSnapshot(
                movies: snapshot.movies + [film], libraries: snapshot.libraries,
                memberships: snapshot.memberships,
                copies: snapshot.copies
                    + request.formats.enumerated().map {
                        OwnedCopy(
                            id: request.id + "-" + String($0.offset), libraryID: request.libraryID,
                            movieID: film.id, format: $0.element)
                    }, states: snapshot.states, defaultLibraryID: snapshot.defaultLibraryID)
        }
        func load() async throws -> CollectionSnapshot {
            if fail { throw CollectionFailure.unavailable }
            await beforeLoad?()
            afterLoad?()
            return snapshot
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
    func testLibraryPreferencesSurviveRefreshAndAccountRelaunch() async throws {
        let suite = "shogun-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake, preferences: preferences)
        await store.refresh()
        let catalog = try XCTUnwrap(store.catalog)
        catalog.librarySort = .titleDescending
        catalog.libraryFormats = [.dvd, .uhd]
        catalog.zoomOut()
        catalog.libraryQuery = "temporary search"
        await store.refresh()
        XCTAssertTrue(store.catalog === catalog)
        XCTAssertEqual(catalog.librarySort, .titleDescending)
        XCTAssertEqual(catalog.libraryFormats, [.dvd, .uhd])
        store.invalidate()

        let relaunched = CollectionStore(
            userID: user, service: fake,
            preferences: try XCTUnwrap(UserDefaults(suiteName: suite)))
        await relaunched.refresh()
        let restored = try XCTUnwrap(relaunched.catalog)
        XCTAssertEqual(restored.librarySort, .titleDescending)
        XCTAssertEqual(restored.libraryFormats, [.dvd, .uhd])
        XCTAssertEqual(restored.libraryColumns, 4)
        XCTAssertEqual(restored.libraryQuery, "")
        XCTAssertEqual(restored.selectedLibraryID, "family")

        restored.libraryFormats.removeAll()
        restored.librarySort = .recentlyAdded
        let cleared = CollectionStore(userID: user, service: fake, preferences: preferences)
        await cleared.refresh()
        XCTAssertEqual(cleared.catalog?.libraryFormats, [])
        XCTAssertEqual(cleared.catalog?.librarySort, .recentlyAdded)
    }

    func testLibraryPreferencesAreIsolatedByAccount() async throws {
        let suite = "shogun-preferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let first = CollectionStore(
            userID: user, service: Fake(fixture()), preferences: preferences)
        await first.refresh()
        first.catalog?.libraryFormats = [.digital]
        first.catalog?.librarySort = .titleAscending
        let other = CollectionStore(
            userID: UUID(), service: Fake(fixture()), preferences: preferences)
        await other.refresh()
        XCTAssertEqual(other.catalog?.libraryFormats, [])
        XCTAssertEqual(other.catalog?.librarySort, .recentlyAdded)
        XCTAssertEqual(other.catalog?.libraryColumns, 3)
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
    func testNewMovieSaveRequiresConfirmedReloadAndReusesIntentAfterLostResponse() async throws {
        let fake = Fake(fixture())
        let store = CollectionStore(userID: user, service: fake)
        await store.refresh()
        let metadata = MovieMetadata(DiscoveryUITestService.arrival)
        let id = UUID().uuidString
        let request = MovieAddRequest(
            id: id, libraryID: "personal", providerID: nil, metadata: metadata,
            formats: [.dvd, .dvd])
        fake.failAfterSave = true
        let uncertain = await store.addMovie(request)
        XCTAssertFalse(uncertain)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.catalog?.movies.contains { $0.id == id } == true)
        fake.failAfterSave = false
        fake.fail = false
        let retried = await store.addMovie(request)
        XCTAssertTrue(retried)
        XCTAssertEqual(store.catalog?.copies.filter { $0.movieID == id }.count, 2)
        XCTAssertEqual(fake.addRequests.map(\.id), [id, id])
        let readOnly = MovieAddRequest(
            id: UUID().uuidString, libraryID: "readonly", providerID: nil, metadata: metadata,
            formats: [.dvd])
        let denied = await store.addMovie(readOnly)
        XCTAssertFalse(denied)
        let invalid = MovieAddRequest(
            id: "bad", libraryID: "personal", providerID: nil, metadata: metadata, formats: [])
        let rejected = await store.addMovie(invalid)
        XCTAssertFalse(rejected)
        store.invalidate()
        let signedOut = await store.addMovie(request)
        XCTAssertFalse(signedOut)
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
