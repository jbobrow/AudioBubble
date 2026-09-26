import UIKit
import os

/// What the field shows for one person.
struct BubbleModel: Equatable {
    let id: UInt64
    let name: String
    let hue: Double
    let avatar: AvatarContent
    let invited: Bool
}

/// The nearby bubbles as a physics toy, drawn with Core Animation.
///
/// Each bubble is drawn once into bitmaps (`BubbleArt`); every frame, a display link steps
/// `BubblePhysics` and only moves and transforms layers, which the GPU composites without redrawing
/// anything. Touches are handled here directly: the bubble under a finger follows it (several
/// fingers can each hold one), a flick keeps its momentum, and a tap invites.
final class BubbleFieldView: UIView {
    var onTap: ((UInt64) -> Void)?
    static let bubbleSize: CGFloat = 104

    private let physics = BubblePhysics()
    private var bubbles: [UInt64: BubbleLayer] = [:]
    private var models: [BubbleModel] = []
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var touchesByID: [ObjectIdentifier: TrackedTouch] = [:]
    private var reduceMotion = UIAccessibility.isReduceMotionEnabled
    #if DEBUG
    private var stats = FrameStats()
    private let demoDrag = DebugLaunch.has("-demoDrag")
    private let demoVideo = DebugLaunch.value(after: "-screenshotDemo") == "video"
    private lazy var demoFinger = DemoFinger(in: layer)
    #endif

    private struct TrackedTouch {
        let bubble: UInt64
        let start: CGPoint
        let startTime: TimeInterval
        var moved = false
        var velocity = TouchVelocityEstimator()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        applyMotionPreference()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(pause), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
        center.addObserver(self, selector: #selector(motionPreferenceChanged),
                           name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Data

    /// Adds, removes and redraws bubbles to match `models`. Only what changed is touched.
    func setBubbles(_ newModels: [BubbleModel]) {
        guard newModels != models else { return }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        let keep = Set(newModels.map(\.id))
        for (id, bubble) in bubbles where !keep.contains(id) {
            bubble.remove()
            bubbles[id] = nil
        }
        let old = Dictionary(uniqueKeysWithValues: models.map { ($0.id, $0) })
        for model in newModels {
            if let bubble = bubbles[model.id] {
                if old[model.id] != model { bubble.update(model, scale: scale) }
            } else {
                let bubble = BubbleLayer(size: Self.bubbleSize)
                bubble.update(model, scale: scale)
                layer.addSublayer(bubble.container)
                bubbles[model.id] = bubble
                bubble.popIn()
            }
        }
        models = newModels
        physics.sync(newModels.map { (id: $0.id, radius: Double(Self.bubbleSize) / 2) })
        render()
        accessibilityElements = nil   // rebuilt on demand
        wake()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        physics.size = .init(Double(bounds.width), Double(bounds.height))
    }

    // MARK: Frame loop

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
            link.preferredFrameRateRange = Self.activeRate
            link.add(to: .main, forMode: .common)
            displayLink = link
            lastTimestamp = nil
        }
    }

