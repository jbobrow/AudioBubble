# App Store listing

Everything App Store Connect asks for on the iPhone version page. Character counts are checked
against App Store Connect's limits.

## Screenshots

Apple's current iPhone size is **6.9"**, and it's the only iPhone size you must upload: App Store
Connect scales it down for 6.5", 6.3", 6.1" and smaller. Every file here is **1320 × 2868** px
portrait (iPhone 17 Pro Max / 18 Pro Max), PNG, with no alpha channel. Captured on the
iPhone 18 Pro Max simulator.

- `screenshots/iPhone 6.9 captioned/`: the recommended set of 4, each with a headline and a framed screenshot.
  1. **Hear each other, even in loud places**: a bubble of four, with Maya talking
  2. **Tap someone nearby to invite them**: the floating bubbles, with Sam invited
  3. **One tap to join**: Maya's invite
  4. **No network? No problem.**: the introduction's last page
- `screenshots/iPhone 6.9 plain/`: the same screens without captions, plus the first
  introduction page and Settings, in case you'd rather upload plain screens.

The people in them are made up. To retake them, build Debug and launch with
`-screenshotDemo nearby|bubble|invite -assumeHeadphones` (see `AppModel.setUpDemo`).
The welcome pages use `-introPage <0-4>` on a fresh install. The plain `4-intro3` and
`5-intro0` shots predate the current welcome (which now opens on the app icon and adds
"Everyone brings an iPhone"), so retake them before uploading those.

## App Preview (video)

`app preview/AudioBubble-preview-886x1920.mp4`: 25 seconds, portrait, captioned and framed to
match the screenshots. Someone opens the app. People arrive one by one, a finger drags and flicks
Maya, then taps Sam to invite him. Sam joins, then Maya and Ava, and each bubble glows in turn as
that person talks.

The middle section drags and flicks Maya, which needs the Core Animation bubble field on
`claude/bubble-physics`. Reshoot it before shipping a build without that field.

It meets Apple's current App Preview spec: 886 × 1920 portrait, 15–30 s, H.264 High Profile
Level 4.0 at 30 fps and ~10.8 Mbps (target 10–12), a silent stereo AAC track at 48 kHz, and an
.mp4 file of 34 MB (500 MB max).

**Where it goes:** Apple lists 6.9" previews as "support available later this year". Until then,
upload it in the **6.5"** slot (886 × 1920 is the accepted size for 6.9", 6.5", 6.3" and 6.1"),
and App Store Connect uses it for the larger phones as well. **Poster frame:** the default is 5 s
(people still arriving). Around 20 s (everyone in the bubble) makes a stronger still.

To remake it: build Debug, record with `xcrun simctl io <device> recordVideo --codec=h264`, and
launch with `-screenshotDemo video -assumeHeadphones`. The story starts 3 s after launch.

**iPad:** none needed. The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

**App icon:** nothing to upload. App Store Connect takes it from the build
(`AudioBubble-icon.icon`).

## Name (12 / 30)

```
Audio Bubble
```

## Subtitle (27 / 30)

```
Hear friends in loud places
```

## Promotional text (145 / 170)

You can change this at any time without a new build.

```
Hear the people you're with, clearly and instantly, even in loud places. Phone to phone, with no Wi-Fi network needed. Just headphones and a tap.
```

## Keywords (97 / 100)

Comma-separated with no spaces after the commas. They leave out words already in the name and
subtitle, since those are indexed anyway.

```
walkie talkie,intercom,headphones,airpods,concert,noisy,bar,group,voice,chat,offline,nearby,party
```

## Description (1952 / 4000)

In `description.txt`, ready to paste.

## Other fields

- **Primary category:** Social Networking. **Secondary:** Utilities.
- **Age rating:** 4+. The questionnaire's "unrestricted web access" and "user-generated
  content" answers can stay No: audio goes only to people you've invited, in person.
- **App Privacy:** Data Not Collected. Names, colors, avatars and audio travel directly between
  nearby phones and never reach you or a server.
