import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle().fill(Color.bubble(0.58).gradient).frame(width: 120, height: 120).offset(x: -30)
                    .opacity(0.8)
                Circle().fill(Color.bubble(0.93).gradient).frame(width: 90, height: 90).offset(x: 40, y: 20)
                    .opacity(0.8)
            }
            .blendMode(.screen)
            Text("Audio Bubble")
                .font(.largeTitle.weight(.semibold))
            Text("Talk with the people around you,\nclearly and instantly.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            TextField("Your name", text: $name)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .focused($focused)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .background(.white.opacity(0.08), in: .capsule)
                .padding(.horizontal, 40)
                .onSubmit(finish)
            Button(action: finish) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .padding(.horizontal, 40)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .onAppear { focused = true }
    }

    private func finish() {
        model.completeOnboarding(name: name)
    }
}
