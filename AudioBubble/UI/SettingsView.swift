import SwiftUI

/// Your name and color, debug mode, and the introduction again.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DebugSettings.key) private var debugMode = false
    @State private var name = ""
    @State private var hue = 0.58
    @State private var avatar = AvatarChoice.initial
    @State private var showsIntro = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                    ColorSwatches(hue: $hue)
                        .padding(.vertical, 6)
                } header: {
                    // Above the group rather than a clear row inside it, so the group keeps its
                    // rounded top.
                    EditableAvatar(name: name, hue: hue, avatar: $avatar)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                        .textCase(nil)
                } footer: {
                    Text("Tap your bubble to use a Memoji or emoji. People nearby see your name, color and bubble.")
                }

                Section {
                    Button("How Audio Bubble works") { showsIntro = true }
                }

                Section {
                    Toggle("Debug mode", isOn: $debugMode)
                } footer: {
                    Text("Shows latency, connection and echo details in your bubble.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Background())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = model.identity?.name ?? ""
            hue = model.identity?.hue ?? hue
            avatar = model.identity?.avatar ?? .initial
        }
        .onDisappear(perform: save)
        .fullScreenCover(isPresented: $showsIntro) {
            ZStack {
                Background()
                IntroPages(finishTitle: "Done") { showsIntro = false }
            }
        }
    }

    private func save() {
        model.updateIdentity(name: name, hue: hue, avatar: avatar)
    }
}
