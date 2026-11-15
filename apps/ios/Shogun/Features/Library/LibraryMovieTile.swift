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
    let dragOffset: CGSize
    let onBegin: () -> Void
    let onNavigate: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void
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
                        .highPriorityGesture(
                            LongPressGesture(minimumDuration: 0.25)
                                .sequenced(
                                    before: DragGesture(
                                        minimumDistance: 8, coordinateSpace: .named("library.grid")))
                                .onChanged { value in
                                    if case .second(true, let drag?) = value {
                                        onDragChanged(drag.location)
                                    }
                                }
                                .onEnded { _ in onDragEnded() }
                        )
                        .scaleEffect(isDragging ? 1.03 : 1)
                        .offset(dragOffset)
                } else {
                    navigationTile(movie)
                        .overlay {
                            MoviePressGestureTarget(onTap: onNavigate, onHold: onBegin)
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

/// Bridges native press recognition without coupling navigation to gesture phases.
private struct MoviePressGestureTarget: UIViewRepresentable {
    let onTap: () -> Void
    let onHold: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap, onHold: onHold) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let hold = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 0.25
        hold.allowableMovement = 10
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.require(toFail: hold)
        view.addGestureRecognizer(hold)
        view.addGestureRecognizer(tap)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onHold = onHold
    }
    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onHold: () -> Void
        init(onTap: @escaping () -> Void, onHold: @escaping () -> Void) {
            self.onTap = onTap
            self.onHold = onHold
        }
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            if gesture.state == .ended { onTap() }
        }
        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { onHold() }
        }
    }
}
