import Foundation

struct AuthAccount: Equatable {
    let id: UUID
    let email: String
    let libraryID: UUID
    let libraryName: String
    var googleIdentityLinked = false
    var appleIdentityLinked = false
}

enum AuthSignal { case signedOut, recovery }

enum SignInFailure: Error, LocalizedError, Equatable {
    case configuration, credentials, confirmation, network, expired, password, callback,
        unavailable, reauthentication, identityLinking, appleReauthentication
    var errorDescription: String? {
        switch self {
        case .configuration:
            return
                "Account connection is not configured. Follow the iOS setup instructions, then rebuild the app."
        case .credentials: return "The email or password is incorrect. Try again."
        case .confirmation: return "Confirm your email address before signing in."
        case .network:
            return "Cannot reach the account service. Check your connection and try again."
        case .expired: return "Your session has expired. Please sign in again."
        case .password: return "Use a password with at least 8 characters."
        case .callback:
            return "This account link is invalid or expired. Request a new link on this device."
        case .reauthentication:
            return "Confirm with the same Google account you use in Shogun, then try again."
        case .appleReauthentication:
            return
                "Confirm with the Apple Account connected to this Shogun account, then try again."
        case .identityLinking:
            return
                "Apple could not be connected to this account. Your existing account and collection have not been moved. Try again or use your current sign-in method."
        case .unavailable: return "The account request could not be completed. Please try again."
        }
    }
}

@MainActor protocol AuthServicing: AnyObject {
    var signals: AsyncStream<AuthSignal> { get }
    var appleSignInAvailable: Bool { get }
    var appleDeletionAvailable: Bool { get }
    func deleteAccountWithApplePassword(_ password: String) async throws
    func deleteAccountWithApple() async throws
    var appleIdentityLinkingAvailable: Bool { get }
    func linkAppleIdentity() async throws -> AuthAccount
    func signInWithApple() async throws -> AuthAccount
    var googleSignInAvailable: Bool { get }
    func signInWithGoogle() async throws -> AuthAccount
    func restore() async throws -> AuthAccount?
    func signIn(email: String, password: String) async throws -> AuthAccount
    func signUp(email: String, password: String) async throws -> AuthAccount?
    func recover(email: String) async throws
    func changePassword(_ password: String) async throws -> AuthAccount
    func callback(_ url: URL) async throws -> AuthAccount
    func deleteAccountWithGoogle() async throws
    func deleteAccount(password: String) async throws
    func signOut() async throws
}

extension AuthServicing {
    func deleteAccountWithApplePassword(_ password: String) async throws {
        throw SignInFailure.configuration
    }
    var appleDeletionAvailable: Bool { false }
    func deleteAccountWithApple() async throws { throw SignInFailure.configuration }
    var appleIdentityLinkingAvailable: Bool { false }
    func linkAppleIdentity() async throws -> AuthAccount { throw SignInFailure.configuration }
    var appleSignInAvailable: Bool { false }
    func signInWithApple() async throws -> AuthAccount { throw SignInFailure.configuration }
    func deleteAccountWithGoogle() async throws { throw SignInFailure.configuration }
    var googleSignInAvailable: Bool { false }
    func signInWithGoogle() async throws -> AuthAccount { throw SignInFailure.configuration }
}

struct AuthConfiguration: Equatable {
    let url: URL
    let key: String
    static var redirect: URL {
        let scheme =
            Bundle.main.object(forInfoDictionaryKey: "ShogunAuthScheme") as? String ?? "shogun"
        return URL(string: "\(scheme)://auth-callback")!
    }
    init(info: [String: Any], allowLocalHTTP: Bool) throws {
        guard let raw = info["SUPABASE_URL"] as? String, let url = URL(string: raw),
            let host = url.host, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil, ["", "/"].contains(url.path),
            let key = info["SUPABASE_PUBLISHABLE_KEY"] as? String, !key.isEmpty,
            !key.contains("$("), !key.hasPrefix("sb_secret_")
        else { throw SignInFailure.configuration }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        let privateIP =
            parts.count == 4 && parts.allSatisfy { (0...255).contains($0) }
            && (parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 172 && (16...31).contains(parts[1])))
        let local = host == "localhost" || host.hasSuffix(".local") || privateIP
        guard url.scheme == "https" || (allowLocalHTTP && local && url.scheme == "http") else {
            throw SignInFailure.configuration
        }
        if !key.hasPrefix("sb_publishable_") {
            let pieces = key.split(separator: ".")
            guard pieces.count == 3 else { throw SignInFailure.configuration }
            var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
            guard let data = Data(base64Encoded: payload),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["role"] as? String == "anon"
            else { throw SignInFailure.configuration }
        }
        self.url = url
        self.key = key
    }
    static func acceptsCallback(_ url: URL) -> Bool {
        url.scheme == redirect.scheme && url.host == redirect.host && url.user == nil
            && url.password == nil && url.port == nil && ["", "/"].contains(url.path)
    }
}
