import XCTest
import Auth
@testable import Shogun

final class MemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
    func expireSessions() throws -> Int {
        var count = 0
        lock.lock(); defer { lock.unlock() }
        for (key, value) in values {
            if var json = try? JSONSerialization.jsonObject(with: value) as? [String: Any], json["accessToken"] != nil {
                count += 1; json["expiresAt"] = 1; values[key] = try JSONSerialization.data(withJSONObject: json)
            }
        }
        return count
    }
}
final class AuthURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@MainActor final class AuthSDKTests: XCTestCase {
    let userID = "10000000-0000-0000-0000-000000000001"
    let libraryID = "20000000-0000-0000-0000-000000000001"
    var user: [String: Any] { ["id":userID,"aud":"authenticated","email":"owner@example.test","app_metadata":[:],"user_metadata":[:],"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","is_anonymous":false] }
    func json(_ value: Any) -> Data { try! JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) }
    var token: Data { json(["access_token":"test-access-token","refresh_token":"test-refresh-token","token_type":"bearer","expires_in":3600,"expires_at":Date().timeIntervalSince1970 + 3600,"user":user]) }
    func service(_ storage: MemoryAuthStorage = MemoryAuthStorage()) throws -> SupabaseAuthService {
        let config = try AuthConfiguration(info: ["SUPABASE_URL":"https://auth.example.test","SUPABASE_PUBLISHABLE_KEY":"sb_publishable_test"], allowLocalHTTP: false)
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [AuthURLProtocol.self]
        return SupabaseAuthService(config: config, storage: storage, session: URLSession(configuration: sessionConfig))
    }
    func installHandler() {
        let token = token, user = json(user), id = json(libraryID), library = json([["id":libraryID,"name":"My Library"]])
        AuthURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
            switch request.url!.path {
            case "/auth/v1/token": return (200, token)
            case "/auth/v1/user": return (200, user)
            case "/rest/v1/rpc/bootstrap_account":
                XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token"); return (200, id)
            case "/rest/v1/libraries": return (200, library)
            case "/auth/v1/signup": return (200, user)
            default: return (200, Data("{}".utf8))
            }
        }
    }
    func testOfficialSDKPersistsRestoresRefreshesAndSignsOutOffline() async throws {
        installHandler(); let storage = MemoryAuthStorage()
        var first: SupabaseAuthService? = try service(storage)
        let initial = try await first!.restore(); XCTAssertNil(initial)
        let signedIn = try await first!.signIn(email: "owner@example.test", password: "password")
        XCTAssertEqual(signedIn.id.uuidString.lowercased(), userID); XCTAssertEqual(signedIn.libraryName, "My Library")
        first = nil
        XCTAssertGreaterThan(try storage.expireSessions(), 0)
        let restored = try service(storage)
        let account = try await restored.restore(); XCTAssertEqual(account, signedIn)
        AuthURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { try await restored.signOut() } catch { XCTAssertEqual(error as? SignInFailure, .network) }
        installHandler(); let afterSignOut = try service(storage)
        let cleared = try await afterSignOut.restore(); XCTAssertNil(cleared)
    }
    func testConfirmationRecoveryCallbackAndPasswordUpdate() async throws {
        installHandler(); let storage = MemoryAuthStorage(); let first = try service(storage)
        let confirmation = try await first.signUp(email: "owner@example.test", password: "password"); XCTAssertNil(confirmation)
        try await first.recover(email: "owner@example.test")
        let resumed = try service(storage)
        let signal = Task { for await event in resumed.signals { if case .recovery = event { return true } }; return false }
        let account = try await resumed.callback(URL(string: "shogun://auth-callback?code=test-code")!)
        let recovered = await signal.value; XCTAssertTrue(recovered); XCTAssertEqual(account.email, "owner@example.test")
        let updated = try await resumed.changePassword("new-password"); XCTAssertEqual(updated, account)
        do { _ = try await resumed.callback(URL(string: "https://evil.test")!); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .callback) }
        do { _ = try await resumed.callback(AuthConfiguration.redirect); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .callback) }
    }
    func testDeleteAccountUsesAuthenticatedEndpointAndClearsPersistedSession() async throws {
        installHandler(); let storage = MemoryAuthStorage(); let first = try service(storage)
        _ = try await first.signIn(email: "owner@example.test", password: "password")
        let normal = AuthURLProtocol.handler!
        AuthURLProtocol.handler = { request in
            if request.url!.path == "/functions/v1/delete-account" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
                return (403, Data("{}".utf8))
            }
            return try normal(request)
        }
        do { try await first.deleteAccount(password: "wrong"); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .credentials) }
        let stillSignedIn = try await first.restore(); XCTAssertNotNil(stillSignedIn)
        AuthURLProtocol.handler = { request in
            request.url!.path == "/functions/v1/delete-account" ? (200, Data(#"{"deleted":true}"#.utf8)) : try normal(request)
        }
        try await first.deleteAccount(password: "password")
        let fresh = try service(storage); let restored = try await fresh.restore(); XCTAssertNil(restored)
    }
    func testSafeFailuresAndMissingLibrary() async throws {
        installHandler(); let first = try service()
        AuthURLProtocol.handler = { _ in (400, Data(#"{"error_code":"invalid_credentials","msg":"private diagnostic"}"#.utf8)) }
        do { _ = try await first.signIn(email: "a@b.test", password: "password"); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .credentials) }
        installHandler(); let handler = AuthURLProtocol.handler!
        AuthURLProtocol.handler = { request in request.url!.path == "/rest/v1/libraries" ? (200, Data("[]".utf8)) : try handler(request) }
        do { _ = try await first.signIn(email: "a@b.test", password: "password"); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .unavailable) }
        XCTAssertTrue(SupabaseAuthService.failure(CancellationError()) is CancellationError)
        XCTAssertEqual(SupabaseAuthService.failure(URLError(.timedOut)) as? SignInFailure, .network)
        XCTAssertEqual(SupabaseAuthService.failure(AuthError.sessionMissing) as? SignInFailure, .expired)
        XCTAssertEqual(SupabaseAuthService.failure(NSError(domain: "private", code: 1)) as? SignInFailure, .unavailable)
    }
    func testAuthenticatedTransportBindsSessionAndPreservesHTTPFailures() async throws {
        installHandler()
        let service = try service()
        do { _ = try await service.backendClient(for: UUID()).rpc("collection_snapshot", body: Data()); XCTFail("No session") }
        catch { XCTAssertEqual(error as? SignInFailure, .expired) }
        _ = try await service.signIn(email: "owner@example.test", password: "password")
        do { _ = try await service.backendClient(for: UUID()).rpc("collection_snapshot", body: Data()); XCTFail("Wrong account") }
        catch { XCTAssertEqual(error as? SignInFailure, .expired) }
        for status in [401, 403, 500] {
            AuthURLProtocol.handler = { _ in (status, Data("{}".utf8)) }
            do { _ = try await service.backendClient(for: UUID(uuidString: userID)!).rpc("collection_snapshot", body: Data()); XCTFail("Expected failure") }
            catch { XCTAssertEqual((error as? BackendHTTPError)?.status, status) }
        }
        AuthURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token")
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/collection_snapshot")
            return (200, Data("{}".utf8))
        }
        let data = try await service.backendClient(for: UUID(uuidString: userID)!).rpc("collection_snapshot", body: Data("{}".utf8))
        XCTAssertEqual(data, Data("{}".utf8))
    }

}
