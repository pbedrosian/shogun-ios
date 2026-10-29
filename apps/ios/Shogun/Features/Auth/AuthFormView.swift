import SwiftUI

struct AuthFormView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var mode: AuthStore.Form = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var validation: String?
    @FocusState private var emailFocused: Bool
    @FocusState private var passwordFocused: Bool
    @FocusState private var confirmationFocused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                AuthHeader(title: mode.rawValue)
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.regular) {
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
                        Text("Email").font(ShogunTheme.Typography.body)
                        TextField("you@example.com", text: $email)
                            .textContentType(mode == .signUp ? .emailAddress : .username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($emailFocused).submitLabel(mode == .recover ? .go : .next)
                            .onSubmit {
                                if mode == .recover { submit() } else { passwordFocused = true }
                            }
                            .accessibilityLabel("Email").accessibilityIdentifier("auth.email")
                            .shogunAuthField()
                    }
                    if mode != .recover {
                        AuthPasswordField(
                            title: "Password", identifier: "auth.password", text: $password,
                            isFocused: $passwordFocused, isNew: mode == .signUp,
                            next: mode == .signUp
                        ) {
                            if mode == .signUp { confirmationFocused = true } else { submit() }
                        }.id(mode)
                    }
                    if mode == .signUp {
                        AuthPasswordField(
                            title: "Confirm password", identifier: "auth.confirmPassword",
                            text: $confirmation,
                            isFocused: $confirmationFocused, isNew: true, next: false,
                            onSubmit: submit)
                        Text("Use at least 8 characters.")
                            .font(ShogunTheme.Typography.footnote).foregroundStyle(
                                ShogunTheme.muted)
                    }
                }.disabled(auth.isBusy)
                if mode == .signIn {
                    Button("Forgot password?") { changeMode(.recover) }
                        .font(ShogunTheme.Typography.body).frame(
                            maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget,
                            alignment: .trailing
                        )
                        .accessibilityIdentifier("auth.forgotPassword").disabled(auth.isBusy)
                        .padding(.top, -ShogunTheme.Spacing.regular)
                }
                if !auth.configured {
                    Text(SignInFailure.configuration.localizedDescription).font(
                        ShogunTheme.Typography.footnote
                    ).foregroundStyle(ShogunTheme.muted)
                }
                if let validation {
                    Text(validation).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                        "auth.validation")
                }
                AuthFeedback()
                if auth.error != nil && auth.configured {
                    Button("Retry connection", action: auth.retryRestore)
                }
                Button(action: submit) {
                    HStack(spacing: ShogunTheme.Spacing.small) {
                        if auth.isBusy { ProgressView().tint(ShogunTheme.authOnPrimary) }
                        Text(mode == .recover ? "Send reset link" : mode.rawValue)
                    }
                }.buttonStyle(ShogunAuthPrimaryButtonStyle())
                    .disabled(auth.isBusy || !auth.configured).accessibilityIdentifier(
                        "auth.submit")
                if auth.isBusy {
                    Button("Cancel request", action: auth.cancel).frame(
                        maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget
                    )
                    .accessibilityIdentifier("auth.cancel")
                }
                VStack(spacing: ShogunTheme.Spacing.tight) {
                    if mode == .signIn {
                        Text("New to Shogun?").font(ShogunTheme.Typography.body).foregroundStyle(
                            ShogunTheme.muted)
                        Button("Create account") { changeMode(.signUp) }.accessibilityIdentifier(
                            "auth.createAccount")
                    } else {
                        if mode == .signUp {
                            Text("Already have an account?").font(ShogunTheme.Typography.body)
                                .foregroundStyle(ShogunTheme.muted)
                        }
                        Button("Back to sign in") { changeMode(.signIn) }.accessibilityIdentifier(
                            "auth.backToSignIn")
                    }
                }.buttonStyle(ShogunAuthTextButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget).disabled(
                        auth.isBusy)
            }.shogunAuthContent()
        }.scrollDismissesKeyboard(.interactively).shogunCanvas()
            .tint(ShogunTheme.accent)
            .onChange(of: auth.isBusy) { _, busy in
                if !busy {
                    password = ""
                    confirmation = ""
                }
            }
            .onDisappear {
                password = ""
                confirmation = ""
            }
    }
    private func changeMode(_ next: AuthStore.Form) {
        mode = next
        password = ""
        confirmation = ""
        validation = nil
        auth.clearFeedback()
        emailFocused = false
        passwordFocused = false
        confirmationFocused = false
    }
    private func submit() {
        emailFocused = false
        passwordFocused = false
        confirmationFocused = false
        validation = nil
        guard mode != .signUp || password == confirmation else {
            validation = "Passwords do not match."
            return
        }
        auth.submit(form: mode, email: email, password: password)
    }
}
