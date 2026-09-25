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
            if let invite = model.incomingInvite {
                InviteBanner(invite: invite)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .alert("Connect your headphones", isPresented: Bindable(model).showsHeadphonesRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You need headphones to be in an audio bubble. Put in your AirPods or connect other headphones, then try again.")
        }
        .animation(.spring(duration: 0.5), value: model.identity == nil)
        .animation(.spring(duration: 0.45), value: model.incomingInvite)
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
