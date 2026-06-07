import SwiftUI

/// Easter-egg overlay: confetti-style 🥒 particles launched up from the bottom
/// of the editor canvas, peaking near mid-height, then falling back through the
/// floor under gravity. Triggered by mutating `trigger` (any new UUID = new
/// burst). Ported from pizzaClip's `PizzaBurst`, themed to the pickle 🥒.
///
/// Renders each particle as a real `Text` view positioned with `.position()`
/// and rotated with `.rotationEffect`. Canvas + `gc.draw(text:)` was tried
/// first but emojis sometimes fail to rasterise inside a Canvas draw layer
/// on macOS 13 — plain SwiftUI views avoid that entire failure mode.
struct PickleBurst: View {
    let trigger: UUID?

    @State private var startedAt: Date = .distantPast
    @State private var particles: [Particle] = []

    private let duration: TimeInterval = 2.4
    private let gravity: CGFloat = 600   // px/s² — tuned for a ~640pt canvas

    struct Particle: Identifiable {
        let id = UUID()
        let x0Norm: CGFloat       // 0…1 of width
        let vySpeed: CGFloat      // upward initial speed (px/s)
        let vx: CGFloat           // sideways drift (px/s)
        let angle0: CGFloat       // initial rotation (rad)
        let omega: CGFloat        // angular velocity (rad/s)
        let delay: TimeInterval   // stagger so particles don't all launch on frame 0
        let size: CGFloat         // emoji font size
        let emoji: String
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                ZStack(alignment: .topLeading) {
                    // Anchor so the GeometryReader-driven ZStack actually expands
                    // to fill the proposed size even when no live particles
                    // are inside it.
                    Color.clear
                    ForEach(particles) { p in
                        particleView(p, elapsed: elapsed, size: geo.size)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .allowsHitTesting(false)
        // `.task(id:)` fires on first mount AND on every `trigger` change, so
        // we catch the case where the canvas is being mounted from scratch
        // with a non-nil burst ID already set. `.onChange` alone would miss
        // that initial-mount fire and the burst would never play.
        .task(id: trigger) {
            guard trigger != nil else { return }
            startedAt = Date()
            particles = PickleBurst.makeParticles()
        }
    }

    @ViewBuilder
    private func particleView(_ p: Particle, elapsed: TimeInterval, size: CGSize) -> some View {
        let t = elapsed - p.delay
        if t >= 0, t <= duration, size.width > 0, size.height > 0 {
            let tt = CGFloat(t)
            let h = p.vySpeed * tt - 0.5 * gravity * tt * tt
            let x = p.x0Norm * size.width + p.vx * tt
            let y = size.height - h
            let angle = p.angle0 + p.omega * tt
            let life = duration - p.delay
            let opacity: Double = {
                if t < 0.12 { return Double(t / 0.12) }
                if t > life - 0.35 { return max(0, Double((life - t) / 0.35)) }
                return 1
            }()

            Text(p.emoji)
                .font(.system(size: p.size))
                .rotationEffect(.radians(Double(angle)))
                .position(x: x, y: y)
                .opacity(opacity)
        }
    }

    private static func makeParticles() -> [Particle] {
        (0..<48).map { _ in
            Particle(
                x0Norm: CGFloat.random(in: 0.08...0.92),
                vySpeed: CGFloat.random(in: 360...560),
                vx: CGFloat.random(in: -70...70),
                angle0: CGFloat.random(in: 0...(2 * .pi)),
                omega: CGFloat.random(in: -4...4),
                delay: TimeInterval.random(in: 0...0.32),
                size: CGFloat.random(in: 16...30),
                emoji: "🥒"
            )
        }
    }
}
