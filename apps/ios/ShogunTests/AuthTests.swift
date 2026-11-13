import XCTest
@testable import Shogun

@MainActor final class AuthStoreTests: XCTestCase {
    final class Service: AuthServicing {
        let signals: AsyncStream<AuthSignal>
        let continuation: AsyncStream<AuthSignal>.Continuation
        var appleDeletionAvailable = false
        func deleteAccountWithApplePassword(_ password: String) async throws {
            calls += 1
            if let failure { throw failure }
            restored = nil
        }
        func deleteAccountWithApple() async throws {
            calls += 1
            if slow { try await Task.sleep(for: .seconds(30)) }
            if let failure { throw failure }
            restored = nil
        }
        var appleIdentityLinkingAvailable = false
        var linkedAccount: AuthAccount?
        func linkAppleIdentity() async throws -> AuthAccount {
            calls += 1
            if slow { try await Task.sleep(for: .seconds(30)) }
            if let failure { throw failure }
            var linked = linkedAccount ?? Self.account
            linked.appleIdentityLinked = true
            return linked
        }
        var appleSignInAvailable = true
        func signInWithApple() async throws -> AuthAccount {
            try await signIn(email: "user@example.test", password: "unused")
        }
        var googleSignInAvailable = true
        var restored: AuthAccount?
        var failure: Error?
        var confirmations = true
        var slow = false
        var calls = 0
        var signOuts = 0
        static let account = AuthAccount(id: UUID(), email: "user@example.test", libraryID: UUID(), libraryName: "Personal library")
        init() { (signals, continuation) = AsyncStream.makeStream() }
        func restore() async throws -> AuthAccount? { if let failure { throw failure }; return restored }
        func signIn(email: String, password: String) async throws -> AuthAccount {
            calls += 1
            if slow { try await Task.sleep(for: .seconds(30)) }
            if let failure { throw failure }; return Self.account
        }
        func signInWithGoogle() async throws -> AuthAccount {
            try await signIn(email: "user@example.test", password: "unused")
        }
        func signUp(email: String, password: String) async throws -> AuthAccount? { confirmations ? nil : Self.account }
        func recover(email: String) async throws { if let failure { throw failure } }
        func changePassword(_ password: String) async throws -> AuthAccount { Self.account }
        func callback(_ url: URL) async throws -> AuthAccount { continuation.yield(.recovery); return Self.account }
        func deleteAccountWithGoogle() async throws {
            calls += 1
            if slow { try await Task.sleep(for: .seconds(30)) }
            if let failure { throw failure }
            restored = nil
        }
        func deleteAccount(password: String) async throws { if let failure { throw failure }; restored = nil }
        func signOut() async throws { signOuts += 1; continuation.yield(.signedOut); if let failure { throw failure } }
    }
    func settle(_ store: AuthStore) async {
        for _ in 0..<200 { if !store.isBusy { return }; await Task.yield() }
        XCTFail("Authentication did not settle")
    }
    func testApplePasswordFallbackPreservesOnFailureAndShowsManualRemovalAfterSuccess() async {
        let service = Service()
        var account = Service.account
        account.appleIdentityLinked = true
        service.restored = account
        service.appleDeletionAvailable = true
        let store = AuthStore(service: service)
        store.start()
        await settle(store)
        store.deleteAccountWithApplePassword("")
        XCTAssertEqual(service.calls, 0)
        service.failure = SignInFailure.credentials
        store.deleteAccountWithApplePassword("wrong")
        await settle(store)
        XCTAssertEqual(store.account, account)
        service.failure = nil
        store.deleteAccountWithApplePassword("password")
        await settle(store)
        XCTAssertNil(store.account)
        XCTAssertTrue(store.message?.contains("Remove Shogun from Sign in with Apple") == true)
    }
    func testAppleDeletionKeepsMainAccountOnFailureAndCancellation() async {
        let service = Service()
        var account = Service.account
        account.appleIdentityLinked = true
        service.restored = account
        let store = AuthStore(service: service)
        store.start()
        await settle(store)
        store.deleteAccountWithApple()
        XCTAssertEqual(service.calls, 0)
        service.appleDeletionAvailable = true
        service.failure = SignInFailure.appleReauthentication
        store.deleteAccountWithApple()
        await settle(store)
        XCTAssertEqual(store.account, account)
        service.failure = nil
        service.slow = true
        store.deleteAccountWithApple()
        store.cancel()
        for _ in 0..<40 { await Task.yield() }
        await settle(store)
        XCTAssertEqual(store.account, account)
        XCTAssertEqual(service.signOuts, 0)
        service.slow = false
        store.deleteAccountWithApple()
        await settle(store)
        XCTAssertNil(store.account)
    }
    func testAppleLinkingKeepsCurrentAccountOnFailureCancellationAndMismatchedResult() async {
        let service = Service()
        service.restored = Service.account
        let store = AuthStore(service: service)
        store.start()
        await settle(store)
        store.linkAppleIdentity()
        XCTAssertEqual(service.calls, 0)
        service.appleIdentityLinkingAvailable = true
        service.failure = SignInFailure.identityLinking
        store.linkAppleIdentity()
        await settle(store)
        XCTAssertEqual(store.account, Service.account)
        XCTAssertNotNil(store.error)
        service.failure = nil
        service.slow = true
        store.linkAppleIdentity()
        store.cancel()
        for _ in 0..<40 { await Task.yield() }
        await settle(store)
        XCTAssertEqual(store.account, Service.account)
        XCTAssertEqual(service.signOuts, 0)
        service.slow = false
        service.linkedAccount = AuthAccount(
            id: UUID(), email: "other@example.test", libraryID: UUID(), libraryName: "Other")
        store.linkAppleIdentity()
        await settle(store)
        XCTAssertEqual(store.account, Service.account)
        service.linkedAccount = AuthAccount(
            id: Service.account.id, email: Service.account.email, libraryID: UUID(),
            libraryName: "Other")
        store.linkAppleIdentity()
        await settle(store)
        XCTAssertEqual(store.account, Service.account)
        service.linkedAccount = nil
        store.linkAppleIdentity()
        await settle(store)
        XCTAssertEqual(store.account?.id, Service.account.id)
        XCTAssertEqual(store.account?.libraryID, Service.account.libraryID)
        XCTAssertTrue(store.account?.appleIdentityLinked == true)
        let calls = service.calls
        store.linkAppleIdentity()
        XCTAssertEqual(service.calls, calls)
    }
    func testAppleLayoutPreviewCannotStartSignIn() {
        let service = Service()
        service.appleSignInAvailable = false
        let hidden = AuthStore(service: service)
        XCTAssertFalse(hidden.appleSignInVisible)
        let preview = AuthStore(service: service, previewAppleSignIn: true)
        XCTAssertTrue(preview.appleSignInVisible)
        XCTAssertFalse(preview.appleSignInAvailable)
        preview.signInWithApple()
        XCTAssertEqual(service.calls, 0)
        XCTAssertFalse(preview.isBusy)
        XCTAssertNil(preview.account)
    }
    func testAppleAvailabilityFailureSuccessAndCancellation() async {
        let service = Service()
        let store = AuthStore(service: service)
        service.appleSignInAvailable = false
        XCTAssertFalse(store.appleSignInAvailable)
        store.signInWithApple()
        XCTAssertEqual(service.calls, 0)
        service.appleSignInAvailable = true
        service.failure = SignInFailure.network
        store.signInWithApple()
        await settle(store)
        XCTAssertNil(store.account)
        XCTAssertEqual(store.error, SignInFailure.network.localizedDescription)
        service.failure = nil
        store.signInWithApple()
        await settle(store)
        XCTAssertEqual(store.account, Service.account)
        store.signOut()
        await settle(store)
        service.slow = true
        store.signInWithApple()
        let calls = service.calls
        store.signInWithApple()
        XCTAssertEqual(service.calls, calls)
        store.cancel()
        for _ in 0..<40 { await Task.yield() }
        await settle(store)
        XCTAssertNil(store.account)
        XCTAssertNil(store.error)
    }
    func testGoogleSignInAvailabilitySuccessFailureAndCancellation() async {
        let service = Service()
        let store = AuthStore(service: service)
        service.googleSignInAvailable = false
        XCTAssertFalse(store.googleSignInAvailable)
        store.signInWithGoogle()
        XCTAssertEqual(service.calls, 0)
        service.googleSignInAvailable = true
        service.failure = SignInFailure.network
        store.signInWithGoogle(); await settle(store)
        XCTAssertNil(store.account)
        XCTAssertEqual(store.error, SignInFailure.network.localizedDescription)
        service.failure = nil
        store.signInWithGoogle(); await settle(store)
        XCTAssertEqual(store.account, Service.account)
        store.signOut(); await settle(store)
        service.slow = true
        store.signInWithGoogle()
        store.signInWithGoogle()
        XCTAssertTrue(store.isBusy)
        store.cancel()
        for _ in 0..<40 { await Task.yield() }
        await settle(store)
        XCTAssertNil(store.account)
        XCTAssertNil(store.error)
    }
    func testRestoreAndRetryDoesNotLoseOfflineSession() async {
        let service = Service(); service.failure = SignInFailure.network
        let store = AuthStore(service: service); store.start(); await settle(store)
        XCTAssertEqual(store.error, SignInFailure.network.localizedDescription); XCTAssertFalse(store.isRestoring)
        service.failure = nil; service.restored = Service.account
        store.retryRestore(); await settle(store); XCTAssertEqual(store.account, Service.account)
        store.start(); XCTAssertFalse(store.isBusy)
    }
    func testCallbackDuringColdLaunchIsProcessedAfterRestoration() async {
        let service = Service(); let store = AuthStore(service: service)
        store.start(); store.handle(AuthConfiguration.redirect)
        await settle(store)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.account, Service.account); XCTAssertTrue(store.needsPasswordUpdate)
    }
    func testGoogleDeletionPreservesMainAccountOnFailureAndCancellation() async {
        let service = Service()
        var account = Service.account
        account.googleIdentityLinked = true
        service.restored = account
        let store = AuthStore(service: service)
        store.start(); await settle(store)
        XCTAssertTrue(store.googleDeletionAvailable)
        service.failure = SignInFailure.reauthentication
        store.deleteAccountWithGoogle(); await settle(store)
        XCTAssertEqual(store.account, account)
        XCTAssertNotNil(store.error)
        service.failure = nil
        service.slow = true
        store.deleteAccountWithGoogle(); store.cancel()
        for _ in 0..<40 { await Task.yield() }
        await settle(store)
        XCTAssertEqual(store.account, account)
        XCTAssertNil(store.error)
        XCTAssertEqual(service.signOuts, 0)
        service.slow = false
        store.deleteAccountWithGoogle(); await settle(store)
        XCTAssertNil(store.account)
        XCTAssertEqual(store.message, "Your account has been deleted.")
    }
    func testDeletionKeepsAccountOnFailureAndClearsItOnlyAfterSuccess() async {
        let service = Service(); service.restored = Service.account
        let store = AuthStore(service: service); store.start(); await settle(store)
        store.deleteAccount(password: ""); XCTAssertNotNil(store.error); XCTAssertEqual(store.account, Service.account)
        service.failure = SignInFailure.credentials
        store.deleteAccount(password: "wrong"); await settle(store)
        XCTAssertEqual(store.account, Service.account); XCTAssertEqual(store.error, SignInFailure.credentials.localizedDescription)
        service.failure = nil; store.deleteAccount(password: "password"); await settle(store)
        XCTAssertNil(store.account); XCTAssertEqual(store.message, "Your account has been deleted.")
        store.deleteAccount(password: "password"); XCTAssertFalse(store.isBusy)
    }
    func testMissingConfigurationAndExplicitDemo() async {
        let store = AuthStore(service: nil); store.start(); await settle(store)
        XCTAssertNil(store.account); XCTAssertFalse(store.isDemo); XCTAssertFalse(store.configured)
        store.submit(form: .signIn, email: "a@b.test", password: "password")
        XCTAssertEqual(store.error, SignInFailure.configuration.localizedDescription)
        store.handle(AuthConfiguration.redirect); XCTAssertNotNil(store.error)
        let demo = AuthStore(service: nil, demo: true); demo.start(); XCTAssertTrue(demo.isDemo); XCTAssertFalse(demo.isRestoring)
        demo.leaveDemo(); XCTAssertFalse(demo.isDemo)
    }
    func testValidationAndCredentialFailure() async {
        let service = Service(); let store = AuthStore(service: service); store.start(); await settle(store)
        store.submit(form: .signIn, email: "bad", password: "x"); XCTAssertNotNil(store.error)
        store.submit(form: .signIn, email: "a@b.test", password: ""); XCTAssertEqual(store.error, "Enter your password.")
        store.submit(form: .signUp, email: "a@b.test", password: "short"); XCTAssertEqual(store.error, SignInFailure.password.localizedDescription)
        service.failure = SignInFailure.credentials
        store.submit(form: .signIn, email: " a@b.test ", password: "password"); await settle(store)
        XCTAssertNil(store.account); XCTAssertEqual(store.error, SignInFailure.credentials.localizedDescription)
        store.clearFeedback(); XCTAssertNil(store.error)
        service.failure = NSError(domain: "must not expose private server details", code: 1)
        store.submit(form: .signIn, email: "a@b.test", password: "password"); await settle(store)
        XCTAssertEqual(store.error, SignInFailure.unavailable.localizedDescription)
    }
    func testSignInAndSignOutClearPrivateStateEvenOnNetworkFailure() async {
        let service = Service(); let store = AuthStore(service: service); store.start(); await settle(store)
        store.submit(form: .signIn, email: "a@b.test", password: "password"); await settle(store)
        XCTAssertEqual(store.account, Service.account)
        service.failure = SignInFailure.network; store.signOut(); XCTAssertNil(store.account); await settle(store)
        XCTAssertNil(store.account); XCTAssertFalse(store.isDemo); XCTAssertEqual(service.signOuts, 1)
    }
    func testConfirmationAndRecoveryAndPasswordUpdate() async {
        let service = Service(); let store = AuthStore(service: service); store.start(); await settle(store)
        store.submit(form: .signUp, email: "a@b.test", password: "password"); await settle(store)
        XCTAssertNil(store.account); XCTAssertTrue(store.message?.contains("confirm") == true)
        service.confirmations = false
        store.submit(form: .signUp, email: "a@b.test", password: "password"); await settle(store); XCTAssertNotNil(store.account)
        store.submit(form: .recover, email: "a@b.test", password: ""); await settle(store)
        XCTAssertTrue(store.message?.contains("If this email") == true)
        store.handle(URL(string: "https://evil.test?code=private")!); XCTAssertFalse(store.isBusy)
        store.handle(AuthConfiguration.redirect); await settle(store)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.needsPasswordUpdate)
        store.updatePassword("short"); XCTAssertNotNil(store.error)
        store.updatePassword("new-password"); await settle(store); XCTAssertFalse(store.needsPasswordUpdate)
        XCTAssertEqual(store.message, "Your password has been updated.")
        service.continuation.yield(.signedOut)
        for _ in 0..<20 { await Task.yield() }; XCTAssertNil(store.account)
    }
    func testCancelledRequestCannotPublishEvenIfServiceReturnsSuccess() async {
        let service = Service()
        let store = AuthStore(service: service); store.start(); await settle(store)
        store.submit(form: .signIn, email: "a@b.test", password: "password")
        store.cancel() // The fake returns success without checking cancellation.
        await settle(store)
        XCTAssertNil(store.account); XCTAssertNil(store.error); XCTAssertEqual(service.signOuts, 1)
    }
    func testCancellationAndDuplicateRequestsCannotRestoreAccount() async {
        let service = Service(); service.slow = true
        let store = AuthStore(service: service); store.start(); await settle(store)
        store.submit(form: .signIn, email: "a@b.test", password: "password")
        store.submit(form: .signIn, email: "a@b.test", password: "password"); XCTAssertFalse(store.isDemo)
        for _ in 0..<10 { await Task.yield() }
        store.cancel(); await settle(store); XCTAssertNil(store.account); XCTAssertNil(store.error)
        XCTAssertEqual(service.calls, 1); XCTAssertEqual(service.signOuts, 1)
        store.cancel(); XCTAssertFalse(store.isBusy)
    }
}