    /// Full rate while touched or moving; a relaxed rate for the gentle drift.
    private static let activeRate = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
    private static let calmRate = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)

    fileprivate func tick(_ link: CADisplayLink) {
        #if DEBUG
        let started = CACurrentMediaTime()
        if demoDrag { driveDemoDrag(at: link.targetTimestamp) }
        if demoVideo { driveDemoVideo(at: link.targetTimestamp) }
        #endif
        let now = link.targetTimestamp
        physics.advance(by: now - (lastTimestamp ?? now))
        lastTimestamp = now
        render()
        #if DEBUG
        stats.record(frameWork: CACurrentMediaTime() - started, at: now, bubbles: physics.bodies.count)
        #endif
        let calm = touchesByID.isEmpty && physics.isCalm
        let rate = calm ? Self.calmRate : Self.activeRate
        if link.preferredFrameRateRange != rate { link.preferredFrameRateRange = rate }
    }

    /// Writes every bubble's position and squash-and-stretch. The only per-frame work.
    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for body in physics.bodies {
            guard let bubble = bubbles[body.id] else { continue }
            bubble.container.position = CGPoint(x: body.position.x, y: body.position.y)
            let speed = BubblePhysics.length(body.velocity)
            let stretch = reduceMotion ? 0 : CGFloat(min(speed / 2_200, 0.14))
            if stretch < 0.002 {
                bubble.shape.setAffineTransform(.identity)
            } else {
                let angle = CGFloat(atan2(body.velocity.y, body.velocity.x))
                bubble.shape.setAffineTransform(
                    CGAffineTransform(rotationAngle: -angle)
                        .concatenating(CGAffineTransform(scaleX: 1 + stretch, y: 1 - stretch * 0.8))
                        .concatenating(CGAffineTransform(rotationAngle: angle)))
            }
        }
        CATransaction.commit()
    }

    private func wake() {
        displayLink?.preferredFrameRateRange = Self.activeRate
    }

    @objc private func pause() { displayLink?.isPaused = true }

    @objc private func resume() {
        lastTimestamp = nil
        displayLink?.isPaused = false
    }

    @objc private func motionPreferenceChanged() {
        reduceMotion = UIAccessibility.isReduceMotionEnabled
        applyMotionPreference()
    }

    /// Reduce Motion: no drift or stretch, and bubbles settle quickly.
    private func applyMotionPreference() {
        physics.drift = reduceMotion ? 0 : 22
        physics.damping = reduceMotion ? 8 : 3
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            guard let id = physics.hitTest(.init(Double(point.x), Double(point.y))),
                  !touchesByID.values.contains(where: { $0.bubble == id }) else { continue }
            var tracked = TrackedTouch(bubble: id, start: point, startTime: touch.timestamp)
            tracked.velocity.add(.init(Double(point.x), Double(point.y)), at: touch.timestamp)
            touchesByID[ObjectIdentifier(touch)] = tracked
            bubbles[id]?.setLifted(true)
        }
        if !touchesByID.isEmpty { wake() }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard var tracked = touchesByID[ObjectIdentifier(touch)] else { continue }
            // Every sample the hardware saw, for an accurate release velocity.
            for sample in event?.coalescedTouches(for: touch) ?? [touch] {
                let p = sample.location(in: self)
                tracked.velocity.add(.init(Double(p.x), Double(p.y)), at: sample.timestamp)
            }
            let point = touch.location(in: self)
            if !tracked.moved, hypot(point.x - tracked.start.x, point.y - tracked.start.y) > 6 {
                tracked.moved = true
            }
            if tracked.moved {
                // Aim slightly ahead with the predicted touch, so the bubble keeps up with the finger.
                let aim = event?.predictedTouches(for: touch)?.last?.location(in: self) ?? point
                physics.drag(tracked.bubble, to: .init(Double(aim.x), Double(aim.y)))
            }
            touchesByID[ObjectIdentifier(touch)] = tracked
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            guard let tracked = touchesByID.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            bubbles[tracked.bubble]?.setLifted(false)
            if tracked.moved {
                let velocity = cancelled ? .zero : tracked.velocity.velocity(at: touch.timestamp)
                physics.endDrag(tracked.bubble, velocity: velocity)
            } else if !cancelled, touch.timestamp - tracked.startTime < 0.35 {
                onTap?(tracked.bubble)
            }
        }
    }

    #if DEBUG
    /// `-demoDrag`: after a few seconds, the first bubble is dragged in a loop through the others,
    /// then flung, over and over, to exercise the drag path without a finger.
    private var demoStart: CFTimeInterval?
    private func driveDemoDrag(at time: CFTimeInterval) {
        guard let first = physics.bodies.first?.id else { return }
        if demoStart == nil { demoStart = time + 3 }
        let t = time - demoStart!
        guard t > 0 else { return }
        let cycle = t.truncatingRemainder(dividingBy: 4)
        if cycle < 2.5 {
            let angle = cycle / 2.5 * 2 * .pi
            let c = physics.center
            physics.drag(first, to: c + BubblePhysics.Vector(cos(angle) * 120, sin(angle) * 170))
        } else if physics.body(first)?.isDragged == true {
            physics.endDrag(first, velocity: .init(900, -600))
        }
    }

    /// `-screenshotDemo video`: once all seven people have arrived, a visible finger drags Maya
    /// (id 1) around the field and flicks her, then taps Sam (id 2) to invite him.
    private var videoStart: CFTimeInterval?
    private var videoTapped = false
    private func driveDemoVideo(at time: CFTimeInterval) {
        if videoStart == nil {
            guard physics.bodies.count == 7 else { return }
            videoStart = time + 1.2
        }
        let t = time - videoStart!
        let maya: UInt64 = 1, sam: UInt64 = 2
        guard let mayaBody = physics.body(maya), let samBody = physics.body(sam) else { return }
        let c = physics.center
        func point(_ v: BubblePhysics.Vector) -> CGPoint { CGPoint(x: v.x, y: v.y) }

        switch t {
        case ..<0:
            break
        case ..<0.35:
            // Finger comes down on Maya.
            demoFinger.show(at: point(mayaBody.position), pressed: t > 0.15)
        case ..<3.2:
            if !mayaBody.isDragged { bubbles[maya]?.setLifted(true) }
            // Ease from where she was onto a loop through the others.
            let u = (t - 0.35) / 2.85
            let angle = -Double.pi / 2 + u * 2 * .pi
            let loop = c + BubblePhysics.Vector(cos(angle) * 115, sin(angle) * 165)
            let blend = min(1, (t - 0.35) / 0.5)
            let start = videoDragStart ?? mayaBody.position
            videoDragStart = start
            let target = start + (loop - start) * blend * blend * (3 - 2 * blend)
            physics.drag(maya, to: target)
            demoFinger.show(at: point(target), pressed: true)
        case ..<3.5:
            if mayaBody.isDragged {
                physics.endDrag(maya, velocity: .init(-700, 900))
                bubbles[maya]?.setLifted(false)
            }
            demoFinger.hide()
        case ..<5.0:
            break
        case ..<5.45:
            // Tap Sam.
            demoFinger.show(at: point(samBody.position), pressed: t > 5.15)
            if t > 5.3, !videoTapped {
                videoTapped = true
                onTap?(sam)
            }
        default:
            demoFinger.hide()
        }
    }
    private var videoDragStart: BubblePhysics.Vector?
    #endif

    // MARK: Accessibility

    override var accessibilityElements: [Any]? {
        get {
            if let elements = super.accessibilityElements { return elements }
            let elements = models.map { BubbleAccessibilityElement(field: self, model: $0) }
            super.accessibilityElements = elements
            return elements
        }
        set { super.accessibilityElements = newValue }
    }

    fileprivate func frame(of id: UInt64) -> CGRect {
        guard let body = physics.body(id) else { return .zero }
        let r = CGFloat(body.radius)
        return CGRect(x: body.position.x - r, y: body.position.y - r, width: 2 * r, height: 2 * r + 24)
    }

    fileprivate func activate(_ id: UInt64) { onTap?(id) }
}

