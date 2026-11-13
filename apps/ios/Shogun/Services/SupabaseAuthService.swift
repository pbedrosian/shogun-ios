import Auth
import AuthenticationServices
import Foundation
import UIKit

@MainActor final class SupabaseAuthService: AuthServicing {
    let appleSignInAvailable: Bool
    private let appleFlow: @MainActor @Sendable () async throws -> AppleSignInProof
    let googleSignInAvailable: Bool
    private let googleFlow: @MainActor @Sendable (URL) async throws -> URL
    let signals: AsyncStream<AuthSignal>
    private let client: AuthClient
    private let config: AuthConfiguration
    private let authSession: URLSession
    private let http: BackendHTTPClient
    private let storage: any AuthLocalStorage
    private let continuation: AsyncStream<AuthSignal>.Continuation
    private var recoveryKey: String { "shogun-recovery-\(config.url.absoluteString)" }
    private var observer: Task<Void, Never>?

    init(
        config: AuthConfiguration, storage: any AuthLocalStorage = SecureAuthStorage(),
        session: URLSession = .shared,
        appleSignInAvailable: Bool = false,
        appleFlow: @escaping @MainActor @Sendable () async throws -> AppleSignInProof = {
            try await AppleAuthenticationFlow().authenticate()
        },
        googleSignInAvailable: Bool = false,
        googleFlow: @escaping @MainActor @Sendable (URL) async throws -> URL = {
            try await GoogleAuthenticationFlow().authenticate($0)
        }
    ) {
        self.appleSignInAvailable = appleSignInAvailable
        self.appleFlow = appleFlow
        self.googleSignInAvailable = googleSignInAvailable
        self.googleFlow = googleFlow
        self.authSession = session
        self.config = config
        self.http = BackendHTTPClient(config: config, session: session)
        self.storage = storage
        client = Self.makeClient(
            config: config, storage: storage, key: "shogun-\(config.url.absoluteString)",
            session: session, persistent: true)
        let (stream, continuation) = AsyncStream<AuthSignal>.makeStream()
        signals = stream
        self.continuation = continuation
        let changes = client.authStateChanges
        observer = Task {
            for await (event, _) in changes {
                guard !Task.isCancelled else { break }
                if event == .signedOut || event == .userDeleted { continuation.yield(.signedOut) }
                if event == .passwordRecovery { continuation.yield(.recovery) }
            }
            continuation.finish()
        }
    }
    deinit { observer?.cancel() }
    func restore() async throws -> AuthAccount? {
        do {
            _ = try await client.session  // SDK refreshes expired persisted sessions.
            if try storage.retrieve(key: recoveryKey) == Data([2]) { continuation.yield(.recovery) }
            return try await account()
        } catch AuthError.sessionMissing { return nil } catch { throw Self.failure(error) }
    }
    func signIn(email: String, password: String) async throws -> AuthAccount {
        do {
            _ = try await client.signIn(email: email, password: password)
            try storage.remove(key: recoveryKey)
            return try await account()
        } catch { throw Self.failure(error) }
    }
    func signInWithApple() async throws -> AuthAccount {
        guard appleSignInAvailable else { throw SignInFailure.configuration }
        do {
            try storage.remove(key: recoveryKey)
            let proof = try await appleFlow()
            try Task.checkCancellation()
            guard !proof.idToken.isEmpty, !proof.nonce.isEmpty else {
                throw SignInFailure.callback
            }
            _ = try await client.signInWithIdToken(
                credentials: .init(
                    provider: .apple, idToken: proof.idToken, nonce: proof.nonce))
            try Task.checkCancellation()
            return try await account()
        } catch { throw Self.failure(error) }
    }
    func signInWithGoogle() async throws -> AuthAccount {
        guard googleSignInAvailable else { throw SignInFailure.configuration }
        do {
            try storage.remove(key: recoveryKey)
            _ = try await authenticateWithGoogle(using: client)
            try Task.checkCancellation()
            return try await account()
        } catch {
            throw Self.failure(error)
        }
    }
    func signUp(email: String, password: String) async throws -> AuthAccount? {
        do {
            try storage.remove(key: recoveryKey)
            let result = try await client.signUp(email: email, password: password)
            return result.session == nil ? nil : try await account()
        } catch { throw Self.failure(error) }
    }
    func recover(email: String) async throws {
        do {
            try await client.resetPasswordForEmail(email)
            try storage.store(key: recoveryKey, value: Data([1]))
        } catch { throw Self.failure(error) }
    }
    func changePassword(_ password: String) async throws -> AuthAccount {
        do {
            _ = try await client.update(user: UserAttributes(password: password))
            try storage.remove(key: recoveryKey)
            return try await account()
        } catch { throw Self.failure(error) }
    }
    func callback(_ url: URL) async throws -> AuthAccount {
        guard AuthConfiguration.acceptsCallback(url) else { throw SignInFailure.callback }
        do {
            _ = try await client.session(from: url)
            if try storage.retrieve(key: recoveryKey) != nil {
                try storage.store(key: recoveryKey, value: Data([2]))
                continuation.yield(.recovery)
            }
            return try await account()
        } catch { throw SignInFailure.callback }
    }
    func deleteAccountWithGoogle() async throws {
        guard googleSignInAvailable else { throw SignInFailure.configuration }
        let original = try await client.session
        let secondary = Self.makeClient(
            config: config, storage: TransientAuthStorage(),
            key: "shogun-delete-\(UUID().uuidString)",
            session: authSession, persistent: false)
        do {
            let proof = try await authenticateWithGoogle(using: secondary)
            let verified = try await secondary.user()
            guard proof.user.id == original.user.id, verified.id == original.user.id,
                verified.identities?.contains(where: { $0.provider == "google" }) == true
            else { throw SignInFailure.reauthentication }
            try Task.checkCancellation()
            let current = try await client.session
            guard current.user.id == original.user.id else { throw SignInFailure.reauthentication }
            try await deleteVerifiedAccount(
                current: current, proof: ["reauthentication_token": proof.accessToken],
                forbiddenFailure: .reauthentication)
            try? await secondary.signOut(scope: .local)
        } catch {
            try? await secondary.signOut(scope: .local)
            throw Self.failure(error)
        }
    }
    func deleteAccount(password: String) async throws {
        do {
            let current = try await client.session
            try await deleteVerifiedAccount(
                current: current, proof: ["password": password], forbiddenFailure: .credentials)
        } catch { throw Self.failure(error) }
    }
    private static func makeClient(
        config: AuthConfiguration, storage: any AuthLocalStorage, key: String,
        session: URLSession, persistent: Bool
    ) -> AuthClient {
        AuthClient(
            configuration: .init(
                url: config.url.appendingPathComponent("auth/v1"), headers: ["apikey": config.key],
                flowType: .pkce, redirectToURL: AuthConfiguration.redirect,
                storageKey: key, localStorage: storage, logger: nil,
                fetch: { try await session.data(for: $0) }, autoRefreshToken: persistent,
                // Initial events never authorize routing; restore() validates with Auth.
                emitLocalSessionAsInitialSession: persistent))
    }
    private func authenticateWithGoogle(using authClient: AuthClient) async throws -> Session {
        try await authClient.signInWithOAuth(
            provider: .google, redirectTo: AuthConfiguration.redirect,
            scopes: "openid email profile", queryParams: [("prompt", "select_account")]
        ) { [googleFlow] url in
            let callback = try await googleFlow(url)
            try Task.checkCancellation()
            guard AuthConfiguration.acceptsCallback(callback) else { throw SignInFailure.callback }
            return callback
        }
    }
    private func deleteVerifiedAccount(
        current: Session, proof: [String: String], forbiddenFailure: SignInFailure
    ) async throws {
        struct Result: Decodable { let deleted: Bool }
        let result: Result = try await request(
            path: "functions/v1/delete-account", method: "POST", token: current.accessToken,
            body: JSONEncoder().encode(proof), forbiddenFailure: forbiddenFailure)
        guard result.deleted else { throw SignInFailure.unavailable }
        // Clear local state even if logout now rejects the deleted identity.
        try? await signOut()
    }
    func signOut() async throws {
        // The SDK clears local Keychain state before attempting remote revocation.
        try? storage.remove(key: recoveryKey)
        do { try await client.signOut(scope: .local) } catch { throw Self.failure(error) }
    }
    private func account() async throws -> AuthAccount {
        let current = try await client.session
        let user = try await client.user()  // Validate the identity with Auth before routing.
        let libraryID: UUID = try await request(
            path: "rest/v1/rpc/bootstrap_account", method: "POST", token: current.accessToken)
        struct Library: Decodable {
            let id: UUID
            let name: String
        }
        let libraries: [Library] = try await request(
            path: "rest/v1/libraries?select=id,name&id=eq.\(libraryID)", method: "GET",
            token: current.accessToken)
        guard let library = libraries.first else { throw SignInFailure.unavailable }
        return AuthAccount(
            id: user.id, email: user.email ?? "", libraryID: library.id, libraryName: library.name,
            googleIdentityLinked: user.identities?.contains(where: { $0.provider == "google" })
                == true)
    }
    private func request<T: Decodable>(
        path: String, method: String, token: String, body: Data? = nil,
        forbiddenFailure: SignInFailure = .unavailable
    ) async throws -> T {
        let data = try await rawRequest(
            path: path, method: method, token: token, body: body,
            forbiddenFailure: forbiddenFailure)
        return try JSONDecoder().decode(T.self, from: data)
    }
    func backendClient(for userID: UUID) -> AuthenticatedBackendClient {
        AuthenticatedBackendClient(
            http: http,
            token: { [weak self] in
                guard let self else { throw SignInFailure.expired }
                do {
                    let current = try await self.client.session
                    guard current.user.id == userID else { throw SignInFailure.expired }
                    return current.accessToken
                } catch { throw Self.failure(error) }
            })
    }
    private func rawRequest(
        path: String, method: String, token: String, body: Data?,
        forbiddenFailure: SignInFailure
    ) async throws -> Data {
        do {
            return try await http.send(path: path, method: method, body: body, token: token)
        } catch let error as BackendHTTPError {
            if error.status == 401 { throw SignInFailure.expired }
            if error.status == 403 { throw forbiddenFailure }
            throw SignInFailure.unavailable
        }
    }
    static func failure(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled
            || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
            || (error as? ASAuthorizationError)?.code == .canceled
        {
            return CancellationError()
        }
        if let failure = error as? SignInFailure { return failure }
        if error is URLError { return SignInFailure.network }
        if case AuthError.sessionMissing = error { return SignInFailure.expired }
        if case AuthError.weakPassword = error { return SignInFailure.password }
        if case AuthError.api(_, let code, _, let response) = error {
            if code == .invalidCredentials { return SignInFailure.credentials }
            if code == .emailNotConfirmed { return SignInFailure.confirmation }
            if response.statusCode == 401 { return SignInFailure.expired }
        }
        return SignInFailure.unavailable
    }
}

