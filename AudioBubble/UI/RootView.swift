import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            Background()
            if model.identity == nil {
                OnboardingView()
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
            if model.showsHeadphonesConfirmation {
                Label("Headphones connected", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.green.opacity(0.35), in: .capsule)
                    .background(.ultraThinMaterial, in: .capsule)
                    .environment(\.colorScheme, .dark)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
            if let invite = model.incomingInvite {
                InviteBanner(invite: invite)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .alert("Connect your headphones".withoutWidows, isPresented: Bindable(model).showsHeadphonesRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need headphones to be in an audio bubble. Put in your AirPods or connect other headphones, then try again.".withoutWidows)
        }
        .animation(.spring(duration: 0.5), value: model.identity == nil)
        .animation(.spring(duration: 0.45), value: model.incomingInvite)
        .animation(.spring(duration: 0.45), value: model.showsHeadphonesConfirmation)
    }
}

struct Background: View {
    var body: some View {
        LinearGradient(colors: [Color(white: 0.08), Color(red: 0.07, green: 0.08, blue: 0.14)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension Color {
    /// The soft color for a person's hue.
    static func bubble(_ hue: Double) -> Color {
        Color(hue: hue, saturation: 0.55, brightness: 0.95)
    }
}
