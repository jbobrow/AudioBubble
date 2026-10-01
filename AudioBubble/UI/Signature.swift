import SwiftUI

/// "App by Jon Bobrow" in Jon's hand, with an ellipsis in a circle beneath it. Opens the
/// About page. Like `AboutView`, which uses its "Apps by" sibling, this file
/// is the same across all of Jon Bobrow's apps.
struct SignatureButton: View {
    /// Width of the signature, before Dynamic Type.
    var width: CGFloat = 180
    /// `nil` for the signature alone.
    var mark: SignatureLabel.Mark? = .more
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SignatureLabel(signature: .appBy, mark: mark, width: width)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows more info")
    }
}

/// A signature, usually with a small mark centered beneath it, in gray.
struct SignatureLabel: View {
    enum Mark {
        /// Three dots in a circle, for opening the About page.
        case more
        /// A box with an arrow out its top right corner, for opening a web
        /// page.
        case linkOut
    }

    let signature: Signature
    let mark: Mark?
    /// Width of the signature, before Dynamic Type.
    var width: CGFloat = 180

    /// Grows the signature with Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 8) {
            SignatureShape(signature: signature)
                .stroke(style: stroke)
                .frame(width: scaledWidth, height: scaledWidth * signature.viewBox.height / signature.viewBox.width)
            // Marks are drawn with the signature's own line weight
            if let mark {
                Group {
                    switch mark {
                    case .more: MoreShape().stroke(style: stroke)
                    case .linkOut: LinkOutShape().stroke(style: stroke)
                    }
                }
                .frame(width: scaledWidth * 0.085, height: scaledWidth * 0.085)
            }
        }
        .foregroundStyle(.secondary)
        .padding(12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(signature.text)
    }

    private var scaledWidth: CGFloat { width * scale }

    /// The drawing's own line weight, scaled to its size on screen.
    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: signature.strokeWidth * scaledWidth / signature.viewBox.width,
                    lineCap: .round, lineJoin: .round)
    }
}

/// A circle with three dots across its middle. Each dot is a stroke with no
/// length, so its round caps make it exactly the line's width.
private struct MoreShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect.insetBy(dx: rect.width * 0.05, dy: rect.height * 0.05))
        for x in [0.3, 0.5, 0.7] {
            let dot = CGPoint(x: rect.minX + x * rect.width, y: rect.midY)
            path.move(to: dot)
            path.addLine(to: dot)
        }
        return path
    }
}

/// A box open at its top right corner, with an arrow leaving through the gap.
private struct LinkOutShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let corner = rect.width * 0.18
        var path = Path()
        // The box, from the gap at the top around to the gap at the right
        path.move(to: p(0.45, 0.1))
        path.addArc(tangent1End: p(0.1, 0.1), tangent2End: p(0.1, 0.9), radius: corner)
        path.addArc(tangent1End: p(0.1, 0.9), tangent2End: p(0.9, 0.9), radius: corner)
        path.addArc(tangent1End: p(0.9, 0.9), tangent2End: p(0.9, 0.1), radius: corner)
        path.addLine(to: p(0.9, 0.55))
        // The arrow
        path.move(to: p(0.45, 0.55))
        path.addLine(to: p(0.95, 0.05))
        path.move(to: p(0.62, 0.05))
        path.addLine(to: p(0.95, 0.05))
        path.addLine(to: p(0.95, 0.38))
        return path
    }
}

/// One of Jon's hand-drawn signatures, as exported from Illustrator.
struct Signature {
    /// What it says, for VoiceOver.
    let text: String
    /// The SVG's viewBox.
    let viewBox: CGSize
    /// The SVG's stroke width, in viewBox units.
    let strokeWidth: CGFloat = 30
    /// Every stroke, in viewBox coordinates.
    let path: Path

    /// `strokes` are each path's `d` attribute, straight from the SVG.
    init(text: String, viewBox: CGSize, strokes: [String]) {
        self.text = text
        self.viewBox = viewBox
        var path = Path()
        for d in strokes { SVGPathData(d).append(to: &path) }
        self.path = path
    }

