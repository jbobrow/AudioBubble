import SwiftUI

/// How Audio Bubble works, a page at a time: what it's for, that everyone needs it on their own
/// iPhone, inviting, headphones, and no network. Shown on first launch, and again from Settings.
struct WelcomeView: View {
    /// Seen again from Settings, so it ends with Done and can be closed at any point.
    var isReplay = false
    let onFinish: () -> Void

    @State private var page: Page = DebugLaunch.value(after: "-introPage")
        .flatMap { Int($0) }.flatMap(Page.init(rawValue:)) ?? .welcome

    enum Page: Int, CaseIterable {
        case welcome, together, invite, headphones, noNetwork
    }

    private var isLast: Bool { page == Page.allCases.last }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            TabView(selection: $page) {
                ForEach(Page.allCases, id: \.self) { page in
                    content(for: page).tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            controls
        }
        .foregroundStyle(.white)
    }

    // MARK: - Pages

    @ViewBuilder
    private func content(for page: Page) -> some View {
        switch page {
        case .welcome:
            WelcomePage()
        case .together:
            WalkthroughPage(title: "Everyone brings an iPhone",
                            message: "Audio Bubble connects iPhones in the same place. Each person opens it on their own iPhone, with their own headphones, and you find each other.") {
                TogetherArt()
            }
        case .invite:
            WalkthroughPage(title: "Tap to invite",
                            message: "People nearby with Audio Bubble open float on your screen. Tap someone to invite them. Once they join, you're in a bubble together.") {
                InviteArt()
            }
        case .headphones:
            WalkthroughPage(title: "Put in your headphones",
                            message: "You'll hear everyone in your bubble, but never yourself. AirPods work great.") {
                HeadphonesArt()
            }
        case .noNetwork:
            WalkthroughPage(title: "No network needed",
                            message: "Keep Wi-Fi on, but you don't need to join a network. Your bubble is actually faster without one.") {
                NoNetworkArt()
            }
        }
    }

    // MARK: - Controls

    private var topBar: some View {
        HStack {
            Spacer()
            if isReplay {
                Button("Close", action: onFinish)
                    .modifier(TopBarButton())
            } else if !isLast {
                Button("Skip") { withAnimation(.snappy) { page = Page.allCases.last! } }
                    .modifier(TopBarButton())
            }
        }
        .frame(height: 44)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            dots.padding(.bottom, 20)

            Button(action: advance) {
                Text(isLast ? (isReplay ? "Done" : "Get started") : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 40)

            // Who to find, once the walkthrough is done
            Text(isLast && !isReplay ? "Ask someone with you to open Audio Bubble too. They'll appear on your screen." : " ")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .padding(.horizontal, 36)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .opacity(isLast && !isReplay ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isLast)
                .accessibilityHidden(!(isLast && !isReplay))
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(Page.allCases, id: \.self) { dot in
                Capsule()
                    .fill(.white.opacity(dot == page ? 0.9 : 0.25))
                    .frame(width: dot == page ? 20 : 7, height: 7)
            }
        }
        .animation(.snappy, value: page)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
    }

    private func advance() {
        if isLast {
            onFinish()
        } else if let next = Page(rawValue: page.rawValue + 1) {
            withAnimation(.snappy) { page = next }
        }
    }
}

private struct TopBarButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .contentShape(.rect)
    }
}

// MARK: - Page layouts

/// The app icon, "Audio Bubble", and what it's for.
private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: Color.bubble(0.58).opacity(0.35), radius: 24, y: 6)
                .accessibilityHidden(true)
            Text("Audio Bubble")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .padding(.top, 32)
                .accessibilityAddTraits(.isHeader)
            Text("Hear the people you're with, clearly and instantly, even in loud places.".withoutWidows)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.horizontal, 36)
            Spacer(minLength: 20)
        }
    }
}

/// Illustration on top, then a title and a short explanation.
private struct WalkthroughPage<Art: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            art
                .frame(height: 220)
                .accessibilityHidden(true)
            Text(title.withoutWidows)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(message.withoutWidows)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            Spacer()
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Art

/// A bubble that drifts a little around where it's placed.
private struct Floating: View {
    let initial: String
    let hue: Double
    let size: CGFloat
    var x: CGFloat = 0
    var y: CGFloat = 0
    let t: Double
    var seed: Double = 0

    var body: some View {
        BubbleAvatar(name: initial, hue: hue, size: size)
            .offset(x: x + 6 * sin(t * 0.8 + seed), y: y + 8 * cos(t * 0.6 + seed * 1.3))
    }
}

/// Two iPhones side by side, each with its own person, and voices passing between them.
private struct TogetherArt: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 0) {
                phone(initial: "M", hue: 0.92, t: t, seed: 0)
                link(t: t)
                phone(initial: "S", hue: 0.58, t: t, seed: 2)
            }
        }
    }

    private func phone(initial: String, hue: Double, t: Double, seed: Double) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.white.opacity(0.05))
            .strokeBorder(.white.opacity(0.6), lineWidth: 2)
            .frame(width: 100, height: 200)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.6))
                    .frame(width: 30, height: 8)
                    .padding(.top, 10)
            }
            .overlay {
                Floating(initial: initial, hue: hue, size: 56, t: t, seed: seed)
            }
    }

    /// Dots traveling both ways between the phones.
    private func link(t: Double) -> some View {
        Canvas { context, size in
            let count = 5
            for i in 0..<count {
                let phase = (t * 0.5 + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                let x = size.width * phase
                let fade = sin(phase * .pi)
                let dot = CGRect(x: x - 3, y: size.height / 2 - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.85 * fade)))
                let back = CGRect(x: size.width - x - 3, y: size.height / 2 + 9, width: 6, height: 6)
                context.fill(Path(ellipseIn: back), with: .color(.white.opacity(0.45 * fade)))
            }
        }
        .frame(width: 80, height: 40)
    }
}

private struct InviteArt: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Floating(initial: "M", hue: 0.92, size: 64, x: -80, y: -40, t: t, seed: 1).opacity(0.7)
                Floating(initial: "A", hue: 0.12, size: 54, x: 86, y: 50, t: t, seed: 3).opacity(0.7)
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
        }
    }
}

private struct HeadphonesArt: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
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
        }
    }
}

private struct NoNetworkArt: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Image(systemName: "wifi")
                    .font(.system(size: 70, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(y: -10)
                Floating(initial: "M", hue: 0.92, size: 50, x: -80, y: 60, t: t, seed: 1)
                Floating(initial: "S", hue: 0.58, size: 50, x: 80, y: 60, t: t, seed: 3)
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(width: 100, height: 3)
                    .offset(y: 60)
            }
        }
    }
}
