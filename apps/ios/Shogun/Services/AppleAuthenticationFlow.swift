import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

/// Ephemeral proof. Supabase, not the app, validates Apple's signature and nonce.
struct AppleSignInProof: Sendable {
    let idToken: String
    let nonce: String
    var authorizationCode: String? = nil
}

struct AppleSignInChallenge {
    let nonce: String
    let state: String
    init() throws {
        nonce = try Self.randomValue()
        state = try Self.randomValue()
    }
    var hashedNonce: String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func request() -> ASAuthorizationAppleIDRequest {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = hashedNonce
        request.state = state
        return request
    }
    func proof(identityToken: Data?, returnedState: String?, authorizationCode: Data? = nil) throws
        -> AppleSignInProof
    {
        guard returnedState == state,
            let identityToken, let token = String(data: identityToken, encoding: .utf8),
            !token.isEmpty
        else { throw SignInFailure.callback }
        return AppleSignInProof(
            idToken: token, nonce: nonce,
            authorizationCode: authorizationCode.flatMap { String(data: $0, encoding: .utf8) })
    }
    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SignInFailure.unavailable
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class AppleAuthenticationFlow: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
{
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<AppleSignInProof, Error>?
    private var challenge: AppleSignInChallenge?
    private var anchor: ASPresentationAnchor?

    func authenticate() async throws -> AppleSignInProof {
        try Task.checkCancellation()
        guard continuation == nil,
            let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .filter({ $0.activationState == .foregroundActive })
                .flatMap(\.windows).first(where: \.isKeyWindow)
        else { throw SignInFailure.unavailable }
        let challenge = try AppleSignInChallenge()
        self.challenge = challenge
        anchor = window
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let controller = ASAuthorizationController(authorizationRequests: [
                    challenge.request()
                ])
                self.controller = controller
                controller.delegate = self
                controller.presentationContextProvider = self
                if Task.isCancelled { cancel() } else { controller.performRequests() }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard controller === self.controller else { return }
        do {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let challenge
            else { throw SignInFailure.callback }
            finish(
                .success(
                    try challenge.proof(
                        identityToken: credential.identityToken, returnedState: credential.state,
                        authorizationCode: credential.authorizationCode)))
        } catch { finish(.failure(error)) }
    }
    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithError error: Error
    ) {
        guard controller === self.controller else { return }
        finish(.failure(error))
    }
    private func cancel() {
        let active = controller
        finish(.failure(CancellationError()))
        active?.cancel()
    }
    private func finish(_ result: Result<AppleSignInProof, Error>) {
        let pending = continuation
        continuation = nil
        controller = nil
        challenge = nil
        anchor = nil
        pending?.resume(with: result)
    }
}