- **Review notes** (paste into App Review Information → Notes). Version 1.0 (9) was rejected
  under 2.1(a) because the reviewer, on one iPhone, saw "Looking for people nearby…" and took it
  for endless loading. Lead with the two-iPhone requirement:
  > Audio Bubble needs TWO OR MORE iPhones in the same room to do anything. It connects nearby
  > iPhones directly (Bonjour over peer-to-peer Wi-Fi) so people in the same place can hear each
  > other through their headphones. It has no server, account or sign-in. On a single iPhone the
  > app correctly waits at "Looking for people nearby…" because there is no one to find. That
  > screen now explains this, and the welcome pages say so too.
  >
  > To test:
  > 1. Install on two iPhones. Turn Wi-Fi on for both (joining a network isn't required).
  > 2. Open Audio Bubble on both, go through the welcome, and enter a name.
  > 3. Allow Microphone and Local Network access when asked.
  > 4. Each iPhone shows the other's colored bubble within a few seconds. Tap it to invite, then
  >    tap Join on the other iPhone.
  > 5. Connect headphones (AirPods or wired) to both to talk. Each person hears the others but
  >    not themselves.
  >
  > A demo video of two iPhones in use: <link>
  >
  > BACKGROUND AUDIO (UIBackgroundModes: audio): Audio Bubble is a live voice intercom. While
  > you're in a bubble it records your microphone and plays the other people's voices in your
  > headphones continuously, and it must keep doing so with the iPhone locked or in a pocket, or
  > while you use another app (it's made for concerts, bars and other loud places). Without the
  > audio background mode iOS suspends the app and the conversation cuts off within seconds.
  > Audio runs only while you're in a bubble with at least one other person and headphones are
  > connected; outside a bubble the app releases the microphone and audio session, and it never
  > plays audio in the background otherwise. To see it: start a bubble as above, then press the
  > Side button or swipe to the Home Screen on one iPhone and keep talking on the other. You
  > still hear each other, and the orange microphone indicator stays on.
  >
  > A screen recording of background audio on a physical device: <link>

  Version 1.0 (10) was then rejected under **2.5.4** ("we are unable to play any audible content
  when the app is running in the background"): the reviewer couldn't get into a bubble, so the
  app never had audio to keep playing. The audio mode stays, since the app's core feature
  needs it. Reply in App Store Connect with the text below and the screen recording, and keep
  the paragraph above in the notes for future submissions.

  **The screen recording.** Two iPhones, each with headphones, in a bubble. Record on iPhone A
  (Control Center → long-press Screen Recording → Microphone **On**, so the recording has
  sound). Show the bubble, then go to the Home Screen and open another app (Settings, say)
  while the person on iPhone B keeps talking, then lock iPhone A and unlock it again. The orange
  mic indicator stays on throughout. If iPhone A's recording doesn't capture the call audio,
  film both phones with a third camera instead so the voice is audible.

  **Reply to App Review:**
  > Thank you for the review. Audio Bubble does have a feature that requires persistent
  > background audio, and a screen recording on a physical device is attached.
  >
  > Audio Bubble is a live voice intercom for people in the same place. Each person uses their
  > own iPhone and headphones; nearby iPhones connect directly, and while you're in a "bubble"
  > the app continuously records your microphone and plays the other members' voices in your
  > headphones. People use it at concerts, bars and other loud places, usually with the iPhone
  > locked in a pocket, so the conversation has to keep going in the background, just like a
  > phone call. Without the audio background mode iOS suspends the app and the audio stops
  > within seconds.
  >
  > Audio only runs while you're in a bubble with at least one other person and with headphones
  > connected. Outside a bubble the app deactivates its audio session and releases the
  > microphone, so it never keeps itself running in the background.
  >
  > To test, it needs two iPhones (one iPhone has no one to talk to): install on both, go
  > through the welcome, allow Microphone and Local Network access, and connect headphones to
  > each. Tap the other iPhone's bubble to invite it, then tap Join on the other iPhone. Now go
  > to the Home Screen or lock one iPhone and keep talking on the other: you still hear each
  > other, and the orange microphone indicator stays on.
  >
  > The recording shows exactly this, and we've added the explanation to the App Review notes
  > for future submissions.
- **Support URL:** https://jbobrow.github.io/AudioBubble/support/
- **Privacy Policy URL:** https://jbobrow.github.io/AudioBubble/privacy/
- **Marketing URL:** https://jbobrow.github.io/AudioBubble/

  All three are served by GitHub Pages from `docs/` on `main`.
