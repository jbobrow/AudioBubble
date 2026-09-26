import Foundation
import Testing
@testable import AudioBubble

struct BubblePhysicsTests {
    typealias Vector = BubblePhysics.Vector

    static func field(count: Int, radius: Double = 52) -> BubblePhysics {
        let physics = BubblePhysics()
        physics.size = Vector(390, 700)
        physics.sync((0..<count).map { (id: UInt64($0 + 1), radius: radius) })
        return physics
    }

    static func run(_ physics: BubblePhysics, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { physics.step(1.0 / 120) }
    }

    static func length(_ v: Vector) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    /// Smallest distance between any two bodies minus the spacing they need, including room for
    /// the name under the upper one (≥ 0 means nothing overlaps).
    static func worstOverlap(_ physics: BubblePhysics) -> Double {
        let bodies = physics.bodies
        var worst = Double.infinity
        for i in bodies.indices {
            for j in bodies.indices where j > i {
                let delta = bodies[j].position - bodies[i].position
                let d = length(delta)
                let vertical = delta.y / max(d, 1e-9)
                let required = bodies[i].radius + bodies[j].radius + physics.gap + physics.labelClearance * vertical * vertical
                worst = min(worst, d - required)
            }
        }
        return worst
    }

    @Test func leavesRoomForNamesBetweenStackedBubbles() {
        // Hold one bubble in the middle and let the other settle against it.
        let physics = Self.field(count: 2)
        for _ in 0..<240 {
            physics.drag(1, to: physics.center)
            physics.step(1.0 / 120)
        }
        let a = physics.body(1)!, b = physics.body(2)!
        let d = Self.length(b.position - a.position)
        let vertical = abs(b.position.y - a.position.y) / d
        // Whatever the arrangement, the required clearance (including names) holds.
        #expect(d >= a.radius + b.radius + physics.gap + physics.labelClearance * vertical * vertical - 3)
    }

    static func inside(_ physics: BubblePhysics) -> Bool {
        physics.bodies.allSatisfy {
            $0.position.x >= $0.radius - 0.5 && $0.position.x <= physics.size.x - $0.radius + 0.5
                && $0.position.y >= $0.radius - 0.5
                && $0.position.y <= physics.size.y - $0.radius - physics.bottomClearance + 0.5
        }
    }

    @Test(arguments: [1, 3, 8])
    func settlesIntoAClusterWithoutOverlapping(count: Int) {
        let physics = Self.field(count: count)
        Self.run(physics, seconds: 6)
        #expect(Self.worstOverlap(physics) > -3, "overlap \(Self.worstOverlap(physics))")
        #expect(Self.inside(physics))
        // Gathered around the middle, and calm (only the gentle drift).
        for body in physics.bodies {
            #expect(Self.length(body.position - physics.center) < 260)
            #expect(Self.length(body.velocity) < 40, "speed \(Self.length(body.velocity))")
        }
    }

    @Test func aDraggedBubblePushesOthersAside() throws {
        let physics = Self.field(count: 2)
        Self.run(physics, seconds: 4)
        let a = physics.body(1)!, b = physics.body(2)!
        // Drag A straight through B's position.
        let start = a.position
        for step in 0...60 {
            let t = Double(step) / 60
            physics.drag(1, to: start + (b.position + (b.position - start) * 0.3 - start) * t)
            physics.step(1.0 / 120)
            physics.step(1.0 / 120)
        }
        let draggedTo = physics.body(1)!.position
        let pushed = physics.body(2)!.position
        #expect(Self.length(pushed - b.position) > 40, "B moved \(Self.length(pushed - b.position))")
        #expect(Self.length(pushed - draggedTo) > a.radius + b.radius + physics.gap - 3)
        // The dragged bubble is exactly where the finger put it.
        #expect(Self.length(draggedTo - (start + (b.position + (b.position - start) * 0.3 - start))) < 1e-6)
    }

