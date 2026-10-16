import SwiftUI

struct ShogunCanvasStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.background(ShogunTheme.canvas).foregroundStyle(ShogunTheme.ink)
    }
}
struct ShogunSurfaceStyle: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content.padding(padding).background(ShogunTheme.surface, in: RoundedRectangle(cornerRadius: ShogunTheme.Radius.control))
    }
}
struct ShogunBrandStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(ShogunTheme.Typography.brand).tracking(2).foregroundStyle(ShogunTheme.accent)
    }
}
struct MovieTitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(ShogunTheme.Typography.cardTitle)
            .lineLimit(2, reservesSpace: true)
            .fixedSize(horizontal: false, vertical: true)
    }
}
struct MovieMetadataStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(ShogunTheme.Typography.small).foregroundStyle(ShogunTheme.muted)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}
struct ShogunRatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ShogunTheme.Typography.actionIcon)
            .frame(minWidth: ShogunTheme.Size.ratingWidth, minHeight: ShogunTheme.Size.touchTarget)
            .foregroundStyle(.orange)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
extension View {
    func shogunCanvas() -> some View { modifier(ShogunCanvasStyle()) }
    func shogunSurface(padding: CGFloat = ShogunTheme.Spacing.control) -> some View { modifier(ShogunSurfaceStyle(padding: padding)) }
    func shogunBrand() -> some View { modifier(ShogunBrandStyle()) }
    func movieTitleStyle() -> some View { modifier(MovieTitleStyle()) }
    func movieMetadataStyle() -> some View { modifier(MovieMetadataStyle()) }
}
