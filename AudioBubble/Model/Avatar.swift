import UIKit

/// What you've chosen to show in your bubble.
enum AvatarChoice: Equatable {
    /// The first letter of your name.
    case initial
    case emoji(String)
    /// A Memoji sticker (or Genmoji / sticker): prepared image bytes, see `AvatarImage`.
    case image(Data)
}

/// What a bubble actually draws.
enum AvatarContent: Equatable {
    case initial
    case emoji(String)
    case image(UIImage)
}

/// Saves your avatar: an emoji in user defaults, an image as a file.
enum AvatarStore {
    private static let emojiKey = "identity.emoji"

    private static var imageURL: URL {
        URL.applicationSupportDirectory.appending(path: "avatar.heic")
    }

    static func load() -> AvatarChoice {
        if let data = try? Data(contentsOf: imageURL), !data.isEmpty { return .image(data) }
        if let emoji = UserDefaults.standard.string(forKey: emojiKey), !emoji.isEmpty { return .emoji(emoji) }
        return .initial
    }

    static func save(_ choice: AvatarChoice) {
        let defaults = UserDefaults.standard
        switch choice {
        case .initial:
            defaults.removeObject(forKey: emojiKey)
            try? FileManager.default.removeItem(at: imageURL)
        case let .emoji(emoji):
            defaults.set(emoji, forKey: emojiKey)
            try? FileManager.default.removeItem(at: imageURL)
        case let .image(data):
            defaults.removeObject(forKey: emojiKey)
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? data.write(to: imageURL, options: .atomic)
        }
    }
}

/// Turns whatever the keyboard gave us (a Memoji sticker's multi-resolution HEIC, a PNG, …) into
/// a small square image with transparency, compact enough to send to peers in a few chunks.
enum AvatarImage {
    static let side: CGFloat = 240
    static let maxBytes = 48_000

    static func prepare(_ source: UIImage) -> Data? {
        for side in [side, 180, 128] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let size = CGSize(width: side, height: side)
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let scale = min(side / source.size.width, side / source.size.height)
                let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
                source.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                                       width: drawn.width, height: drawn.height))
            }
            if let data = image.heicData() ?? image.pngData(), data.count <= maxBytes { return data }
        }
        return nil
    }
}
