#if SHOGUN_LIVE_AUTH
import XCTest
import Auth
@testable import Shogun

/// Explicit local integration run only; never requires a hosted account or admin key.
@MainActor final class LiveAuthTests: XCTestCase {
    final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    func testLocalRecoveryEmailPKCEAndPasswordUpdate() async throws {
        let config = try AuthConfiguration(info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: true)
        guard config.url.absoluteString == "http://127.0.0.1:54321" else { throw SignInFailure.configuration }
        func messages() async throws -> [[String: Any]] {
            let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54324/api/v1/messages")!)
            return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["messages"] as? [[String: Any]] ?? []
        }
        let previous = Set(try await messages().compactMap { $0["ID"] as? String })
        let storage = SecureAuthStorage(service: "shogun.recovery.integration.\(UUID())")
        let first = SupabaseAuthService(config: config, storage: storage)
        try await first.recover(email: "owner@shogun.test")
        var messageID: String?
        for _ in 0..<30 {
            messageID = try await messages().compactMap { $0["ID"] as? String }.first { !previous.contains($0) }
            if messageID != nil { break }; try await Task.sleep(for: .milliseconds(200))
        }
        let id = try XCTUnwrap(messageID)
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54324/api/v1/message/\(id)")!)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let html = try XCTUnwrap(json["HTML"] as? String)
        let regex = try NSRegularExpression(pattern: #"href="([^"]+)""#)
        let match = try XCTUnwrap(regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)))
        let range = try XCTUnwrap(Range(match.range(at: 1), in: html))
        let link = try XCTUnwrap(URL(string: String(html[range]).replacingOccurrences(of: "&amp;", with: "&")))
        XCTAssertEqual(link.host, "127.0.0.1")
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        let (_, response) = try await session.data(from: link)
        let redirect = try XCTUnwrap((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"))
        let url = try XCTUnwrap(URL(string: redirect)); XCTAssertTrue(AuthConfiguration.acceptsCallback(url))
        let resumed = SupabaseAuthService(config: config, storage: storage)
        _ = try await resumed.callback(url)
        // Use the fixture's existing password, so this check does not change its credentials.
        // GoTrue rejects reusing it; that proves the recovery session reached authenticated update.
        do { _ = try await resumed.changePassword("Shogun-local-only-25!"); XCTFail("Expected same-password rejection") }
        catch { XCTAssertEqual(error as? SignInFailure, .unavailable) }
        try await resumed.signOut()
    }
    func testLocalSignInKeychainRestorationAndAccountIsolation() async throws {
        let config = try AuthConfiguration(info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: true)
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:54321")
        guard config.url.absoluteString == "http://127.0.0.1:54321" else { throw SignInFailure.configuration }
        let storage = SecureAuthStorage(service: "shogun.integration.\(UUID())")
        let first = SupabaseAuthService(config: config, storage: storage)
        let owner = try await first.signIn(email: "owner@shogun.test", password: "Shogun-local-only-25!")
        XCTAssertEqual(owner.email, "owner@shogun.test")
        let second = SupabaseAuthService(config: config, storage: storage)
        let restored = try await second.restore(); XCTAssertEqual(restored, owner)
        try await second.signOut()
        let third = SupabaseAuthService(config: config, storage: storage)
        let empty = try await third.restore(); XCTAssertNil(empty)
        let outsider = try await third.signIn(email: "outsider@shogun.test", password: "Shogun-local-only-25!")
        XCTAssertNotEqual(outsider.id, owner.id); XCTAssertNotEqual(outsider.libraryID, owner.libraryID)
        try await third.signOut()
    }
    func testLocalCollectionReloadAndAccountBinding() async throws {
        let config = try AuthConfiguration(info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: true)
        guard config.url.absoluteString == "http://127.0.0.1:54321" else { throw SignInFailure.configuration }
        let storage = SecureAuthStorage(service: "shogun.collection.integration.\(UUID())")
        let first = SupabaseAuthService(config: config, storage: storage)
        let owner = try await first.signIn(email: "owner@shogun.test", password: "Shogun-local-only-25!")
        let collection = SupabaseCollectionService { name, body in
            try await first.backendClient(for: owner.id).rpc(name, body: body)
        }
        let snapshot = try await collection.load()
        XCTAssertTrue(snapshot.libraries.contains { $0.id == owner.libraryID.uuidString.lowercased() })
        XCTAssertTrue(snapshot.memberships.allSatisfy { $0.userID == owner.id.uuidString.lowercased() })
        let relaunched = SupabaseAuthService(config: config, storage: storage)
        let restored = try await relaunched.restore(); XCTAssertEqual(restored?.id, owner.id)
        let second = SupabaseCollectionService { name, body in
            try await relaunched.backendClient(for: owner.id).rpc(name, body: body)
        }
        let reloaded = try await second.load()
        XCTAssertEqual(Set(snapshot.libraries.map(\.id)), Set(reloaded.libraries.map(\.id)))
        XCTAssertEqual(Set(snapshot.copies.map(\.id)), Set(reloaded.copies.map(\.id)))
        _ = try await relaunched.signIn(email: "outsider@shogun.test", password: "Shogun-local-only-25!")
        do { _ = try await second.load(); XCTFail("Old collection must reject another account's session") }
        catch { XCTAssertEqual(error as? CollectionFailure, .expired) }
        try await relaunched.signOut()
        try await first.signOut()
    }

    func testLocalTMDBSearchDetailsAndNoCollectionMutation() async throws {
        let config = try AuthConfiguration(info: Bundle.main.infoDictionary ?? [:], allowLocalHTTP: true)
        guard config.url.absoluteString == "http://127.0.0.1:54321" else { throw SignInFailure.configuration }
        let auth = SupabaseAuthService(config: config, storage: SecureAuthStorage(service: "shogun.discovery.integration.\(UUID())"))
        let account = try await auth.signIn(email: "owner@shogun.test", password: "Shogun-local-only-25!")
        let backend = auth.backendClient(for: account.id)
        let collections = SupabaseCollectionService { try await backend.rpc($0, body: $1) }
        let before = try await collections.load()
        let service = MovieDiscoveryService { try await backend.function("catalog", body: $0) }
        let page = try await service.search(query: "Arrival", page: 1)
        XCTAssertTrue(page.results.contains { $0.id == 329865 })
        let movie = try await service.details(id: 329865)
        XCTAssertEqual(movie.year, 2016); XCTAssertTrue((movie.runtimeMinutes ?? 0) > 0)
        XCTAssertEqual(movie.posterURL?.host, "image.tmdb.org"); XCTAssertNotNil(movie.director)
        let after = try await collections.load()
        XCTAssertEqual(Set(before.copies.map(\.id)), Set(after.copies.map(\.id)))
        XCTAssertEqual(Set(before.movies.map(\.id)), Set(after.movies.map(\.id)))
        try await auth.signOut()
    }

}
#endif
