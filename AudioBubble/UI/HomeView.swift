import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = DebugLaunch.has("-showSettings")

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.headphonesConnected {
                HeadphonesNotice(paused: model.isPausedForHeadphones)
                    .padding(.horizontal)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if model.bubbleID != nil {
                BubbleView()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                if !model.nearby.isEmpty {
                    Text("Nearby — tap to invite".withoutWidows)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    NearbyField(peers: model.nearby, compact: true)
                        .frame(height: 130)
                }
            } else {
                NearbyField(peers: model.nearby, compact: false)
                    .overlay {
                        if model.nearby.isEmpty { EmptyNearbyView() }
                    }
            }
        }
        .foregroundStyle(.white)
        .animation(.spring(duration: 0.6), value: model.bubbleID)
        .animation(.spring(duration: 0.6), value: model.nearby.map(\.id))
        .animation(.spring(duration: 0.5), value: model.headphonesConnected)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
                .presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack {
            if let identity = model.identity {
                Button { showsSettings = true } label: {
                    HStack(spacing: 8) {
                        if model.myAvatar == .initial {
                            Circle().fill(Color.bubble(identity.hue)).frame(width: 12, height: 12)
                        } else {
                            BubbleAvatar(name: identity.name, hue: identity.hue, size: 26, content: model.myAvatar)
                        }
                        Text(identity.name).font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(identity.name), settings")
                .accessibilityHint("Change your name and color")
            }
            Spacer()
            // Mic modes exist only while the mic is in use, i.e. in a bubble.
            if model.bubbleID != nil {
                Button(action: showMicModes) {
                    Label(model.micModeName, systemImage: "waveform.and.mic")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityHint("Opens Mic Modes. Choose Voice Isolation to block background noise.")
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(minHeight: 44)
    }

    private func showMicModes() {
        if model.headphonesConnected {
            model.showMicModes()
        } else {
            model.showsHeadphonesRequired = true
        }
    }
}

/// Nearby people, floating as soft colored bubbles. On the main page they're a physics toy drawn
/// with Core Animation (`BubbleFieldView`): drag or flick them and they shove each other aside.
/// Tap one to invite them.
struct NearbyField: View {
    @Environment(AppModel.self) private var model
    let peers: [Peer]
    let compact: Bool

    var body: some View {
        if compact {
            GeometryReader { geometry in row(in: geometry.size) }
        } else {
            BubbleField(bubbles: peers.map {
                BubbleModel(id: $0.id, name: $0.name, hue: $0.hue, avatar: model.avatar(of: $0),
                            invited: model.outgoingInvites[$0.id] != nil)
            }, onTap: { model.invite($0) })
        }
    }

    /// Inside a bubble: a simple row of smaller bubbles.
    private func row(in size: CGSize) -> some View {
        let spacing = min(96, size.width / CGFloat(max(peers.count, 1)))
        return ZStack {
            ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                PeerBubble(peer: peer, avatar: model.avatar(of: peer), size: 70,
                           invited: model.outgoingInvites[peer.id] != nil)
                    .position(x: size.width / 2 + (CGFloat(index) - CGFloat(peers.count - 1) / 2) * spacing,
                              y: size.height / 2 - 10)
                    .onTapGesture { model.invite(peer.id) }
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct PeerBubble: View {
    let peer: Peer
    var avatar: AvatarContent = .initial
    let size: CGFloat
    var invited = false

    /// How far the dashed "invited" ring sits outside the bubble.
    private static let ringInset: CGFloat = 7

    var body: some View {
        // The view's frame is the circle, so its position is the bubble's center; the name hangs
        // below (leaving room for the ring even when it isn't shown, so it never jumps).
        ZStack {
            Circle()
                .fill(Color.bubble(peer.hue).gradient)
                .shadow(color: Color.bubble(peer.hue).opacity(0.5), radius: 14)
            AvatarFace(name: peer.name, content: avatar, size: size)
            if invited {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(-Self.ringInset)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .overlay(alignment: .bottom) {
            Text(invited ? "Invited…" : peer.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .fixedSize()
                .alignmentGuide(.bottom) { $0[.top] - (Self.ringInset + 7) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(peer.name)
        .accessibilityHint(invited ? "Invited" : "Double-tap to invite")
        .accessibilityAddTraits(.isButton)
    }
}

struct EmptyNearbyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let waited = timeline.date.timeIntervalSince(model.searchStarted)
            VStack(spacing: 14) {
                PulsingDot()
                Text("Looking for people nearby…".withoutWidows)
                    .font(.headline)
                if waited > 5 {
                    Text("Keep Wi-Fi on. No network needed.".withoutWidows)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: waited > 5)
        }
    }
}

struct PulsingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.white.opacity(0.25))
            .frame(width: 40, height: 40)
            .scaleEffect(pulse ? 1.4 : 0.8)
            .opacity(pulse ? 0.2 : 0.8)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
