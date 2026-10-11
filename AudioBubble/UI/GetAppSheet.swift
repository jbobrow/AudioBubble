import SwiftUI
import CoreImage.CIFilterBuiltins

/// Where a friend without the app gets it: the website's /get page, which sends an iPhone on to
/// the App Store and tells anything else that Audio Bubble is for iPhone.
enum GetApp {
    static let url = URL(string: "https://audiobubble.jonbobrow.com/get/")!
    static let message = "Get Audio Bubble so we can hear each other, even in loud places."
}

/// A QR code a friend scans with their Camera to get Audio Bubble, shown at full brightness so it
/// reads in a dark room. Sending the link is the fallback.
struct GetAppSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                QRCode(string: GetApp.url.absoluteString)
                    .frame(width: 240, height: 240)
                    .overlay {
                        Image("AppIconImage")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(4)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .padding(22)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("QR code for getting Audio Bubble")
                VStack(spacing: 10) {
                    Text("Scan to get Audio Bubble".withoutWidows)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Have your friend point their iPhone camera here. Once they open Audio Bubble, they'll appear on your screen.".withoutWidows)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                Spacer(minLength: 0)
                ShareLink(item: GetApp.url, message: Text(GetApp.message)) {
                    Label("Send the link instead", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Background())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .modifier(FullBrightness())
    }
}

/// Black-on-white QR code for a string, drawn with crisp modules at any size. High error
/// correction leaves room for the app icon in the middle.
struct QRCode: View {
    let string: String

    var body: some View {
        if let image = Self.image(for: string) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        }
    }

    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// Turns the screen all the way up while showing, and back to where it was when it goes away or
/// the app leaves the foreground.
private struct FullBrightness: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var original: CGFloat?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: brighten)
            .onDisappear(perform: restore)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { brighten() } else { restore() }
            }
    }

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    private func brighten() {
        guard let screen, original == nil else { return }
        original = screen.brightness
        screen.brightness = 1
    }

    private func restore() {
        guard let screen, let original else { return }
        screen.brightness = original
        self.original = nil
    }
}
