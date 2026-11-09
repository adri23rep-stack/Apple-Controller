import SwiftUI
import UIKit

@MainActor
struct TrackpadView: View {
    @ObservedObject var remote: RemoteClient
    @State private var touching = false
    @State private var moved = false
    @State private var holding = false
    @State private var lastTranslation = CGSize.zero
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.13, green: 0.14, blue: 0.19))
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    holding ? Color(red: 0.96, green: 0.25, blue: 0.35) :
                        Color.white.opacity(0.13),
                    lineWidth: holding ? 2.5 : 1
                )
            VStack(spacing: 12) {
                Image(systemName: holding ? "hand.point.up.left.fill" : "hand.draw.fill")
                    .font(.system(size: 27, weight: .light))
                    .foregroundStyle(holding ? Color.red : Color.white.opacity(0.7))
                Text(holding ? "ARRASTRANDO" : "TRACKPAD")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.75))
                Text("Desliza para mover · Toca para hacer clic")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.54))
                Text("Mantén presionado para arrastrar")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.46))
            }
            .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { gesture in
                    if !touching { beginTouch() }

                    let dx = gesture.translation.width - lastTranslation.width
                    let dy = gesture.translation.height - lastTranslation.height
                    lastTranslation = gesture.translation

                    let distance = hypot(gesture.translation.width, gesture.translation.height)
                    if distance > 11 {
                        moved = true
                        if !holding { holdTask?.cancel() }
                    }
                    let x = Int((dx * 1.55).rounded())
                    let y = Int((dy * 1.55).rounded())
                    if x != 0 || y != 0 {
                        remote.send("pointer_move", dx: x, dy: y)
                    }
                }
                .onEnded { gesture in
                    holdTask?.cancel()
                    if holding {
                        remote.send("pointer_up")
                    } else if !moved &&
                                hypot(gesture.translation.width, gesture.translation.height) < 11 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        remote.send("click")
                    }
                    touching = false
                    holding = false
                    moved = false
                    lastTranslation = .zero
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trackpad del control remoto")
        .accessibilityHint("Arrastra para mover, toca para hacer clic, mantén para arrastrar")
    }

    private func beginTouch() {
        touching = true
        moved = false
        holding = false
        lastTranslation = .zero
        holdTask?.cancel()
        holdTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, touching, !moved, !holding else { return }
            holding = true
            remote.send("pointer_down")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}
