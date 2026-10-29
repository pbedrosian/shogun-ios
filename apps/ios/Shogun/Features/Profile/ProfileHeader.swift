import SwiftUI

/// Compact account identity shared by connected and fixture profiles.
struct ProfileHeader: View {
    let name: String
    let email: String
    let badge: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: ShogunTheme.Spacing.control) {
                    avatar
                    identity
                }
            } else {
                HStack(spacing: ShogunTheme.Spacing.regular) {
                    avatar
                    identity
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, ShogunTheme.Spacing.small)
    }
    private var avatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: ShogunTheme.Size.profileAvatar))
            .foregroundStyle(ShogunTheme.accent)
            .accessibilityHidden(true)
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: ShogunTheme.Spacing.tight) {
            Text(name).font(ShogunTheme.Typography.profileTitle)
            Text(email).font(ShogunTheme.Typography.body)
                .foregroundStyle(ShogunTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("auth.accountEmail")
            Text(badge).font(ShogunTheme.Typography.caption)
                .foregroundStyle(ShogunTheme.muted)
        }
    }
}
