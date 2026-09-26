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

/// Nearby people, floating as soft colored bubbles. On the main page they're a little physics
/// toy (`BubblePhysics`): they cluster and drift, and you can drag or flick one and it shoves the
/// others aside. Tap one to invite them.
struct NearbyField: View {
    @Environment(AppModel.self) private var model
    let peers: [Peer]
    let compact: Bool
    @State private var physics = BubblePhysics()
    @State private var dragged: UInt64?

    var body: some View {
        GeometryReader { geometry in
            if compact {
                row(in: geometry.size)
            } else {
                field(in: geometry.size)
            }
        }
    }

    private static let fieldSize: CGFloat = 104

    private func field(in size: CGSize) -> some View {
        TimelineView(.animation) { timeline in
            let _ = physics.update(size: size, items: peers.map { (id: $0.id, radius: Double(Self.fieldSize) / 2) },
                                   date: timeline.date)
            ZStack {
                ForEach(peers) { peer in
                    if let body = physics.bodies[peer.id] {
                        let speed = (body.velocity.x * body.velocity.x + body.velocity.y * body.velocity.y).squareRoot()
                        PeerBubble(peer: peer, avatar: model.avatar(of: peer), size: Self.fieldSize,
                                   invited: model.outgoingInvites[peer.id] != nil,
                                   stretch: CGFloat(min(speed / 2_200, 0.14)),
                                   stretchAngle: .radians(atan2(body.velocity.y, body.velocity.x)),
                                   lifted: dragged == peer.id)
                            .position(x: body.position.x, y: body.position.y)
                            .onTapGesture { model.invite(peer.id) }
                            .gesture(
                                DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
                                    .onChanged { value in
                                        dragged = peer.id
                                        physics.drag(peer.id, to: .init(value.location.x, value.location.y))
                                    }
                                    .onEnded { value in
                                        dragged = nil
                                        physics.endDrag(peer.id, velocity: .init(value.velocity.width, value.velocity.height))
                                    }
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .coordinateSpace(.named(Self.space))
        .animation(.spring(duration: 0.3), value: dragged)
    }

    private static let space = "nearby-field"

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
    /// Squash-and-stretch: 0 is round; the bubble lengthens along `stretchAngle` as it moves.
    var stretch: CGFloat = 0
    var stretchAngle: Angle = .zero
    /// Held by a finger: a touch bigger, with a stronger glow.
    var lifted = false

    /// How far the dashed "invited" ring sits outside the bubble.
    private static let ringInset: CGFloat = 7

    var body: some View {
        // The view's frame is the circle, so its position is the bubble's center; the name hangs
        // below (leaving room for the ring even when it isn't shown, so it never jumps).
        ZStack {
            Circle()
                .fill(Color.bubble(peer.hue).gradient)
                .shadow(color: Color.bubble(peer.hue).opacity(lifted ? 0.8 : 0.5), radius: lifted ? 24 : 14)
            AvatarFace(name: peer.name, content: avatar, size: size)
            if invited {
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(-Self.ringInset)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(-stretchAngle)
        .scaleEffect(x: 1 + stretch, y: 1 - stretch * 0.8)
        .rotationEffect(stretchAngle)
        .scaleEffect(lifted ? 1.08 : 1)
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