/// One VoiceOver element per bubble; its frame follows the bubble.
private final class BubbleAccessibilityElement: UIAccessibilityElement {
    private weak var field: BubbleFieldView?
    private let id: UInt64

    init(field: BubbleFieldView, model: BubbleModel) {
        self.field = field
        id = model.id
        super.init(accessibilityContainer: field)
        accessibilityLabel = model.name
        accessibilityHint = model.invited ? "Invited" : "Double-tap to invite"
        accessibilityTraits = .button
    }

    override var accessibilityFrameInContainerSpace: CGRect {
        get { field?.frame(of: id) ?? .zero }
        set {}
    }

    override func accessibilityActivate() -> Bool {
        field?.activate(id)
        return true
    }
}

/// A display link retains its target; this keeps it from retaining the view.
private final class DisplayLinkProxy: NSObject {
    private weak var view: BubbleFieldView?
    init(_ view: BubbleFieldView) { self.view = view }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.tick(link)
    }
}

/// The layers of one bubble:
///
///     container   position: the bubble's center; lift and pop-in scale
///     ├─ shape    squash-and-stretch (per frame)
///     │  ├─ glow  bitmap halo
///     │  ├─ body  bitmap circle + avatar
///     │  └─ ring  dashed "invited" ring
///     └─ label    bitmap name, hanging below; never stretched
private final class BubbleLayer {
    let container = CALayer()
    let shape = CALayer()
    private let glow = CALayer()
    private let body = CALayer()
    private let ring = CAShapeLayer()
    private let label = CALayer()
    private let size: CGFloat
    private var current: BubbleModel?

    private static let ringInset: CGFloat = 7
    private static let restingGlow: Float = 0.6

