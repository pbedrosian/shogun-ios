import SwiftUI

struct AuthRootView: View {
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        Group {
            #if DEBUG
            if auth.isDemo { DemoTabs().id("offline-demo") } else { accountContent }
            #else
            accountContent
            #endif
        }
        .tint(ShogunTheme.accent)
        .task { auth.start() }
        .onOpenURL { auth.handle($0) }
    }
    @ViewBuilder private var accountContent: some View {
        if auth.isRestoring {
            VStack(spacing: ShogunTheme.Spacing.regular) {
                ProgressView("Restoring your session…")
                Button("Cancel", action: auth.cancel)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).shogunCanvas()
        } else if auth.needsPasswordUpdate { PasswordUpdateView() }
        else if let account = auth.account { AccountTabs(account: account).id(account.id) }
        else { AuthFormView() }
    }
}

private struct AuthHeader: View {
    let title: String
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.large) {
            Text("SHOGUN").font(ShogunTheme.Typography.authBrand)
                .tracking(2).foregroundStyle(ShogunTheme.accent)
                .accessibilityIdentifier("auth.brand")
            Text(title).font(ShogunTheme.Typography.authTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity).padding(.bottom, ShogunTheme.Spacing.small)
    }
}

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
                            .textContentType(mode == .signUp ? .emailAddress : .username).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($emailFocused).submitLabel(mode == .recover ? .go : .next)
                            .onSubmit { if mode == .recover { submit() } else { passwordFocused = true } }
                            .accessibilityLabel("Email").accessibilityIdentifier("auth.email").shogunAuthField()
                    }
                    if mode != .recover {
                        AuthPasswordField(title: "Password", identifier: "auth.password", text: $password,
                            isFocused: $passwordFocused, isNew: mode == .signUp, next: mode == .signUp) {
                                if mode == .signUp { confirmationFocused = true } else { submit() }
                            }.id(mode)
                    }
                    if mode == .signUp {
                        AuthPasswordField(title: "Confirm password", identifier: "auth.confirmPassword", text: $confirmation,
                            isFocused: $confirmationFocused, isNew: true, next: false, onSubmit: submit)
                        Text("Use at least 8 characters.")
                            .font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
                    }
                }.disabled(auth.isBusy)
                if mode == .signIn {
                    Button("Forgot password?") { changeMode(.recover) }
                        .font(ShogunTheme.Typography.body).frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget, alignment: .trailing)
                        .accessibilityIdentifier("auth.forgotPassword").disabled(auth.isBusy)
                        .padding(.top, -ShogunTheme.Spacing.regular)
                }
                if !auth.configured {
                    Text(SignInFailure.configuration.localizedDescription).font(ShogunTheme.Typography.footnote).foregroundStyle(ShogunTheme.muted)
                }
                if let validation { Text(validation).foregroundStyle(.red).accessibilityIdentifier("auth.validation") }
                AuthFeedback()
                if auth.error != nil && auth.configured { Button("Retry connection", action: auth.retryRestore) }
                Button(action: submit) {
                    HStack(spacing: ShogunTheme.Spacing.small) {
                        if auth.isBusy { ProgressView().tint(ShogunTheme.onAccent) }
                        Text(mode == .recover ? "Send reset link" : mode.rawValue)
                    }
                }.buttonStyle(ShogunAuthPrimaryButtonStyle())
                    .disabled(auth.isBusy || !auth.configured).accessibilityIdentifier("auth.submit")
                if auth.isBusy {
                    Button("Cancel request", action: auth.cancel).frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget)
                        .accessibilityIdentifier("auth.cancel")
                }
                VStack(spacing: ShogunTheme.Spacing.tight) {
                    if mode == .signIn {
                        Text("New to Shogun?").font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.muted)
                        Button("Create account") { changeMode(.signUp) }.accessibilityIdentifier("auth.createAccount")
                    } else {
                        if mode == .signUp { Text("Already have an account?").font(ShogunTheme.Typography.body).foregroundStyle(ShogunTheme.muted) }
                        Button("Back to sign in") { changeMode(.signIn) }.accessibilityIdentifier("auth.backToSignIn")
                    }
                }.buttonStyle(ShogunAuthTextButtonStyle())
                    .frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget).disabled(auth.isBusy)
            }.padding(ShogunTheme.Spacing.large).padding(.top, ShogunTheme.Auth.headerSpacing)
                .frame(maxWidth: ShogunTheme.Auth.contentWidth).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).shogunCanvas()
            .onChange(of: auth.isBusy) { _, busy in if !busy { password = ""; confirmation = "" } }
            .onDisappear { password = ""; confirmation = "" }
    }
    private func changeMode(_ next: AuthStore.Form) {
        mode = next; password = ""; confirmation = ""; validation = nil; auth.clearFeedback()
        emailFocused = false; passwordFocused = false; confirmationFocused = false
    }
    private func submit() {
        emailFocused = false; passwordFocused = false; confirmationFocused = false; validation = nil
        guard mode != .signUp || password == confirmation else { validation = "Passwords do not match."; return }
        auth.submit(form: mode, email: email, password: password)
    }
}