final class AuthConfigurationTests: XCTestCase {
    func config(_ url: String, _ key: String = "sb_publishable_test", local: Bool = false) throws -> AuthConfiguration {
        try AuthConfiguration(info: ["SUPABASE_URL": url, "SUPABASE_PUBLISHABLE_KEY": key], allowLocalHTTP: local)
    }
    func testEndpointsAndClientKeys() throws {
        XCTAssertEqual(try config("https://example.supabase.co").key, "sb_publishable_test")
        for host in ["127.0.0.1", "192.168.1.2", "10.1.1.1", "172.16.0.1", "mac.local", "localhost"] {
            XCTAssertNoThrow(try config("http://\(host):54321", local: true)); XCTAssertThrowsError(try config("http://\(host):54321"))
        }
        for url in ["http://example.com", "http://8.8.8.8", "https://user:pass@example.com", "https://example.com/path", "https://example.com?bad=1", "https://example.com#bad"] {
            XCTAssertThrowsError(try config(url, local: true))
        }
        for key in ["", "sb_secret_private", "bad", "$(MISSING)"] { XCTAssertThrowsError(try config("https://example.com", key)) }
        for role in ["anon", "service_role"] {
            let data = try JSONSerialization.data(withJSONObject: ["role": role]); let key = "header.\(data.base64EncodedString()).signature"
            if role == "anon" { XCTAssertNoThrow(try config("https://example.com", key)) }
            else { XCTAssertThrowsError(try config("https://example.com", key)) }
        }
        XCTAssertThrowsError(try AuthConfiguration(info: [:], allowLocalHTTP: true))
    }
    func testCallbackScopeAndSafeMessages() {
        let otherScheme =
            AuthConfiguration.redirect.scheme == "shogun-dev" ? "shogun" : "shogun-dev"
        XCTAssertFalse(
            AuthConfiguration.acceptsCallback(
                URL(string: "\(otherScheme)://auth-callback?code=example")!))
        XCTAssertTrue(
            AuthConfiguration.acceptsCallback(
                URL(string: "\(AuthConfiguration.redirect.absoluteString)?code=example")!))
        for url in ["https://auth-callback", "shogun://evil", "shogun://auth-callback/path", "shogun://user@auth-callback", "shogun://auth-callback:123"] { XCTAssertFalse(AuthConfiguration.acceptsCallback(URL(string: url)!)) }
        for failure in [SignInFailure.configuration, .credentials, .confirmation, .network, .expired, .password, .callback, .unavailable] { XCTAssertFalse(failure.localizedDescription.isEmpty) }
    }
}
