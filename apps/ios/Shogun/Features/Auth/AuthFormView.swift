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
    private var signupEmailIsValid: Bool {
        AuthStore.validEmail(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private var showsPasswordFields: Bool {
        mode == .signIn || (mode == .signUp && signupEmailIsValid)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                AuthHeader(title: mode.rawValue)
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                    if mode != .recover && (auth.appleSignInVisible || auth.googleSignInAvailable) {
                        socialSignIn
                        emailDivider
                    }
                    VStack(alignment: .leading, spacing: ShogunTheme.Spacing.regular) {
                        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
                            Text("Email").font(ShogunTheme.Typography.body)
                            TextField("you@example.com", text: $email)
                                .textContentType(mode == .signUp ? .emailAddress : .username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($emailFocused).submitLabel(mode == .recover ? .go : .next)
                                .onSubmit {
                                    if mode == .recover {
                                        submit()
                                    } else if mode == .signUp && !signupEmailIsValid {
                                        validation = "Enter a valid email address."
                                    } else {
                                        passwordFocused = true
                                    }
                                }
                                .accessibilityLabel("Email").accessibilityIdentifier("auth.email")
                                .shogunAuthField()
                        }
                        if showsPasswordFields {
                            AuthPasswordField(
                                title: "Password", identifier: "auth.password", text: $password,
                                isFocused: $passwordFocused, isNew: mode == .signUp,
                                next: mode == .signUp
                            ) {
                                if mode == .signUp { confirmationFocused = true } else { submit() }
                            }.id(mode)
                        }
                        if mode == .signUp && showsPasswordFields {
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
                            Text(
                                mode == .recover
                                    ? "Send reset link"
                                    : mode == .signUp ? "Create with Email" : mode.rawValue)
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
                            Text("New to Shogun?").font(ShogunTheme.Typography.body)
                                .foregroundStyle(
                                    ShogunTheme.muted)
                            Button("Create account") { changeMode(.signUp) }
                                .accessibilityIdentifier(
                                    "auth.createAccount")
                        } else {
                            if mode == .signUp {
                                Text("Already have an account?").font(ShogunTheme.Typography.body)
                                    .foregroundStyle(ShogunTheme.muted)
                            }
                            Button("Back to sign in") { changeMode(.signIn) }
                                .accessibilityIdentifier(
                                    "auth.backToSignIn")
                        }
                    }.buttonStyle(ShogunAuthTextButtonStyle())
                        .frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget)
                        .disabled(
                            auth.isBusy)
                }
                .padding(ShogunTheme.Spacing.regular)
                .background(
                    ShogunTheme.surface,
                    in: RoundedRectangle(cornerRadius: ShogunTheme.Radius.authPanel))
            }.shogunAuthContent()
        }.scrollDismissesKeyboard(.interactively).shogunCanvas()
            .tint(ShogunTheme.accent)
            .onChange(of: email) { _, _ in
                if mode == .signUp {
                    validation = nil
                    if !signupEmailIsValid {
                        password = ""
                        confirmation = ""
                        passwordFocused = false
                        confirmationFocused = false
                    }
                }
            }
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
    private var socialSignIn: some View {
        HStack(spacing: ShogunTheme.Spacing.regular) {
            if auth.appleSignInVisible {
                Button {
                    prepareSocialSignIn()
                    auth.signInWithApple()
                } label: {
                    Image("AppleSignInLogo")
                        .resizable().scaledToFit()
                        .frame(
                            width: ShogunTheme.Auth.providerButtonSize,
                            height: ShogunTheme.Auth.providerButtonSize
                        )
                        .background(.white, in: Circle())
                        .overlay(Circle().strokeBorder(ShogunTheme.muted.opacity(0.25)))
                        .clipShape(Circle())
                }
                .accessibilityLabel(mode == .signUp ? "Sign up with Apple" : "Sign in with Apple")
                .accessibilityIdentifier("auth.apple")
                .disabled(!auth.appleSignInAvailable)
                .opacity(auth.appleSignInAvailable ? 1 : 0.5)
                .accessibilityHint(auth.appleSignInAvailable ? "" : "Not available yet.")
            }
            if auth.googleSignInAvailable {
                Button {
                    prepareSocialSignIn()
                    auth.signInWithGoogle()
                } label: {
                    Image("GoogleSignIn")
                        .resizable().scaledToFit()
                        .frame(
                            width: ShogunTheme.Auth.providerButtonSize,
                            height: ShogunTheme.Auth.providerButtonSize)
                }
                .accessibilityLabel(mode == .signUp ? "Sign up with Google" : "Sign in with Google")
                .accessibilityIdentifier("auth.google")
            }
        }
        .buttonStyle(.plain)
        .disabled(auth.isBusy)
        .frame(maxWidth: .infinity)
    }
    private var emailDivider: some View {
        HStack(spacing: ShogunTheme.Spacing.small) {
            dividerLine
            Text(mode == .signUp ? "Or sign up with" : "Or log in with")
                .font(ShogunTheme.Typography.footnote)
                .foregroundStyle(ShogunTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("auth.emailDivider")
                .layoutPriority(1)
            dividerLine
        }
    }
    private var dividerLine: some View {
        Rectangle().fill(ShogunTheme.muted.opacity(0.2))
            .frame(height: ShogunTheme.Auth.dividerThickness)
            .accessibilityHidden(true)
    }
    private func prepareSocialSignIn() {
        validation = nil
        emailFocused = false
        passwordFocused = false
        confirmationFocused = false
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
        guard mode != .signUp || signupEmailIsValid else {
            validation = "Enter a valid email address."
            emailFocused = true
            return
        }
        guard mode != .signUp || password == confirmation else {
            validation = "Passwords do not match."
            return
        }
        auth.submit(form: mode, email: email, password: password)
    }
}
