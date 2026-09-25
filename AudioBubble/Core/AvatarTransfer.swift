import Foundation

/// Moving a Memoji (a small image) between phones.
///
/// Hellos only carry the image's version (a hash of its bytes). A peer that doesn't have that
/// version asks for it, and the owner replies with the image split into datagram-sized chunks.
/// Missing chunks are re-requested. Images are cached by version, so each is fetched once.
nonisolated enum AvatarTransfer {
    /// Raw bytes per chunk; with JSON's base64 and the header a chunk stays well under one
    /// Wi-Fi frame.
    static let chunkSize = 900
    /// Larger images are refused (the app sends ~10–20 KB).
    static let maxChunks = 96

    /// A stable 32-bit FNV-1a hash of the image bytes.
    static func version(of data: Data) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in data {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash == 0 ? 1 : hash
    }

    static func chunks(of data: Data) -> [Data] {
        stride(from: 0, to: data.count, by: chunkSize).map {
            data.subdata(in: $0..<min($0 + chunkSize, data.count))
        }
    }

    /// Collects the chunks of one image, in any order, with duplicates.
    struct Assembly {
        let version: UInt32
        let count: Int
        private var parts: [Data?]

        init?(version: UInt32, count: Int) {
            guard count > 0, count <= AvatarTransfer.maxChunks else { return nil }
            self.version = version
            self.count = count
            parts = Array(repeating: nil, count: count)
        }

        mutating func insert(index: Int, data: Data) {
            guard parts.indices.contains(index) else { return }
            parts[index] = data
        }

        var missing: [Int] { parts.indices.filter { parts[$0] == nil } }

        /// The image once every chunk has arrived and the bytes match the version.
        var data: Data? {
            guard missing.isEmpty else { return nil }
            let joined = parts.reduce(into: Data()) { $0.append($1!) }
            return AvatarTransfer.version(of: joined) == version ? joined : nil
        }
    }
}
