import SwiftUI

struct DeleteAccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirming = false
    @State private var usePassword = false
    private var hasApple: Bool { auth.account?.appleIdentityLinked == true }
    private var usesApple: Bool { hasApple && !usePassword }
    private var usesGoogle: Bool { !hasApple && auth.googleDeletionAvailable && !usePassword }
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
                        if usesApple {
                            Text(
                                auth.appleDeletionAvailable
                                    ? "Confirm with the Apple Account connected to this Shogun account. Apple authorization will be revoked before your account is deleted."
                                    : "Apple account deletion is not available in this build yet."
                            )
                            .accessibilityIdentifier("auth.deleteAppleIdentity")
                        } else if usesGoogle {
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
                        if hasApple && usePassword {
                            Text(
                                "Use your Shogun password if you can’t confirm with Apple. After deletion, remove Shogun from Sign in with Apple in your Apple Account settings."
                            )
                            .font(ShogunTheme.Typography.footnote)
                            .foregroundStyle(ShogunTheme.muted)
                            .accessibilityIdentifier("auth.appleDeletionFallbackNotice")
                        }
                        if hasApple && auth.appleDeletionAvailable {
                            Button(usesApple ? "Can’t use Apple?" : "Use Apple instead") {
                                usePassword.toggle()
                                password = ""
                                auth.clearFeedback()
                            }.disabled(auth.isBusy).accessibilityIdentifier(
                                "auth.appleDeletionFallback")
                        }
                        if auth.googleDeletionAvailable && !hasApple {
                            Button(usesGoogle ? "Use password instead" : "Use Google instead") {
                                usePassword.toggle()
                                password = ""
                                auth.clearFeedback()
                            }.disabled(auth.isBusy)
                        }
                    }
                    if hasApple {
                        Section {
                            Link(
                                "Request help deleting your account",
                                destination: URL(
                                    string:
                                        "mailto:feedback@getshogun.app?subject=Shogun%20account%20deletion%20request"
                                )!)
                        } footer: {
                            Text(
                                "If you can’t confirm with Apple or your Shogun password, contact support to request account deletion."
                            )
                        }
                    }
                    Section {
                        if let error = auth.error {
                            Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier(
                                "auth.deleteError")
                        }
                        if auth.isBusy {
                            ProgressView(
                                usesGoogle || usesApple
                                    ? "Confirming and deleting account…" : "Deleting account…")
                        }
                        Button("Delete account", role: .destructive) {
                            passwordFocused = false
                            confirming = true
                        }
                        .disabled(
                            (hasApple && !auth.appleDeletionAvailable)
                                || (!usesApple && !usesGoogle && password.isEmpty) || auth.isBusy
                        )
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
                        if hasApple && usePassword {
                            auth.deleteAccountWithApplePassword(password)
                        } else if usesApple {
                            auth.deleteAccountWithApple()
                        } else if usesGoogle {
                            auth.deleteAccountWithGoogle()
                        } else {
                            auth.deleteAccount(password: password)
                        }
                        password = ""
                    }
                    Button("Keep account", role: .cancel) {}
                } message: {
                    Text(
                        hasApple && usePassword
                            ? "Your Shogun account and owned libraries will be removed. You’ll also need to remove Shogun’s Apple access in your Apple Account settings."
                            : "Your account and owned libraries will be removed from Shogun.")
                }
                .onDisappear { password = "" }
        }
    }
}