    /// app-by-jon-bobrow.svg, for an app's own screens.
    static let appBy = Signature(
        text: "App by Jon Bobrow",
        viewBox: CGSize(width: 3087.29, height: 681.93),
        strokes: [
            "M1610.11,335.11c0,17.82,19.8,77.22,3.96,110.89",
            "M15,537.47C23.66,136.35,107.34,18.04,136.2,15.15c28.86-2.89,86.57,31.74,86.57,484.8",
            "M80.58,356.55c65.34-37.62,178.21-25.74,178.21-25.74",
            "M320.17,330.81c81.18-15.84,176.23,73.26,47.52,142.57",
            "M466.7,328.83c81.18-15.84,160.39,71.28,67.32,134.65",
            "M353.83,396.15c-5.94,104.95,29.7,241.57,29.7,241.57",
            "M490.46,378.33c-5.94,104.95,13.86,211.87,13.86,211.87",
            "M788.37,148.98c-11.88,49.5-26.16,130.64-33.66,199.99-7.92,73.26,38.68,123.77,86.2,90.1s12.8-101.98-40.66-98.06",
            "M923.02,537.08c-35.64,27.72-53.4,109.67,2.96,126.69,69.81,21.08,80.2-67.28,76.24-138.57s-19.8-194.05-19.8-194.05",
            "M982.42,331.15c1.98,75.24-9.9,118.81-51.48,110.89s-31.68-85.14-23.76-128.71",
            "M1388.34,55.92c29.7,142.57,55.95,373.41-47.52,407.9-71.28,23.76-100.98-51.48-93.06-83.16",
            "M1507.15,321.25c-45.54-3.96-56.51,138.61,9.9,138.61,73.26,0,47.85-133.59-9.9-138.61Z",
            "M2225.92,343.03c-72.62,9.68-56.39,142.67,9.9,138.61,97.02-5.94,49.5-146.53-9.9-138.61Z",
            "M2686.12,343.13c-64.18-8.02-87.35,95.19-26.56,112.77,66.28,19.16,73.26-106.93,26.56-112.77Z",
            "M1614.07,445.99c19.8-85.14,41.58-116.83,55.44-116.83s37.62,108.91,73.26,128.71",
            "M1934.85,172.74c47.52-45.54,186.13-25.74,194.05,33.66,7.92,59.4-39.6,97.02-37.62,122.77s56.36,69.3,38.54,120.79-66.26,57.42-137.55,25.74",
            "M2002.17,198.48c-5.94,47.52-1.98,209.89,7.92,241.57",
            "M2352.65,182.64c-7.92,55.44-9.84,280.18,67.32,277.21,51.48-1.98,57.42-116.83-17.82-122.77",
            "M2590.26,305.41c-35.64,13.86-59.4,27.56-59.4,134.65,0,9.9-15.84-93.06-19.8-116.83",
            "M2881.33,392.53s-9.9,67.32,39.6,65.34c69.28-2.77,130.89-59.33,148.51-138.61,15.84-71.28-39.6-83.16-39.6-83.16",
            "M2778.37,360.85c-7.92,49.5-1.85,92.77,17.82,95.04,51.48,5.94,85.14-63.36,85.14-63.36",
        ])

    /// apps-by-jon-bobrow.svg, for the link to all the apps.
    static let appsBy = Signature(
        text: "Apps by Jon Bobrow",
        viewBox: CGSize(width: 3072.11, height: 681.93),
        strokes: [
            "M1594.93,335.11c0,17.82,19.8,77.22,3.96,110.89",
            "M1373.16,55.92c29.7,142.57,55.95,373.41-47.52,407.9-71.28,23.76-100.98-51.48-93.06-83.16",
            "M1491.97,321.25c-45.54-3.96-56.51,138.61,9.9,138.61,73.26,0,47.85-133.59-9.9-138.61Z",
            "M2210.74,343.03c-72.62,9.68-56.39,142.67,9.9,138.61,97.02-5.94,49.5-146.53-9.9-138.61Z",
            "M2670.94,343.13c-64.18-8.02-87.35,95.19-26.56,112.77,66.28,19.16,73.26-106.93,26.56-112.77Z",
            "M1598.89,445.99c19.8-85.14,41.58-116.83,55.44-116.83s37.62,108.91,73.26,128.71",
            "M1919.67,172.74c47.52-45.54,186.13-25.74,194.05,33.66,7.92,59.4-39.6,97.02-37.62,122.77s56.36,69.3,38.54,120.79-66.26,57.42-137.55,25.74",
            "M1986.99,198.48c-5.94,47.52-1.98,209.89,7.92,241.57",
            "M2337.47,182.64c-7.92,55.44-9.84,280.18,67.32,277.21,51.48-1.98,57.42-116.83-17.82-122.77",
            "M2575.08,305.41c-35.64,13.86-59.4,27.56-59.4,134.65,0,9.9-15.84-93.06-19.8-116.83",
            "M2866.15,392.53s-9.9,67.32,39.6,65.34c69.28-2.77,130.89-59.33,148.51-138.61,15.84-71.28-39.6-83.16-39.6-83.16",
            "M2763.19,360.85c-7.92,49.5-1.85,92.77,17.82,95.04,51.48,5.94,85.14-63.36,85.14-63.36",
            "M15,537.47C23.66,136.35,107.34,18.04,136.2,15.15c28.86-2.89,86.57,31.74,86.57,484.8",
            "M80.58,356.55c65.34-37.62,178.21-25.74,178.21-25.74",
            "M320.17,330.81c81.18-15.84,176.23,73.26,47.52,142.57",
            "M466.7,328.83c81.18-15.84,160.39,71.28,67.32,134.65",
            "M353.83,396.15c-5.94,104.95,29.7,241.57,29.7,241.57",
            "M490.46,378.33c-5.94,104.95,13.86,211.87,13.86,211.87",
            "M865.25,148.98c-11.88,49.5-26.16,130.64-33.66,199.99-7.92,73.26,38.68,123.77,86.2,90.1s12.8-101.98-40.66-98.06",
            "M999.9,537.08c-35.64,27.72-53.4,109.67,2.96,126.69,69.81,21.08,80.2-67.28,76.24-138.57s-19.8-194.05-19.8-194.05",
            "M1059.3,331.15c1.98,75.24-9.9,118.81-51.48,110.89s-31.68-85.14-23.76-128.71",
            "M667.65,308.05c-45.54,7.92-55.44,17.82-53.46,33.66s61.38,49.5,69.3,81.18c7.92,31.68-39.6,61.38-77.22,33.66",
        ])
}

