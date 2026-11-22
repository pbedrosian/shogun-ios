import SwiftUI
import UIKit

/// Geometry policy shared by edge scrolling and drop selection, independent of saved order.
enum LibraryGridScrollPolicy {
    static func velocity(y: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        let y = min(height, max(0, y))
        let band = min(80, height / 4)
        if y < band { return -480 * (1 - y / band) }
        if y > height - band { return 480 * (1 - (height - y) / band) }
        return 0
    }

    static func target(at point: CGPoint, frames: [String: CGRect], viewport: CGRect) -> String? {
        frames.filter { $0.value.intersects(viewport) }.min { lhs, rhs in
            func distance(_ rect: CGRect) -> CGFloat {
                let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
                let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
                return dx * dx + dy * dy
            }
            let left = distance(lhs.value)
            let right = distance(rhs.value)
            return left == right ? lhs.key < rhs.key : left < right
        }?.key
    }
}

/// Keeps the drag on the scroll container, so recycled/offscreen tiles cannot lose the finger.
/// UIKit owns touch arbitration and scrolling; the screen receives only movie/position intents.
struct LibraryGridInteraction: UIViewRepresentable {
    let isEnabled: Bool
    let isArranging: Bool
    let frames: [String: CGRect]
    let anchorOrigin: CGPoint
    let onBegin: () -> Void
    let onMove: (String, CGPoint, String?) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let anchor = UIView()
        anchor.isUserInteractionEnabled = false
        return anchor
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.update(self)
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view else { return }
            var ancestor = view.superview
            while let candidate = ancestor {
                if let scroll = candidate as? UIScrollView {
                    coordinator?.attach(to: scroll, anchor: view)
                    break
                }
                ancestor = candidate.superview
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var configuration: LibraryGridInteraction
        private weak var scroll: UIScrollView?
        private weak var anchor: UIView?
        private var heldID: String?
        private var grabOffset: CGSize = .zero
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var originalMinimumTouches: Int?
        private lazy var hold: UILongPressGestureRecognizer = {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(pressed))
            recognizer.minimumPressDuration = 0.25
            recognizer.allowableMovement = 10
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = true
            return recognizer
        }()

        init(_ configuration: LibraryGridInteraction) { self.configuration = configuration }

        func update(_ configuration: LibraryGridInteraction) {
            let shouldCancel =
                heldID != nil && (!configuration.isEnabled || !configuration.isArranging)
            self.configuration = configuration
            if shouldCancel { hold.isEnabled = false }
            hold.isEnabled = configuration.isEnabled
        }
        func attach(to scroll: UIScrollView, anchor: UIView) {
            self.anchor = anchor
            guard self.scroll !== scroll else { return }
            detach()
            self.scroll = scroll
            scroll.addGestureRecognizer(hold)
            hold.isEnabled = configuration.isEnabled
        }
        func detach() {
            finish()
            scroll?.removeGestureRecognizer(hold)
            scroll = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        )
            -> Bool
        {
            // Ignore extra fingers in the hold recognizer; the scroll pan still receives them.
            guard heldID == nil, configuration.isEnabled, let anchor else { return false }
            let point = gridPoint(touch.location(in: anchor))
            return configuration.frames.values.contains { $0.contains(point) }
        }
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer === scroll?.panGestureRecognizer
        }

        @objc private func pressed() {
            guard let scroll, let anchor else { return }
            switch hold.state {
            case .began:
                let point = gridPoint(hold.location(in: anchor))
                guard
                    let (id, frame) = configuration.frames.first(where: { $0.value.contains(point) }
                    )
                else { return }
                heldID = id
                grabOffset = CGSize(width: frame.midX - point.x, height: frame.midY - point.y)
                originalMinimumTouches = scroll.panGestureRecognizer.minimumNumberOfTouches
                scroll.panGestureRecognizer.minimumNumberOfTouches = 2
                configuration.onBegin()
                sendPosition()
                let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
                displayLink = link
                link.add(to: .main, forMode: .common)
            case .changed:
                sendPosition()
            case .ended, .cancelled, .failed:
                finish()
            default: break
            }
        }

        // The UIKit scroll viewport can extend under SwiftUI's safe area.
        // Use the embedded view as the shared origin for touches and tile frames.
        private func gridPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x + configuration.anchorOrigin.x,
                y: point.y + configuration.anchorOrigin.y)
        }
        private func sendPosition() {
            guard let id = heldID, let scroll, let anchor else { return }
            let point = gridPoint(hold.location(in: anchor))
            let visibleRect = scroll.convert(viewport(in: scroll), to: anchor)
            let target = LibraryGridScrollPolicy.target(
                at: point, frames: configuration.frames,
                viewport: visibleRect.offsetBy(
                    dx: configuration.anchorOrigin.x, dy: configuration.anchorOrigin.y))
            let previewCenter = CGPoint(
                x: point.x + grabOffset.width, y: point.y + grabOffset.height)
            configuration.onMove(id, previewCenter, target)
        }
        private func viewport(in scroll: UIScrollView) -> CGRect {
            let insets = scroll.adjustedContentInset
            return scroll.bounds.inset(by: insets)
        }
        @objc private func tick(_ link: CADisplayLink) {
            guard heldID != nil, let scroll else { return }
            let elapsed =
                lastTimestamp == 0 ? link.duration : min(link.timestamp - lastTimestamp, 1 / 30)
            lastTimestamp = link.timestamp
            // A second finger controls the page directly; do not fight it with edge scrolling.
            if scroll.panGestureRecognizer.numberOfTouches < 2 {
                let viewport = viewport(in: scroll)
                let velocity = LibraryGridScrollPolicy.velocity(
                    y: hold.location(in: scroll).y - viewport.minY, height: viewport.height)
                let minimum = -scroll.adjustedContentInset.top
                let maximum = max(
                    minimum,
                    scroll.contentSize.height - scroll.bounds.height
                        + scroll.adjustedContentInset.bottom)
                let y = min(maximum, max(minimum, scroll.contentOffset.y + velocity * elapsed))
                if y != scroll.contentOffset.y {
                    scroll.setContentOffset(
                        CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
                }
            }
            // Re-evaluate after scrolling even when the held finger does not move.
            sendPosition()
        }
        private func finish() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
            if let minimum = originalMinimumTouches {
                scroll?.panGestureRecognizer.minimumNumberOfTouches = minimum
            }
            originalMinimumTouches = nil
            if heldID != nil {
                heldID = nil
                configuration.onEnd()
            }
        }
    }
}
