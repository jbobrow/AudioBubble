import Foundation
import Testing
@testable import AudioBubble

struct AvatarTransferTests {
    static let image = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })

    @Test func reassemblesChunksInAnyOrderWithDuplicates() throws {
        let chunks = AvatarTransfer.chunks(of: Self.image)
        #expect(chunks.count == 12)
        #expect(chunks.allSatisfy { $0.count <= AvatarTransfer.chunkSize })
        let version = AvatarTransfer.version(of: Self.image)
        var assembly = try #require(AvatarTransfer.Assembly(version: version, count: chunks.count))
        for index in chunks.indices.reversed() where index != 5 {
            assembly.insert(index: index, data: chunks[index])
            assembly.insert(index: index, data: chunks[index])
        }
        #expect(assembly.missing == [5])
        #expect(assembly.data == nil)
        assembly.insert(index: 5, data: chunks[5])
        #expect(assembly.data == Self.image)
    }

    @Test func rejectsCorruptOrOversizedImages() throws {
        let chunks = AvatarTransfer.chunks(of: Self.image)
        var assembly = try #require(AvatarTransfer.Assembly(version: AvatarTransfer.version(of: Self.image), count: chunks.count))
        for (index, chunk) in chunks.enumerated() {
            assembly.insert(index: index, data: index == 3 ? Data(chunk.reversed()) : chunk)
        }
        #expect(assembly.data == nil)
        #expect(AvatarTransfer.Assembly(version: 1, count: AvatarTransfer.maxChunks + 1) == nil)
        #expect(AvatarTransfer.Assembly(version: 1, count: 0) == nil)
    }

    @Test func versionIsStableAndSensitive() {
        #expect(AvatarTransfer.version(of: Self.image) == AvatarTransfer.version(of: Self.image))
        var changed = Self.image
        changed[100] ^= 1
        #expect(AvatarTransfer.version(of: changed) != AvatarTransfer.version(of: Self.image))
    }
}
