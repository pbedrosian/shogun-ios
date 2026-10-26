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
}
#endif
