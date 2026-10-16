import SwiftUI

/// Shared icon label for header Buttons and Menus, including a full touch target.
struct ShogunIcon: View {
    let systemName: String
    var font: Font = ShogunTheme.Typography.actionIcon
    var body: some View {
        Image(systemName: systemName).font(font)
            .frame(width: ShogunTheme.Size.touchTarget, height: ShogunTheme.Size.touchTarget)
    }
}
