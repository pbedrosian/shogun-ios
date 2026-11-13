import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @State private var usePassword = false
    private var usesGoogle: Bool { auth.googleDeletionAvailable && !usePassword }
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
                        if usesGoogle {
                            Text(
                                "Sign in with Google as \(auth.account?.email ?? "your current account") to confirm deletion."
                            )
                            .accessibilityIdentifier("auth.deleteGoogleIdentity")
                        } else {
                            SecureField("Current password", text: $password).textContentType(
                                .password
                            )
                            .focused($passwordFocused).submitLabel(.done)
                            .onSubmit { passwordFocused = false }
                            .disabled(auth.isBusy).accessibilityIdentifier("auth.deletePassword")
                        }
                        if auth.googleDeletionAvailable {
                            Button(usesGoogle ? "Use password instead" : "Use Google instead") {
                                usePassword.toggle()
                                password = ""
                                auth.clearFeedback()
                            }.disabled(auth.isBusy)
                        }
                    }
                    Section {
                        if let error = auth.error {
                            Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                                "auth.deleteError")
                        }
                        if auth.isBusy {
                            ProgressView(
                                usesGoogle
                                    ? "Confirming and deleting account…" : "Deleting account…")
                        }
                        Button("Delete account", role: .destructive) {
                            passwordFocused = false
                            confirming = true
                        }
                        .disabled((!usesGoogle && password.isEmpty) || auth.isBusy)
                        .accessibilityIdentifier(
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
                        if usesGoogle {
                            auth.deleteAccountWithGoogle()
                        } else {
                            auth.deleteAccount(password: password)
                        }
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
