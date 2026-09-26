import SwiftUI

/// First launch: the introduction, then your name and color.
struct OnboardingView: View {
    @State private var showsIntro = !DebugLaunch.has("-nameStep")

    var body: some View {
        if showsIntro {
            IntroPages { withAnimation { showsIntro = false } }
                .transition(.opacity)
        } else {
            NameStep()
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

private struct NameStep: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var hue = Palette.random()
    @State private var avatar = AvatarChoice.initial
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            EditableAvatar(name: name, hue: hue, avatar: $avatar, size: 110)
            Text("What should people call you?".withoutWidows)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .background(.white.opacity(0.08), in: .capsule)
                .padding(.horizontal, 40)
                .onSubmit { focused = false }
            ColorSwatches(hue: $hue)
                .padding(.horizontal, 48)
            Spacer()
            Button(action: finish) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .foregroundStyle(.white)
        .onAppear { focused = true }
    }

    private func finish() {
        model.completeOnboarding(name: name, hue: hue, avatar: avatar)
    }
}
