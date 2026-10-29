import XCTest

@testable import Shogun

@MainActor final class CollectionServiceTests: XCTestCase {
    func testWireMappingPreservesIdentityAndSerializesWritesWithoutUserIDs() async throws {
        let id = "30000000-0000-0000-0000-000000000001"
        var calls: [(String, [String: Any])] = []
        let service = SupabaseCollectionService { name, data in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            calls.append((name, body))
            if name == "collection_snapshot" {
                return Data(
                    """
                    {"libraries":[{"id":"library","name":"Home","is_shared":false}],
                     "memberships":[{"library_id":"library","user_id":"user","role":"owner"},
                        {"library_id":"family","user_id":"user","role":"editor"},
                        {"library_id":"view","user_id":"user","role":"viewer"}],
                     "movies":[{"id":"\(id)","title":"Arrival","release_year":2016,"synopsis":"First contact"},
                        {"id":"unknown","title":"Undated","release_year":null,"synopsis":""}],
                     "copies":[{"id":"copy","library_id":"library","movie_id":"\(id)","format":"Blu-ray"}],
                     "states":[{"user_id":"user","movie_id":"\(id)","watched":true,"rating":5}],
                     "default_library_id":"library"}
                    """.utf8)
            }
            return Data("true".utf8)
        }
        let value = try await service.load()
        XCTAssertEqual(value.movies.first?.id, id)
        XCTAssertNil(value.movies.last?.year)
        XCTAssertEqual(value.movies.last?.releaseYearText, "Unknown year")
        XCTAssertEqual(value.movies.first?.releaseYearText, "2016")
        XCTAssertEqual(value.libraries.first?.name, "Home")
        XCTAssertEqual(value.copies.first?.format, .bluRay)
        XCTAssertEqual(value.states.first?.rating, 5)
        XCTAssertEqual(value.memberships.map(\.role), [.owner, .editor, .viewer])
        XCTAssertEqual(value.defaultLibraryID, "library")
        try await service.saveState(
            PersonalMovieState(userID: "untrusted", movieID: id, watched: true))
        try await service.setDefault(libraryID: "library")
        try await service.createLibrary(id: "new", name: "Friends")
        try await service.restorePersonalLibrary()
        XCTAssertEqual(
            calls.map(\.0),
            [
                "collection_snapshot", "save_movie_diary",
                "set_default_library", "create_collection_library", "bootstrap_account",
            ])
        XCTAssertTrue(calls[1].1["personal_rating"] is NSNull)
        XCTAssertTrue(calls.allSatisfy { $0.1["user_id"] == nil })
    }
    func testEditCopiesUsesStableExpectedRowsAndOnlyCopyFields() async throws {
        var captured: [String: Any] = [:]
        let service = SupabaseCollectionService { name, data in
            XCTAssertEqual(name, "edit_collection_copies")
            captured = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            return Data("true".utf8)
        }
        let old = OwnedCopy(id: "copy", libraryID: "library", movieID: "movie", format: .dvd)
        try await service.editCopies(
            libraryID: "library", movieID: "movie", expected: [old], formats: [.bluRay, .bluRay])
        XCTAssertEqual(captured["copy_formats"] as? [String], ["Blu-ray", "Blu-ray"])
        XCTAssertEqual(
            captured["expected_copies"] as? [[String: String]], [["id": "copy", "format": "DVD"]])
        XCTAssertNil(captured["metadata"])
        XCTAssertNil(captured["user_id"])
    }
    func testMalformedSnapshotFailsClosedAndErrorsPropagate() async {
        let service = SupabaseCollectionService { _, _ in Data("{}".utf8) }
        do {
            _ = try await service.load()
            XCTFail("Expected decoding failure")
        } catch { XCTAssertTrue(error is DecodingError) }
        for failure in [CollectionFailure.access, .expired, .invalid, .unavailable] {
            XCTAssertFalse(failure.localizedDescription.isEmpty)
        }
    }
}

