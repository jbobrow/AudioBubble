# Audio Bubble

Audio Bubble shows you the Audio Bubble users nearby. Tap the people you want, they accept, and
you're in a bubble together: you hear everyone else in the bubble, never yourself. It works with
no Wi-Fi network at all (peer-to-peer over AWDL) and on shared Wi-Fi.

See [PLAN.md](PLAN.md) for the design and the reasoning behind it.

## How it works

```
 mic ─► VoiceProcessingIO (AEC/NS/AGC, 48 kHz, ~5 ms I/O) ─► capture ring ─► sender thread
        ─► 5 ms Int16 PCM frames ─► UDP (.interactiveVoice, includePeerToPeer) ─► every member
 speaker ◄─ mixer + soft limiter ◄─ per-peer adaptive jitter buffers ◄─ frame queues ◄─ UDP
```

| Folder | What's in it |
|---|---|
| `AudioBubble/Core/` | Platform-independent, unit-tested: SPSC rings, wire protocol, jitter buffer, concealment, limiter |
| `AudioBubble/Audio/` | Audio session, the VoiceProcessingIO engine, the stream table / mixer |
| `AudioBubble/Network/` | Bonjour + UDP mesh transport, the sender thread |
| `AudioBubble/Model/` | `@Observable` app state: identity, peers, bubble membership, invites |
| `AudioBubble/UI/` | SwiftUI views |
| `AudioBubbleTests/` | Swift Testing unit tests for Core |

Requires iOS 18 (for `Synchronization.Atomic`).

## Build and test

```sh
# Build for device
xcodebuild -project AudioBubble.xcodeproj -scheme AudioBubble -destination 'generic/platform=iOS' build

# Unit tests (any iOS simulator)
xcodebuild -project AudioBubble.xcodeproj -scheme AudioBubble \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Testing on devices

1. **No Wi-Fi network first:** two phones with Wi-Fi *on* but joined to no network (airplane
   mode with Wi-Fi on also works). Then repeat on shared Wi-Fi.
2. Check discovery, invite/accept, audio both ways, the latency readout, and that audio keeps
   going with the screen locked.
3. Use headphones, or expect Apple's echo cancellation to work hard on speakerphone.

Debug builds accept launch arguments for hands-free testing: `-autoInvite` invites the first
person found, `-autoAccept` accepts any invite. They also log each member's RTT, jitter-buffer
depth and estimated latency (subsystem `com.jonbobrow.AudioBubble`, category `model`).

Two simulators on the same Mac also find each other and can bubble, which is handy for UI and
protocol work (though not representative of real radio latency).
