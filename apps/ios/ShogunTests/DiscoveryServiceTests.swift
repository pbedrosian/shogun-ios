import XCTest

@testable import Shogun

@MainActor final class DiscoveryServiceTests: XCTestCase {
    let film = """
        {"id":329865,"title":"Arrival","year":2016,"synopsis":"First contact","posterURL":"https://image.tmdb.org/t/p/w342/arrival.jpg","runtimeMinutes":116,"genres":["Science Fiction"],"director":"Denis Villeneuve"}
        """
    func testSearchDetailsMappingAndRequestBodies() async throws {
        let film = film
        var bodies: [[String: Any]] = []
        let service = MovieDiscoveryService { data in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            bodies.append(body)
            return Data(
                (body["operation"] as? String == "details"
                    ? film : "{\"page\":1,\"totalPages\":2,\"results\":[\(film)]}").utf8)
        }
        let blank = try await service.search(query: " \n", page: 1)
        XCTAssertTrue(blank.results.isEmpty)
        XCTAssertTrue(bodies.isEmpty)
        let page = try await service.search(query: " Arrival ", page: 1)
        XCTAssertEqual(page.results.first?.posterURL?.host, "image.tmdb.org")
        XCTAssertEqual(bodies.first?["query"] as? String, "Arrival")
        XCTAssertEqual(page.totalPages, 2)
        let details = try await service.details(id: 329865)
        XCTAssertEqual(details.id, 329865)
        XCTAssertEqual(details.runtimeMinutes, 116)
        XCTAssertEqual(bodies.last?["movieID"] as? Int, 329865)
        let invalidImage = MovieDiscoveryService { _ in
            Data(
                film.replacingOccurrences(
                    of: "https://image.tmdb.org", with: "http://untrusted.test"
                ).utf8)
        }
        let safe = try await invalidImage.details(id: 329865)
        XCTAssertNil(safe.posterURL)
    }
    func testTransportErrorsAndInvalidResponses() async {
        for (error, expected) in [
            (BackendHTTPError(status: 401, code: nil), DiscoveryFailure.expired),
            (.init(status: 429, code: nil), .rateLimited),
            (.init(status: 404, code: nil), .notFound),
            (.init(status: 503, code: "catalog_not_configured"), .notConfigured),
            (.init(status: 500, code: nil), .unavailable),
        ] {
            let service = MovieDiscoveryService { _ in throw error }
            do {
                _ = try await service.search(query: "Arrival", page: 1)
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? DiscoveryFailure, expected) }
        }
        for error in [
            SignInFailure.expired as Error, URLError(.notConnectedToInternet),
            DiscoveryFailure.notFound,
        ] {
            let service = MovieDiscoveryService { _ in throw error }
            do {
                _ = try await service.details(id: 1)
                XCTFail("Expected failure")
            } catch { XCTAssertTrue(error is DiscoveryFailure) }
        }
        let cancelled = MovieDiscoveryService { _ in throw URLError(.cancelled) }
        do {
            _ = try await cancelled.details(id: 1)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let malformed = MovieDiscoveryService { _ in Data("{}".utf8) }
        do {
            _ = try await malformed.search(query: "Arrival", page: 1)
            XCTFail("Expected invalid response")
        } catch {}
        do {
            _ = try await malformed.search(query: "Arrival", page: 0)
            XCTFail("Expected invalid page")
        } catch {}
        do {
            _ = try await malformed.search(query: String(repeating: "a", count: 201), page: 1)
            XCTFail("Expected invalid query")
        } catch {}
        do {
            _ = try await malformed.details(id: 0)
            XCTFail("Expected invalid ID")
        } catch {}
        let film = film
        let wrongID = MovieDiscoveryService { _ in Data(film.utf8) }
        do {
            _ = try await wrongID.details(id: 11)
            XCTFail("Expected identity validation")
        } catch {}
        let wrongPage = MovieDiscoveryService { _ in
            Data("{\"page\":2,\"totalPages\":1,\"results\":[]}".utf8)
        }
        do {
            _ = try await wrongPage.search(query: "Arrival", page: 1)
            XCTFail("Expected page validation")
        } catch {}
        for failure in [
            DiscoveryFailure.expired, .notConfigured, .notFound, .rateLimited, .unavailable,
        ] { XCTAssertFalse(failure.localizedDescription.isEmpty) }
    }
    func testCollectionErrorMappingRemainsFeatureSpecific() async {
        for (status, expected) in [
            (401, CollectionFailure.expired), (403, .access), (500, .unavailable),
        ] {
            let service = SupabaseCollectionService { _, _ in
                throw BackendHTTPError(status: status, code: nil)
            }
            do {
                _ = try await service.load()
                XCTFail("Expected failure")
            } catch { XCTAssertEqual(error as? CollectionFailure, expected) }
        }
        let expired = SupabaseCollectionService { _, _ in throw SignInFailure.expired }
        do {
            _ = try await expired.load()
            XCTFail("Expected failure")
        } catch { XCTAssertEqual(error as? CollectionFailure, .expired) }
        let cancelled = SupabaseCollectionService { _, _ in throw CancellationError() }
        do {
            _ = try await cancelled.load()
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
