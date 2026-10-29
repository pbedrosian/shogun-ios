import SwiftUI

struct AuthHeader: View {
    let title: String
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.large) {
            ViewThatFits(in: .horizontal) {
                ShogunWordmark(width: ShogunTheme.Brand.authWidth)
                ShogunWordmark()
            }
            .accessibilityIdentifier("auth.brand")
            Text(title).font(ShogunTheme.Typography.authTitle).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity).padding(.bottom, ShogunTheme.Spacing.small)
    }
}

struct AuthPasswordField: View {
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
                    if visible {
                        TextField(
                            isNew ? "At least 8 characters" : "Enter your password", text: $text)
                    } else {
                        SecureField(
                            isNew ? "At least 8 characters" : "Enter your password", text: $text)
                    }
                }.textContentType(isNew ? .newPassword : .password)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($isFocused).submitLabel(next ? .next : .go).onSubmit(onSubmit)
                    .accessibilityLabel(title).accessibilityIdentifier(identifier)
                Button {
                    visible.toggle()
                    isFocused = true
                } label: {
                    Image(systemName: visible ? "eye.slash" : "eye").foregroundStyle(
                        ShogunTheme.muted
                    )
                    .frame(
                        minWidth: ShogunTheme.Size.touchTarget,
                        minHeight: ShogunTheme.Size.touchTarget)
                }.buttonStyle(.plain).accessibilityLabel(
                    visible ? "Hide \(title.lowercased())" : "Show \(title.lowercased())"
                )
                .accessibilityIdentifier(identifier + ".visibility")
            }.shogunAuthField()
        }
    }
}

struct AuthFeedback: View {
    @EnvironmentObject private var auth: AuthStore
    var body: some View {
        if let error = auth.error {
            Text(error).foregroundStyle(ShogunTheme.error).accessibilityIdentifier("auth.error")
        }
        if let message = auth.message {
            Text(message).foregroundStyle(ShogunTheme.success).accessibilityIdentifier(
                "auth.message")
        }
    }
}
