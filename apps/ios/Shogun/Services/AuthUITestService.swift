#if DEBUG
import Foundation

/// Deterministic UI-only service. The release build never includes this path.
@MainActor final class AuthUITestService: AuthServicing {
    let signals: AsyncStream<AuthSignal>
    private let continuation: AsyncStream<AuthSignal>.Continuation
    private let account = AuthAccount(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, email: "owner@shogun.test", libraryID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, libraryName: "My Library")
    private let recovery = ProcessInfo.processInfo.arguments.contains("-shogun-auth-recovery")
    init() { (signals, continuation) = AsyncStream.makeStream() }
    func restore() async throws -> AuthAccount? {
        if recovery { continuation.yield(.recovery); return account }; return nil
    }
    func signIn(email: String, password: String) async throws -> AuthAccount {
        if password == "invalid-password" { throw SignInFailure.credentials }
        if password == "slow-password" { try await Task.sleep(for: .seconds(30)) }
        return account
    }
    func signUp(email: String, password: String) async throws -> AuthAccount? { nil }
    func recover(email: String) async throws {}
    func changePassword(_ password: String) async throws -> AuthAccount { account }
    func callback(_ url: URL) async throws -> AuthAccount { continuation.yield(.recovery); return account }
    func deleteAccount(password: String) async throws {
        if password == "invalid-password" { throw SignInFailure.credentials }
        continuation.yield(.signedOut)
    }
    func signOut() async throws { continuation.yield(.signedOut) }
}
#endif
