import SwiftUI

/// The bubble you're in: everyone gathered in one large circle, glowing with their voice.
struct BubbleView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(DebugSettings.key) private var debugMode = false

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height) - 24
                TimelineView(.animation) { _ in
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.05))
                            .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
                            .frame(width: diameter, height: diameter)
                        ForEach(Array(participants.enumerated()), id: \.element.id) { index, participant in
                            MemberGlow(participant: participant, size: memberSize(diameter))
                                .position(position(index: index, count: participants.count,
                                                   diameter: diameter, in: geometry.size))
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            controls
        }
        .padding(.top, 8)
    }

    struct Participant: Identifiable {
        let id: UInt64
        let name: String
        let initial: String
        let hue: Double
        let level: Float
        let latency: Double?
        let isMe: Bool
        /// "direct", "via network" — how their audio reaches you.
        var link: String?
        var onWiFi = false
        var echoSuppressed = false
    }

    private var participants: [Participant] {
        var list: [Participant] = []
        if let identity = model.identity {
            list.append(Participant(id: model.localID, name: "You", initial: String(identity.name.prefix(1)), hue: identity.hue,
                                    level: model.myLevel, latency: nil, isMe: true))
        }
        for member in model.members {
            list.append(Participant(id: member.id, name: member.name, initial: String(member.name.prefix(1)), hue: member.hue,
                                    level: model.level(of: member.id),
                                    latency: debugMode ? model.latencyMilliseconds(from: member.id) : nil, isMe: false,
                                    link: member.isDirect.map { $0 ? "direct" : "via network" },
                                    onWiFi: member.onWiFi,
                                    echoSuppressed: model.isSuppressingEcho(from: member.id)))
        }
        return list
    }

    private func memberSize(_ diameter: CGFloat) -> CGFloat {
        let count = CGFloat(max(participants.count, 1))
        return min(110, diameter / (count > 4 ? 3.6 : 2.8))
    }

    private func position(index: Int, count: Int, diameter: CGFloat, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard count > 1 else { return center }
        let radius = diameter / 2 - memberSize(diameter) * 0.75
        let angle = -Double.pi / 2 + Double(index) / Double(count) * 2 * .pi
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if model.shouldAdviseLeavingWiFi {
                WiFiAdviceCard()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.members.isEmpty {
                Text(model.outgoingInvites.isEmpty ? "Everyone else has left" : "Waiting for them to join…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if debugMode { LatencyReadout() }
            }
            HStack(spacing: 16) {
                Button(action: model.toggleMute) {
                    Label(model.isMuted ? "Unmute" : "Mute",
                          systemImage: model.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .tint(model.isMuted ? .red : .white)

                Button(role: .destructive, action: model.leaveBubble) {
                    Label("Leave", systemImage: "xmark")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }
}

struct MemberGlow: View {
    let participant: BubbleView.Participant
    let size: CGFloat

    var body: some View {
        let level = CGFloat(min(1, sqrt(participant.level) * 1.6))
        let color = Color.bubble(participant.hue)
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(1 + level * 0.45)
                    .blur(radius: 10 + level * 10)
                Circle()
                    .fill(color.gradient)
                    .shadow(color: color.opacity(0.4 + level * 0.6), radius: 6 + level * 22)
                Text(participant.initial.uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
            }
            .frame(width: size, height: size)
            Text(participant.name)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
            if let latency = participant.latency {
                HStack(spacing: 4) {
                    Text("\(Int(latency.rounded())) ms")
                    if let link = participant.link { Text("· \(link)") }
                    if participant.onWiFi {
                        Image(systemName: "wifi")
                            .accessibilityLabel("on a Wi-Fi network")
                    }
                    if participant.echoSuppressed {
                        // Their mic hears you; your voice is being removed from their stream.
                        Image(systemName: "person.wave.2")
                            .accessibilityLabel("removing your voice from their audio")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(participant.isMe ? "You" : participant.name)
    }
}

/// Estimated mouth-to-ear latency, averaged over the bubble. Tap for the breakdown.
struct LatencyReadout: View {
    @Environment(AppModel.self) private var model
    @State private var showsDetails = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let parts = model.members.compactMap { model.latencyBreakdown(from: $0.id) }
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                    if parts.isEmpty {
                        Text("Measuring latency…")
                    } else {
                        Text("~\(Self.ms(parts.map(\.total))) ms mouth to ear")
                        Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                if showsDetails, !parts.isEmpty {
                    Text("network \(Self.ms(parts.map(\.network))) · buffer \(Self.ms(parts.map(\.buffer))) · processing \(Self.ms(parts.map(\.processing))) · audio hardware \(Self.ms(parts.map(\.hardware))) ms")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }
            .monospacedDigit()
            .font(.footnote)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { showsDetails.toggle() } }
        }
    }

    private static func ms(_ values: [Double]) -> Int {
        Int((values.reduce(0, +) / Double(max(values.count, 1))).rounded())
    }
}

/// iOS won't let apps leave a Wi-Fi network, so explain the one-tap way to do it.
struct WiFiAdviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title3)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Leave Wi-Fi for clearer, faster audio")
                    .font(.subheadline.weight(.semibold))
                Text("Open Control Center and tap Wi-Fi. You'll leave the network, but Wi-Fi stays on for nearby devices, which is all your bubble needs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                withAnimation { model.wifiAdviceDismissed = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Not now")
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }
}
