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

struct ShogunAuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, ShogunTheme.Spacing.regular)
            .padding(.vertical, ShogunTheme.Spacing.compact)
            .frame(minHeight: ShogunTheme.Auth.fieldHeight)
            .background(ShogunTheme.surface, in: RoundedRectangle(cornerRadius: ShogunTheme.Radius.control))
    }
}
struct ShogunAuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ShogunTheme.Typography.headline)
            .frame(maxWidth: .infinity, minHeight: ShogunTheme.Auth.fieldHeight)
            .padding(.vertical, ShogunTheme.Spacing.tight)
            .foregroundStyle(ShogunTheme.onAccent)
            .background(ShogunTheme.authPrimary, in: Capsule())
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
    }
}
extension View {
    func shogunAuthField() -> some View { modifier(ShogunAuthFieldStyle()) }
}

struct ShogunAuthTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(ShogunTheme.Typography.emphasizedBody)
            .frame(minHeight: ShogunTheme.Size.touchTarget)
            .contentShape(Rectangle()).foregroundStyle(ShogunTheme.accent)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
