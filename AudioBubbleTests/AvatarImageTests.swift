import Testing
import UIKit
@testable import AudioBubble

struct AvatarImageTests {
    /// A stand-in for a Memoji sticker: a colorful face on a transparent background.
    static func sticker(side: CGFloat = 400) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side * 1.1), format: format).image { context in
            let colors = [UIColor.systemYellow.cgColor, UIColor.systemOrange.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            context.cgContext.addEllipse(in: CGRect(x: side * 0.15, y: side * 0.15, width: side * 0.7, height: side * 0.8))
            context.cgContext.clip()
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        }
    }

    @Test func producesASmallSquareImageThatKeepsTransparency() throws {
        let data = try #require(AvatarImage.prepare(Self.sticker()))
        #expect(data.count <= AvatarImage.maxBytes, "\(data.count) bytes")
        #expect(data.count <= 30 * AvatarTransfer.chunkSize, "\(data.count) bytes is more than 30 chunks")

        let image = try #require(UIImage(data: data))
        #expect(image.size.width == AvatarImage.side && image.size.height == AvatarImage.side)
        let pixels = try #require(Self.rgba(image))
        let side = Int(image.size.width)
        let corner = pixels[3]                                 // alpha of the top-left pixel
        let center = pixels[((side / 2) * side + side / 2) * 4 + 3]
        #expect(corner < 10, "corner alpha \(corner)")
        #expect(center > 245, "center alpha \(center)")
    }

    @Test func roundTripsThroughTheAvatarTransfer() throws {
        let data = try #require(AvatarImage.prepare(Self.sticker()))
        let chunks = AvatarTransfer.chunks(of: data)
        var assembly = try #require(AvatarTransfer.Assembly(version: AvatarTransfer.version(of: data), count: chunks.count))
        for (index, chunk) in chunks.enumerated().shuffled() { assembly.insert(index: index, data: chunk) }
        let received = try #require(assembly.data)
        #expect(UIImage(data: received) != nil)
    }

    @Test func recognizesEmojiButNotPlainCharacters() {
        for emoji in ["🦊", "👍🏽", "❤️", "👩‍👩‍👧", "🇯🇵", "☕️"] { #expect(Character(emoji).isEmoji, "\(emoji)") }
        for plain in ["a", "1", "#", "©", "→", " "] { #expect(!Character(plain).isEmoji, "\(plain)") }
    }

    private static func rgba(_ image: UIImage) -> [UInt8]? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? pixels : nil
    }
}
