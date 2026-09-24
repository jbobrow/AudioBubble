# Audio Bubble — Rebuild Plan

Audio Bubble shows you the Audio Bubble users nearby. You tap the people you want,
they accept, and you're in a bubble together: you hear everyone else in the bubble,
never yourself. The goals are superb audio quality and the lowest latency we can get.

## Why the previous attempts sounded bad

| Previous approach | Problem |
|---|---|
| `AVAudioInputNode.installTap(bufferSize: 256)` | iOS ignores small tap sizes and delivers ~100 ms chunks. That alone added ~100 ms and made the audio bursty. |
| `AVAudioPlayerNode.scheduleBuffer` for every packet | No jitter buffer: late packets cause gaps and clicks, early ones pile up latency that never drains. There's also no correction for clock drift between devices. |
| A new `AVAudioConverter` for every buffer, resampling to 16 kHz | Resampler state is thrown away each buffer (clicks and "funny effects"), and the audio is capped at telephone bandwidth. |
| MultipeerConnectivity `.unreliable` | Opaque buffering, it can fall back to Bluetooth (very high latency), and its latency varies a lot. Invitations are awkward, and there's no control over QoS. |
| `Date()` timestamps compared across devices | The devices' clocks aren't synced, so the latency numbers it showed were meaningless. |

## New architecture

```
 mic ─► VoiceProcessingIO AudioUnit (AEC/NS/AGC, 48 kHz, ~5 ms I/O buffer)
          │ input callback (real-time thread)
          ▼
   lock-free capture ring ─► sender thread ─► 5 ms Int16 PCM frames ─► UDP (NWConnection, .interactiveVoice)
                                                                            │ one flow per bubble member (mesh)
 speaker ◄─ mixer + soft limiter ◄─ per-peer jitter buffers ◄─ lock-free packet queues ◄─ UDP receive
          output callback (real-time thread)
```

1. **Audio I/O: a raw `kAudioUnitSubType_VoiceProcessingIO` AudioUnit**, the same approach
   WebRTC uses on iOS. Input and output happen in one real-time I/O cycle of about 5 ms,
   with Apple's echo cancellation, noise suppression and AGC. Because the app is in
   voice-chat mode, the user can pick **Voice Isolation** in Control Center's Mic Modes;
   the app has a button that opens it. Mic audio is never sent to the local output,
   so you never hear yourself.
2. **Codec: none.** Each frame is 48 kHz, 16-bit mono PCM covering 5 ms (240 samples),
   about 800 kbps per stream. That's trivial on a local network, and it means no codec
   delay and no quality loss.
3. **Transport: Network.framework over UDP.**
   - Bonjour `_audio-bubble._udp` with `includePeerToPeer = true`, so it works on shared
     Wi-Fi *and* with no Wi-Fi at all (AWDL).
   - `serviceClass = .interactiveVoice` puts packets in the Wi-Fi voice access category
     (WMM AC_VO), so they get priority over other traffic.
   - Full mesh: each member sends directly to every other member. That's one hop and
     no relay, which is lowest latency for bubbles of 2–8 people.
4. **Adaptive jitter buffer (per peer, all on the audio thread):**
   - Reorders packets by sequence number. A packet is declared lost only when its audio
     is actually needed, so late packets still get used.
   - Packet loss concealment: pitch-period repetition with overlap-add and a fade-out,
     then a crossfade back when real audio resumes.
   - Controls the *minimum* buffer level toward a small safety margin (starting at
     2.5 ms). Each underrun raises the margin; clean periods slowly lower it again.
   - Excess latency and clock drift are removed by playing ±0.5–1 % faster or slower
     through a cubic resampler. That's inaudible, with no skips or clicks.
   - **Peer-to-peer comes first — the app must work with no Wi-Fi network at all.**
     With `includePeerToPeer`, Network.framework uses AWDL, the direct Wi-Fi link that
     AirDrop uses, whenever there's no shared access point. Rules:
     - Set `includePeerToPeer = true` on the listener, the browser *and* every connection.
     - Connect to the Bonjour **service endpoint**, never a resolved IP address, so the
       system can route over AWDL (`awdl0`).
     - The data path must never assume there's a router or DHCP address. No IP
       literals, and no multicast or broadcast for audio.
     - Wi-Fi must be *on*, but it doesn't need to be joined to a network, and airplane
       mode with Wi-Fi on works. If no one is found after a few seconds, the empty state
       says "Keep Wi-Fi on. No network needed."
     - Don't use Bluetooth for audio: its bandwidth and latency can't carry this. That
       ruled out MultipeerConnectivity's Bluetooth fallback.
     - AWDL latency spikes: AWDL periodically hops channels, which causes bursts of
       delay of tens of milliseconds. The jitter buffer's upper limit must absorb these
       (up to 150 ms) and then drain back down automatically.
     - Test the no-network case first: two phones with Wi-Fi on, joined to no network.
   - Worth evaluating later: the iOS 26 **Wi-Fi Aware** framework, a standard
     peer-to-peer Wi-Fi link that may give steadier latency than AWDL. It needs an
     entitlement and a device-pairing step, so it's not the default.
5. **Membership: leaderless and eventually consistent.** Every peer sends a small hello
   about once a second with its id, name, color and current `bubbleID`. The bubble is simply
   "everyone advertising my `bubbleID`". Invite and accept messages are sent several times
   and de-duplicated by id. There's no server and no host to lose.
6. **Threading:** the real-time callbacks never lock, allocate or make system calls.
   Data crosses threads only through single-producer/single-consumer rings built on
   `Synchronization.Atomic`, which requires raising the deployment target to iOS 18.
   The capture side wakes the sender thread with a semaphore.
7. **Latency display:** RTT is measured from hello echoes. The estimated mouth-to-ear
   latency shown is one-way network time + jitter-buffer depth + hardware I/O latency.

Expected mouth-to-ear latency on good Wi-Fi: about 5 ms I/O + 5 ms framing + 2–10 ms
network + 3–10 ms jitter buffer (more over AWDL during channel hops) + about 5 ms output, so **about 20–35 ms**. Previous
builds measured 100 ms or more. Bluetooth HFP to AirPods adds its own link latency
on top.

## User experience

- **First launch:** you choose a name. A color is picked for you.
- **Main screen:** nearby people float as soft colored bubbles. Tap someone to invite them.
- **Invite:** a gentle banner appears for them: *"Maya wants to bubble with you"*,
  with **Join** and **Not now**.
- **In a bubble:** members gather into one large bubble. Each member glows with their
  live voice level. There's a mute button, a Leave button, and a small latency readout.
- **Background audio** keeps the bubble alive when the screen locks.

## Code layout

- `AudioBubble/Core/` — platform-independent, unit-testable: SPSC rings, jitter buffer,
  concealment, wire protocol.
- `AudioBubble/Audio/` — audio session, the VoiceProcessingIO engine, the stream table.
- `AudioBubble/Network/` — Bonjour discovery, UDP links, the sender thread.
- `AudioBubble/Model/` — `@Observable` app state: identity, peers, bubble, invites.
- `AudioBubble/UI/` — SwiftUI views.

## Verification

- Unit tests for the Core module: jitter buffer under simulated jitter, loss and
  reordering; the concealment output; wire-protocol round trips.
- `xcodebuild` for iOS, run on the Mac.
- Test on two devices **with no Wi-Fi network**, then on shared Wi-Fi: discovery, invite/accept, audio in both directions, the
  latency readout, and background/lock-screen behavior.
