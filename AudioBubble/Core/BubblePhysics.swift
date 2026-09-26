import Foundation

/// Soft "blob" physics for the nearby bubbles: they cluster, drift, can be dragged and flung, and
/// shove each other out of the way.
///
/// Verlet integration with position constraints (the classic soft-body toy approach): each body
/// keeps its current and previous position, so velocity is implicit and collisions are resolved
/// by simply moving bodies apart. That is unconditionally stable and never jitters.
///
/// - A gentle spring pulls everything toward the center, so the bubbles gather into a cluster.
/// - A slow per-body drift keeps them floating.
/// - Overlapping bodies are pushed apart (a dragged body is immovable, so it plows through).
/// - Bodies stay inside the field.
///
/// Bodies live in one contiguous array (an id → index map is rebuilt only when membership
/// changes), so a step allocates nothing and copies nothing.
nonisolated final class BubblePhysics {
    typealias Vector = SIMD2<Double>

    struct Body {
        let id: UInt64
        var position: Vector
        var previous: Vector
        var radius: Double
        let seed: Double
        /// While dragged: where the finger holds it, relative to its center.
        var grabOffset: Vector?
        var dragTarget: Vector?
        /// Velocity in points per second, from the last step (for squash-and-stretch).
        var velocity: Vector = .zero

        var isDragged: Bool { dragTarget != nil }
    }

    private(set) var bodies: [Body] = []
    private var indexByID: [UInt64: Int] = [:]

    /// The field's size; bodies stay inside it.
    var size = Vector(390, 700)
    /// Extra room kept free below each body (for its name label).
    var bottomClearance = 26.0
    /// Space kept between bubbles.
    var gap = 14.0
    /// Extra space when one bubble is above another, for the name hanging below the upper one.
    /// Scaled by how vertical the pair is, so side-by-side bubbles don't need it.
    var labelClearance = 24.0
    var centerPull = 2.0        // 1/s²
    var damping = 3.0           // 1/s
    var drift = 22.0            // pt/s²

    static let substep = 1.0 / 120
    private var time = 0.0
    private var accumulator = 0.0
    private var lastDate: Date?

    var center: Vector { size / 2 }

    func body(_ id: UInt64) -> Body? {
        indexByID[id].map { bodies[$0] }
    }

    // MARK: Membership

    /// Adds new ids (near the center, spread out), removes missing ones, updates radii.
    func sync(_ items: [(id: UInt64, radius: Double)]) {
        let ids = Set(items.map(\.id))
        if bodies.contains(where: { !ids.contains($0.id) }) {
            bodies.removeAll { !ids.contains($0.id) }
            indexByID = Dictionary(uniqueKeysWithValues: bodies.enumerated().map { ($1.id, $0) })
        }
        for (index, item) in items.enumerated() {
            if let existing = indexByID[item.id] {
                bodies[existing].radius = item.radius
                continue
            }
            // Golden-angle spiral start so new bodies never coincide.
            let angle = Double(index) * 2.399963
            let distance = 20 + 30 * Double(index).squareRoot()
            let position = center + Vector(cos(angle), sin(angle)) * distance
            bodies.append(Body(id: item.id, position: position, previous: position, radius: item.radius,
                               seed: Double(item.id % 10_007) / 10_007 * 2 * .pi))
            indexByID[item.id] = bodies.count - 1
        }
    }

    // MARK: Touch

    /// The body under `point`: the nearest center within its radius plus `slop`.
    func hitTest(_ point: Vector, slop: Double = 8) -> UInt64? {
        var best: (id: UInt64, distance: Double)?
        for body in bodies {
            let d = Self.length(body.position - point)
            guard d <= body.radius + slop else { continue }
            if best == nil || d < best!.distance { best = (body.id, d) }
        }
        return best?.id
    }

    /// Holds a body under the finger. The first call remembers where it was grabbed, so the body
    /// doesn't jump to center itself on the touch.
    func drag(_ id: UInt64, to point: Vector) {
        guard let i = indexByID[id] else { return }
        if bodies[i].grabOffset == nil { bodies[i].grabOffset = bodies[i].position - point }
        bodies[i].dragTarget = point + bodies[i].grabOffset!
    }

    /// Lets go, carrying the flick's velocity (points per second).
    func endDrag(_ id: UInt64, velocity: Vector) {
        guard let i = indexByID[id] else { return }
        bodies[i].dragTarget = nil
        bodies[i].grabOffset = nil
        let speed = Self.length(velocity)
        let capped = speed > 3_000 ? velocity * (3_000 / speed) : velocity
        bodies[i].previous = bodies[i].position - capped * Self.substep
    }

    /// Nothing is held and nothing moves faster than the gentle drift: the view can drop its
    /// frame rate.
    var isCalm: Bool {
        bodies.allSatisfy { !$0.isDragged && Self.length($0.velocity) < 40 }
    }

    // MARK: Simulation

    /// Advances by `elapsed` seconds in fixed substeps (frame-rate independent; long pauses are
    /// clamped so a stall never launches the bubbles).
    func advance(by elapsed: Double) {
        accumulator += min(max(0, elapsed), 0.05)
        while accumulator >= Self.substep {
            step(Self.substep)
            accumulator -= Self.substep
        }
    }

    func advance(to date: Date) {
        defer { lastDate = date }
        guard let lastDate else { return }
        advance(by: date.timeIntervalSince(lastDate))
    }

    func step(_ h: Double) {
        time += h
        let keep = exp(-damping * h)
        let c = center
        let n = bodies.count
        bodies.withUnsafeMutableBufferPointer { b in
            for i in 0..<n {
                if let target = b[i].dragTarget {
                    b[i].previous = b[i].position
                    b[i].position = target
                } else {
                    let velocity = (b[i].position - b[i].previous) * keep
                    let wander = Vector(sin(time * 0.5 + b[i].seed), cos(time * 0.37 + b[i].seed * 1.3)) * drift
                    let acceleration = (c - b[i].position) * centerPull + wander
                    b[i].previous = b[i].position
                    b[i].position += velocity + acceleration * h * h
                }
            }

            // Resolve overlaps a few times, then keep everything inside the field.
            for _ in 0..<4 {
                for i in 0..<n {
                    for j in (i + 1)..<max(i + 1, n) {
                        let wi = b[i].isDragged ? 0.0 : 1.0
                        let wj = b[j].isDragged ? 0.0 : 1.0
                        guard wi + wj > 0 else { continue }
                        var delta = b[j].position - b[i].position
                        var distance = Self.length(delta)
                        if distance < 1e-6 {
                            // Exactly on top of each other: separate along a stable direction.
                            delta = Vector(cos(b[i].seed), sin(b[i].seed))
                            distance = 1
                        }
                        let vertical = delta.y / distance
                        let required = b[i].radius + b[j].radius + gap + labelClearance * vertical * vertical
                        let overlap = required - distance
                        guard overlap > 0 else { continue }
                        // 0.7: slightly soft, so collisions feel squishy rather than rigid.
                        let correction = delta / distance * (overlap * 0.7 / (wi + wj))
                        b[i].position -= correction * wi
                        b[j].position += correction * wj
                    }
                }
            }
            for i in 0..<n {
                if !b[i].isDragged {
                    let r = b[i].radius
                    b[i].position.x = min(max(b[i].position.x, r), max(r, size.x - r))
                    b[i].position.y = min(max(b[i].position.y, r), max(r, size.y - r - bottomClearance))
                }
                b[i].velocity = (b[i].position - b[i].previous) / h
            }
        }
    }

    @inline(__always)
    static func length(_ v: Vector) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }
}

