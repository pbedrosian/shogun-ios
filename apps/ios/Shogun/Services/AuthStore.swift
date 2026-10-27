import Combine
import Foundation

@MainActor final class AuthStore: ObservableObject {
    enum Form: String {
        case signIn = "Sign in"
        case signUp = "Create account"
        case recover = "Reset password"
    }
    @Published private(set) var account: AuthAccount?
    @Published private(set) var isBusy = false
    @Published private(set) var isRestoring = true
    @Published private(set) var isDemo = false
    @Published private(set) var needsPasswordUpdate = false
    @Published private(set) var message: String?
    @Published private(set) var error: String?
    private let service: (any AuthServicing)?
    private var operation: Task<Void, Never>?
    private var observer: Task<Void, Never>?
    private var started = false
    private var pendingCallback: URL?
    var configured: Bool { service != nil }

    init(service: (any AuthServicing)?, demo: Bool = false) {
        self.service = service
        isDemo = demo
        if demo {
            isRestoring = false
            started = true
        }
    }
    deinit {
        operation?.cancel()
        observer?.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        if let service {
            let signals = service.signals
            observer = Task { [weak self] in
                for await signal in signals {
                    guard !Task.isCancelled, let self else { return }
                    switch signal {
                    case .signedOut: self.clearAccount()
                    case .recovery:
                        self.needsPasswordUpdate = true
                        self.isDemo = false
                    }
                }
            }
        }
        perform { [self] in
            try accept(try await service?.restore())
        }
    }
    func retryRestore() {
        guard !isBusy else { return }
        isRestoring = true
        perform { [self] in try accept(try await service?.restore()) }
    }
    func leaveDemo() {
        isDemo = false
        error = nil
        message = nil
    }
    func clearFeedback() {
        error = nil
        message = nil
    }
    static func validEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !email.contains(where: \.isWhitespace)
    }
    func submit(form: Form, email: String, password: String) {
        guard !isBusy else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validEmail(email) else {
            error = "Enter a valid email address."
            return
        }
        guard form == .recover || !password.isEmpty else {
            error = "Enter your password."
            return
        }
        guard form != .signUp || password.count >= 8 else {
            error = SignInFailure.password.localizedDescription
            return
        }
        guard let service else {
            error = SignInFailure.configuration.localizedDescription
            return
        }
        perform { [self] in
            switch form {
            case .signIn: try accept(try await service.signIn(email: email, password: password))
            case .signUp:
                try accept(try await service.signUp(email: email, password: password))
                if account == nil {
                    message =
                        "Check your email to confirm your account, then return here to sign in."
                }
            case .recover:
                try await service.recover(email: email)
                message =
                    "If this email has an account, a password reset link has been sent. Open it on this device."
            }
        }
    }
    func handle(_ url: URL) {
        guard AuthConfiguration.acceptsCallback(url) else { return }
        if isBusy {
            if isRestoring { pendingCallback = url }
            return
        }
        guard let service else {
            error = SignInFailure.configuration.localizedDescription
            return
        }
        perform { [self] in try accept(try await service.callback(url)) }
    }
    func updatePassword(_ password: String) {
        guard !isBusy else { return }
        guard password.count >= 8 else {
            error = SignInFailure.password.localizedDescription
            return
        }
        guard let service else { return }
        perform { [self] in
            try accept(try await service.changePassword(password))
            needsPasswordUpdate = false
            message = "Your password has been updated."
        }
    }
    func deleteAccount(password: String) {
        guard !isBusy, account != nil, let service else { return }
        guard !password.isEmpty else {
            error = "Enter your current password."
            return
        }
        perform { [self] in
            try await service.deleteAccount(password: password)
            clearAccount()
            message = "Your account has been deleted."
        }
    }
    func signOut() {
        guard !isBusy else { return }
        clearAccount()
        perform { [self] in try await service?.signOut() }
    }
    func cancel() {
        guard isBusy else { return }
        pendingCallback = nil
        operation?.cancel()
    }
    private func clearAccount() {
        account = nil
        isDemo = false
        needsPasswordUpdate = false
    }
    private func accept(_ result: AuthAccount?) throws {
        try Task.checkCancellation()
        account = result
        isDemo = false
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        message = nil
        operation = Task { [self] in
            do {
                try await action()
                try Task.checkCancellation()
            } catch {
                if Task.isCancelled || error is CancellationError {
                    clearAccount()
                    try? await service?.signOut()
                } else {
                    self.error = (error as? SignInFailure ?? .unavailable).localizedDescription
                }
            }
            isBusy = false
            isRestoring = false
            operation = nil
            if let url = pendingCallback {
                pendingCallback = nil
                handle(url)
            }
        }
    }
}
