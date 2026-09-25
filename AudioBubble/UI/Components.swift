import SwiftUI

/// A person's colored bubble with their initial.
struct BubbleAvatar: View {
    let name: String
    let hue: Double
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.bubble(hue).gradient)
                .shadow(color: Color.bubble(hue).opacity(0.5), radius: size * 0.14)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.6))
        }
        .frame(width: size, height: size)
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

/// Shown whenever no headphones are connected: the app is built around them.
struct HeadphonesNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "airpods")
                .font(.title3)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect your headphones")
                    .font(.subheadline.weight(.semibold))
                Text("Audio Bubble is made for AirPods or other headphones. From the speaker, people nearby hear your bubble too.")
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