@MainActor final class MovieAddTests: XCTestCase {
    final class Discovery: MovieDiscoveryServicing {
        var fail = false
        var before: (() async -> Void)?
        func search(query: String, page: Int) async throws -> CatalogPage {
            CatalogPage(page: page, totalPages: 1, results: [DiscoveryUITestService.arrival])
        }
        func details(id: Int) async throws -> CatalogMovie {
            await before?()
            if fail { throw DiscoveryFailure.unavailable }
            return DiscoveryUITestService.arrival
        }
    }
    func testDraftMetadataSelectionManualValidationAndRetryIdentity() async throws {
        let discovery = Discovery()
        let draft = MovieAddDraft(discovery: discovery)
        draft.libraryID = "library"
        XCTAssertFalse(draft.canSave)
        discovery.fail = true
        await draft.select(DiscoveryUITestService.arrival)
        XCTAssertNotNil(draft.error)
        XCTAssertFalse(draft.canSave)
        discovery.fail = false
        await draft.select(DiscoveryUITestService.arrival)
        XCTAssertTrue(draft.formats.isEmpty)
        XCTAssertFalse(draft.canSave)
        draft.quantities[.bluRay] = 1
        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.metadata.director, "Denis Villeneuve")
        XCTAssertEqual(draft.metadata.runtimeMinutes, 116)
        XCTAssertEqual(draft.providerID, 329865)
        let first = draft.saveIntent()
        XCTAssertEqual(draft.saveIntent(), first)
        // Provider display metadata is not part of the submitted import payload.
        draft.metadata.title = "Updated provider display"
        XCTAssertEqual(draft.saveIntent().id, first.id)
        draft.quantities[.dvd] = 2
        let changed = draft.saveIntent()
        XCTAssertNotEqual(changed.id, first.id)
        XCTAssertEqual(changed.formats, [.dvd, .dvd, .bluRay])
        draft.enterManually(title: "  My film  ")
        XCTAssertNil(draft.providerID)
        XCTAssertEqual(draft.metadata.title, "My film")
        XCTAssertTrue(draft.canSave)
        XCTAssertNotEqual(draft.saveIntent().id, changed.id)
        draft.metadata.year = 1
        XCTAssertFalse(draft.canSave)
        draft.metadata.year = nil
        draft.metadata.runtimeMinutes = 0
        XCTAssertFalse(draft.canSave)
        draft.metadata.runtimeMinutes = 100
        draft.metadata.posterURL = "http://example.com/image.jpg"
        XCTAssertFalse(draft.canSave)
        draft.metadata.posterURL = "https://example.com/image.jpg"
        XCTAssertTrue(draft.canSave)
        draft.metadata.posterURL = "https://user:password@example.com/image.jpg"
        XCTAssertFalse(draft.canSave)
        draft.metadata.posterURL = ""
        draft.quantities = [:]
        XCTAssertFalse(draft.canSave)
        draft.quantities = [.dvd: 99, .bluRay: 1]
        XCTAssertFalse(draft.canSave)
        draft.resetSelection()
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.manual)
    }
    func testCancelledSelectionCannotOverwriteManualDraft() async {
        let discovery = Discovery()
        let draft = MovieAddDraft(discovery: discovery)
        discovery.before = { draft.enterManually(title: "Keep this") }
        await draft.select(DiscoveryUITestService.arrival)
        XCTAssertEqual(draft.metadata.title, "Keep this")
        XCTAssertNil(draft.providerID)
        XCTAssertFalse(draft.loading)
    }
    func testManualAndProviderSerializationAndErrors() async throws {
        var calls: [(String, [String: Any])] = []
        var imports: [[String: Any]] = []
        let service = SupabaseCollectionService(catalog: { data in
            imports.append(
                try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
            return Data("{}".utf8)
        }) { name, data in
            calls.append(
                (name, try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])))
            return Data("true".utf8)
        }
        var metadata = MovieMetadata(DiscoveryUITestService.arrival)
        let id = UUID().uuidString
        try await service.addMovie(
            MovieAddRequest(
                id: id, libraryID: "library", providerID: nil, metadata: metadata,
                formats: [.dvd, .dvd]))
        XCTAssertEqual(calls.first?.0, "add_manual_movie")
        XCTAssertEqual(calls.first?.1["copy_formats"] as? [String], ["DVD", "DVD"])
        XCTAssertNil(calls.first?.1["actor"])
        metadata.title = "Untrusted title"
        try await service.addMovie(
            MovieAddRequest(
                id: id, libraryID: "library", providerID: 329865, metadata: metadata,
                formats: [.uhd]))
        XCTAssertEqual(imports.first?["movieID"] as? Int, 329865)
        XCTAssertNil(imports.first?["metadata"])
        XCTAssertNil(imports.first?["actor"])
        let invalid = MovieAddRequest(
            id: "bad", libraryID: "library", providerID: nil, metadata: metadata, formats: [.dvd])
        do {
            try await service.addMovie(invalid)
            XCTFail("invalid request accepted")
        } catch { XCTAssertEqual(error as? CollectionFailure, .invalid) }
        let failing = SupabaseCollectionService(catalog: { _ in throw SignInFailure.expired }) {
            _, _ in throw CollectionFailure.access
        }
        do {
            try await failing.addMovie(
                MovieAddRequest(
                    id: id, libraryID: "library", providerID: 1, metadata: metadata, formats: [.dvd]
                ))
            XCTFail()
        } catch { XCTAssertEqual(error as? CollectionFailure, .expired) }
        do {
            try await failing.addMovie(
                MovieAddRequest(
                    id: id, libraryID: "library", providerID: nil, metadata: metadata,
                    formats: [.dvd]))
            XCTFail()
        } catch { XCTAssertEqual(error as? CollectionFailure, .access) }
    }
}
