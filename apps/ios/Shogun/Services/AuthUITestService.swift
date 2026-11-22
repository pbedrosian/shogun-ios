#if DEBUG
    import Foundation

    /// Deterministic UI-only service. The release build never includes this path.
    @MainActor final class AuthUITestService: AuthServicing {
        var googleSignInAvailable: Bool {
            ProcessInfo.processInfo.arguments.contains("-shogun-auth-google")
        }
        func signInWithGoogle() async throws -> AuthAccount { account }
        var appleSignInAvailable: Bool {
            ProcessInfo.processInfo.arguments.contains("-shogun-auth-apple")
        }
        func signInWithApple() async throws -> AuthAccount { account }
        var appleIdentityLinkingAvailable: Bool {
            ProcessInfo.processInfo.arguments.contains("-shogun-auth-apple-linking")
        }
        var appleDeletionAvailable: Bool {
            ProcessInfo.processInfo.arguments.contains("-shogun-auth-apple-deletion")
        }
        func deleteAccountWithApplePassword(_ password: String) async throws {
            if password == "invalid-password" { throw SignInFailure.credentials }
            continuation.yield(.signedOut)
        }
        func deleteAccountWithApple() async throws { continuation.yield(.signedOut) }
        private var appleLinked = ProcessInfo.processInfo.arguments.contains(
            "-shogun-auth-apple-linked")
        func linkAppleIdentity() async throws -> AuthAccount {
            appleLinked = true
            return account
        }
        let signals: AsyncStream<AuthSignal>
        private let continuation: AsyncStream<AuthSignal>.Continuation
        private var account: AuthAccount {
            AuthAccount(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                email: "owner@shogun.test",
                libraryID: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                libraryName: "My Library", googleIdentityLinked: googleSignInAvailable,
                appleIdentityLinked: appleLinked)
        }
        private let recovery = ProcessInfo.processInfo.arguments.contains("-shogun-auth-recovery")
        init() { (signals, continuation) = AsyncStream.makeStream() }
        func restore() async throws -> AuthAccount? {
            if recovery {
                continuation.yield(.recovery)
                return account
            }
            return nil
        }
        func signIn(email: String, password: String) async throws -> AuthAccount {
            if password == "invalid-password" { throw SignInFailure.credentials }
            if password == "slow-password" { try await Task.sleep(for: .seconds(30)) }
            return account
        }
        func signUp(email: String, password: String) async throws -> AuthAccount? { nil }
        func recover(email: String) async throws {}
        func changePassword(_ password: String) async throws -> AuthAccount { account }
        func callback(_ url: URL) async throws -> AuthAccount {
            continuation.yield(.recovery)
            return account
        }
        func deleteAccountWithGoogle() async throws { continuation.yield(.signedOut) }
        func deleteAccount(password: String) async throws {
            if password == "invalid-password" { throw SignInFailure.credentials }
            continuation.yield(.signedOut)
        }
        func signOut() async throws { continuation.yield(.signedOut) }
    }
#endif