/// Retains the system authentication sheet and cancels it with the store's task.
@MainActor
final class GoogleAuthenticationFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var anchor: ASPresentationAnchor?

    func authenticate(_ url: URL) async throws -> URL {
        try Task.checkCancellation()
        guard continuation == nil,
            let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows).first(where: \.isKeyWindow)
        else { throw SignInFailure.unavailable }
        anchor = window
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let session = ASWebAuthenticationSession(
                    url: url, callbackURLScheme: AuthConfiguration.redirect.scheme
                ) { [weak self] callback, error in
                    Task { @MainActor in
                        if let error {
                            self?.finish(.failure(error))
                        } else if let callback {
                            self?.finish(.success(callback))
                        } else {
                            self?.finish(.failure(SignInFailure.callback))
                        }
                    }
                }
                self.session = session
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                if Task.isCancelled {
                    cancel()
                } else if !session.start() {
                    finish(.failure(SignInFailure.unavailable))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
    private func cancel() {
        session?.cancel()
        finish(.failure(CancellationError()))
    }
    private func finish(_ result: Result<URL, Error>) {
        let pending = continuation
        continuation = nil
        session = nil
        anchor = nil
        pending?.resume(with: result)
    }
}

/// The deletion proof must never replace the main session or persist to Keychain.
private final class TransientAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
    func retrieve(key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
    func remove(key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
