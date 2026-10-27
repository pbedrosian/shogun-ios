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
        try await service.saveCopy(id: "copy", libraryID: "library", movieID: id, format: .dvd)
        try await service.saveState(
            PersonalMovieState(userID: "untrusted", movieID: id, watched: true))
        try await service.setDefault(libraryID: "library")
        try await service.createLibrary(id: "new", name: "Friends")
        try await service.restorePersonalLibrary()
        XCTAssertEqual(
            calls.map(\.0),
            [
                "collection_snapshot", "save_collection_copy", "save_movie_diary",
                "set_default_library", "create_collection_library", "bootstrap_account",
            ])
        XCTAssertEqual(calls[1].1["copy_id"] as? String, "copy")
        XCTAssertEqual(calls[1].1["target_movie"] as? String, id)
        XCTAssertTrue(calls[2].1["personal_rating"] is NSNull)
        XCTAssertTrue(calls.allSatisfy { $0.1["user_id"] == nil })
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