/// Estimates a finger's velocity at release from its recent samples: a least-squares line through
/// the last ~60 ms, which is much steadier than the difference of the last two points.
nonisolated struct TouchVelocityEstimator {
    typealias Vector = BubblePhysics.Vector

    static let window = 0.06
    private var samples: [(time: Double, point: Vector)] = []

    mutating func add(_ point: Vector, at time: Double) {
        samples.append((time, point))
        if let last = samples.last?.time { samples.removeAll { last - $0.time > Self.window * 2 } }
    }

    /// Velocity in points per second at `time`. Zero when the finger has been still for a moment
    /// before lifting, so a careful placement doesn't fling.
    func velocity(at time: Double) -> Vector {
        guard let last = samples.last, time - last.time < 0.08 else { return .zero }
        let recent = samples.filter { last.time - $0.time <= Self.window }
        guard recent.count >= 2 else { return .zero }
        let meanT = recent.reduce(0) { $0 + $1.time } / Double(recent.count)
        let meanP = recent.reduce(Vector.zero) { $0 + $1.point } / Double(recent.count)
        var covariance = Vector.zero
        var variance = 0.0
        for sample in recent {
            let dt = sample.time - meanT
            covariance += (sample.point - meanP) * dt
            variance += dt * dt
        }
        return variance > 1e-9 ? covariance / variance : .zero
    }
}
