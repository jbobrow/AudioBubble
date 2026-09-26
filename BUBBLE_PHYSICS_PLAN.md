# Bubble Physics — Performance Plan

The first version (the `BubblePhysics` commit on this branch) lets you drag and flick the nearby
bubbles, and they shove each other aside. The physics works: its unit tests step it far faster
than real time. But on a phone the screen updates at about **1 fps**. This plan explains why, and
describes how to rebuild the view so it runs at the display's full rate (120 Hz on ProMotion)
using almost no CPU.

## Why the SwiftUI version is slow

The view is built as `TimelineView(.animation)` → `ZStack` → one `PeerBubble` per person. Every
frame, that setup:

1. **Rebuilds the whole view tree.** It calls `body` for every bubble, diffs the results, runs
   layout, and re-creates each bubble's `DragGesture` and `onTapGesture`. Re-creating gestures
   mid-drag can also make a drag stutter or restart.
2. **Redraws expensive effects from scratch.** Each bubble has a large blurred `.shadow`, a
   gradient fill and a clipped Memoji image. The stretch effect changes its rotation and
   uneven scale every frame, so none of that can be cached. Every blurred shadow is redrawn
   off-screen on every frame, and that is the most likely reason for 1 fps.
3. **Runs physics inside `body`, copying dictionaries.** The physics steps from inside the view
   body, and it copies its body dictionary to an array and back up to 6 times a frame. That's
   cheap in a Release build, but noticeable in Debug.

So the physics isn't the problem. The problem is asking SwiftUI to rebuild and redraw a set of
shadowed, clipped, transformed views 60–120 times a second.

**Step 0 below confirms this with Instruments before anything is rewritten.**

## The approach: Core Animation layers, a display link, raw touches

Draw each bubble **once**, into bitmaps. Every frame after that, only move and transform layers,
which the GPU does without redrawing anything. The field becomes a small UIKit view, hosted in
SwiftUI.

```
SwiftUI HomeView
  └─ BubbleField (UIViewRepresentable)        data in: peers, avatars, invited ids
       └─ BubbleFieldView: UIView             events out: onTap(peerID)
            ├─ CADisplayLink ──► BubblePhysics.step ──► write layer positions/transforms
            ├─ touchesBegan/Moved/Ended ──► physics.drag / endDrag, tap detection
            └─ one BubbleLayer per peer (a CALayer tree whose contents are pre-rendered bitmaps)
```

### 1. Rendering: pre-rendered bitmaps, per-frame transforms only

Each bubble is a `BubbleLayer`: a container `CALayer` with these sublayers.

| Sublayer | Contents | Redrawn when |
|---|---|---|
| `glow` | Bitmap of a soft radial gradient in the person's color (the "shadow"). No live `shadowRadius`. | Their color changes |
| `body` | Bitmap of the gradient circle with the avatar (initial, emoji or Memoji) composited in. | Their color or avatar changes |
| `ring` | `CAShapeLayer` with the dashed stroke, and an explicit path. | Invite state changes (shown or hidden) |
| `label` | Bitmap of the name, drawn with the same font and color as today. | Their name or invite state changes |

- The bitmaps are rendered with `UIGraphicsImageRenderer` at the screen's scale, cached by
  `(hue, avatar version, size)`, and set as `layer.contents`. The emoji, Memoji and glow are
  drawn once, not every frame.
- **Per frame, set only** `container.position` and `body.transform` (the squash-and-stretch,
  which touches only the circle and avatar, never the name). Wrap the updates in
  `CATransaction.setDisableActions(true)` so Core Animation adds no implicit animations.
- No live shadows, no masks and no `cornerRadius` clipping on moving layers, so nothing forces
  an off-screen render. `glow` and `label` are static contents that are never redrawn per
  frame; they just move with their container.
- **Lifting a held bubble** (scale up, brighter glow) is a `CASpringAnimation` on the container
  scale and the glow's opacity, run by the render server, not per frame by us.
- **Arrivals and departures:** a spring pop-in (scale 0.3 → 1 with opacity), and a quick fade
  and shrink before a layer is removed.

With this, a frame costs roughly a dozen property writes per bubble, well under 0.1 ms for 20
bubbles.

### 2. Frame loop: `CADisplayLink` with frame pacing

- A `CADisplayLink` on the main run loop calls `physics.advance(by: link.targetTimestamp - last)`,
  then writes the layer properties.
- `preferredFrameRateRange`: **120 Hz while a finger is down or bodies move fast**, dropping to
  **30 Hz once everything has calmed down to just the drift**. That needs `CADisableMinimumFrameDurationOnPhone = YES`
  in Info.plist to get 120 Hz on iPhone.
- **Sleep:** when nothing is dragged and total kinetic energy is below a threshold, the display
  link runs at 30 Hz for the drift. It pauses entirely when the view isn't in a window or the
  app is backgrounded, and wakes on touch or when peers change.
- Physics keeps its fixed 120 Hz substeps, so its behavior doesn't depend on frame rate.

### 3. Input: raw touches on the field, not a gesture per bubble

The field view itself handles `touchesBegan/Moved/Ended/Cancelled`, with no per-bubble gesture
recognizers:

- **Hit-testing** goes through physics: the bubble whose center is nearest the touch, within its
  radius plus a few points of slop. It's cheap (a few bubbles), and exact even while bubbles move.
- **Multi-touch comes for free:** track `UITouch → body id`, so two fingers can drag two bubbles
  at once.