    init(size: CGFloat) {
        self.size = size
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        shape.frame = container.bounds
        let margin = BubbleArt.glowMargin
        glow.frame = container.bounds.insetBy(dx: -margin, dy: -margin)
        glow.opacity = Self.restingGlow
        body.frame = container.bounds
        let inset = Self.ringInset
        ring.frame = container.bounds
        ring.path = CGPath(ellipseIn: container.bounds.insetBy(dx: -inset + 1, dy: -inset + 1), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        ring.lineWidth = 2
        ring.lineDashPattern = [6, 5]
        ring.isHidden = true
        for layer in [glow, body, ring] { shape.addSublayer(layer) }
        container.addSublayer(shape)
        container.addSublayer(label)
        // Nothing here animates implicitly; changes are explicit.
        for layer in [container, shape, glow, body, ring, label] as [CALayer] {
            layer.actions = ["position": NSNull(), "transform": NSNull(), "bounds": NSNull(),
                             "contents": NSNull(), "hidden": NSNull(), "opacity": NSNull()]
        }
    }

    func update(_ model: BubbleModel, scale: CGFloat) {
        if current?.hue != model.hue {
            glow.contents = BubbleArt.glow(hue: model.hue, size: size, scale: scale)
        }
        if current?.hue != model.hue || current?.avatar != model.avatar || current?.name.prefix(1) != model.name.prefix(1) {
            body.contents = BubbleArt.body(name: model.name, hue: model.hue, avatar: model.avatar, size: size, scale: scale)
        }
        if current?.name != model.name || current?.invited != model.invited {
            let (image, textSize) = BubbleArt.label(model.invited ? "Invited…" : model.name, scale: scale)
            label.contents = image
            label.bounds = CGRect(origin: .zero, size: textSize)
            label.position = CGPoint(x: size / 2, y: size + Self.ringInset + 7 + textSize.height / 2)
        }
        for layer in [glow, body, label] { layer.contentsScale = scale }
        ring.isHidden = !model.invited
        current = model
    }

    func setLifted(_ lifted: Bool) {
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = container.presentation()?.value(forKeyPath: "transform.scale") ?? (lifted ? 1 : 1.08)
        scale.toValue = lifted ? 1.08 : 1
        scale.damping = 14
        scale.stiffness = 300
        scale.duration = scale.settlingDuration
        container.setValue(lifted ? 1.08 : 1, forKeyPath: "transform.scale")
        container.add(scale, forKey: "lift")

        let brighten = CABasicAnimation(keyPath: "opacity")
        brighten.fromValue = glow.presentation()?.opacity ?? glow.opacity
        brighten.toValue = lifted ? 1 : Self.restingGlow
        brighten.duration = 0.2
        glow.opacity = lifted ? 1 : Self.restingGlow
        glow.add(brighten, forKey: "lift")
    }

    func popIn() {
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.3
        grow.toValue = 1
        grow.damping = 12
        grow.stiffness = 180
        grow.duration = grow.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.25
        container.add(grow, forKey: "popIn")
        container.add(fade, forKey: "fadeIn")
    }

    func remove() {
        let layer = container
        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = 0.25
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "remove")
        CATransaction.commit()
    }
}

#if DEBUG
/// A soft circle where a finger would be, for the App Preview.
private final class DemoFinger {
    private let dot = CALayer()
    private var visible = false

    init(in parent: CALayer) {
        dot.bounds = CGRect(x: 0, y: 0, width: 50, height: 50)
        dot.cornerRadius = 25
        dot.backgroundColor = UIColor.white.withAlphaComponent(0.4).cgColor
        dot.borderColor = UIColor.white.withAlphaComponent(0.85).cgColor
        dot.borderWidth = 2
        dot.shadowColor = UIColor.black.cgColor
        dot.shadowOpacity = 0.3
        dot.shadowRadius = 6
        dot.opacity = 0
        dot.zPosition = 1_000
        parent.addSublayer(dot)
    }

    func show(at point: CGPoint, pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.position = point
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        dot.opacity = 1
        dot.transform = CATransform3DMakeScale(pressed ? 0.82 : 1, pressed ? 0.82 : 1, 1)
        CATransaction.commit()
        visible = true
    }

    func hide() {
        guard visible else { return }
        visible = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        dot.opacity = 0
        dot.transform = CATransform3DMakeScale(1.25, 1.25, 1)
        CATransaction.commit()
    }
}

/// Logs frame rate and per-frame main-thread work every two seconds (debug builds only).
private struct FrameStats {
    private var frames = 0
    private var worst = 0.0
    private var total = 0.0
    private var windowStart: CFTimeInterval?
    private let log = Logger(subsystem: "com.jonbobrow.AudioBubble", category: "bubbles")

    mutating func record(frameWork: Double, at time: CFTimeInterval, bubbles: Int) {
        if windowStart == nil { windowStart = time }
        frames += 1
        worst = max(worst, frameWork)
        total += frameWork
        let elapsed = time - windowStart!
        guard elapsed >= 2 else { return }
        let fps = Double(frames) / elapsed
        let average = total / Double(frames) * 1000
        let peak = worst * 1000
        log.debug("bubbles: \(bubbles) at \(fps, format: .fixed(precision: 0)) fps, frame work avg \(average, format: .fixed(precision: 3)) ms, worst \(peak, format: .fixed(precision: 3)) ms")
        frames = 0
        worst = 0
        total = 0
        windowStart = time
    }
}
#endif
