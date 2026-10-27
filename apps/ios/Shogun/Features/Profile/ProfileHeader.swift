import SwiftUI

/// Shared between the original catalog fixture and the authenticated profile.
struct ProfileHeader: View {
    let name: String
    let email: String
    let badge: String
    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.medium) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: ShogunTheme.Size.profileAvatar)).foregroundStyle(
                    ShogunTheme.accent
                ).accessibilityHidden(true)
            Text(name).font(ShogunTheme.Typography.profileTitle)
            Text(email).foregroundStyle(.secondary).accessibilityIdentifier("auth.accountEmail")
            Text(badge).font(ShogunTheme.Typography.disclosure)
                .padding(.horizontal, ShogunTheme.Spacing.control).padding(
                    .vertical, ShogunTheme.Spacing.compact
                )
                .background(.quaternary, in: Capsule())
        }.frame(maxWidth: .infinity).padding(.vertical)
    }
}
