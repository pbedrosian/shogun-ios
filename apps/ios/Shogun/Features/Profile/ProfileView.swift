import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeader(name: "Alex Morgan", email: "alex@example.com", badge: "Demo account")
                }
                Section { Button("Leave demo", action: auth.leaveDemo).accessibilityIdentifier("auth.leaveDemo") }
                Section("Your libraries") {
                    ForEach(store.libraries) { library in Label(library.name, systemImage: library.isShared ? "person.2" : "person").badge(library.isShared ? "Shared" : "Personal") }
                }
                Section("About this preview") {
                    LabeledContent("Version", value: "1.0 · Phase 1")
                    Text("This demo stays offline. Leave demo to connect your real account with email sign-in. Family invitations and online movie lookup are coming later.").font(ShogunTheme.Typography.body).foregroundStyle(.secondary)
                    Text("All content is local sample data. No account is connected.").font(ShogunTheme.Typography.footnote).foregroundStyle(.secondary)
                }
            }.scrollContentBackground(.hidden).background(ShogunTheme.canvas).navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        }
    }
}

/// Shared between the original catalog fixture and the authenticated profile.
private struct ProfileHeader: View {
    let name: String
    let email: String
    let badge: String
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.medium) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: ShogunTheme.Size.profileAvatar)).foregroundStyle(ShogunTheme.accent).accessibilityHidden(true)
            Text(name).font(ShogunTheme.Typography.profileTitle)
            Text(email).foregroundStyle(.secondary).accessibilityIdentifier("auth.accountEmail")
            Text(badge).font(ShogunTheme.Typography.disclosure)
                .padding(.horizontal, ShogunTheme.Spacing.control).padding(.vertical, ShogunTheme.Spacing.compact)
                .background(.quaternary, in: Capsule())
        }.frame(maxWidth: .infinity).padding(.vertical)
    }
}

struct AccountProfileView: View {
    let account: AuthAccount
    @EnvironmentObject private var auth: AuthStore
    @State private var deleting = false
    var body: some View {
        NavigationStack {
            List {
                Section { ProfileHeader(name: "Shogun account", email: account.email, badge: "Signed in") }
                Section("Your personal library") { Label(account.libraryName, systemImage: "person").badge("Personal") }
                Section("About") { LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") }
                Section {
                    if let error = auth.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.error") }
                    Button("Sign out", role: .destructive, action: auth.signOut).disabled(auth.isBusy).accessibilityIdentifier("auth.signOut")
                    Button("Delete account", role: .destructive) { auth.clearFeedback(); deleting = true }
                        .disabled(auth.isBusy).accessibilityIdentifier("auth.deleteAccount")
                }
            }.navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar).scrollContentBackground(.hidden).background(ShogunTheme.canvas)
                .sheet(isPresented: $deleting) { DeleteAccountView() }
        }
    }
}

private struct DeleteAccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @FocusState private var passwordFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Permanently delete your account?").font(ShogunTheme.Typography.profileTitle)
                    Text("This deletes your sign-in, profile, personal activity, and libraries you own—including shared libraries and their copies. It cannot be undone.")
                    Text("Movie metadata used by other accounts remains available to them.").font(ShogunTheme.Typography.footnote).foregroundStyle(.secondary)
                }
                Section("Confirm your identity") {
                    SecureField("Current password", text: $password).textContentType(.password)
                        .focused($passwordFocused).submitLabel(.done)
                        .onSubmit { passwordFocused = false }
                        .disabled(auth.isBusy).accessibilityIdentifier("auth.deletePassword")
                }
                Section {
                    if let error = auth.error { Text(error).foregroundStyle(.red).accessibilityIdentifier("auth.deleteError") }
                    if auth.isBusy { ProgressView("Deleting account…") }
                    Button("Delete account", role: .destructive) { passwordFocused = false; confirming = true }
                        .disabled(password.isEmpty || auth.isBusy).accessibilityIdentifier("auth.requestDeletion")
                }
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden).background(ShogunTheme.canvas)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { auth.clearFeedback(); dismiss() }.disabled(auth.isBusy) } }
                .interactiveDismissDisabled(auth.isBusy)
                .alert("Delete your account permanently?", isPresented: $confirming) {
                    Button("Delete permanently", role: .destructive) { auth.deleteAccount(password: password); password = "" }
                    Button("Keep account", role: .cancel) {}
                } message: { Text("Your account and owned libraries will be removed from Shogun.") }
                .onDisappear { password = "" }
        }
    }
}
