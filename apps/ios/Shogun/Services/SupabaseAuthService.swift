import Auth
import Foundation

@MainActor final class SupabaseAuthService: AuthServicing {
    let signals: AsyncStream<AuthSignal>
    private let client: AuthClient
    private let config: AuthConfiguration
    private let http: BackendHTTPClient
    private let storage: any AuthLocalStorage
    private let continuation: AsyncStream<AuthSignal>.Continuation
    private var recoveryKey: String { "shogun-recovery-\(config.url.absoluteString)" }
    private var observer: Task<Void, Never>?

    init(
        config: AuthConfiguration, storage: any AuthLocalStorage = SecureAuthStorage(),
        session: URLSession = .shared
    ) {
        self.config = config
        self.http = BackendHTTPClient(config: config, session: session)
        self.storage = storage
        client = AuthClient(
            configuration: .init(
                url: config.url.appendingPathComponent("auth/v1"), headers: ["apikey": config.key],
                flowType: .pkce, redirectToURL: AuthConfiguration.redirect,
                storageKey: "shogun-\(config.url.absoluteString)", localStorage: storage,
                logger: nil,
                // Initial events never authorize routing: restore() refreshes and validates with Auth.
                fetch: { try await session.data(for: $0) }, emitLocalSessionAsInitialSession: true)
        )
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
    func deleteAccount(password: String) async throws {
        do {
            let current = try await client.session
            struct Result: Decodable { let deleted: Bool }
            let result: Result = try await request(
                path: "functions/v1/delete-account", method: "POST", token: current.accessToken,
                body: JSONEncoder().encode(["password": password]), forbiddenFailure: .credentials)
            guard result.deleted else { throw SignInFailure.unavailable }
            // Remove the local session even though remote logout may now reject the deleted user.
            try? await signOut()
        } catch { throw Self.failure(error) }
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
            id: user.id, email: user.email ?? "", libraryID: library.id, libraryName: library.name)
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
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
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
