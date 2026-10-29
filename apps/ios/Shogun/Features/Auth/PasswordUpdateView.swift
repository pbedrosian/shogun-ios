import SwiftUI

struct PasswordUpdateView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var password = ""
    @FocusState private var focused: Bool
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ShogunTheme.Spacing.large) {
                AuthHeader(title: "Reset password")
                AuthPasswordField(
                    title: "New password", identifier: "auth.newPassword", text: $password,
                    isFocused: $focused, isNew: true, next: false, onSubmit: update
                ).disabled(auth.isBusy)
                AuthFeedback()
                Button(action: update) { Text("Update password") }
                    .buttonStyle(ShogunAuthPrimaryButtonStyle()).disabled(auth.isBusy)
                    .accessibilityIdentifier("auth.updatePassword")
                if auth.isBusy { ProgressView("Updating password…") }
                Button("Cancel", action: auth.signOut).frame(
                    maxWidth: .infinity, minHeight: ShogunTheme.Size.touchTarget
                ).disabled(auth.isBusy)
            }.shogunAuthContent()
        }.scrollDismissesKeyboard(.interactively).shogunCanvas()
    }
    private func update() {
        focused = false
        auth.updatePassword(password)
        password = ""
    }
}
