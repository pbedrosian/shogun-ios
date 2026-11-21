import SwiftUI

/// Owns tile gestures and presentation; ordering and navigation are emitted as intent.
struct LibraryMovieTile: View {
    let movie: Movie
    let compact: Bool
    let formatDescription: String
    let isCustom: Bool
    let isArranging: Bool
    let isPinching: Bool
    let isDragging: Bool
    let onBegin: () -> Void
    let onNavigate: () -> Void
    let onMoveOffset: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if isCustom {
            Group {
                if isArranging {
                    navigationTile(movie)
                        .modifier(
                            ShogunJiggleStyle(
                                phase: Double(movie.id.utf8.reduce(0) { ($0 + Int($1)) % 20 })
                                    * 0.3, isEnabled: !isDragging
                            )
                        )
                        .opacity(isDragging ? 0 : 1)
                } else {
                    navigationTile(movie)
                        .overlay {
                            MoviePressGestureTarget(onTap: onNavigate)
                                .accessibilityHidden(true)
                        }
                }
            }
            .accessibilityHint(
                isArranging
                    ? "Drag to rearrange, or use the move actions."
                    : "Touch and hold to arrange movies."
            )
            .accessibilityAction(named: "Move earlier") {
                onBegin()
                onMoveOffset(-1)
            }
            .accessibilityAction(named: "Move later") {
                onBegin()
                onMoveOffset(1)
            }
        } else {
            navigationTile(movie)
        }
    }
    private func navigationTile(_ movie: Movie) -> some View {
        Group {
            if isArranging {
                movieCard(movie)
            } else {
                NavigationLink(value: movie) { movieCard(movie) }
                    .buttonStyle(.plain).disabled(isPinching)
            }
        }
        .accessibilityIdentifier("library.movie.\(movie.id)")
        .contentShape(Rectangle())
    }
    private func movieCard(_ movie: Movie) -> some View {
        MovieCard(
            movie: movie, compact: compact,
            formats: formatDescription
        )
        .overlay {
            if isArranging {
                RoundedRectangle(cornerRadius: ShogunTheme.Radius.poster)
                    .strokeBorder(ShogunTheme.accent.opacity(0.5))
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Follows the finger outside grid layout, while its empty cell reserves the drop position.
struct LibraryLiftedMovie: View {
    let movie: Movie
    let compact: Bool
    let formats: String
    let size: CGSize
    let location: CGPoint

    var body: some View {
        MovieCard(movie: movie, compact: compact, formats: formats)
            .frame(width: size.width, height: size.height, alignment: .top)
            .scaleEffect(1.03)
            .shadow(
                color: .black.opacity(0.25), radius: ShogunTheme.Spacing.small,
                y: ShogunTheme.Spacing.tight
            )
            .position(x: location.x, y: location.y - ShogunTheme.Spacing.tight)
            .transaction { $0.animation = nil }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Bridges native press recognition without coupling navigation to gesture phases.
private struct MoviePressGestureTarget: UIViewRepresentable {
    let onTap: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }
    final class Coordinator: NSObject {
        var onTap: () -> Void
        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { onTap() }
        }
    }
}