private struct AuthPasswordField: View {
    let title: String
    let identifier: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let isNew: Bool
    let next: Bool
    let onSubmit: () -> Void
    @State private var visible = false
    var body: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.small) {
            Text(title).font(ShogunTheme.Typography.body)
            HStack(spacing: ShogunTheme.Spacing.small) {
                Group {
                    if visible { TextField(isNew ? "At least 8 characters" : "Enter your password", text: $text) }
                    else { SecureField(isNew ? "At least 8 characters" : "Enter your password", text: $text) }
                }.textContentType(isNew ? .newPassword : .password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($isFocused).submitLabel(next ? .next : .go).onSubmit(onSubmit)
                    .accessibilityLabel(title).accessibilityIdentifier(identifier)
                Button { visible.toggle(); isFocused = true } label: {
                    Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(ShogunTheme.muted)
                        .frame(minWidth: ShogunTheme.Size.touchTarget, minHeight: ShogunTheme.Size.touchTarget)
                }.buttonStyle(.plain).accessibilityLabel(visible ? "Hide \(title.lowercased())" : "Show \(title.lowercased())")
                    .accessibilityIdentifier(identifier + ".visibility")
            }.shogunAuthField()
        }
    }
}

private struct PasswordUpdateView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var password = ""
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                AuthHeader(title: "Reset password")
                AuthPasswordField(title: "New password", identifier: "auth.newPassword", text: $password,
                    isFocused: $focused, isNew: true, next: false, onSubmit: update).disabled(auth.isBusy)
                AuthFeedback()
                Button(action: update) { Text("Update password") }
                    .buttonStyle(ShogunAuthPrimaryButtonStyle()).disabled(auth.isBusy).accessibilityIdentifier("auth.updatePassword")
                if auth.isBusy { ProgressView("Updating password…") }
                Button("Cancel", action: auth.signOut).frame(maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget).disabled(auth.isBusy)
            }.padding(ShogunTheme.Spacing.large).padding(.top, ShogunTheme.Auth.headerSpacing)
                .frame(maxWidth: ShogunTheme.Auth.contentWidth).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).shogunCanvas()
    }
    private func update() { focused = false; auth.updatePassword(password); password = "" }
}

private struct AuthFeedback: View {
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        if let error = auth.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.error") }
        if let message = auth.message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("auth.message") }
    }
}

#if DEBUG
private struct DemoTabs: View {
    @StateObject private var catalog = CatalogStore()
    var body: some View {
        TabView {
            LibraryView().tabItem { Label("Library", systemImage: "square.grid.2x2") }
            SearchView().tabItem { Label("Search", systemImage: "magnifyingglass") }
            ProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }.environmentObject(catalog)
    }
}

#endif

private struct AccountTabs: View {
    let account: AuthAccount
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        TabView {
            NavigationStack {
                ContentUnavailableView("Your library is ready", systemImage: "film.stack",
                    description: Text("Your account is connected. Movie collection syncing is coming soon."))
                    .navigationTitle(account.libraryName).navigationBarTitleDisplayMode(.inline).shogunCanvas()
            }.tabItem { Label("Library", systemImage: "square.grid.2x2") }
            AccountProfileView(account: account).tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}
