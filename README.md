# Audio Bubble

Hear the people you're with, clearly and instantly, even in loud places.

Audio Bubble shows you the Audio Bubble users nearby. Tap the people you want, they accept, and
you're in a bubble together: you hear everyone else in the bubble, never yourself. It works
phone to phone with **no Wi-Fi network at all**, and that's also where it sounds best.

See [PLAN.md](PLAN.md) for the original design and the reasoning behind it.

## Using it

1. **First launch:** a short introduction, then choose your name, a color, and optionally a
   Memoji or emoji for your bubble.
2. **Put in your headphones.** They're required: without them you can't start or join a
   bubble, and if they come out mid-bubble your audio pauses until they're back.
3. **Nearby people float as bubbles.** Drag or flick them around (they shove each other out of
   the way). Tap someone to invite them. They get a banner,
   *"Jon wants to bubble with you"*, with **Join** and **Not now**.
4. **In a bubble:** everyone gathers in one large circle and glows with their voice. There's
   Mute, Leave, and a Mic Mode button for choosing **Voice Isolation**.
5. **Leave the Wi-Fi network for the best audio.** Keep Wi-Fi *on*, but don't join a network:
   open Control Center and tap Wi-Fi. If you're in a bubble while joined to a network, the app
   tells you how.
6. **Tap your name** to change your name, color or bubble (tap the bubble to pick a Memoji
   sticker or any emoji), replay the introduction, or turn on Debug mode.

Audio keeps going with the screen locked.

## How it works

```
 mic ─► VoiceProcessingIO (AEC/NS/AGC, 48 kHz, ~5 ms I/O) ─► capture ring ─► sender thread
        ─► 5 ms Int16 PCM frames ─► UDP (.interactiveVoice, includePeerToPeer) ─► every member

 speaker ◄─ soft limiter ◄─ mix ◄─ self-echo suppressor ◄─ adaptive jitter buffer ◄─ UDP
                                    (per peer, with your mic as the reference)
```

- **Audio I/O:** a raw VoiceProcessingIO AudioUnit: Apple's echo cancellation, noise
  suppression and AGC in one ~5 ms real-time cycle. The real-time callbacks never lock or
  allocate; they talk to other threads through lock-free rings.
- **No codec:** 48 kHz 16-bit mono PCM in 5 ms frames. That's no codec delay and no quality
  loss, at ~800 kbps per stream.
- **Transport:** Bonjour `_audio-bubble._udp` and UDP with `includePeerToPeer`, always
  connecting to the service endpoint, so phones talk directly over AWDL when there's no shared
  network. Full mesh, marked `.interactiveVoice` (Wi-Fi voice priority).
- **Jitter buffer (per peer):** reorders packets and conceals losses by repeating the pitch
  period. Late packets are still played. It adapts its safety margin to the link and removes
  excess latency and clock drift by playing up to 1 % faster or slower.
- **Self-echo suppression:** people in a bubble share a room, so their mics also pick up *your*
  voice and send it back ~100 ms later. Your phone finds your voice in each incoming stream (it
  estimates the delay and learns how loudly you leak in) and turns down just those frequencies.
  The other person's voice passes through.
- **Membership:** leaderless. Every phone says hello once a second with its name, color and
  bubble id, and a bubble is everyone advertising the same id. Invites and replies are sent
  several times and de-duplicated, so there's no host to lose.
- **Avatars:** iOS has no API for reading someone's Memoji, so the picker opens the emoji
  keyboard in a text view that accepts adaptive image glyphs, where Memoji stickers (and
  Genmoji) arrive as images. The image is shrunk to a 240 px HEIC with transparency (~10 KB).
  Hellos carry only its version; peers fetch it once in 900-byte chunks and re-request any
  that go missing. An emoji just rides along in the hello.
- **Wi-Fi advice:** a joined Wi-Fi network makes the radio time-share with the access point
  (or send traffic through it), which raises latency and hurts quality. The app detects this
  and explains how to leave the network while keeping Wi-Fi on.

Expected mouth-to-ear latency with no Wi-Fi network is roughly 20–35 ms plus your headphones'
own latency; Bluetooth headphones add a noticeable amount.

## Code layout

| Folder | What's in it |
|---|---|
| `AudioBubble/Core/` | Platform-independent, unit-tested DSP and protocol: SPSC rings, wire protocol, jitter buffer, loss concealment, STFT, self-echo suppressor, limiter, and the bubble physics |
| `AudioBubble/Audio/` | Audio session (route, headphones, interruptions), the VoiceProcessingIO engine, the stream table / mixer |
| `AudioBubble/Network/` | Bonjour + UDP mesh transport, the sender thread, the Wi-Fi monitor |
| `AudioBubble/Model/` | `@Observable` app state: identity, peers, bubble membership, invites, latency |
| `AudioBubble/UI/` | SwiftUI: introduction, home, bubble, invite banner, settings |
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

The tests cover the ring buffers, wire-protocol round trips, avatar chunking and image
preparation, loss concealment, the limiter, and
simulations of the jitter buffer (reordering, loss, jitter, clock drift, an 80 ms AWDL-style
delay spike) and the self-echo suppressor (several delays and leak levels, double talk, no
echo, a delay that changes mid-session).

## Testing on devices

1. **No Wi-Fi network first:** two phones with Wi-Fi *on* but joined to no network (airplane
   mode with Wi-Fi on also works). Then try shared Wi-Fi to compare.
2. Check discovery, invite/accept, audio both ways, and that audio keeps going with the
   screen locked.
3. Use headphones. Standing near each other is a good test of self-echo suppression.

**Debug mode** (Settings → Debug mode, off by default) shows each member's estimated latency,
whether the link is direct or through a network, whether they're on Wi-Fi, and whether your
voice is being removed from their stream. Tap the latency readout for the breakdown: network,
buffer, processing and audio hardware.

Debug builds also take launch arguments:

| Argument | Effect |
|---|---|
| `-autoInvite [name]` | Invite the person with that name (or, without a name, the first person found; careful, that can be a real phone nearby) |
| `-autoAccept` | Accept any invite |
| `-introPage <0-3>` | Open the introduction on a given page |
| `-nameStep` | Open the name and color step |
| `-showSettings` | Open Settings on launch |
| `-assumeHeadphones` | Act as if headphones are connected (simulators have none) |
| `-demoDrag` | Drag a nearby bubble around automatically (for measuring the bubble field; frame timing is logged under category `bubbles`) |
| `-avatarPicker` | With `-showSettings` or `-nameStep`, also open the Memoji picker |

They also log each member's round trip, buffer depth, link and estimated latency once a
second (subsystem `com.jonbobrow.AudioBubble`, category `model`).

Two simulators on the same Mac find each other and can bubble, which is handy for UI and
protocol work. They share the Mac's microphone, so they also exercise self-echo suppression,
but they say nothing about real radio latency.
