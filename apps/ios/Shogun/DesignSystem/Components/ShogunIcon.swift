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

/// The approved chrome loading loop, rendered natively at the current appearance.
struct ShogunLoadingView: View {
    let label: LocalizedStringKey
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ label: LocalizedStringKey) { self.label = label }

    var body: some View {
        VStack(spacing: ShogunTheme.Spacing.regular) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let phase =
                    reduceMotion
                    ? 0
                    : context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: ShogunTheme.Loading.cycleDuration)
                        / ShogunTheme.Loading.cycleDuration
                VStack(spacing: ShogunTheme.Spacing.control) {
                    ShogunWordmark()
                        .opacity(reduceMotion ? 1 : 0.95 + 0.05 * cos(phase * .pi * 2))
                        .overlay {
                            if !reduceMotion, phase < ShogunTheme.Loading.sweepFraction {
                                GeometryReader { geometry in
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.55), .clear],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                    .frame(width: geometry.size.width / 4)
                                    .offset(
                                        x: geometry.size.width
                                            * (phase / ShogunTheme.Loading.sweepFraction * 1.5
                                                - 0.25))
                                }
                                .mask { ShogunWordmark() }
                            }
                        }
                    HStack(spacing: ShogunTheme.Spacing.small) {
                        ForEach(0..<3) { index in
                            let pulse =
                                reduceMotion
                                ? 0.5
                                : pow(max(0, cos(phase * .pi * 2 - Double(index) * 0.8)), 3)
                            Circle().fill(ShogunTheme.accent)
                                .frame(
                                    width: ShogunTheme.Loading.dotSize,
                                    height: ShogunTheme.Loading.dotSize
                                )
                                .opacity(0.2 + 0.75 * pulse)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.vertical, ShogunTheme.Spacing.regular)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue("In progress")
    }
}
