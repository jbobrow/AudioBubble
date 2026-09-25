import Testing
@testable import AudioBubble

struct SampleRingTests {
    @Test func wrapsAroundAndPreservesOrder() {
        let ring = SampleRing(capacity: 8)
        var next: Float = 0
        var expected: Float = 0
        var out = [Float](repeating: 0, count: 8)
        for _ in 0..<20 {
            var chunk = (0..<5).map { _ in defer { next += 1 }; return next }
            #expect(ring.write(&chunk, count: 5) == 5)
            #expect(ring.read(into: &out, count: 5) == 5)
            for v in out.prefix(5) { #expect(v == expected); expected += 1 }
        }
    }

    @Test func refusesToOverwriteUnreadSamples() {
        let ring = SampleRing(capacity: 8)
        var data = [Float](repeating: 1, count: 12)
        #expect(ring.write(&data, count: 12) == 8)
        #expect(ring.availableToWrite == 0)
        var out = [Float](repeating: 0, count: 12)
        #expect(ring.read(into: &out, count: 12) == 8)
        #expect(ring.availableToRead == 0)
    }
}

struct FrameQueueTests {
    @Test func pushesAndPopsFrames() {
        let queue = FrameQueue(capacity: 4)
        var bytes = [UInt8](repeating: 0, count: AudioFormat.frameSamples * 2)
        for i in 0..<AudioFormat.frameSamples {
            let v = Int16(i - 120).littleEndian
            bytes[i * 2] = UInt8(truncatingIfNeeded: v)
            bytes[i * 2 + 1] = UInt8(truncatingIfNeeded: v >> 8)
        }
        bytes.withUnsafeBytes { raw in
            for seq in 0..<4 { #expect(queue.push(sequence: UInt32(seq), silent: seq == 2, payload: raw)) }
            #expect(!queue.push(sequence: 4, silent: false, payload: raw))
        }
        for seq in 0..<4 {
            let popped = queue.pop { sequence, samples in
                #expect(sequence == UInt32(seq))
                if seq == 2 {
                    #expect(samples == nil)
                } else {
                    #expect(samples?[0] == -120)
                    #expect(samples?[239] == 119)
                }
            }
            #expect(popped)
        }
        #expect(!queue.pop { _, _ in })
    }
}

struct WireProtocolTests {
    @Test func audioRoundTrip() {
        let samples = (0..<AudioFormat.frameSamples).map { Int16($0 * 100 - 12_000) }
        let data = samples.withUnsafeBufferPointer {
            WireProtocol.encodeAudio(sender: 0x0123_4567_89AB_CDEF, sequence: 0xDEAD_BEEF, samples: $0.baseAddress)
        }
        #expect(data.count == WireProtocol.audioPacketSize)
        data.withUnsafeBytes { raw in
            let header = WireProtocol.parseHeader(raw)
            #expect(header == .init(kind: .audio, silent: false, sender: 0x0123_4567_89AB_CDEF))
            let frame = WireProtocol.parseAudio(raw, header: header!)
            #expect(frame?.sequence == 0xDEAD_BEEF)
            let payload = frame!.payload
            #expect(payload.count == AudioFormat.frameSamples * 2)
            for i in 0..<AudioFormat.frameSamples {
                #expect(Int16(littleEndian: payload.loadUnaligned(fromByteOffset: i * 2, as: Int16.self)) == samples[i])
            }
        }
    }

    @Test func silentAudioOmitsPayload() {
        let data = WireProtocol.encodeAudio(sender: 7, sequence: 3, samples: nil)
        #expect(data.count == WireProtocol.audioHeaderSize)
        data.withUnsafeBytes { raw in
            let header = WireProtocol.parseHeader(raw)!
            #expect(header.silent)
            #expect(WireProtocol.parseAudio(raw, header: header)?.payload.count == 0)
        }
    }

    @Test func controlRoundTrip() throws {
        let messages: [ControlMessage] = [
            .hello(.init(name: "Maya", hue: 0.42, bubble: UUID(), time: 123, echoTime: 99, echoHold: 7)),
            .hello(.init(name: "Sam", hue: 0, bubble: nil, time: 1, echoTime: nil, echoHold: nil)),
            .invite(.init(id: UUID(), bubble: UUID())),
            .reply(.init(id: UUID(), bubble: UUID(), accepted: true)),
            .hello(.init(name: "Jo", hue: 0.9, bubble: nil, time: 5, echoTime: nil, echoHold: nil,
                         onWiFi: true, emoji: "🦊", avatarVersion: 0xABCD_EF01)),
            .avatarRequest(.init(version: 7, chunks: [0, 3])),
            .avatarChunk(.init(version: 7, index: 2, count: 12, data: Data((0..<AvatarTransfer.chunkSize).map { UInt8($0 % 251) }))),
        ]
        for message in messages {
            let data = try #require(WireProtocol.encodeControl(message, sender: 42))
            let header = data.withUnsafeBytes { WireProtocol.parseHeader($0) }
            #expect(header == .init(kind: .control, silent: false, sender: 42))
            #expect(WireProtocol.decodeControl(data) == message)
            // Every control datagram, including a full avatar chunk, fits one Wi-Fi frame.
            #expect(data.count < 1_400, "\(data.count) bytes")
        }
    }

    @Test func rejectsForeignDatagrams() {
        let junk: [UInt8] = [0x00, 1, 1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 9, 9, 9]
        junk.withUnsafeBytes { #expect(WireProtocol.parseHeader($0) == nil) }
        let short: [UInt8] = [0xAB, 1, 1]
        short.withUnsafeBytes { #expect(WireProtocol.parseHeader($0) == nil) }
    }
}

import Foundation