/// A signature's strokes, fit to whatever rect it's given. Stroke it to draw
/// it.
struct SignatureShape: Shape {
    let signature: Signature

    func path(in rect: CGRect) -> Path {
        let box = signature.viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        let x = rect.midX - box.width * scale / 2
        let y = rect.midY - box.height * scale / 2
        return signature.path.applying(
            CGAffineTransform(translationX: x, y: y).scaledBy(x: scale, y: scale))
    }
}

/// Reads an SVG path's `d` attribute: move, line, cubic curve and close
/// commands, absolute or relative. Enough for a drawing exported from
/// Illustrator.
private struct SVGPathData {
    private let scalars: [Character]
    private var index = 0

    init(_ d: String) { scalars = Array(d) }

    func append(to path: inout Path) {
        var reader = self
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?   // for "s", the previous curve's second control point
        var command: Character = "M"

        while let next = reader.nextCommand(default: command) {
            command = next
            let relative = command.isLowercase
            let origin = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = reader.number(), let y = reader.number() else { return nil }
                return CGPoint(x: origin.x + x, y: origin.y + y)
            }

            switch command.lowercased() {
            case "m":
                guard let p = point() else { return }
                path.move(to: p)
                current = p; start = p; lastControl = nil
                command = relative ? "l" : "L"   // further pairs are lines
            case "l":
                guard let p = point() else { return }
                path.addLine(to: p)
                current = p; lastControl = nil
            case "h":
                guard let x = reader.number() else { return }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current); lastControl = nil
            case "v":
                guard let y = reader.number() else { return }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current); lastControl = nil
            case "c":
                guard let c1 = point(), let c2 = point(), let p = point() else { return }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastControl = c2
            case "s":
                guard let c2 = point(), let p = point() else { return }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastControl = c2
            case "z":
                path.closeSubpath()
                current = start; lastControl = nil
            default:
                return
            }
        }
    }

    /// The next command letter, or `previous` again if more numbers follow it.
    private mutating func nextCommand(default previous: Character) -> Character? {
        skipSeparators()
        guard index < scalars.count else { return nil }
        let c = scalars[index]
        if c.isLetter {
            index += 1
            return c
        }
        return previous.lowercased() == "z" ? nil : previous
    }

    private mutating func number() -> CGFloat? {
        skipSeparators()
        let begin = index
        var seenDot = false, seenExponent = false
        if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
        while index < scalars.count {
            let c = scalars[index]
            if c.isNumber {
                index += 1
            } else if c == ".", !seenDot, !seenExponent {
                seenDot = true; index += 1
            } else if c == "e" || c == "E", !seenExponent {
                seenExponent = true; index += 1
                if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
            } else {
                break
            }
        }
        return Double(String(scalars[begin..<index])).map { CGFloat($0) }
    }

    private mutating func skipSeparators() {
        while index < scalars.count, scalars[index] == "," || scalars[index].isWhitespace { index += 1 }
    }
}

#Preview {
    VStack(spacing: 40) {
        SignatureButton {}
        SignatureLabel(signature: .appsBy, mark: .linkOut)
    }
    .padding(40)
    .background(.black)
    .preferredColorScheme(.dark)
}