- **Flick velocity:** keep each touch's last ~60 ms of samples, using
  `event.coalescedTouches(for:)` for full-rate input and `predictedTouches(for:)` to lower
  latency during the drag. On release, estimate velocity with a least-squares fit over those
  samples, which is steadier than the last-two-points difference.
- **Tap vs. drag:** a touch that moves less than ~6 pt and lasts under ~0.3 s is a tap, and
  calls `onTap(peerID)` (invite). Anything else is a drag. There's no race between two
  recognizers.
- The view sets `isMultipleTouchEnabled = true`. When it's embedded in a scrolling container, it
  claims touches only when they start on a bubble.

### 4. Physics: same model, flatter data

Keep the model, which already behaves well: Verlet integration with position constraints, a
pull toward the center, drift, soft collisions, the extra room for names, and the bounds. Change
the storage:

- **Contiguous arrays** (positions, previous positions, radii, flags, seeds) indexed `0..<n`,
  with an `id → index` map rebuilt only when membership changes. No dictionary copying in the
  step, and no allocation per frame.
- **API** for the new input: `beginDrag(id, touch point)`, `moveDrag(id, point)`,
  `endDrag(id, velocity)`, `body(at point) -> id?`, and `isCalm`, for pausing the display link.
- O(n²) collisions stay: for up to ~30 bubbles that's under 500 pair checks per substep, which
  is trivial. Spatial hashing isn't worth the complexity.
- The existing `BubblePhysicsTests` carry over, plus tests for hit-testing, multi-drag,
  velocity estimation and the calm detector.

### 5. SwiftUI bridge

`BubbleField: UIViewRepresentable`:

- `updateUIView` passes an array of `BubbleModel(id, name, hue, avatar, invited)`. The view
  diffs it by id and touches only the layers that changed. Nothing is updated per frame from
  SwiftUI, so SwiftUI does no work while bubbles move.
- Callback `onTap: (UInt64) -> Void` calls `model.invite`.
- Avatar images come from `AppModel` as today; the view turns them into bitmaps once.
- The compact row inside an active bubble can use the same view with physics turned off, or
  keep its simple SwiftUI layout. Those bubbles don't move, so SwiftUI is fine there.

### 6. Accessibility

Layers are invisible to VoiceOver, so the view provides one `UIAccessibilityElement` per bubble:

- **Label** is the person's name. **Hint** is "Double-tap to invite", or "Invited".
- Frames are computed from the physics when VoiceOver asks (override `accessibilityFrame`), so
  they follow the bubbles.
- VoiceOver users just see a list of people to invite. They don't need the physics.
- Respect **Reduce Motion**: when it's on, turn off drift and squash-and-stretch. Bubbles can
  still be dragged, but they settle with more damping.

## Alternatives considered

| Option | Verdict |
|---|---|
| **SwiftUI `Canvas` + `TimelineView`** | One draw pass instead of many views, so much faster than now. But it re-draws every bubble (glow, gradient, image) on the CPU every frame, and gestures still need a single overlay with manual hit-testing. That's a good quick win, but not the best result. |
| **SpriteKit** (`SKView`, `SKPhysicsWorld`) | Built-in physics and GPU sprites. But rigid-body physics feels bouncy and "gamey" rather than soft. It's harder to match the current look (glow, emoji, text) and to host cleanly in SwiftUI, and it costs more battery at idle. It's the fallback if hand-rolled physics ever becomes a burden. |
| **Metal** | Maximum control and speed, but far more code for a dozen bubbles. Not justified. |
| **Core Animation layers** (this plan) | GPU compositing of pre-rendered bitmaps. Almost no per-frame CPU, native text and image rendering, and it hosts cleanly in SwiftUI. **Chosen.** |

## Steps

0. **Confirm the diagnosis.** Profile the current branch in a Release build on a phone with the
   Instruments *Animation Hitches* and *Time Profiler* templates, and turn on Core Animation's
   "Color Offscreen-Rendered" debug option. We expect shadow rendering and SwiftUI rebuilding
   the view tree to dominate. If something else does (for example repeated avatar decoding),
   the plan changes. About 15 minutes.
1. **Physics storage refactor:** contiguous arrays, the new drag, hit-test and calm API, and
   tests.
2. **`BubbleLayer` and the bitmap cache:** render the glow, body and label images, and check
   them against the current SwiftUI look side by side in screenshots.
3. **`BubbleFieldView`:** the display link, per-frame layer writes, adding and removing bubbles
   with pop-in and fade-out, and the lift animation.
4. **Touch handling:** hit-testing, multi-touch drags, the velocity fit, and taps that invite.
5. **SwiftUI bridge:** `BubbleField` replaces the physics `NearbyField` on the main page.
6. **Accessibility and Reduce Motion.**
7. **Frame pacing and sleep:** 120 → 30 Hz, pausing when hidden or in the background, and the
   Info.plist key.
8. **Verify** (below), then merge to `main`.

## Verification

- **Target:** a steady 120 fps on a ProMotion iPhone, and 60 fps elsewhere, while dragging
  through 12 bubbles. Zero hitches in Animation Hitches. Main-thread time under 1 ms per frame.
  No off-screen rendering in the moving layers.
- **Idle:** once bubbles are calm, the display link is at 30 Hz, and it's paused with the app
  backgrounded. CPU under 2% in the Energy gauge.
- **Feel on device:** grab lag should be imperceptible (predicted touches). Flicks should go
  where they're thrown. Two-finger drags should work. A tap should always invite and never
  nudge a bubble.
- **Unit tests:** the physics tests (existing and new), all passing.
- **Look:** screenshots of the new view next to the SwiftUI version: the same colors, glow,
  avatars and names, and "Invited…" under the ring.
