import SwiftUI
import UIKit

// Native UIKit touch tracking instead of SwiftUI DragGesture: distinguishes
// one finger (cursor/click/hold-to-drag) from two fingers (mouse-wheel scroll).
@MainActor
struct TrackpadView: View {
    @ObservedObject var remote: RemoteClient
    @State private var dragging = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 19)
                .fill(Color(red: 0.112, green: 0.137, blue: 0.188))
            RoundedRectangle(cornerRadius: 19)
                .strokeBorder(dragging ? Color(red: 0.71, green: 0.65, blue: 1) :
                              .white.opacity(0.12), lineWidth: dragging ? 2 : 1)

            VStack(spacing: 6) {
                Image(systemName: dragging ? "hand.point.up.left.fill" : "hand.draw")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.65))
                Text(dragging ? "ARRASTRANDO" : "TRACKPAD")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(2)
                Text("1 dedo: mover y tocar para clic")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.64))
                Text("2 dedos: desplazamiento vertical")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .allowsHitTesting(false)

            TrackpadSurface(
                onMove: { dx, dy in remote.send("pointer_move", dx: dx, dy: dy) },
                onWheel: { ticks in remote.send("wheel", value: ticks) },
                onClick: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    remote.send("click")
                },
                onDown: {
                    dragging = true
                    remote.send("pointer_down")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                },
                onUp: {
                    dragging = false
                    remote.send("pointer_up")
                }
            )
            .accessibilityLabel("Trackpad. Un dedo para mover o hacer clic. Dos dedos para desplazarse.")
        }
    }
}

private struct TrackpadSurface: UIViewRepresentable {
    let onMove: (Int, Int) -> Void
    let onWheel: (Int) -> Void
    let onClick: () -> Void
    let onDown: () -> Void
    let onUp: () -> Void

    func makeUIView(context: Context) -> TouchpadSurfaceView {
        let view = TouchpadSurfaceView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchpadSurfaceView, context: Context) {
        uiView.onMove = onMove
        uiView.onWheel = onWheel
        uiView.onClick = onClick
        uiView.onDown = onDown
        uiView.onUp = onUp
    }
}

private final class TouchpadSurfaceView: UIView {
    var onMove: ((Int, Int) -> Void)?
    var onWheel: ((Int) -> Void)?
    var onClick: (() -> Void)?
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?

    private var active = Set<UITouch>()
    private var lastPoint: CGPoint?
    private var scrollY: CGFloat?
    private var scrollRemainder: CGFloat = 0
    private var moved = false
    private var didHold = false
    private var scrolling = false
    private var holdWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    private func cancelHold() {
        holdWork?.cancel()
        holdWork = nil
    }

    private func beginHold() {
        cancelHold()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.active.count == 1, !self.moved,
                  !self.didHold, !self.scrolling else { return }
            self.didHold = true
            self.onDown?()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50, execute: work)
    }

    private func averageY() -> CGFloat? {
        guard active.count >= 2 else { return nil }
        return active.prefix(2).reduce(CGFloat(0)) { $0 + $1.location(in: self).y } / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        active.formUnion(touches)
        if active.count >= 2 {
            if didHold { onUp?(); didHold = false }
            cancelHold()
            scrolling = true
            moved = true
            scrollY = averageY()
            scrollRemainder = 0
            lastPoint = nil
        } else if let touch = active.first, !scrolling {
            moved = false
            lastPoint = touch.location(in: self)
            beginHold()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if active.count >= 2 && scrolling {
            guard let y = averageY() else { return }
            if let previous = scrollY {
                scrollRemainder += y - previous
                // Approx. 18 screen points per wheel notch, capped per event.
                let ticks = Int(scrollRemainder / 18)
                if ticks != 0 {
                    let bounded = min(4, max(-4, ticks))
                    onWheel?(-bounded) // touch down = scroll content down
                    scrollRemainder -= CGFloat(bounded * 18)
                }
            }
            scrollY = y
            return
        }
        guard active.count == 1, !scrolling, let touch = active.first else { return }
        let current = touch.location(in: self)
        guard let previous = lastPoint else { lastPoint = current; return }
        lastPoint = current
        let dx = current.x - previous.x, dy = current.y - previous.y
        if hypot(dx, dy) > 1 {
            moved = true
            if !didHold { cancelHold() }
            let x = Int((dx * 1.6).rounded()), y = Int((dy * 1.6).rounded())
            if x != 0 || y != 0 { onMove?(x, y) }
        }
    }

    private func finish(_ touches: Set<UITouch>) {
        active.subtract(touches)
        cancelHold()
        if active.isEmpty {
            if didHold { onUp?() }
            else if !moved && !scrolling { onClick?() }
            lastPoint = nil
            scrollY = nil
            scrollRemainder = 0
            didHold = false
            moved = false
            scrolling = false
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        moved = true // never click when interrupted
        finish(touches)
    }
}
