import Foundation

/// Every datagram starts with a 12-byte header:
///
///     0      magic 0xAB
///     1      version
///     2      kind (1 = audio, 2 = control)
///     3      flags (bit 0 = silent audio frame, payload omitted)
///     4..<12 sender id, UInt64 little-endian
///
/// Audio body: sequence number (UInt32 LE) then 240 Int16 LE samples, 48 kHz mono.
/// Control body: a JSON-encoded `ControlMessage`.
nonisolated enum WireProtocol {
    static let magic: UInt8 = 0xAB
    static let version: UInt8 = 1
    static let headerSize = 12
    static let audioHeaderSize = headerSize + 4
    static let audioPacketSize = audioHeaderSize + AudioFormat.frameSamples * 2

    enum Kind: UInt8 { case audio = 1, control = 2 }

    struct Header: Equatable {
        var kind: Kind
        var silent: Bool
        var sender: UInt64
    }

    static func parseHeader(_ bytes: UnsafeRawBufferPointer) -> Header? {
        guard bytes.count >= headerSize,
              bytes[0] == magic, bytes[1] == version,
              let kind = Kind(rawValue: bytes[2]) else { return nil }
        let sender = UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: 4, as: UInt64.self))
        return Header(kind: kind, silent: bytes[3] & 1 != 0, sender: sender)
    }

    private static func writeHeader(_ header: Header, into bytes: UnsafeMutableRawBufferPointer) {
        bytes[0] = magic
        bytes[1] = version
        bytes[2] = header.kind.rawValue
        bytes[3] = header.silent ? 1 : 0
        bytes.storeBytes(of: header.sender.littleEndian, toByteOffset: 4, as: UInt64.self)
    }

    // MARK: Audio

    /// Writes an audio packet into `buffer`, which must hold at least `audioPacketSize` bytes.
    /// Pass nil `samples` for a silent frame. Returns the packet length.
    static func encodeAudio(sender: UInt64, sequence: UInt32, samples: UnsafePointer<Int16>?,
                            into buffer: UnsafeMutableRawBufferPointer) -> Int {
        precondition(buffer.count >= audioPacketSize)
        writeHeader(Header(kind: .audio, silent: samples == nil, sender: sender), into: buffer)
        buffer.storeBytes(of: sequence.littleEndian, toByteOffset: headerSize, as: UInt32.self)
        guard let samples else { return audioHeaderSize }
        for i in 0..<AudioFormat.frameSamples {
            buffer.storeBytes(of: samples[i].littleEndian, toByteOffset: audioHeaderSize + i * 2, as: Int16.self)
        }
        return audioPacketSize
    }

    static func encodeAudio(sender: UInt64, sequence: UInt32, samples: UnsafePointer<Int16>?) -> Data {
        var data = Data(count: audioPacketSize)
        let length = data.withUnsafeMutableBytes {
            encodeAudio(sender: sender, sequence: sequence, samples: samples, into: $0)
        }
        data.count = length
        return data
    }

    struct AudioFrame {
        var sequence: UInt32
        /// Little-endian Int16 samples; empty for a silent frame.
        var payload: UnsafeRawBufferPointer
    }

    /// Parses the body of an audio packet. The payload points into `bytes`.
    static func parseAudio(_ bytes: UnsafeRawBufferPointer, header: Header) -> AudioFrame? {
        guard header.kind == .audio, bytes.count >= audioHeaderSize else { return nil }
        let sequence = UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: headerSize, as: UInt32.self))
        if header.silent { return AudioFrame(sequence: sequence, payload: UnsafeRawBufferPointer(start: nil, count: 0)) }
        guard bytes.count >= audioPacketSize else { return nil }
        return AudioFrame(sequence: sequence, payload: UnsafeRawBufferPointer(rebasing: bytes[audioHeaderSize..<audioPacketSize]))
    }

    // MARK: Control

    static func encodeControl(_ message: ControlMessage, sender: UInt64) -> Data? {
        guard let body = try? JSONEncoder().encode(message) else { return nil }
        var data = Data(count: headerSize)
        data.withUnsafeMutableBytes { writeHeader(Header(kind: .control, silent: false, sender: sender), into: $0) }
        data.append(body)
        return data
    }

    static func decodeControl(_ data: Data) -> ControlMessage? {
        guard data.count > headerSize else { return nil }
        return try? JSONDecoder().decode(ControlMessage.self, from: data.dropFirst(headerSize))
    }
}

/// Small, infrequent messages. Membership is leaderless: each peer's hello says which bubble it is in.
nonisolated enum ControlMessage: Codable, Equatable, Sendable {
    /// Sent about once a second to every nearby peer.
    case hello(Hello)
    /// "Join my bubble". Sent several times; de-duplicated by `id`.
    case invite(Invite)
    /// The answer to an invite. Sent several times; de-duplicated by `id`.
    case reply(InviteReply)
    /// "Send me your avatar image", optionally just some chunks of it.
    case avatarRequest(AvatarRequest)
    /// One piece of an avatar image.
    case avatarChunk(AvatarChunk)

    struct Hello: Codable, Equatable, Sendable {
        var name: String
        /// Color hue, 0...1.
        var hue: Double
        /// The bubble this peer is in, if any.
        var bubble: UUID?
        /// Sender's monotonic clock, in microseconds.
        var time: UInt64
        /// The latest `time` this peer received from the recipient, echoed back for RTT.
        var echoTime: UInt64?
        /// Microseconds between receiving `echoTime` and sending this hello.
        var echoHold: UInt64?
        /// Whether the sender is joined to a Wi-Fi network (which slows its direct links).
        var onWiFi: Bool?
        /// An emoji shown in the sender's bubble instead of their initial.
        var emoji: String?
        /// Version of the sender's avatar image (a Memoji), if they have one. Fetch it with
        /// `avatarRequest`.
        var avatarVersion: UInt32?
    }

    struct Invite: Codable, Equatable, Sendable {
        var id: UUID
        var bubble: UUID
    }

    struct InviteReply: Codable, Equatable, Sendable {
        var id: UUID
        var bubble: UUID
        var accepted: Bool
    }

    struct AvatarRequest: Codable, Equatable, Sendable {
        var version: UInt32
        /// Chunks wanted; nil for all of them.
        var chunks: [Int]?
    }

    struct AvatarChunk: Codable, Equatable, Sendable {
        var version: UInt32
        var index: Int
        var count: Int
        var data: Data
    }
}
