import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.bubbleID != nil {
                BubbleView()
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                if !model.nearby.isEmpty {
                    Text("Nearby — tap to invite")
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
    }

    private var header: some View {
        HStack {
            if let identity = model.identity {
                Circle().fill(Color.bubble(identity.hue)).frame(width: 12, height: 12)
                Text(identity.name).font(.headline)
            }
            Spacer()
            Button(action: model.showMicModes) {
                Label(model.micModeName, systemImage: "waveform.and.mic")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityHint("Opens Mic Modes. Choose Voice Isolation to block background noise.")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

/// Nearby people, floating as soft colored bubbles.
struct NearbyField: View {
    @Environment(AppModel.self) private var model
    let peers: [Peer]
    let compact: Bool

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(Array(peers.enumerated()), id: \.element.id) { index, peer in
                        let position = layout(index: index, count: peers.count, in: geometry.size)
                        let seed = Double(peer.id % 1_000) / 1_000 * 2 * .pi
                        PeerBubble(peer: peer, size: compact ? 70 : 104,
                                   invited: model.outgoingInvites[peer.id] != nil)
                            .position(x: position.x + 8 * sin(t * 0.6 + seed),
                                      y: position.y + 10 * cos(t * 0.45 + seed * 1.3))
                            .onTapGesture { model.invite(peer.id) }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }

    /// A loose spiral that keeps bubbles apart and stable as people come and go.
    private func layout(index: Int, count: Int, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if compact {
            let spacing = min(96, size.width / CGFloat(max(count, 1)))
            let x = center.x + (CGFloat(index) - CGFloat(count - 1) / 2) * spacing
            return CGPoint(x: x, y: center.y)
        }
        guard count > 1 else { return center }
        let angle = Double(index) * 2.4   // golden angle, roughly
        let radius = 70 + 34 * sqrt(Double(index))
        let scale = min(size.width, size.height) / 360
        return CGPoint(x: center.x + CGFloat(cos(angle) * radius) * scale,
                       y: center.y + CGFloat(sin(angle) * radius) * scale)
    }
}

struct PeerBubble: View {
    let peer: Peer
    let size: CGFloat
    var invited = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.bubble(peer.hue).gradient)
                    .shadow(color: Color.bubble(peer.hue).opacity(0.5), radius: 14)
                Text(peer.name.prefix(1).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
                if invited {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(-7)
                }
            }
            .frame(width: size, height: size)
            Text(invited ? "Invited…" : peer.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(peer.name)
        .accessibilityHint(invited ? "Invited" : "Double-tap to invite")
    }
}

struct EmptyNearbyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let waited = timeline.date.timeIntervalSince(model.searchStarted)
            VStack(spacing: 14) {
                PulsingDot()
                Text("Looking for people nearby…")
                    .font(.headline)
                if waited > 5 {
                    Text("Keep Wi-Fi on. No network needed.")
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