    @Test func aFlickCarriesMomentumThenSettles() {
        let physics = Self.field(count: 1)
        Self.run(physics, seconds: 3)
        let start = physics.body(1)!.position
        physics.drag(1, to: start)
        physics.step(1.0 / 120)
        physics.endDrag(1, velocity: Vector(1_500, 0))
        Self.run(physics, seconds: 0.15)
        #expect(physics.body(1)!.position.x > start.x + 60, "moved \(physics.body(1)!.position.x - start.x)")
        Self.run(physics, seconds: 6)
        #expect(Self.inside(physics))
        #expect(Self.length(physics.body(1)!.position - physics.center) < 60)
    }

    @Test func staysInsideEvenWhenFlungHard() {
        let physics = Self.field(count: 4)
        Self.run(physics, seconds: 2)
        physics.drag(1, to: physics.body(1)!.position)
        physics.step(1.0 / 120)
        physics.endDrag(1, velocity: Vector(-50_000, 50_000))   // capped to 3,000 pt/s
        for _ in 0..<600 {
            physics.step(1.0 / 120)
            #expect(Self.inside(physics))
        }
    }

    @Test func syncAddsAndRemovesBodies() {
        let physics = Self.field(count: 3)
        physics.sync([(id: 2, radius: 52), (id: 9, radius: 30)])
        #expect(Set(physics.bodies.map(\.id)) == [2, 9])
        #expect(physics.body(9)?.radius == 30)
        // A new body never starts exactly on top of another.
        physics.sync([(id: 2, radius: 52), (id: 9, radius: 30), (id: 10, radius: 30)])
        #expect(Self.length(physics.body(10)!.position - physics.body(9)!.position) > 1)
    }

    @Test func hitTestFindsTheBubbleUnderAFinger() {
        let physics = Self.field(count: 3)
        Self.run(physics, seconds: 3)
        for body in physics.bodies {
            #expect(physics.hitTest(body.position + Vector(body.radius * 0.6, 0)) == body.id)
        }
        #expect(physics.hitTest(Vector(-500, -500)) == nil)
    }

    @Test func twoFingersCanDragTwoBubbles() {
        let physics = Self.field(count: 3)
        Self.run(physics, seconds: 3)
        let a = physics.body(1)!.position, b = physics.body(2)!.position
        // Each finger grabs its bubble dead center, then both move apart.
        for step in 0...60 {
            let t = Double(step) / 60
            physics.drag(1, to: a + Vector(-80, 0) * t)
            physics.drag(2, to: b + Vector(80, 0) * t)
            physics.step(1.0 / 120)
        }
        #expect(Self.length(physics.body(1)!.position - (a + Vector(-80, 0))) < 1e-6)
        #expect(Self.length(physics.body(2)!.position - (b + Vector(80, 0))) < 1e-6)
        #expect(!physics.isCalm)
        physics.endDrag(1, velocity: .zero)
        physics.endDrag(2, velocity: .zero)
        Self.run(physics, seconds: 6)
        #expect(physics.isCalm)
    }

    @Test func velocityEstimateIsSteadyAndStopsWhenTheFingerRests() {
        var estimator = TouchVelocityEstimator()
        // 120 Hz samples moving at (600, -300) pt/s with ±1.5 pt of jitter.
        for i in 0..<30 {
            let t = Double(i) / 120
            let jitter = Vector(i % 2 == 0 ? 1.5 : -1.5, i % 3 == 0 ? 1.5 : -1.5)
            estimator.add(Vector(600, -300) * t + jitter, at: t)
        }
        let v = estimator.velocity(at: 29.0 / 120)
        #expect(abs(v.x - 600) < 60 && abs(v.y + 300) < 60, "estimated \(v)")
        // Lifting 0.2 s after the last movement: a placement, not a flick.
        #expect(estimator.velocity(at: 29.0 / 120 + 0.2) == .zero)
    }
}
