import XCTest
import Auth
import AuthenticationServices
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
    func service(
        _ storage: MemoryAuthStorage = MemoryAuthStorage(), google: Bool = false,
        flow: @escaping @MainActor @Sendable (URL) async throws -> URL = { _ in
            throw CancellationError()
        }
    ) throws -> SupabaseAuthService {
        let config = try AuthConfiguration(info: ["SUPABASE_URL":"https://auth.example.test","SUPABASE_PUBLISHABLE_KEY":"sb_publishable_test"], allowLocalHTTP: false)
        let sessionConfig = URLSessionConfiguration.ephemeral; sessionConfig.protocolClasses = [AuthURLProtocol.self]
        return SupabaseAuthService(
            config: config, storage: storage, session: URLSession(configuration: sessionConfig),
            googleSignInAvailable: google, googleFlow: flow)
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
    func testAppleChallengeRejectsMissingTokenAndMismatchedOrStaleState() throws {
        let challenge = try AppleSignInChallenge()
        let second = try AppleSignInChallenge()
        let request = challenge.request()
        XCTAssertEqual(request.requestedScopes, [.email])
        XCTAssertEqual(request.state, challenge.state)
        XCTAssertEqual(request.nonce?.count, 64)
        XCTAssertNotEqual(request.nonce, challenge.nonce)
        XCTAssertNotEqual(challenge.nonce, second.nonce)
        XCTAssertNotEqual(challenge.state, second.state)
        let proof = try challenge.proof(
            identityToken: Data("apple-id-token".utf8), returnedState: request.state)
        XCTAssertEqual(proof.nonce, challenge.nonce)
        XCTAssertEqual(proof.idToken, "apple-id-token")
        for state in [nil, "wrong", second.state] {
            XCTAssertThrowsError(
                try challenge.proof(identityToken: Data("token".utf8), returnedState: state))
        }
        for token in [nil, Data(), Data([0xff])] {
            XCTAssertThrowsError(
                try challenge.proof(identityToken: token, returnedState: request.state))
        }
    }
    func testAppleExchangesTokenWithRawNonceAndRestoresValidatedAccount() async throws {
        installHandler()
        let normal = AuthURLProtocol.handler!
        var exchanges = 0
        AuthURLProtocol.handler = { request in
            if request.url!.path == "/auth/v1/token" {
                exchanges += 1
                XCTAssertEqual(
                    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?
                        .first?.value, "id_token")
                let body =
                    try JSONSerialization.jsonObject(with: self.requestBody(request))
                    as! [String: Any]
                XCTAssertEqual(body["provider"] as? String, "apple")
                XCTAssertEqual(body["id_token"] as? String, "apple-id-token")
                XCTAssertEqual(body["nonce"] as? String, "raw-one-time-nonce")
            }
            return try normal(request)
        }
        let storage = MemoryAuthStorage()
        let auth = try appleService(storage) {
            AppleSignInProof(idToken: "apple-id-token", nonce: "raw-one-time-nonce")
        }
        let account = try await auth.signInWithApple()
        XCTAssertEqual(account.id.uuidString.lowercased(), userID)
        XCTAssertEqual(account.libraryID.uuidString.lowercased(), libraryID)
        XCTAssertEqual(exchanges, 1)
        let restored = try await appleService(storage) { throw CancellationError() }.restore()
        XCTAssertEqual(restored, account)
    }
    func testAppleUnavailableCancelledAndMalformedProofNeverReachBackend() async throws {
        AuthURLProtocol.handler = { _ in
            XCTFail("Unexpected backend request")
            return (500, Data())
        }
        let disabled = try service()
        XCTAssertFalse(disabled.appleSignInAvailable)
        do {
            _ = try await disabled.signInWithApple()
            XCTFail()
        } catch { XCTAssertEqual(error as? SignInFailure, .configuration) }
        for error in [CancellationError() as Error, ASAuthorizationError(.canceled)] {
            let auth = try appleService { throw error }
            do {
                _ = try await auth.signInWithApple()
                XCTFail()
            } catch { XCTAssertTrue(error is CancellationError) }
        }
        for proof in [
            AppleSignInProof(idToken: "", nonce: "nonce"),
            AppleSignInProof(idToken: "token", nonce: ""),
        ] {
            let auth = try appleService { proof }
            do {
                _ = try await auth.signInWithApple()
                XCTFail()
            } catch { XCTAssertEqual(error as? SignInFailure, .callback) }
        }
    }
    func testAppleRejectedExchangeDoesNotCreateLocalSession() async throws {
        AuthURLProtocol.handler = { request in
            XCTAssertEqual(request.url!.path, "/auth/v1/token")
            return (400, Data(#"{"code":"bad_jwt","msg":"Invalid identity token"}"#.utf8))
        }
        let storage = MemoryAuthStorage()
        let auth = try appleService(storage) {
            AppleSignInProof(idToken: "rejected", nonce: "nonce")
        }
        do {
            _ = try await auth.signInWithApple()
            XCTFail()
        } catch {}
        let restored = try await auth.restore()
        XCTAssertNil(restored)
    }
    private func appleService(
        _ storage: MemoryAuthStorage = MemoryAuthStorage(),
        flow: @escaping @MainActor @Sendable () async throws -> AppleSignInProof
    ) throws -> SupabaseAuthService {
        let config = try AuthConfiguration(
            info: [
                "SUPABASE_URL": "https://auth.example.test",
                "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_test",
            ], allowLocalHTTP: false)
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [AuthURLProtocol.self]
        return SupabaseAuthService(
            config: config, storage: storage, session: URLSession(configuration: session),
            appleSignInAvailable: true, appleFlow: flow)
    }
    nonisolated private func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
    func testGoogleUsesPKCEDevCallbackAndRestoresExistingAccount() async throws {
        installHandler()
        let normal = AuthURLProtocol.handler!
        AuthURLProtocol.handler = { request in
            if request.url!.path == "/auth/v1/token" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                    .queryItems!
                XCTAssertEqual(query.first(where: { $0.name == "grant_type" })?.value, "pkce")
            }
            return try normal(request)
        }
        let storage = MemoryAuthStorage()
        let auth = try service(storage, google: true) { url in
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.host, "auth.example.test")
            XCTAssertEqual(components.path, "/auth/v1/authorize")
            let items = components.queryItems!
            XCTAssertEqual(items.first(where: { $0.name == "provider" })?.value, "google")
            XCTAssertEqual(
                items.first(where: { $0.name == "redirect_to" })?.value,
                AuthConfiguration.redirect.absoluteString)
            XCTAssertEqual(
                items.first(where: { $0.name == "code_challenge_method" })?.value, "s256")
            XCTAssertFalse(items.first(where: { $0.name == "code_challenge" })!.value!.isEmpty)
            return URL(
                string: "\(AuthConfiguration.redirect.absoluteString)?code=google-test-code")!
        }
        let account = try await auth.signInWithGoogle()
        XCTAssertEqual(account.id.uuidString.lowercased(), userID)
        XCTAssertEqual(account.libraryID.uuidString.lowercased(), libraryID)
        let restored = try await service(storage).restore()
        XCTAssertEqual(restored, account)
    }
    func testGoogleRejectsOtherAppCallbackBeforeExchangingCode() async throws {
        installHandler()
        AuthURLProtocol.handler = { _ in
            XCTFail("Untrusted callback must not make an API request"); return (400, Data())
        }
        let other = AuthConfiguration.redirect.scheme == "shogun-dev" ? "shogun" : "shogun-dev"
        let auth = try service(google: true) { _ in
            URL(string: "\(other)://auth-callback?code=bad")!
        }
        do { _ = try await auth.signInWithGoogle(); XCTFail() } catch {
            XCTAssertEqual(error as? SignInFailure, .callback)
        }
    }
    func testGoogleDisabledAndCancellationDoNotCreateSession() async throws {
        let disabled = try service()
        XCTAssertFalse(disabled.googleSignInAvailable)
        do { _ = try await disabled.signInWithGoogle(); XCTFail() } catch {
            XCTAssertEqual(error as? SignInFailure, .configuration)
        }
        let cancelled = try service(google: true)
        do { _ = try await cancelled.signInWithGoogle(); XCTFail() } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let restored = try await cancelled.restore()
        XCTAssertNil(restored)
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
        let account = try await resumed.callback(
            URL(string: "\(AuthConfiguration.redirect.absoluteString)?code=test-code")!)
        let recovered = await signal.value; XCTAssertTrue(recovered); XCTAssertEqual(account.email, "owner@example.test")
        let updated = try await resumed.changePassword("new-password"); XCTAssertEqual(updated, account)
        do { _ = try await resumed.callback(URL(string: "https://evil.test")!); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .callback) }
        do { _ = try await resumed.callback(AuthConfiguration.redirect); XCTFail() } catch { XCTAssertEqual(error as? SignInFailure, .callback) }
    }
    func testGoogleDeletionUsesSeparateProofAndClearsMainSessionOnlyOnSuccess() async throws {
        for outcome in ["wrong-account", "cancel", "failure", "success"] {
            let storage = MemoryAuthStorage()
            let owner = userID
            let freshID =
                outcome == "wrong-account" ? "10000000-0000-0000-0000-000000000099" : owner
            func googleUser(_ id: String) -> [String: Any] {
                var value = user
                value["id"] = id
                value["identities"] = [
                    [
                        "id": "google-subject",
                        "identity_id": "30000000-0000-0000-0000-000000000001", "user_id": id,
                        "provider": "google",
                    ]
                ]
                return value
            }
            let originalUser = json(googleUser(owner)), proofUser = json(googleUser(freshID))
            let mainToken = json([
                "access_token": "test-access-token", "refresh_token": "main-refresh",
                "token_type": "bearer", "expires_in": 3600,
                "expires_at": Date().timeIntervalSince1970 + 3600, "user": googleUser(owner),
            ])
            let proofToken = json([
                "access_token": "proof-access", "refresh_token": "proof-refresh",
                "token_type": "bearer", "expires_in": 3600,
                "expires_at": Date().timeIntervalSince1970 + 3600, "user": googleUser(freshID),
            ])
            installHandler()
            let normal = AuthURLProtocol.handler!
            var deletionRequests = 0
            var proofRevoked = false
            AuthURLProtocol.handler = { request in
                let path = request.url!.path
                if path == "/auth/v1/token" {
                    return (200, request.url!.query!.contains("pkce") ? proofToken : mainToken)
                }
                if path == "/auth/v1/user" {
                    return (
                        200,
                        request.value(forHTTPHeaderField: "Authorization") == "Bearer proof-access"
                            ? proofUser : originalUser
                    )
                }
                if path == "/functions/v1/delete-account" {
                    deletionRequests += 1
                    XCTAssertEqual(
                        request.value(forHTTPHeaderField: "Authorization"),
                        "Bearer test-access-token")
                    return (outcome == "failure" ? 403 : 200, Data(#"{"deleted":true}"#.utf8))
                }
                if path == "/auth/v1/logout" {
                    if request.value(forHTTPHeaderField: "Authorization") == "Bearer proof-access" {
                        proofRevoked = true
                    }
                    return (204, Data())
                }
                return try normal(request)
            }
            let auth = try service(storage, google: true) { _ in
                if outcome == "cancel" { throw CancellationError() }
                return URL(string: "\(AuthConfiguration.redirect.absoluteString)?code=delete-test")!
            }
            let before = try await auth.signIn(email: "owner@example.test", password: "password")
            XCTAssertTrue(before.googleIdentityLinked)
            if outcome == "success" {
                try await auth.deleteAccountWithGoogle()
                let after = try await auth.restore()
                XCTAssertNil(after)
            } else {
                do { try await auth.deleteAccountWithGoogle(); XCTFail() } catch {
                    if outcome == "cancel" {
                        XCTAssertTrue(error is CancellationError)
                    } else {
                        XCTAssertEqual(error as? SignInFailure, .reauthentication)
                    }
                }
                let after = try await auth.restore()
                XCTAssertEqual(after, before)
            }
            XCTAssertEqual(deletionRequests, outcome == "success" || outcome == "failure" ? 1 : 0)
            if outcome != "cancel" { XCTAssertTrue(proofRevoked) }
        }
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
