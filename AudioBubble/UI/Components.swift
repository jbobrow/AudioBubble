import SwiftUI

/// A person's colored bubble with their initial, emoji or Memoji.
struct BubbleAvatar: View {
    let name: String
    let hue: Double
    var size: CGFloat = 88
    var content: AvatarContent = .initial

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.bubble(hue).gradient)
                .shadow(color: Color.bubble(hue).opacity(0.5), radius: size * 0.14)
            AvatarFace(name: name, content: content, size: size)
        }
        .frame(width: size, height: size)
    }
}

/// What goes on top of the colored circle: an initial, an emoji, or a Memoji clipped to the circle.
struct AvatarFace: View {
    let name: String
    let content: AvatarContent
    let size: CGFloat

    var body: some View {
        switch content {
        case .initial:
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.6))
        case let .emoji(emoji):
            Text(emoji)
                .font(.system(size: size * 0.56))
        case let .image(image):
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.92, height: size * 0.92)
                .offset(y: size * 0.04)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }
}

/// The colors people can pick from.
enum Palette {
    static let hues: [Double] = [0.58, 0.64, 0.72, 0.82, 0.92, 0.99, 0.06, 0.12, 0.30, 0.45]
    static func random() -> Double { hues.randomElement()! }
}

struct ColorSwatches: View {
    @Binding var hue: Double

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 12) {
            ForEach(Palette.hues, id: \.self) { candidate in
                let selected = abs(candidate - hue) < 0.005
                Button {
                    withAnimation(.snappy) { hue = candidate }
                } label: {
                    Circle()
                        .fill(Color.bubble(candidate).gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            Circle()
                                .strokeBorder(.white, lineWidth: selected ? 3 : 0)
                                .padding(-5)
                        }
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(Palette.hues.firstIndex(of: candidate)! + 1)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Debug mode shows latency, link and echo details. Off by default.
enum DebugSettings {
    static let key = "debugMode"
}

/// Shown whenever no headphones are connected: they're required to be in a bubble.
struct HeadphonesNotice: View {
    /// In a bubble, your audio is paused until they're back.
    var paused = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: paused ? "pause.circle.fill" : "airpods")
                .font(.title3)
                .foregroundStyle(paused ? .yellow : .white)
            VStack(alignment: .leading, spacing: 2) {
                Text(paused ? "Your bubble is paused" : "Connect headphones to join a bubble")
                    .font(.subheadline.weight(.semibold))
                Text(paused
                     ? "Put your headphones back in to keep talking. You won't hear or send audio until you do."
                     : "Audio Bubble works with AirPods or other headphones, so only the people in your bubble hear it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// DEBUG-only launch arguments for looking at screens on a simulator without tapping through.
/// Release builds ignore them.
enum DebugLaunch {
    static func has(_ flag: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(flag)
        #else
        false
        #endif
    }

    static func value(after flag: String) -> String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
        #else
        nil
        #endif
    }
}

/// Your bubble, large, with a badge: tap to choose a Memoji or emoji.
struct EditableAvatar: View {
    let name: String
    let hue: Double
    @Binding var avatar: AvatarChoice
    var size: CGFloat = 96
    @State private var picking = DebugLaunch.has("-avatarPicker")

    var body: some View {
        Button { picking = true } label: {
            BubbleAvatar(name: name.isEmpty ? "?" : name, hue: hue, size: size, content: content)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: avatar == .initial ? "face.smiling" : "pencil")
                        .font(.system(size: size * 0.16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(size * 0.08)
                        .background(.white, in: Circle())
                        .offset(x: size * 0.02, y: size * 0.02)
                }
                .animation(.snappy, value: hue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your bubble")
        .accessibilityHint("Choose a Memoji or emoji")
        .sheet(isPresented: $picking) {
            AvatarPicker(name: name, hue: hue) { avatar = $0 }
                .presentationDetents([.height(340)])
                .presentationBackground(.clear)
        }
    }

    private var content: AvatarContent {
        switch avatar {
        case .initial: .initial
        case let .emoji(emoji): .emoji(emoji)
        case let .image(data): UIImage(data: data).map(AvatarContent.image) ?? .initial
        }
    }
}
