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
nonisolated final class BubblePhysics {
    typealias Vector = SIMD2<Double>

    struct Body {
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

    private(set) var bodies: [UInt64: Body] = [:]
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

    private static let substep = 1.0 / 120
    private var time = 0.0
    private var accumulator = 0.0
    private var lastDate: Date?

    var center: Vector { size / 2 }

    // MARK: Membership

    /// Adds new ids (near the center, spread out), removes missing ones, updates radii.
    func sync(_ items: [(id: UInt64, radius: Double)]) {
        let ids = Set(items.map(\.id))
        for id in bodies.keys where !ids.contains(id) { bodies[id] = nil }
        for (index, item) in items.enumerated() {
            if bodies[item.id] != nil {
                bodies[item.id]?.radius = item.radius
                continue
            }
            // Golden-angle spiral start so new bodies never coincide.
            let angle = Double(index) * 2.399963
            let distance = 20 + 30 * Double(index).squareRoot()
            let position = center + Vector(cos(angle), sin(angle)) * distance
            bodies[item.id] = Body(position: position, previous: position, radius: item.radius,
                                   seed: Double(item.id % 10_007) / 10_007 * 2 * .pi)
        }
    }

    /// Per frame, from the view: match the field size and members, then simulate up to `date`.
    func update(size: CGSize, items: [(id: UInt64, radius: Double)], date: Date) {
        self.size = Vector(Double(size.width), Double(size.height))
        sync(items)
        advance(to: date)
    }

    // MARK: Dragging

    func drag(_ id: UInt64, to point: Vector) {
        guard var body = bodies[id] else { return }
        if body.grabOffset == nil { body.grabOffset = body.position - point }
        body.dragTarget = point + body.grabOffset!
        bodies[id] = body
    }

    /// Lets go, carrying the flick's velocity (points per second).
    func endDrag(_ id: UInt64, velocity: Vector) {
        guard var body = bodies[id] else { return }
        body.dragTarget = nil
        body.grabOffset = nil
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        let capped = speed > 3_000 ? velocity * (3_000 / speed) : velocity
        body.previous = body.position - capped * Self.substep
        bodies[id] = body
    }

    // MARK: Simulation

    /// Advances to `date` in fixed substeps (frame-rate independent; long pauses are skipped).
    func advance(to date: Date) {
        defer { lastDate = date }
        guard let lastDate else { return }
        accumulator += min(max(0, date.timeIntervalSince(lastDate)), 0.05)
        while accumulator >= Self.substep {
            step(Self.substep)
            accumulator -= Self.substep
        }
    }

    func step(_ h: Double) {
        time += h
        let keep = exp(-damping * h)
        let c = center
        for (id, var body) in bodies {
            if let target = body.dragTarget {
                body.previous = body.position
                body.position = target
            } else {
                let velocity = (body.position - body.previous) * keep
                let wander = Vector(sin(time * 0.5 + body.seed), cos(time * 0.37 + body.seed * 1.3)) * drift
                let acceleration = (c - body.position) * centerPull + wander
                body.previous = body.position
                body.position += velocity + acceleration * h * h
            }
            bodies[id] = body
        }

        // Resolve overlaps a few times, then keep everything inside the field.
        var list = Array(bodies)
        for _ in 0..<4 {
            for i in list.indices {
                for j in list.indices where j > i {
                    let wi = list[i].value.isDragged ? 0.0 : 1.0
                    let wj = list[j].value.isDragged ? 0.0 : 1.0
                    guard wi + wj > 0 else { continue }
                    var delta = list[j].value.position - list[i].value.position
                    var distance = (delta.x * delta.x + delta.y * delta.y).squareRoot()
                    if distance < 1e-6 {
                        // Exactly on top of each other: separate along a stable direction.
                        delta = Vector(cos(list[i].value.seed), sin(list[i].value.seed))
                        distance = 1
                    }
                    let vertical = delta.y / distance
                    let required = list[i].value.radius + list[j].value.radius + gap + labelClearance * vertical * vertical
                    let overlap = required - distance
                    guard overlap > 0 else { continue }
                    // 0.7: slightly soft, so collisions feel squishy rather than rigid.
                    let correction = delta / distance * (overlap * 0.7 / (wi + wj))
                    list[i].value.position -= correction * wi
                    list[j].value.position += correction * wj
                }
            }
        }
        for i in list.indices where !list[i].value.isDragged {
            let r = list[i].value.radius
            var p = list[i].value.position
            p.x = min(max(p.x, r), max(r, size.x - r))
            p.y = min(max(p.y, r), max(r, size.y - r - bottomClearance))
            list[i].value.position = p
        }
        for (id, var body) in list {
            body.velocity = (body.position - body.previous) / h
            bodies[id] = body
        }
    }
}
