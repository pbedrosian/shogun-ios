import SwiftUI

/// Shared icon label for header Buttons and Menus, including a full touch target.
struct ShogunIcon: View {
    let systemName: String
    var font: Font = ShogunTheme.Typography.actionIcon
    // Native toolbar controls provide their own hit target and padding.
    var includesTouchTarget = true
    var body: some View {
        Image(systemName: systemName).font(font)
            .frame(
                width: includesTouchTarget ? ShogunTheme.Size.touchTarget : nil,
                height: includesTouchTarget ? ShogunTheme.Size.touchTarget : nil)
    }
}

/// Displays the approved artwork without recreating its lettering in a font.
struct ShogunWordmark: View {
    var width: CGFloat = ShogunTheme.Brand.compactWidth

    var body: some View {
        Image("ShogunWordmark")
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width / ShogunTheme.Brand.aspectRatio)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: ShogunTheme.Radius.poster))
            .accessibilityLabel("Shogun")
            .accessibilityAddTraits(.isImage)
    }
}
