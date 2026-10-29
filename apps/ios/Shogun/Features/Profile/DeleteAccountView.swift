import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @FocusState private var passwordFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Text("Permanently delete your account?").font(
                            ShogunTheme.Typography.profileTitle)
                        Text(
                            "This deletes your sign-in, profile, personal activity, and libraries you own—including shared libraries and their copies. It cannot be undone."
                        )
                        Text("Movie metadata used by other accounts remains available to them.")
                            .font(
                                ShogunTheme.Typography.footnote
                            ).foregroundStyle(ShogunTheme.muted)
                    }
                    Section("Confirm your identity") {
                        SecureField("Current password", text: $password).textContentType(.password)
                            .focused($passwordFocused).submitLabel(.done)
                            .onSubmit { passwordFocused = false }
                            .disabled(auth.isBusy).accessibilityIdentifier("auth.deletePassword")
                    }
                    Section {
                        if let error = auth.error {
                            Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                                "auth.deleteError")
                        }
                        if auth.isBusy { ProgressView("Deleting account…") }
                        Button("Delete account", role: .destructive) {
                            passwordFocused = false
                            confirming = true
                        }
                        .disabled(password.isEmpty || auth.isBusy).accessibilityIdentifier(
                            "auth.requestDeletion")
                    }

                }.listRowBackground(ShogunTheme.surface)
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle("Delete account").navigationBarTitleDisplayMode(.inline)
                .shogunListCanvas()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            auth.clearFeedback()
                            dismiss()
                        }.disabled(auth.isBusy)
                    }
                }
                .interactiveDismissDisabled(auth.isBusy)
                .alert("Delete your account permanently?", isPresented: $confirming) {
                    Button("Delete permanently", role: .destructive) {
                        auth.deleteAccount(password: password)
                        password = ""
                    }
                    Button("Keep account", role: .cancel) {}
                } message: {
                    Text("Your account and owned libraries will be removed from Shogun.")
                }
                .onDisappear { password = "" }
        }
    }
}
