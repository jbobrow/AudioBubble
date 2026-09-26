import UIKit

/// Draws a bubble's pieces into bitmaps, once. The field view only ever moves and transforms
/// them, so nothing is redrawn while bubbles are in motion.
enum BubbleArt {
    /// Space around the circle for its glow.
    static let glowMargin: CGFloat = 30

    static func color(_ hue: Double) -> UIColor {
        UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1)
    }

    /// The soft colored halo (in place of a live, blurred shadow).
    static func glow(hue: Double, size: CGFloat, scale: CGFloat) -> CGImage? {
        let side = size + 2 * glowMargin
        return render(CGSize(width: side, height: side), scale: scale) { context in
            let c = color(hue)
            let colors = [c.withAlphaComponent(0.85).cgColor, c.withAlphaComponent(0.35).cgColor,
                          c.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1])!
            let center = CGPoint(x: side / 2, y: side / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: size * 0.42,
                                       endCenter: center, endRadius: side / 2, options: [])
        }
    }

    /// The colored circle with the person's initial, emoji or Memoji.
    static func body(name: String, hue: Double, avatar: AvatarContent, size: CGFloat, scale: CGFloat) -> CGImage? {
        render(CGSize(width: size, height: size), scale: scale) { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            // Like SwiftUI's `Color.gradient`: a touch lighter at the top.
            let base = color(hue)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let top = UIColor(hue: h, saturation: s * 0.82, brightness: min(1, b * 1.04), alpha: 1)
            let bottom = UIColor(hue: h, saturation: min(1, s * 1.08), brightness: b * 0.93, alpha: 1)
            context.addEllipse(in: rect)
            context.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])

            switch avatar {
            case .initial:
                let font = UIFont.systemFont(ofSize: size * 0.4, weight: .semibold)
                let rounded = font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 0) } ?? font
                drawCentered(String(name.prefix(1)).uppercased(), font: rounded,
                             color: UIColor.black.withAlphaComponent(0.6), in: rect)
            case let .emoji(emoji):
                drawCentered(emoji, font: .systemFont(ofSize: size * 0.56), color: .black, in: rect)
            case let .image(image):
                let side = size * 0.92
                let aspect = image.size.width / max(image.size.height, 1)
                let drawn = aspect >= 1 ? CGSize(width: side, height: side / aspect) : CGSize(width: side * aspect, height: side)
                image.draw(in: CGRect(x: (size - drawn.width) / 2, y: (size - drawn.height) / 2 + size * 0.04,
                                      width: drawn.width, height: drawn.height))
            }
        }
    }

    /// The name (or "Invited…") under a bubble.
    static func label(_ text: String, scale: CGFloat) -> (image: CGImage?, size: CGSize) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .medium),
            .foregroundColor: UIColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: 240, height: 60), options: .usesLineFragmentOrigin, context: nil)
        let size = CGSize(width: ceil(bounds.width), height: ceil(bounds.height))
        let image = render(size, scale: scale) { _ in string.draw(at: .zero) }
        return (image, size)
    }

    private static func drawCentered(_ text: String, font: UIFont, color: UIColor, in rect: CGRect) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    private static func render(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }.cgImage
    }
}
