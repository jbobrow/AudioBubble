import SwiftUI

/// A short, swipeable introduction: what a bubble is, how to invite, headphones, no network needed.
struct IntroPages: View {
    var finishTitle = "Get started"
    let onFinish: () -> Void
    @State private var page = DebugLaunch.value(after: "-introPage").flatMap { Int($0) } ?? 0

    private struct Page {
        let title: String
        let text: String
        let art: Art
    }

    private enum Art { case bubbles, invite, headphones, noNetwork }

    private let pages = [
        Page(title: "Your bubble",
             text: "Hear the people you're with, clearly and instantly, even in loud places.",
             art: .bubbles),
        Page(title: "Tap to invite",
             text: "People nearby with Audio Bubble float on your screen. Tap someone to invite them. Once they join, you're in a bubble together.",
             art: .invite),
        Page(title: "Put in your headphones",
             text: "You'll hear everyone in your bubble, but never yourself. AirPods work great.",
             art: .headphones),
        Page(title: "No network needed",
             text: "Keep Wi-Fi on, but you don't need to join a network. Your bubble is actually faster without one.",
             art: .noNetwork),
    ]

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 28) {
                        Spacer()
                        IntroArt(art: pages[index].art)
                            .frame(height: 220)
                        Text(pages[index].title)
                            .font(.title.weight(.semibold))
                        Text(pages[index].text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 36)
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index == page ? 0.9 : 0.25))
                        .frame(width: index == page ? 20 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
            .accessibilityHidden(true)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : finishTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .foregroundStyle(.white)
    }

    private struct IntroArt: View {
        let art: Art

        var body: some View {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                switch art {
                case .bubbles:
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.05))
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            .frame(width: 210, height: 210)
                        floating("M", hue: 0.92, size: 70, x: -40, y: -32, t: t, seed: 0)
                        floating("S", hue: 0.58, size: 62, x: 44, y: -18, t: t, seed: 2)
                        floating("A", hue: 0.12, size: 56, x: 0, y: 50, t: t, seed: 4)
                    }
                case .invite:
                    ZStack {
                        floating("M", hue: 0.92, size: 64, x: -80, y: -40, t: t, seed: 1).opacity(0.7)
                        floating("A", hue: 0.12, size: 54, x: 86, y: 50, t: t, seed: 3).opacity(0.7)
                        ZStack {
                            BubbleAvatar(name: "Sam", hue: 0.58, size: 96)
                            Circle()
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(width: 112, height: 112)
                                .rotationEffect(.degrees(t * 20))
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.white)
                                .offset(x: 38, y: 50)
                                .scaleEffect(1 + 0.06 * sin(t * 3))
                        }
                    }
                case .headphones:
                    ZStack {
                        Circle()
                            .fill(Color.bubble(0.72).opacity(0.25))
                            .frame(width: 160, height: 160)
                            .scaleEffect(1 + 0.08 * sin(t * 2))
                            .blur(radius: 18)
                        Image(systemName: "airpods")
                            .font(.system(size: 88, weight: .light))
                            .foregroundStyle(.white)
                    }
                case .noNetwork:
                    ZStack {
                        Image(systemName: "wifi")
                            .font(.system(size: 70, weight: .light))
                            .foregroundStyle(.white.opacity(0.9))
                            .offset(y: -10)
                        floating("M", hue: 0.92, size: 50, x: -80, y: 60, t: t, seed: 1)
                        floating("S", hue: 0.58, size: 50, x: 80, y: 60, t: t, seed: 3)
                        Capsule()
                            .fill(.white.opacity(0.35))
                            .frame(width: 100, height: 3)
                            .offset(y: 60)
                    }
                }
            }
            .accessibilityHidden(true)
        }

        private func floating(_ initial: String, hue: Double, size: CGFloat, x: CGFloat, y: CGFloat,
                              t: Double, seed: Double) -> some View {
            BubbleAvatar(name: initial, hue: hue, size: size)
                .offset(x: x + 6 * sin(t * 0.8 + seed), y: y + 8 * cos(t * 0.6 + seed * 1.3))
        }
    }
}
