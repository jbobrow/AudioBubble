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
The introduction pages use `-introPage <0-3>` on a fresh install.

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
- **Review notes** (suggested):
  > Audio Bubble connects nearby iPhones directly (Bonjour over peer-to-peer Wi-Fi) so people in
  > the same place can talk through their headphones. Testing needs two iPhones with Wi-Fi on
  > and headphones connected. Open the app on both, tap the other person's bubble, then tap
  > Join. No account or sign-in is needed.
- **Support URL** and **Privacy Policy URL:** required; not in this folder yet.
